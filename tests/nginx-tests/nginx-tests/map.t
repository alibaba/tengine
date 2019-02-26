#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Andrey Zelenkov
# (C) Nginx, Inc.

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

my $t = Test::Nginx->new()->has(qw/http map rewrite/)->plan(19);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $args $x {
        default                     0;
        foo                         bar;
        foo2                        bar;
    }

    map $args $y {
        hostnames;
        default                     0;
        example.com                 foo;
        example.*                   right-wildcard;
        *.example.com               left-wildcard;
        .dot.example.com            special-wildcard;
        ~^REGEX.EXAMPLE\.ORG$       regex-sensitive;
        ~*^www.regex.example\.org$  regex-insensitive;
        \include                    include;
        server                      $server_name;
        var                         $z;
    }

    map $args $z {
        default                     0;
        var                         baz;
        include                     map.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-Foo "x:$x y:$y\n";
            return 204;
        }
        location /z {
            add_header X-Foo "z:$z\n";
            return 204;
        }
    }
}

EOF

$t->write_file('map.conf', "foo bar;");
$t->run();

###############################################################################

like(http_get('/?1'), qr/x:0 y:0/, 'map default');
like(http_get('/?foo'), qr/x:bar y:0/, 'map foo bar');
like(http_get('/?foo2'), qr/x:bar y:0/, 'map foo bar key');
like(http_get('/?example.com'), qr/x:0 y:foo/, 'map example.com foo');
like(http_get('/?EXAMPLE.COM'), qr/x:0 y:foo/, 'map EXAMPLE.COM foo');
like(http_get('/?example.com.'), qr/x:0 y:foo/, 'map example.com. foo');
like(http_get('/?example.org'), qr/x:0 y:right-wildcard/,
	'map example.org wildcard');
like(http_get('/?foo.example.com'), qr/x:0 y:left-wildcard/,
	'map foo.example.com wildcard');
like(http_get('/?foo.example.com.'), qr/x:0 y:left-wildcard/,
	'map foo.example.com. wildcard');
like(http_get('/?dot.example.com'), qr/x:0 y:special-wildcard/,
	'map dot.example.com special wildcard');
like(http_get('/?www.dot.example.com'), qr/x:0 y:special-wildcard/,
	'map www.dot.example.com special wildcard');
like(http_get('/?REGEX.EXAMPLE.ORG'), qr/x:0 y:regex-sensitive/,
	'map REGEX.EXAMPLE.ORG');
like(http_get('/?regex.example.org'), qr/x:0 y:0/,
	'map regex.example.org');
like(http_get('/?www.regex.example.org'), qr/x:0 y:regex-insensitive/,
	'map www.regex.example.org insensitive');
like(http_get('/?WWW.REGEX.EXAMPLE.ORG'), qr/x:0 y:regex-insensitive/,
	'map WWW.REGEX.EXAMPLE.ORG insensitive');
like(http_get('/?include'), qr/x:0 y:include/, 'map special parameter');
like(http_get('/?server'), qr/x:0 y:localhost/, 'map server_name variable');
like(http_get('/?var'), qr/x:0 y:baz/, 'map z variable');
like(http_get('/z?foo'), qr/z:bar/, 'include foo bar');

###############################################################################
