#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx dav module with chunked request body.

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

my $t = Test::Nginx->new()->has(qw/http dav/)->plan(6);

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

        client_header_buffer_size 1k;
        client_body_buffer_size 2k;

        location / {
            dav_methods PUT;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_put_chunked('/file', '1234567890'),
	qr/201 Created.*(Content-Length|\x0d\0a0\x0d\x0a)/ms, 'put chunked');
is($t->read_file('file'), '1234567890', 'put content');

like(http_put_chunked('/file', ''), qr/204 No Content/, 'put chunked empty');
is($t->read_file('file'), '', 'put empty content');

like(http_put_chunked('/file', '1234567890', 1024),
	qr/204 No Content/, 'put chunked big');
is($t->read_file('file'), '1234567890' x 1024, 'put big content');

###############################################################################

sub http_put_chunked {
	my ($url, $body, $count) = @_;
	my $length = sprintf("%x", length $body);
	$body = $length ? $length . CRLF . $body . CRLF : '';
	$body x= ($count || 1);
	$body .= '0' . CRLF . CRLF;
	return http(<<EOF . $body);
PUT $url HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

EOF
}

###############################################################################
