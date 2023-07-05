#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for server_tokens directive.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /200 {
            return 200;
        }

        location /404 {
            return 404;
        }

        location /off {
            server_tokens off;

            location /off/200 {
                return 200;
            }

            location /off/404 {
                return 404;
            }
        }

        location /on {
            server_tokens on;

            location /on/200 {
                return 200;
            }

            location /on/404 {
                return 404;
            }
        }

        location /b {
            server_tokens build;

            location /b/200 {
                return 200;
            }

            location /b/404 {
                return 404;
            }
        }
    }
}

EOF

$t->run()->plan(12);

###############################################################################

my $re = qr/nginx\/\d+\.\d+\.\d+/;

like(http_get_server('/200'), $re, 'tokens default 200');
like(http_get_server('/404'), $re, 'tokens default 404');
like(http_body('/404'), $re, 'tokens default 404 body');

is(http_get_server('/off/200'), 'nginx', 'tokens off 200');
is(http_get_server('/off/404'), 'nginx', 'tokens off 404');
like(http_body('/off/404'), qr/nginx(?!\/)/, 'tokens off 404 body');

like(http_get_server('/on/200'), $re, 'tokens on 200');
like(http_get_server('/on/404'), $re, 'tokens on 404');
like(http_body('/on/404'), $re, 'tokens on 404 body');

$re = qr/$re \(.*\)/ if $t->has_module('--build=');

like(http_get_server('/b/200'), $re, 'tokens build 200');
like(http_get_server('/b/404'), $re, 'tokens build 404');
like(http_body('/b/404'), $re, 'tokens build 404 body');

###############################################################################

sub http_body {
	my ($uri) = shift;
	return http_get($uri) =~ /.*?\x0d\x0a?\x0d\x0a?(.*)/ms && $1;
}

sub http_get_server {
	my ($url) = @_;
	return http_get($url) =~ /^Server:\s(.+?)\x0d?$/mi && $1 || undef;
}

###############################################################################
