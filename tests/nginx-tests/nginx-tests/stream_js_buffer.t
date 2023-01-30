#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for stream njs module, buffer properties.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite stream stream_return/)
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

        location /p/ {
            proxy_pass http://127.0.0.1:8085/;
        }

        location /return {
            return 200 'RETURN:$http_foo';
        }
    }
}

stream {
    js_import test.js;

    js_set $type        test.type;
    js_set $binary_var  test.binary_var;

    server {
        listen  127.0.0.1:8081;
        return  $type;
    }

    server {
        listen  127.0.0.1:8082;
        return  $binary_var;
    }

    server {
        listen      127.0.0.1:8083;
        js_preread  test.cb_mismatch;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8084;
        js_preread  test.cb_mismatch2;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8085;
        js_filter   test.header_inject;
        proxy_pass  127.0.0.1:8080;
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function type(s) {
		var v = s.rawVariables.remote_addr;
		var type = Buffer.isBuffer(v) ? 'buffer' : (typeof v);
		return type;
    }

    function binary_var(s) {
        var test = s.rawVariables
                   .binary_remote_addr.equals(Buffer.from([127,0,0,1]));
        return test;
    }

    function cb_mismatch(s) {
        try {
            s.on('upload', () => {});
            s.on('downstream', () => {});
        } catch (e) {
            throw new Error(`cb_mismatch:\${e.message}`)
        }
    }

    function cb_mismatch2(s) {
        try {
            s.on('upstream', () => {});
            s.on('download', () => {});
        } catch (e) {
            throw new Error(`cb_mismatch2:\${e.message}`)
        }
    }

    function header_inject(s) {
        var req = Buffer.from([]);

        s.on('upstream', function(data, flags) {
            req = Buffer.concat([req, data]);

            var n = req.indexOf('\\n');
            if (n != -1) {
                var rest = req.slice(n + 1);
                req = req.slice(0, n + 1);

                s.send(req, flags);
                s.send('Foo: foo\\r\\n', flags);
                s.send(rest, flags);

                s.off('upstream');
            }
        });
    }

    export default {njs: test_njs, type, binary_var, cb_mismatch, cb_mismatch2,
                    header_inject};

EOF

$t->try_run('no njs ngx')->plan(5);

###############################################################################

TODO: {
local $TODO = 'not yet'
	unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.5.0';

is(stream('127.0.0.1:' . port(8081))->read(), 'buffer', 'var type');
is(stream('127.0.0.1:' . port(8082))->read(), 'true', 'binary var');

stream('127.0.0.1:' . port(8083))->io('x');
stream('127.0.0.1:' . port(8084))->io('x');

like(http_get('/p/return'), qr/RETURN:foo/, 'injected header');

$t->stop();

ok(index($t->read_file('error.log'), 'cb_mismatch:mixing string and buffer')
   > 0, 'cb mismatch');
ok(index($t->read_file('error.log'), 'cb_mismatch2:mixing string and buffer')
   > 0, 'cb mismatch');
}

###############################################################################
