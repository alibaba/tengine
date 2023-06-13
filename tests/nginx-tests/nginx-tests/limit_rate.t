#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for limit_rate and limit_rate_after directives.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format test escape=none $uri:$arg_a$arg_xal:$upstream_response_time;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8081;
            access_log %%TESTDIR%%/test.log test;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        limit_rate 12k;
        limit_rate_after 256;

        location /data {
            add_header X-Accel-Redirect $arg_xar;
            add_header X-Accel-Limit-Rate $arg_xal;
        }

        location /redirect {
            limit_rate 0;
            alias %%TESTDIR%%/data;
        }

        location /var {
            alias %%TESTDIR%%/data;
            limit_rate $arg_l;
            limit_rate_after $arg_a;
        }

        location /proxy/ {
            proxy_pass http://127.0.0.1:8081/;
        }
    }
}

EOF

$t->write_file('data', 'X' x 30000);
$t->run()->plan(7);

###############################################################################

# NB: response time may be 1s less, if timer is scheduled on upper half second

like(http_get('/data'), qr/^(XXXXXXXXXX){3000}\x0d?\x0a?$/m, 'response body');
like($t->read_file('test.log'), qr/data::[12]/, 'limit_rate');

# /proxy -> /redirect
# before 1.17.0, limit was set once in ngx_http_update_location_config()

http_get('/proxy/data?xar=/redirect');
like($t->read_file('test.log'), qr!proxy/data::0!, 'X-Accel-Redirect');

# X-Accel-Limit-Rate has higher precedence

http_get('/proxy/data?xar=/redirect&xal=13000');
like($t->read_file('test.log'), qr!roxy/data:13000:[12]!, 'X-Accel-Limit-Rate');

http_get('/var?l=12k&a=256');
like($t->read_file('test.log'), qr/var:256:[12]/, 'variable');

http_get('/var?l=12k&a=40k');
like($t->read_file('test.log'), qr/var:40k:0/, 'variable after');

http_get('/var');
like($t->read_file('test.log'), qr/var::0/, 'variables unset');

###############################################################################
