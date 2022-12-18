#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, working with headers.

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

my $t = Test::Nginx->new()->has(qw/http charset/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    js_set $test_foo_in   test.foo_in;
    js_set $test_ifoo_in  test.ifoo_in;

    js_import test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /njs {
            js_content test.njs;
        }

        location /content_length {
            js_content test.content_length;
        }

        location /content_length_arr {
            js_content test.content_length_arr;
        }

        location /content_length_keys {
            js_content test.content_length_keys;
        }

        location /content_type {
            charset windows-1251;

            default_type text/plain;
            js_content test.content_type;
        }

        location /content_type_arr {
            charset windows-1251;

            default_type text/plain;
            js_content test.content_type_arr;
        }

        location /content_encoding {
            js_content test.content_encoding;
        }

        location /content_encoding_arr {
            js_content test.content_encoding_arr;
        }

        location /headers_list {
            js_content test.headers_list;
        }

        location /foo_in {
            return 200 $test_foo_in;
        }

        location /ifoo_in {
            return 200 $test_ifoo_in;
        }

        location /hdr_in {
            js_content test.hdr_in;
        }

        location /raw_hdr_in {
            js_content test.raw_hdr_in;
        }

        location /hdr_out {
            js_content test.hdr_out;
        }

        location /raw_hdr_out {
            js_content test.raw_hdr_out;
        }

        location /hdr_out_array {
            js_content test.hdr_out_array;
        }

        location /hdr_out_set_cookie {
            js_content test.hdr_out_set_cookie;
        }

        location /hdr_out_single {
            js_content test.hdr_out_single;
        }

        location /ihdr_out {
            js_content test.ihdr_out;
        }

        location /hdr_sorted_keys {
            js_content test.hdr_sorted_keys;
        }

        location /hdr_out_special_set {
            js_content test.hdr_out_special_set;
        }

        location /copy_subrequest_hdrs {
            js_content test.copy_subrequest_hdrs;
        }

        location = /subrequest {
            internal;

            js_content test.subrequest;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function content_length(r) {
        if (njs.version_number >= 0x000705) {
            var clength = r.headersOut['Content-Length'];
            if (clength !== undefined) {
                r.return(500, `Content-Length "\${clength}" is not empty`);
                return;
            }
        }

        delete r.headersOut['Content-Length'];
        r.headersOut['Content-Length'] = '';
        r.headersOut['Content-Length'] = 3;
        delete r.headersOut['Content-Length'];
        r.headersOut['Content-Length'] = 3;
        r.sendHeader();
        r.send('XXX');
        r.finish();
    }

    function content_length_arr(r) {
        r.headersOut['Content-Length'] = [5];
        r.headersOut['Content-Length'] = [];
        r.headersOut['Content-Length'] = [4,3];
        r.sendHeader();
        r.send('XXX');
        r.finish();
    }

    function content_length_keys(r) {
        r.headersOut['Content-Length'] = 3;
        var in_keys = Object.keys(r.headersOut).some(v=>v=='Content-Length');
        r.return(200, `B:\${in_keys}`);
    }

    function content_type(r) {
        if (njs.version_number >= 0x000705) {
            var ctype = r.headersOut['Content-Type'];
            if (ctype !== undefined) {
                r.return(500, `Content-Type "\${ctype}" is not empty`);
                return;
            }
        }

        delete r.headersOut['Content-Type'];
        r.headersOut['Content-Type'] = 'text/xml';
        r.headersOut['Content-Type'] = '';
        r.headersOut['Content-Type'] = 'text/xml; charset=';
        delete r.headersOut['Content-Type'];
        r.headersOut['Content-Type'] = 'text/xml; charset=utf-8';
        r.headersOut['Content-Type'] = 'text/xml; charset="utf-8"';
        var in_keys = Object.keys(r.headersOut).some(v=>v=='Content-Type');
        r.return(200, `B:\${in_keys}`);
    }

    function content_type_arr(r) {
        r.headersOut['Content-Type'] = ['text/html'];
        r.headersOut['Content-Type'] = [];
        r.headersOut['Content-Type'] = [ 'text/xml', 'text/html'];
        r.return(200);
    }

    function content_encoding(r) {
        if (njs.version_number >= 0x000705) {
            var ce = r.headersOut['Content-Encoding'];
            if (ce !== undefined) {
                r.return(500, `Content-Encoding "\${ce}" is not empty`);
                return;
            }
        }

        delete r.headersOut['Content-Encoding'];
        r.headersOut['Content-Encoding'] = '';
        r.headersOut['Content-Encoding'] = 'test';
        delete r.headersOut['Content-Encoding'];
        r.headersOut['Content-Encoding'] = 'gzip';
        r.return(200);
    }

    function content_encoding_arr(r) {
        r.headersOut['Content-Encoding'] = 'test';
        r.headersOut['Content-Encoding'] = [];
        r.headersOut['Content-Encoding'] = ['test', 'gzip'];
        r.return(200);
    }

    function headers_list(r) {
        for (var h in {a:1, b:2, c:3}) {
            r.headersOut[h] = h;
        }

        delete r.headersOut.b;
        r.headersOut.d = 'd';

        var out = "";
        for (var h in r.headersOut) {
            out += h + ":";
        }

        r.return(200, out);
    }

    function hdr_in(r) {
        var s = '', h;
        for (h in r.headersIn) {
            s += `\${h.toLowerCase()}: \${r.headersIn[h]}\n`;
        }

        r.return(200, s);
    }

    function raw_hdr_in(r) {
        var filtered = r.rawHeadersIn
                       .filter(v=>v[0].toLowerCase() == r.args.filter);
        r.return(200, 'raw:' + filtered.map(v=>v[1]).join('|'));
    }

    function hdr_sorted_keys(r) {
        var s = '';
        var hdr = r.args.in ? r.headersIn : r.headersOut;

        if (!r.args.in) {
            r.headersOut.b = 'b';
            r.headersOut.c = 'c';
            r.headersOut.a = 'a';
        }

        r.return(200, Object.keys(hdr).sort());
    }

    function foo_in(r) {
        return 'hdr=' + r.headersIn.foo;
    }

    function ifoo_in(r) {
        var s = '', h;
        for (h in r.headersIn) {
            if (h.substr(0, 3) == 'foo') {
                s += r.headersIn[h];
            }
        }
        return s;
    }

    function hdr_out(r) {
        r.status = 200;
        r.headersOut['Foo'] = r.args.foo;

        if (r.args.bar) {
            r.headersOut['Bar'] =
                r.headersOut[(r.args.bar == 'empty' ? 'Baz' :'Foo')]
        }

        r.sendHeader();
        r.finish();
    }

    function raw_hdr_out(r) {
        r.headersOut.a = ['foo', 'bar'];
        r.headersOut.b = 'b';

        var filtered = r.rawHeadersOut
                       .filter(v=>v[0].toLowerCase() == r.args.filter);
        r.return(200, 'raw:' + filtered.map(v=>v[1]).join('|'));
    }

    function hdr_out_array(r) {
        if (!r.args.hidden) {
            r.headersOut['Foo'] = [r.args.foo];
            r.headersOut['Foo'] = [];
            r.headersOut['Foo'] = ['bar', r.args.foo];
        }

        if (r.args.scalar_set) {
            r.headersOut['Foo'] = 'xxx';
        }

        r.return(200, `B:\${njs.dump(r.headersOut.foo)}`);
    }

    function hdr_out_single(r) {
        r.headersOut.ETag = ['a', 'b'];
        r.return(200, `B:\${njs.dump(r.headersOut.etag)}`);
    }

    function hdr_out_set_cookie(r) {
        r.headersOut['Set-Cookie'] = [];
        r.headersOut['Set-Cookie'] = ['a', 'b'];
        delete r.headersOut['Set-Cookie'];
        r.headersOut['Set-Cookie'] = 'e';
        r.headersOut['Set-Cookie'] = ['c', '', null, 'd', 'f'];

        r.return(200, `B:\${njs.dump(r.headersOut['Set-Cookie'])}`);
    }

    function ihdr_out(r) {
        r.status = 200;
        r.headersOut['a'] = r.args.a;
        r.headersOut['b'] = r.args.b;

        var s = '', h;
        for (h in r.headersOut) {
            s += r.headersOut[h];
        }

        r.sendHeader();
        r.send(s);
        r.finish();
    }

    function hdr_out_special_set(r) {
        r.headersOut['Foo'] = "xxx";
        r.headersOut['Content-Encoding'] = 'abc';

        let ce = r.headersOut['Content-Encoding'];
        r.return(200, `CE: \${ce}`);
    }

    async function copy_subrequest_hdrs(r) {
        let resp = await r.subrequest("/subrequest");

        for (const h in resp.headersOut) {
            r.headersOut[h] = resp.headersOut[h];
        }

        r.return(200, resp.responseText);
    }

    function subrequest(r) {
        r.headersOut['A'] = 'a';
        r.headersOut['Content-Encoding'] = 'ce';
        r.headersOut['B'] = 'b';
        r.headersOut['C'] = 'c';
        r.headersOut['D'] = 'd';
        r.headersOut['Set-Cookie'] = ['A', 'BB'];
        r.headersOut['Content-Length'] = 3;
        r.headersOut['Content-Type'] = 'ct';
        r.sendHeader();
        r.send('XXX');
        r.finish();
    }

    export default {njs:test_njs, content_length, content_length_arr,
                    content_length_keys, content_type, content_type_arr,
                    content_encoding, content_encoding_arr, headers_list,
                    hdr_in, raw_hdr_in, hdr_sorted_keys, foo_in, ifoo_in,
                    hdr_out, raw_hdr_out, hdr_out_array, hdr_out_single,
                    hdr_out_set_cookie, ihdr_out, hdr_out_special_set,
                    copy_subrequest_hdrs, subrequest};


EOF

$t->try_run('no njs')->plan(42);

###############################################################################

like(http_get('/content_length'), qr/Content-Length: 3/,
	'set Content-Length');
like(http_get('/content_type'), qr/Content-Type: text\/xml; charset="utf-8"\r/,
	'set Content-Type');
unlike(http_get('/content_type'), qr/Content-Type: text\/plain/,
	'set Content-Type 2');
like(http_get('/content_encoding'), qr/Content-Encoding: gzip/,
	'set Content-Encoding');
like(http_get('/headers_list'), qr/a:c:d/, 'headers list');

like(http_get('/ihdr_out?a=12&b=34'), qr/^1234$/m, 'r.headersOut iteration');
like(http_get('/ihdr_out'), qr/\x0d\x0a?\x0d\x0a?$/m, 'r.send zero');
like(http_get('/hdr_out?foo=12345'), qr/Foo: 12345/, 'r.headersOut');
like(http_get('/hdr_out?foo=123&bar=copy'), qr/Bar: 123/, 'r.headersOut get');
unlike(http_get('/hdr_out?bar=empty'), qr/Bar:/, 'r.headersOut empty');
unlike(http_get('/hdr_out?foo='), qr/Foo:/, 'r.headersOut no value');
unlike(http_get('/hdr_out?foo'), qr/Foo:/, 'r.headersOut no value 2');

like(http_get('/content_length_keys'), qr/B:true/, 'Content-Length in keys');
like(http_get('/content_length_arr'), qr/Content-Length: 3/,
	'set Content-Length arr');

like(http_get('/content_type'), qr/B:true/, 'Content-Type in keys');
like(http_get('/content_type_arr'), qr/Content-Type: text\/html/,
	'set Content-Type arr');
like(http_get('/content_encoding_arr'), qr/Content-Encoding: gzip/,
	'set Content-Encoding arr');

like(http_get('/hdr_out_array?foo=12345'), qr/Foo: bar\r\nFoo: 12345/,
	'r.headersOut arr');
like(http_get('/hdr_out_array'), qr/Foo: bar/,
	'r.headersOut arr last is empty');
like(http_get('/hdr_out_array?foo=abc'), qr/B:bar,\s?abc/,
	'r.headersOut get');
like(http_get('/hdr_out_array'), qr/B:bar/, 'r.headersOut get2');
like(http_get('/hdr_out_array?hidden=1'), qr/B:undefined/,
	'r.headersOut get3');
like(http_get('/hdr_out_array?scalar_set=1'), qr/B:xxx/,
	'r.headersOut scalar set');
like(http_get('/hdr_out_single'), qr/ETag: a\r\nETag: b/,
	'r.headersOut single');
like(http_get('/hdr_out_single'), qr/B:a/,
	'r.headersOut single get');
like(http_get('/hdr_out_set_cookie'), qr/Set-Cookie: c\r\nSet-Cookie: d/,
	'set_cookie');
like(http_get('/hdr_out_set_cookie'), qr/B:\['c','d','f']/,
	'set_cookie2');
unlike(http_get('/hdr_out_set_cookie'), qr/Set-Cookie: [abe]/,
	'set_cookie3');

like(http(
	'GET /hdr_in HTTP/1.0' . CRLF
	. 'Cookie: foo' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/cookie: foo/, 'r.headersIn cookie');

like(http(
	'GET /hdr_in HTTP/1.0' . CRLF
	. 'X-Forwarded-For: foo' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/x-forwarded-for: foo/, 'r.headersIn xff');

like(http(
	'GET /hdr_in HTTP/1.0' . CRLF
	. 'Cookie: foo1' . CRLF
	. 'Cookie: foo2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/cookie: foo1;\s?foo2/, 'r.headersIn cookie2');

like(http(
	'GET /hdr_in HTTP/1.0' . CRLF
	. 'X-Forwarded-For: foo1' . CRLF
	. 'X-Forwarded-For: foo2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/x-forwarded-for: foo1,\s?foo2/, 'r.headersIn xff2');

like(http(
	'GET /hdr_in HTTP/1.0' . CRLF
	. 'ETag: bar1' . CRLF
	. 'ETag: bar2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/etag: bar1(?!,\s?bar2)/, 'r.headersIn duplicate single');

like(http(
	'GET /hdr_in HTTP/1.0' . CRLF
	. 'Content-Type: bar1' . CRLF
	. 'Content-Type: bar2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/content-type: bar1(?!,\s?bar2)/, 'r.headersIn duplicate single 2');

like(http(
	'GET /hdr_in HTTP/1.0' . CRLF
	. 'Foo: bar1' . CRLF
	. 'Foo: bar2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/foo: bar1,\s?bar2/, 'r.headersIn duplicate generic');

like(http(
	'GET /raw_hdr_in?filter=foo HTTP/1.0' . CRLF
	. 'foo: bar1' . CRLF
	. 'Foo: bar2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/raw: bar1|bar2/, 'r.rawHeadersIn');

like(http_get('/raw_hdr_out?filter=a'), qr/raw: foo|bar/, 'r.rawHeadersOut');

like(http(
	'GET /hdr_sorted_keys?in=1 HTTP/1.0' . CRLF
	. 'Cookie: foo1' . CRLF
	. 'Accept: */*' . CRLF
	. 'Cookie: foo2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/Accept,Cookie,Host/, 'r.headersIn sorted keys');

like(http(
	'GET /hdr_sorted_keys HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/a,b,c/, 'r.headersOut sorted keys');

TODO: {
local $TODO = 'not yet'
	unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.7.6';

like(http_get('/hdr_out_special_set'), qr/CE: abc/,
	'r.headerOut special set');

like(http_get('/copy_subrequest_hdrs'),
	qr/A: a.*B: b.*C: c.*D: d.*Set-Cookie: A.*Set-Cookie: BB/s,
	'subrequest copy');

like(http_get('/copy_subrequest_hdrs'),
	qr/Content-Type: ct.*Content-Encoding: ce.*Content-Length: 3/s,
	'subrequest copy special');

}

###############################################################################
