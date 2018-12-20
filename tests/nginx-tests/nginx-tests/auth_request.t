#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for auth request module.

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

my $t = Test::Nginx->new()
	->has(qw/http rewrite proxy cache fastcgi auth_basic auth_request/)
	->plan(19);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            return 444;
        }

        location /open {
            auth_request /auth-open;
        }
        location = /auth-open {
            return 204;
        }

        location /open-static {
            auth_request /auth-open-static;
        }
        location = /auth-open-static {
            # nothing, use static file
        }

        location /unauthorized {
            auth_request /auth-unauthorized;
        }
        location = /auth-unauthorized {
            return 401;
        }

        location /forbidden {
            auth_request /auth-forbidden;
        }
        location = /auth-forbidden {
            return 403;
        }

        location /error {
            auth_request /auth-error;
        }
        location = /auth-error {
            return 404;
        }

        location /off {
            auth_request off;
        }

        location /proxy {
            auth_request /auth-proxy;
        }
        location = /auth-proxy {
            proxy_pass http://127.0.0.1:8080/auth-basic;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
        }
        location = /auth-basic {
            auth_basic "restricted";
            auth_basic_user_file %%TESTDIR%%/htpasswd;
        }

        location = /proxy-double {
            proxy_pass http://127.0.0.1:8080/auth-error;
            proxy_intercept_errors on;
            error_page 404 = /proxy-double-fallback;
            client_body_buffer_size 4k;
        }
        location = /proxy-double-fallback {
            auth_request /auth-proxy-double;
            proxy_pass http://127.0.0.1:8080/auth-open;
        }
        location = /auth-proxy-double {
            proxy_pass http://127.0.0.1:8080/auth-open;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
        }

        location /proxy-cache {
            auth_request /auth-proxy-cache;
        }
        location = /auth-proxy-cache {
            proxy_pass http://127.0.0.1:8080/auth-basic;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_cache NAME;
            proxy_cache_valid 1m;
        }

        location /fastcgi {
            auth_request /auth-fastcgi;
        }
        location = /auth-fastcgi {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_pass_request_body off;
        }
    }
}

EOF

$t->write_file('htpasswd', 'user:{PLAIN}secret' . "\n");
$t->write_file('auth-basic', 'INVISIBLE');
$t->write_file('auth-open-static', 'INVISIBLE');
$t->run();

###############################################################################

like(http_get('/open'), qr/ 404 /, 'auth open');
like(http_get('/unauthorized'), qr/ 401 /, 'auth unauthorized');
like(http_get('/forbidden'), qr/ 403 /, 'auth forbidden');
like(http_get('/error'), qr/ 500 /, 'auth error');
like(http_get('/off'), qr/ 404 /, 'auth off');

like(http_post('/open'), qr/ 404 /, 'auth post open');
like(http_post('/unauthorized'), qr/ 401 /, 'auth post unauthorized');

like(http_get('/open-static'), qr/ 404 /, 'auth open static');
unlike(http_get('/open-static'), qr/INVISIBLE/, 'auth static no content');

like(http_get('/proxy'), qr/ 401 /, 'proxy auth unauthorized');
like(http_get('/proxy'), qr/WWW-Authenticate: Basic realm="restricted"/,
	'proxy auth has www-authenticate');
like(http_get_auth('/proxy'), qr/ 404 /, 'proxy auth pass');
unlike(http_get_auth('/proxy'), qr/INVISIBLE/, 'proxy auth no content');

like(http_post('/proxy'), qr/ 401 /, 'proxy auth post');

like(http_get_auth('/proxy-cache'), qr/ 404 /, 'proxy auth with cache');
like(http_get('/proxy-cache'), qr/ 404 /, 'proxy auth cached');

# Consider the following scenario:
#
# 1. proxy_pass reads request body, then goes to fallback via error_page
# 2. auth request uses proxy_pass, and upstream module closes request body file
#    in ngx_http_upstream_send_response()
# 3. oops: fallback has no body
#
# To prevent this we always allocate fake request body for auth request.
#
# Note that this doesn't happen when using header_only as relevant code
# in ngx_http_upstream_send_response() isn't reached.  It may be reached
# with proxy_cache or proxy_store, but they will shutdown client connection
# in case of header_only and hence do not work for us at all.

like(http_post_big('/proxy-double'), qr/ 204 /, 'proxy auth with body read');

SKIP: {
	eval { require FCGI; };
	skip 'FCGI not installed', 2 if $@;
	skip 'win32', 2 if $^O eq 'MSWin32';

	$t->run_daemon(\&fastcgi_daemon);
	$t->waitforsocket('127.0.0.1:' . port(8081));

	like(http_get('/fastcgi'), qr/ 404 /, 'fastcgi auth open');
	unlike(http_get('/fastcgi'), qr/INVISIBLE/, 'fastcgi auth no content');
}

###############################################################################

sub http_get_auth {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
Host: localhost
Authorization: Basic dXNlcjpzZWNyZXQ=

EOF
}

sub http_post {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 10" . CRLF .
		CRLF .
		"1234567890";

	return http($p, %extra);
}

sub http_post_big {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 10240" . CRLF .
		CRLF .
		("1234567890" x 1024);

	return http($p, %extra);
}

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:' . port(8081), 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	while ($request->Accept() >= 0) {
		print <<EOF;
Content-Type: text/html

INVISIBLE
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
