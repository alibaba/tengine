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

my $t = Test::Nginx->new()->has(qw/stream/)->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    upstream u {
        server 127.0.0.1:8087 max_fails=0;
        server 127.0.0.1:8088 max_fails=0;
        server 127.0.0.1:8089 backup;
    }

    upstream u2 {
        server 127.0.0.1:8087;
        server 127.0.0.1:8089 backup;
    }

    proxy_connect_timeout 1s;

    server {
        listen      127.0.0.1:8081;
        proxy_pass  u;
        proxy_next_upstream off;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  u2;
        proxy_next_upstream on;
    }

    server {
        listen      127.0.0.1:8083;
        proxy_pass  u;
        proxy_next_upstream on;
        proxy_next_upstream_tries 2;
    }
}

EOF

$t->run_daemon(\&stream_daemon);
$t->run()->waitforsocket('127.0.0.1:8089');

###############################################################################

is(stream('127.0.0.1:8081')->io('.'), '', 'next off');
is(stream('127.0.0.1:8082')->io('.'), 'SEE-THIS', 'next on');

# make sure backup is not tried

is(stream('127.0.0.1:8083')->io('.'), '', 'next tries');

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:8089',
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
