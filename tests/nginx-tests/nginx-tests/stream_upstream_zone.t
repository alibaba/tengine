#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream zone.

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

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_upstream_zone/)
	->plan(2)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    log_format test $upstream_addr;

    upstream u {
        zone u 1m;
        server 127.0.0.1:8081;
    }

    upstream u2 {
        zone u;
        server 127.0.0.1:8081 down;
        server 127.0.0.1:8081 backup down;
    }

    server {
        listen      127.0.0.1:8081;
        return      OK;
    }

    server {
        listen      127.0.0.1:8091;
        proxy_pass  u;

        access_log %%TESTDIR%%/access1.log test;
    }

    server {
        listen      127.0.0.1:8092;
        proxy_pass  u2;

        access_log %%TESTDIR%%/access2.log test;
    }
}

EOF

$t->write_file('index.html', '');
$t->run();

###############################################################################

my $p = port(8081);

TODO: {
todo_skip 'leaves coredump', 2 unless $^O ne 'MSWin32'
	or $ENV{TEST_NGINX_UNSAFE} or $t->has_version('1.13.4');

stream('127.0.0.1:' . port(8091));
stream("127.0.0.1:" . port(8092));

$t->stop();

is($t->read_file('access1.log'), "127.0.0.1:$p\n", 'upstream name');
is($t->read_file('access2.log'), "u2\n", 'no live upstreams');

}

###############################################################################
