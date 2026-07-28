#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for multiple patterns in sub filter.

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

my $t = Test::Nginx->new()->has(qw/http rewrite sub proxy/)->plan(42);

my $long_pattern = '0123456789abcdef' x 17;

(my $conf = <<'EOF') =~ s/%%LONG_PATTERN%%/$long_pattern/g;

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        sub_filter_types *;
        sub_filter foo bar;

        location /multi {
            sub_filter_once off;
            sub_filter aab +;
            sub_filter yyz -;
            return 200 $arg_a;
        }

        location /multi2 {
            sub_filter_once off;
            sub_filter aabb  +;
            sub_filter aaabb -;
            return 200 $arg_a;
        }

        location /multi3 {
            sub_filter_once off;
            sub_filter aacbb +;
            sub_filter aadbb -;
            return 200 $arg_a;
        }

        location /case {
            sub_filter_once off;
            sub_filter AAB +;
            sub_filter YYZ -;
            return 200 $arg_a;
        }

        location /case2 {
            sub_filter_once off;
            sub_filter ABCDEFGHIJKLMNOPQRSTUVWXYZ +;
            return 200 $arg_a;
        }

        location /case3 {
            sub_filter_once off;
            sub_filter abcdefghijklmnopqrstuvwxyz +;
            return 200 $arg_a;
        }

        location /minimal {
            sub_filter_once off;
            sub_filter ab +;
            sub_filter cd -;
            sub_filter ef *;
            sub_filter gh !;
            sub_filter x  _;
            return 200 $arg_a;
        }

        location /once {
            sub_filter aab +;
            sub_filter yyz -;
            return 200 $arg_a;
        }

        location /table/inheritance {
            sub_filter_once off;
            return 200 $arg_a;
        }

        location /utf8 {
            sub_filter_once off;
            sub_filter 模様 замена1;
            sub_filter पैटर्न замена2;
            sub_filter паттерн replaced;
            return 200 $arg_a;
        }

        location /var/replacement/multi {
            sub_filter_once off;
            sub_filter aab '${arg_a}_replaced';
            sub_filter yyz '${arg_b}_replaced';
            return 200 $arg_c;
        }

        location /crossbuf/match1 {
            sub_filter_once off;
            sub_filter abpattyz +;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/match2 {
            sub_filter_once off;
            sub_filter abpattrnyz +;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/match3 {
            sub_filter_once off;
            sub_filter abpatternyz +;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/match4 {
            sub_filter_once off;
            sub_filter abpattternyz +;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/match5-01 {
            sub_filter_once off;
            sub_filter abyz +;
            sub_filter abpattternyz -;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/match5-02 {
            sub_filter_once off;
            sub_filter abpayz +;
            sub_filter abpattternyz -;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/match6 {
            sub_filter_once off;
            sub_filter abpattxernyz +;
            sub_filter abpattternyz -;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/superlong/match1 {
            sub_filter_once off;
            sub_filter %%LONG_PATTERN%% +;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/superlong/match2 {
            sub_filter_once off;
            sub_filter %%LONG_PATTERN%% +;
            sub_filter yz -;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/superlong/match3 {
            sub_filter_once off;
            sub_filter %%LONG_PATTERN%% +;
            sub_filter 01ef -;
            alias %%TESTDIR%%/;
        }

        location /crossbuf/superlong/match4 {
            sub_filter_once off;
            sub_filter %%LONG_PATTERN%% +;
            sub_filter 01ef -;
            sub_filter _ *;
            alias %%TESTDIR%%/;
        }

        location /shortbuf/match1 {
            sub_filter_once off;
            sub_filter abpatternyz +;

            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }

        location /shortbuf/match2 {
            sub_filter_once off;
            sub_filter abpatternyz +;
            sub_filter abpaernyz -;

            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }

        location /shortbuf/match3 {
            sub_filter_once off;
            sub_filter abpatternyz +;
            sub_filter abpaernyz -;
            sub_filter _ *;

            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }

        location /shortbuf/match4 {
            sub_filter_once off;
            sub_filter patt +;

            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }

        location /shortbuf/match5 {
            sub_filter_once off;
            sub_filter abpatternyz +;
            sub_filter abpa -;
            sub_filter tter *;

            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }
    }

    server {
        listen       127.0.0.1:8081;

        limit_rate 4;
        limit_rate_after 160;

        keepalive_requests 1;

        location / {
            return 200 $arg_a;
        }
    }
}

EOF

$t->write_file_expand('nginx.conf', $conf);

$t->write_file('huge1.html', 'abpattyz' x 6000);
$t->write_file('huge2.html', 'abpattrnyz' x 5000);
$t->write_file('huge3.html', 'abpatternyz' x 4000);
$t->write_file('huge4.html', 'abpattternyz' x 4000);

$t->write_file('huge5-01.html', 'abpatternyzA' x 4000);
$t->write_file('huge5-02.html', 'abpatternyzABCDEFGHIJ' x 4000);
$t->write_file('huge5-03.html', 'abpatternyzABCDEFGHIJK' x 4000);
$t->write_file('huge5-04.html', 'abpatternyzABCDEFGHIJKL' x 4000);

$t->write_file('huge6-01.html', 'abyzAabpattternyz' x 3000);
$t->write_file('huge6-02.html', 'abpayzAabpattternyz' x 3000);

$t->write_file('huge7-01.html', 'abpattxernyzabpattternyz' x 3000);
$t->write_file('huge7-02.html', 'abpattxernyzAabpattternyz' x 3000);
$t->write_file('huge7-03.html', 'abpattxernyzABCDEFGHIJabpattternyz' x 3000);
$t->write_file('huge7-04.html', 'abpattxernyzABCDEFGHIJKabpattternyz' x 3000);
$t->write_file('huge7-05.html', 'abpattxernyzABCDEFGHIJKLabpattternyz' x 3000);

$t->write_file('huge8.html', scalar ('ABC' . $long_pattern . 'XYZ') x 1000);
$t->write_file('huge9.html', scalar ('ABC' . $long_pattern . 'yz') x 1000);
$t->write_file('huge10-01.html', scalar ($long_pattern . 'ABC01ef') x 1000);
$t->write_file('huge10-02.html', scalar ('01efABC' . $long_pattern) x 1000);
$t->write_file('huge11.html', scalar ('01efA_Z' . $long_pattern) x 1000);

$t->run();

###############################################################################

like(http_get('/multi?a=aabAyyzBaab'), qr/\+A-B\+/, 'simple match');
like(http_get('/multi2?a=aabbaaabbaabb'), qr/\+-\+/, 'partial match');
like(http_get('/multi3?a=aadbbaacbb'), qr/-\+/, 'exact match');

like(http_get('/multi?a=AABYYZAAB'), qr/\+-\+/, 'case insensivity 1');
like(http_get('/case?a=aabyyzaab'), qr/\+-\+/, 'case insensivity 2');
like(http_get('/case2?a=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'),
	qr/\+\+/, 'case insensivity 3');
like(http_get('/case3?a=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'),
	qr/\+\+/, 'case insensivity 4');

like(http_get('/minimal?a=AAabcdefghBxBabCxCcdDDefEEghFF'),
	qr/AA\+-\*!B_B\+C_C-DD\*EE!FF/, 'minimal match');

like(http_get('/utf8?a=ТЕКСТ模様ТЕКСТ2पैटर्नТЕКСТ3паттерн'),
	qr/ТЕКСТзамена1ТЕКСТ2замена2ТЕКСТ3replaced/, 'utf8 match');

like(http_get('/once?a=aabyyzaab'), qr/\+-aab/, 'once 1');
like(http_get('/once?a=yyzaabyyz'), qr/-\+yyz/, 'once 2');
like(http_get('/once?a=yyzyyzaabaabyyz'), qr/-yyz\+aabyyz/, 'once 3');

like(http_get('/table/inheritance?a=foofoo'), qr/barbar/, 'table inheritance');

like(http_get('/var/replacement/multi?a=A&b=B&c=aabyyzaab'),
	qr/A_replacedB_replacedA_replaced/, 'complex multiple replace');

like(http_get('/crossbuf/match1/huge1.html'), qr/\+{6000}/,
	'crossbuf match 1 (simple match len 8)');
like(http_get('/crossbuf/match2/huge2.html'), qr/\+{5000}/,
	'crossbuf match 2 (simple match len 9)');
like(http_get('/crossbuf/match3/huge3.html'), qr/\+{4000}/,
	'crossbuf match 3 (simple match len 10)');
like(http_get('/crossbuf/match4/huge4.html'), qr/\+{4000}/,
	'crossbuf match 4 (simple match len 11)');

like(http_get('/crossbuf/match3/huge5-01.html'), qr/(\+A){4000}/,
	'crossbuf match 5.1');
like(http_get('/crossbuf/match3/huge5-02.html'), qr/(\+ABCDEFGHIJ){4000}/,
	'crossbuf match 5.2');
like(http_get('/crossbuf/match3/huge5-03.html'), qr/(\+ABCDEFGHIJK){4000}/,
	'crossbuf match 5.3');
like(http_get('/crossbuf/match3/huge5-04.html'), qr/(\+ABCDEFGHIJKL){4000}/,
	'crossbuf match 5.4');

like(http_get('/crossbuf/match5-01/huge6-01.html'), qr/(\+A-){3000}/,
	'crossbuf match 6.1 (multiple replace)');
like(http_get('/crossbuf/match5-02/huge6-02.html'), qr/(\+A-){3000}/,
	'crossbuf match 6.2 (multiple replace)');

like(http_get('/crossbuf/match6/huge7-01.html'), qr/(\+-){3000}/,
	'crossbuf match 7.1 (multiple replace)');
like(http_get('/crossbuf/match6/huge7-02.html'), qr/(\+A-){3000}/,
	'crossbuf match 7.2 (multiple replace)');
like(http_get('/crossbuf/match6/huge7-03.html'), qr/(\+ABCDEFGHIJ-){3000}/,
	'crossbuf match 7.3 (multiple replace)');
like(http_get('/crossbuf/match6/huge7-04.html'), qr/(\+ABCDEFGHIJK-){3000}/,
	'crossbuf match 7.4 (multiple replace)');
like(http_get('/crossbuf/match6/huge7-05.html'), qr/(\+ABCDEFGHIJKL-){3000}/,
	'crossbuf match 7.5 (multiple replace)');

like(http_get('/crossbuf/superlong/match1/huge8.html'), qr/(ABC\+XYZ){1000}/,
	'crossbuf superlong match 1');
like(http_get('/crossbuf/superlong/match2/huge9.html'), qr/(ABC\+-){1000}/,
	'crossbuf superlong match 2 (multiple replace)');
like(http_get('/crossbuf/superlong/match3/huge10-01.html'), qr/(\+ABC-){1000}/,
	'crossbuf superlong match 3.1 (multiple replace)');
like(http_get('/crossbuf/superlong/match3/huge10-02.html'), qr/(-ABC\+){1000}/,
	'crossbuf superlong match 3.2 (multiple replace)');
like(http_get('/crossbuf/superlong/match4/huge11.html'), qr/(-A\*Z\+){1000}/,
	'crossbuf superlong match 4 (1 byte search pattern)');

SKIP: {
skip 'long tests', 8 unless $ENV{TEST_NGINX_UNSAFE};

like(http_get('/shortbuf/match1?a=' . 'abpatternyzA' x 3),
	qr/(\+A){3}/, 'shortbuf match 1.1');
like(http_get('/shortbuf/match1?a=' . 'abpatternyzABCD' x 3),
	qr/(\+ABCD){3}/, 'shortbuf match 1.2');
like(http_get('/shortbuf/match1?a=' . 'abpatternyzABCDE' x 3),
	qr/(\+ABCDE){3}/, 'shortbuf match 1.3');
like(http_get('/shortbuf/match2?a=' . 'abpatternyzAabpaernyzB' x 2),
	qr/(\+A-B){2}/, 'shortbuf match 2.1 (multiple replace)');
like(http_get('/shortbuf/match2?a=' . 'abpatternyzAabpaernyz' x 2),
	qr/(\+A-){2}/, 'shortbuf match 2.2 (multiple replace)');
like(http_get('/shortbuf/match3?a=' . 'abpatternyzA_' x 3),
	qr/(\+A\*){3}/, 'shortbuf match 3 (1 byte search pattern)');
like(http_get('/shortbuf/match4?a=' . 'pattABCDEFGHI' x 3),
	qr/(\+ABCDEFGHI){3}/, 'shortbuf match 4');
like(http_get('/shortbuf/match5?a=abpatternyzABCDE' . 'abpatternyABCDE' x 2),
	qr/\+ABCDE(-\*nyABCDE){2}/, 'shortbuf match 5');
}

###############################################################################
