#!/usr/bin/perl

# (C) Sergey Kandaurov

# Tests for nginx access module.

# At the moment only the new "unix:" syntax is tested (cf "all").

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

my $t = Test::Nginx->new()->has(qw/http proxy access ipv6/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /inet/ {
            proxy_pass http://127.0.0.1:8081/;
        }

        location /inet6/ {
            proxy_pass http://[::1]:8081/;
        }

        location /unix/ {
            proxy_pass http://unix:%%TESTDIR%%/unix.sock:/;
        }

    }

    server {
        listen       127.0.0.1:8081;
        listen       [::1]:8081;
        listen       unix:%%TESTDIR%%/unix.sock;

        location /allow_all {
            allow all;
        }

        location /allow_unix {
            allow unix:;
        }

        location /deny_all {
            deny all;
        }

        location /deny_unix {
            deny unix:;
        }
    }
}

EOF

$t->try_run('no inet6 and/or unix support')->plan(12);

###############################################################################

# tests with inet socket

like(http_get('/inet/allow_all'), qr/404 Not Found/, 'inet allow all');
like(http_get('/inet/allow_unix'), qr/404 Not Found/, 'inet allow unix');
like(http_get('/inet/deny_all'), qr/403 Forbidden/, 'inet deny all');
like(http_get('/inet/deny_unix'), qr/404 Not Found/, 'inet deny unix');

# tests with inet6 socket

like(http_get('/inet6/allow_all'), qr/404 Not Found/, 'inet6 allow all');
like(http_get('/inet6/allow_unix'), qr/404 Not Found/, 'inet6 allow unix');
like(http_get('/inet6/deny_all'), qr/403 Forbidden/, 'inet6 deny all');
like(http_get('/inet6/deny_unix'), qr/404 Not Found/, 'inet6 deny unix');

# tests with unix socket

like(http_get('/unix/allow_all'), qr/404 Not Found/, 'unix allow all');
like(http_get('/unix/allow_unix'), qr/404 Not Found/, 'unix allow unix');
like(http_get('/unix/deny_all'), qr/403 Forbidden/, 'unix deny all');
like(http_get('/unix/deny_unix'), qr/403 Forbidden/, 'unix deny unix');

###############################################################################
