#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, request object.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

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

        location /to_string {
            js_content test.to_string;
        }

        location /define_prop {
            js_content test.define_prop;
        }

        location /in_operator {
            js_content test.in_operator;
        }

        location /redefine_bind {
            js_content test.redefine_bind;
        }

        location /redefine_proxy {
            js_content test.redefine_proxy;
        }

        location /redefine_proto {
            js_content test.redefine_proto;
        }

        location /get_own_prop_descs {
            js_content test.get_own_prop_descs;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function to_string(r) {
        r.return(200, r.toString());
    }

    function define_prop(r) {
        Object.defineProperty(r.headersOut, 'Foo', {value:'bar'});
        r.return(200);
    }

    function in_operator(r) {
        r.return(200, ['Foo', 'Bar'].map(v=>v in r.headersIn)
                      .toString() === 'true,false');
    }

    function redefine_bind(r) {
        r.return = r.return.bind(r, 200);
        r.return('redefine_bind');
    }

    function redefine_proxy(r) {
        r.return_orig = r.return;
        r.return = function (body) { this.return_orig(200, body);}
        r.return('redefine_proxy');
    }

    function redefine_proto(r) {
        r[0] = 'a';
        r[1] = 'b';
        r.length = 2;
        Object.setPrototypeOf(r, Array.prototype);
        r.return(200, r.join('|'));
    }

    function get_own_prop_descs(r) {
        r.return(200,
                 Object.getOwnPropertyDescriptors(r)['log'].value === r.log);
    }

    export default {to_string, define_prop, in_operator, redefine_bind,
                    redefine_proxy, redefine_proto, get_own_prop_descs};

EOF

$t->try_run('no njs request object')->plan(7);

###############################################################################

like(http_get('/to_string'), qr/\[object Request\]/, 'toString');
like(http_get('/define_prop'), qr/Foo: bar/, 'define_prop');
like(http(
	'GET /in_operator HTTP/1.0' . CRLF
	. 'Foo: foo' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/true/, 'in_operator');
like(http_get('/redefine_bind'), qr/redefine_bind/, 'redefine_bind');
like(http_get('/redefine_proxy'), qr/redefine_proxy/, 'redefine_proxy');
like(http_get('/redefine_proto'), qr/a|b/, 'redefine_proto');
like(http_get('/get_own_prop_descs'), qr/true/, 'get_own_prop_descs');

###############################################################################
