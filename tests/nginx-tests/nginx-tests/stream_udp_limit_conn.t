#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stream limit_conn module with datagrams.

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

my $t = Test::Nginx->new()->has(qw/stream stream_limit_conn udp/)->plan(9)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    limit_conn_zone  $binary_remote_addr  zone=zone:1m;
    limit_conn_zone  $binary_remote_addr  zone=zone2:1m;

    proxy_responses  1;
    proxy_timeout    1s;

    server {
        listen           127.0.0.1:%%PORT_8981_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8980_UDP%%;

        limit_conn       zone 1;
        proxy_responses  2;
    }

    server {
        listen           127.0.0.1:%%PORT_8982_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8980_UDP%%;
        limit_conn       zone2 1;
    }

    server {
        listen           127.0.0.1:%%PORT_8983_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8980_UDP%%;
        limit_conn       zone 5;
    }

    server {
        listen           127.0.0.1:%%PORT_8984_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8981_UDP%%;
        limit_conn       zone2 1;
    }

    server {
        listen           127.0.0.1:%%PORT_8985_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8981_UDP%%;
        limit_conn       zone 1;
    }
}

EOF

$t->run();
$t->run_daemon(\&udp_daemon, $t);
$t->waitforfile($t->testdir . '/' . port(8980));

###############################################################################

# same and other zones

my $s = dgram('127.0.0.1:' . port(8981));

is($s->io('1'), '1', 'passed');

# regardless of incomplete responses, new requests in the same
# socket will be treated as requests in existing session

is($s->io('1', read_timeout => 0.4), '1', 'passed new request');

is(dgram('127.0.0.1:' . port(8981))->io('1', read_timeout => 0.1), '',
	'rejected new session');
is(dgram('127.0.0.1:' . port(8982))->io('1'), '1', 'passed different zone');
is(dgram('127.0.0.1:' . port(8983))->io('1'), '1', 'passed same zone unlimited');

sleep 1;	# waiting for proxy_timeout to expire

is($s->io('2', read => 2), '12', 'new session after proxy_timeout');

is(dgram('127.0.0.1:' . port(8981))->io('2', read => 2), '12', 'passed 2');

# zones proxy chain

is(dgram('127.0.0.1:' . port(8984))->io('1'), '1', 'passed proxy');
is(dgram('127.0.0.1:' . port(8985))->io('1', read_timeout => 0.1), '',
	'rejected proxy');

###############################################################################

sub udp_daemon {
	my $t = shift;

	my $server = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => '127.0.0.1:' . port(8980),
		Reuse => 1,
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . port(8980);
	close $fh;

	while (1) {
		$server->recv(my $buffer, 65536);
		$server->send($_) for (1 .. $buffer);
	}
}

###############################################################################
