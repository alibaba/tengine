#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream module and balancers with datagrams.

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

my $t = Test::Nginx->new()->has(qw/stream udp/)->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    proxy_responses      1;
    proxy_timeout        1s;

    upstream u {
        server 127.0.0.1:%%PORT_8984_UDP%%;
        server 127.0.0.1:%%PORT_8985_UDP%%;
    }

    upstream u2 {
        server 127.0.0.1:%%PORT_8986_UDP%% down;
        server 127.0.0.1:%%PORT_8986_UDP%%;
        server 127.0.0.1:%%PORT_8984_UDP%%;
        server 127.0.0.1:%%PORT_8985_UDP%%;
    }

    upstream u3 {
        server 127.0.0.1:%%PORT_8984_UDP%%;
        server 127.0.0.1:%%PORT_8985_UDP%% weight=2;
    }

    upstream u4 {
        server 127.0.0.1:%%PORT_8986_UDP%% down;
        server 127.0.0.1:%%PORT_8984_UDP%% backup;
    }

    server {
        listen      127.0.0.1:%%PORT_8980_UDP%% udp;
        proxy_pass  u;
    }

    server {
        listen      127.0.0.1:%%PORT_8981_UDP%% udp;
        proxy_pass  u2;
    }

    server {
        listen      127.0.0.1:%%PORT_8982_UDP%% udp;
        proxy_pass  u3;
    }

    server {
        listen      127.0.0.1:%%PORT_8983_UDP%% udp;
        proxy_pass  u4;
    }
}

EOF

$t->run_daemon(\&udp_daemon, port(8984), $t);
$t->run_daemon(\&udp_daemon, port(8985), $t);
$t->run();

$t->waitforfile($t->testdir . '/' . port(8984));
$t->waitforfile($t->testdir . '/' . port(8985));

###############################################################################

my @ports = my ($port4, $port5) = (port(8984), port(8985));

is(many(10, port(8980)), "$port4: 5, $port5: 5", 'balanced');

is(dgram('127.0.0.1:' . port(8981))->io('.', read_timeout => 0.5), '',
	'no next upstream for dgram');

is(many(10, port(8981)), "$port4: 5, $port5: 5", 'failures');

is(many(9, port(8982)), "$port4: 3, $port5: 6", 'weight');
is(many(10, port(8983)), "$port4: 10", 'backup');

###############################################################################

sub many {
	my ($count, $port) = @_;
	my (%ports);

	for (1 .. $count) {
		if (dgram("127.0.0.1:$port")->io('.') =~ /(\d+)/) {
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
		$buffer = $server->sockport();
		$server->send($buffer);
	}
}

###############################################################################
