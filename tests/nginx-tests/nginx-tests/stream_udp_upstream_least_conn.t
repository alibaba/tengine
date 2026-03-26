#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream least_conn balancer module with datagrams.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ dgram /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_upstream_least_conn udp/)
	->plan(2)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    proxy_responses      1;
    proxy_timeout        1s;

    upstream u {
        least_conn;
        server 127.0.0.1:%%PORT_8981_UDP%%;
        server 127.0.0.1:%%PORT_8982_UDP%%;
    }

    server {
        listen      127.0.0.1:%%PORT_8980_UDP%% udp;
        proxy_pass  u;
    }
}

EOF

$t->run_daemon(\&udp_daemon, port(8981), $t);
$t->run_daemon(\&udp_daemon, port(8982), $t);
$t->run();

$t->waitforfile($t->testdir . '/' . port(8981));
$t->waitforfile($t->testdir . '/' . port(8982));

###############################################################################

my @ports = my ($port1, $port2) = (port(8981), port(8982));

is(many(10), "$port1: 5, $port2: 5", 'balanced');

my @sockets;
for (1 .. 2) {
	my $s = dgram('127.0.0.1:' . port(8980));
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
		if (dgram('127.0.0.1:' . port(8980))->io('.') =~ /(\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################

sub udp_daemon {
	my ($port, $t) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => '127.0.0.1:' . $port,
		Reuse => 1,
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
	close $fh;

	while (1) {
		$server->recv(my $buffer, 65536);

		my $port = $server->sockport();

		if ($buffer =~ /w/ && $port == port(8981)) {
			select undef, undef, undef, 2.5;
		}

		$buffer = $port;

		$server->send($buffer);
	}
}

###############################################################################
