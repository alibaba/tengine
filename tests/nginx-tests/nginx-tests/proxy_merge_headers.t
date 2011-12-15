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

my $t = Test::Nginx->new()->has(qw/http proxy cache rewrite/)->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:10m;

    proxy_set_header X-Blah "blah";

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_cache  NAME;

        location / {
            proxy_pass    http://127.0.0.1:8081;
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
            return 200 "ims=$http_if_modified_since;blah=$http_x_blah;";
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get_ims('/'), qr/ims=;blah=blah;/,
	'if-modified-since cleared with cache');

TODO: {
local $TODO = 'not yet';

like(http_get_ims('/no/'), qr/ims=blah;blah=blah;/,
	'if-modified-since preserved without cache');

}

TODO: {
local $TODO = 'not yet';

like(http_get_ims('/setbody/'), qr/blah=blah;/,
	'proxy_set_header inherited with proxy_set_body');

}

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
