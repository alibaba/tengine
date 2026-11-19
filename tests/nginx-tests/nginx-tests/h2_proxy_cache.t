#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with cache.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy cache/)->plan(9)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path %%TESTDIR%%/cache    keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        listen       127.0.0.1:8081;
        server_name  localhost;

        http2 on;

        location /cache {
            proxy_pass http://127.0.0.1:8081/;
            proxy_cache NAME;
            proxy_cache_valid 1m;
        }

        location /proxy_buffering_off {
            proxy_pass http://127.0.0.1:8081/;
            proxy_cache NAME;
            proxy_cache_valid 1m;
            proxy_buffering off;
        }

        location / { }

        location /slow {
            limit_rate 200;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->write_file('slow.html', 'SEE-THIS');
$t->run();

###############################################################################

# simple proxy cache test

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ path => '/cache/t.html' });
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, '200', 'proxy cache');

my $etag = $frame->{headers}->{'etag'};

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{length}, length 'SEE-THIS', 'proxy cache - DATA');
is($frame->{data}, 'SEE-THIS', 'proxy cache - DATA payload');

$t->write_file('t.html', 'NOOP');

$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/cache/t.html' },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'if-none-match', value => $etag }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 304, 'proxy cache conditional');

$t->write_file('t.html', 'SEE-THIS');

# request body with cached response

$sid = $s->new_stream({ path => '/cache/t.html', body_more => 1 });
$s->h2_body('TEST');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'proxy cache - request body');

$s->h2_ping('SEE-THIS');
$frames = $s->read(all => [{ type => 'PING' }]);

($frame) = grep { $_->{type} eq "PING" && $_->{flags} & 0x1 } @$frames;
ok($frame, 'proxy cache - request body - next');

# HEADERS could be received with fin, followed by DATA

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/cache/t.html?1', method => 'HEAD' });

$frames = $s->read(all => [{ sid => $sid, fin => 1 }], wait => 0.2);
push @$frames, $_ for @{$s->read(all => [{ sid => $sid }], wait => 0.2)};
ok(!grep ({ $_->{type} eq "DATA" } @$frames), 'proxy cache HEAD - no body');

# HEAD on empty cache with proxy_buffering off

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream(
	{ path => '/proxy_buffering_off/t.html?1', method => 'HEAD' });

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
push @$frames, $_ for @{$s->read(all => [{ sid => $sid }], wait => 0.2)};
ok(!grep ({ $_->{type} eq "DATA" } @$frames),
	'proxy cache HEAD buffering off - no body');

SKIP: {
skip 'win32', 1 if $^O eq 'MSWin32';

# client cancels stream with a cacheable request that was sent to upstream
# HEADERS should not be produced for the canceled stream

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/cache/slow.html' });

$s->h2_rst($sid, 8);

$frames = $s->read(all => [{ sid => $sid, fin => 0x4 }], wait => 1.2);
ok(!(grep { $_->{type} eq "HEADERS" } @$frames), 'no headers');

}

# client closes connection after sending a cacheable request producing alert

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/cache/t.html?4' });

undef $s;
select undef, undef, undef, 0.2;

$t->stop();

###############################################################################
