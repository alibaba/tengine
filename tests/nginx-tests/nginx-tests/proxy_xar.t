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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(15);

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

        # catch safe and unhandled unsafe URIs,
        # bypassed with redirect to named location
        if ($upstream_http_x_accel_redirect) {
            return 200 "xar: $upstream_http_x_accel_redirect uri: $uri";
        }

        location /proxy {
            proxy_pass http://127.0.0.1:8080/return-xar;
        }
        location /return-xar {
            add_header  X-Accel-Redirect     $arg_xar;

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
        location @named {
            return 200 "named xar: $upstream_http_x_accel_redirect uri: $uri";
        }
    }
}

EOF

$t->run();

###############################################################################

my $r = http_get('/proxy?xar=/index.html');
like($r, qr/xar: \/index.html uri: \/index.html/, 'X-Accel-Redirect works');
like($r, qr/^Content-Type: text\/blah/m, 'Content-Type preserved');
like($r, qr/^Set-Cookie: blah=blah/m, 'Set-Cookie preserved');
like($r, qr/^Content-Disposition: attachment/m, 'Content-Disposition preserved');
like($r, qr/^Cache-Control: no-cache/m, 'Cache-Control preserved');
like($r, qr/^Expires: fake/m, 'Expires preserved');
like($r, qr/^Accept-Ranges: parrots/m, 'Accept-Ranges preserved');
unlike($r, qr/^Something/m, 'other headers stripped');

# escaped characters

like(http_get('/proxy?xar=/foo?bar'), qr/200 OK.*xar: \/foo\?bar/s,
	'X-Accel-Redirect value unchanged');
unlike(http_get('/proxy?xar=..'), qr/200 OK/,
	'X-Accel-Redirect unsafe dotdot');
unlike(http_get('/proxy?xar=../foo'), qr/200 OK/,
	'X-Accel-Redirect unsafe dotdotsep');
unlike(http_get('/proxy?xar=/foo/..'), qr/200 OK/,
	'X-Accel-Redirect unsafe sepdotdot');
unlike(http_get('/proxy?xar=/foo/.%2e'), qr/200 OK/,
	'X-Accel-Redirect unsafe unescaped');
like(http_get('/proxy?xar=/foo%20bar'), qr/uri: \/foo bar/,
	'X-Accel-Redirect unescaped');

like(http_get('/proxy?xar=@named'),
	qr!200 OK.*named xar: \@named uri: /proxy!s, 'in named location');

###############################################################################
