#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache, the Vary header.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache gzip rewrite/)
	->plan(42)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache keys_zone=one:1m inactive=5s;
    proxy_cache_key    $uri;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Cache-Status $upstream_cache_status;

        location / {
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   one;
        }

        location /replace/ {
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   one;
        }

        location /revalidate/ {
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   one;
            proxy_cache_revalidate on;
        }

        location /ignore/ {
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   one;
            proxy_ignore_headers Vary;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        gzip on;
        gzip_min_length 0;
        gzip_http_version 1.0;
        gzip_vary on;

        expires 2s;

        location / {
            if ($args = "novary") {
                return 200 "the only variant\n";
            }
        }

        location /asterisk {
            gzip off;
            add_header Vary "*";
        }

        location /complex {
            gzip off;
            add_header Vary ",, Accept-encoding , ,";
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');
$t->write_file('asterisk', 'SEE-THIS');
$t->write_file('complex', 'SEE-THIS');

$t->run();

###############################################################################

like(get('/', 'gzip'), qr/MISS/ms, 'first request');
like(get('/', 'gzip'), qr/HIT/ms, 'vary match cached');
like(get('/', 'deflate'), qr/MISS/ms, 'vary mismatch');
like(get('/', 'deflate'), qr/HIT/ms, 'vary mismatch cached');
like(get('/', 'foo'), qr/MISS/ms, 'vary mismatch 2');
like(get('/', 'foo'), qr/HIT/ms, 'vary mismatch 2 cached');
like(get('/', 'gzip'), qr/HIT/ms, 'multiple representations cached');

SKIP: {
skip 'long tests', 6 unless $ENV{TEST_NGINX_UNSAFE};

# make sure all variants are properly expire
# and removed after inactive timeout

sleep(3);

like(get('/', 'gzip'), qr/EXPIRED/ms, 'first expired');
like(get('/', 'deflate'), qr/EXPIRED/ms, 'second variant expired');

like(get('/', 'gzip'), qr/HIT/ms, 'first cached after expire');
like(get('/', 'deflate'), qr/HIT/ms, 'second cached after expire');

sleep(12);

like(get('/', 'gzip'), qr/MISS/ms, 'first inactive removed');
like(get('/', 'deflate'), qr/MISS/ms, 'second variant removed');

}

SKIP: {
skip 'long tests', 6 unless $ENV{TEST_NGINX_UNSAFE};

# check if the variant which was loaded first will be properly
# removed if it's not requested (but another variant is requested
# at the same time)

sleep(3);
like(get('/', 'deflate'), qr/EXPIRED/ms, 'bump1');
sleep(3);
like(get('/', 'deflate'), qr/EXPIRED/ms, 'bump2');
sleep(3);
like(get('/', 'deflate'), qr/EXPIRED/ms, 'bump3');
sleep(3);
like(get('/', 'deflate'), qr/EXPIRED/ms, 'bump4');

TODO: {
local $TODO = 'not yet';

like(get('/', 'gzip'), qr/MISS/ms, 'first not bumped by second requests');

}

like(get('/', 'deflate'), qr/HIT/ms, 'second variant cached');

}

# if a response without Vary is returned to replace previously returned
# responses with Vary, make sure it is then used in all cases

like(get('/replace/', 'gzip'), qr/MISS/, 'replace first');
like(get('/replace/', 'deflate'), qr/MISS/, 'replace second');

sleep(3);

like(get('/replace/?novary', 'deflate'), qr/EXPIRED/, 'replace novary');
like(get('/replace/?zztest', 'gzip'), qr/HIT/, 'all replaced');

# make sure revalidation of variants works fine

like(get('/revalidate/', 'gzip'), qr/MISS/, 'revalidate first');
like(get('/revalidate/', 'deflate'), qr/MISS/, 'revalidate second');

sleep(3);

like(get('/revalidate/', 'gzip'), qr/REVALIDATED/, 'revalidated first');
like(get('/revalidate/', 'deflate'), qr/REVALIDATED/, 'revalidated second');
like(get('/revalidate/', 'gzip'), qr/HIT/, 'revalidate first after');
like(get('/revalidate/', 'deflate'), qr/HIT/, 'revalidate second after');

# if the Vary header is ignored, cached version can be returned
# regardless of request headers

like(get('/ignore/', 'gzip'), qr/MISS/ms, 'another request');
like(get('/ignore/', 'deflate'), qr/HIT/ms, 'vary ignored');

# check parsing of Vary with multiple headers listed

like(get('/complex', 'gzip'), qr/MISS/ms, 'vary complex first');
like(get('/complex', 'deflate'), qr/MISS/ms, 'vary complex second');
like(get('/complex', 'gzip'), qr/HIT/ms, 'vary complex first cached');
like(get('/complex', 'deflate'), qr/HIT/ms, 'vary complex second cached');

# From RFC 7231, "7.1.4. Vary",
# http://tools.ietf.org/html/rfc7231#section-7.1.4:
#
#    A Vary field value of "*" signals that anything about the request
#    might play a role in selecting the response representation, possibly
#    including elements outside the message syntax (e.g., the client's
#    network address).  A recipient will not be able to determine whether
#    this response is appropriate for a later request without forwarding
#    the request to the origin server.
#
# In theory, If-None-Match can be used to check if the representation
# present in the cache is appropriate.  This seems to be only possible
# with strong entity tags though, as representation with different
# content condings may share the same weak entity tag.

like(get('/asterisk', 'gzip'), qr/MISS/ms, 'vary asterisk first');
like(get('/asterisk', 'gzip'), qr/MISS/ms, 'vary asterisk second');

# From RFC 7234, "4.1. Calculating Secondary Keys with Vary",
# http://tools.ietf.org/html/rfc7234#section-4.1:
#
#    The selecting header fields from two requests are defined to match if
#    and only if those in the first request can be transformed to those in
#    the second request by applying any of the following:
#
#    o  adding or removing whitespace, where allowed in the header field's
#       syntax
#
#    o  combining multiple header fields with the same field name (see
#       Section 3.2 of [RFC7230])
#
#    o  normalizing both header field values in a way that is known to
#       have identical semantics, according to the header field's
#       specification (e.g., reordering field values when order is not
#       significant; case-normalization, where values are defined to be
#       case-insensitive)
#
# Only whitespace normalization is currently implemented.

like(get('/', 'foo, bar'), qr/MISS/ms, 'normalize first');
like(get('/', 'foo,bar'), qr/HIT/ms, 'normalize whitespace');
like(get('/', 'foo,,  ,bar , '), qr/HIT/ms, 'normalize empty');
like(get('/', 'foobar'), qr/MISS/ms, 'normalize no whitespace mismatch');

TODO: {
local $TODO = 'not yet';

like(get('/', 'bar,foo'), qr/HIT/ms, 'normalize order');

}

###############################################################################

sub get {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
Accept-Encoding: $extra

EOF
}

###############################################################################
