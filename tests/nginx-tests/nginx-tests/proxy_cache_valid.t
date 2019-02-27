#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache, the proxy_cache_valid directive
# used with the caching parameters set in the response header.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache rewrite/)->plan(12)
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

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;

            proxy_cache_valid  200 401  1m;

            proxy_intercept_errors on;
            error_page 404 401 = @fallback;

            add_header X-Cache-Status $upstream_cache_status;
        }

        location @fallback {
            return 403;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header Cache-Control $http_x_cc always;
            error_page 403 = /index-no-cache;
        }

        location /index-no-cache {
            add_header Cache-Control no-cache always;
            return 401;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->run();

###############################################################################

like(get('/t.html?1', 'X-CC: max-age=1'), qr/MISS/, 'max-age');
like(get('/t.html?2', 'X-CC: max-age=1, s-maxage=10'), qr/MISS/, 's-maxage');
like(http_get('/t.html?3'), qr/MISS/, 'proxy_cache_valid');

$t->write_file('t.html', 'NOOP');

like(http_get('/t.html?1'), qr/HIT/, 'max-age cached');
like(http_get('/t.html?2'), qr/HIT/, 's-maxage cached');
like(http_get('/t.html?3'), qr/HIT/, 'proxy_cache_valid cached');

select undef, undef, undef, 2.1;

# Cache-Control in the response header overrides proxy_cache_valid

like(http_get('/t.html?1'), qr/EXPIRED/, 'max-age ceased');
like(http_get('/t.html?2'), qr/HIT/, 's-maxage overrides max-age');

# ticket #1382, cache item "error" field was not set from Cache-Control: max-age

like(get('/t2.html', 'X-CC: max-age=1'), qr/403 Forbidden/, 'intercept error');

$t->write_file('t2.html', 'NOOP');

like(http_get('/t2.html'), qr/403 Forbidden/, 'error cached from max-age');

# ticket #1382, cache item "error" field was set regardless of u->cacheable.

like(http_get('/'), qr/403 Forbidden/, 'error no-cache');

$t->write_file('index.html', '');

like(http_get('/'), qr/200 OK/, 'error no-cache - not cacheable');

###############################################################################

sub get {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

###############################################################################
