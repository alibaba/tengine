#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, js_path directive.

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

    js_path "%%TESTDIR%%/lib1";
    js_path "lib2";

    js_import test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /test {
            js_content test.test;
        }

        location /test2 {
            js_content test.test2;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    import m1 from 'module1.js';
    import m2 from 'module2.js';
    import m3 from 'lib1/module1.js';

    function test(r) {
        r.return(200, m1[r.args.fun](r.args.a, r.args.b));
    }

    function test2(r) {
        r.return(200, m2.sum(r.args.a, r.args.b));
    }

    function test3(r) {
        r.return(200, m3.sum(r.args.a, r.args.b));
    }

    export default {test, test2};

EOF

my $d = $t->testdir();

mkdir("$d/lib1");
mkdir("$d/lib2");

$t->write_file('lib1/module1.js', <<EOF);
    function sum(a, b) { return Number(a) + Number(b); }
    function prod(a, b) { return Number(a) * Number(b); }

    export default {sum, prod};

EOF

$t->write_file('lib2/module2.js', <<EOF);
    function sum(a, b) { return a + b; }

    export default {sum};

EOF


$t->try_run('no njs available')->plan(4);

###############################################################################

like(http_get('/test?fun=sum&a=3&b=4'), qr/7/s, 'test sum');
like(http_get('/test?fun=prod&a=3&b=4'), qr/12/s, 'test prod');
like(http_get('/test2?a=3&b=4'), qr/34/s, 'test2');
like(http_get('/test2?a=A&b=B'), qr/AB/s, 'test2 relative');

###############################################################################
