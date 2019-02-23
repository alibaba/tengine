#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for nginx post_action directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(5);

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

        location / {
            post_action /post.html;
        }

        location /post.html {
            # static
        }

        location /remote {
            post_action /post.remote;
        }

        location /post.remote {
            proxy_pass http://127.0.0.1:8080/post.html;
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');
$t->write_file('post.html', 'HIDDEN');
$t->write_file('remote', 'SEE-THIS');

$t->run();

###############################################################################

like(http_get('/'), qr/SEE-THIS/m, 'post action');
unlike(http_get('/'), qr/HIDDEN/m, 'no additional body');

like(http_get('/remote'), qr/SEE-THIS/m, 'post action proxy');
unlike(http_get('/remote'), qr/HIDDEN/m, 'no additional body proxy');

$t->stop();

like(`cat ${\($t->testdir())}/access.log`, qr/post/, 'post action in logs');

###############################################################################
