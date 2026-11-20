#!/usr/bin/perl

# CVE-2026-123007: connection flow control must charge DATA that is queued
# but not fully sent against the window.
# Back pressure is produced with a small local TCP buffer and a large static
# response, without depending on external services or TLS.
# Entry: TEST_NGINX_BINARY=$PWD/objs/nginx prove \
#   -I tests/nginx-tests/nginx-tests/lib tests/nginx-tests/tengine-tests/h2_flow_control.t

use warnings;
use strict;
use Test::More;
use Socket qw/ SOL_SOCKET SO_RCVBUF /;
use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }
use lib '../nginx-tests/lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $max = 0x7fffffff;
my $default = 65535;
my $size = 1024 * 1024;
my $t = Test::Nginx->new()->has(qw/http http_v2/)->plan(14);

$t->write_file_expand('nginx.conf', <<'EOF');
%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log off;
    sendfile off;
    output_buffers 1 1m;

    server {
        listen 127.0.0.1:8080 sndbuf=4k;
        http2 on;
        server_name localhost;
        root %%TESTDIR%%;
    }
}
EOF

$t->write_file('tiny.html', 'ok');
$t->write_file('large.html', 'x' x $size);
$t->run();

# With an empty queue the exact limit is legal; one more byte returns a
# connection FLOW_CONTROL_ERROR.
my $s = Test::Nginx::HTTP2->new();
$s->h2_window($max - $default);
$s->h2_ping('boundary');
my $frames = $s->read(all => [{ type => 'PING' }]);
my ($frame) = grep { $_->{type} eq 'PING' } @$frames;
is($frame && $frame->{value}, 'boundary', 'empty queue: exact limit accepted');
$s->h2_window(1);
$frames = $s->read(all => [{ type => 'GOAWAY' }]);
($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
is($frame && $frame->{code}, 3, 'empty queue: limit plus one returns FLOW_CONTROL_ERROR');
close $s->{socket};

# Fully sent DATA must be written off, otherwise topping up by the number of
# bytes actually received would be wrongly rejected.
$s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ path => '/tiny.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;
is($frame && $frame->{headers}->{':status'}, 200, 'plain response: 200');
is(join('', map { $_->{data} } grep { $_->{type} eq 'DATA' } @$frames),
    'ok', 'plain response: body complete');
$s->h2_window($max - $default + 2);
$s->h2_ping('complete');
$frames = $s->read(all => [{ type => 'PING' }]);
($frame) = grep { $_->{type} eq 'PING' } @$frames;
is($frame && $frame->{value}, 'complete', 'full send: bytes actually sent can be topped up again');
close $s->{socket};

# The real vulnerability regression: the effective window reaches MAX first,
# and queued DATA must not free up room for a top-up.
# The TCP buffer is far smaller than the response, so the response cannot be
# fully sent before the client starts reading the body.
# Even if the server reads HEADERS and WINDOW_UPDATE in one go, the frame
# order still guarantees that queueing happens before the top-up.
$s = large_connection();
$sid = $s->new_stream({ path => '/large.html' });
select undef, undef, undef, 0.1;
# Top-up and cancel in a single write; the old code accepted the top-up and
# refunded the window above MAX on cancel.
$s->raw_write(
    pack('x2C2xNN', 4, 8, 0, $size) . pack('x2C2xNN', 4, 3, $sid, 8));
$frames = $s->read(all => [{ type => 'GOAWAY' }], wait => 1);
($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
# An unpatched baseline may close the connection outright when the socket
# is not writable, so GOAWAY cannot be sent.
# A timeout is not a close: only a real EOF (or a correct GOAWAY) counts as a
# successful rejection.
my $eof = 0;
if (!$frame && IO::Select->new($s->{socket})->can_read(1)) {
    my $byte;
    my $n = sysread($s->{socket}, $byte, 1);
    $eof = defined($n) && $n == 0;
}
ok($frame ? $frame->{code} == 3 : $eof,
    'back pressure queueing: illegal top-up rejected with an error or a closed connection');
like($t->read_file('error.log'),
    qr/client violated connection flow control:.*window increment $size not allowed/,
    'back pressure queueing: connection flow control violation logged for this top-up');
close $s->{socket};

# Legal cancel: only unsent frames are refunded and the connection stays
# usable; topping up the bytes actually received must land exactly on MAX.
$s = large_connection();
$sid = $s->new_stream({ path => '/large.html' });
select undef, undef, undef, 0.1;
$s->raw_write(
    pack('x2C2xNN', 4, 3, $sid, 8) . pack('x2C2x5a8', 8, 6, 'cancelok'));
$frames = $s->read(all => [{ type => 'PING' }]);
($frame) = grep { $_->{type} eq 'PING' } @$frames;
is($frame && $frame->{value}, 'cancelok', 'legal cancel: connection still answers PING');
my $sent = 0;
$sent += $_->{length} for grep { $_->{type} eq 'DATA' } @$frames;
ok($sent > 0 && $sent < $size, 'legal cancel: unsent response allowance really exists');
if ($sent) {
    $s->h2_window($sent);
}
$s->h2_ping('refunded');
$frames = $s->read(all => [{ type => 'PING' }]);
($frame) = grep { $_->{type} eq 'PING' } @$frames;
is($frame && $frame->{value}, 'refunded', 'legal cancel: top-up by bytes actually sent succeeds');
$sid = $s->new_stream({ path => '/tiny.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;
is($frame && $frame->{headers}->{':status'}, 200, 'legal cancel: new stream on the same connection succeeds');
$s->h2_window(2);
$s->h2_window(1);
$frames = $s->read(all => [{ type => 'GOAWAY' }]);
($frame) = grep { $_->{type} eq 'GOAWAY' } @$frames;
is($frame && $frame->{code}, 3, 'legal cancel: allowance neither lost nor refunded twice');
close $s->{socket};

# After the offending connection is closed, the worker still serves new
# connections.
$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/tiny.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;
is($frame && $frame->{headers}->{':status'}, 200, 'after violation: a new connection is still served');
close $s->{socket};
$t->stop();
unlike($t->read_file('error.log'), qr/exited on signal|Sanitizer/,
    'no worker crash or sanitizer error');

sub large_connection {
    my $client = Test::Nginx::HTTP2->new();
    setsockopt($client->{socket}, SOL_SOCKET, SO_RCVBUF, pack('i', 4096))
        or die "failed to set the local receive buffer: $!";
    $client->h2_settings(0, 4, $max);
    $client->h2_window($max - $default);
    $client->h2_ping('prepared');
    my $got = $client->read(all => [{ type => 'PING' }]);
    my ($ping) = grep { $_->{type} eq 'PING' } @$got;
    die "failed to set up the initial window for the large response test"
        unless $ping && $ping->{value} eq 'prepared';
    return $client;
}
