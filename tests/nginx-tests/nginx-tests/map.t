#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for map module.

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

my $t = Test::Nginx->new()->has(qw/http map/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $args $x {
        default      0;
        foo          bar;
    }

    map $args $y {
        hostnames;
        default      0;
        example.com  foo;
        example.*    wildcard;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-Foo "x:$x y:$y\n";
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->run();

###############################################################################

like(http_get('/?1'), qr/x:0 y:0/, 'map default');
like(http_get('/?foo'), qr/x:bar y:0/, 'map foo bar');
like(http_get('/?example.com'), qr/x:0 y:foo/, 'map example.com foo');
like(http_get('/?example.org'), qr/x:0 y:wild/, 'map example.org wildcard');
like(http_get('/?example.com.'), qr/x:0 y:foo/, 'map example.com. foo');

###############################################################################
