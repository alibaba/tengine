#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream proxy module, proxy_next_upstream directive and friends.

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

my $t = Test::Nginx->new()->has(qw/stream/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    upstream u {
        server 127.0.0.1:8083 max_fails=0;
        server 127.0.0.1:8084 max_fails=0;
        server 127.0.0.1:8085 backup;
    }

    upstream u2 {
        server 127.0.0.1:8083;
        server 127.0.0.1:8085 backup;
    }

    upstream u3 {
        server 127.0.0.1:8083;
        server 127.0.0.1:8085 down;
    }

    proxy_connect_timeout 2;

    server {
        listen      127.0.0.1:8080;
        proxy_pass  u;
        proxy_next_upstream off;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  u2;
        proxy_next_upstream on;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  u;
        proxy_next_upstream on;
        proxy_next_upstream_tries 2;
    }

    log_format test "$upstream_addr";

    server {
        listen      127.0.0.1:8086;
        proxy_pass  u3;
        proxy_next_upstream on;
        access_log  %%TESTDIR%%/test.log test;
    }
}

EOF

$t->run_daemon(\&stream_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8085));

###############################################################################

is(stream('127.0.0.1:' . port(8080))->io('.'), '', 'next off');
is(stream('127.0.0.1:' . port(8081))->io('.'), 'SEE-THIS', 'next on');

# make sure backup is not tried

is(stream('127.0.0.1:' . port(8082))->io('.'), '', 'next tries');

# make sure backend marked as down doesn't count towards "no live upstreams"

is(stream('127.0.0.1:' . port(8086))->io('.'), '', 'next down');

$t->stop();

is($t->read_file('test.log'), '127.0.0.1:' . port(8083) . "\n",
	'next down log');

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8085),
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

		$buffer = 'SEE-THIS';

		log2o("$client $buffer");

		$client->syswrite($buffer);

	} continue {
		close $client;
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
