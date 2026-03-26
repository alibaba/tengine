#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol, keepalive directives.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw(SOL_SOCKET SO_RCVBUF);

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2/)->plan(19)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    http2 on;

    server {
        listen       127.0.0.1:8080 sndbuf=1m;
        server_name  localhost;

        keepalive_requests 2;

        location / { }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        keepalive_timeout 0;

        location / { }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;

        keepalive_time 1s;

        add_header X-Conn $connection_requests:$connection_time;

        location / { }
    }
}

EOF

$t->write_file('index.html', 'SEE-THAT' x 50000);
$t->write_file('t.html', 'SEE-THAT');
$t->run();

###############################################################################

my $s = Test::Nginx::HTTP2->new();

# to test lingering close, let full response settle down in send buffer space
# so that client additional data past server-side close would trigger TCP RST

$s->{socket}->setsockopt(SOL_SOCKET, SO_RCVBUF, 64*1024) or die $!;
$s->h2_settings(0, 0x4 => 2**20);
$s->h2_window(2**21);

my $frames = $s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'max requests');

$frames = $s->read(all => [{ type => 'GOAWAY' }], wait => 0.5)
	unless grep { $_->{type} eq "GOAWAY" } @$frames;

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame, undef, 'max requests - GOAWAY');

# max requests limited

my $sid = $s->new_stream();

# wait server to finish and close socket if lingering close were disabled

select undef, undef, undef, 0.1;
$s->h2_ping("SEE-THIS");

$frames = $s->read(all => [{ sid => $sid, fin => 1 }, { type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'max requests limited');

my @data = grep { $_->{type} eq "DATA" } @$frames;
my $sum = eval join '+', map { $_->{length} } @data;
is($sum, 400000, 'max requests limited - all data received');

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'max requests limited - GOAWAY');
is($frame->{last_sid}, $sid, 'max requests limited - GOAWAY last stream');

# keepalive_timeout 0

$s = Test::Nginx::HTTP2->new(port(8081));
$sid = $s->new_stream({ path => '/t.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }, { type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'keepalive_timeout 0');

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'keepalive_timeout 0 - GOAWAY');

# keepalive_time

$s = Test::Nginx::HTTP2->new(port(8082));
$sid = $s->new_stream({ path => '/t.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'keepalive time request');
like($frame->{headers}->{'x-conn'}, qr/^1:0/, 'keepalive time variables');

$frames = $s->read(all => [{ type => 'GOAWAY' }], wait => 0.5);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame, undef, 'keepalive time - no GOAWAY yet');

select undef, undef, undef, 1.1;

$sid = $s->new_stream({ path => '/t.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }, { type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'keepalive time request 2');
like($frame->{headers}->{'x-conn'}, qr/^2:[^0]/, 'keepalive time variables 2');

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'keepalive time limit - GOAWAY');
is($frame->{last_sid}, $sid, 'keepalive time limit - GOAWAY last stream');

# graceful shutdown in idle state

$s = Test::Nginx::HTTP2->new();
$s->{socket}->setsockopt(SOL_SOCKET, SO_RCVBUF, 64*1024) or die $!;
$s->h2_settings(0, 0x4 => 2**20);
$s->h2_window(2**21);

$sid = $s->new_stream();

# wait server to finish and close socket if lingering close were disabled

select undef, undef, undef, 0.1;

$t->reload();

select undef, undef, undef, 0.3;

$s->h2_ping("SEE-THIS");

$frames = $s->read(all => [{ sid => $sid, fin => 1 }, { type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'graceful shutdown in idle');

@data = grep { $_->{type} eq "DATA" } @$frames;
$sum = eval join '+', map { $_->{length} } @data;
is($sum, 400000, 'graceful shutdown in idle - all data received');

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'graceful shutdown in idle - GOAWAY');
is($frame->{last_sid}, $sid, 'graceful shutdown in idle - GOAWAY last stream');

###############################################################################
