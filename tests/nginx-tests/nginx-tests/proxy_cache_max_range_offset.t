#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache, proxy_cache_max_range_offset directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache/)
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
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   NAME;
            proxy_cache_valid 200 1m;
            proxy_cache_max_range_offset 2;
        }

        location /zero/ {
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   NAME;
            proxy_cache_valid 200 1m;
            proxy_cache_max_range_offset 0;
        }

        location /min_uses/ {
            proxy_pass    http://127.0.0.1:8081/;
            proxy_cache   NAME;
            proxy_cache_valid 200 1m;
            proxy_cache_max_range_offset 2;
            proxy_cache_min_uses 2;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Range $http_range;
        }
    }
}

EOF

$t->write_file('t.html', 'SEE-THIS');
$t->run()->plan(8);

###############################################################################

unlike(get('/t.html?1', 'bytes=1-'), qr/X-Range/, 'range - below');
like(get('/t.html?2', 'bytes=3-'), qr/X-Range/, 'range - above');
like(get('/t.html?3', 'bytes=-1'), qr/X-Range/, 'range - last');

TODO: {
local $TODO = 'not yet';

like(get('/t.html?4', 'bytes=1-1,3-'), qr/X-Range/, 'range - multipart above');

}

like(get('/zero/t.html?5', 'bytes=0-0'), qr/X-Range/, 'always non-cacheable');
like(get('/min_uses/t.html?6', 'bytes=1-'), qr/X-Range/, 'below min_uses');

# no range in client request

like(http_get('/t.html'), qr/SEE-THIS/, 'no range');

$t->write_file('t.html', 'NOOP');
like(http_get('/t.html'), qr/SEE-THIS/, 'no range - cached');

###############################################################################

sub get {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
Range: $extra

EOF
}

###############################################################################
