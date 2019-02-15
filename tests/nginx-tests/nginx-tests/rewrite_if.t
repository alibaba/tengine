#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for rewrite "if" condition.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(33)
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
            if ($arg_c) {
                return 204;
            }
        }

        location /sp {
            if ( $arg_c ) {
                return 204;
            }
        }

        location /eq {
            if ($arg_c = 1) {
                return 204;
            }
        }

        location /not {
            if ($arg_c != 2) {
                return 204;
            }
        }

        location /pos {
            if ($arg_c ~ foo) {
                return 204;
            }
        }

        location /cpos {
            if ($arg_c ~* foo) {
                return 204;
            }
        }

        location /neg {
            if ($arg_c !~ foo) {
                return 204;
            }
        }

        location /cneg {
            if ($arg_c !~* foo) {
                return 204;
            }
        }

        location /plain {
            if (-f %%TESTDIR%%/$arg_c) {
                return 204;
            }
        }

        location /dir {
            if (-d %%TESTDIR%%/$arg_c) {
                return 204;
            }
        }

        location /exist {
            if (-e %%TESTDIR%%/$arg_c) {
                return 204;
            }
        }

        location /exec {
            if (-x %%TESTDIR%%/$arg_c) {
                return 204;
            }
        }

        location /not_plain {
            if (!-f %%TESTDIR%%/$arg_c) {
                return 204;
            }
        }

        location /not_dir {
            if (!-d %%TESTDIR%%/$arg_c) {
                return 204;
            }
        }

        location /not_exist {
            if (!-e %%TESTDIR%%/$arg_c) {
                return 204;
            }
        }

        location /not_exec {
            if (!-x %%TESTDIR%%/$arg_c) {
                return 204;
            }
        }
    }
}

EOF

$t->write_file('file', '');
mkdir($t->testdir() . '/dir');

$t->run();

###############################################################################

like(http_get('/?c=1'), qr/ 204 /, 'var');
unlike(http_get('/?c=0'), qr/ 204 /, 'false');
like(http_get('/sp?c=1'), qr/ 204 /, 'spaces');

like(http_get('/eq?c=1'), qr/ 204 /, 'equal');
unlike(http_get('/eq?c=2'), qr/ 204 /, 'equal false');
like(http_get('/not?c=1'), qr/ 204 /, 'not equal');
unlike(http_get('/not?c=2'), qr/ 204 /, 'not equal false');

like(http_get('/pos?c=food'), qr/ 204 /, 'match');
like(http_get('/cpos?c=FooD'), qr/ 204 /, 'match case');
like(http_get('/neg?c=FooD'), qr/ 204 /, 'match negative');
like(http_get('/cneg?c=bar'), qr/ 204 /, 'match negative case');

unlike(http_get('/pos?c=FooD'), qr/ 204 /, 'mismatch');
unlike(http_get('/cpos?c=bar'), qr/ 204 /, 'mismatch case');
unlike(http_get('/neg?c=food'), qr/ 204 /, 'mismatch negative');
unlike(http_get('/cneg?c=FooD'), qr/ 204 /, 'mismatch negative case');

like(http_get('/plain?c=file'), qr/ 204 /, 'plain file');
unlike(http_get('/plain?c=dir'), qr/ 204 /, 'plain dir');
unlike(http_get('/not_plain?c=file'), qr/ 204 /, 'not plain file');
like(http_get('/not_plain?c=dir'), qr/ 204 /, 'not plain dir');

unlike(http_get('/dir/?c=file'), qr/ 204 /, 'directory file');
like(http_get('/dir?c=dir'), qr/ 204 /, 'directory dir');
like(http_get('/not_dir?c=file'), qr/ 204 /, 'not directory file');
unlike(http_get('/not_dir?c=dir'), qr/ 204 /, 'not directory dir');

like(http_get('/exist?c=file'), qr/ 204 /, 'exist file');
like(http_get('/exist?c=dir'), qr/ 204 /, 'exist dir');
unlike(http_get('/exist?c=nx'), qr/ 204 /, 'exist non-existent');
unlike(http_get('/not_exist?c=file'), qr/ 204 /, 'not exist file');
unlike(http_get('/not_exist?c=dir'), qr/ 204 /, 'not exist dir');
like(http_get('/not_exist?c=nx'), qr/ 204 /, 'not exist non-existent');

SKIP: {
skip 'no exec on win32', 4 if $^O eq 'MSWin32';

unlike(http_get('/exec?c=file'), qr/ 204 /, 'executable file');
like(http_get('/exec?c=dir'), qr/ 204 /, 'executable dir');
like(http_get('/not_exec?c=file'), qr/ 204 /, 'not executable file');
unlike(http_get('/not_exec?c=dir'), qr/ 204 /, 'not executable dir');

}

###############################################################################
