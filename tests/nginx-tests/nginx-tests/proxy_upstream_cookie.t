#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for the $upstream_cookie_<name> variables.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(19);

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
            add_header X-Upstream-Cookie $upstream_cookie_tc;
            proxy_pass http://127.0.0.1:8081;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header Set-Cookie $http_x_test_cookie;
            return 204;
        }

        # embed multiline cookie with add_header
        location /mcomma {
            add_header Set-Cookie "tc=one,two,three";
            add_header Set-Cookie "tc=four,five,six";
            return 204;
        }
        location /msemicolon {
            add_header Set-Cookie "tc=one;two;three";
            add_header Set-Cookie "tc=four;five;six";
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

is(http_get_uc('tc='), undef, 'value_none');
is(http_get_uc('tc=;'), undef, 'semicolon');
is(http_get_uc('tc= ;'), undef, 'space_semicolon');
is(http_get_uc('tc =   ; Domain=example.com;'), undef, 'space_semicolon_more');

is(http_get_uc('tc=x'), 'x', 'onechar');
is(http_get_uc('tc=,'), ',', 'comma');
is(http_get_uc('tc	=	content     ;'), undef, 'tabbed');
is(http_get_uc('tc="content"'), '"content"', 'dquoted');
is(http_get_uc('tc=content'), 'content', 'normal');
is(http_get_uc('tc=con  tent; Domain=example.com'), 'con  tent',
	'internal_space');
is(http_get_uc('tc = content'), 'content', 'separated');

is(http_get_uc('tc=1.2.3'), '1.2.3', 'dots');
is(http_get_uc('tc==abc'), '=abc', 'deq');
is(http_get_uc('tc==;abc'), '=', 'deqsemi');
is(http_get_uc('=tc=content'), undef, 'eqfirst');
is(http_get_uc('tc=first,tc=second'), 'first,tc=second', 'two_comma');
is(http_get_uc('tc=first;tc=second'), 'first', 'two_semicolon');

like(http_get('/mcomma'), qr/^X-Upstream-Cookie: one,two,three\x0d?$/mi,
	'multiline comma');
like(http_get('/msemicolon'), qr/^X-Upstream-Cookie: one\x0d?$/mi,
	'multiline semicolon');

###############################################################################

sub http_get_uc {
	my ($cookie) = @_;

	http(<<EOF) =~ qr/^X-Upstream-Cookie:\s(.+?)\x0d?$/mi;
GET / HTTP/1.1
Host: localhost
Connection: close
X-Test-Cookie: $cookie

EOF

	return $1;
}

###############################################################################
