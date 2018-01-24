#!/usr/bin/perl

# (C) Sergey Kandaurov

# Tests for empty gif module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http empty_gif/)->plan(4);

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
            empty_gif;
        }
    }
}

EOF

$t->run();

my $gif = unhex(<<'EOF');
0x0000:  47 49 46 38 39 61 01 00  01 00 80 01 00 00 00 00  |GIF89a.. ........|
0x0010:  ff ff ff 21 f9 04 01 00  00 01 00 2c 00 00 00 00  |...!.... ...,....|
0x0020:  01 00 01 00 00 02 02 4c  01 00 3b                 |.......L ..;|
EOF

###############################################################################

is(http_get_body('/'), $gif, 'empty gif');
like(http_get('/'), qr!Content-Type: image/gif!i, 'get content type');
like(http_head('/'), qr!Content-Type: image/gif!i, 'head content type');
like(http('PUT / HTTP/1.0' . CRLF . CRLF), qr!405 Not Allowed!i, 'put');

###############################################################################

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

sub http_get_body {
	my ($uri) = @_;

	return undef if !defined $uri;

	my $text = http_get($uri);

	if ($text !~ /(.*?)\x0d\x0a?\x0d\x0a?(.*)/ms) {
		return undef;
	}

	return $2;
}

###############################################################################
