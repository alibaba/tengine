#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for charset filter.

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

my $t = Test::Nginx->new()->has(qw/http charset proxy/)->plan(7)
	->write_file_expand('nginx.conf', <<'EOF')->run();

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html html;
        text/foo  foo;
    }

    charset_map B A {
        58 59; # X -> Y
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            charset utf-8;
        }

        location /t3.foo {
            charset utf-8;
            charset_types text/foo;
        }

        location /t4.any {
            charset utf-8;
            charset_types *;
        }

        location /t5.html {
            charset $arg_c;
        }

        location /t.html {
            charset A;
            source_charset B;
        }

        location /proxy/ {
            charset B;
            override_charset on;
            proxy_pass http://127.0.0.1:8080/;
        }
    }
}

EOF

$t->write_file('t1.html', '');
$t->write_file('t2.foo', '');
$t->write_file('t3.foo', '');
$t->write_file('t4.any', '');
$t->write_file('t5.html', '');
$t->write_file('t.html', 'X' x 99);

###############################################################################

like(http_get('/t1.html'), qr!text/html; charset=utf-8!, 'charset indicated');
like(http_get('/t2.foo'), qr!text/foo\x0d!, 'wrong type');
like(http_get('/t3.foo'), qr!text/foo; charset=utf-8!, 'charset_types');
like(http_get('/t4.any'), qr!text/plain; charset=utf-8!, 'charset_types any');
like(http_get('/t5.html?c=utf-8'), qr!text/html; charset=utf-8!, 'variables');

like(http_get('/t.html'), qr!Y{99}!, 'recode');
like(http_get('/proxy/t.html'), qr!X{99}!, 'override charset');

###############################################################################
