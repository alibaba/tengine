#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for SPDY protocol version 3.1.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval {
	require Compress::Raw::Zlib;
	Compress::Raw::Zlib->Z_OK;
	Compress::Raw::Zlib->Z_SYNC_FLUSH;
	Compress::Raw::Zlib->Z_NO_COMPRESSION;
	Compress::Raw::Zlib->WANT_GZIP_OR_ZLIB;
};
plan(skip_all => 'Compress::Raw::Zlib not installed') if $@;

my $t = Test::Nginx->new()
	->has(qw/http proxy cache limit_conn rewrite spdy realip shmem/);

# Some systems have a bug in not treating zero writev iovcnt as EINVAL

$t->todo_alerts() if $^O eq 'darwin';

$t->plan(84)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path %%TESTDIR%%/cache    keys_zone=NAME:1m;
    limit_conn_zone  $binary_remote_addr  zone=conn:1m;

    server {
        listen       127.0.0.1:8080 spdy;
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082 proxy_protocol spdy;
        server_name  localhost;

        location /s {
            add_header X-Header X-Foo;
            return 200 'body';
        }
        location /pp {
            set_real_ip_from  127.0.0.1/32;
            real_ip_header proxy_protocol;
            alias %%TESTDIR%%/t2.html;
            add_header X-PP $remote_addr;
        }
        location /spdy {
            return 200 $spdy;
        }
        location /prio {
            return 200 $spdy_request_priority;
        }
        location /chunk_size {
            spdy_chunk_size 1;
            return 200 'body';
        }
        location /redirect {
            error_page 405 /s;
            return 405;
        }
        location /proxy {
            add_header X-Body "$request_body";
            proxy_pass http://127.0.0.1:8081/;
            proxy_cache NAME;
            proxy_cache_valid 1m;
        }
        location /header/ {
            proxy_pass http://127.0.0.1:8083/;
        }
        location /proxy_buffering_off {
            proxy_pass http://127.0.0.1:8081/;
            proxy_cache NAME;
            proxy_cache_valid 1m;
            proxy_buffering off;
        }
        location /t3.html {
            limit_conn conn 1;
        }
        location /set-cookie {
            add_header Set-Cookie val1;
            add_header Set-Cookie val2;
            return 200;
        }
        location /cookie {
            add_header X-Cookie $http_cookie;
            return 200;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:8083');

# file size is slightly beyond initial window size: 2**16 + 80 bytes

$t->write_file('t1.html',
	join('', map { sprintf "X%04dXXX", $_ } (1 .. 8202)));
$t->write_file('tbig.html',
	join('', map { sprintf "XX%06dXX", $_ } (1 .. 100000)));

$t->write_file('t2.html', 'SEE-THIS');
$t->write_file('t3.html', 'SEE-THIS');

my %cframe = (
	2 => \&syn_reply,
	3 => \&rst_stream,
	4 => \&settings,
	6 => \&ping,
	7 => \&goaway,
	9 => \&window_update
);

###############################################################################

# PING

my $sess = new_session();
spdy_ping($sess, 0x12345678);
my $frames = spdy_read($sess, all => [{ type => 'PING' }]);

my ($frame) = grep { $_->{type} eq "PING" } @$frames;
ok($frame, 'PING frame');
is($frame->{value}, 0x12345678, 'PING payload');

# GET

$sess = new_session();
my $sid1 = spdy_stream($sess, { path => '/s' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
ok($frame, 'SYN_REPLY frame');
is($frame->{sid}, $sid1, 'SYN_REPLY stream');
is($frame->{headers}->{':status'}, 200, 'SYN_REPLY status');
is($frame->{headers}->{'x-header'}, 'X-Foo', 'SYN_REPLY header');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'DATA frame');
is($frame->{length}, length 'body', 'DATA length');
is($frame->{data}, 'body', 'DATA payload');

# GET in new SPDY stream in same session

my $sid2 = spdy_stream($sess, { path => '/s' });
$frames = spdy_read($sess, all => [{ sid => $sid2, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{sid}, $sid2, 'SYN_REPLY stream 2');
is($frame->{headers}->{':status'}, 200, 'SYN_REPLY status 2');
is($frame->{headers}->{'x-header'}, 'X-Foo', 'SYN_REPLY header 2');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'DATA frame 2');
is($frame->{sid}, $sid2, 'SYN_REPLY stream 2');
is($frame->{length}, length 'body', 'DATA length 2');
is($frame->{data}, 'body', 'DATA payload 2');

# HEAD

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/s', method => 'HEAD' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{sid}, $sid1, 'SYN_REPLY stream HEAD');
is($frame->{headers}->{':status'}, 200, 'SYN_REPLY status HEAD');
is($frame->{headers}->{'x-header'}, 'X-Foo', 'SYN_REPLY header HEAD');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame, undef, 'HEAD no body');

# GET with PROXY protocol

my $proxy = 'PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678' . CRLF;
$sess = new_session(8082, proxy => $proxy);
$sid1 = spdy_stream($sess, { path => '/pp' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
ok($frame, 'PROXY SYN_REPLY frame');
is($frame->{headers}->{'x-pp'}, '192.0.2.1', 'PROXY remote addr');

# request header

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/t1.html',
	headers => { "range" =>  "bytes=10-19" }
});
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{':status'}, 206, 'SYN_REPLY status range');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{length}, 10, 'DATA length range');
is($frame->{data}, '002XXXX000', 'DATA payload range');

# request header with multiple values

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/cookie',
	headers => { "cookie" =>  "val1\0val2" }
});
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);
ok(grep ({ $_->{type} eq "SYN_REPLY" } @$frames),
	'multiple request header values');

# request header with multiple values proxied to http backend

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/proxy/cookie',
	headers => { "cookie" =>  "val1\0val2" }
});
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{'x-cookie'}, 'val1; val2',
	'multiple request header values - proxied');

# response header with multiple values

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/set-cookie' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{'set-cookie'}, "val1\0val2",
	'response header with multiple values');

# response header with multiple values - no empty values inside

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/header/inside' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{'x-foo'}, "val1\0val2", 'no empty header value inside');

$sid1 = spdy_stream($sess, { path => '/header/first' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{'x-foo'}, "val1\0val2", 'no empty header value first');

$sid1 = spdy_stream($sess, { path => '/header/last' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{'x-foo'}, "val1\0val2", 'no empty header value last');

# $spdy

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/spdy' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, '3.1', 'spdy variable');

# spdy_chunk_size=1

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/chunk_size' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

my @data = grep { $_->{type} eq "DATA" } @$frames;
is(@data, 4, 'chunk_size body chunks');
is($data[0]->{data}, 'b', 'chunk_size body 1');
is($data[1]->{data}, 'o', 'chunk_size body 2');
is($data[2]->{data}, 'd', 'chunk_size body 3');
is($data[3]->{data}, 'y', 'chunk_size body 4');

# redirect

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/redirect' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{':status'}, 405, 'SYN_REPLY status with redirect');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
ok($frame, 'DATA frame with redirect');
is($frame->{data}, 'body', 'DATA payload with redirect');

# SYN_REPLY could be received with fin, followed by DATA

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/proxy/t2.html', method => 'HEAD' });

$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);
push @$frames, $_ for @{spdy_read($sess, all => [{ sid => $sid1 }])};
ok(!grep ({ $_->{type} eq "DATA" } @$frames), 'proxy cache HEAD - no body');

# ensure that HEAD-like requests, i.e., without response body, do not lead to
# client connection close due to cache filling up with upstream response body

$sid2 = spdy_stream($sess, { path => '/' });
$frames = spdy_read($sess, all => [{ sid => $sid2, fin => 1 }]);
ok(grep ({ $_->{type} eq "SYN_REPLY" } @$frames), 'proxy cache headers only');

# HEAD on empty cache with proxy_buffering off

$sess = new_session();
$sid1 = spdy_stream($sess,
	{ path => '/proxy_buffering_off/t2.html?1', method => 'HEAD' });

$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);
push @$frames, $_ for @{spdy_read($sess, all => [{ sid => $sid1 }])};
ok(!grep ({ $_->{type} eq "DATA" } @$frames),
	'proxy cache HEAD buffering off - no body');

# simple proxy cache test

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/proxy/t2.html' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{':status'}, '200 OK', 'proxy cache unconditional');

$sid2 = spdy_stream($sess, { path => '/proxy/t2.html',
	headers => { "if-none-match" => $frame->{headers}->{'etag'} }
});
$frames = spdy_read($sess, all => [{ sid => $sid2, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{':status'}, 304, 'proxy cache conditional');

# request body (uses proxied response)

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/proxy/t2.html', body => 'TEST' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{'x-body'}, 'TEST', 'request body');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{length}, length 'SEE-THIS', 'proxied response length');
is($frame->{data}, 'SEE-THIS', 'proxied response');

# WINDOW_UPDATE (client side)

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/t1.html' });
$frames = spdy_read($sess, all => [{ sid => $sid1, length => 2**16 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
my $sum = eval join '+', map { $_->{length} } @data;
is($sum, 2**16, 'iws - stream blocked on initial window size');

spdy_ping($sess, 0xf00ff00f);
$frames = spdy_read($sess, all => [{ type => 'PING' }]);

($frame) = grep { $_->{type} eq "PING" } @$frames;
ok($frame, 'iws - PING not blocked');

spdy_window($sess, 2**16, $sid1);
$frames = spdy_read($sess);
is(@$frames, 0, 'iws - updated stream window');

spdy_window($sess, 2**16);
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 80, 'iws - updated connection window');

# SETTINGS (initial window size, client side)

$sess = new_session();
spdy_settings($sess, 7 => 2**17);
spdy_window($sess, 2**17);

$sid1 = spdy_stream($sess, { path => '/t1.html' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 2**16 + 80, 'increased initial window size');

# probe for negative available space in a flow control window

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/t1.html' });
spdy_read($sess, all => [{ sid => $sid1, length => 2**16 }]);

spdy_window($sess, 1);
spdy_settings($sess, 7 => 42);
spdy_window($sess, 1024, $sid1);

$frames = spdy_read($sess);
is(@$frames, 0, 'negative window - no data');

spdy_window($sess, 2**16 - 42 - 1024, $sid1);
$frames = spdy_read($sess);
is(@$frames, 0, 'zero window - no data');

spdy_window($sess, 1, $sid1);
$frames = spdy_read($sess, all => [{ sid => $sid1, length => 1 }]);
is(@$frames, 1, 'positive window - data');
is(@$frames[0]->{length}, 1, 'positive window - data length');

# ask write handler in sending large response

$sid1 = spdy_stream($sess, { path => '/tbig.html' });

spdy_window($sess, 2**30, $sid1);
spdy_window($sess, 2**30);

sleep 1;
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{':status'}, 200, 'large response - HEADERS');

@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 1000000, 'large response - DATA');

# stream multiplexing

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/t1.html' });
$frames = spdy_read($sess, all => [{ sid => $sid1, length => 2**16 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 2**16, 'multiple - stream1 data');

$sid2 = spdy_stream($sess, { path => '/t1.html' });
$frames = spdy_read($sess, all => [{ sid => $sid2, fin => 0 }]);

@data = grep { $_->{type} eq "DATA" } @$frames;
is(@data, 0, 'multiple - stream2 no data');

spdy_window($sess, 2**17, $sid1);
spdy_window($sess, 2**17, $sid2);
spdy_window($sess, 2**17);

$frames = spdy_read($sess, all => [
	{ sid => $sid1, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

@data = grep { $_->{type} eq "DATA" && $_->{sid} == $sid1 } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 80, 'multiple - stream1 remain data');

@data = grep { $_->{type} eq "DATA" && $_->{sid} == $sid2 } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 2**16 + 80, 'multiple - stream2 full data');

# request priority parsing in $spdy_request_priority

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/prio', prio => 0 });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 0, 'priority 0');

$sid1 = spdy_stream($sess, { path => '/prio', prio => 1 });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 1, 'priority 1');

$sid1 = spdy_stream($sess, { path => '/prio', prio => 7 });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 7, 'priority 7');

# stream multiplexing + priority

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/t1.html', prio => 7 });
spdy_read($sess, all => [{ sid => $sid1, length => 2**16 }]);

$sid2 = spdy_stream($sess, { path => '/t2.html', prio => 0 });
spdy_read($sess, all => [{ sid => $sid2, fin => 0 }]);

spdy_window($sess, 2**17, $sid1);
spdy_window($sess, 2**17, $sid2);
spdy_window($sess, 2**17);

$frames = spdy_read($sess, all => [
	{ sid => $sid1, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
is(join (' ', map { $_->{sid} } @data), "$sid2 $sid1", 'multiple priority 1');

# and vice versa

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/t1.html', prio => 0 });
spdy_read($sess, all => [{ sid => $sid1, length => 2**16 }]);

$sid2 = spdy_stream($sess, { path => '/t2.html', prio => 7 });
spdy_read($sess, all => [{ sid => $sid2, fin => 0 }]);

spdy_window($sess, 2**17, $sid1);
spdy_window($sess, 2**17, $sid2);
spdy_window($sess, 2**17);

$frames = spdy_read($sess, all => [
	{ sid => $sid1, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
is(join (' ', map { $_->{sid} } @data), "$sid1 $sid2", 'multiple priority 2');

# limit_conn

$sess = new_session();
spdy_settings($sess, 7 => 1);

$sid1 = spdy_stream($sess, { path => '/t3.html' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 0 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" && $_->{sid} == $sid1 } @$frames;
is($frame->{headers}->{':status'}, 200, 'conn_limit 1');

$sid2 = spdy_stream($sess, { path => '/t3.html' });
$frames = spdy_read($sess, all => [{ sid => $sid2, fin => 0 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" && $_->{sid} == $sid2 } @$frames;
is($frame->{headers}->{':status'}, 503, 'conn_limit 2');

spdy_settings($sess, 7 => 2**16);

spdy_read($sess, all => [
	{ sid => $sid1, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

# limit_conn + client's RST_STREAM

$sess = new_session();
spdy_settings($sess, 7 => 1);

$sid1 = spdy_stream($sess, { path => '/t3.html' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 0 }]);
spdy_rst($sess, $sid1, 5);

($frame) = grep { $_->{type} eq "SYN_REPLY" && $_->{sid} == $sid1 } @$frames;
is($frame->{headers}->{':status'}, 200, 'RST_STREAM 1');

$sid2 = spdy_stream($sess, { path => '/t3.html' });
$frames = spdy_read($sess, all => [{ sid => $sid2, fin => 0 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" && $_->{sid} == $sid2 } @$frames;
is($frame->{headers}->{':status'}, 200, 'RST_STREAM 2');

# GOAWAY on SYN_STREAM with even StreamID

TODO: {
local $TODO = 'not yet';

$sess = new_session();
spdy_stream($sess, { path => '/s' }, 2);
$frames = spdy_read($sess, all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'even stream - GOAWAY frame');
is($frame->{code}, 1, 'even stream - error code');
is($frame->{sid}, 0, 'even stream - last used stream');

}

# GOAWAY on SYN_STREAM with backward StreamID

TODO: {
local $TODO = 'not yet';

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/s' }, 3);
spdy_read($sess, all => [{ type => 'GOAWAY' }]);

$sid2 = spdy_stream($sess, { path => '/s' }, 1);
$frames = spdy_read($sess, all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'backward stream - GOAWAY frame');
is($frame->{code}, 1, 'backward stream - error code');
is($frame->{sid}, $sid1, 'backward stream - last used stream');

}

# RST_STREAM on the second SYN_STREAM with same StreamID

TODO: {
local $TODO = 'not yet';

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/s' }, 3);
spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);
$sid2 = spdy_stream($sess, { path => '/s' }, 3);
$frames = spdy_read($sess, all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
ok($frame, 'dup stream - RST_STREAM frame');
is($frame->{code}, 1, 'dup stream - error code');
is($frame->{sid}, $sid1, 'dup stream - stream');

}

# awkward protocol version

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/s', version => 'HTTP/1.10' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{':status'}, 200, 'awkward version');

# missing mandatory request header

$sess = new_session();
$sid1 = spdy_stream($sess, { path => '/s', version => '' });
$frames = spdy_read($sess, all => [{ sid => $sid1, fin => 1 }]);

($frame) = grep { $_->{type} eq "SYN_REPLY" } @$frames;
is($frame->{headers}->{':status'}, 400, 'incomplete headers');

# GOAWAY before closing a connection by server

$t->stop();

TODO: {
local $TODO = 'not yet';

$frames = spdy_read($sess, all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'GOAWAY on connection close');

}

###############################################################################

sub spdy_ping {
	my ($sess, $payload) = @_;

	raw_write($sess->{socket}, pack("N3", 0x80030006, 0x4, $payload));
}

sub spdy_rst {
	my ($sess, $sid, $error) = @_;

	raw_write($sess->{socket}, pack("N4", 0x80030003, 0x8, $sid, $error));
}

sub spdy_window {
	my ($sess, $win, $stream) = @_;

	$stream = 0 unless defined $stream;
	raw_write($sess->{socket}, pack("N4", 0x80030009, 8, $stream, $win));
}

sub spdy_settings {
	my ($sess, %extra) = @_;

	my $cnt = keys %extra;
	my $len = 4 + 8 * $cnt;

	my $buf = pack "N3", 0x80030004, $len, $cnt;
	$buf .= join '', map { pack "N2", $_, $extra{$_} } keys %extra;
	raw_write($sess->{socket}, $buf);
}

sub spdy_read {
	my ($sess, %extra) = @_;
	my ($length, @got);
	my $s = $sess->{socket};
	my $buf = '';

	while (1) {
		$buf = raw_read($s, $buf, 8);
		last unless length $buf;

		my $type = unpack("B", $buf);
		$length = 8 + hex unpack("x5 H6", $buf);
		$buf = raw_read($s, $buf, $length);
		last unless length $buf;

		if ($type == 0) {
			push @got, dframe($buf);

		} else {
			my $ctype = unpack("x2 n", $buf);
			push @got, $cframe{$ctype}($sess, $buf);
		}
		$buf = substr($buf, $length);

		last unless test_fin($got[-1], $extra{all});
	};
	return \@got;
}

sub test_fin {
	my ($frame, $all) = @_;
	my @test = @{$all};

	# wait for the specified DATA length

	for (@test) {
		if ($_->{length} && $frame->{type} eq 'DATA') {
			# check also for StreamID if needed

			if (!$_->{sid} || $_->{sid} == $frame->{sid}) {
				$_->{length} -= $frame->{length};
			}
		}
	}
	@test = grep { !(defined $_->{length} && $_->{length} == 0) } @test;

	# wait for the fin flag

	@test = grep { !(defined $_->{fin}
		&& $_->{sid} == $frame->{sid} && $_->{fin} == $frame->{fin})
	} @test if defined $frame->{fin};

	# wait for the specified frame

	@test = grep { !($_->{type} && $_->{type} eq $frame->{type}) } @test;

	@{$all} = @test;
}

sub dframe {
	my ($buf) = @_;
	my %frame;
	my $skip = 0;

	my $stream = unpack "\@$skip B32", $buf; $skip += 4;
	substr($stream, 0, 1) = 0;
	$stream = unpack("N", pack("B32", $stream));
	$frame{sid} = $stream;

	my $flags = unpack "\@$skip B8", $buf; $skip += 1;
	$frame{fin} = substr($flags, 7, 1);

	my $length = hex (unpack "\@$skip H6", $buf); $skip += 3;
	$frame{length} = $length;

	$frame{data} = substr($buf, $skip, $length);
	$frame{type} = "DATA";
	return \%frame;
}

sub spdy_stream {
	my ($ctx, $uri, $stream) = @_;
	my ($input, $output, $buf);
	my ($d, $status);

	my $host = $uri->{host} || '127.0.0.1:8080';
	my $method = $uri->{method} || 'GET';
	my $headers = $uri->{headers} || {};
	my $body = $uri->{body};
	my $prio = defined $uri->{prio} ? $uri->{prio} : 4;
	my $version = defined $uri->{version} ? $uri->{version} : "HTTP/1.1";

	if ($stream) {
		$ctx->{last_stream} = $stream;
	} else {
		$ctx->{last_stream} += 2;
	}

	$buf = pack("NC", 0x80030001, not $body);
	$buf .= pack("xxx");			# Length stub
	$buf .= pack("N", $ctx->{last_stream});	# Stream-ID
	$buf .= pack("N", 0);			# Assoc. Stream-ID
	$buf .= pack("n", $prio << 13);

	my $ent = 4 + keys %{$headers};
	$ent++ if $body;
	$ent++ if $version;

	$input = pack("N", $ent);
	$input .= hpack(":host", $host);
	$input .= hpack(":method", $method);
	$input .= hpack(":path", $uri->{path});
	$input .= hpack(":scheme", "http");
	if ($version) {
		$input .= hpack(":version", $version);
	}
	if ($body) {
		$input .= hpack("content-length", length $body);
	}
	$input .= join '', map { hpack($_, $headers->{$_}) } keys %{$headers};

	$d = $ctx->{zlib}->{d};
	$status = $d->deflate($input => \my $start);
	$status == Compress::Raw::Zlib->Z_OK or fail "deflate failed";
	$status = $d->flush(\my $tail => Compress::Raw::Zlib->Z_SYNC_FLUSH);
	$status == Compress::Raw::Zlib->Z_OK or fail "flush failed";
	$output = $start . $tail;

	# set length, attach headers and optional body

	$buf |= pack "x4N", length($output) + 10;
	$buf .= $output;

	if (defined $body) {
		$buf .= pack "NCxn", $ctx->{last_stream}, 0x01, length $body;
		$buf .= $body;
	}

	raw_write($ctx->{socket}, $buf);
	return $ctx->{last_stream};
}

sub syn_reply {
	my ($ctx, $buf) = @_;
	my ($i, $status);
	my %payload;
	my $skip = 4;

	my $flags = unpack "\@$skip B8", $buf; $skip += 1;
	$payload{fin} = substr($flags, 7, 1);

	my $length = hex unpack "\@$skip H6", $buf; $skip += 3;
	$payload{length} = $length;
	$payload{type} = 'SYN_REPLY';

	my $stream = unpack "\@$skip B32", $buf; $skip += 4;
	substr($stream, 0, 1) = 0;
	$stream = unpack("N", pack("B32", $stream));
	$payload{sid} = $stream;

	my $input = substr($buf, $skip, $length - 4);
	$i = $ctx->{zlib}->{i};

	$status = $i->inflate($input => \my $out);
	fail "Failed: $status" unless $status == Compress::Raw::Zlib->Z_OK;
	$payload{headers} = hunpack($out);
	return \%payload;
}

sub rst_stream {
	my ($ctx, $buf) = @_;
	my %payload;
	my $skip = 5;

	$payload{length} = hex(unpack "\@$skip H6", $buf); $skip += 3;
	$payload{type} = 'RST_STREAM';
	$payload{sid} = unpack "\@$skip N", $buf; $skip += 4;
	$payload{code} = unpack "\@$skip N", $buf;
	return \%payload;
}

sub settings {
	my ($ctx, $buf) = @_;
	my %payload;
	my $skip = 4;

	$payload{flags} = unpack "\@$skip H", $buf; $skip += 1;
	$payload{length} = hex(unpack "\@$skip H6", $buf); $skip += 3;
	$payload{type} = 'SETTINGS';

	my $nent = unpack "\@$skip N", $buf; $skip += 4;
	for (1 .. $nent) {
		my $flags = hex unpack "\@$skip H2", $buf; $skip += 1;
		my $id = hex unpack "\@$skip H6", $buf; $skip += 3;
		$payload{$id}{flags} = $flags;
		$payload{$id}{value} = unpack "\@$skip N", $buf; $skip += 4;
	}
	return \%payload;
}

sub ping {
	my ($ctx, $buf) = @_;
	my %payload;
	my $skip = 5;

	$payload{length} = hex(unpack "\@$skip H6", $buf); $skip += 3;
	$payload{type} = 'PING';
	$payload{value} = unpack "\@$skip N", $buf;
	return \%payload;
}

sub goaway {
	my ($ctx, $buf) = @_;
	my %payload;
	my $skip = 5;

	$payload{length} = hex unpack "\@$skip H6", $buf; $skip += 3;
	$payload{type} = 'GOAWAY';
	$payload{sid} = unpack "\@$skip N", $buf; $skip += 4;
	$payload{code} = unpack "\@$skip N", $buf;
	return \%payload;
}

sub window_update {
	my ($ctx, $buf) = @_;
	my %payload;
	my $skip = 5;

	$payload{length} = hex(unpack "\@$skip H6", $buf); $skip += 3;
	$payload{type} = 'WINDOW_UPDATE';

	my $stream = unpack "\@$skip B32", $buf; $skip += 4;
	substr($stream, 0, 1) = 0;
	$stream = unpack("N", pack("B32", $stream));
	$payload{sid} = $stream;

	my $value = unpack "\@$skip B32", $buf;
	substr($value, 0, 1) = 0;
	$payload{wdelta} = unpack("N", pack("B32", $value));
	return \%payload;
}

sub hpack {
	my ($name, $value) = @_;

	pack("N", length($name)) . $name . pack("N", length($value)) . $value;
}

sub hunpack {
	my ($data) = @_;
	my %headers;
	my $skip = 0;

	my $nent = unpack "\@$skip N", $data; $skip += 4;
	for (1 .. $nent) {
		my $len = unpack("\@$skip N", $data); $skip += 4;
		my $name = unpack("\@$skip A$len", $data); $skip += $len;

		$len = unpack("\@$skip N", $data); $skip += 4;
		my $value = unpack("\@$skip A$len", $data); $skip += $len;
		$value .= "\0" x ($len - length $value);

		$headers{$name} = $value;
	}
	return \%headers;
}

sub raw_read {
	my ($s, $buf, $len) = @_;
	my $got = '';

	while (length($buf) < $len && IO::Select->new($s)->can_read(1)) {
		$s->sysread($got, $len - length($buf)) or last;
		log_in($got);
		$buf .= $got;
	}
	return $buf;
}

sub raw_write {
	my ($s, $message) = @_;

	local $SIG{PIPE} = 'IGNORE';

	while (IO::Select->new($s)->can_write(0.4)) {
		log_out($message);
		my $n = $s->syswrite($message);
		last unless $n;
		$message = substr($message, $n);
		last unless length $message;
	}
}

sub new_session {
	my ($port, %extra) = @_;
	my ($d, $i, $status, $s);

	($d, $status) = Compress::Raw::Zlib::Deflate->new(
		-WindowBits => 12,
		-Dictionary => dictionary(),
		-Level => Compress::Raw::Zlib->Z_NO_COMPRESSION
	);
	fail "Zlib failure: $status" unless $d;

	($i, $status) = Compress::Raw::Zlib::Inflate->new(
		-WindowBits => Compress::Raw::Zlib->WANT_GZIP_OR_ZLIB,
		-Dictionary => dictionary()
	);
	fail "Zlib failure: $status" unless $i;

	$s = new_socket($port);

	if ($extra{proxy}) {
		raw_write($s, $extra{proxy});
	}

	return { zlib => { i => $i, d => $d },
		socket => $s, last_stream => -1 };
}

sub new_socket {
	my ($port) = @_;
	my $s;

	$port = 8080 unless defined $port;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		$s = IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => "127.0.0.1:$port",
		);
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	return $s;
}

sub dictionary {
	join('', (map pack('N/a*', $_), qw(
		options
		head
		post
		put
		delete
		trace
		accept
		accept-charset
		accept-encoding
		accept-language
		accept-ranges
		age
		allow
		authorization
		cache-control
		connection
		content-base
		content-encoding
		content-language
		content-length
		content-location
		content-md5
		content-range
		content-type
		date
		etag
		expect
		expires
		from
		host
		if-match
		if-modified-since
		if-none-match
		if-range
		if-unmodified-since
		last-modified
		location
		max-forwards
		pragma
		proxy-authenticate
		proxy-authorization
		range
		referer
		retry-after
		server
		te
		trailer
		transfer-encoding
		upgrade
		user-agent
		vary
		via
		warning
		www-authenticate
		method
		get
		status), "200 OK",
		qw(version HTTP/1.1 url public set-cookie keep-alive origin)),
		"100101201202205206300302303304305306307402405406407408409410",
		"411412413414415416417502504505",
		"203 Non-Authoritative Information",
		"204 No Content",
		"301 Moved Permanently",
		"400 Bad Request",
		"401 Unauthorized",
		"403 Forbidden",
		"404 Not Found",
		"500 Internal Server Error",
		"501 Not Implemented",
		"503 Service Unavailable",
		"Jan Feb Mar Apr May Jun Jul Aug Sept Oct Nov Dec",
		" 00:00:00",
		" Mon, Tue, Wed, Thu, Fri, Sat, Sun, GMT",
		"chunked,text/html,image/png,image/jpg,image/gif,",
		"application/xml,application/xhtml+xml,text/plain,",
		"text/javascript,public", "privatemax-age=gzip,deflate,",
		"sdchcharset=utf-8charset=iso-8859-1,utf-,*,enq=0."
	);
}

###############################################################################

# reply with multiple (also empty) header values

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => 8083,
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

		if ($uri eq '/inside') {

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Foo: val1
X-Foo:
X-Foo: val2

EOF

		} elsif ($uri eq '/first') {

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Foo:
X-Foo: val1
X-Foo: val2

EOF

		} elsif ($uri eq '/last') {

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Foo: val1
X-Foo: val2
X-Foo:

EOF
		}

	} continue {
		close $client;
	}
}

###############################################################################
