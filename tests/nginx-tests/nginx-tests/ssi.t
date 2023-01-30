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

my $t = Test::Nginx->new()->has(qw/http ssi cache proxy rewrite/)
	->plan(30);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path       %%TESTDIR%%/cache levels=1:2
                           keys_zone=NAME:1m;

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
        location = /test-empty-postpone.html {
            ssi on;
            postpone_output 0;
        }
        location /var {
            ssi on;
            add_header X-Var x${date_gmt}x;
        }
        location /var_noformat {
            ssi on;
            add_header X-Var x${date_gmt}x;
            return 200;
        }
        location /var_nossi {
            add_header X-Var x${date_gmt}x;
            return 200;
        }
    }
}

EOF

$t->write_file('test1.html', 'X<!--#echo var="arg_test" -->X');
$t->write_file('test2.html',
	'X<!--#include virtual="/test1.html?test=test" -->X');
$t->write_file('test3.html',
	'X<!--#set var="blah" value="test" --><!--#echo var="blah" -->X');
$t->write_file('test4-echo-none.html',
	'X<!--#set var="blah" value="<test>" -->'
	. '<!--#echo var="blah" encoding="none" -->X');
$t->write_file('test5-echo-url.html',
	'X<!--#set var="blah" value="<test>" -->'
	. '<!--#echo var="blah" encoding="url" -->X');
$t->write_file('test6-echo-entity.html',
	'X<!--#set var="blah" value="<test>" -->'
	. '<!--#echo var="blah" encoding="entity" -->X');
$t->write_file('test-args-rewrite.html',
	'X<!--#include virtual="/check?found" -->X');
$t->write_file('test-empty1.html', 'X<!--#include virtual="/empty.html" -->X');
$t->write_file('test-empty2.html',
	'X<!--#include virtual="/local/empty.html" -->X');
$t->write_file('test-empty3.html',
	'X<!--#include virtual="/cache/empty.html" -->X');
$t->write_file('test-empty-postpone.html',
	'X<!--#include virtual="/proxy/empty.html" -->X');
$t->write_file('empty.html', '');

$t->write_file('unescape.html?', 'SEE-THIS') unless $^O eq 'MSWin32';
$t->write_file('unescape1.html',
	'X<!--#include virtual="/tes%741.html?test=test" -->X');
$t->write_file('unescape2.html',
	'X<!--#include virtual="/unescape.html%3f" -->X');
$t->write_file('unescape3.html',
	'X<!--#include virtual="/test1.html%3ftest=test" -->X');

$t->write_file('var_format.html',
	'x<!--#if expr="$arg_custom" -->'
		. '<!--#config timefmt="%A, %H:%M:%S" -->'
		. '<!--#set var="v" value="$date_gmt" -->'
		. '<!--#echo var="v" -->'
	. '<!--#else -->'
		. '<!--#set var="v" value="$date_gmt" -->'
		. '<!--#echo var="v" -->'
	. '<!--#endif -->x');

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

like(http_get('/test4-echo-none.html'), qr/^X<test>X$/m,
	'echo encoding none');

TODO: {
local $TODO = 'no strict URI escaping yet' unless $t->has_version('1.21.1');

like(http_get('/test5-echo-url.html'), qr/^X%3Ctest%3EX$/m,
	'echo encoding url');

}

like(http_get('/test6-echo-entity.html'), qr/^X&lt;test&gt;X$/m,
	'echo encoding entity');

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

# empty subrequests

like(http_get('/test-empty1.html'), qr/HTTP/, 'empty with ssi');
like(http_get('/test-empty2.html'), qr/HTTP/, 'empty without ssi');
like(http_get('/test-empty3.html'), qr/HTTP/, 'empty with proxy');
like(http_get('/test-empty3.html'), qr/HTTP/, 'empty with proxy cached');

like(http_get('/test-empty-postpone.html'), qr/HTTP.*XX/ms,
	'empty with postpone_output 0');

# handling of escaped URIs

like(http_get('/unescape1.html'), qr/^XXtestXX$/m, 'escaped in path');

SKIP: {
skip 'incorrect filename on win32', 2 if $^O eq 'MSWin32';

like(http_get('/unescape2.html'), qr/^XSEE-THISX$/m,
	'escaped question in path');
like(http_get('/unescape3.html'), qr/404 Not Found/,
	'escaped query separator');

}

# handling of embedded date variables

my $re_date_gmt = qr/X-Var: x.+, \d\d-.+-\d{4} \d\d:\d\d:\d\d .+x/;

like(http_get('/var_nossi.html'), $re_date_gmt, 'no ssi');
like(http_get('/var_noformat.html'), $re_date_gmt, 'no format');

like(http_get('/var_format.html?custom=1'), $re_date_gmt, 'custom header');
like(http_get('/var_format.html'), $re_date_gmt, 'default header');

like(http_get('/var_format.html?custom=1'),
	qr/x.+, \d\d:\d\d:\d\dx/, 'custom ssi');
like(http_get('/var_format.html'),
	qr/x.+, \d\d-.+-\d{4} \d\d:\d\d:\d\d .+x/, 'default ssi');

###############################################################################
