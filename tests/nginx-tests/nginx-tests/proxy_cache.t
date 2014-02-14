#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy cache gzip/)->plan(11)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:10m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        gzip on;
        gzip_min_length 0;

        location / {
            proxy_pass    http://127.0.0.1:8081;

            proxy_cache   NAME;

            proxy_cache_valid   200 302  1s;
            proxy_cache_valid   301      1d;
            proxy_cache_valid   any      1m;

            proxy_cache_min_uses  1;

            proxy_cache_use_stale  error timeout invalid_header http_500
                                   http_404;
        }
    }
    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->write_file('t2.html', 'SEE-THIS');
$t->write_file('empty.html', '');

$t->run();

###############################################################################

like(http_get('/t.html'), qr/SEE-THIS/, 'proxy request');

$t->write_file('t.html', 'NOOP');
like(http_get('/t.html'), qr/SEE-THIS/, 'proxy request cached');

unlike(http_head('/t2.html'), qr/SEE-THIS/, 'head request');
like(http_get('/t2.html'), qr/SEE-THIS/, 'get after head');
unlike(http_head('/t2.html'), qr/SEE-THIS/, 'head after get');

like(http_get_range('/t.html', 'Range: bytes=4-'), qr/^THIS/m, 'cached range');
like(http_get_range('/t.html', 'Range: bytes=0-2,4-'), qr/^SEE.*^THIS/ms,
	'cached multipart range');

like(http_get('/empty.html'), qr/HTTP/, 'empty get first');
like(http_get('/empty.html'), qr/HTTP/, 'empty get second');

select(undef, undef, undef, 1.1);
unlink $t->testdir() . '/t.html';
like(http_gzip_request('/t.html'),
	qr/HTTP.*1c\x0d\x0a.{28}\x0d\x0a0\x0d\x0a\x0d\x0a\z/s,
	'non-empty get stale');

unlink $t->testdir() . '/empty.html';
like(http_gzip_request('/empty.html'),
	qr/HTTP.*14\x0d\x0a.{20}\x0d\x0a0\x0d\x0a\x0d\x0a\z/s,
	'empty get stale');

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
