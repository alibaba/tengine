#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, ES6 import, export.

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

my $t = Test::Nginx->new()->has(qw/http/)
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

        location /test {
            js_content test.test;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    import m from 'module.js';

    function test(r) {
        r.return(200, m[r.args.fun](r.args.a, r.args.b));
    }

    export default {test};

EOF

$t->write_file('module.js', <<EOF);
    function sum(a, b) {
        return Number(a) + Number(b);
    }

    function prod(a, b) {
        return Number(a) * Number(b);
    }

    export default {sum, prod};

EOF


$t->try_run('no njs modules')->plan(2);

###############################################################################

like(http_get('/test?fun=sum&a=3&b=4'), qr/7/s, 'test sum');
like(http_get('/test?fun=prod&a=3&b=4'), qr/12/s, 'test prod');

###############################################################################
