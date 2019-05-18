#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache and range filter.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache/)->plan(7)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;
            proxy_cache_valid 200 1m;
        }

        location /min_uses {
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   NAME;
            proxy_cache_valid 200 1m;
            proxy_cache_min_uses 2;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
        }

        location /tbig.html {
            limit_rate 50k;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');

# should not fit in a single proxy buffer

$t->write_file('tbig.html',
	join('', map { sprintf "XX%06dXX", $_ } (1 .. 7000)));

$t->run();

###############################################################################

like(http_get_range('/t.html?1', 'Range: bytes=4-'), qr/^THIS/m,
	'range on first request');

{
local $TODO = 'not yet';

like(http_get_range('/t.html?2', 'Range: bytes=0-2,4-'), qr/^SEE.*^THIS/ms,
	'multipart range on first request');
}

like(http_get_range('/t.html?1', 'Range: bytes=4-'), qr/^THIS/m,
	'cached range');
like(http_get_range('/t.html?1', 'Range: bytes=0-2,4-'), qr/^SEE.*^THIS/ms,
	'cached multipart range');

like(http_get_range('/min_uses/t.html?3', 'Range: bytes=4-'),
	qr/^THIS/m, 'range below min_uses');

like(http_get_range('/min_uses/t.html?4', 'Range: bytes=0-2,4-'),
	qr/^SEE.*^THIS/ms, 'multipart range below min_uses');

like(http_get_range('/tbig.html', 'Range: bytes=0-19'),
	qr/^XX000001XXXX000002XX$/ms, 'range of response received in parts');

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
