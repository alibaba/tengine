#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for range filter on proxied response with charset.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy cache charset/)->plan(10)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    charset_map B A {
        58 59; # X -> Y
    }

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;
            proxy_cache_valid 200 1m;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        charset B;

        location /t2.html {
            add_header X-Accel-Charset A;
        }
    }
}

EOF

$t->write_file('t1.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->write_file('t2.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->run();

###############################################################################

my $t1;

# range request on proxied response with charset attribute in content-type
# NB: to get partial content, requests need to be served from cache

http_get('/t1.html');
$t1 = http_get_range('/t1.html', 'Range: bytes=0-9, 10-19');
like($t1, qr/206/, 'charset - 206 partial reply');
like($t1, qr/Content-Type: multipart\/byteranges; boundary=\w+\x0d\x0a/,
	'charset - content type');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.11');

like($t1, qr/Content-Type: text\/html; charset=B(?!; charset)/,
	'charset - charset attribute');
}

like($t1, qr/X000XXXXXX/m, 'charset - content 0-9');
like($t1, qr/X001XXXXXX\x0d?$/m, 'charset - content 10-19');

http_get('/t2.html');
$t1 = http_get_range('/t2.html', 'Range: bytes=0-9, 10-19');
like($t1, qr/206/, 'x-accel-charset - 206 partial reply');
like($t1, qr/Content-Type: multipart\/byteranges; boundary=\w+\x0d\x0a/,
	'x-accel-charset - content type');
like($t1, qr/Content-Type: text\/html; charset=A(?!; charset)/,
	'x-accel-charset - charset attribute');
like($t1, qr/Y000YYYYYY/m, 'x-accel-charset - content 0-9');
like($t1, qr/Y001YYYYYY\x0d?$/m, 'x-accel-charset - content 10-19');

###############################################################################

sub http_get_range {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

###############################################################################
