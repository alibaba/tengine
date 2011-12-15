#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for range filter module.

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

my $t = Test::Nginx->new()->has(qw/http charset/)->plan(31);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    charset_map B A {
        58 59; # X -> Y
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t2.html {
            charset A;
            source_charset B;
        }
    }
}

EOF

$t->write_file('t1.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->write_file('t2.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->run();

###############################################################################

my $t1;

$t1 = http_get_range('/t1.html', 'Range: bytes=0-8');
like($t1, qr/206/, 'range request - 206 partial reply');
like($t1, qr/Content-Length: 9/, 'range request - correct length');
like($t1, qr/Content-Range: bytes 0-8\/1000/, 'range request - content range');
like($t1, qr/^X000XXXXX$/m, 'range request - correct content');

$t1 = http_get_range('/t1.html', 'Range: bytes=-10');
like($t1, qr/206/, 'final bytes - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'final bytes - content length');
like($t1, qr/Content-Range: bytes 990-999\/1000/,
	'final bytes - content range');
like($t1, qr/^X099XXXXXX$/m, 'final bytes - correct content');

$t1 = http_get_range('/t1.html', 'Range: bytes=990-');
like($t1, qr/206/, 'final bytes explicit - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'final bytes explicit - content length');
like($t1, qr/Content-Range: bytes 990-999\/1000/,
	'final bytes explicit - content range');
like($t1, qr/^X099XXXXXX$/m, 'final bytes explicit - correct content');

$t1 = http_get_range('/t1.html', 'Range: bytes=990-1990');
like($t1, qr/206/, 'more than length - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'more than length - content length');
like($t1, qr/Content-Range: bytes 990-999\/1000/,
	'more than length - content range');
like($t1, qr/^X099XXXXXX$/m, 'more than length - correct content');

$t1 = http_get_range('/t2.html', 'Range: bytes=990-1990');
like($t1, qr/206/, 'recoded - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'recoded - content length');
like($t1, qr/Content-Range: bytes 990-999\/1000/, 'recoded - content range');
like($t1, qr/^Y099YYYYYY$/m, 'recoded - correct content');

$t1 = http_get_range('/t1.html', 'Range: bytes=0-9, -10, 10-19');
like($t1, qr/206/, 'multipart - 206 partial reply');
like($t1, qr/Content-Type: multipart\/byteranges; boundary=/,
	'multipart - content type');
like($t1, qr/X000XXXXXX/m, 'multipart - content 0-9');
like($t1, qr/^X099XXXXXX\x0d?$/m, 'multipart - content -10 aka 990-999');
like($t1, qr/X001XXXXXX\x0d?$/m, 'multipart - content 10-19');

$t1 = http_get_range('/t1.html', 'Range: bytes=0-9, -10, 100000-, 10-19');
like($t1, qr/206/, 'multipart big - 206 partial reply');
like($t1, qr/Content-Type: multipart\/byteranges; boundary=/,
        'multipart big - content type');
like($t1, qr/X000XXXXXX/m, 'multipart big - content 0-9');
like($t1, qr/^X099XXXXXX\x0d?$/m, 'multipart big - content -10 aka 990-999');
like($t1, qr/X001XXXXXX\x0d?$/m, 'multipart big - content 10-19');

like(http_get_range('/t1.html', 'Range: bytes=100000-'), qr/416/,
	'not satisfiable');

###############################################################################

sub http_get_range {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

###############################################################################
