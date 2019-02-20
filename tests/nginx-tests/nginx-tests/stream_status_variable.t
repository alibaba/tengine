#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream status variable.

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

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_access/)
	->has(qw/stream_limit_conn/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    log_format  status  $status;

    limit_conn_zone  $binary_remote_addr  zone=zone:1m;

    server {
        listen      127.0.0.1:8080;
        return      SEE-THIS;
        access_log  %%TESTDIR%%/200.log status;
    }

    server {
        listen      127.0.0.1:8081;
        return      SEE-THIS;
        deny        all;
        access_log  %%TESTDIR%%/403.log status;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8083;
        access_log  %%TESTDIR%%/502.log status;

        proxy_connect_timeout 0;
    }

    server {
        listen      127.0.0.1:8084;
        proxy_pass  example.com:$remote_port;
        access_log  %%TESTDIR%%/500.log status;
    }

    server {
        listen      127.0.0.1:8085;
        limit_conn  zone 1;
        proxy_pass  127.0.0.1:8086;
        access_log  %%TESTDIR%%/503.log status;
    }

    server {
        listen      127.0.0.1:8086 proxy_protocol;
        return      SEE-THIS;
        access_log  %%TESTDIR%%/400.log status;
    }
}

EOF

$t->run()->plan(6);

###############################################################################

stream('127.0.0.1:' . port(8080))->read();
stream('127.0.0.1:' . port(8081))->read();
stream('127.0.0.1:' . port(8082))->read();
stream('127.0.0.1:' . port(8084))->read();

my $s = stream('127.0.0.1:' . port(8085));
stream('127.0.0.1:' . port(8085))->read();
$s->io('PROXY INVALID');

$t->stop();

is($t->read_file('200.log'), "200\n", 'stream status 200');
is($t->read_file('400.log'), "400\n", 'stream status 400');
is($t->read_file('403.log'), "403\n", 'stream status 403');
is($t->read_file('500.log'), "500\n", 'stream status 500');
is($t->read_file('502.log'), "502\n", 'stream status 502');
is($t->read_file('503.log'), "503\n200\n", 'stream status 503');

###############################################################################
