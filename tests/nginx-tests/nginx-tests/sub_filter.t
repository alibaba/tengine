#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for sub filter.

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

my $t = Test::Nginx->new()->has(qw/http rewrite sub proxy/)->plan(30)
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

        sub_filter_types *;
        sub_filter foo bar;

        location / {
        }

        location /once {
            return 200 $arg_b;
        }

        location /many {
            sub_filter_once off;
            return 200 $arg_b;
        }

        location /complex {
            sub_filter abac _replaced;
            return 200 $arg_b;
        }

        location /complex2 {
            sub_filter ababX _replaced;
            return 200 $arg_b;
        }

        location /complex3 {
            sub_filter aab _replaced;
            return 200 $arg_b;
        }

        location /single {
            sub_filter A B;
            return 200 $arg_b;
        }

        location /single/many {
            sub_filter A B;
            sub_filter_once off;
            return 200 $arg_b;
        }

        location /var/string {
            sub_filter X$arg_a _replaced;
            return 200 $arg_b;
        }

        location /var/replacement {
            sub_filter aab '${arg_a}_replaced';
            return 200 $arg_b;
        }

        location /lm {
            sub_filter_last_modified on;
            proxy_pass http://127.0.0.1:8081/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
    }
}

EOF

$t->write_file('foo.html', 'foo');
$t->write_file('foo_uc.html', 'FOO');
$t->write_file('foofoo.html', 'foofoo');
$t->run();

###############################################################################

like(http_get('/foo.html'), qr/bar/, 'sub_filter');
like(http_get('/foo_uc.html'), qr/bar/, 'sub_filter caseless');
like(http_get('/foofoo.html'), qr/barfoo/, 'once default');

like(http_get('/once?b=foofoo'), qr/barfoo/, 'once');
like(http_get('/many?b=foofoo'), qr/barbar/, 'many');
like(http_get('/many?b=fo'), qr/fo/, 'incomplete');
like(http_get('/many?b=foofo'), qr/barfo/, 'incomplete long');

like(http_get('/complex?b=abac'), qr/_replaced/, 'complex');
like(http_get('/complex?b=abaabac'), qr/aba_replaced/, 'complex 1st char');
like(http_get('/complex?b=ababac'), qr/replaced/, 'complex 2nd char');
like(http_get('/complex2?b=ababX'), qr/_replaced/, 'complex2');
like(http_get('/complex2?b=abababX'), qr/ab_replaced/, 'complex2 long');
like(http_get('/complex3?b=aab'), qr/_replaced/, 'complex3 aab in aab');
like(http_get('/complex3?b=aaab'), qr/a_replaced/, 'complex3 aab in aaab');
like(http_get('/complex3?b=aaaab'), qr/aa_replaced/, 'complex3 aab in aaaab');

like(http_get('/single?b=A'), qr/B/, 'single only');
like(http_get('/single?b=AA'), qr/BA/, 'single begin');
like(http_get('/single?b=CAAC'), qr/CBAC/, 'single middle');
like(http_get('/single?b=CA'), qr/CB/, 'single end');

like(http_get('/single/many?b=A'), qr/B/, 'single many only');
like(http_get('/single/many?b=AA'), qr/BB/, 'single many begin');
like(http_get('/single/many?b=CAAC'), qr/CBBC/, 'single many middle');
like(http_get('/single/many?b=CA'), qr/CB/, 'single many end');

like(http_get('/var/string?a=foo&b=Xfoo'), qr/_replaced/, 'complex string');
like(http_get('/var/string?a=foo&b=XFOO'), qr/_replaced/,
	'complex string caseless');
like(http_get('/var/string?a=abcdefghijklmnopq&b=Xabcdefghijklmnopq'),
	qr/_replaced/, 'complex string long');

like(http_get('/var/replacement?a=ee&b=aaab'), qr/aee_replaced/,
	'complex replacement');

unlike(http_get('/foo.html'), qr/(Last-Modified|ETag)/, 'no last modified');
like(http_get('/lm/foo.html'), qr/Last-Modified/, 'last modified');
like(http_get('/lm/foo.html'), qr!ETag: W/"[^"]+"!, 'last modified weak');

###############################################################################
