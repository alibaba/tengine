#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream least_conn balancer module.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_upstream_least_conn/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    upstream u {
        least_conn;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    server {
        listen      127.0.0.1:8080;
        proxy_pass  u;
    }
}

EOF

$t->run_daemon(\&stream_daemon, port(8081));
$t->run_daemon(\&stream_daemon, port(8082));
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

my @ports = my ($port1, $port2) = (port(8081), port(8082));

is(many(10), "$port1: 5, $port2: 5", 'balanced');

my @sockets;
for (1 .. 2) {
	my $s = stream('127.0.0.1:' . port(8080));
	$s->write('w');
	push @sockets, $s;
}

select undef, undef, undef, 0.2;

is(many(10), "$port2: 10", 'least_conn');

###############################################################################

sub many {
	my ($count) = @_;
	my (%ports);

	for (1 .. $count) {
		if (stream('127.0.0.1:' . port(8080))->io('.') =~ /(\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################

sub stream_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($server);

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($server == $fh) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif (stream_handle_client($fh)) {
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

sub stream_handle_client {
	my ($client) = @_;

	log2c("(new connection $client)");

	$client->sysread(my $buffer, 65536) or return 1;

	log2i("$client $buffer");

	my $port = $client->sockport();

	if ($buffer =~ /w/ && $port == port(8081)) {
		Test::Nginx::log_core('||', "$port: sleep(2.5)");
		select undef, undef, undef, 2.5;
	}

	$buffer = $port;

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return 1;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
