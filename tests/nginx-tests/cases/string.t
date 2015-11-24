#!/usr/bin/perl

# Tests for string.c.

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

my $t = Test::Nginx->new()->plan(4);

$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");
$t->set_dso("ngx_http_upstream_ip_hash_module", "ngx_http_upstream_ip_hash_module.so");
$t->set_dso("ngx_http_upstream_least_conn_module", "ngx_http_upstream_least_conn_module.so");

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /good {
            #output: s%20elect
            rewrite .* http://127.0.0.1/s%20elect;
        }

        location /good1 {
            #output: s&elect
            rewrite .* http://127.0.0.1/s%26elect;
        }

        location /invalid {
            #output: s%elect
            rewrite .* http://127.0.0.1/s%elect;
        }

        location /invalid1 {
            #output: se%lect
            rewrite .* http://127.0.0.1/se%lect;
        }
    }
}

EOF

$t->write_file('index.html', 'hello, tengine!');

$t->run();

###############################################################################

like(http_get('/good'), qr/s%20elect/, 'good');
like(http_get('/good1'), qr/s&elect/,  'good1');
like(http_get('/invalid'), qr/sect/, 'invalid');
like(http_get('/invalid1'), qr/se%lect/, 'invalid1');

###############################################################################
