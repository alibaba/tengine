#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache, "header already sent" alerts on backend errors,
# http://mailman.nginx.org/pipermail/nginx-devel/2018-January/010737.html.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache/)->plan(1)
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

            proxy_read_timeout 500ms;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            postpone_output 0;
            limit_rate 512;
            expires 1m;
        }
    }
}

EOF

$t->write_file('big.html', 'x' x 1024);

$t->run();

###############################################################################

# make a HEAD request; since cache is enabled, nginx converts HEAD to GET
# and will set u->pipe->downstream_error to suppress sending the response
# body to the client

like(http_head('/big.html'), qr/200 OK/, 'head request');

# once proxy_read_timeout expires, nginx will call
# ngx_http_finalize_upstream_request() with u->pipe->downstream_error set
# and rc = NGX_HTTP_BAD_GATEWAY; after revision ad3f342f14ba046c this
# will result in ngx_http_finalize_request(NGX_HTTP_BAD_GATEWAY),
# leading to an attempt to return additional error response and
# the "header already sent" alert; fixed in 93abb5a855d6

###############################################################################
