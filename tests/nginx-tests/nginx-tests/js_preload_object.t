#!/usr/bin/perl

# (C) Vadim Zhestikov
# (C) Nginx, Inc.

# Tests for http njs module, js_preload_object directive.

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

    js_preload_object g1 from g.json;
    js_preload_object ga from ga.json;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        js_import lib.js;
        js_preload_object lx from l.json;

        location /test {
            js_content lib.test;
        }

        location /test_query {
            js_import lib1.js;
            js_content lib1.query;
        }

        location /test_query_preloaded {
            js_import lib1.js;
            js_preload_object l.json;
            js_content lib1.query;
        }

        location /test_var {
            js_set $test_var lib.test_var;
            return 200 $test_var;
        }

        location /test_mutate {
            js_content lib.mutate;
        }

        location /test_no_suffix {
            js_preload_object gg from no_suffix;
            js_content lib.suffix;
        }
    }
}

EOF

$t->write_file('lib.js', <<EOF);
    function test(r) {
        r.return(200, ga + ' ' + g1.c.prop[0].a + ' ' + lx);
    }

    function test_var(r) {
        return g1.b[2];
    }

    function mutate(r) {
        var res = "OK";

        try {
            switch (r.args.method) {
            case 'set_obj':
                g1.c.prop[0].a = 5;
                break;
            case 'set_arr':
                g1.c.prop[0] = 5;
                break;
            case 'add_obj':
                g1.c.prop[0].xxx = 5;
                break;
            case 'add_arr':
                g1.c.prop[10] = 5;
                break;
            case 'del_obj':
                delete g1.c.prop[0].a;
                break;
            case 'del_arr':
                delete g1.c.prop[0];
                break;
            }

        } catch (e) {
            res = e.message;
        }

        r.return(200, res);
    }

    function suffix(r) {
        r.return(200, gg);
    }

    export default {test, test_var, mutate, suffix};

EOF

$t->write_file('lib1.js', <<EOF);
    function query(r) {
        var res = 'ok';

        try {
            res = r.args.path.split('.').reduce((a, v) => a[v], globalThis);

        } catch (e) {
            res = e.message;
        }

        r.return(200, njs.dump(res));
    }

    export default {query};

EOF

$t->write_file('g.json',
	'{"a":1, "b":[1,2,"element",4,5], "c":{"prop":[{"a":2}]}}');
$t->write_file('ga.json', '"ga loaded"');
$t->write_file('l.json', '"l loaded"');
$t->write_file('no_suffix', '"no_suffix loaded"');

$t->try_run('no js_preload_object available')->plan(12);

###############################################################################

like(http_get('/test'), qr/ga loaded 2 l loaded/s, 'direct query');
like(http_get('/test_query?path=l'), qr/undefined/s, 'unreferenced');
like(http_get('/test_query_preloaded?path=l'), qr/l loaded/s,
	'reference preload');
like(http_get('/test_query?path=g1.b.1'), qr/2/s, 'complex query');
like(http_get('/test_var'), qr/element/s, 'var reference');

like(http_get('/test_mutate?method=set_obj'), qr/Cannot assign to read-only/s,
	'preload_object props are const (object)');
like(http_get('/test_mutate?method=set_arr'), qr/Cannot assign to read-only/s,
	'preload_object props are const (array)');
like(http_get('/test_mutate?method=add_obj'), qr/Cannot add property "xxx"/s,
	'preload_object props are not extensible (object)');
like(http_get('/test_mutate?method=add_arr'), qr/Cannot add property "10"/s,
	'preload_object props are not extensible (array)');
like(http_get('/test_mutate?method=del_obj'), qr/Cannot delete property "a"/s,
	'preload_object props are not deletable (object)');
like(http_get('/test_mutate?method=del_arr'), qr/Cannot delete property "0"/s,
	'preload_object props are not deletable (array)');

like(http_get('/test_no_suffix'), qr/no_suffix loaded/s,
	'load without suffix');

###############################################################################
