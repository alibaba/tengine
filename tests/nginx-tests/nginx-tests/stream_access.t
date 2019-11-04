#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stream access module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_access unix/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    server {
        listen       127.0.0.1:8082;
        proxy_pass   [::1]:%%PORT_8080%%;
    }

    server {
        listen       127.0.0.1:8083;
        proxy_pass   unix:%%TESTDIR%%/unix.sock.0;
    }

    server {
        listen       127.0.0.1:8085;
        proxy_pass   [::1]:%%PORT_8081%%;
    }

    server {
        listen       127.0.0.1:8086;
        proxy_pass   unix:%%TESTDIR%%/unix.sock.1;
    }

    server {
        listen       127.0.0.1:8088;
        proxy_pass   [::1]:%%PORT_8082%%;
    }

    server {
        listen       127.0.0.1:8089;
        proxy_pass   unix:%%TESTDIR%%/unix.sock.2;
    }

    server {
        listen       127.0.0.1:8091;
        proxy_pass   [::1]:%%PORT_8083%%;
    }

    server {
        listen       127.0.0.1:8092;
        proxy_pass   unix:%%TESTDIR%%/unix.sock.3;
    }

    server {
        listen       127.0.0.1:8094;
        proxy_pass   [::1]:%%PORT_8084%%;
    }

    server {
        listen       127.0.0.1:8095;
        proxy_pass   unix:%%TESTDIR%%/unix.sock.4;
    }

    server {
        listen       127.0.0.1:8097;
        proxy_pass   [::1]:%%PORT_8085%%;
    }

    server {
        listen       127.0.0.1:8098;
        proxy_pass   unix:%%TESTDIR%%/unix.sock.5;
    }

    server {
        listen       127.0.0.1:8081;
        listen       [::1]:%%PORT_8080%%;
        listen       unix:%%TESTDIR%%/unix.sock.0;
        proxy_pass   127.0.0.1:8080;
        allow        all;
    }

    server {
        listen       127.0.0.1:8084;
        listen       [::1]:%%PORT_8081%%;
        listen       unix:%%TESTDIR%%/unix.sock.1;
        proxy_pass   127.0.0.1:8080;
        deny         all;
    }

    server {
        listen       127.0.0.1:8087;
        listen       [::1]:%%PORT_8082%%;
        listen       unix:%%TESTDIR%%/unix.sock.2;
        proxy_pass   127.0.0.1:8080;
        allow        unix:;
    }

    server {
        listen       127.0.0.1:8090;
        listen       [::1]:%%PORT_8083%%;
        listen       unix:%%TESTDIR%%/unix.sock.3;
        proxy_pass   127.0.0.1:8080;
        deny         127.0.0.1;
    }

    server {
        listen       127.0.0.1:8093;
        listen       [::1]:%%PORT_8084%%;
        listen       unix:%%TESTDIR%%/unix.sock.4;
        proxy_pass   127.0.0.1:8080;
        deny         ::1;
    }

    server {
        listen       127.0.0.1:8096;
        listen       [::1]:%%PORT_8085%%;
        listen       unix:%%TESTDIR%%/unix.sock.5;
        proxy_pass   127.0.0.1:8080;
        deny         unix:;
    }
}

EOF

$t->try_run('no inet6 support')->plan(18);
$t->run_daemon(\&stream_daemon);
$t->waitforsocket('127.0.0.1:' . port(8080));

###############################################################################

my $str = 'SEE-THIS';

# allow all

is(stream('127.0.0.1:' . port(8081))->io($str), $str, 'inet allow all');
is(stream('127.0.0.1:' . port(8082))->io($str), $str, 'inet6 allow all');
is(stream('127.0.0.1:' . port(8083))->io($str), $str, 'unix allow all');

# deny all

is(stream('127.0.0.1:' . port(8084))->io($str), '', 'inet deny all');
is(stream('127.0.0.1:' . port(8085))->io($str), '', 'inet6 deny all');
is(stream('127.0.0.1:' . port(8086))->io($str), '', 'unix deny all');

# allow unix

is(stream('127.0.0.1:' . port(8087))->io($str), $str, 'inet allow unix');
is(stream('127.0.0.1:' . port(8088))->io($str), $str, 'inet6 allow unix');
is(stream('127.0.0.1:' . port(8089))->io($str), $str, 'unix allow unix');

# deny inet

is(stream('127.0.0.1:' . port(8090))->io($str), '', 'inet deny inet');
is(stream('127.0.0.1:' . port(8091))->io($str), $str, 'inet6 deny inet');
is(stream('127.0.0.1:' . port(8092))->io($str), $str, 'unix deny inet');

# deny inet6

is(stream('127.0.0.1:' . port(8093))->io($str), $str, 'inet deny inet6');
is(stream('127.0.0.1:' . port(8094))->io($str), '', 'inet6 deny inet6');
is(stream('127.0.0.1:' . port(8095))->io($str), $str, 'unix deny inet6');

# deny unix

is(stream('127.0.0.1:' . port(8096))->io($str), $str, 'inet deny unix');
is(stream('127.0.0.1:' . port(8097))->io($str), $str, 'inet6 deny unix');
is(stream('127.0.0.1:' . port(8098))->io($str), '', 'unix deny unix');

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8080),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		log2c("(new connection $client)");

		$client->sysread(my $buffer, 65536) or next;

		log2i("$client $buffer");

		log2o("$client $buffer");

		$client->syswrite($buffer);

		close $client;
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
