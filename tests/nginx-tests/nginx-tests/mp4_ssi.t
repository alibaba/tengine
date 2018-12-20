#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Test for mp4 module in subrequests.

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

my $t = Test::Nginx->new()->has(qw/http mp4 ssi/)->has_daemon('ffprobe')
	->has_daemon('ffmpeg')->write_file_expand('nginx.conf', <<'EOF');

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
            ssi on;
        }
        location /ssi {
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
	. "${\($t->testdir())}/ssi.mp4") == 0
	or die "Can't create mp4 file: $!";

$t->write_file('index.html', 'X<!--#include virtual="/ssi.mp4?end=1" -->X');

$t->run()->plan(1);

###############################################################################

(my $r = get('/')) =~ s/([^\x20-\x7e])/sprintf('\\x%02x', ord($1))/gmxe;
unlike($r, qr/\\x0d(\\x0a)?0\\x0d(\\x0a)?\\x0d(\\x0a)?\w/, 'only final chunk');

###############################################################################

sub get {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close

EOF
}

###############################################################################
