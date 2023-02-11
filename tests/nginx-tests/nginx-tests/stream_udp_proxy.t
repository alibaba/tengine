#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for stream proxy module with datagrams.

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

my $t = Test::Nginx->new()->has(qw/stream udp/)->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    proxy_timeout        1s;

    server {
        listen           127.0.0.1:%%PORT_8980_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8981_UDP%%;

        proxy_responses  0;
    }

    server {
        listen           127.0.0.1:%%PORT_8982_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8981_UDP%%;

        proxy_responses  2;
    }

    server {
        listen           127.0.0.1:%%PORT_8983_UDP%% udp;
        proxy_pass       127.0.0.1:%%PORT_8981_UDP%%;
    }
}

EOF


$t->run_daemon(\&udp_daemon, port(8981), $t);
$t->run();
$t->waitforfile($t->testdir . '/' . port(8981));

###############################################################################

my $s = dgram('127.0.0.1:' . port(8980));
is($s->io('1', read => 1, read_timeout => 0.5), '', 'proxy responses 0');

$s = dgram('127.0.0.1:' . port(8982));
is($s->io('1'), '1', 'proxy responses 1');
$s = dgram('127.0.0.1:' . port(8982));
is($s->io('2', read => 2), '12', 'proxy responses 2');

$s = dgram('127.0.0.1:' . port(8983));
is($s->io('3', read => 3), '123', 'proxy responses default');

# zero-length payload

$s = dgram('127.0.0.1:' . port(8982));
$s->write('');
is($s->read(), 'zero', 'upstream read zero bytes');
is($s->read(), '', 'upstream sent zero bytes');

$s->write('');
is($s->read(), 'zero', 'upstream read zero bytes again');
is($s->read(), '', 'upstream sent zero bytes again');

###############################################################################

sub udp_daemon {
	my ($port, $t) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => '127.0.0.1:' . port(8981),
		Reuse => 1,
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . port(8981);
	close $fh;

	while (1) {
		$server->recv(my $buffer, 65536);

		if (length($buffer) > 0) {
			$server->send($_) for (1 .. $buffer);

		} else {
			$server->send('zero');
			select undef, undef, undef, 0.2;
			$server->send('');
		}
	}
}

###############################################################################
