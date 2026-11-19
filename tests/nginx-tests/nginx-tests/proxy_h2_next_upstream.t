#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for request body to HTTP/2 backend on next upstream.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy rewrite/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u1 {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    upstream u2 {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    upstream u3 {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_body_buffer_size 8k;

        # sendfile_max_chunk 1024;

        location /1 {
            proxy_next_upstream http_404;
            proxy_pass http://u1/;
            proxy_http_version 2;
        }

        location /2 {
            proxy_next_upstream http_404;
            proxy_pass http://u2/;
            proxy_http_version 2;
        }

        location /3 {
            proxy_next_upstream http_404;
            proxy_pass http://u3/;
            proxy_http_version 2;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        http2 on;

        location / {
            return 404;
        }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;

        http2 on;

        location / {
            proxy_pass http://127.0.0.1:8082/discard;
        }

        location /discard {
            return 200;
        }
    }
}

EOF

$t->try_run('no proxy_http_version 2')->plan(3);

###############################################################################

# request body should be proxied correctly after switching to next upstream
# - in-memory request body sent in one output filter call in two input buffers
# - buffered request body sent in many output filter calls
# - buffered request body sent in many output filter calls + window update

like(http_get_body('/1', '0123456789' x 192), qr/200 OK/, 'body 1');

# bug: request body last_buf not cleared, fixed in 3afd85e4b (1.29.5)
# resulting in END_STREAM set prematurely on 1st DATA frame on next upstream

TODO: {
local $TODO = 'not yet' unless $t->read_file('nginx.conf') =~ /sendfile on/
	or $t->has_version('1.29.5');

like(http_get_body('/2', '0123456789' x 1024), qr/200 OK/, 'body 2');

}

# bug: if request body was not fully sent, it might remain in ctx->in,
# or in ctx->busy when limited with sendfile_max_chunk, fixed in cd12dc4f1

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.5');

like(http_get_body('/3', '0123456789' x 10240), qr/200 OK/, 'body 3');

}

###############################################################################

sub http_get_body {
	my ($uri, $body) = @_;
	return http(
		"GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Transfer-Encoding: chunked" . CRLF . CRLF
		. sprintf("%x", length $body) . CRLF
		. $body . CRLF
		. "0" . CRLF . CRLF
	);
}

###############################################################################
