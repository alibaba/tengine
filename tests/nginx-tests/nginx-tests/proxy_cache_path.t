#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache with use_temp_path parameter.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache shmem/)->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache1
                       keys_zone=ON:1m      use_temp_path=on;
    proxy_cache_path   %%TESTDIR%%/cache2
                       keys_zone=OFF:1m     use_temp_path=off;
    proxy_cache_path   %%TESTDIR%%/cache4   levels=1:2
                       keys_zone=LEVELS:1m  use_temp_path=off;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;

            proxy_cache   $arg_c;

            proxy_cache_valid   any      1m;

            add_header X-Cache-Status $upstream_cache_status;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
        }
    }
}

EOF

$t->write_file('t', 'SEE-THIS');

$t->run();

###############################################################################

like(http_get('/t?c=ON'), qr/MISS.*SEE-THIS/ms, 'temp path');
like(http_get('/t?c=OFF'), qr/MISS.*SEE-THIS/ms, 'temp path off');
like(http_get('/t?c=LEVELS'), qr/MISS.*SEE-THIS/ms, 'temp path levels');

$t->write_file('t', 'SEE-THAT');

like(http_get('/t?c=ON'), qr/HIT.*SEE-THIS/ms, 'temp path cached');
like(http_get('/t?c=OFF'), qr/HIT.*SEE-THIS/ms, 'temp path cached off');
like(http_get('/t?c=LEVELS'), qr/HIT.*SEE-THIS/ms, 'temp path cached levels');

###############################################################################
