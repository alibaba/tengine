#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for nginx geo module, include directive.

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

my $t = Test::Nginx->new()->has(qw/http geo/);

plan(skip_all => 'not yet') until $t->has_version('1.29.8');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geo $geo_inc_wildcard {
        include       geo*.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-Giw  $geo_inc_wildcard;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('geo_inc_wildcard.conf', '127.0.0.0/8  loopback;');

$t->run()->plan(1);

###############################################################################

like(http_get('/'), qr/^X-Giw: loopback/m, 'geo include with wildcard');

###############################################################################
