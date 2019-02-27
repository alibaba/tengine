#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http filter finalize code.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy cache image_filter limit_req/)
	->has(qw/rewrite/)->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path %%TESTDIR%%/cache keys_zone=cache:1m;

    limit_req_zone $binary_remote_addr zone=limit:1m rate=25r/m;

    log_format time "$request_uri:$status:$upstream_response_time";
    access_log time.log time;

    upstream u {
        server 127.0.0.1:8081;
        server 127.0.0.1:8081;
        server 127.0.0.1:8081;
        server 127.0.0.1:8081;
        server 127.0.0.1:8080;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # this used to cause a segmentation fault before 07f028df3879 (1.3.1)
        # http://nginx.org/pipermail/nginx/2011-January/024703.html

        location /t1 {
            proxy_pass http://127.0.0.1:8080/bad;
            proxy_cache cache;
            proxy_cache_valid any 1h;

            image_filter   resize  150 100;
            error_page     415   = /empty;
        }

        location /empty {
            return 204;
        }

        location /bad {
            return 404;
        }

        # another segfault, introduced in 204b780a89de (1.3.0),
        # fixed in 07f028df3879 (1.3.1)

        location /t2 {
            proxy_pass http://127.0.0.1:8080/big;
            proxy_store on;

            image_filter_buffer 10m;
            image_filter   resize  150 100;
            error_page     415   = /empty;
        }

        location /big {
            # big enough static file
        }

        # filter finalization may cause duplicate upstream finalization,
        # resulting in wrong $upstream_response_time,
        # http://nginx.org/pipermail/nginx-devel/2015-February/006539.html

        # note that we'll need upstream response time to be at least 1 second,
        # and at least 4 failed requests to make sure r->upstream_states will
        # not be reallocated

        location /t3 {
            proxy_pass http://u/slow;
            proxy_buffering off;

            image_filter   resize  150 100;
            error_page     415   = /upstream;
        }

        location /slow {
            limit_req zone=limit burst=5;
        }

        location /upstream {
            proxy_pass http://127.0.0.1:8080/empty;
        }

        location /time.log {
            # access to log
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
        return 444;
    }
}

EOF

$t->write_file('big', "x" x 10240000);
$t->write_file('slow', "x");

$t->run();

###############################################################################

like(http_get('/t1'), qr/HTTP/, 'image filter and cache');
like(http_get('/t2'), qr/HTTP/, 'image filter and store');

http_get('/slow');
http_get('/t3');
like(http_get('/time.log'), qr!/t3:.*, [1-9]\.!, 'upstream response time');

# "aio_write" is used to produce the following alert on some platforms:
# "readv() failed (9: Bad file descriptor) while reading upstream"

$t->todo_alerts() if $t->read_file('nginx.conf') =~ /aio_write on/
	and $t->read_file('nginx.conf') =~ /aio threads/;

###############################################################################
