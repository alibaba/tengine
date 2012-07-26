#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for proxy_store functionality.

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

my $t = Test::Nginx->new();

$t->write_file_expand('nginx.conf', <<'EOF')->has(qw/http proxy ssi/)->plan(7);

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /store- {
            proxy_pass http://127.0.0.1:8080/;
            proxy_store on;
        }
        location /ssi.html {
            ssi on;
        }
        location /index-nostore.html {
            add_header  X-Accel-Expires  0;
        }
        location /index-big.html {
            limit_rate  200k;
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');
$t->write_file('index-nostore.html', 'SEE-THIS');
$t->write_file('index-big.html', 'x' x (100 << 10));
$t->write_file('ssi.html',
	'<!--#include virtual="/store-index-big.html?1" -->' .
	'<!--#include virtual="/store-index-big.html?2" -->'
);
$t->run();

###############################################################################

like(http_get('/store-index.html'), qr/SEE-THIS/, 'proxy request');
ok(-e $t->testdir() . '/store-index.html', 'result stored');

like(http_get('/store-index-nostore.html'), qr/SEE-THIS/,
	'proxy request with x-accel-expires');

TODO: {
local $TODO = 'patch rejected';

ok(!-e $t->testdir() . '/store-index-nostore.html', 'result not stored');
}

ok(scalar @{[ glob $t->testdir() . '/proxy_temp/*' ]} == 0, 'no temp files');

http_get('/store-index-big.html', aborted => 1, sleep => 0.1);
sleep(1);

ok(scalar @{[ glob $t->testdir() . '/proxy_temp/*' ]} == 0,
	'no temp files after aborted request');

http_get('/ssi.html', aborted => 1, sleep => 0.1);
sleep(1);

ok(scalar @{[ glob $t->testdir() . '/proxy_temp/*' ]} == 0,
	'no temp files after aborted ssi');

###############################################################################
