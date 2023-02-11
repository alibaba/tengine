#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for limit_conn_dry_run directive, limit_conn_status variable.

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

my $t = Test::Nginx->new()->has(qw/stream stream_limit_conn http/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    limit_conn_zone  $binary_remote_addr  zone=zone:1m;

    log_format test $server_port:$limit_conn_status;
    access_log %%TESTDIR%%/test.log test;

    server {
        listen      127.0.0.1:8080;
        proxy_pass  127.0.0.1:8084;
        limit_conn  zone 1;

        proxy_timeout 5s;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  127.0.0.1:8084;
        limit_conn  zone 1;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8084;
        limit_conn  zone 1;

        limit_conn_dry_run on;
    }

    server {
        listen      127.0.0.1:8083;
        proxy_pass  127.0.0.1:8084;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8084;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('index.html', 'OK');
$t->run()->plan(9);

###############################################################################

my ($p, $p1, $p2, $p3) = (port(8080), port(8081), port(8082), port(8083));

is(stream("127.0.0.1:$p")->io("GET /\n"), 'OK', 'passed');

my $s = stream('127.0.0.1:' . port(8080));
$s->write("GET");

is(stream("127.0.0.1:$p1")->io("GET /\n"), '', 'rejected');
is(stream("127.0.0.1:$p2")->io("GET /\n"), 'OK', 'rejected dry run');
is(stream("127.0.0.1:$p3")->io("GET /\n"), 'OK', 'no limit');

undef $s;

$t->stop();

like($t->read_file('error.log'), qr/limiting connections, dry/, 'log dry run');
like($t->read_file('test.log'), qr|$p:PASSED|, 'log passed');
like($t->read_file('test.log'), qr|$p1:REJECTED$|m, 'log rejected');
like($t->read_file('test.log'), qr|$p2:REJECTED_DRY_RUN|, 'log rejected dry');
like($t->read_file('test.log'), qr|$p3:-|, 'log not found');

###############################################################################
