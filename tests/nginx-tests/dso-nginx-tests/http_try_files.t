#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for try_files directive.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(4);

$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

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

        location / {
            try_files $uri /fallback;
        }

        location /nouri/ {
            try_files $uri /fallback_nouri;
        }

        location /short/ {
            try_files /short $uri =404;
        }

        location /fallback {
            proxy_pass http://127.0.0.1:8081/fallback;
        }
        location /fallback_nouri {
            proxy_pass http://127.0.0.1:8081;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-URI $request_uri;
            return 204;
        }
    }
}

EOF

$t->write_file('found.html', 'SEE THIS');
$t->run();

###############################################################################

like(http_get('/found.html'), qr!SEE THIS!, 'found');
like(http_get('/uri/notfound'), qr!X-URI: /fallback!, 'not found uri');
like(http_get('/nouri/notfound'), qr!X-URI: /fallback!, 'not found nouri');
like(http_get('/short/long'), qr!404 Not!, 'short uri in try_files');

###############################################################################
