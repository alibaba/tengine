#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx ssi module.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http ssi cache proxy rewrite/)->plan(18);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path       %%TESTDIR%%/cache levels=1:2
                           keys_zone=NAME:10m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        if ($args = "found") {
            return 204;
        }

        location / {
            ssi on;
        }
        location /proxy/ {
            ssi on;
            proxy_pass http://127.0.0.1:8080/local/;
        }
        location /cache/ {
            proxy_pass http://127.0.0.1:8080/local/;
            proxy_cache NAME;
            proxy_cache_valid 200 1h;
        }
        location /local/ {
            ssi off;
            alias %%TESTDIR%%/;
        }
    }
}

EOF

$t->write_file('test1.html', 'X<!--#echo var="arg_test" -->X');
$t->write_file('test2.html',
	'X<!--#include virtual="/test1.html?test=test" -->X');
$t->write_file('test3.html',
	'X<!--#set var="blah" value="test" --><!--#echo var="blah" -->X');
$t->write_file('test-args-rewrite.html',
	'X<!--#include virtual="/check?found" -->X');
$t->write_file('test-empty1.html', 'X<!--#include virtual="/empty.html" -->X');
$t->write_file('test-empty2.html',
	'X<!--#include virtual="/local/empty.html" -->X');
$t->write_file('test-empty3.html',
	'X<!--#include virtual="/cache/empty.html" -->X');
$t->write_file('empty.html', '');

$t->run();

###############################################################################

like(http_get('/test1.html'), qr/^X\(none\)X$/m, 'echo no argument');
like(http_get('/test1.html?test='), qr/^XX$/m, 'empty argument');
like(http_get('/test1.html?test=test'), qr/^XtestX$/m, 'argument');
like(http_get('/test1.html?test=test&a=b'), qr/^XtestX$/m, 'argument 2');
like(http_get('/test1.html?a=b&test=test'), qr/^XtestX$/m, 'argument 3');
like(http_get('/test1.html?a=b&test=test&d=c'), qr/^XtestX$/m, 'argument 4');
like(http_get('/test1.html?atest=a&testb=b&ctestc=c&test=test'), qr/^XtestX$/m,
	'argument 5');

like(http_get('/test2.html'), qr/^XXtestXX$/m, 'argument via include');

like(http_get('/test3.html'), qr/^XtestX$/m, 'set');

# args should be in subrequest even if original request has no args and that
# was queried somehow (e.g. by server rewrites)

like(http_get('/test-args-rewrite.html'), qr/^XX$/m, 'args only subrequest');

like(http_get('/test-args-rewrite.html?wasargs'), qr/^XX$/m,
	'args was in main request');

# Last-Modified and Accept-Ranges headers should be cleared

unlike(http_get('/test1.html'), qr/Last-Modified|Accept-Ranges/im,
	'cleared headers');
unlike(http_get('/proxy/test1.html'), qr/Last-Modified|Accept-Ranges/im,
	'cleared headers from proxy');

like(http_get('/test-empty1.html'), qr/HTTP/, 'empty with ssi');
like(http_get('/test-empty2.html'), qr/HTTP/, 'empty without ssi');
like(http_get('/test-empty3.html'), qr/HTTP/, 'empty with proxy');
like(http_get('/test-empty3.html'), qr/HTTP/, 'empty with proxy cached');

like(`grep -F '[alert]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no alerts');

###############################################################################
