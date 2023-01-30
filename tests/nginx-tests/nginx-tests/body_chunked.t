#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx request body reading, with chunked transfer-coding.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(18);

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
        location /single {
            client_body_in_single_buffer on;
            add_header X-Body "$request_body";
            add_header X-Body-File "$request_body_file";
            proxy_pass http://127.0.0.1:8081;
        }
        location /large {
            client_max_body_size 1k;
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

like(http_get_body('/large', '0123456789' x 128), qr/ 413 /, 'body too large');

# pipelined requests

like(http_get_body('/', '0123456789', '0123456789' x 128, '0123456789' x 512,
	'foobar'), qr/X-Body: foobar\x0d?$/ms, 'chunked body pipelined');
like(http_get_body('/', '0123456789' x 128, '0123456789' x 512, '0123456789',
	'foobar'), qr/X-Body: foobar\x0d?$/ms, 'chunked body pipelined 2');

like(http_get_body('/discard', '0123456789', '0123456789' x 128,
	'0123456789' x 512, 'foobar'), qr/(TEST.*){4}/ms,
	'chunked body discard');
like(http_get_body('/discard', '0123456789' x 128, '0123456789' x 512,
	'0123456789', 'foobar'), qr/(TEST.*){4}/ms,
	'chunked body discard 2');

# invalid chunks

like(
	http(
		'GET / HTTP/1.1' . CRLF
		. 'Host: localhost' . CRLF
		. 'Connection: close' . CRLF
		. 'Transfer-Encoding: chunked' . CRLF . CRLF
		. '4' . CRLF
		. 'SEE-THIS' . CRLF
		. '0' . CRLF . CRLF
	),
	qr/400 Bad/, 'runaway chunk'
);

like(
	http(
		'GET /discard HTTP/1.1' . CRLF
		. 'Host: localhost' . CRLF
		. 'Connection: close' . CRLF
		. 'Transfer-Encoding: chunked' . CRLF . CRLF
		. '4' . CRLF
		. 'SEE-THIS' . CRLF
		. '0' . CRLF . CRLF
	),
	qr/400 Bad/, 'runaway chunk discard'
);

# proxy_next_upstream

like(http_get_body('/next', '0123456789'),
	qr/X-Body: 0123456789\x0d?$/ms, 'body chunked next upstream');

# invalid Transfer-Encoding

like(http_transfer_encoding('identity'), qr/501 Not Implemented/,
	'transfer encoding identity');

like(http_transfer_encoding("chunked\nTransfer-Encoding: chunked"),
	qr/400 Bad/, 'transfer encoding repeat');

like(http_transfer_encoding('chunked, identity'), qr/501 Not Implemented/,
	'transfer encoding list');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.1');

like(http_transfer_encoding("chunked\nContent-Length: 5"), qr/400 Bad/,
	'transfer encoding with content-length');

}

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.2');

like(http_transfer_encoding("chunked", "1.0"), qr/400 Bad/,
	'transfer encoding in HTTP/1.0 requests');

}

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
		. "Transfer-Encoding: chunked" . CRLF . CRLF
		. sprintf("%x", length $body) . CRLF
		. $body . CRLF
		. "0" . CRLF . CRLF
	} @_),
		"GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Transfer-Encoding: chunked" . CRLF . CRLF
		. sprintf("%x", length $last) . CRLF
		. $last . CRLF
		. "0" . CRLF . CRLF
	);
}

sub http_transfer_encoding {
	my ($encoding, $version) = @_;
	$version ||= "1.1";

	http("GET / HTTP/$version" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Transfer-Encoding: $encoding" . CRLF . CRLF
		. "0" . CRLF . CRLF);
}

###############################################################################
