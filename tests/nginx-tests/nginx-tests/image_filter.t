#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for image filter module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/CRLF/;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require GD; };
plan(skip_all => 'GD not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http proxy map image_filter/)->plan(39)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $arg_w $w {
        "" '-';
        default $arg_w;
    }
    map $arg_h $h {
        "" '-';
        default $arg_h;
    }

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

            location /test/off {
                image_filter off;
                alias %%TESTDIR%%/;
            }
        }

        location /resize {
            image_filter resize 10 12;
            alias %%TESTDIR%%/;
        }
        location /resize1 {
            image_filter resize 10 -;
            alias %%TESTDIR%%/;
        }
        location /resize2 {
            image_filter resize - 12;
            alias %%TESTDIR%%/;
        }
        location /resize_var {
            image_filter resize $w $h;
            alias %%TESTDIR%%/;
        }

        location /rotate {
            image_filter rotate 90;
            alias %%TESTDIR%%/;
        }
        location /rotate_var {
            image_filter rotate $arg_r;
            alias %%TESTDIR%%/;
        }

        location /crop {
            image_filter crop 60 80;
            alias %%TESTDIR%%/;
        }
        location /crop_var {
            image_filter crop $arg_w $arg_h;
            alias %%TESTDIR%%/;
        }
        location /crop_rotate {
            image_filter crop $arg_w $arg_h;
            image_filter rotate $arg_r;
            alias %%TESTDIR%%/;
        }
        location /resize_rotate {
            image_filter resize $w $h;
            image_filter rotate $arg_r;
            alias %%TESTDIR%%/;

            location /resize_rotate/resize {
                image_filter resize 10 12;
                alias %%TESTDIR%%/;
            }
        }

        location /interlaced {
            image_filter resize 10 12;
            image_filter_interlace on;
            alias %%TESTDIR%%/;
        }

        location /nontransparent {
            image_filter resize 10 12;
            image_filter_transparency off;
            alias %%TESTDIR%%/;
        }

        location /quality {
            image_filter resize 10 12;
            image_filter_jpeg_quality 50;
            alias %%TESTDIR%%/;
        }
        location /quality_var {
            image_filter resize 10 12;
            image_filter_jpeg_quality $arg_q;
            alias %%TESTDIR%%/;

            location /quality_var/quality {
                image_filter_jpeg_quality 60;
                alias %%TESTDIR%%/;
            }
        }

        location /buffer {
            image_filter test;
            image_filter_buffer 1k;
            alias %%TESTDIR%%/;
        }
        location /proxy_buffer {
            image_filter rotate 90;
            image_filter_buffer 20;
            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
            proxy_buffer_size 512;
        }
    }
}

EOF


my $im = new GD::Image(100, 120);
my $white = $im->colorAllocate(255, 255, 255);
my $black = $im->colorAllocate(0, 0, 0);

$im->transparent($white);
$im->rectangle(0, 0, 99, 99, $black);

$t->write_file('jpeg', $im->jpeg);
$t->write_file('gif', $im->gif);
$t->write_file('png', $im->png);
$t->write_file('txt', 'SEE-THIS');

$t->run_daemon(\&http_daemon, $t);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_head('/test/gif'), qr/200 OK/, 'test');
like(http_head('/test/gif'), qr!Content-Type: image/gif!, 'test content-type');
like(http_get('/test/txt'), qr/415 Unsupported/, 'test fail');
like(http_get('/test/off/txt'), qr/SEE-THIS/, 'off');

is(http_get_body('/size/txt'), '{}' . CRLF, 'size wrong type');
like(http_head('/size/txt'), qr!Content-Type: application/json!,
	'size content-type');
like(http_get('/size/jpeg'), qr/"width": 100/, 'size width');
like(http_get('/size/jpeg'), qr/"height": 120/, 'size height');
like(http_get('/size/jpeg'), qr/"type": "jpeg"/, 'size jpeg');
like(http_get('/size/gif'), qr/"type": "gif"/, 'size gif');
like(http_get('/size/png'), qr/"type": "png"/, 'size png');

is(gif_size('/resize/gif'), '10 12', 'resize');
is(gif_size('/resize1/gif'), '10 12', 'resize 1');
is(gif_size('/resize2/gif'), '10 12', 'resize 2');

is(gif_size('/resize_var/gif?w=10&h=12'), '10 12', 'resize var');
is(gif_size('/resize_var/gif?w=10'), '10 12', 'resize var 1');
is(gif_size('/resize_var/gif?h=12'), '10 12', 'resize var 2');

is(gif_size('/rotate/gif?r=90'), '120 100', 'rotate');
is(gif_size('/rotate_var/gif?r=180'), '100 120', 'rotate var 1');
is(gif_size('/rotate_var/gif?r=270'), '120 100', 'rotate var 2');

$im = GD::Image->newFromGifData(http_get_body('/gif'));
is($im->interlaced, 0, 'gif interlaced off');
is($im->transparent, 0, 'gif transparent white');

SKIP: {
skip 'broken libgd', 1 unless has_gdversion('2.1.0') or $ENV{TEST_NGINX_UNSAFE};

$im = GD::Image->newFromGifData(http_get_body('/interlaced/gif'));
is($im->interlaced, 1, 'gif interlaced on');

}

$im = GD::Image->newFromGifData(http_get_body('/nontransparent/gif'));
is($im->transparent, -1, 'gif transparent loss');

$im = GD::Image->newFromPngData(http_get_body('/png'));
is($im->interlaced, 0, 'png interlaced off');
is($im->transparent, 0, 'png transparent white');

# this test produces libpng warning on STDERR:
# "Interlace handling should be turned on when using png_read_image"

SKIP: {
skip 'can wedge nginx with SIGPIPE', 1 unless $ENV{TEST_NGINX_UNSAFE};

$im = GD::Image->newFromPngData(http_get_body('/interlaced/png'));
is($im->interlaced, 1, 'png interlaced on');

}

$im = GD::Image->newFromPngData(http_get_body('/nontransparent/png'));
is($im->transparent, -1, 'png transparent loss');

like(http_get('/resize/jpeg'), qr/quality = 75/, 'quality default');
like(http_get('/quality/jpeg'), qr/quality = 50/, 'quality');
like(http_get('/quality_var/jpeg?q=40'), qr/quality = 40/, 'quality var');
like(http_get('/quality_var/quality/jpeg?q=40'), qr/quality = 60/,
	'quality nested');

is(gif_size('/crop/gif'), '60 80', 'crop');
is(gif_size('/crop_var/gif?w=10&h=20'), '10 20', 'crop var');
is(gif_size('/crop_rotate/gif?w=5&h=6&r=90'), '5 5', 'rotate before crop');
is(gif_size('/resize_rotate/gif?w=5&h=6&r=90'), '6 5', 'rotate after resize');
is(gif_size('/resize_rotate/resize/gif??w=5&h=6&r=90'), '10 12',
	'resize rotate nested');

like(http_get('/buffer/jpeg'), qr/415 Unsupported/, 'small buffer');
isnt(http_get('/proxy_buffer/jpeg'), undef, 'small buffer proxy');

###############################################################################

sub gif_size {
	join ' ', unpack("x6v2", http_get_body(@_));
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

sub has_gdversion {
	my ($need) = @_;

	my $v_str = `gdlib-config --version 2>&1` or return 1;
	($v_str) = $v_str =~ m!^([0-9.]+)! or return 1;
	my @v = split(/\./, $v_str);
	my ($n, $v);

	for $n (split(/\./, $need)) {
		$v = shift @v || 0;
		return 0 if $n > $v;
		return 1 if $v > $n;
	}

	return 1;
}

###############################################################################

# serve static files without Content-Length

sub http_daemon {
	my ($t) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		next if $headers eq '';
		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;
		my $data = $t->read_file($uri);

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

$data
EOF

	} continue {
		close $client;
	}
}

###############################################################################
