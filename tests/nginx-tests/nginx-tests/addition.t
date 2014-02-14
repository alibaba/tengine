#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for addition module.

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

my $t = Test::Nginx->new()->has(qw/http rewrite addition/)->plan(9);

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

        location /regular {
            return 200 "body";
        }

        location /b.html {
            add_before_body /add_before;
            return 200 "body";
        }

        location /a.html {
            add_after_body /add_after;
            return 200 "body";
        }

        location /ba.html {
            add_before_body /add_before;
            add_after_body /add_after;
            return 200 "body";
        }

        location /notype {
            add_before_body /add_before;
            add_after_body /add_after;
            return 200 "body";
        }

        location /notype2 {
            addition_types text/plain;
            add_after_body /add_after;
            return 200 "body";
        }

        location /notype.html {
            types {}
            add_before_body /add_before;
            return 200 "body";
        }

        location /add_before {
            return 200 "before";
        }

        location /add_after {
            return 200 "after";
        }

        location /self.html {
            add_after_body /self.html;
            return 200 "self";
        }

        location /return202.html {
            add_after_body /add_after;
            return 202 "body";
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/regular'), qr/^body$/ms, 'no addition');
like(http_get('/b.html'), qr/^beforebody$/ms, 'add_before');
like(http_get('/a.html'), qr/^bodyafter$/ms, 'add_after');
like(http_get('/ba.html'), qr/^beforebodyafter$/ms, 'both');
like(http_get('/notype'), qr/^body$/ms, 'no content type');
like(http_get('/notype2'), qr/^bodyafter$/ms, 'addition_types');
like(http_get('/notype.html'), qr/^body$/ms, 'empty content type');
like(http_get('/self.html'), qr/^selfself$/ms, 'self');
like(http_get('/return202.html'), qr/HTTP\/1.. 202.*^body$/ms, 'not 200');

###############################################################################
