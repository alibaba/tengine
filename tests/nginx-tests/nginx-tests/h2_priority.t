#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with priority.

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

my $t = Test::Nginx->new()->has(qw/http http_v2/)->plan(20)
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
    }
}

EOF

$t->run();

# file size is slightly beyond initial window size: 2**16 + 80 bytes

$t->write_file('t1.html',
	join('', map { sprintf "X%04dXXX", $_ } (1 .. 8202)));

$t->write_file('t2.html', 'SEE-THIS');

###############################################################################

# stream muliplexing + PRIORITY frames

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

my $sid2 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$s->h2_priority(0, $sid);
$s->h2_priority(255, $sid2);

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

my $frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

my @data = grep { $_->{type} eq "DATA" } @$frames;
is(join(' ', map { $_->{sid} } @data), "$sid2 $sid", 'weight - PRIORITY 1');

# and vice versa

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$s->h2_priority(255, $sid);
$s->h2_priority(0, $sid2);

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
is(join(' ', map { $_->{sid} } @data), "$sid $sid2", 'weight - PRIORITY 2');

# stream muliplexing + HEADERS PRIORITY flag

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/t1.html', prio => 0 });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html', prio => 255 });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
my $sids = join ' ', map { $_->{sid} } @data;
is($sids, "$sid2 $sid", 'weight - HEADERS PRIORITY 1');

# and vice versa

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/t1.html', prio => 255 });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html', prio => 0 });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 }
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sids = join ' ', map { $_->{sid} } @data;
is($sids, "$sid $sid2", 'weight - HEADERS PRIORITY 2');

# 5.3.1.  Stream Dependencies

# PRIORITY frame

$s = Test::Nginx::HTTP2->new();

$s->h2_priority(16, 3, 0);
$s->h2_priority(16, 1, 3);

$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 },
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sids = join ' ', map { $_->{sid} } @data;
is($sids, "$sid2 $sid", 'dependency - PRIORITY 1');

# and vice versa

$s = Test::Nginx::HTTP2->new();

$s->h2_priority(16, 1, 0);
$s->h2_priority(16, 3, 1);

$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 },
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sids = join ' ', map { $_->{sid} } @data;
is($sids, "$sid $sid2", 'dependency - PRIORITY 2');

# PRIORITY - self dependency

# 5.3.1.  Stream Dependencies
#   A stream cannot depend on itself.  An endpoint MUST treat this as a
#   stream error of type PROTOCOL_ERROR.

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream();
$s->read(all => [{ sid => $sid, fin => 1 }]);

$s->h2_priority(0, $sid, $sid);
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

my ($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{sid}, $sid, 'dependency - PRIORITY self - RST_STREAM');
is($frame->{code}, 1, 'dependency - PRIORITY self - PROTOCOL_ERROR');

# HEADERS PRIORITY flag, reprioritize prior PRIORITY frame records

$s = Test::Nginx::HTTP2->new();

$s->h2_priority(16, 1, 0);
$s->h2_priority(16, 3, 0);

$sid = $s->new_stream({ path => '/t1.html', dep => 3 });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 },
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sids = join ' ', map { $_->{sid} } @data;
is($sids, "$sid2 $sid", 'dependency - HEADERS PRIORITY 1');

# and vice versa

$s = Test::Nginx::HTTP2->new();

$s->h2_priority(16, 1, 0);
$s->h2_priority(16, 3, 0);

$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html', dep => 1 });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$s->h2_window(2**17, $sid);
$s->h2_window(2**17, $sid2);
$s->h2_window(2**17);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 },
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sids = join ' ', map { $_->{sid} } @data;
is($sids, "$sid $sid2", 'dependency - HEADERS PRIORITY 2');

# HEADERS - self dependency

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ dep => 1 });
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{sid}, $sid, 'dependency - HEADERS self - RST_STREAM');
is($frame->{code}, 1, 'dependency - HEADERS self - PROTOCOL_ERROR');

# PRIORITY frame, weighted dependencies

$s = Test::Nginx::HTTP2->new();

$s->h2_priority(16, 5, 0);
$s->h2_priority(255, 1, 5);
$s->h2_priority(0, 3, 5);

$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

my $sid3 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid3, fin => 0x4 }]);

$s->h2_window(2**16, 1);
$s->h2_window(2**16, 3);
$s->h2_window(2**16, 5);
$s->h2_window(2**16);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 },
	{ sid => $sid3, fin => 1 },
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sids = join ' ', map { $_->{sid} } @data;
is($sids, "$sid3 $sid $sid2", 'weighted dependency - PRIORITY 1');

# and vice versa

$s = Test::Nginx::HTTP2->new();

$s->h2_priority(16, 5, 0);
$s->h2_priority(0, 1, 5);
$s->h2_priority(255, 3, 5);

$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid2, fin => 0x4 }]);

$sid3 = $s->new_stream({ path => '/t2.html' });
$s->read(all => [{ sid => $sid3, fin => 0x4 }]);

$s->h2_window(2**16, 1);
$s->h2_window(2**16, 3);
$s->h2_window(2**16, 5);
$s->h2_window(2**16);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 },
	{ sid => $sid3, fin => 1 },
]);

@data = grep { $_->{type} eq "DATA" } @$frames;
$sids = join ' ', map { $_->{sid} } @data;
is($sids, "$sid3 $sid2 $sid", 'weighted dependency - PRIORITY 2');

# PRIORITY - reprioritization with circular dependency - after [3] removed
# initial dependency tree:
# 1 <- [3] <- 5

$s = Test::Nginx::HTTP2->new();

$s->h2_window(2**18);

$s->h2_priority(16, 1, 0);
$s->h2_priority(16, 3, 1);
$s->h2_priority(16, 5, 3);

$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid2, length => 2**16 - 1 }]);

$sid3 = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid3, length => 2**16 - 1 }]);

$s->h2_window(2**16, $sid2);

$frames = $s->read(all => [{ sid => $sid2, fin => 1 }]);
$sids = join ' ', map { $_->{sid} } grep { $_->{type} eq "DATA" } @$frames;
is($sids, $sid2, 'removed dependency');

for (1 .. 40) {
	$s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);
}

# make circular dependency
# 1 <- 5 -- current dependency tree before reprioritization
# 5 <- 1
# 1 <- 5

$s->h2_priority(16, 1, 5);
$s->h2_priority(16, 5, 1);

$s->h2_window(2**16, $sid);
$s->h2_window(2**16, $sid3);

$frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid3, fin => 1 },
]);

($frame) = grep { $_->{type} eq "DATA" && $_->{sid} == $sid } @$frames;
is($frame->{length}, 81, 'removed dependency - first stream');

($frame) = grep { $_->{type} eq "DATA" && $_->{sid} == $sid3 } @$frames;
is($frame->{length}, 81, 'removed dependency - last stream');

# PRIORITY - reprioritization with circular dependency - exclusive [5]
# 1 <- [5] <- 3

$s = Test::Nginx::HTTP2->new();

$s->h2_window(2**18);

$s->h2_priority(16, 1, 0);
$s->h2_priority(16, 3, 1);
$s->h2_priority(16, 5, 1, excl => 1);

$sid = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid, length => 2**16 - 1 }]);

$sid2 = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid2, length => 2**16 - 1 }]);

$sid3 = $s->new_stream({ path => '/t1.html' });
$s->read(all => [{ sid => $sid3, length => 2**16 - 1 }]);

$s->h2_window(2**16, $sid);

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
$sids = join ' ', map { $_->{sid} } grep { $_->{type} eq "DATA" } @$frames;
is($sids, $sid, 'exclusive dependency - parent removed');

# make circular dependency
# 5 <- 3 -- current dependency tree before reprioritization
# 3 <- 5

$s->h2_priority(16, 5, 3);

$s->h2_window(2**16, $sid2);
$s->h2_window(2**16, $sid3);

$frames = $s->read(all => [
	{ sid => $sid2, fin => 1 },
	{ sid => $sid3, fin => 1 },
]);

($frame) = grep { $_->{type} eq "DATA" && $_->{sid} == $sid2 } @$frames;
is($frame->{length}, 81, 'exclusive dependency - first stream');

($frame) = grep { $_->{type} eq "DATA" && $_->{sid} == $sid3 } @$frames;
is($frame->{length}, 81, 'exclusive dependency - last stream');

###############################################################################
