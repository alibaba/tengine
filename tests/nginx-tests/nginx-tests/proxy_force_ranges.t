#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache and range filter.
# proxy_force_ranges enables partial response regardless Accept-Ranges.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache shmem/)->plan(4)
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
        }

        location /cache/ {
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   NAME;
            proxy_cache_valid 200 1m;

            proxy_force_ranges on;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            max_ranges 0;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->run();

###############################################################################

# serving range requests requires Accept-Ranges by default

unlike(http_get_range('/t.html', 'Range: bytes=4-'), qr/^THIS/m,
	'range without Accept-Ranges');

like(http_get_range('/cache/t.html', 'Range: bytes=4-'), qr/^THIS/m,
	'uncached range');
like(http_get_range('/cache/t.html', 'Range: bytes=4-'), qr/^THIS/m,
	'cached range');
like(http_get_range('/cache/t.html', 'Range: bytes=0-2,4-'), qr/^SEE.*^THIS/ms,
	'cached multipart range');

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
