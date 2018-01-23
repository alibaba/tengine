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

my $t = Test::Nginx->new()->has(qw/http charset/)->plan(41);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

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

        location /t3.html {
            max_ranges 2;
        }

        location /t4.html {
            max_ranges 0;
        }
    }
}

EOF

$t->write_file('t1.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->write_file('t2.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->write_file('t3.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->write_file('t4.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->run();

###############################################################################

my $t1;

$t1 = http_get_range('/t1.html', 'Range: bytes=0-8');
like($t1, qr/ 206 /, 'range request - 206 partial reply');
like($t1, qr/Content-Length: 9/, 'range request - correct length');
like($t1, qr/Content-Range: bytes 0-8\/1000/, 'range request - content range');
like($t1, qr/^X000XXXXX$/m, 'range request - correct content');

$t1 = http_get_range('/t1.html', 'Range: bytes=-10');
like($t1, qr/ 206 /, 'final bytes - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'final bytes - content length');
like($t1, qr/Content-Range: bytes 990-999\/1000/,
	'final bytes - content range');
like($t1, qr/^X099XXXXXX$/m, 'final bytes - correct content');

$t1 = http_get_range('/t1.html', 'Range: bytes=990-');
like($t1, qr/ 206 /, 'final bytes explicit - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'final bytes explicit - content length');
like($t1, qr/Content-Range: bytes 990-999\/1000/,
	'final bytes explicit - content range');
like($t1, qr/^X099XXXXXX$/m, 'final bytes explicit - correct content');

$t1 = http_get_range('/t1.html', 'Range: bytes=990-1990');
like($t1, qr/ 206 /, 'more than length - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'more than length - content length');
like($t1, qr/Content-Range: bytes 990-999\/1000/,
	'more than length - content range');
like($t1, qr/^X099XXXXXX$/m, 'more than length - correct content');

$t1 = http_get_range('/t2.html', 'Range: bytes=990-1990');
like($t1, qr/ 206 /, 'recoded - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'recoded - content length');
like($t1, qr/Content-Range: bytes 990-999\/1000/, 'recoded - content range');
like($t1, qr/^Y099YYYYYY$/m, 'recoded - correct content');

$t1 = http_get_range('/t1.html', 'Range: bytes=0-9, -10, 10-19');
like($t1, qr/ 206 /, 'multipart - 206 partial reply');
like($t1, qr/Content-Type: multipart\/byteranges; boundary=/,
	'multipart - content type');
like($t1, qr/X000XXXXXX/m, 'multipart - content 0-9');
like($t1, qr/^X099XXXXXX\x0d?$/m, 'multipart - content -10 aka 990-999');
like($t1, qr/X001XXXXXX\x0d?$/m, 'multipart - content 10-19');

$t1 = http_get_range('/t1.html', 'Range: bytes=0-9, -10, 100000-, 10-19');
like($t1, qr/ 206 /, 'multipart big - 206 partial reply');
like($t1, qr/Content-Type: multipart\/byteranges; boundary=/,
	'multipart big - content type');
like($t1, qr/X000XXXXXX/m, 'multipart big - content 0-9');
like($t1, qr/^X099XXXXXX\x0d?$/m, 'multipart big - content -10 aka 990-999');
like($t1, qr/X001XXXXXX\x0d?$/m, 'multipart big - content 10-19');

like(http_get_range('/t1.html', 'Range: bytes=100000-'), qr/ 416 /,
	'not satisfiable - too big first byte pos');
like(http_get_range('/t1.html', 'Range: bytes=alpha'), qr/ 416 /,
	'not satisfiable - alpha in first byte pos');
like(http_get_range('/t1.html', 'Range: bytes=10-alpha'), qr/ 416 /,
	'not satisfiable - alpha in last byte pos');
like(http_get_range('/t1.html', 'Range: bytes=10'), qr/ 416 /,
	'not satisfiable - no hyphen');
like(http_get_range('/t1.html', 'Range: bytes=10-11 12-'), qr/ 416 /,
	'not satisfiable - no comma');

# last-byte-pos is taken to be equal to one less than the current length
# of the entity-body in bytes -- rfc2616 sec 14.35.

like(http_get_range('/t1.html', 'Range: bytes=0-10001'), qr/ 206 /,
	'satisfiable - last byte pos adjusted');

# total size of all ranges is greater than source response size

like(http_get_range('/t1.html', 'Range: bytes=0-10001, 0-0'), qr/ 200 /,
	'not satisfiable - malicious byte ranges');

like(http_get_range('/t3.html', 'Range: bytes=0-9, -10'), qr/ 206 /,
	'max_ranges not reached');
like(http_get_range('/t3.html', 'Range: bytes=0-9, -10, 10000-'), qr/ 206 /,
	'max_ranges not reached bad range');
unlike(http_get_range('/t3.html', 'Range: bytes=0-9, -10, 10-19'),
	qr/ 206 /, 'max_ranges reached');
unlike(http_get_range('/t4.html', 'Range: bytes=0-9'), qr/ 206 /,
	'max_ranges zero');

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
