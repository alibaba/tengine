#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream proxy module, the proxy_requests directive.

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

my $t = Test::Nginx->new()->has(qw/stream udp/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    proxy_timeout  2100ms;

    log_format status $status;

    server {
        listen           127.0.0.1:%%PORT_8980_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8990_UDP%%;

        proxy_requests   0;
    }

    server {
        listen           127.0.0.1:%%PORT_8981_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8990_UDP%%;

        proxy_requests   1;
    }

    server {
        listen           127.0.0.1:%%PORT_8982_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8990_UDP%%;

        proxy_requests   2;
    }

    server {
        listen           127.0.0.1:%%PORT_8983_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8990_UDP%%;
    }

    server {
        listen           127.0.0.1:%%PORT_8984_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8991_UDP%%;

        proxy_requests   2;
        access_log       %%TESTDIR%%/s.log status;
    }

    server {
        listen           127.0.0.1:%%PORT_8985_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8990_UDP%%;

        proxy_requests   2;
        proxy_responses  2;
        access_log       %%TESTDIR%%/s2.log status;
    }
}

EOF


$t->run_daemon(\&udp_daemon, $t, port(8990));
$t->run_daemon(\&udp_daemon, $t, port(8991));
$t->try_run('no proxy_requests')->plan(26);

$t->waitforfile($t->testdir . '/' . port(8990));
$t->waitforfile($t->testdir . '/' . port(8991));

###############################################################################

# proxy_requests 0, binding is not dropped across streams

my $s = dgram('127.0.0.1:' . port(8980));
my $n = $s->io('1', read => 1);
ok($n, 'requests 0 create');
is($s->read(), '1', 'requests 0 create - response');

is($s->io('1', read => 1), $n, 'requests 0 second - binding saved');
is($s->read(), '1', 'requests 0 second - response');

is($s->io('1', read => 1), $n, 'requests 0 follow - binding saved');
is($s->read(), '1', 'requests 0 follow - response');

# proxy_requests 1, binding is dropped on every next stream

$s = dgram('127.0.0.1:' . port(8981));
$n = $s->io('1', read => 1);
ok($n, 'requests 1 create');
is($s->read(), '1', 'requests 1 create - response');

isnt($s->io('1', read => 1), $n, 'requests 1 second - binding lost');
is($s->read(), '1', 'requests 1 second - response');

# proxy_requests 2, binding is dropped on every second stream

$s = dgram('127.0.0.1:' . port(8982));
$n = $s->io('1', read => 1);
ok($n, 'requests 2 create');
is($s->read(), '1', 'requests 2 create - response');

is($s->io('1', read => 1), $n, 'requests 2 second - binding saved');
is($s->read(), '1', 'requests 2 second - response');

isnt($s->io('1', read => 1), $n, 'requests 2 follow - binding lost');
is($s->read(), '1', 'requests 2 follow - response');

# proxy_requests unset, binding is not dropped across streams

$s = dgram('127.0.0.1:' . port(8983));
$n = $s->io('1', read => 1);
ok($n, 'requests unset create');
is($s->read(), '1', 'requests unset create - response');

is($s->io('1', read => 1), $n, 'requests unset second - binding saved');
is($s->read(), '1', 'requests unset second - response');

is($s->io('1', read => 1), $n, 'requests unset follow - binding saved');
is($s->read(), '1', 'requests unset follow - response');

# proxy_requests 2, with slow backend
# client sends 5 packets, each responded with 3 packets
# expects all packets proxied from backend, the last (uneven) session succeed

$s = dgram('127.0.0.1:' . port(8984));
$s->write('2') for 1 .. 5;
my $b = join ' ', map { $s->read() } (1 .. 15);
like($b, qr/^(\d+ 1 2) \1 (?!\1)(\d+ 1 2) \2 (?!\2)\d+ 1 2$/, 'slow backend');

# proxy_requests 2, proxy_responses 2
# client sends 5 packets, each responded with 2 packets
# expects all packets proxied from backend, the last (uneven) session succeed

$s = dgram('127.0.0.1:' . port(8985));
$s->write('1') for 1 .. 5;
$b = join ' ', map { $s->read() } (1 .. 10);

SKIP: {
skip 'session could early terminate', 1 unless $ENV{TEST_NGINX_UNSAFE};

like($b, qr/^(\d+ 1) \1 (?!\1)(\d+ 1) \2 (?!\2)\d+ 1$/, 'requests - responses');

}

$t->stop();

is($t->read_file('s.log'), <<EOF, 'uneven session status - slow backend');
200
200
200
EOF

is($t->read_file('s2.log'), <<EOF, 'uneven session status - responses');
200
200
200
EOF

###############################################################################

sub udp_daemon {
	my ($t, $port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => "127.0.0.1:$port",
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . "/$port";
	close $fh;

	my $slp = 1 if $port == port(8991);

	while (1) {
		$server->recv(my $buffer, 65536);
		sleep 1, $slp = 0 if $slp;

		$server->send($server->peerport());
		$server->send($_) for (1 .. $buffer);
	}
}

###############################################################################
