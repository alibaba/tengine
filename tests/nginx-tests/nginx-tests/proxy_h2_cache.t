#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

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

my $t = Test::Nginx->new()
	->has(qw/http http_v2 proxy cache gzip upstream_keepalive/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    upstream u {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        gzip on;
        gzip_min_length 0;

        location / {
            proxy_pass    http://127.0.0.1:8081;

            proxy_cache   NAME;

            proxy_http_version  2;

            proxy_cache_valid   200 302  2s;
            proxy_cache_valid   301      1d;
            proxy_cache_valid   any      1m;

            proxy_cache_min_uses  1;

            proxy_cache_use_stale  error timeout invalid_header http_500
                                   http_404;

            proxy_no_cache  $arg_e;

            add_header X-Cache-Status $upstream_cache_status;

            location /keepalive/ {
                proxy_pass http://u/;
            }
        }
    }
    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        http2 on;

        location / {
            limit_rate 512;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->write_file('t2.html', 'SEE-THIS');
$t->write_file('empty.html', '');
$t->write_file('big.html', 'x' x 1024);

$t->try_run('no proxy_http_version 2')->plan(19);

###############################################################################

like(http_get('/t.html'), qr/SEE-THIS/, 'proxy request');

$t->write_file('t.html', 'NOOP');
like(http_get('/t.html'), qr/SEE-THIS/, 'proxy request cached');

unlike(http_head('/t2.html'), qr/SEE-THIS/, 'head request');
like(http_get('/t2.html'), qr/SEE-THIS/, 'get after head');
unlike(http_head('/t2.html'), qr/SEE-THIS/, 'head after get');

like(http_head('/empty.html?head'), qr/MISS/, 'empty head first');
like(http_head('/empty.html?head'), qr/HIT/, 'empty head second');

like(http_get_range('/t.html', 'Range: bytes=4-'), qr/^THIS/m, 'cached range');
like(http_get_range('/t.html', 'Range: bytes=0-2,4-'), qr/^SEE.*^THIS/ms,
	'cached multipart range');

like(http_get('/empty.html'), qr/MISS/, 'empty get first');
like(http_get('/empty.html'), qr/HIT/, 'empty get second');

select(undef, undef, undef, 3.1);
unlink $t->testdir() . '/t.html';
like(http_gzip_request('/t.html'),
	qr/HTTP.*STALE.*1c\x0d\x0a.{28}\x0d\x0a0\x0d\x0a\x0d\x0a\z/s,
	'non-empty get stale');

unlink $t->testdir() . '/empty.html';
like(http_gzip_request('/empty.html'),
	qr/HTTP.*STALE.*14\x0d\x0a.{20}\x0d\x0a0\x0d\x0a\x0d\x0a\z/s,
	'empty get stale');

# no client connection close with response on non-cacheable HEAD requests
# see 573ec98d2 in nginx for detailed explanation

my $s = http(<<EOF, start => 1);
HEAD /big.html?e=1 HTTP/1.1
Host: localhost

EOF

my $r = http_get('/t.html', socket => $s);

like($r, qr/Connection: keep-alive/, 'non-cacheable head - keepalive');
like($r, qr/SEE-THIS/, 'non-cacheable head - second');

# check for HTTP/2 stream ID from a cached response needs to be skipped

like(http_get('/keepalive/t2.html?0'), qr/200 OK/, 'keepalive - first request');
like(http_get('/keepalive/t2.html?1'), qr/MISS/, 'keepalive - request');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.6');

like(http_get('/keepalive/t2.html?1'), qr/HIT/, 'keepalive - request cached');

$t->stop();

like(`grep -F '[crit]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no crits');

}

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
