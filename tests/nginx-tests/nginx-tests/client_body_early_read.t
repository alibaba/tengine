#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for client_body_early_read directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/);

plan(skip_all => 'not yet') unless $t->has_version('1.31.5');

$t->write_file_expand('nginx.conf', <<'EOF')->plan(24);

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    client_body_early_read 1;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_max_body_size 256;

        location / {
            return 200 "body:$request_body";
        }

        location /less {
            client_max_body_size 10;
            return 200 "body:$request_body";
        }

        location /more {
            client_max_body_size 512;
            return 200 "body:$request_body";
        }

        location /proxy {
            add_header X-Body $request_body;
            proxy_pass http://127.0.0.1:8083;
        }

        location /single {
            client_body_in_single_buffer on;
            add_header X-Body $request_body;
            proxy_pass http://127.0.0.1:8083;
        }

        location /loc1 {
            return 200 "loc1:$request_body";
        }

        location /rewrite {
            rewrite ^ /loc1 last;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        client_body_early_read $arg_on;

        location / {
            return 200 "body:$request_body";
        }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;

        client_body_buffer_size 16;

        location / {
            add_header X-Body $request_body;
            add_header X-Body-File $request_body_file;
            proxy_pass http://127.0.0.1:8083;
        }
    }

    server {
        listen       127.0.0.1:8083;
        server_name  localhost;

        location / {
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_post_body('/', '0123456789', 8080), qr/body:0123456789/,
	'body via return');
like(http_post_body('/', '0123456789', 8081), qr/body:$/,
	'no early read - body not available');
like(http_post_body('/?on=1', '0123456789', 8081), qr/body:0123456789/,
	'early read - body available');
like(http_post_body('/?on=0', '0123456789', 8081), qr/body:$/,
	'early read - body not available when 0');
like(http_post_body('/?on=00', '0123456789', 8081), qr/body:0123456789/,
	'early read - body available when non-0');
like(http_post_body('/proxy', '0123456789', 8080),
	qr/X-Body: 0123456789\x0d?$/ms, 'body via proxy');
like(http_get('/'), qr/body:$/, 'no body');
like(http_post_body('/', '', 8080), qr/body:$/, 'empty body');
like(http_post_body('/', 'x' x 300, 8080), qr/ 413 /,
	'body exceeds limit');
like(http_post_body('/', 'x' x 256, 8080), qr/body:x{256}/,
	'body at exact limit');
like(http_post_body('/less', 'x' x 11, 8080), qr/ 413 /,
	'location limit applies not server');
like(http_post_body('/more', 'x' x 300, 8080), qr/ 413 /,
	'server limit applies not location');
like(http_post_body('/', '0123456789' x 100000, 8082), qr/ 204 /,
	'big body and small buffer size');

like(http_post_chunked('/', '0123456789', 8080), qr/body:0123456789/,
	'chunked body early read');
like(http_post_chunked('/less', '0123456789' x 5, 8080), qr/ 413 /,
	'chunked body exceeds limit');

like(http_post_body('/', '0123456789', 8082),
	qr/X-Body: 0123456789\x0d?$/ms, 'body in buffer');
like(http_post_body('/', '0123456789' x 100, 8082),
	qr/X-Body-File/ms, 'body in file');
like(http_post_body('/single', '0123456789' x 12, 8080),
	qr/X-Body: (0123456789){12}\x0d?$/ms, 'body in single buffer');

like(http_pipelined('/', '0123456789', 'foobar', 8080),
	qr/body:0123456789.*body:foobar/s, 'pipelined early read');
like(http_pipelined('/', '0123456789' x 12, 'foobar', 8080),
	qr/body:(0123456789){12}.*body:foobar/s, 'pipelined mixed sizes');

like(http_expect('/', '0123456789', 8080), qr/100 Continue.*200/s,
	'expect continue');
my $r = http_expect('/', 'x' x 300, 8080);
like($r, qr/ 413 /, 'expect continue too large');
unlike($r, qr/100 Continue/, 'expect continue too large - no 100');

like(http_post_body('/rewrite', 'HELLO', 8080), qr/loc1:HELLO/,
	'early read body survives rewrite');

###############################################################################

sub http_post_body {
	my ($uri, $body, $port) = @_;
	return http(
		"POST $uri HTTP/1.0" . CRLF
		. "Host: localhost" . CRLF
		. "Content-Length: " . length($body) . CRLF . CRLF
		. $body,
		PeerAddr => '127.0.0.1:' . port($port)
	);
}

sub http_post_chunked {
	my ($uri, $body, $port) = @_;
	return http(
		"POST $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Transfer-Encoding: chunked" . CRLF . CRLF
		. sprintf("%x", length $body) . CRLF
		. $body . CRLF
		. "0" . CRLF . CRLF,
		PeerAddr => '127.0.0.1:' . port($port)
	);
}

sub http_pipelined {
	my ($uri, $body1, $body2, $port) = @_;
	return http(
		"POST $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Content-Length: " . length($body1) . CRLF . CRLF
		. $body1
		. "POST $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Content-Length: " . length($body2) . CRLF . CRLF
		. $body2,
		PeerAddr => '127.0.0.1:' . port($port)
	);
}

sub http_expect {
	my ($uri, $body, $port) = @_;
	return http(
		"POST $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Expect: 100-continue" . CRLF
		. "Content-Length: " . length($body) . CRLF . CRLF,
		PeerAddr => '127.0.0.1:' . port($port),
		body => $body
	);
}

###############################################################################
