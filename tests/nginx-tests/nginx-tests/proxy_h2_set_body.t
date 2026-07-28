#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for proxy_set_body.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy rewrite/)
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

        http2 on;
        proxy_http_version 2;

        location / {
            proxy_pass http://127.0.0.1:8080/body;
            proxy_set_body "body";
        }

        location /p1 {
            proxy_pass http://127.0.0.1:8080/x1;
            proxy_set_body "body";
        }

        location /p2 {
            proxy_pass http://127.0.0.1:8080/body;
            proxy_set_body "body two";
        }

        location /x1 {
            add_header X-Accel-Redirect /p2;
            return 204;
        }

        location /body {
            add_header X-Body $request_body;
            proxy_pass http://127.0.0.1:8080/empty;
        }

        location /empty {
            return 204;
        }
    }
}

EOF

$t->try_run('no proxy_http_version 2')->plan(2);

###############################################################################

like(http_get('/'), qr/x-body: body/, 'proxy_set_body');
like(http_get('/p1'), qr/x-body: body two/, 'proxy_set_body twice');

###############################################################################
