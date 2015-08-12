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

my $t = Test::Nginx->new()->has(qw/http flv/)->plan(12);

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
            flv;
        }
    }
}

EOF

$t->write_file('t1.flv',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->run();

###############################################################################

my $t1;

# FLV has 13 byte header at start.

$t1 = http_get_range('/t1.flv?start=100', 'Range: bytes=0-9');
like($t1, qr/206/, 'first bytes - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'first bytes - correct length');
like($t1, qr/Content-Range: bytes 0-9\/913/, 'first bytes - content range');
like($t1, qr/^FLV.{7}$/m, 'first bytes - correct content');

$t1 = http_get_range('/t1.flv?start=100', 'Range: bytes=-10');
like($t1, qr/206/, 'final bytes - 206 partial reply');
like($t1, qr/Content-Length: 10/, 'final bytes - content length');
like($t1, qr/Content-Range: bytes 903-912\/913/,
	'final bytes - content range');
like($t1, qr/^X099XXXXXX$/m, 'final bytes - correct content');

$t1 = http_get_range('/t1.flv?start=100', 'Range: bytes=0-99');
like($t1, qr/206/, 'multi buffers - 206 partial reply');
like($t1, qr/Content-Length: 100/, 'multi buffers - content length');
like($t1, qr/Content-Range: bytes 0-99\/913/, 'multi buffers - content range');
like($t1, qr/^FLV.{10}X010XXXXXX(X01[1-7]XXXXXX){7}X018XXX$/m,
	'multi buffers - correct content');

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
