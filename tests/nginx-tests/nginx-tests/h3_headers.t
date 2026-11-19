#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 headers.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v3 proxy rewrite cryptx/)
	->has_daemon('openssl')->plan(75)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Sent-Foo $http_x_foo;
            add_header X-Referer $http_referer;
            add_header X-Path $uri;
            return 200;
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
        listen       127.0.0.1:%%PORT_8984_UDP%% quic;
        server_name  localhost;

        large_client_header_buffers 4 512;
    }

    server {
        listen       127.0.0.1:%%PORT_8985_UDP%% quic;
        server_name  localhost;

        large_client_header_buffers 1 512;
    }

    server {
        listen       127.0.0.1:%%PORT_8986_UDP%% quic;
        server_name  localhost;

        underscores_in_headers on;
        add_header X-Sent-Foo $http_x_foo always;
    }

    server {
        listen       127.0.0.1:%%PORT_8987_UDP%% quic;
        server_name  localhost;

        ignore_invalid_headers off;
        add_header X-Sent-Foo $http_x_foo always;
    }

    server {
        listen       127.0.0.1:%%PORT_8988_UDP%% quic;
        server_name  localhost;

        client_header_timeout 1s;
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8083));

$t->write_file('t2.html', 'SEE-THIS');

###############################################################################

my ($s, $sid, $frames, $frame);

# 4.5.2. Indexed Field Line

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-path'}, '/', 'indexed');

$s->insert_literal(':path', '/foo');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/foo', mode => 0, dyn => 1 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-path'}, '/foo', 'indexed dynamic');

$s->insert_literal(':path', '/bar', huff => 1);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/bar', mode => 0, dyn => 1 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-path'}, '/bar', 'indexed dynamic huffman');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/foo', mode => 0, dyn => 1 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-path'}, '/foo', 'indexed dynamic previous');

$s->insert_reference(':path', '/qux');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/qux', mode => 0, dyn => 1 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-path'}, '/qux', 'indexed reference');

$s->insert_reference(':path', '/corge', dyn => 1);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/corge', mode => 0, dyn => 1 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-path'}, '/corge', 'indexed reference dynamic');

$s->insert_reference(':path', '/grault', huff => 1);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/grault', mode => 0, dyn => 1 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-path'}, '/grault', 'indexed reference huffman');

# 4.5.3.  Indexed Field Line with Post-Base Index

$s = Test::Nginx::HTTP3->new();
$s->insert_literal(':path', '/foo');
$sid = $s->new_stream({ base => -1, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/foo', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-path'}, '/foo', 'post-base index');

# 4.5.4.  Literal Field Line with Name Reference

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'reference');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 2, huff => 1 },
	{ name => ':scheme', value => 'http', mode => 2, huff => 1 },
	{ name => ':path', value => '/', mode => 2, huff => 1 },
	{ name => ':authority', value => 'localhost', mode => 2, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'reference huffman');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 2, ni => 1 },
	{ name => ':scheme', value => 'http', mode => 2, ni => 1 },
	{ name => ':path', value => '/', mode => 2, ni => 1 },
	{ name => ':authority', value => 'localhost', mode => 2, ni => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'reference never indexed');

$s->insert_literal('x-foo', 'X-Bar');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => 'X-Baz', mode => 2, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Baz', 'reference dynamic');

# 4.5.5.  Literal Field Line with Post-Base Name Reference

$s = Test::Nginx::HTTP3->new();
$s->insert_literal('x-foo', 'X-Bar');
$sid = $s->new_stream({ base => -1, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 4 },
	{ name => 'x-foo', value => 'X-Baz', mode => 3 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Baz', 'base-base ref');

$sid = $s->new_stream({ base => -1, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 4 },
	{ name => 'x-foo', value => 'X-Baz', mode => 3, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Baz', 'post-base ref huffman');

$sid = $s->new_stream({ base => -1, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 4 },
	{ name => 'x-foo', value => 'X-Baz', mode => 3, ni => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Baz', 'post-base ref never indexed');

# 4.5.6. Literal Field Line with Literal Name

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 4 },
	{ name => ':scheme', value => 'http', mode => 4 },
	{ name => ':path', value => '/', mode => 4 },
	{ name => ':authority', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 4, huff => 1 },
	{ name => ':scheme', value => 'http', mode => 4, huff => 1 },
	{ name => ':path', value => '/', mode => 4, huff => 1 },
	{ name => ':authority', value => 'localhost', mode => 4, huff => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal huffman');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 4, ni => 1 },
	{ name => ':scheme', value => 'http', mode => 4, ni => 1 },
	{ name => ':path', value => '/', mode => 4, ni => 1 },
	{ name => ':authority', value => 'localhost', mode => 4, ni => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'literal never indexed');

# response header field with characters not suitable for huffman encoding

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => '{{{{{', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, '{{{{{', 'rare chars');
like($s->{headers}, qr/\Q{{{{{/, 'rare chars - no huffman encoding');

# response header field with huffman encoding
# NB: implementation detail, not obligated

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => 'aaaaa', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'aaaaa', 'well known chars');
unlike($s->{headers}, qr/aaaaa/, 'well known chars - huffman encoding');

# response header field with huffman encoding - complete table mod \0, CR, LF
# first saturate with short-encoded characters (NB: implementation detail)

my $field = pack "C*", ((map { 97 } (1 .. 862)), 1 .. 9, 11, 12, 14 .. 255);

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => $field, mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, $field, 'all chars');
unlike($s->{headers}, qr/abcde/, 'all chars - huffman encoding');

# 3.2.2.  Dynamic Table Capacity and Eviction

# remove some indexed headers from the dynamic table
# by maintaining dynamic table space only for index 0

$s = Test::Nginx::HTTP3->new(undef, capacity => 64);
$s->insert_literal('x-foo', 'X-Bar');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => 'X-Bar', mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Bar', 'capacity insert');

$s->insert_literal('x-foo', 'X-Baz');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => 'X-Baz', mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Baz', 'capacity replace');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => 'X-Bar', mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ type => 'DECODER_C' }]);

($frame) = grep { $_->{type} eq "DECODER_C" } @$frames;
is($frame->{'val'}, $sid, 'capacity eviction');

# insert with referenced entry eviction

$s = Test::Nginx::HTTP3->new(undef, capacity => 64);
$s->insert_literal('x-foo', 'X-Bar');
$s->insert_reference('x-foo', 'X-Baz', dyn => 1);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => 'X-Baz', mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Baz', 'insert ref eviction');

$s = Test::Nginx::HTTP3->new(undef, capacity => 64);
$s->insert_literal('x-foo', 'X-Bar');
$s->duplicate('x-foo');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => 'X-Bar', mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Bar', 'duplicate eviction');

# invalid capacity

$s = Test::Nginx::HTTP3->new(undef, capacity => 4097);
$frames = $s->read(all => [{ type => 'CONNECTION_CLOSE' }]);

($frame) = grep { $_->{type} eq "CONNECTION_CLOSE" } @$frames;
is($frame->{'phrase'}, 'stream error', 'capacity invalid');

# request header field with multiple values

# 4.2.1.  Field Compression
#   To allow for better compression efficiency, the Cookie header field
#   MAY be split into separate field lines <..>.

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/cookie', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'cookie', value => 'a=b', mode => 2 },
	{ name => 'cookie', value => 'c=d', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-cookie-a'}, 'b',
	'multiple request header fields - cookie');
is($frame->{headers}->{'x-cookie-c'}, 'd',
	'multiple request header fields - cookie 2');
is($frame->{headers}->{'x-cookie'}, 'a=b; c=d',
	'multiple request header fields - semi-colon');

# request header field with multiple values to HTTP backend

# 4.2.1.  Field Compression
#   these MUST be concatenated into a single byte string
#   using the two-byte delimiter of "; " (ASCII 0x3b, 0x20)
#   before being passed into a context other than HTTP/2 or
#   HTTP/3, such as an HTTP/1.1 connection <..>

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/proxy/cookie', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
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

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/set-cookie' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'set-cookie'}[0], 'a=b',
	'multiple response header fields - cookie');
is($frame->{headers}->{'set-cookie'}[1], 'c=d',
	'multiple response header fields - cookie 2');

# response header field with multiple values from HTTP backend

$s = Test::Nginx::HTTP3->new();
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

# max_field_size - header field name

$s = Test::Nginx::HTTP3->new(8984, capacity => 2048);
$s->insert_literal('x' x 511, 'value');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x' x 511, value => 'value', mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'field name size less');

$s = Test::Nginx::HTTP3->new(8984, capacity => 2048);
$s->insert_literal('x' x 512, 'value');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x' x 512, value => 'value', mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'field name size equal');

$s = Test::Nginx::HTTP3->new(8984, capacity => 2048);
$s->insert_literal('x' x 513, 'value');
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name =>  'x' x 513, value => 'value', mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ type => 'CONNECTION_CLOSE' }]);

($frame) = grep { $_->{type} eq "CONNECTION_CLOSE" } @$frames;
is($frame->{'phrase'}, 'stream error', 'field name size greater');

# max_field_size - header field value

$s = Test::Nginx::HTTP3->new(8984, capacity => 2048);
$s->insert_literal('name', 'x' x 511);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'name', value => 'x' x 511, mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'field value size less');

$s = Test::Nginx::HTTP3->new(8984, capacity => 2048);
$s->insert_literal('name', 'x' x 512);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'name', value => 'x' x 512, mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'field value size equal');

$s = Test::Nginx::HTTP3->new(8984, capacity => 2048);
$s->insert_literal('name', 'x' x 513);
$frames = $s->read(all => [{ type => 'CONNECTION_CLOSE' }]);

($frame) = grep { $_->{type} eq "CONNECTION_CLOSE" } @$frames;
is($frame->{'phrase'}, 'stream error', 'field value size greater');

# max_header_size

$s = Test::Nginx::HTTP3->new(8985, capacity => 2048);
$s->insert_literal('longname', 'x' x 450);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'longname', value => 'x' x 450, mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'header size less');

$s = Test::Nginx::HTTP3->new(8985, capacity => 2048);
$s->insert_literal('longname', 'x' x 451);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'longname', value => 'x' x 451, mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'header size equal');

$s = Test::Nginx::HTTP3->new(8985, capacity => 2048);
$s->insert_literal('longname', 'x' x 452);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'longname', value => 'x' x 452, mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'header size greater');

# header size is based on (decompressed) header list
# two extra 1-byte indices would otherwise fit in max_header_size

$s = Test::Nginx::HTTP3->new(8985, capacity => 2048);
$s->insert_literal('longname', 'x' x 400);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'longname', value => 'x' x 400, mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'header size indexed');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t2.html', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'longname', value => 'x' x 400, mode => 0, dyn => 1 },
	{ name => 'longname', value => 'x' x 400, mode => 0, dyn => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'header size indexed greater');

# ensure that request header field value with newline doesn't get split
#
# 10.3.  Intermediary-Encapsulation Attacks
#   Requests or responses containing invalid field names MUST be treated
#   as malformed.

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/proxy2/', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x-foo', value => "x-bar\r\nreferer:see-this", mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

# 10.3.  Intermediary Encapsulation Attacks
#   Therefore, an intermediary cannot translate an HTTP/3 request or response
#   containing an invalid field name into an HTTP/1.1 message.

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
isnt($frame->{headers}->{'x-referer'}, 'see-this', 'newline in request header');

is($frame->{headers}->{':status'}, 400, 'newline in request header - bad request');

# invalid header name as seen with underscore should not lead to ignoring rest

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x_foo', value => "x-bar", mode => 4 },
	{ name => 'referer', value => "see-this", mode => 2 }]});
$frames = $s->read(all => [{ type => 'HEADERS' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-referer'}, 'see-this', 'after invalid header name');

# other invalid header name characters as seen with ':'

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x:foo', value => "x-bar", mode => 4 },
	{ name => 'referer', value => "see-this", mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'colon in header name');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x foo', value => "bar", mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'space in header name');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => "foo\x02", value => "bar", mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'control in header name');

# header name with underscore - underscores_in_headers on

$s = Test::Nginx::HTTP3->new(8986);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x_foo', value => "x-bar", mode => 4 },
	{ name => 'referer', value => "see-this", mode => 2 }]});
$frames = $s->read(all => [{ type => 'HEADERS' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'x-bar',
	'underscore in header name - underscores_in_headers');

# header name with underscore - ignore_invalid_headers off

$s = Test::Nginx::HTTP3->new(8987);
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'x_foo', value => "x-bar", mode => 4 },
	{ name => 'referer', value => "see-this", mode => 2 }]});
$frames = $s->read(all => [{ type => 'HEADERS' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'x-bar',
	'underscore in header name - ignore_invalid_headers');

# missing mandatory request header ':scheme'

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'incomplete headers');

# no ':authority'

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'no authority');

# empty request header ':authority'

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => '', mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'empty authority');

# no ':authority' and non-empty 'host'

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => 'host', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'no authority and non-empty host');

# no ':authority' and non-empty 'host' with port

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.1');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => 'host', value => 'localhost:1234', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'no authority and non-empty host with port');

}

# equal ':authority' and 'host'

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'host', value => 'localhost', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'equal authority and host');

# equal ':authority' and 'host' with port

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.1');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost:1234', mode => 2 },
	{ name => 'host', value => 'localhost:1234', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'equal authority and host with port');

}

# non-equal ':authority' and 'host'

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => 'host', value => 'localhost2', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'non-equal authority and host');

# non-equal ':authority' and 'host' with port

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost:1234', mode => 2 },
	{ name => 'host', value => 'localhost:5678', mode => 4 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400,
	'non-equal authority and host with port');

# client sent invalid :path header

$sid = $s->new_stream({ path => 't2.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'invalid path');

$sid = $s->new_stream({ path => "/t2.html\x02" });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'invalid path control');

# stream blocked on insert count

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ ric => 3 });
select undef, undef, undef, 0.2;

$s->reset_stream($sid, 0x010c);
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, '400', 'blocked insert reset - bad request');

$s = Test::Nginx::HTTP3->new(8988);
$sid = $s->new_stream({ ric => 3 });
$frames = $s->read(all => [{ type => 'RESET_STREAM' }]);

($frame) = grep { $_->{type} eq "RESET_STREAM" } @$frames;
is($frame->{sid}, $sid, 'blocked insert timeout - RESET_STREAM');

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
	}
}

###############################################################################
