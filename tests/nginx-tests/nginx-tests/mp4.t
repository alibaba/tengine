#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for mp4 module.
# Ensures that requested stream duration is given with sane accuracy.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_content /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http mp4/)->has_daemon('ffprobe')
	->has_daemon('ffmpeg')
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            mp4;
        }
    }
}

EOF

plan(skip_all => 'no lavfi')
	unless grep /lavfi/, `ffmpeg -loglevel quiet -formats`;
system('ffmpeg -nostdin -loglevel quiet -y '
	. '-f lavfi -i testsrc=duration=10:size=320x200:rate=15 '
	. '-f lavfi -i testsrc=duration=20:size=320x200:rate=15 '
	. '-map 0:0 -map 1:0 -pix_fmt yuv420p -g 15 -c:v libx264 '
	. "${\($t->testdir())}/test.mp4") == 0
	or die "Can't create mp4 file: $!";
system('ffmpeg -nostdin -loglevel quiet -y '
	. '-f lavfi -i testsrc=duration=10:size=320x200:rate=15 '
	. '-f lavfi -i testsrc=duration=20:size=320x200:rate=15 '
	. '-map 0:0 -map 1:0 -pix_fmt yuv420p -g 15 -c:v libx264 '
	. '-movflags +faststart '
	. "${\($t->testdir())}/no_mdat.mp4") == 0
	or die "Can't create mp4 file: $!";

my $sbad = <<'EOF';
00000000:  00 00 00 1c 66 74 79 70  69 73 6f 6d 00 00 02 00  |....ftypisom....|
00000010:  69 73 6f 6d 69 73 6f 32  6d 70 34 31 00 00 00 09  |isomiso2mp41....|
00000020:  6d 64 61 74 00 00 00 00  94 6d 6f 6f 76 00 00 00  |mdat.....moov...|
00000030:  8c 74 72 61 6b 00 00 00  84 6d 64 69 61 00 00 00  |.trak....mdia...|
00000040:  7c 6d 69 6e 66 00 00 00  74 73 74 62 6c 00 00 00  ||minf...tstbl...|
00000050:  18 73 74 74 73 00 00 00  00 00 00 00 01 00 00 03  |.stts...........|
00000060:  3a 00 00 04 00 00 00 00  28 73 74 73 63 00 00 00  |:.......(stsc...|
00000070:  00 00 00 00 02 00 00 00  01 00 00 03 0f 00 00 00  |................|
00000080:  01 00 00 00 02 00 00 00  2b 00 00 00 01 00 00 00  |........+.......|
00000090:  14 73 74 73 7a 00 00 00  00 00 00 05 a9 00 00 03  |.stsz...........|
000000a0:  3b 00 00 00 18 63 6f 36  34 00 00 00 00 00 00 00  |;....co64.......|
000000b0:  01 ff ff ff ff f0 0f fb  e7                       |.........|
EOF

$t->write_file('bad.mp4', unhex($sbad));
$t->run()->plan(27);

###############################################################################

my $test_uri = '/test.mp4';

again:

is(durations($t, 0.0), '10.0 20.0', 'start zero');
is(durations($t, 2), '8.0 18.0', 'start integer');
is(durations($t, 7.1), '2.9 12.9', 'start float');

is(durations($t, 6, 9), '3.0 3.0', 'start end integer');
is(durations($t, 2.7, 5.6), '2.9 2.9', 'start end float');

is(durations($t, undef, 9), '9.0 9.0', 'end integer');
is(durations($t, undef, 5.6), '5.6 5.6', 'end float');

# invalid range results in ignoring end argument

like(http_head("$test_uri?start=1&end=1"), qr/200 OK/, 'zero range');
like(http_head("$test_uri?start=1&end=0"), qr/200 OK/, 'negative range');

# start/end values exceeding track/file duration

unlike(http_head("$test_uri?end=11"), qr!HTTP/1.1 500!,
	'end beyond short track');
unlike(http_head("$test_uri?end=21"), qr!HTTP/1.1 500!, 'end beyond EOF');
unlike(http_head("$test_uri?start=11"), qr!HTTP/1.1 500!,
	'start beyond short track');
like(http_head("$test_uri?start=21"), qr!HTTP/1.1 500!, 'start beyond EOF');

$test_uri = '/no_mdat.mp4', goto again unless $test_uri eq '/no_mdat.mp4';

# corrupted formats

like(http_get("/bad.mp4?start=0.5"), qr/500 Internal/, 'co64 chunk beyond EOF');

###############################################################################

sub durations {
	my ($t, $start, $end) = @_;
	my $path = $t->{_testdir} . '/frag.mp4';

	my $uri = $test_uri;
	if (defined $start) {
		$uri .= "?start=$start";
		if (defined $end) {
			$uri .= "&end=$end";
		}

	} elsif (defined $end) {
		$uri .= "?end=$end";
	}

	$t->write_file('frag.mp4', http_content(http_get($uri)));

	my $r = `ffprobe -show_streams $path 2>/dev/null`;
	Test::Nginx::log_core('||', $r);
	sprintf "%.1f %.1f", $r =~ /duration=(\d+\.\d+)/g;
}

sub unhex {
	my ($input) = @_;
	my $buffer = '';

	for my $l ($input =~ m/:  +((?:[0-9a-f]{2,4} +)+) /gms) {
		for my $v ($l =~ m/[0-9a-f]{2}/g) {
			$buffer .= chr(hex($v));
		}
	}

	return $buffer;
}

###############################################################################
