#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (c) Nginx, Inc.

# Tests for http njs module, js_import directive in server | location contexts.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)
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

        js_set $test foo.bar.p;

        js_import foo from main.js;

        location /njs {
            js_content foo.version;
        }

        location /test_foo {
            js_content foo.test;
        }

        location /test_lib {
            js_import lib.js;
            js_content lib.test;
        }

        location /test_fun {
            js_import fun.js;
            js_content fun;
        }

        location /test_var {
            return 200 $test;
        }

        location /proxy {
            proxy_pass http://127.0.0.1:8081/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location /test_fun {
            js_import fun.js;
            js_content fun;
        }
    }
}

EOF

$t->write_file('lib.js', <<EOF);
    function test(r) {
        r.return(200, "LIB-TEST");
    }

    function p(r) {
        return "LIB-P";
    }

    export default {test, p};

EOF

$t->write_file('fun.js', <<EOF);
    export default function (r) {r.return(200, "FUN-TEST")};

EOF

$t->write_file('main.js', <<EOF);
    function version(r) {
        r.return(200, njs.version);
    }

    function test(r) {
        r.return(200, "MAIN-TEST");
    }

    export default {version, test, bar: {p(r) {return "P-TEST"}}};

EOF

$t->try_run('no njs available')->plan(5);

###############################################################################

like(http_get('/test_foo'), qr/MAIN-TEST/s, 'foo.test');
like(http_get('/test_lib'), qr/LIB-TEST/s, 'lib.test');
like(http_get('/test_fun'), qr/FUN-TEST/s, 'fun');
like(http_get('/proxy/test_fun'), qr/FUN-TEST/s, 'proxy fun');
like(http_get('/test_var'), qr/P-TEST/s, 'foo.bar.p');

###############################################################################
