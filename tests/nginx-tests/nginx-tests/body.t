#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx request body reading.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(13);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8082;
        server 127.0.0.1:8080 backup;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_header_buffer_size 1k;

        location / {
            client_body_buffer_size 2k;
            add_header X-Body "$request_body";
            add_header X-Body-File "$request_body_file";
            proxy_pass http://127.0.0.1:8081;
        }
        location /b {
            client_body_buffer_size 2k;
            client_body_in_file_only on;
            add_header X-Body "$request_body";
            add_header X-Body-File "$request_body_file";
            proxy_pass http://127.0.0.1:8081;
        }
        location /small {
            client_body_in_file_only on;
            add_header X-Original-Uri "$request_uri";
            proxy_pass http://127.0.0.1:8080/;
        }
        location /single {
            client_body_in_single_buffer on;
            add_header X-Body "$request_body";
            add_header X-Body-File "$request_body_file";
            proxy_pass http://127.0.0.1:8081;
        }
        location /discard {
            return 200 "TEST\n";
        }
        location /next {
            proxy_pass http://u/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            return 200 "TEST\n";
        }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;

        location / {
            return 444;
        }
    }
}

EOF

$t->run();

###############################################################################

unlike(http_get('/'), qr/X-Body:/ms, 'no body');

like(http_get_body('/', '0123456789'),
	qr/X-Body: 0123456789\x0d?$/ms, 'body');

like(http_get_body('/', '0123456789' x 128),
	qr/X-Body: (0123456789){128}\x0d?$/ms, 'body in two buffers');

like(http_get_body('/', '0123456789' x 512),
	qr/X-Body-File/ms, 'body in file');

like(read_body_file(http_get_body('/b', '0123456789' x 512)),
	qr/^(0123456789){512}$/s, 'body in file only');

like(http_get_body('/single', '0123456789' x 128),
	qr/X-Body: (0123456789){128}\x0d?$/ms, 'body in single buffer');

# pipelined requests

like(http_get_body('/', '0123456789', '0123456789' x 128, '0123456789' x 512,
	'foobar'), qr/X-Body: foobar\x0d?$/ms, 'body pipelined');
like(http_get_body('/', '0123456789' x 128, '0123456789' x 512, '0123456789',
	'foobar'), qr/X-Body: foobar\x0d?$/ms, 'body pipelined 2');

like(http_get_body('/discard', '0123456789', '0123456789' x 128,
	'0123456789' x 512, 'foobar'), qr/(TEST.*){4}/ms,
	'body discard');
like(http_get_body('/discard', '0123456789' x 128, '0123456789' x 512,
	'0123456789', 'foobar'), qr/(TEST.*){4}/ms,
	'body discard 2');

# proxy with file only

like(http_get_body('/small', '0123456789'),
	qr/X-Body: 0123456789\x0d?$/ms, 'small body in file only');

# proxy with file only - reuse of r->header_in

like(
	http(
		'GET /small HTTP/1.0' . CRLF
		. 'Content-Length: 10' . CRLF . CRLF
		. '01234',
		sleep => 0.1,
		body => '56789'
	),
	qr!X-Body: 0123456789\x0d?\x0a.*X-Original-Uri: /small!ms,
	'small body in file only, not preread'
);

# proxy_next_upstream

like(http_get_body('/next', '0123456789'),
	qr/X-Body: 0123456789\x0d?$/ms, 'body next upstream');

###############################################################################

sub read_body_file {
	my ($r) = @_;
	return '' unless $r =~ m/X-Body-File: (.*)/;
	open FILE, $1
		or return "$!";
	local $/;
	my $content = <FILE>;
	close FILE;
	return $content;
}

sub http_get_body {
	my $uri = shift;
	my $last = pop;
	return http( join '', (map {
		my $body = $_;
		"GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Content-Length: " . (length $body) . CRLF . CRLF
		. $body
	} @_),
		"GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Content-Length: " . (length $last) . CRLF . CRLF
		. $last
	);
}

###############################################################################
