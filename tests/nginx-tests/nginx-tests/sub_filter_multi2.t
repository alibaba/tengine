#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for sub filter with variables in search patterns.

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

my $t = Test::Nginx->new()->has(qw/http rewrite sub/)
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

        location /var/replacement {
            sub_filter_once off;
            sub_filter '${arg_a}' '${arg_a}+';
            sub_filter '${arg_b}' '${arg_b}-';
            return 200 $arg_c;
        }

        location /var/replacement2 {
            sub_filter_once off;
            sub_filter '${arg_a}A${arg_b}'  +;
            sub_filter '${arg_c}AA${arg_d}' -;
            return 200 $arg_e;
        }
    }

}

EOF

$t->try_run('no multiple sub_filter')->plan(7);

###############################################################################

like(http_get('/var/replacement?a=a&b=b&c=abXYaXbZ'),
	qr/a\+b-XYa\+Xb-Z/, 'complex');
like(http_get('/var/replacement?a=patt&b=abyz&c=pattabyzXYpattXabyzZpatt'),
	qr/patt\+abyz-XYpatt\+Xabyz-Zpatt\+/, 'complex 2');
like(http_get('/var/replacement?a=a&b=b&c=ABXYAXBZ'),
	qr/a\+b-XYa\+Xb-Z/, 'case insensivity');
like(http_get('/var/replacement?b=b&c=abXYaXbZ'),
	qr/ab-XYaXb-Z/, 'one search string is empty');
like(http_get('/var/replacement?c=abXYaXbZ'),
	qr/abXYaXbZ/, 'all search strings are empty');
like(http_get('/var/replacement2?a=aaa&b=bbb&c=yy&d=zz&e=AaaaAbbbZyyAAzzY'),
	qr/A\+Z-Y/, 'multiple variables');
like(http_get('/var/replacement2?b=bbb&c=yy&e=AAbbbZyyAAY'),
	qr/A\+Z-Y/, 'multiple variables 2');

###############################################################################
