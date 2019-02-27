#!/usr/bin/perl

# (C) Dmitry Lazurkin

# Tests for proxy_method.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(4)
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

        location /preserve {
            proxy_pass http://127.0.0.1:8080/get-method;
        }

        location /const {
            proxy_pass http://127.0.0.1:8080/get-method;
            proxy_method POST;
        }

        location /var {
            proxy_pass http://127.0.0.1:8080/get-method;
            proxy_method $arg_method;
        }

        location /parent {
            proxy_method POST;
            location /parent/child {
                proxy_pass http://127.0.0.1:8080/get-method;
            }
        }

        location /get-method {
            return 200 "request_method=$request_method";
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/preserve'), qr/request_method=GET/,
	'proxy_method from request');

like(http_get('/const'), qr/request_method=POST/,
	'proxy_method from constant');

like(http_get('/var?method=POST'), qr/request_method=POST/,
	'proxy_method from variable');

like(http_get('/parent/child'), qr/request_method=POST/,
	'proxy_method from parent');

###############################################################################
