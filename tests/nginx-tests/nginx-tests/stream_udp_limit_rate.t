#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream proxy module with datagrams, limit rate directives.

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
    proxy_requests           2;
    proxy_responses          1;

    server {
        listen               127.0.0.1:%%PORT_8982_UDP%% udp;
        proxy_pass           127.0.0.1:%%PORT_8980_UDP%%;
    }

    server {
        listen               127.0.0.1:%%PORT_8983_UDP%% udp;
        proxy_pass           127.0.0.1:%%PORT_8980_UDP%%;
        proxy_download_rate  500;
    }

    server {
        listen               127.0.0.1:%%PORT_8984_UDP%% udp;
        proxy_pass           127.0.0.1:%%PORT_8980_UDP%%;
        proxy_upload_rate    500;
    }
}

EOF

$t->run_daemon(\&udp_daemon, port(8980), $t);
$t->try_run('no proxy_requests')->plan(8);

$t->waitforfile($t->testdir . '/' . port(8980));

###############################################################################

my $str = '1234567890' x 100;

# unlimited

my $s = dgram('127.0.0.1:' . port(8982));
is($s->io($str), $str, 'unlimited');
is($s->io($str), $str, 'unlimited 2');

# datagram doesn't get split

my $t1;

TODO: {
local $TODO = 'split datagram' unless $t->has_version('1.15.9');

$s = dgram('127.0.0.1:' . port(8983));
is($s->io($str), $str, 'download');
$t1 = time();
is($s->io($str), $str, 'download 2');

}

my $t2 = time();
cmp_ok($t1, '<', $t2, 'download 2 delayed');

TODO: {
todo_skip 'infinite event report', 3 unless $t->has_version('1.15.9');

$s = dgram('127.0.0.1:' . port(8984));
is($s->io($str), $str, 'upload');
is($s->io($str, read_timeout => 0.5), '', 'upload limited');

select undef, undef, undef, 1.6;
is($s->io($str), $str, 'upload passed');

}

###############################################################################

sub udp_daemon {
	my ($port, $t) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => "127.0.0.1:$port",
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . "/$port";
	close $fh;

	while (1) {
		$server->recv(my $buffer, 65536);
		log2i("$server $buffer");

		log2o("$server $buffer");
		$server->send($buffer);
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
