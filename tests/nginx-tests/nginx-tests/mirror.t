#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http mirror module.

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

my $t = Test::Nginx->new()->has(qw/http mirror/)->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format test $uri;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            mirror /mirror;

            location /off {
                mirror off;
            }
        }

        location /many {
            mirror /mirror/1;
            mirror /mirror/2;
        }

        location /mirror {
            log_subrequest on;
            access_log test$args.log test;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('many', '');
$t->write_file('off', '');
$t->run();

###############################################################################

like(http_get('/index.html?1'), qr/200 OK/, 'request');
like(http_get('/?2'), qr/200 OK/, 'internal redirect');
like(http_get('/off?3'), qr/200 OK/, 'mirror off');
like(http_get('/many?4'), qr/200 OK/, 'mirror many');

$t->stop();

is($t->read_file('test1.log'), "/mirror\n", 'log - request');
is($t->read_file('test2.log'), "/mirror\n/mirror\n", 'log - redirect');
ok(!-e $t->testdir() . '/test3.log', 'log - mirror off');
is($t->read_file('test4.log'), "/mirror/1\n/mirror/2\n", 'log - mirror many');

###############################################################################
