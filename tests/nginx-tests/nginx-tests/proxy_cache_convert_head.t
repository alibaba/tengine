#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache with proxy_cache_convert_head directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache shmem/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_cache   NAME;

        proxy_cache_key $request_uri;

        proxy_cache_valid   200 302  2s;

        add_header X-Cache-Status $upstream_cache_status;

        location / {
            proxy_pass http://127.0.0.1:8081/t.html;
            proxy_cache_convert_head   off;

            location /inner {
                proxy_pass http://127.0.0.1:8081/t.html;
                proxy_cache_convert_head on;
            }
        }

        location /on {
            proxy_pass http://127.0.0.1:8081/t.html;
            proxy_cache_convert_head on;
        }
    }
    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Method $request_method;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');

$t->try_run('no proxy_cache_convert_head')->plan(8);

###############################################################################

like(http_get('/'), qr/X-Method: GET/, 'get');
like(http_head('/?2'), qr/X-Method: HEAD/, 'head');
like(http_head('/?2'), qr/HIT/, 'head cached');
unlike(http_get('/?2'), qr/SEE-THIS/, 'get after head');

like(http_get('/on'), qr/X-Method: GET/, 'on - get');
like(http_head('/on?2'), qr/X-Method: GET/, 'on - head');

like(http_get('/inner'), qr/X-Method: GET/, 'inner - get');
like(http_head('/inner?2'), qr/X-Method: GET/, 'inner - head');

###############################################################################
