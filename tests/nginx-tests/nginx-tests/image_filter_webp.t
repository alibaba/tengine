#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for image filter module, WebP support.

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

my $t = Test::Nginx->new()->has(qw/http image_filter/)
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

        location /size {
            image_filter size;
            alias %%TESTDIR%%/;
        }

        location /test {
            image_filter test;
            alias %%TESTDIR%%/;
        }

        location /resize {
            image_filter resize 1 1;
            alias %%TESTDIR%%/;
        }

        location /quality {
            image_filter rotate 90;
            image_filter_webp_quality 50;
            alias %%TESTDIR%%/;
        }
        location /quality_var {
            image_filter rotate 90;
            image_filter_webp_quality $arg_q;
            alias %%TESTDIR%%/;
        }
    }
}

EOF

$t->run()->plan(18);

$t->write_file('webp', pack("A4LA8", "RIFF", 0x22, "WEBPVP8 ") .
	pack("N4", 0x16000000, 0x3001009d, 0x012a0100, 0x01000ec0) .
	pack("N2n", 0xfe25a400, 0x03700000, 0x0000));
$t->write_file('webpl', pack("A4LA8", "RIFF", 0x1a, "WEBPVP8L") .
	pack("N4n", 0x0d000000, 0x2f000000, 0x10071011, 0x118888fe, 0x0700));
$t->write_file('webpx', pack("A4LA8", "RIFF", 0x4a, "WEBPVP8X") .
	pack("N4", 0x0a000000, 0x10000000, 0x00000000, 0x0000414c) .
	pack("N4", 0x50480c00, 0x00001107, 0x1011fd0f, 0x4444ff03) .
	pack("N4", 0x00005650, 0x38201800, 0x00001401, 0x009d012a) .
	pack("N4n", 0x01000100, 0x0000fe00, 0x000dc000, 0xfee6b500, 0x0000));

$t->write_file('webperr', pack("A4LA8", "RIFF", 0x22, "WEBPERR ") .
	pack("N4", 0x16000000, 0x3001009d, 0x012a0100, 0x01000ec0) .
	pack("N2n", 0xfe25a400, 0x03700000, 0x0000));
$t->write_file('webptrunc', substr $t->read_file('webp'), 0, 29);

###############################################################################

my $r = http_get('/test/webp');
like($r, qr!Content-Type: image/webp!, 'content-type');
like($r, qr/RIFF/, 'content');

$r = http_get('/size/webp');
like($r, qr/"type": "webp"/, 'size type');
like($r, qr/"width": 1/, 'size width');
like($r, qr/"height": 1/, 'size height');

# lossless

$r = http_get('/size/webpl');
like($r, qr/"type": "webp"/, 'lossless type');
like($r, qr/"width": 1/, 'lossless width');
like($r, qr/"height": 1/, 'lossless height');

# extended

$r = http_get('/size/webpx');
like($r, qr/"type": "webp"/, 'extended type');
like($r, qr/"width": 1/, 'extended width');
like($r, qr/"height": 1/, 'extended height');

# transforms, libgd may have no WebP support

like(http_get('/quality/webp'), qr/RIFF|415/, 'quality');
like(http_get('/quality_var/webp?q=40'), qr/RIFF|415/, 'quality var');
like(http_get('/resize/webp'), qr/RIFF/, 'resize as is');

# generic error handling

like(http_get('/quality/webperr'), qr/415 Unsupported/, 'bad header');
like(http_get('/quality/webptrunc'), qr/415 Unsupported/, 'truncated');

like(http_get('/size/webperr'), qr/{}/, 'size - bad header');
like(http_get('/size/webptrunc'), qr/{}/, 'size - truncated');

###############################################################################
