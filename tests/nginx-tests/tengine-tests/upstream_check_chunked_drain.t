#!/usr/bin/perl

# Copyright (C) 2010-2015 Alibaba Group Holding Limited

# Tests that a hostile chunked response body can never wedge the worker that
# runs the health checks.
#
# ngx_http_upstream_check_chunked_drain() walks the body with a state machine
# that advances its read pointer by hand, so an iteration that neither consumes
# a byte nor changes the state spins over the same buffer forever: the worker
# burns a core, answers no request and runs no further check (CWE-835). The
# state is a caller-owned integer carried across reads, and a value outside the
# state machine used to match no case at all -- exactly such an iteration.
#
# Every peer below answers a 200 and then sends chunked framing the drain has
# to reject: a size line whose CR is not followed by LF, chunk-data that is not
# followed by CRLF, and the 132 bytes of filler from the report that triggered
# this, which hold neither a CR nor an LF at all. Two of them send the body in
# two writes far enough apart that the tail reaches the discard handler on the
# idle connection instead of the parser inline with the headers -- that is the
# path that runs between two checks. The two well-formed peers are the control:
# they show that a drained connection is still reused, so "not reused" for the
# others is the drain's decision and not a check that never ran.
#
# Checks and the status page share one worker (worker_processes 1), so a
# spinning drain shows up as a /status request that is never answered: http_get
# gives up after eight seconds and the assertions below fail on the empty
# answer. A crash or a sanitizer report fails the "no alerts" and "no sanitizer
# errors" checks the test framework runs at the end.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Socket::INET;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

# how long a peer waits between the two writes of a split body: long enough
# that the check is over and the discard handler owns the connection, short
# enough that the tail still arrives before the next check
my $split_delay = 0.4;

my $head = "HTTP/1.1 200 OK\r\n";
my $chunked = "Transfer-Encoding: chunked\r\n\r\n";

# name => [ port, response part, ... ]
my %peers = (
	# the size line ends in a bare CR: the drain refuses it on the spot
	size_no_lf => [ 8081, $head . $chunked . "5\rX\r\n" ],

	# chunk-data followed by something that is not CRLF
	data_no_crlf => [ 8082,
		$head . $chunked . "5\r\nhelloXY\r\n0\r\n\r\n" ],

	# the sample quoted in the report: filler bytes with a few odd ones, no
	# CR and no LF anywhere, so the body is one chunk extension that never
	# ends and the drain has to keep asking for more instead of spinning
	reported_filler => [ 8083, $head . $chunked . reported_filler() ],

	# the tail arrives after the check, so the discard handler drains it on
	# the idle connection and has to reject it there
	split_bad_tail => [ 8084, $head . $chunked . "5\r\nhel", "loXY\r\n" ],

	good_chunked => [ 8085,
		$head . $chunked . "5\r\nhello\r\n0\r\n\r\n" ],

	# the same body as good_chunked, but split so that the discard handler
	# is the one that finishes the drain before the connection is reused
	split_good => [ 8086, $head . $chunked . "5\r\nhel",
		"lo\r\n0\r\n\r\n" ],
);

my $upstreams = '';

for my $name (sort keys %peers) {
	$upstreams .= <<EOF;
    upstream $name {
        server 127.0.0.1:%%PORT_$peers{$name}[0]%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keep-alive\\r\\n\\r\\n";
        check_http_expect_alive http_2xx;
    }

EOF
}

my $conf = <<'EOF';

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

%%UPSTREAMS%%
    server {
        listen      127.0.0.1:%%PORT_8080%%;
        server_name localhost;

        location /status {
            check_status;
            access_log off;
        }
    }
}

EOF

$conf =~ s/%%UPSTREAMS%%/$upstreams/;

my $t = Test::Nginx->new()->has(qw/http upstream_check/)->plan(15)
	->write_file_expand('nginx.conf', $conf);

my $testdir = $t->testdir();

$t->run_daemon(\&http_daemon, port($peers{$_}[0]), @{$peers{$_}}[1 .. $#{$peers{$_}}])
	for sort keys %peers;
$t->run();

$t->waitforsocket('127.0.0.1:' . port($peers{$_}[0])) for sort keys %peers;

###############################################################################

# The first check of a peer fires after a random delay of up to one second;
# allow for that plus several intervals, enough for a reused connection to
# carry more than one request.
select undef, undef, undef, 4;

my %status = get_status();

is(scalar keys %status, scalar keys %peers,
	'status page answered while hostile bodies were being drained');

for my $name (qw/size_no_lf data_no_crlf reported_filler split_bad_tail/) {
	is($status{$name}, 'up', "$name: peer up");
	is(max_requests(port($peers{$name}[0])), 1,
		"$name: connection not reused");
}

for my $name (qw/good_chunked split_good/) {
	is($status{$name}, 'up', "$name: peer up");
	cmp_ok(max_requests(port($peers{$name}[0])), '>', 1,
		"$name: connection reused");
}

# The tail of the split body is what the discard handler rejects, and it says
# so: proof that the drain ran to a verdict there rather than never returning.
like($t->read_file('error.log'),
	qr/check peer sent a malformed response body/,
	'discard handler reported the malformed body');

# A drain that spins does so forever, so the worker has to still be running
# checks -- and answering -- well after the bodies above were served.
select undef, undef, undef, 2;

my %later = get_status();

is(scalar keys %later, scalar keys %peers,
	'status page still answered after further checks');

###############################################################################

# CSV columns: index,upstream,name,status,rise,fall,type,port,protocol
sub get_status {
	my %status;

	my $r = http_get('/status?format=csv');
	return %status unless defined $r;

	$r =~ s/.*?\x0d\x0a\x0d\x0a//s;

	for my $line (split /\n/, $r) {
		my @f = split /,/, $line;
		next unless @f >= 9;
		$status{$f[1]} = $f[3];
	}

	return %status;
}

sub max_requests {
	my ($port) = @_;
	my $file = "$testdir/requests_$port";

	open my $fh, '<', $file or die "Can't open $file: $!\n";
	my $n = <$fh>;
	close $fh;

	return defined $n ? $n + 0 : 0;
}

# The bytes the report quotes: 0x13 filler with the handful of odd bytes its
# hex dump shows.
sub reported_filler {
	my $b = chr(0x13) x 132;

	substr($b, 5, 1) = chr(0xfd);
	substr($b, 7, 4) = chr(0x00) x 3 . chr(0xa0);

	return $b;
}

###############################################################################

# Answers every request on a connection with the same canned response, written
# one part at a time with $split_delay between the parts, and keeps in
# requests_<port> the most requests seen on any one connection.
sub http_daemon {
	my ($port, @parts) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	my $max = 0;
	record_requests($port, $max);

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my ($buf, $requests) = ('', 0);

		while ($client->sysread($buf, 4096, length $buf)) {
			while ($buf =~ s/^.*?\x0d\x0a\x0d\x0a//s) {
				$requests++;

				if ($requests > $max) {
					$max = $requests;
					record_requests($port, $max);
				}

				for my $i (0 .. $#parts) {
					select undef, undef, undef, $split_delay
						if $i;
					last unless
						defined $client->syswrite($parts[$i]);
				}
			}
		}

		$client->close;
	}
}

sub record_requests {
	my ($port, $n) = @_;

	my $file = "$testdir/requests_$port";

	open my $fh, '>', "$file.tmp" or die "Can't create $file.tmp: $!\n";
	print $fh $n;
	close $fh;

	rename "$file.tmp", $file or die "Can't rename $file.tmp: $!\n";
}

###############################################################################
