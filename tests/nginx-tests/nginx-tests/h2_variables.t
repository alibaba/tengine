#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with variables.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 rewrite/)->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2;
        server_name  localhost;

        location /h2 {
            return 200 $http2;
        }
        location /sp {
            return 200 $server_protocol;
        }
        location /scheme {
            return 200 $scheme;
        }
        location /https {
            return 200 "body $https";
        }
        location /rl {
            return 200 $request_length;
        }
    }
}

EOF

$t->run();

###############################################################################

# $http2

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ path => '/h2' });
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'h2c', 'http variable - h2c');

# $server_protocol

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/sp' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'HTTP/2.0', 'server_protocol variable');

# $scheme

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/scheme' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'http', 'scheme variable');

# $https

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/https' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'body ', 'https variable');

# $request_length, HEADERS payload length

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },		# 1
	{ name => ':scheme', value => 'http', mode => 0 },		# 1
	{ name => ':authority', value => 'localhost', mode => 1 },	# 1+1+9
	{ name => ':path', value => '/rl', mode => 1 }]});		# 1+1+3
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, '18', 'request length');

# $request_length, HEADERS+CONTINUATION payload length

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ continuation => 1, headers => [
	{ name => ':method', value => 'GET', mode => 0 },		# 1
	{ name => ':authority', value => 'localhost', mode => 1 },	# 1+1+9
	{ name => ':path', value => '/rl', mode => 1 }]});		# 1+1+3
$s->h2_continue($sid, { headers => [
	{ name => ':scheme', value => 'http', mode => 0 }]});		# 1
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, '18', 'request length');

###############################################################################
