#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx limit_req module, limit_req_dry_run directive.

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

my $t = Test::Nginx->new()->has(qw/http limit_req/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $binary_remote_addr  zone=one:1m   rate=1r/m;

    log_format test $uri:$limit_req_status;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        limit_req_dry_run  on;
        add_header X-Status $limit_req_status always;
        access_log %%TESTDIR%%/test.log test;

        location /delay {
            limit_req    zone=one  burst=2;
        }

        location /reject {
            limit_req    zone=one;
        }

        location /reject/off {
            limit_req    zone=one;

            limit_req_dry_run off;
        }

        location / { }
    }
}

EOF

$t->write_file('delay', 'SEE-THIS');
$t->write_file('reject', 'SEE-THIS');
$t->run()->plan(8);

###############################################################################

like(http_get('/delay'), qr/ 200 .*PASSED/ms, 'dry run - passed');
like(http_get('/delay'), qr/ 200 .*DELAYED_DRY_RUN/ms, 'dry run - delayed');
like(http_get('/reject'), qr/ 200 .*REJECTED_DRY_RUN/ms, 'dry run - rejected');

like(http_get('/reject/off'), qr/ 503 .*REJECTED/ms, 'dry run off - rejected');

unlike(http_get('/'), qr/X-Status/, 'no limit');

$t->stop();

like($t->read_file('error.log'), qr/delaying request, dry/, 'log - delay');
like($t->read_file('error.log'), qr/limiting requests, dry/, 'log - reject');

like($t->read_file('test.log'), qr|^/:-|m, 'log - not found');

###############################################################################
