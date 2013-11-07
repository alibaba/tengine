#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for proxy_set_header inheritance.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy cache rewrite/)->plan(7)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:10m;

    proxy_set_header X-Blah "blah";
    proxy_hide_header X-Hidden;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_cache  NAME;

        location / {
            proxy_pass    http://127.0.0.1:8081;

            location /nested/ {
                proxy_pass   http://127.0.0.1:8081;
                proxy_pass_header X-Pad;
            }
        }

        location /no/ {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   off;
        }

        location /setbody/ {
            proxy_pass    http://127.0.0.1:8081;
            proxy_set_body "body";
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Hidden "hidden";
            add_header X-Pad "passed";
            return 200 "ims=$http_if_modified_since;blah=$http_x_blah;";
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get_ims('/'), qr/ims=;blah=blah;/,
	'if-modified-since cleared with cache');

like(http_get_ims('/no/'), qr/ims=blah;blah=blah;/,
	'if-modified-since preserved without cache');

like(http_get_ims('/setbody/'), qr/blah=blah;/,
	'proxy_set_header inherited with proxy_set_body');

unlike(http_get('/'), qr/X-Pad/, 'proxy_pass_header default');
like(http_get('/nested/'), qr/X-Pad/, 'proxy_pass_header nested');
unlike(http_get('/'), qr/X-Hidden/, 'proxy_hide_header inherited');
unlike(http_get('/nested/'), qr/X-Hidden/, 'proxy_hide_header nested');

###############################################################################

sub http_get_ims {
        my ($url) = @_;
        return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
Connection: close
If-Modified-Since: blah

EOF
}

###############################################################################
