#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for the mp4_start_key_frame directive.

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

        location /force/ {
            mp4;
            mp4_start_key_frame on;
            alias %%TESTDIR%%/;
        }
    }
}

EOF

plan(skip_all => 'no lavfi')
	unless grep /lavfi/, `ffmpeg -loglevel quiet -formats`;
system('ffmpeg -nostdin -loglevel quiet -y '
	. '-f lavfi -i testsrc=duration=10:size=320x200:rate=15 '
	. '-pix_fmt yuv420p -g 15 -c:v h264 '
	. "${\($t->testdir())}/test.mp4") == 0
	or die "Can't create mp4 file: $!";
$t->run()->plan(4);

###############################################################################

# baseline durations

my $test_uri = '/test.mp4';
is(durations($t, 2.0, 4.0), '2.00', 'start at key frame');
isnt(durations($t, 2.1, 4.0), '1.90', 'start off key frame');

# with forced start at key frame

$test_uri = '/force/test.mp4';
is(durations($t, 2.0, 4.0), '2.00', 'start at key frame force');
is(durations($t, 2.1, 4.0), '1.90', 'start off key frame force');

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
	sprintf "%.2f", $r =~ /duration=(\d+\.\d+)/g;
}

###############################################################################
