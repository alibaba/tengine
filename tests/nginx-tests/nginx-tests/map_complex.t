#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for map module with complex value.

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

my $t = Test::Nginx->new()->has(qw/http map rewrite/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $args $x {
        var      foo:$y;
        var2     $y:foo;
        default  foo:$y;
    }

    map $args $y {
        default  bar;
        same     baz;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-Foo $x;
            return 204;
        }
    }
}

EOF

$t->run()->plan(3);

###############################################################################

like(http_get('/?var'), qr/foo:bar/, 'map cv');
like(http_get('/?var2'), qr/bar:foo/, 'map cv 2');
like(http_get('/?same'), qr/foo:baz/, 'map cv key');

###############################################################################
