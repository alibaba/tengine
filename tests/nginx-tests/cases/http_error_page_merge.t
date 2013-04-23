#!/usr/bin/perl

# Tests for error_page directive (inherit).

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(16);

$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    error_page       403 /403.html;
    error_page       404 /404.html;
    error_page       400 /h400.html;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        error_page       400 /s400.html;

        location /inherit400 {
            return 400;
        }

        location /my400 {
            error_page 400 /l400.html;
            return 400;
        }

        location /default400 {
            error_page 400 default;
            return 400;
        }

        location /default_all_400 {
            error_page default;
            return 400;
        }

        location /inherit403 {
            return 403;
        }

        location /inherit404 {
            return 404;
        }

        location /default403 {
            error_page 403 default;
            return 403;
        }

        location /default404 {
            error_page 404 default;
            return 404;
        }

        location /my403 {
            error_page 403 /new403.html;
            return 403;
        }

        location /my404 {
            error_page 404 /new404.html;
            return 404;
        }

        location /default_all_403 {
            error_page default; 
            return 403;
        }

        location /default_all_404 {
            error_page default; 
            return 404;
        }
    }
}

EOF

$t->write_file('h400.html', 'http400');
$t->write_file('s400.html', 'server400');
$t->write_file('l400.html', 'location400');
$t->write_file('403.html', 'http403');
$t->write_file('404.html', 'http404');
$t->write_file('new403.html', 'location403');
$t->write_file('new404.html', 'location404');

$t->run();

###############################################################################

like(http_get('/inherit400'), qr/server400/, '400 - inherited from upper level');
like(http_get('/default400'), qr/html/, '400 - nginx');
like(http_get('/my400'), qr/location400/, '400 - nginx');
like(http_get('/default_all_400'), qr/html/, '400 - default all');
like(http_get('/inherit403'), qr/http403/, '403 - inherited from upper level');
like(http_get('/inherit404'), qr/http404/, '404 - inherited from upper level');
like(http_get('/default403'), qr/html/, '403 - nginx');
like(http_get('/default404'), qr/html/, '404 - nginx');
like(http_get('/my403'), qr/location403/, '403 - overrided');
like(http_get('/my404'), qr/location404/, '404 - overrided');
like(http_get('/default_all_403'), qr/html/, '403 - default all');
like(http_get('/default_all_404'), qr/html/, '404 - default all');

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    error_page       403 /403.html;
    error_page       404 /404.html;
    error_page       400 /h400.html;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        error_page       default;

        location /inherit400 {
            return 400;
        }

        location /my400 {
            error_page 400 /l400.html;
            return 400;
        }

        location /default400 {
            error_page 400 default;
            return 400;
        }

        location /default_all_400 {
            error_page default;
            return 400;
        }
    }
}

EOF

$t->run();
like(http_get('/inherit400'), qr/html/, '400 - inherited from upper level');
like(http_get('/default400'), qr/html/, '400 - nginx');
like(http_get('/my400'), qr/location400/, '400 - nginx');
like(http_get('/default_all_400'), qr/html/, '400 - default all');
$t->stop();
###############################################################################
