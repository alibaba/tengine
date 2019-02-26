#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx limit_req module, multiple limits.

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

my $t = Test::Nginx->new()->has(qw/http limit_req/)->plan(14);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $arg_a  zone=slow:1m   rate=1r/m;
    limit_req_zone  $arg_b  zone=fast:1m   rate=1000r/s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            limit_req    zone=fast;
            limit_req    zone=slow;
        }

        location /t2.html {
            limit_req    zone=fast  nodelay;
            limit_req    zone=slow  nodelay;

            alias %%TESTDIR%%/t1.html;
        }
    }
}

EOF

$t->write_file('t1.html', 'XtestX');
$t->run();

###############################################################################

like(http_get('/t1.html?b=1'), qr/^HTTP\/1.. 200 /m, 'fast');
select undef, undef, undef, 0.1;
like(http_get('/t1.html?b=1'), qr/^HTTP\/1.. 200 /m, 'fast - passed');

like(http_get('/t1.html?a=1'), qr/^HTTP\/1.. 200 /m, 'slow');
select undef, undef, undef, 0.1;
like(http_get('/t1.html?a=1'), qr/^HTTP\/1.. 503 /m, 'slow - rejected');

like(http_get('/t1.html?a=2&b=2'), qr/^HTTP\/1.. 200 /m, 'both');
select undef, undef, undef, 0.1;
like(http_get('/t1.html?a=2&b=2'), qr/^HTTP\/1.. 503 /m, 'both - rejected');

like(http_get('/t1.html'), qr/^HTTP\/1.. 200 /m, 'no key');
like(http_get('/t1.html'), qr/^HTTP\/1.. 200 /m, 'no key - passed');

# nodelay

like(http_get('/t2.html?b=3'), qr/^HTTP\/1.. 200 /m, 'nodelay fast');
select undef, undef, undef, 0.1;
like(http_get('/t2.html?b=3'), qr/^HTTP\/1.. 200 /m, 'nodelay fast - passed');

like(http_get('/t2.html?a=3'), qr/^HTTP\/1.. 200 /m, 'nodelay slow');
select undef, undef, undef, 0.1;
like(http_get('/t2.html?a=3'), qr/^HTTP\/1.. 503 /m, 'nodelay slow - rejected');

like(http_get('/t2.html?a=4&b=4'), qr/^HTTP\/1.. 200 /m, 'nodelay both');
select undef, undef, undef, 0.1;
like(http_get('/t2.html?a=4&b=4'), qr/^HTTP\/1.. 503 /m,
	'nodelay both - rejected');

###############################################################################
