#!/usr/bin/perl

# Copyright (C) 2010-2015 Alibaba Group Holding Limited

# Tests for hostile response framing under keepalive HTTP health checks.
#
# With check_keepalive_requests > 1 the check parses the response headers to
# learn the body length, so that it can drain the body and reuse the
# connection. Every byte of that comes from the checked peer:
#
#  - a NUL right after "Transfer-Encoding: chunked" pushed the token match index
#    past the end of the "chunked" table, which was then read out of bounds;
#    "chunkedX" and "chunked, gzip" were taken for chunked as well;
#  - a chunk size or a Content-Length too large for off_t wrapped negative,
#    and a negative length moved the read pointer before the buffer;
#  - a Content-Length that is not a plain decimal number -- a leading minus
#    sign in particular -- was silently reduced to its digits, so "-1" was
#    drained as one byte and the connection was reused with body bytes still
#    on it, which the next check then read as its status line.
#
# Each peer below sends one such response with a 200 status. The verdict comes
# from the status line, so every peer must be up; the body length is unknown,
# so the check must close the connection instead of reusing it. Each backend
# records the most requests it saw on one connection, which tells the two
# apart. The well-formed peers show that reuse is still detected. A crash or a
# sanitizer report fails the "no alerts" / "no sanitizer errors" checks the
# test framework runs at the end.

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

my $t = Test::Nginx->new()->has(qw/http upstream_check/)->plan(18)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream te_nul {
        server 127.0.0.1:%%PORT_8081%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream te_glued {
        server 127.0.0.1:%%PORT_8082%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream te_not_final {
        server 127.0.0.1:%%PORT_8083%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream chunk_overflow {
        server 127.0.0.1:%%PORT_8084%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream cl_overflow {
        server 127.0.0.1:%%PORT_8085%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream good_chunked {
        server 127.0.0.1:%%PORT_8086%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream good_length {
        server 127.0.0.1:%%PORT_8087%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream cl_negative {
        server 127.0.0.1:%%PORT_8088%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    upstream cl_negative_large {
        server 127.0.0.1:%%PORT_8089%%;
        check interval=300 rise=1 fall=1 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

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

my $testdir = $t->testdir();

my $head = "HTTP/1.1 200 OK\r\n";

my %peers = (
	# a NUL glued to the token: the out-of-bounds read of the "chunked" table
	te_nul => [ port(8081),
		$head . "Transfer-Encoding: chunked\0X\r\n\r\n0\r\n\r\n" ],

	te_glued => [ port(8082),
		$head . "Transfer-Encoding: chunkedX\r\n\r\n0\r\n\r\n" ],

	# chunked is not the final coding, so the body is delimited by close
	te_not_final => [ port(8083),
		$head . "Transfer-Encoding: chunked, gzip\r\n\r\n0\r\n\r\n" ],

	# 2^64 - 2^44: wraps to a negative chunk size of -2^44
	chunk_overflow => [ port(8084),
		$head . "Transfer-Encoding: chunked\r\n\r\n"
		. "fffff00000000000\r\nAB\r\n0\r\n\r\n" ],

	# 2^64 - 1: wraps to a Content-Length of -1
	cl_overflow => [ port(8085),
		$head . "Content-Length: 18446744073709551615\r\n\r\n" ],

	good_chunked => [ port(8086),
		$head . "Transfer-Encoding: gzip, chunked\r\n\r\n"
		. "5\r\nhello\r\n0\r\n\r\n" ],

	good_length => [ port(8087),
		$head . "Content-Length: 5\r\n\r\nhello" ],

	# a leading minus sign is not a digit: the length is unknown, so the
	# connection must not be reused with the body still on it
	cl_negative => [ port(8088),
		$head . "Content-Length: -1\r\n\r\nhello" ],

	cl_negative_large => [ port(8089),
		$head . "Content-Length: -1000000\r\n\r\nhello" ],
);

$t->run_daemon(\&http_daemon, @{$peers{$_}}) for sort keys %peers;
$t->run();

$t->waitforsocket('127.0.0.1:' . $peers{$_}[0]) for sort keys %peers;

###############################################################################

# The first check of a peer fires after a random delay of up to one second;
# allow for that plus several intervals, enough for a reused connection to
# carry more than one request.
select undef, undef, undef, 4;

my %status = get_status();

for my $name (qw/te_nul te_glued te_not_final chunk_overflow cl_overflow
	cl_negative cl_negative_large/)
{
	is($status{$name}, 'up', "$name: peer up");
	is(max_requests($peers{$name}[0]), 1, "$name: connection not reused");
}

for my $name (qw/good_chunked good_length/) {
	is($status{$name}, 'up', "$name: peer up");
	cmp_ok(max_requests($peers{$name}[0]), '>', 1,
		"$name: connection reused");
}

###############################################################################

# CSV columns: index,upstream,name,status,rise,fall,type,port,protocol
sub get_status {
	my %status;

	my $r = http_get('/status?format=csv');
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

###############################################################################

# Answers every request on a connection with the same canned response, and
# keeps in requests_<port> the most requests seen on any one connection.
sub http_daemon {
	my ($port, $response) = @_;

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

				$client->syswrite($response);
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
