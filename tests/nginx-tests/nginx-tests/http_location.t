#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for location selection.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(14)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = / {
            add_header X-Location exactlyroot;
            return 204;
        }

        location / {
            add_header X-Location root;
            return 204;
        }

        location ^~ /images/ {
            add_header X-Location images;
            return 204;
        }

        location ~* \.(gif|jpg|jpeg)$ {
            add_header X-Location regex;
            return 204;
        }

        location ~ casefull {
            add_header X-Location casefull;
            return 204;
        }

        location = /foo {
            add_header X-Location "/foo exact";
            return 204;
        }

        location /foo {
            add_header X-Location "/foo prefix";
            return 204;
        }

        location = /foo/ {
            add_header X-Location "/foo/ exact";
            return 204;
        }

        location /foo/ {
            add_header X-Location "/foo/ prefix";
            return 204;
        }

        location /lowercase {
            add_header X-Location lowercase;
            return 204;
        }

        location /UPPERCASE {
            add_header X-Location uppercase;
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/'), qr/X-Location: exactlyroot/, 'exactlyroot');
like(http_get('/x'), qr/X-Location: root/, 'root');
like(http_get('/images/t.gif'), qr/X-Location: images/, 'images');
like(http_get('/t.gif'), qr/X-Location: regex/, 'regex');
like(http_get('/t.GIF'), qr/X-Location: regex/, 'regex with mungled case');
like(http_get('/casefull/t.gif'), qr/X-Location: regex/, 'first regex wins');
like(http_get('/casefull/'), qr/X-Location: casefull/, 'casefull regex');

like(http_get('/foo'), qr!X-Location: /foo exact!, '/foo exact');
like(http_get('/foobar'), qr!X-Location: /foo prefix!, '/foo prefix');
like(http_get('/foo/'), qr!X-Location: /foo/ exact!, '/foo/ exact');
like(http_get('/foo/bar'), qr!X-Location: /foo/ prefix!, '/foo/ prefix');

SKIP: {
	skip 'caseless os', 1
		if $^O eq 'MSWin32' or $^O eq 'darwin';

	like(http_get('/CASEFULL/'), qr/X-Location: root/,
		'casefull regex do not match wrong case');
}

# on case-insensitive systems a request to "/UPPERCASE" fails,
# as location search tree is incorrectly sorted if uppercase
# characters are used in location directives (ticket #90)

like(http_get('/lowercase'), qr/X-Location: lowercase/, 'lowercase');

TODO: {
local $TODO = 'fails on caseless oses'
	if ($^O eq 'MSWin32' or $^O eq 'darwin') and !$t->has_version('1.5.6');

like(http_get('/UPPERCASE'), qr/X-Location: uppercase/, 'uppercase');

}

###############################################################################
