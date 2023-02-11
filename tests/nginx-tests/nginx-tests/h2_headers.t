#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 headers.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy rewrite/)->plan(107)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2;
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082 http2 sndbuf=128;
        server_name  localhost;

        large_client_header_buffers 2 64k;

        location / {
            add_header X-Sent-Foo $http_x_foo;
            add_header X-Referer $http_referer;
            return 200;
        }
        location /frame_size {
            add_header X-LongHeader $arg_h;
            add_header X-LongHeader $arg_h;
            add_header X-LongHeader $arg_h;
            alias %%TESTDIR%%/t2.html;
        }
        location /continuation {
            add_header X-LongHeader $arg_h;
            add_header X-LongHeader $arg_h;
            add_header X-LongHeader $arg_h;
            return 200 body;

            location /continuation/204 {
                return 204;
            }
        }
        location /proxy/ {
            add_header X-UC-a $upstream_cookie_a;
            add_header X-UC-c $upstream_cookie_c;
            proxy_pass http://127.0.0.1:8083/;
            proxy_set_header X-Cookie-a $cookie_a;
            proxy_set_header X-Cookie-c $cookie_c;
        }
        location /proxy2/ {
            proxy_pass http://127.0.0.1:8081/;
        }
        location /set-cookie {
            add_header Set-Cookie a=b;
            add_header Set-Cookie c=d;
            return 200;
        }
        location /cookie {
            add_header X-Cookie $http_cookie;
            add_header X-Cookie-a $cookie_a;
            add_header X-Cookie-c $cookie_c;
            return 200;
        }
    }

    server {
        listen       127.0.0.1:8084 http2;
        server_name  localhost;

        large_client_header_buffers 4 512;
    }

    server {
        listen       127.0.0.1:8085 http2;
        server_name  localhost;

        large_client_header_buffers 1 512;
    }

    server {
        listen       127.0.0.1:8086 http2;
        server_name  localhost;

        underscores_in_headers on;
        add_header X-Sent-Foo $http_x_foo always;
    }

    server {
        listen       127.0.0.1:8087 http2;
        server_name  localhost;

        ignore_invalid_headers off;
        add_header X-Sent-Foo $http_x_foo always;
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8083));

# file size is slightly beyond initial window size: 2**16 + 80 bytes

$t->write_file('t1.html',
	join('', map { sprintf "X%04dXXX", $_ } (1 .. 8202)));

$t->write_file('t2.html', 'SEE-THIS');

###############################################################################

# 6.1. Indexed Header Field Representation

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'indexed header field');

# 6.2.1. Literal Header Field with Incremental Indexing

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 1, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 1, huff => 0 },
	{ name => ':path', value => '/', mode => 1, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 1, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal with indexing');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 1, huff => 1 },
	{ name => ':scheme', value => 'http', mode => 1, huff => 1 },
	{ name => ':path', value => '/', mode => 1, huff => 1 },
	{ name => ':authority', value => 'localhost', mode => 1, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal with indexing - huffman');

# 6.2.1. Literal Header Field with Incremental Indexing -- New Name

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 2, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 2, huff => 0 },
	{ name => ':path', value => '/', mode => 2, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 2, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal with indexing - new');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 2, huff => 1 },
	{ name => ':scheme', value => 'http', mode => 2, huff => 1 },
	{ name => ':path', value => '/', mode => 2, huff => 1 },
	{ name => ':authority', value => 'localhost', mode => 2, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal with indexing - new huffman');

# 6.2.2. Literal Header Field without Indexing

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 3, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 3, huff => 0 },
	{ name => ':path', value => '/', mode => 3, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 3, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal without indexing');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 3, huff => 1 },
	{ name => ':scheme', value => 'http', mode => 3, huff => 1 },
	{ name => ':path', value => '/', mode => 3, huff => 1 },
	{ name => ':authority', value => 'localhost', mode => 3, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal without indexing - huffman');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 3, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 3, huff => 0 },
	{ name => ':path', value => '/', mode => 3, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 3, huff => 0 },
	{ name => 'referer', value => 'foo', mode => 3, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'literal without indexing - multibyte index');
is($frame->{headers}->{'x-referer'}, 'foo',
	'literal without indexing - multibyte index value');

# 6.2.2. Literal Header Field without Indexing -- New Name

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 4, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 4, huff => 0 },
	{ name => ':path', value => '/', mode => 4, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 4, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal without indexing - new');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 4, huff => 1 },
	{ name => ':scheme', value => 'http', mode => 4, huff => 1 },
	{ name => ':path', value => '/', mode => 4, huff => 1 },
	{ name => ':authority', value => 'localhost', mode => 4, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'literal without indexing - new huffman');

# 6.2.3. Literal Header Field Never Indexed

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 5, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 5, huff => 0 },
	{ name => ':path', value => '/', mode => 5, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 5, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal never indexed');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 5, huff => 1 },
	{ name => ':scheme', value => 'http', mode => 5, huff => 1 },
	{ name => ':path', value => '/', mode => 5, huff => 1 },
	{ name => ':authority', value => 'localhost', mode => 5, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal never indexed - huffman');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 5, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 5, huff => 0 },
	{ name => ':path', value => '/', mode => 5, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 5, huff => 0 },
	{ name => 'referer', value => 'foo', mode => 5, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'literal never indexed - multibyte index');
is($frame->{headers}->{'x-referer'}, 'foo',
	'literal never indexed - multibyte index value');

# 6.2.3. Literal Header Field Never Indexed -- New Name

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 6, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 6, huff => 0 },
	{ name => ':path', value => '/', mode => 6, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 6, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal never indexed - new');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 6, huff => 1 },
	{ name => ':scheme', value => 'http', mode => 6, huff => 1 },
	{ name => ':path', value => '/', mode => 6, huff => 1 },
	{ name => ':authority', value => 'localhost', mode => 6, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal never indexed - new huffman');

# reuse literal with multibyte indexing

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'referer', value => 'foo', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-referer'}, 'foo', 'value with indexing - new');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 0 },
	{ name => 'referer', value => 'foo', mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-referer'}, 'foo', 'value with indexing - indexed');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x-foo', value => 'X-Bar', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Bar', 'name with indexing - new');

# reuse literal with multibyte indexing - reused name

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 0 },
	{ name => 'x-foo', value => 'X-Bar', mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Bar', 'name with indexing - indexed');

# reuse literal with multibyte indexing - reused name only

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 0 },
	{ name => 'x-foo', value => 'X-Baz', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Baz',
	'name with indexing - indexed name');

# response header field with characters not suitable for huffman encoding

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x-foo', value => '{{{{{', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, '{{{{{', 'rare chars');
like($s->{headers}, qr/\Q{{{{{/, 'rare chars - no huffman encoding');

# response header field with huffman encoding
# NB: implementation detail, not obligated

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x-foo', value => 'aaaaa', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'aaaaa', 'well known chars');
unlike($s->{headers}, qr/aaaaa/, 'well known chars - huffman encoding');

# response header field with huffman encoding - complete table mod \0, CR, LF
# first saturate with short-encoded characters (NB: implementation detail)

my $field = pack "C*", ((map { 97 } (1 .. 862)), 1 .. 9, 11, 12, 14 .. 255);

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x-foo', value => $field, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, $field, 'all chars');
unlike($s->{headers}, qr/abcde/, 'all chars - huffman encoding');

# 6.3.  Dynamic Table Size Update

# remove some indexed headers from the dynamic table
# by maintaining dynamic table space only for index 0
# 'x-foo' has index 0, and 'referer' has index 1

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'referer', value => 'foo', mode => 1 },
	{ name => 'x-foo', value => 'X-Bar', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

$sid = $s->new_stream({ table_size => 61, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => 'x-foo', value => 'X-Bar', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
isnt($frame, undef, 'updated table size - remaining index');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'referer', value => 'foo', mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame->{code}, 0x9, 'invalid index');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'unknown', value => 'foo', mode => 3 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame->{code}, 0x9, 'invalid index in literal header field');

# 5.4.1.  Connection Error Handling
#   An endpoint that encounters a connection error SHOULD first send a
#   GOAWAY frame <..>

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'invalid index - GOAWAY');

# RFC 7541, 2.3.3.  Index Address Space
#   Indices strictly greater than the sum of the lengths of both tables
#   MUST be treated as a decoding error.

# 4.3.  Header Compression and Decompression
#   A decoding error in a header block MUST be treated
#   as a connection error of type COMPRESSION_ERROR.

is($frame->{last_sid}, $sid, 'invalid index - GOAWAY last stream');
is($frame->{code}, 9, 'invalid index - GOAWAY COMPRESSION_ERROR');

# HPACK zero index

# RFC 7541, 6.1  Indexed Header Field Representation
#   The index value of 0 is not used.  It MUST be treated as a decoding
#   error if found in an indexed header field representation.

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => '', value => '', mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

ok($frame, 'zero index - GOAWAY');
is($frame->{code}, 9, 'zero index - GOAWAY COMPRESSION_ERROR');

# invalid table size update

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ table_size => 4097, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => 'x-foo', value => 'X-Bar', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'invalid table size - GOAWAY');
is($frame->{last_sid}, $sid, 'invalid table size - GOAWAY last stream');
is($frame->{code}, 9, 'invalid table size - GOAWAY COMPRESSION_ERROR');

# request header field with multiple values

# 8.1.2.5.  Compressing the Cookie Header Field
#   To allow for better compression efficiency, the Cookie header field
#   MAY be split into separate header fields <..>.

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/cookie', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'cookie', value => 'a=b', mode => 2},
	{ name => 'cookie', value => 'c=d', mode => 2}]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-cookie-a'}, 'b',
	'multiple request header fields - cookie');
is($frame->{headers}->{'x-cookie-c'}, 'd',
	'multiple request header fields - cookie 2');
is($frame->{headers}->{'x-cookie'}, 'a=b; c=d',
	'multiple request header fields - semi-colon');

# request header field with multiple values to HTTP backend

# 8.1.2.5.  Compressing the Cookie Header Field
#   these MUST be concatenated into a single octet string
#   using the two-octet delimiter of 0x3B, 0x20 (the ASCII string "; ")
#   before being passed into a non-HTTP/2 context, such as an HTTP/1.1
#   connection <..>

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/proxy/cookie', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'cookie', value => 'a=b', mode => 2 },
	{ name => 'cookie', value => 'c=d', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-cookie'}, 'a=b; c=d',
	'multiple request header fields proxied - semi-colon');
is($frame->{headers}->{'x-sent-cookie2'}, '',
	'multiple request header fields proxied - dublicate cookie');
is($frame->{headers}->{'x-sent-cookie-a'}, 'b',
	'multiple request header fields proxied - cookie 1');
is($frame->{headers}->{'x-sent-cookie-c'}, 'd',
	'multiple request header fields proxied - cookie 2');

# response header field with multiple values

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/set-cookie' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'set-cookie'}[0], 'a=b',
	'multiple response header fields - cookie');
is($frame->{headers}->{'set-cookie'}[1], 'c=d',
	'multiple response header fields - cookie 2');

# response header field with multiple values from HTTP backend

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/proxy/set-cookie' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'set-cookie'}[0], 'a=b',
	'multiple response header proxied - cookie');
is($frame->{headers}->{'set-cookie'}[1], 'c=d',
	'multiple response header proxied - cookie 2');
is($frame->{headers}->{'x-uc-a'}, 'b',
	'multiple response header proxied - upstream cookie');
is($frame->{headers}->{'x-uc-c'}, 'd',
	'multiple response header proxied - upstream cookie 2');

# CONTINUATION in response
# put three long header fields (not less than SETTINGS_MAX_FRAME_SIZE/2)
# to break header block into separate frames, one such field per frame

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/continuation?h=' . 'x' x 2**13 });

$frames = $s->read(all => [{ sid => $sid, fin => 0x4 }]);
my @data = grep { $_->{type} =~ "HEADERS|CONTINUATION" } @$frames;
my $data = $data[-1];
is(@{$data->{headers}{'x-longheader'}}, 3,
	'response CONTINUATION - headers');
is($data->{headers}{'x-longheader'}[0], 'x' x 2**13,
	'response CONTINUATION - header 1');
is($data->{headers}{'x-longheader'}[1], 'x' x 2**13,
	'response CONTINUATION - header 2');
is($data->{headers}{'x-longheader'}[2], 'x' x 2**13,
	'response CONTINUATION - header 3');
@data = sort { $a <=> $b } map { $_->{length} } @data;
cmp_ok($data[-1], '<=', 2**14, 'response CONTINUATION - max frame size');

# same but without response DATA frames

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/continuation/204?h=' . 'x' x 2**13 });

$frames = $s->read(all => [{ sid => $sid, fin => 0x4 }]);
@data = grep { $_->{type} =~ "HEADERS|CONTINUATION" } @$frames;
$data = $data[-1];
is(@{$data->{headers}{'x-longheader'}}, 3,
	'no body CONTINUATION - headers');
is($data->{headers}{'x-longheader'}[0], 'x' x 2**13,
	'no body CONTINUATION - header 1');
is($data->{headers}{'x-longheader'}[1], 'x' x 2**13,
	'no body CONTINUATION - header 2');
is($data->{headers}{'x-longheader'}[2], 'x' x 2**13,
	'no body CONTINUATION - header 3');
@data = sort { $a <=> $b } map { $_->{length} } @data;
cmp_ok($data[-1], '<=', 2**14, 'no body CONTINUATION - max frame size');

# response header block is always split by SETTINGS_MAX_FRAME_SIZE

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/continuation?h=' . 'x' x 2**15 });

$frames = $s->read(all => [{ sid => $sid, fin => 0x4 }]);
@data = grep { $_->{type} =~ "HEADERS|CONTINUATION" } @$frames;
@data = sort { $a <=> $b } map { $_->{length} } @data;
cmp_ok($data[-1], '<=', 2**14, 'response header frames limited');

# response header frame sent in parts

$s = Test::Nginx::HTTP2->new(port(8082));
$s->h2_settings(0, 0x5 => 2**17);

$sid = $s->new_stream({ path => '/frame_size?h=' . 'x' x 2**15 });
$frames = $s->read(all => [{ sid => $sid, fin => 0x4 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($frame, 'response header - parts');

SKIP: {
skip 'response header failed', 1 unless $frame;

is(length join('', @{$frame->{headers}->{'x-longheader'}}), 98304,
	'response header - headers');

}

# response header block split and sent in parts

$s = Test::Nginx::HTTP2->new(port(8082));
$sid = $s->new_stream({ path => '/continuation?h=' . 'x' x 2**15 });
$frames = $s->read(all => [{ sid => $sid, fin => 0x4 }]);

@data = grep { $_->{type} =~ "HEADERS|CONTINUATION" } @$frames;
ok(@data, 'response header split');

SKIP: {
skip 'response header split failed', 2 unless @data;

my ($lengths) = sort { $b <=> $a } map { $_->{length} } @data;
cmp_ok($lengths, '<=', 16384, 'response header split - max size');

is(length join('', @{$data[-1]->{headers}->{'x-longheader'}}), 98304,
	'response header split - headers');

}

# max_field_size - header field name

$s = Test::Nginx::HTTP2->new(port(8084));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x' x 511, value => 'value', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'field name size less');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x' x 511, value => 'value', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'field name size second');

$s = Test::Nginx::HTTP2->new(port(8084));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x' x 512, value => 'value', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'field name size equal');

$s = Test::Nginx::HTTP2->new(port(8084));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name =>  'x' x 513, value => 'value', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
is($frame, undef, 'field name size greater');

# max_field_size - header field value

$s = Test::Nginx::HTTP2->new(port(8084));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'name', value => 'x' x 511, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'field value size less');

$s = Test::Nginx::HTTP2->new(port(8084));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'name', value => 'x' x 511, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'field value size equal');

$s = Test::Nginx::HTTP2->new(port(8084));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'name', value => 'x' x 513, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
is($frame, undef, 'field value size greater');

# max_header_size

$s = Test::Nginx::HTTP2->new(port(8085));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'longname', value => 'x' x 450, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'header size less');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'longname', value => 'x' x 450, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'header size second');

$s = Test::Nginx::HTTP2->new(port(8085));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'longname', value => 'x' x 451, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'header size equal');

$s = Test::Nginx::HTTP2->new(port(8085));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'longname', value => 'x' x 452, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
is($frame, undef, 'header size greater');

# header size is based on (decompressed) header list
# two extra 1-byte indices would otherwise fit in max_header_size

$s = Test::Nginx::HTTP2->new(port(8085));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'longname', value => 'x' x 400, mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'header size new index');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'longname', value => 'x' x 400, mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'DATA' } @$frames;
ok($frame, 'header size indexed');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'longname', value => 'x' x 400, mode => 0 },
	{ name => 'longname', value => 'x' x 400, mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
is($frame->{code}, 0xb, 'header size indexed greater');

# HPACK table boundary

$s = Test::Nginx::HTTP2->new();
$s->read(all => [{ sid => $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => '', mode => 0 },
	{ name => 'x' x 2016, value => 'x' x 2048, mode => 2 }]}), fin => 1 }]);
$frames = $s->read(all => [{ sid => $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => '', mode => 0 },
	{ name => 'x' x 2016, value => 'x' x 2048, mode => 0 }]}), fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($frame, 'HPACK table boundary');

$s->read(all => [{ sid => $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => '', mode => 0 },
	{ name => 'x' x 33, value => 'x' x 4031, mode => 2 }]}), fin => 1 }]);
$frames = $s->read(all => [{ sid => $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => '', mode => 0 },
	{ name => 'x' x 33, value => 'x' x 4031, mode => 0 }]}), fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($frame, 'HPACK table boundary - header field name');

$s->read(all => [{ sid => $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => '', mode => 0 },
	{ name => 'x', value => 'x' x 64, mode => 2 }]}), fin => 1 }]);
$frames = $s->read(all => [{ sid => $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => '', mode => 0 },
	{ name => 'x', value => 'x' x 64, mode => 0 }]}), fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($frame, 'HPACK table boundary - header field value');

# ensure that request header field value with newline doesn't get split
#
# 10.3.  Intermediary Encapsulation Attacks
#   Any request or response that contains a character not permitted
#   in a header field value MUST be treated as malformed.

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/proxy2/', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x-foo', value => "x-bar\r\nreferer:see-this", mode => 2 }]});
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

# 10.3.  Intermediary Encapsulation Attacks
#   An intermediary therefore cannot translate an HTTP/2 request or response
#   containing an invalid field name into an HTTP/1.1 message.

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
isnt($frame->{headers}->{'x-referer'}, 'see-this', 'newline in request header');

# 8.1.2.6.  Malformed Requests and Responses
#   Malformed requests or responses that are detected MUST be treated
#   as a stream error (Section 5.4.2) of type PROTOCOL_ERROR.

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{sid}, $sid, 'newline in request header - RST_STREAM sid');
is($frame->{length}, 4, 'newline in request header - RST_STREAM length');
is($frame->{flags}, 0, 'newline in request header - RST_STREAM flags');
is($frame->{code}, 1, 'newline in request header - RST_STREAM code');

# invalid header name as seen with underscore should not lead to ignoring rest

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x_foo', value => "x-bar", mode => 2 },
	{ name => 'referer', value => "see-this", mode => 1 }]});
$frames = $s->read(all => [{ type => 'HEADERS' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-referer'}, 'see-this', 'after invalid header name');

# other invalid header name characters as seen with ':' result in RST_STREAM

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x:foo', value => "x-bar", mode => 2 },
	{ name => 'referer', value => "see-this", mode => 1 }]});
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{sid}, $sid, 'colon in header name - RST_STREAM sid');
is($frame->{code}, 1, 'colon in header name - RST_STREAM code');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.1');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x foo', value => "bar", mode => 2 }]});
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
ok($frame, 'space in header name - RST_STREAM sid');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => "foo\x02", value => "bar", mode => 2 }]});
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
ok($frame, 'control in header name - RST_STREAM sid');

}

# header name with underscore - underscores_in_headers on

$s = Test::Nginx::HTTP2->new(port(8086));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x_foo', value => "x-bar", mode => 2 },
	{ name => 'referer', value => "see-this", mode => 1 }]});
$frames = $s->read(all => [{ type => 'HEADERS' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'x-bar',
	'underscore in header name - underscores_in_headers');

# header name with underscore - ignore_invalid_headers off

$s = Test::Nginx::HTTP2->new(port(8087));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x_foo', value => "x-bar", mode => 2 },
	{ name => 'referer', value => "see-this", mode => 1 }]});
$frames = $s->read(all => [{ type => 'HEADERS' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'x-bar',
	'underscore in header name - ignore_invalid_headers');

# missing mandatory request header ':scheme'

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'incomplete headers');

# empty request header ':authority'

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => '', mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'empty authority');

# client sent invalid :path header

$sid = $s->new_stream({ path => 't1.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'invalid path');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.1');

$sid = $s->new_stream({ path => "/t1.html\x02" });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'invalid path control');

}

# ngx_http_v2_parse_int() error handling

# NGX_ERROR

$s = Test::Nginx::HTTP2->new();
{
	local $SIG{PIPE} = 'IGNORE';
	syswrite($s->{socket}, pack("x2C3NC", 1, 0x1, 5, 1, 0xff));
}
$frames = $s->read(all => [{ type => "GOAWAY" }]);

($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
is($frame->{code}, 0x6, 'invalid index length');

$s = Test::Nginx::HTTP2->new();
{
	local $SIG{PIPE} = 'IGNORE';
	syswrite($s->{socket}, pack("x2C3NC2", 2, 0x1, 5, 1, 0x42, 0xff));
}
$frames = $s->read(all => [{ type => "GOAWAY" }]);

($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
is($frame->{code}, 0x6, 'invalid literal length');

# NGX_DECLINED

$s = Test::Nginx::HTTP2->new();
{
	local $SIG{PIPE} = 'IGNORE';
	syswrite($s->{socket}, pack("x2C3NN", 5, 0x1, 5, 1, 0xffffffff));
}
$frames = $s->read(all => [{ type => "GOAWAY" }]);

($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
is($frame->{code}, 0x9, 'too long index');

$s = Test::Nginx::HTTP2->new();
{
	local $SIG{PIPE} = 'IGNORE';
	syswrite($s->{socket}, pack("x2C3NCN", 6, 0x1, 5, 1, 0x42, 0xffffffff));
}
$frames = $s->read(all => [{ type => "GOAWAY" }]);

($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
is($frame->{code}, 0x9, 'too long literal');

# NGX_AGAIN

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ split => [35], split_delay => 1.1, headers => [
	{ name => ':method', value => 'GET', mode => 3, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 3, huff => 0 },
	{ name => ':path', value => '/', mode => 3, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 3, huff => 0 },
	{ name => 'referer', value => 'foo', mode => 3, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-referer'}, 'foo', 'header split index');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ split => [37], split_delay => 1.1, headers => [
	{ name => ':method', value => 'GET', mode => 3, huff => 0 },
	{ name => ':scheme', value => 'http', mode => 3, huff => 0 },
	{ name => ':path', value => '/', mode => 3, huff => 0 },
	{ name => ':authority', value => 'localhost', mode => 3, huff => 0 },
	{ name => 'referer', value => '1234' x 32, mode => 3, huff => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-referer'}, '1234' x 32, 'header split field length');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8083),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		next if $headers eq '';
		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri eq '/cookie') {

			my ($cookie, $cookie2) = $headers =~ /Cookie: (.+)/ig;
			$cookie2 = '' unless defined $cookie2;

			my ($cookie_a, $cookie_c) = ('', '');
			$cookie_a = $1 if $headers =~ /X-Cookie-a: (.+)/i;
			$cookie_c = $1 if $headers =~ /X-Cookie-c: (.+)/i;

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Sent-Cookie: $cookie
X-Sent-Cookie2: $cookie2
X-Sent-Cookie-a: $cookie_a
X-Sent-Cookie-c: $cookie_c

EOF

		} elsif ($uri eq '/set-cookie') {

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
Set-Cookie: a=b
Set-Cookie: c=d

EOF

		}

	} continue {
		close $client;
	}
}

###############################################################################
