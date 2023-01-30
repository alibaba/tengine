#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol [RFC7540].

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy rewrite charset gzip/)
	->plan(144);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2;
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Header X-Foo;
            add_header X-Sent-Foo $http_x_foo;
            add_header X-Referer $http_referer;
            return 200 'body';
        }
        location /t {
        }
        location /gzip.html {
            gzip on;
            gzip_min_length 0;
            gzip_vary on;
            alias %%TESTDIR%%/t2.html;
        }
        location /frame_size {
            http2_chunk_size 64k;
            alias %%TESTDIR%%;
            output_buffers 2 1m;
        }
        location /chunk_size {
            http2_chunk_size 1;
            return 200 'body';
        }
        location /redirect {
            error_page 405 /;
            return 405;
        }
        location /return301 {
            return 301;
        }
        location /return301_absolute {
            return 301 text;
        }
        location /return301_relative {
            return 301 /;
        }
        location /charset {
            charset utf-8;
            return 200;
        }
    }

    server {
        listen       127.0.0.1:8082 http2;
        server_name  localhost;
        return 200   first;
    }

    server {
        listen       127.0.0.1:8082 http2;
        server_name  localhost2;
        return 200   second;
    }

    server {
        listen       127.0.0.1:8083 http2;
        server_name  localhost;

        http2_max_concurrent_streams 1;
    }

    server {
        listen       127.0.0.1:8086 http2;
        server_name  localhost;

        send_timeout 1s;
        lingering_close off;
    }

    server {
        listen       127.0.0.1:8087 http2;
        server_name  localhost;

        client_header_timeout 1s;
        client_body_timeout 1s;
        lingering_close off;

        location / { }

        location /proxy/ {
            proxy_pass http://127.0.0.1:8081/;
        }
    }
}

EOF

$t->run();

# file size is slightly beyond initial window size: 2**16 + 80 bytes

$t->write_file('t1.html',
	join('', map { sprintf "X%04dXXX", $_ } (1 .. 8202)));
$t->write_file('tbig.html',
	join('', map { sprintf "XX%06dXX", $_ } (1 .. 500000)));

$t->write_file('t2.html', 'SEE-THIS');

###############################################################################

# SETTINGS

my $s = Test::Nginx::HTTP2->new(port(8080), pure => 1);
my $frames = $s->read(all => [
	{ type => 'WINDOW_UPDATE' },
	{ type => 'SETTINGS'}
]);

my ($frame) = grep { $_->{type} eq 'WINDOW_UPDATE' } @$frames;
ok($frame, 'WINDOW_UPDATE frame');
is($frame->{flags}, 0, 'WINDOW_UPDATE zero flags');
is($frame->{sid}, 0, 'WINDOW_UPDATE zero sid');
is($frame->{length}, 4, 'WINDOW_UPDATE fixed length');

($frame) = grep { $_->{type} eq 'SETTINGS' } @$frames;
ok($frame, 'SETTINGS frame');
is($frame->{flags}, 0, 'SETTINGS flags');
is($frame->{sid}, 0, 'SETTINGS stream');

$s->h2_settings(1);
$s->h2_settings(0);

$frames = $s->read(all => [{ type => 'SETTINGS' }]);

($frame) = grep { $_->{type} eq 'SETTINGS' } @$frames;
ok($frame, 'SETTINGS frame ack');
is($frame->{flags}, 1, 'SETTINGS flags ack');

# SETTINGS - no ack on PROTOCOL_ERROR

$s = Test::Nginx::HTTP2->new(port(8080), pure => 1);
$frames = $s->read(all => [
	{ type => 'WINDOW_UPDATE' },
	{ type => 'SETTINGS'}
]);

$s->h2_settings(1);
$s->h2_settings(0, 0x5 => 42);

$frames = $s->read(all => [
	{ type => 'SETTINGS'},
	{ type => 'GOAWAY' }
]);

($frame) = grep { $_->{type} eq 'SETTINGS' } @$frames;
is($frame, undef, 'SETTINGS PROTOCOL_ERROR - no ack');

($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
ok($frame, 'SETTINGS PROTOCOL_ERROR - GOAWAY');

# PING

$s = Test::Nginx::HTTP2->new();
$s->h2_ping('SEE-THIS');
$frames = $s->read(all => [{ type => 'PING' }]);

($frame) = grep { $_->{type} eq "PING" } @$frames;
ok($frame, 'PING frame');
is($frame->{value}, 'SEE-THIS', 'PING payload');
is($frame->{flags}, 1, 'PING flags ack');
is($frame->{sid}, 0, 'PING stream');

# GOAWAY

Test::Nginx::HTTP2->new()->h2_goaway(0, 0, 5);
Test::Nginx::HTTP2->new()->h2_goaway(0, 0, 5, 'foobar');
Test::Nginx::HTTP2->new()->h2_goaway(0, 0, 5, 'foobar', split => [ 8, 8, 4 ]);

$s = Test::Nginx::HTTP2->new();
$s->h2_goaway(0, 0, 5);
$s->h2_goaway(0, 0, 5);

$s = Test::Nginx::HTTP2->new();
$s->h2_goaway(0, 0, 5, 'foobar', len => 0);
$frames = $s->read(all => [{ type => "GOAWAY" }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'GOAWAY invalid length - GOAWAY frame');
is($frame->{code}, 6, 'GOAWAY invalid length - GOAWAY FRAME_SIZE_ERROR');

# 6.8.  GOAWAY
#   An endpoint MUST treat a GOAWAY frame with a stream identifier other
#   than 0x0 as a connection error (Section 5.4.1) of type PROTOCOL_ERROR.

$s = Test::Nginx::HTTP2->new();
$s->h2_goaway(1, 0, 5, 'foobar');
$frames = $s->read(all => [{ type => "GOAWAY" }], wait => 0.5);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'GOAWAY invalid stream - GOAWAY frame');
is($frame->{code}, 1, 'GOAWAY invalid stream - GOAWAY PROTOCOL_ERROR');

# client-initiated PUSH_PROMISE, just to ensure nothing went wrong
# N.B. other implementation returns zero code, which is not anyhow regulated

$s = Test::Nginx::HTTP2->new();
{
	local $SIG{PIPE} = 'IGNORE';
	syswrite($s->{socket}, pack("x2C2xN", 4, 0x5, 1));
}
$frames = $s->read(all => [{ type => "GOAWAY" }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'client-initiated PUSH_PROMISE - GOAWAY frame');
is($frame->{code}, 1, 'client-initiated PUSH_PROMISE - GOAWAY PROTOCOL_ERROR');

# GET

$s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($frame, 'HEADERS frame');
is($frame->{sid}, $sid, 'HEADERS stream');
is($frame->{headers}->{':status'}, 200, 'HEADERS status');
is($frame->{headers}->{'x-header'}, 'X-Foo', 'HEADERS header');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'DATA frame');
is($frame->{length}, length 'body', 'DATA length');
is($frame->{data}, 'body', 'DATA payload');

# GET in the new stream on same connection

$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{sid}, $sid, 'HEADERS stream 2');
is($frame->{headers}->{':status'}, 200, 'HEADERS status 2');
is($frame->{headers}->{'x-header'}, 'X-Foo', 'HEADERS header 2');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'DATA frame 2');
is($frame->{sid}, $sid, 'HEADERS stream 2');
is($frame->{length}, length 'body', 'DATA length 2');
is($frame->{data}, 'body', 'DATA payload 2');

# HEAD

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ method => 'HEAD' });
$frames = $s->read(all => [{ sid => $sid, fin => 0x4 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{sid}, $sid, 'HEAD - HEADERS');
is($frame->{headers}->{':status'}, 200, 'HEAD - HEADERS status');
is($frame->{headers}->{'x-header'}, 'X-Foo', 'HEAD - HEADERS header');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame, undef, 'HEAD - no body');

# CONNECT

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.1');

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ method => 'CONNECT' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 405, 'CONNECT - not allowed');

}

# TRACE

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ method => 'TRACE' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 405, 'TRACE - not allowed');

# range filter

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/t1.html', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'range', value => 'bytes=10-19', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 206, 'range - HEADERS status');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{length}, 10, 'range - DATA length');
is($frame->{data}, '002XXXX000', 'range - DATA payload');

# http2_chunk_size=1

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/chunk_size' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my @data = grep { $_->{type} eq "DATA" } @$frames;
is(@data, 4, 'chunk_size frames');
is(join(' ', map { $_->{data} } @data), 'b o d y', 'chunk_size data');
is(join(' ', map { $_->{flags} } @data), '0 0 0 1', 'chunk_size flags');

# CONTINUATION

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ continuation => 1, headers => [
	{ name => ':method', value => 'HEAD', mode => 1 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
$s->h2_continue($sid, { continuation => 1, headers => [
	{ name => 'x-foo', value => 'X-Bar', mode => 2 }]});
$s->h2_continue($sid, { headers => [
	{ name => 'referer', value => 'foo', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame, undef, 'CONTINUATION - fragment 1');

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-sent-foo'}, 'X-Bar', 'CONTINUATION - fragment 2');
is($frame->{headers}->{'x-referer'}, 'foo', 'CONTINUATION - fragment 3');

# CONTINUATION - in the middle of request header field

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ continuation => [ 2, 4, 1, 5 ], headers => [
	{ name => ':method', value => 'HEAD', mode => 1 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'CONTINUATION - in header field');

# CONTINUATION on a closed stream

$s->h2_continue(1, { headers => [
	{ name => 'x-foo', value => 'X-Bar', mode => 2 }]});
$frames = $s->read(all => [{ sid => 1, fin => 1 }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame->{type}, 'GOAWAY', 'GOAWAY - CONTINUATION closed stream');
is($frame->{code}, 1, 'GOAWAY - CONTINUATION closed stream - PROTOCOL_ERROR');

# frame padding

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ padding => 42, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'padding - HEADERS status');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'padding - next stream');

# padding followed by CONTINUATION

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ padding => 42, continuation => [ 2, 4, 1, 5 ],
	headers => [
	{ name => ':method', value => 'GET', mode => 1 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'padding - CONTINUATION');

# internal redirect

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/redirect' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 405, 'redirect - HEADERS');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'redirect - DATA');
is($frame->{data}, 'body', 'redirect - DATA payload');

# return 301 with absolute URI

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/return301_absolute' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 301, 'return 301 absolute - status');
is($frame->{headers}->{'location'}, 'text', 'return 301 absolute - location');

# return 301 with relative URI

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/return301_relative' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 301, 'return 301 relative - status');
is($frame->{headers}->{'location'}, 'http://localhost:' . port(8080) . '/',
	'return 301 relative - location');

# return 301 with relative URI and ':authority' request header field

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/return301_relative', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 301,
	'return 301 relative - authority - status');
is($frame->{headers}->{'location'}, 'http://localhost:' . port(8080) . '/',
	'return 301 relative - authority - location');

# return 301 with relative URI and 'host' request header field

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/return301_relative', mode => 2 },
	{ name => 'host', value => 'localhost', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 301,
	'return 301 relative - host - status');
is($frame->{headers}->{'location'}, 'http://localhost:' . port(8080) . '/',
	'return 301 relative - host - location');

# virtual host

$s = Test::Nginx::HTTP2->new(port(8082));
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => 'host', value => 'localhost', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'virtual host - host - status');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'first', 'virtual host - host - DATA');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'virtual host - authority - status');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'first', 'virtual host - authority - DATA');

# virtual host - second

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => 'host', value => 'localhost2', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'virtual host 2 - host - status');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'second', 'virtual host 2 - host - DATA');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost2', mode => 2 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'virtual host 2 - authority - status');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'second', 'virtual host 2 - authority - DATA');

# gzip tests for internal nginx version

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/gzip.html' },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'accept-encoding', value => 'gzip' }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'content-encoding'}, 'gzip', 'gzip - encoding');
is($frame->{headers}->{'vary'}, 'Accept-Encoding', 'gzip - vary');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
gunzip_like($frame->{data}, qr/^SEE-THIS\Z/, 'gzip - DATA');

# charset

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/charset' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'content-type'}, 'text/plain; charset=utf-8', 'charset');

# partial request header frame received (field split),
# the rest of frame is received after client header timeout

$s = Test::Nginx::HTTP2->new(port(8087));
$sid = $s->new_stream({ path => '/t2.html', split => [35],
	split_delay => 2.1 });
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
ok($frame, 'client header timeout');
is($frame->{code}, 1, 'client header timeout - protocol error');

$s->h2_ping('SEE-THIS');
$frames = $s->read(all => [{ type => 'PING' }]);

($frame) = grep { $_->{type} eq "PING" && $_->{flags} & 0x1 } @$frames;
ok($frame, 'client header timeout - PING');

# partial request header frame received (no field split),
# the rest of frame is received after client header timeout

$s = Test::Nginx::HTTP2->new(port(8087));
$sid = $s->new_stream({ path => '/t2.html', split => [20], split_delay => 2.1 });
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
ok($frame, 'client header timeout 2');
is($frame->{code}, 1, 'client header timeout 2 - protocol error');

$s->h2_ping('SEE-THIS');
$frames = $s->read(all => [{ type => 'PING' }]);

($frame) = grep { $_->{type} eq "PING" && $_->{flags} & 0x1 } @$frames;
ok($frame, 'client header timeout 2 - PING');

# partial request body data frame received, the rest is after body timeout

$s = Test::Nginx::HTTP2->new(port(8087));
$sid = $s->new_stream({ path => '/proxy/t2.html', body_more => 1 });
$s->h2_body('TEST', { split => [10], split_delay => 2.1 });
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
ok($frame, 'client body timeout');
is($frame->{code}, 1, 'client body timeout - protocol error');

$s->h2_ping('SEE-THIS');
$frames = $s->read(all => [{ type => 'PING' }]);

($frame) = grep { $_->{type} eq "PING" && $_->{flags} & 0x1 } @$frames;
ok($frame, 'client body timeout - PING');

# partial request body data frame with connection close after body timeout

$s = Test::Nginx::HTTP2->new(port(8087));
$sid = $s->new_stream({ path => '/proxy/t2.html', body_more => 1 });
$s->h2_body('TEST', { split => [ 12 ], abort => 1 });

select undef, undef, undef, 1.1;
undef $s;

# proxied request with logging pristine request header field (e.g., referer)

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/proxy2/' },
	{ name => ':authority', value => 'localhost' },
	{ name => 'referer', value => 'foo' }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'proxy with logging request headers');

$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($frame->{headers}, 'proxy with logging request headers - next');

# initial window size, client side

# 6.9.2.  Initial Flow-Control Window Size
#   When an HTTP/2 connection is first established, new streams are
#   created with an initial flow-control window size of 65,535 octets.
#   The connection flow-control window is also 65,535 octets.

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/t1.html' });
$frames = $s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

# with the default http2_chunk_size, data is divided into 8 data frames

@data = grep { $_->{type} eq "DATA" } @$frames;
my $lengths = join ' ', map { $_->{length} } @data;
is($lengths, '8192 8192 8192 8192 8192 8192 8192 8191',
	'iws - stream blocked on initial window size');

$s->h2_ping('SEE-THIS');
$frames = $s->read(all => [{ type => 'PING' }]);

($frame) = grep { $_->{type} eq "PING" && $_->{flags} & 0x1 } @$frames;
ok($frame, 'iws - PING not blocked');

$s->h2_window(2**16, $sid);
$frames = $s->read(wait => 0.2);
is(@$frames, 0, 'iws - updated stream window');

$s->h2_window(2**16);
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
my $sum = eval join '+', map { $_->{length} } @data;
is($sum, 81, 'iws - updated connection window');

# SETTINGS (initial window size, client side)

# 6.9.2.  Initial Flow-Control Window Size
#   Both endpoints can adjust the initial window size for new streams by
#   including a value for SETTINGS_INITIAL_WINDOW_SIZE in the SETTINGS
#   frame that forms part of the connection preface.  The connection
#   flow-control window can only be changed using WINDOW_UPDATE frames.

$s = Test::Nginx::HTTP2->new();
$s->h2_settings(0, 0x4 => 2**17);
$s->h2_window(2**17);

$sid = $s->new_stream({ path => '/t1.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 2**16 + 80, 'iws - increased');

# INITIAL_WINDOW_SIZE duplicate settings

# 6.5.  SETTINGS
#   Each parameter in a SETTINGS frame replaces any existing value for
#   that parameter.  Parameters are processed in the order in which they
#   appear, and a receiver of a SETTINGS frame does not need to maintain
#   any state other than the current value of its parameters.  Therefore,
#   the value of a SETTINGS parameter is the last value that is seen by a
#   receiver.

$s = Test::Nginx::HTTP2->new();
$s->h2_window(2**17);

$sid = $s->new_stream({ path => '/t1.html' });

$frames = $s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);
@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 2**16 - 1, 'iws duplicate - default stream window');

# this should effect in extra stream window octect
# $s->h2_settings(0, 0x4 => 42, 0x4 => 2**16);
{
	local $SIG{PIPE} = 'IGNORE';
	syswrite($s->{socket}, pack("x2C2x5nNnN", 12, 0x4, 4, 42, 4, 2**16));
}

$frames = $s->read(all => [{ sid => $sid, length => 1 }]);
@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 1, 'iws duplicate - updated stream window');

# yet more octets to finish receiving the response

$s->h2_settings(0, 0x4 => 2**16 + 80);

$frames = $s->read(all => [{ sid => $sid, length => 80 }]);
@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 80, 'iws duplicate - updated stream window 2');

# probe for negative available space in a flow control window

# 6.9.2.  Initial Flow-Control Window Size
#   A change to SETTINGS_INITIAL_WINDOW_SIZE can cause the available
#   space in a flow-control window to become negative.  A sender MUST
#   track the negative flow-control window and MUST NOT send new flow-
#   controlled frames until it receives WINDOW_UPDATE frames that cause
#   the flow-control window to become positive.

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$s->h2_window(1);
$s->h2_settings(0, 0x4 => 42);
$s->h2_window(1024, $sid);

$frames = $s->read(all => [{ type => 'SETTINGS' }]);

($frame) = grep { $_->{type} eq 'SETTINGS' } @$frames;
ok($frame, 'negative window - SETTINGS frame ack');
is($frame->{flags}, 1, 'negative window - SETTINGS flags ack');

($frame) = grep { $_->{type} ne 'SETTINGS' } @$frames;
is($frame, undef, 'negative window - no data');

# predefined window size, minus new iws settings, minus window update

$s->h2_window(2**16 - 1 - 42 - 1024, $sid);

$frames = $s->read(wait => 0.2);
is(@$frames, 0, 'zero window - no data');

$s->h2_window(1, $sid);

$frames = $s->read(all => [{ sid => $sid, length => 1 }]);
is(@$frames, 1, 'positive window');

SKIP: {
skip 'failed connection', 2 unless @$frames;

is(@$frames[0]->{type}, 'DATA', 'positive window - data');
is(@$frames[0]->{length}, 1, 'positive window - data length');

}

$s = Test::Nginx::HTTP2->new();
$s->h2_window(2**30);
$s->h2_settings(0, 0x4 => 2**30);

$sid = $s->new_stream({ path => '/frame_size/tbig.html' });

sleep 1;
$s->h2_settings(0, 0x5 => 2**15);

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
$lengths = join ' ', map { $_->{length} } @$frames;
unlike($lengths, qr/16384 0 16384/, 'SETTINGS ack after queued DATA');

# ask write handler in sending large response

SKIP: {
skip 'unsafe socket tests', 4 unless $ENV{TEST_NGINX_UNSAFE};

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/tbig.html' });

$s->h2_window(2**30, $sid);
$s->h2_window(2**30);

sleep 1;
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'large response - HEADERS');

@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 5000000, 'large response - DATA');

# Make sure http2 write handler doesn't break a connection.

$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'new stream after large response');

# write event send timeout

$s = Test::Nginx::HTTP2->new(port(8086));
$sid = $s->new_stream({ path => '/tbig.html' });
$s->h2_window(2**30, $sid);
$s->h2_window(2**30);

select undef, undef, undef, 2.1;

$s->h2_ping('SEE-THIS');

$frames = $s->read(all => [{ type => 'PING' }]);
ok(!grep ({ $_->{type} eq "PING" } @$frames), 'large response - send timeout');

}

# SETTINGS_MAX_FRAME_SIZE

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/frame_size/t1.html' });
$s->h2_window(2**18, 1);
$s->h2_window(2**18);

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@data = grep { $_->{type} eq "DATA" } @$frames;
is($data[0]->{length}, 2**14, 'max frame size - default');

$s = Test::Nginx::HTTP2->new();
$s->h2_settings(0, 0x5 => 2**15);
$sid = $s->new_stream({ path => '/frame_size/t1.html' });
$s->h2_window(2**18, 1);
$s->h2_window(2**18);

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@data = grep { $_->{type} eq "DATA" } @$frames;
is($data[0]->{length}, 2**15, 'max frame size - custom');

# SETTINGS_INITIAL_WINDOW_SIZE + SETTINGS_MAX_FRAME_SIZE
# Expanding available stream window should not result in emitting
# new frames before remaining SETTINGS parameters were applied.

$s = Test::Nginx::HTTP2->new();
$s->h2_window(2**17);
$s->h2_settings(0, 0x4 => 42);

$sid = $s->new_stream({ path => '/frame_size/t1.html' });
$s->read(all => [{ sid => $sid, length => 42 }]);

$s->h2_settings(0, 0x4 => 2**17, 0x5 => 2**15);

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@data = grep { $_->{type} eq "DATA" } @$frames;
$lengths = join ' ', map { $_->{length} } @data;
is($lengths, '32768 32768 38', 'multiple SETTINGS');

# stream multiplexing + WINDOW_UPDATE

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/t1.html' });
$frames = $s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 2**16 - 1, 'multiple - stream1 data');

my $sid2 = $s->new_stream({ path => '/t1.html' });
$frames = $s->read(all => [{ sid => $sid2, fin => 0x4 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
is(@data, 0, 'multiple - stream2 no data');

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

@data = grep { $_->{type} eq "DATA" && $_->{sid} == $sid } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 81, 'multiple - stream1 remain data');

@data = grep { $_->{type} eq "DATA" && $_->{sid} == $sid2 } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 2**16 + 80, 'multiple - stream2 full data');

# http2_max_concurrent_streams

$s = Test::Nginx::HTTP2->new(port(8083), pure => 1);
$frames = $s->read(all => [{ type => 'SETTINGS' }]);

($frame) = grep { $_->{type} eq 'SETTINGS' } @$frames;
is($frame->{3}, 1, 'http2_max_concurrent_streams SETTINGS');

$s->h2_window(2**18);

$sid = $s->new_stream({ path => '/t1.html' });
$frames = $s->read(all => [{ sid => $sid, length => 2 ** 16 - 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid } @$frames;
is($frame->{headers}->{':status'}, 200, 'http2_max_concurrent_streams');

$sid2 = $s->new_stream({ path => '/t1.html' });
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid2 } @$frames;
isnt($frame->{headers}->{':status'}, 200, 'http2_max_concurrent_streams 2');

($frame) = grep { $_->{type} eq "RST_STREAM" && $_->{sid} == $sid2 } @$frames;
is($frame->{sid}, $sid2, 'http2_max_concurrent_streams RST_STREAM sid');
is($frame->{length}, 4, 'http2_max_concurrent_streams RST_STREAM length');
is($frame->{flags}, 0, 'http2_max_concurrent_streams RST_STREAM flags');
is($frame->{code}, 7, 'http2_max_concurrent_streams RST_STREAM code');

# properly skip header field that's not/never indexed from discarded streams

$sid2 = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/', mode => 6 },
	{ name => ':authority', value => 'localhost' },
	{ name => 'x-foo', value => 'Foo', mode => 2 }]});
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

# also if split across writes

$sid2 = $s->new_stream({ split => [ 22 ], headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/', mode => 6 },
	{ name => ':authority', value => 'localhost' },
	{ name => 'x-bar', value => 'Bar', mode => 2 }]});
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

# also if split across frames

$sid2 = $s->new_stream({ continuation => [ 17 ], headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/', mode => 6 },
	{ name => ':authority', value => 'localhost' },
	{ name => 'x-baz', value => 'Baz', mode => 2 }]});
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

$s->h2_window(2**16, $sid);
$s->read(all => [{ sid => $sid, fin => 1 }]);

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/t2.html' },
	{ name => ':authority', value => 'localhost' },
# make sure that discarded streams updated dynamic table
	{ name => 'x-foo', value => 'Foo', mode => 0 },
	{ name => 'x-bar', value => 'Bar', mode => 0 },
	{ name => 'x-baz', value => 'Baz', mode => 0 }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid } @$frames;
is($frame->{headers}->{':status'}, 200, 'http2_max_concurrent_streams 3');


# some invalid cases below

# invalid connection preface

$s = Test::Nginx::HTTP2->new(port(8080), preface => 'x' x 16, pure => 1);
$frames = $s->read(all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'invalid preface - GOAWAY frame');
is($frame->{code}, 1, 'invalid preface - error code');

my $preface = 'PRI * HTTP/2.0' . CRLF . CRLF . 'x' x 8;
$s = Test::Nginx::HTTP2->new(port(8080), preface => $preface, pure => 1);
$frames = $s->read(all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'invalid preface 2 - GOAWAY frame');
is($frame->{code}, 1, 'invalid preface 2 - error code');

# GOAWAY on SYN_STREAM with even StreamID

$s = Test::Nginx::HTTP2->new();
$s->new_stream({ path => '/' }, 2);
$frames = $s->read(all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'even stream - GOAWAY frame');
is($frame->{code}, 1, 'even stream - error code');
is($frame->{last_sid}, 0, 'even stream - last stream');

# GOAWAY on SYN_STREAM with backward StreamID

# 5.1.1.  Stream Identifiers
#   The first use of a new stream identifier implicitly closes all
#   streams in the "idle" state <..> with a lower-valued stream identifier.

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/' }, 3);
$s->read(all => [{ sid => $sid, fin => 1 }]);

$sid2 = $s->new_stream({ path => '/' }, 1);
$frames = $s->read(all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'backward stream - GOAWAY frame');
is($frame->{code}, 1, 'backward stream - error code');
is($frame->{last_sid}, $sid, 'backward stream - last stream');

# GOAWAY on the second SYN_STREAM with same StreamID

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/' });
$s->read(all => [{ sid => $sid, fin => 1 }]);

$sid2 = $s->new_stream({ path => '/' }, $sid);
$frames = $s->read(all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'dup stream - GOAWAY frame');
is($frame->{code}, 1, 'dup stream - error code');
is($frame->{last_sid}, $sid, 'dup stream - last stream');

# aborted stream with zero HEADERS payload followed by client connection close

Test::Nginx::HTTP2->new()->new_stream({ split => [ 9 ], abort => 1 });

# unknown frame type

$s = Test::Nginx::HTTP2->new();
$s->h2_unknown('payload');
$s->h2_ping('SEE-THIS');
$frames = $s->read(all => [{ type => 'PING' }]);

($frame) = grep { $_->{type} eq "PING" } @$frames;
is($frame->{value}, 'SEE-THIS', 'unknown frame type');

# graceful shutdown with stream waiting on HEADERS payload

my $grace = Test::Nginx::HTTP2->new(port(8087));
$grace->new_stream({ split => [ 9 ], abort => 1 });

# graceful shutdown waiting on incomplete request body DATA frames

my $grace3 = Test::Nginx::HTTP2->new(port(8087));
$sid = $grace3->new_stream({ path => '/proxy/t2.html', body_more => 1 });
$grace3->h2_body('TEST', { body_more => 1 });

# GOAWAY without awaiting active streams, further streams ignored

$s = Test::Nginx::HTTP2->new(port(8080));
$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$t->reload();

$frames = $s->read(all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame->{last_sid}, $sid, 'GOAWAY with active stream - last sid');

$sid2 = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid2, fin => 0x4 }], wait => 0.5);

($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;
is($frame, undef, 'GOAWAY with active stream - no new stream');

$s->h2_window(100, $sid);
$s->h2_window(100);
$frames = $s->read(all => [{ sid => $sid, fin => 0x1 }]);

@data = grep { $_->{type} eq "DATA" && $_->{sid} == $sid } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 81, 'GOAWAY with active stream - active stream DATA after GOAWAY');

# GOAWAY - force closing a connection by server with idle or active streams

$s = Test::Nginx::HTTP2->new(port(8086));
$sid = $s->new_stream();
$s->read(all => [{ sid => $sid, fin => 1 }]);

my $active = Test::Nginx::HTTP2->new(port(8086));
$sid = $active->new_stream({ path => '/t1.html' });
$active->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$t->stop();

$frames = $s->read(all => [{ type => 'GOAWAY' }]);
($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'GOAWAY on connection close - idle stream');

$frames = $active->read(all => [{ type => 'GOAWAY' }]);
($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'GOAWAY on connection close - active stream');

###############################################################################

sub gunzip_like {
	my ($in, $re, $name) = @_;

	SKIP: {
		eval { require IO::Uncompress::Gunzip; };
		Test::More::skip(
			"IO::Uncompress::Gunzip not installed", 1) if $@;

		my $out;

		IO::Uncompress::Gunzip::gunzip(\$in => \$out);

		like($out, $re, $name);
	}
}

###############################################################################
