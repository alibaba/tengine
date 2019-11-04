#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache, proxy_cache directive with variables.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache/)->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache1  levels=1:2
                       keys_zone=NAME1:1m;
    proxy_cache_path   %%TESTDIR%%/cache2  levels=1:2
                       keys_zone=NAME2:1m;

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

$t->write_file('index.html', 'SEE-THIS');

$t->run();

###############################################################################

like(http_get('/?c=NAME1'), qr/MISS.*SEE-THIS/ms, 'proxy request');
like(http_get('/?c=NAME1'), qr/HIT.*SEE-THIS/ms, 'proxy request cached');

unlike(http_head('/?c=NAME1'), qr/SEE-THIS/, 'head request');

$t->write_file('index.html', 'SEE-THAT');

like(http_get('/?c=NAME2'), qr/MISS.*SEE-THAT/ms, 'proxy request 2');
like(http_get('/?c=NAME2'), qr/HIT.*SEE-THAT/ms, 'proxy request 2 cached');

# some invalid cases

like(http_get('/?c=NAME'), qr/ 500 /, 'proxy_cache unknown');
like(http_get('/'), qr/(?<!X-Cache).*SEE-THAT/ms, 'proxy_cache empty');

$t->write_file('index.html', 'SEE-THOSE');

like(http_get('/'), qr/SEE-THOSE/, 'proxy_cache empty - not cached');

###############################################################################
