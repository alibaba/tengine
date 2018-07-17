#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for mp4 module with range filter module.

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

my $t = Test::Nginx->new()->has(qw/http mp4/)->has_daemon('ffmpeg');

$t->write_file_expand('nginx.conf', <<'EOF');

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
	unless grep /lavfi/, `ffmpeg -nostdin -loglevel quiet -formats`;
system('ffmpeg -loglevel quiet -y '
	. '-f lavfi -i testsrc=duration=10:size=320x200:rate=15 '
	. "-pix_fmt yuv420p -c:v libx264 ${\($t->testdir())}/test.mp4") == 0
	or die "Can't create mp4 file: $!";

$t->run()->plan(13);

###############################################################################

# simply ensure that mp4 start argument works, we rely on this in range tests

my $fsz0 = http_head('/test.mp4') =~ /Content-Length: (\d+)/ && $1;
my $fsz = http_head('/test.mp4?start=1') =~ /Content-Length: (\d+)/ && $1;
isnt($fsz0, $fsz, 'mp4 start argument works');

my $t1;

# MP4 has minimally 16 byte ftyp object at start

my $start = $fsz - 10;
my $last = $fsz - 1;

$t1 = http_get_range('/test.mp4?start=1', 'Range: bytes=0-9');
like($t1, qr/ 206 /, 'first bytes - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'first bytes - content length');
like($t1, qr/Content-Range: bytes 0-9\/$fsz/, 'first bytes - content range');

$t1 = http_get_range('/test.mp4?start=1', 'Range: bytes=-10');
like($t1, qr/ 206 /, 'final bytes - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'final bytes - content length');
like($t1, qr/Content-Range: bytes $start-$last\/$fsz/,
	'final bytes - content range');

$t1 = http_get_range('/test.mp4?start=1', 'Range: bytes=0-99');
like($t1, qr/ 206 /, 'multi buffers - 206 partial reply');
like($t1, qr/Content-Length: 100/, 'multi buffers - content length');
like($t1, qr/Content-Range: bytes 0-99\/$fsz/,
	'multi buffers - content range');

TODO: {
local $TODO = 'multipart range on mp4';

$t1 = http_get_range('/test.mp4?start=1', 'Range: bytes=0-10,11-99');
like($t1, qr/ 206 /, 'multipart range - 206 partial reply');
like($t1, qr/Content-Length: 100/, 'multipart range - content length');
like($t1, qr/Content-Range: bytes 0-10,11-99\/$fsz/,
	'multipart range - content range');

}

###############################################################################

sub http_get_range {
	my ($url, $extra) = @_;
	return http(<<EOF);
HEAD $url HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

###############################################################################
