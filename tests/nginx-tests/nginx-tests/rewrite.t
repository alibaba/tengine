#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for rewrite module.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(22)
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

        location / {
            rewrite ^ http://example.com/ redirect;
        }

        location /add {
            rewrite ^ http://example.com/?c=d redirect;
        }

        location /no {
            rewrite ^ http://example.com/?c=d? redirect;
        }

        location /return204 {
            return 204;
        }

        location /return200 {
            return 200;
        }

        location /return306 {
            return 306;
        }

        location /return405 {
            return 405;
        }

        location /error404return405 {
            error_page 404 /return405;
            return 404;
        }

        location /error405return204 {
            error_page 405 /return204;
            return 405;
        }

        location /error405return200 {
            error_page 405 /return200;
            return 405;
        }

        location /return200text {
            return 200 "text";
        }

        location /return404text {
            return 404 "text";
        }

        location /return302text {
            return 302 "text";
        }

        location /error405return200text {
            error_page 405 /return200text;
            return 405;
        }

        location /error302return200text {
            error_page 302 /return200text;
            return 302 "text";
        }

        location /error405return302text {
            error_page 405 /return302text;
            return 405;
        }

        location /error405rewrite {
            error_page 405 /;
            return 405;
        }

        location /error405directory {
            error_page 405 /directory;
            return 405;
        }

        location /directory {
        }

        location /capture {
            rewrite ^(.*) $1?c=d;
            return 200 "uri:$uri args:$args";
        }

        location /capturedup {
            rewrite ^(.*) $1?c=$1;
            return 200 "uri:$uri args:$args";
        }
    }
}

EOF

mkdir($t->testdir() . '/directory');

$t->run();

###############################################################################

like(http_get('/'), qr!^Location: http://example.com/\x0d?$!ms, 'simple');
like(http_get('/?a=b'), qr!^Location: http://example.com/\?a=b\x0d?$!ms,
	'simple with args');
like(http_get('/add'), qr!^Location: http://example.com/\?c=d\x0d?$!ms,
	'add args');

like(http_get('/add?a=b'), qr!^Location: http://example.com/\?c=d&a=b\x0d?$!ms,
	'add args with args');

like(http_get('/no?a=b'), qr!^Location: http://example.com/\?c=d\x0d?$!ms,
	'no args with args');

like(http_get('/return204'), qr!204 No Content!, 'return 204');
like(http_get('/return200'), qr!200 OK!, 'return 200');
like(http_get('/return306'), qr!HTTP/1.1 306 !, 'return 306');
like(http_get('/return405'), qr!HTTP/1.1 405.*body!ms, 'return 405');

# this used to result in 404, but was changed in 1.15.4
# to respond with 405 instead, much like a real error would do

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.15.4');

like(http_get('/error404return405'), qr!HTTP/1.1 405!, 'error 404 return 405');

}

# status code should be 405, and entity body is expected (vs. normal 204
# replies which doesn't expect to have body); use HTTP/1.1 for test
# to make problem clear

my $r = http(<<EOF);
GET /error405return204 HTTP/1.1
Host: localhost
Connection: close

EOF

like($r, qr/HTTP\/1.1 405.*(Content-Length|\x0d\0a0\x0d\x0a)/ms,
	'error 405 return 204');

# the same test, but with return 200.  this doesn't have special
# handling and returns builtin error page body (the same problem as
# in /error405return200text below)

like(http_get('/error405return200'), qr/HTTP\/1.1 405(?!.*body)/ms,
	'error 405 return 200');

# tests involving return with two arguments, as introduced in
# 0.8.42

like(http_get('/return200text'), qr!text\z!, 'return 200 text');
like(http_get('/return404text'), qr!text\z!, 'return 404 text');

like(http_get('/error405return200text'), qr!HTTP/1.1 405.*text\z!ms,
	'error 405 to return 200 text');

# return 302 is somewhat special: it adds Location header instead of
# body text.  additionally it doesn't sent reply directly (as it's done for
# other returns since 0.8.42) but instead returns NGX_HTTP_* code

like(http_get('/return302text'), qr!HTTP/1.1 302.*Location: text!ms,
	'return 302 text');

like(http_get('/error302return200text'),
	qr!HTTP/1.1 302.*Location: text.*text\z!ms,
	'error 302 return 200 text');

# in contrast to other return's this shouldn't preserve original status code
# from error, and the same applies to "rewrite ... redirect" as an error
# handler; both should in line with e.g. directory redirect as well

like(http_get('/error405return302text'),
	qr!HTTP/1.1 302.*Location: text!ms,
	'error 405 return 302 text');

like(http_get('/error405rewrite'),
	qr!HTTP/1.1 302.*Location: http://example.com/!ms,
	'error 405 rewrite redirect');

like(http_get('/error405directory'),
	qr!HTTP/1.1 301.*Location: http://!ms,
	'error 405 directory redirect');

# escaping of uri if there are args added in rewrite, and length
# is actually calculated (ticket #162)

like(http_get('/capture/%25?a=b'),
	qr!^uri:/capture/% args:c=d&a=b$!ms,
	'escape with added args');

like(http_get('/capturedup/%25?a=b'),
	qr!^uri:/capturedup/% args:c=/capturedup/%25&a=b$!ms,
	'escape with added args');

###############################################################################
