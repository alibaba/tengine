#!/usr/bin/perl

# (C) Maxim Dounin
# (C) flygoast

# Tests for numeric comparison of 'if' directive in rewrite module.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t1 {
            if ($arg_a > "123456") {
                return 511;
            }
            return 200;
        }

        location /t2 {
            if ($arg_a < "123456") {
                return 512;
            }
            return 200;
        }

        location /t3 {
            if ($arg_a > $arg_b) {
                return 513;
            }
            return 200;
        }

        location /t4 {
            if ($arg_a < $arg_b) {
                return 514;
            }
            return 200;
        }

        location /t5 {
            if ($arg_a >= $arg_b) {
                return 515;
            }
            return 200;
        }

        location /t6 {
            if ($arg_a <= $arg_b) {
                return 516;
            }
            return 200;
        }
    }
}

EOF

mkdir($t->testdir() . '/directory');

$t->run();

###############################################################################

like(http_get('/t1?a=1234567'), qr/^HTTP.*511/,
    "arg_a greater than constant 123456");

like(http_get('/t2?a=12345'), qr/^HTTP.*512/,
    "arg_a less than constant 123456");

like(http_get('/t3?a=654321&b=123456'), qr/^HTTP.*513/,
    "arg_a greater than arg_b");

like(http_get('/t4?a=123456&b=654321'), qr/^HTTP.*514/,
    "arg_a less than arg_b");

like(http_get('/t5?a=123456&b=123456'), qr/^HTTP.*515/,
    "arg_a greater than or equal arg_b");

like(http_get('/t5?a=654321&b=123456'), qr/^HTTP.*515/,
    "arg_a greater than or equal arg_b");

like(http_get('/t6?a=123456&b=123456'), qr/^HTTP.*516/,
    "arg_a less than or equal arg_b");

like(http_get('/t6?a=123456&b=654321'), qr/^HTTP.*516/,
    "arg_a less than or equal arg_b");

###############################################################################
