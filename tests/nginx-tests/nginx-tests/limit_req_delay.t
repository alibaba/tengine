#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx limit_req module, delay parameter.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http limit_req/)->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone $binary_remote_addr zone=one:1m rate=30r/m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            limit_req zone=one delay=1 burst=2;
            add_header X-Time $request_time;
        }
    }
}

EOF

$t->write_file('delay.html', 'XtestX');
$t->run();

###############################################################################

like(http_get('/delay.html'), qr/^HTTP\/1.. 200 /m, 'request');
like(http_get('/delay.html'), qr/X-Time: 0.000/, 'not yet delayed');
my $s = http_get('/delay.html', start => 1, sleep => 0.2);
like(http_get('/delay.html'), qr/^HTTP\/1.. 503 /m, 'rejected');
like(http_end($s), qr/^HTTP\/1.. 200 .*X-Time: (?!0.000)/ms, 'delayed');

###############################################################################
