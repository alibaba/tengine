#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for error_page directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(7)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /redirect200 {
            error_page 404 =200 http://example.com/;
            return 404;
        }

        location /redirect497 {
            # 497 implies implicit status code change
            error_page 497 https://example.com/;
            return 497;
        }

        location /error302redirect {
            error_page 302 http://example.com/;
            return 302 "first";
        }

        location /error302return302text {
            error_page 302 /return302text;
            return 302 "first";
        }

        location /return302text {
            return 302 "http://example.com/";
        }

        location /error302rewrite {
            error_page 302 /rewrite;
            return 302 "first";
        }

        location /rewrite {
            rewrite ^ http://example.com/;
        }

        location /error302directory {
            error_page 302 /directory;
            return 302 "first";
        }

        location /directory {
        }

        location /error302auto {
            error_page 302 /auto;
            return 302 "first";
        }

        location /auto/ {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}

EOF

mkdir($t->testdir() . '/directory');

$t->run();

###############################################################################

# tests for error_page status code change for redirects. problems
# introduced in 0.8.53 and fixed in 0.9.5.

like(http_get('/redirect200'), qr!HTTP!, 'redirect 200');
like(http_get('/redirect497'), qr!HTTP/1.1 302!, 'redirect 497');

# various tests to see if old location cleared if we happen to redirect
# again in error_page 302

like(http_get('/error302redirect'),
	qr{HTTP/1.1 302(?!.*Location: first).*Location: http://example.com/}ms,
	'error 302 redirect - old location cleared');

like(http_get('/error302return302text'),
	qr{HTTP/1.1 302(?!.*Location: first).*Location: http://example.com/}ms,
	'error 302 return 302 text - old location cleared');

like(http_get('/error302rewrite'),
	qr{HTTP/1.1 302(?!.*Location: first).*Location: http://example.com/}ms,
	'error 302 rewrite - old location cleared');

like(http_get('/error302directory'),
	qr{HTTP/1.1 301(?!.*Location: first).*Location: http://}ms,
	'error 302 directory redirect - old location cleared');

like(http_get('/error302auto'),
	qr{HTTP/1.1 301(?!.*Location: first).*Location: http://}ms,
	'error 302 auto redirect - old location cleared');

###############################################################################
