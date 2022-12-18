#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for handling of multiple http headers and access via variables.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http rewrite proxy/)->plan(42);

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
            add_header X-Forwarded-For $http_x_forwarded_for;
            add_header X-Cookie $http_cookie;
            add_header X-Foo $http_foo;

            add_header X-Cookie-Foo $cookie_foo;
            add_header X-Cookie-Bar $cookie_bar;
            add_header X-Cookie-Bazz $cookie_bazz;

            return 204;
        }

        location /s {
            add_header Cache-Control foo;
            add_header Cache-Control bar;
            add_header Cache-Control bazz;

            add_header Link foo;
            add_header Link bar;
            add_header Link bazz;

            add_header Foo foo;
            add_header Foo bar;
            add_header Foo bazz;

            add_header X-Sent-CC $sent_http_cache_control;
            add_header X-Sent-Link $sent_http_link;
            add_header X-Sent-Foo $sent_http_foo;

            return 204;
        }

        location /t {
            add_trailer Foo foo;
            add_trailer Foo bar;
            add_trailer Foo bazz;
            add_trailer X-Sent-Trailer-Foo $sent_trailer_foo;

            return 200 "";
        }

        location /v {
            add_header X-Forwarded-For $http_x_forwarded_for;
            add_header X-Cookie $http_cookie;

            add_header X-HTTP-Host $http_host;
            add_header X-User-Agent $http_user_agent;
            add_header X-Referer $http_referer;
            add_header X-Via $http_via;

            add_header X-Content-Length $content_length;
            add_header X-Content-Type $content_type;
            add_header X-Host $host;
            add_header X-Remote-User $remote_user;

            return 204;
        }

        location /d {
            return 204;
        }

        location /u {
            add_header X-Upstream-Set-Cookie $upstream_http_set_cookie;
            add_header X-Upstream-Bar $upstream_http_bar;

            add_header X-Upstream-Cookie-Foo $upstream_cookie_foo;
            add_header X-Upstream-Cookie-Bar $upstream_cookie_bar;
            add_header X-Upstream-Cookie-Bazz $upstream_cookie_bazz;

            proxy_pass http://127.0.0.1:8080/backend;
        }

        location /backend {
            add_header Set-Cookie foo=1;
            add_header Set-Cookie bar=2;
            add_header Set-Cookie bazz=3;
            add_header Bar foo;
            add_header Bar bar;
            add_header Bar bazz;
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

# combining multiple headers:
#
# $http_cookie, $http_x_forwarded_for, $sent_http_cache_control,
# and $sent_http_link with special handling, other headers with
# general handling

# request headers, $http_*

like(get('/', map { "X-Forwarded-For: $_" } qw/ foo bar bazz /),
	qr/X-Forwarded-For: foo, bar, bazz/, 'multi $http_x_forwarded_for');
like(get('/', 'Cookie: foo=1', 'Cookie: bar=2', 'Cookie: bazz=3'),
	qr/X-Cookie: foo=1; bar=2; bazz=3/, 'multi $http_cookie');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like(get('/', 'Foo: foo', 'Foo: bar', 'Foo: bazz'),
	qr/X-Foo: foo, bar, bazz/, 'multi $http_foo');

}

# request cookies, $cookie_*

my $r = get('/', 'Cookie: foo=1', 'Cookie: bar=2', 'Cookie: bazz=3');

like($r, qr/X-Cookie-Foo: 1/, '$cookie_foo');
like($r, qr/X-Cookie-Bar: 2/, '$cookie_bar');
like($r, qr/X-Cookie-Bazz: 3/, '$cookie_bazz');

# response headers, $http_*

$r = get('/s');

like($r, qr/X-Sent-CC: foo, bar, bazz/, 'multi $sent_http_cache_control');
like($r, qr/X-Sent-Link: foo, bar, bazz/, 'multi $sent_http_link');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like($r, qr/X-Sent-Foo: foo, bar, bazz/, 'multi $sent_http_foo');

}

# upstream response headers, $upstream_http_*

$r = get('/u');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like($r, qr/X-Upstream-Set-Cookie: foo=1, bar=2, bazz=3/,
	'multi $upstream_http_set_cookie');
like($r, qr/X-Upstream-Bar: foo, bar, bazz/, 'multi $upstream_http_bar');

}

# upstream response cookies, $upstream_cookie_*

like($r, qr/X-Upstream-Cookie-Foo: 1/, '$upstream_cookie_foo');
like($r, qr/X-Upstream-Cookie-Bar: 2/, '$upstream_cookie_bar');
like($r, qr/X-Upstream-Cookie-Bazz: 3/, '$upstream_cookie_bazz');

# response trailers, $sent_trailer_*

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like(get('/t'), qr/X-Sent-Trailer-Foo: foo, bar, bazz/,
	'multi $sent_trailer_foo');

}

# various variables for request headers:
#
# $http_host, $http_user_agent, $http_referer
# multiple Host, User-Agent, Referer headers are invalid, but we currently
# reject only requests with multiple Host headers
#
# $http_via, $http_x_forwarded_for, $http_cookie
# multiple headers are valid

like(get('/v'), qr/X-HTTP-Host: localhost/, '$http_host');
like(get('/v', 'Host: foo', 'Host: bar'),
	qr/400 Bad/, 'duplicate host rejected');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like(get('/v', 'User-Agent: foo', 'User-Agent: bar'),
	qr/X-User-Agent: foo, bar/, 'multi $http_user_agent (invalid)');
like(get('/v', 'Referer: foo', 'Referer: bar'),
	qr/X-Referer: foo, bar/, 'multi $http_referer (invalid)');
like(get('/v', 'Via: foo', 'Via: bar', 'Via: bazz'),
	qr/X-Via: foo, bar, bazz/, 'multi $http_via');

}

like(get('/v', 'Cookie: foo', 'Cookie: bar', 'Cookie: bazz'),
	qr/X-Cookie: foo; bar; bazz/, 'multi $http_cookie');
like(get('/v', 'X-Forwarded-For: foo', 'X-Forwarded-For: bar',
	'X-Forwarded-For: bazz'),
	qr/X-Forwarded-For: foo, bar, bazz/, 'multi $http_x_forwarded_for');

# other variables related to request headers:
#
# $content_length, $content_type, $host, $remote_user

like(get('/v', 'Content-Length: 0'),
	qr/X-Content-Length: 0/, '$content_length');
like(get('/v', 'Content-Length: 0', 'Content-Length: 0'),
	qr/400 Bad/, 'duplicate Content-Length rejected');

like(get('/v', 'Content-Type: foo'),
	qr/X-Content-Type: foo/, '$content_type');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like(get('/v', 'Content-Type: foo', 'Content-Type: bar'),
	qr/X-Content-Type: foo, bar/, 'multi $content_type (invalid)');

}

like(http("GET /v HTTP/1.0" . CRLF . CRLF),
	qr/X-Host: localhost/, '$host from server_name');
like(http("GET /v HTTP/1.0" . CRLF . "Host: foo" . CRLF . CRLF),
	qr/X-Host: foo/, '$host');
like(http("GET /v HTTP/1.0" . CRLF . "Host: foo" . CRLF .
	"Host: bar" . CRLF . CRLF),
	qr/400 Bad/, 'duplicate host rejected');

like(get('/v', 'Authorization: Basic dXNlcjpzZWNyZXQ='),
	qr/X-Remote-User: user/, '$remote_user');
like(get('/v', 'Authorization: Basic dXNlcjpzZWNyZXQ=',
	'Authorization: Basic dXNlcjpzZWNyZXQ='),
	qr/400 Bad/, 'duplicate authorization rejected');

# request headers required to be unique:
#
# Host, If-Modified-Since, If-Unmodified-Since, If-Match, If-None-Match,
# Content-Length, Content-Range, If-Range, Transfer-Encoding, Expect,
# Authorization

like(get('/d', 'Host: foo', 'Host: bar'),
	qr/400 Bad/, 'duplicate Host rejected');
like(get('/d', 'If-Modified-Since: foo', 'If-Modified-Since: bar'),
	qr/400 Bad/, 'duplicate If-Modified-Since rejected');
like(get('/d', 'If-Unmodified-Since: foo', 'If-Unmodified-Since: bar'),
	qr/400 Bad/, 'duplicate If-Unmodified-Since rejected');
like(get('/d', 'If-Match: foo', 'If-Match: bar'),
	qr/400 Bad/, 'duplicate If-Match rejected');
like(get('/d', 'If-None-Match: foo', 'If-None-Match: bar'),
	qr/400 Bad/, 'duplicate If-None-Match rejected');
like(get('/d', 'Content-Length: 0', 'Content-Length: 0'),
	qr/400 Bad/, 'duplicate Content-Length rejected');
like(get('/d', 'Content-Range: foo', 'Content-Range: bar'),
	qr/400 Bad/, 'duplicate Content-Range rejected');
like(get('/d', 'If-Range: foo', 'If-Range: bar'),
	qr/400 Bad/, 'duplicate If-Range rejected');
like(get('/d', 'Transfer-Encoding: foo', 'Transfer-Encoding: bar'),
	qr/400 Bad/, 'duplicate Transfer-Encoding rejected');
like(get('/d', 'Expect: foo', 'Expect: bar'),
	qr/400 Bad/, 'duplicate Expect rejected');
like(get('/d', 'Authorization: foo', 'Authorization: bar'),
	qr/400 Bad/, 'duplicate Authorization rejected');

###############################################################################

sub get {
	my ($url, @headers) = @_;
	return http(
		"GET $url HTTP/1.1" . CRLF .
		'Host: localhost' . CRLF .
		'Connection: close' . CRLF .
		join(CRLF, @headers) . CRLF . CRLF
	);
}

###############################################################################
