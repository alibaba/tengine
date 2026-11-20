#!/usr/bin/perl

# Copyright (C) 2010-2015 Alibaba Group Holding Limited

# Tests for the protocol-independent "send" and "udp" health check types.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;
use IO::Socket::INET;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream http upstream_check/)->plan(7)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen      127.0.0.1:%%PORT_8080%%;
        server_name localhost;

        location /status {
            check_status;
            access_log off;
        }
    }
}

stream {
    %%TEST_GLOBALS_STREAM%%

    # 8081 answers "+PONG", 8082 answers something else
    upstream send_expected {
        server 127.0.0.1:%%PORT_8081%%;

        check interval=300 rise=1 fall=1 timeout=250 type=send;
        check_send            "PING\r\n";
        check_expect_response "+PONG";
    }

    upstream send_unexpected {
        server 127.0.0.1:%%PORT_8082%%;

        check interval=300 rise=1 fall=1 timeout=250 type=send;
        check_send            "PING\r\n";
        check_expect_response "+PONG";
    }

    # the same probe spelled out in \xHH escapes: "PING\r\n" / "+PONG"
    upstream send_escaped {
        server 127.0.0.1:%%PORT_8081%%;

        check interval=300 rise=1 fall=1 timeout=250 type=send;
        check_send            "\x50\x49\x4e\x47\r\n";
        check_expect_response "\x2bPONG";
    }

    # no expectation: any reply at all means alive, so the peer answering
    # the "wrong" bytes is up here
    upstream send_any_reply {
        server 127.0.0.1:%%PORT_8082%%;

        check interval=300 rise=1 fall=1 timeout=250 type=send;
        check_send "PING\r\n";
    }

    # 8083 answers over UDP, 8084 stays silent, 8085 is not bound at all
    upstream udp_answering {
        server 127.0.0.1:%%PORT_8083_UDP%%;

        check interval=400 rise=1 fall=1 timeout=300 type=udp;
        check_send            "PING";
        check_expect_response "PONG";
    }

    upstream udp_silent {
        server 127.0.0.1:%%PORT_8084_UDP%%;

        check interval=400 rise=1 fall=1 timeout=300 type=udp;
        check_send            "PING";
        check_expect_response "PONG";
    }

    upstream udp_closed {
        server 127.0.0.1:%%PORT_8085_UDP%%;

        check interval=400 rise=1 fall=1 timeout=300 type=udp;
        check_send            "PING";
        check_expect_response "PONG";
    }
}

EOF

$t->run_daemon(\&tcp_daemon, port(8081), "+PONG\r\n");
$t->run_daemon(\&tcp_daemon, port(8082), "-ERR unexpected\r\n");
$t->run_daemon(\&udp_daemon, port(8083, udp => 1), "PONG");
$t->run_daemon(\&udp_daemon, port(8084, udp => 1), undef);
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

# Peers start out down and the first probe fires after a random delay of up to
# max(interval, 1s), so wait for the first verdict.
select undef, undef, undef, 3;

my $status = get_status();

like($status, qr!^\d+,send_expected,\S+,up,!m,
	'"send" is up when the reply contains the expected bytes');
like($status, qr!^\d+,send_unexpected,\S+,down,!m,
	'"send" is down when the reply does not contain them');
like($status, qr!^\d+,send_escaped,\S+,up,!m,
	'\xHH escapes in check_send and check_expect_response');
like($status, qr!^\d+,send_any_reply,\S+,up,!m,
	'without check_expect_response any reply means alive');

like($status, qr!^\d+,udp_answering,\S+,up,\d+,\d+,udp,!m,
	'"udp" is up when a datagram comes back');
like($status, qr!^\d+,udp_silent,\S+,down,\d+,\d+,udp,!m,
	'"udp" is down when the peer stays silent');
like($status, qr!^\d+,udp_closed,\S+,down,\d+,\d+,udp,!m,
	'"udp" is down when nothing is bound to the port');

###############################################################################

sub get_status {
	my $r = http_get('/status?format=csv');
	$r =~ s/.*?\x0d\x0a\x0d\x0a//s;
	return $r;
}

###############################################################################

sub tcp_daemon {
	my ($port, $reply) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		$client->sysread(my $buffer, 65536);
		$client->syswrite($reply) if defined $reply;
		$client->close;
	}
}

sub udp_daemon {
	my ($port, $reply) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (1) {
		$server->recv(my $buffer, 65536);
		$server->send($reply) if defined $reply;
	}
}

###############################################################################
