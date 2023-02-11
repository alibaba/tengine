#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for limit_conn_dry_run directive, limit_conn_status variable.

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

my $t = Test::Nginx->new()->has(qw/http proxy limit_conn limit_req/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone   $binary_remote_addr  zone=req:1m rate=30r/m;
    limit_conn_zone  $binary_remote_addr  zone=zone:1m;

    log_format test $uri:$limit_conn_status;

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location /w {
            limit_req  zone=req burst=10;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Status $limit_conn_status always;
        access_log %%TESTDIR%%/test.log test;

        location /reject {
            proxy_pass http://127.0.0.1:8081/w;
            limit_conn zone 1;
        }

        location /dry {
            limit_conn zone 1;
            limit_conn_dry_run on;
        }

        location / { }
    }
}

EOF

$t->write_file('w', '');
$t->run()->plan(6);

###############################################################################

like(http_get('/reject'), qr/ 200 .*PASSED/s, 'passed');

my $s = http_get('/reject', start => 1);
like(http_get('/reject'), qr/ 503 .*REJECTED(?!_)/s, 'rejected');
like(http_get('/dry'), qr/ 404 .*REJECTED_DRY_RUN/s, 'rejected dry run');
unlike(http_get('/'), qr/X-Status/, 'no limit');

close $s;

$t->stop();

like($t->read_file('error.log'), qr/limiting connections, dry/, 'log dry run');
like($t->read_file('test.log'), qr|^/:-|m, 'log not found');

###############################################################################
