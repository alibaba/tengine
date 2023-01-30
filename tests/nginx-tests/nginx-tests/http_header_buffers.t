#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for large_client_header_buffers directive.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(10)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    connection_pool_size 128;
    client_header_buffer_size 128;

    server {
        listen       127.0.0.1:8080;
        server_name  five;

        large_client_header_buffers 5 256;

        return 204;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  ten;

        large_client_header_buffers 10 256;

        return 204;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  one;

        large_client_header_buffers 1 256;

        return 204;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  foo;

        large_client_header_buffers 5 256;

        add_header X-URI $uri;
        add_header X-Foo $http_x_foo;
        return 204;
    }
}

EOF

$t->run();

###############################################################################

TODO: {
todo_skip 'overflow', 2 unless $ENV{TEST_NGINX_UNSAFE};

# if hc->busy is allocated before the virtual server is selected,
# and then additional buffers are allocated in a virtual server with larger
# number of buffers configured, hc->busy will be overflowed

like(http(
	"GET / HTTP/1.0" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"Host: ten" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF
), qr/204|400/, 'additional buffers in virtual server');

# for pipelined requests large header buffers are saved to hc->free;
# it sized for number of buffers in the current virtual server, but
# saves previously allocated buffers, and there may be more buffers if
# allocatad before the virtual server was selected

like(http(
	"GET / HTTP/1.1" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"Host: one" . CRLF .
	CRLF .
	"GET / HTTP/1.1" . CRLF .
	"Host: one" . CRLF .
	"Connection: close" . CRLF .
	CRLF
), qr/204/, 'pipelined with too many buffers');

}

# check if long header and long request lines are correctly returned
# when nginx allocates a long header buffer

like(http(
	"GET / HTTP/1.0" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: foo" . ("1234567890" x 20) . "bar" . CRLF .
	CRLF
), qr/X-Foo: foo(1234567890){20}bar/, 'long header');

like(http(
	"GET /foo" . ("1234567890" x 20) . "bar HTTP/1.0" . CRLF .
	"Host: foo" . CRLF .
	CRLF
), qr!X-URI: /foo(1234567890){20}bar!, 'long request line');

# the same as the above, but with pipelining, so there is a buffer
# allocated in the previous request

like(http(
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF .
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"Connection: close" . CRLF .
	"X-Foo: foo" . ("1234567890" x 20) . "bar" . CRLF .
	CRLF
), qr/X-Foo: foo(1234567890){20}bar/, 'long header after pipelining');

like(http(
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF .
	"GET /foo" . ("1234567890" x 20) . "bar HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"Connection: close" . CRLF .
	CRLF
), qr!X-URI: /foo(1234567890){20}bar!, 'long request line after pipelining');

# the same as the above, but with keepalive; this ensures that previously
# allocated buffers are properly cleaned up when we set keepalive handler

like(http(
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF,
sleep => 0.1, body =>
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"Connection: close" . CRLF .
	"X-Foo: foo" . ("1234567890" x 20) . "bar" . CRLF .
	CRLF
), qr/X-Foo: foo(1234567890){20}bar/, 'long header after keepalive');

like(http(
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF,
sleep => 0.1, body =>
	"GET /foo" . ("1234567890" x 20) . "bar HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"Connection: close" . CRLF .
	CRLF
), qr!X-URI: /foo(1234567890){20}bar!, 'long request line after keepalive');

# the same as the above, but with pipelining and then keepalive;
# this ensures that previously allocated buffers are properly cleaned
# up when we set keepalive handler, including hc->free

like(http(
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF .
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF,
sleep => 0.1, body =>
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"Connection: close" . CRLF .
	"X-Foo: foo" . ("1234567890" x 20) . "bar" . CRLF .
	CRLF
), qr/X-Foo: foo(1234567890){20}bar/, 'long header after both');

like(http(
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF .
	"GET / HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"X-Foo: " . ("1234567890" x 20) . CRLF .
	CRLF,
sleep => 0.1, body =>
	"GET /foo" . ("1234567890" x 20) . "bar HTTP/1.1" . CRLF .
	"Host: foo" . CRLF .
	"Connection: close" . CRLF .
	CRLF
), qr!X-URI: /foo(1234567890){20}bar!, 'long request line after both');

###############################################################################
