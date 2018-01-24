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
use Test::Nginx;

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
system('ffmpeg -loglevel quiet -y '
	. '-f lavfi -i testsrc=duration=10:size=320x200:rate=15 '
	. '-f lavfi -i testsrc=duration=20:size=320x200:rate=15 '
	. '-map 0:0 -map 1:0 -pix_fmt yuv420p -g 15 -c:v libx264 '
	. "${\($t->testdir())}/test.mp4") == 0
	or die "Can't create mp4 file: $!";

$t->run()->plan(13);

###############################################################################

is(durations($t, 0.0), '10.0 20.0', 'start zero');
is(durations($t, 2), '8.0 18.0', 'start integer');
is(durations($t, 7.1), '2.9 12.9', 'start float');

is(durations($t, 6, 9), '3.0 3.0', 'start end integer');
is(durations($t, 2.7, 5.6), '2.9 2.9', 'start end float');

is(durations($t, undef, 9), '9.0 9.0', 'end integer');
is(durations($t, undef, 5.6), '5.6 5.6', 'end float');

# invalid range results in ignoring end argument

like(http_head('/test.mp4?start=1&end=1'), qr/200 OK/, 'zero range');
like(http_head('/test.mp4?start=1&end=0'), qr/200 OK/, 'negative range');

# start/end values exceeding track/file duration

unlike(http_head("/test.mp4?end=11"), qr!HTTP/1.1 500!,
	'end beyond short track');
unlike(http_head("/test.mp4?end=21"), qr!HTTP/1.1 500!, 'end beyond EOF');
unlike(http_head("/test.mp4?start=11"), qr!HTTP/1.1 500!,
	'start beyond short track');
like(http_head("/test.mp4?start=21"), qr!HTTP/1.1 500!, 'start beyond EOF');

###############################################################################

sub durations {
	my ($t, $start, $end) = @_;
	my $path = $t->{_testdir} . '/frag.mp4';

	my $uri = '/test.mp4';
	if (defined $start) {
		$uri .= "?start=$start";
		if (defined $end) {
			$uri .= "&end=$end";
		}

	} elsif (defined $end) {
		$uri .= "?end=$end";
	}

	$t->write_file('frag.mp4', Test::Nginx::http_content(http_get($uri)));

	my $r = `ffprobe -show_streams $path 2>/dev/null`;
	Test::Nginx::log_core('||', $r);
	sprintf "%.1f %.1f", $r =~ /duration=(\d+\.\d+)/g;
}

###############################################################################
