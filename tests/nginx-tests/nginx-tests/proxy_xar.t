#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for proxy X-Accel-Redirect functionality.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /proxy {
            proxy_pass http://127.0.0.1:8080/return-xar;
        }
        location /return-xar {
            add_header  X-Accel-Redirect     /index.html;

            # this headers will be preserved on
            # X-Accel-Redirect

            add_header  Content-Type         text/blah;
            add_header  Set-Cookie           blah=blah;
            add_header  Content-Disposition  attachment;
            add_header  Cache-Control        no-cache;
            add_header  Expires              fake;
            add_header  Accept-Ranges        parrots;

            # others won't be
            add_header  Something            other;

            return 204;
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');
$t->run();

###############################################################################

my $r = http_get('/proxy');
like($r, qr/SEE-THIS/, 'X-Accel-Redirect works');
like($r, qr/^Content-Type: text\/blah/m, 'Content-Type preserved');
like($r, qr/^Set-Cookie: blah=blah/m, 'Set-Cookie preserved');
like($r, qr/^Content-Disposition: attachment/m, 'Content-Disposition preserved');
like($r, qr/^Cache-Control: no-cache/m, 'Cache-Control preserved');
like($r, qr/^Expires: fake/m, 'Expires preserved');
like($r, qr/^Accept-Ranges: parrots/m, 'Accept-Ranges preserved');
unlike($r, qr/^Something/m, 'other headers stripped');

###############################################################################
