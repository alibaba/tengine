#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with limit_conn.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 limit_conn/)->plan(4)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_conn_zone  $binary_remote_addr  zone=conn:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        http2 on;

        location /t.html {
            limit_conn conn 1;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->run();

###############################################################################

my $s = Test::Nginx::HTTP2->new();
$s->h2_settings(0, 0x4 => 1);

my $sid = $s->new_stream({ path => '/t.html' });
my $frames = $s->read(all => [{ sid => $sid, length => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid } @$frames;
is($frame->{headers}->{':status'}, 200, 'limit_conn first stream');

my $sid2 = $s->new_stream({ path => '/t.html' });
$frames = $s->read(all => [{ sid => $sid2, length => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid2 } @$frames;
is($frame->{headers}->{':status'}, 503, 'limit_conn rejected');

$s->h2_settings(0, 0x4 => 2**16);

$s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

# limit_conn + client's RST_STREAM

$s = Test::Nginx::HTTP2->new();
$s->h2_settings(0, 0x4 => 1);

$sid = $s->new_stream({ path => '/t.html' });
$frames = $s->read(all => [{ sid => $sid, length => 1 }]);
$s->h2_rst($sid, 5);

($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid } @$frames;
is($frame->{headers}->{':status'}, 200, 'RST_STREAM 1');

$sid2 = $s->new_stream({ path => '/t.html' });
$frames = $s->read(all => [{ sid => $sid2, length => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid2 } @$frames;
is($frame->{headers}->{':status'}, 200, 'RST_STREAM 2');

###############################################################################
