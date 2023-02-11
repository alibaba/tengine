#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for proxy headers Expires / Cache-Control / X-Accel-Expires.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache rewrite/)->plan(19);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header  X-Cache-Status  $upstream_cache_status;

        location / {
            proxy_pass  http://127.0.0.1:8081;
            proxy_cache NAME;

            proxy_cache_background_update on;
        }

        location /ignore {
            proxy_pass  http://127.0.0.1:8081;
            proxy_cache NAME;

            proxy_ignore_headers Cache-Control Expires;
            proxy_ignore_headers X-Accel-Expires;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location /expires {
            add_header Expires "Thu, 31 Dec 2037 23:55:55 GMT";
            return 204;
        }

        location /cache-control {
            add_header Cache-Control max-age=60;
            return 204;
        }

        location /x-accel-expires {
            add_header X-Accel-Expires 60;
            return 204;
        }

        location /x-accel-expires-at {
            add_header X-Accel-Expires @60;
            return 204;
        }

        location /x-accel-expires-duplicate {
            add_header X-Accel-Expires 60;
            add_header X-Accel-Expires 0;
            return 204;
        }

        location /ignore {
            add_header Expires "Thu, 31 Dec 2037 23:55:55 GMT";
            add_header Cache-Control max-age=60;
            add_header X-Accel-Expires 60;
            return 204;
        }

        location /cache-control-before-expires {
            add_header Cache-Control max-age=60;
            add_header Expires "Thu, 01 Jan 1970 00:00:01 GMT";
            return 204;
        }

        location /cache-control-after-expires {
            add_header Expires "Thu, 01 Jan 1970 00:00:01 GMT";
            add_header Cache-Control max-age=60;
            return 204;
        }

        location /cache-control-no-cache-before-expires {
            add_header Cache-Control no-cache;
            add_header Expires "Thu, 31 Dec 2037 23:55:55 GMT";
            return 204;
        }

        location /cache-control-no-cache-after-expires {
            add_header Expires "Thu, 31 Dec 2037 23:55:55 GMT";
            add_header Cache-Control no-cache;
            return 204;
        }

        location /x-accel-expires-before {
            add_header X-Accel-Expires 60;
            add_header Expires "Thu, 01 Jan 1970 00:00:01 GMT";
            add_header Cache-Control no-cache;
            return 204;
        }

        location /x-accel-expires-after {
            add_header Expires "Thu, 01 Jan 1970 00:00:01 GMT";
            add_header Cache-Control no-cache;
            add_header X-Accel-Expires 60;
            return 204;
        }

        location /x-accel-expires-0-before {
            add_header X-Accel-Expires 0;
            add_header Cache-Control max-age=60;
            add_header Expires "Thu, 31 Dec 2037 23:55:55 GMT";
            return 204;
        }

        location /x-accel-expires-0-after {
            add_header Cache-Control max-age=60;
            add_header Expires "Thu, 31 Dec 2037 23:55:55 GMT";
            add_header X-Accel-Expires 0;
            return 204;
        }

        location /cache-control-no-cache-one {
            add_header Cache-Control "no-cache, max-age=60";
            return 204;
        }

        location /cache-control-no-cache-multi {
            add_header Cache-Control no-cache;
            add_header Cache-Control max-age=60;
            return 204;
        }

        location /extension-before-x-accel-expires {
            add_header Cache-Control stale-while-revalidate=2145902155;
            add_header X-Accel-Expires  @1;
            return 204;
        }

        location /extension-after-x-accel-expires {
            add_header X-Accel-Expires @1;
            add_header Cache-Control stale-while-revalidate=2145902155;
            return 204;
        }

        location /set-cookie {
            add_header Set-Cookie foo;
            add_header Expires "Thu, 01 Jan 1970 00:00:01 GMT";
            add_header Cache-control max-age=60;
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

# cache headers work

like(get('/expires'), qr/HIT/, 'expires');
like(get('/cache-control'), qr/HIT/, 'cache-control');
like(get('/x-accel-expires'), qr/HIT/, 'x-accel-expires');
like(get('/x-accel-expires-at'), qr/EXPIRED/, 'x-accel-expires at');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

# the second header to disable cache is duplicate and ignored

like(get('/x-accel-expires-duplicate'), qr/HIT/, 'x-accel-expires duplicate');

}

# with cache headers ignored, the response will be fresh

like(get('/ignore'), qr/MISS/, 'cache headers ignored');

# Cache-Control is preferred over Expires

like(get('/cache-control-before-expires'), qr/HIT/,
	'cache-control before expires');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like(get('/cache-control-after-expires'), qr/HIT/,
	'cache-control after expires');

}

like(get('/cache-control-no-cache-before-expires'), qr/MISS/,
	'cache-control no-cache before expires');
like(get('/cache-control-no-cache-after-expires'), qr/MISS/,
	'cache-control no-cache after expires');

# X-Accel-Expires is preferred over both Cache-Control and Expires

like(get('/x-accel-expires-before'), qr/HIT/, 'x-accel-expires before');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like(get('/x-accel-expires-after'), qr/HIT/, 'x-accel-expires after');

}

like(get('/x-accel-expires-0-before'), qr/MISS/, 'x-accel-expires 0 before');
like(get('/x-accel-expires-0-after'), qr/MISS/, 'x-accel-expires 0 after');

# "Cache-Control: no-cache" disables caching, no matter of "max-age"

like(get('/cache-control-no-cache-one'), qr/MISS/,
	'cache-control no-cache');
like(get('/cache-control-no-cache-multi'), qr/MISS/,
	'cache-control no-cache multi line');

# Cache-Control extensions are preserved with X-Accel-Expires

like(get('/extension-before-x-accel-expires'),
	qr/STALE/, 'cache-control extensions before x-accel-expires');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like(get('/extension-after-x-accel-expires'),
	qr/STALE/, 'cache-control extensions after x-accel-expires');

}

# Set-Cookie is considered when caching with Cache-Control

like(get('/set-cookie'), qr/MISS/, 'set-cookie not cached');

###############################################################################

sub get {
	my ($uri) = @_;
	http_get($uri);
	http_get($uri);
}

###############################################################################
