#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, setting nginx variables.

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

    js_set $test_var   test.variable;

    js_import test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        set $foo       test.foo_orig;

        location /var_set {
            return 200 $test_var$foo;
        }

        location /content_set {
            js_content test.content_set;
        }

        location /not_found_set {
            js_content test.not_found_set;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function variable(r) {
        r.variables.foo = r.variables.arg_a;
        return 'test_var';
    }

    function content_set(r) {
        r.variables.foo = r.variables.arg_a;
        r.return(200, r.variables.foo);
    }

    function not_found_set(r) {
        try {
            r.variables.unknown = 1;
        } catch (e) {
            r.return(500, e);
        }
    }

    export default {variable, content_set, not_found_set};

EOF

$t->try_run('no njs')->plan(3);

###############################################################################

like(http_get('/var_set?a=bar'), qr/test_varbar/, 'var set');
like(http_get('/content_set?a=bar'), qr/bar/, 'content set');
like(http_get('/not_found_set'), qr/variable not found/, 'not found exception');

###############################################################################
