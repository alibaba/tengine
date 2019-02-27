#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache revalidation with conditional requests.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy cache rewrite/)->plan(23)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=one:1m;

    proxy_cache_revalidate on;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   one;

            proxy_cache_valid  200 404  2s;

            add_header X-Cache-Status $upstream_cache_status;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / { }
        location /etag/ {
            proxy_pass http://127.0.0.1:8081/;
            proxy_hide_header Last-Modified;
        }
        location /201 {
            add_header Last-Modified "Mon, 02 Mar 2015 17:20:58 GMT";
            add_header Cache-Control "max-age=1";
            add_header X-If-Modified-Since $http_if_modified_since;
            return 201;
        }
    }
}

EOF

my $d = $t->testdir();

$t->write_file('t', 'SEE-THIS');
$t->write_file('t2', 'SEE-THIS');
$t->write_file('t3', 'SEE-THIS');

$t->run();

###############################################################################

# request documents and make sure they are cached

like(http_get('/t'), qr/X-Cache-Status: MISS.*SEE/ms, 'request');
like(http_get('/t'), qr/X-Cache-Status: HIT.*SEE/ms, 'request cached');

like(http_get('/t2'), qr/X-Cache-Status: MISS.*SEE/ms, '2nd request');
like(http_get('/t2'), qr/X-Cache-Status: HIT.*SEE/ms, '2nd request cached');

like(http_get('/etag/t'), qr/X-Cache-Status: MISS.*SEE/ms, 'etag');
like(http_get('/etag/t'), qr/X-Cache-Status: HIT.*SEE/ms, 'etag cached');

like(http_get('/etag/t2'), qr/X-Cache-Status: MISS.*SEE/ms, 'etag2');
like(http_get('/etag/t2'), qr/X-Cache-Status: HIT.*SEE/ms, 'etag2 cached');

like(http_get('/201'), qr/X-Cache-Status: MISS/, 'other status');
like(http_get('/201'), qr/X-Cache-Status: HIT/, 'other status cached');

like(http_get('/t3'), qr/SEE/, 'cache before 404');

# wait for a while for cached responses to expire

select undef, undef, undef, 3.5;

# 1st document isn't modified, and should be revalidated on first request
# (a 304 status code will appear in backend's logs), then cached again

like(http_get('/t'), qr/X-Cache-Status: REVALIDATED.*SEE/ms, 'revalidated');
like(http_get('/t'), qr/X-Cache-Status: HIT.*SEE/ms, 'cached again');

rename("$d/t3", "$d/t3_moved");

like(http_get('/t3'), qr/ 404 /, 'cache 404 response');

select undef, undef, undef, 0.1;
like($t->read_file('access.log'), qr/ 304 /, 'not modified');

# 2nd document is recreated with a new content

$t->write_file('t2', 'NEW');
like(http_get('/t2'), qr/X-Cache-Status: EXPIRED.*NEW/ms, 'revalidate failed');
like(http_get('/t2'), qr/X-Cache-Status: HIT.*NEW/ms, 'new response cached');

# the same for etag:
# 1st document isn't modified
# 2nd document is recreated

like(http_get('/etag/t'), qr/X-Cache-Status: REVALIDATED.*SEE/ms,
	'etag revalidated');
like(http_get('/etag/t'), qr/X-Cache-Status: HIT.*SEE/ms,
	'etag cached again');
like(http_get('/etag/t2'), qr/X-Cache-Status: EXPIRED.*NEW/ms,
	'etag2 revalidate failed');
like(http_get('/etag/t2'), qr/X-Cache-Status: HIT.*NEW/ms,
	'etag2 new response cached');

# check that conditional requests are only used for 200/206 responses

# d0ce06cb9be1 in 1.7.3 changed to ignore header filter's work to strip
# the Last-Modified header when storing non-200/206 in cache;
# 1573fc7875fa in 1.7.9 effectively turned it back.

unlike(http_get('/201'), qr/X-If-Modified/, 'other status no revalidation');

# wait for a while for a cached 404 response to expire

select undef, undef, undef, 3.5;

# check that conditional requests are not used to revalidate 404 response

# before fd283aa92e04 introduced in 1.7.7, this test passed by chance because
# of the If-Modified-Since header that was sent with Epoch in revalidation
# of responses cached without the Last-Modified header;
# fd283aa92e04 leaved (an legitimate) successful revalidation of 404 by ETag
# (introduced by 44b9ab7752e3 in 1.7.3), which caused the test to fail;
# 1573fc7875fa in 1.7.9 changed to not revalidate non-200/206 responses but
# leaked Last-Modified and ETag into 404 inherited from stale 200/206 response;
# 174512857ccf in 1.7.11 fixed the leak and allowed the test to pass.

rename("$d/t3_moved", "$d/t3");

like(http_get('/t3'), qr/SEE/, 'no 404 revalidation after stale 200');

###############################################################################
