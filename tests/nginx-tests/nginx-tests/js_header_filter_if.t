#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, header filter, if context.

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

    js_import test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /njs {
            js_content test.njs;
        }

        location / {
            if ($arg_name ~ "add") {
                js_header_filter test.add;
            }

            js_header_filter test.add2;

            proxy_pass http://127.0.0.1:8081/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            return 200;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function add(r) {
        r.headersOut['Foo'] = 'bar';
    }

    function add2(r) {
        r.headersOut['Bar'] = 'xxx';
    }

    export default {njs: test_njs, add, add2};

EOF

$t->try_run('no njs header filter')->plan(2);

###############################################################################

like(http_get('/?name=add'), qr/Foo: bar/, 'header filter if');
like(http_get('/'), qr/Bar: xxx/, 'header filter');

###############################################################################
