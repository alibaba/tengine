#!/usr/bin/perl

# (C) Roman Arutyunyan
# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    js_set $test_method   test.method;
    js_set $test_version  test.version;
    js_set $test_addr     test.addr;
    js_set $test_uri      test.uri;
    js_set $test_var      test.variable;
    js_set $test_type     test.type;
    js_set $test_global   test.global_obj;
    js_set $test_log      test.log;
    js_set $test_internal test.sub_internal;
    js_set $test_except   test.except;

    js_import test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /njs {
            js_content test.njs;
        }

        location /method {
            return 200 $test_method;
        }

        location /version {
            return 200 $test_version;
        }

        location /addr {
            return 200 $test_addr;
        }

        location /uri {
            return 200 $test_uri;
        }

        location /var {
            return 200 $test_var;
        }

        location /global {
            return 200 $test_global;
        }

        location /body {
            js_content test.request_body;
        }

        location /in_file {
            client_body_in_file_only on;
            js_content test.request_body;
        }

        location /status {
            js_content test.status;
        }

        location /request_body {
            js_content test.request_body;
        }

        location /request_body_cache {
            js_content test.request_body_cache;
        }

        location /send {
            js_content test.send;
        }

        location /return_method {
            js_content test.return_method;
        }

        location /type {
            js_content test.type;
        }

        location /log {
            return 200 $test_log;
        }

        location /internal {
            js_content test.internal;
        }

        location /sub_internal {
            internal;
            return 200 $test_internal;
        }

        location /except {
            return 200 $test_except;
        }

        location /content_except {
            js_content test.content_except;
        }

        location /content_empty {
            js_content test.content_empty;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    var global = ['n', 'j', 's'].join("");

    function test_njs(r) {
        r.return(200, njs.version);
    }

    function method(r) {
        return 'method=' + r.method;
    }

    function version(r) {
        return 'version=' + r.httpVersion;
    }

    function addr(r) {
        return 'addr=' + r.remoteAddress;
    }

    function uri(r) {
        return 'uri=' + r.uri;
    }

    function variable(r) {
        return 'variable=' + r.variables.remote_addr;
    }

    function global_obj(r) {
        return 'global=' + global;
    }

    function status(r) {
        r.status = 204;
        r.sendHeader();
        r.finish();
    }

    function request_body(r) {
        try {
            var body = r.requestText;
            r.return(200, body);

        } catch (e) {
            r.return(500, e.message);
        }
    }

    function request_body_cache(r) {
        function t(v) {return Buffer.isBuffer(v) ? 'buffer' : (typeof v);}
        r.return(200,
      `requestText:\${t(r.requestText)} requestBuffer:\${t(r.requestBuffer)}`);
    }

    function send(r) {
        var a, s;
        r.status = 200;
        r.sendHeader();
        for (a in r.args) {
            if (a.substr(0, 3) == 'foo') {
                s = r.args[a];
                r.send('n=' + a + ', v=' + s.substr(0, 2) + ' ');
            }
        }
        r.finish();
    }

    function return_method(r) {
        r.return(Number(r.args.c), r.args.t);
    }

    function type(r) {
        var p = r.args.path.split('.').reduce((a, v) => a[v], r);

        var typ = Buffer.isBuffer(p) ? 'buffer' : (typeof p);
        r.return(200, `type: \${typ}`);
    }

    function log(r) {
        r.log('SEE-LOG');
    }

    async function internal(r) {
        let reply = await r.subrequest('/sub_internal');

        r.return(200, `parent: \${r.internal} sub: \${reply.responseText}`);
    }

    function sub_internal(r) {
        return r.internal;
    }

    function except(r) {
        var fs = require('fs');
        fs.readFileSync();
    }


    function content_except(r) {
        JSON.parse({}.a.a);
    }

    function content_empty(r) {
    }

    export default {njs:test_njs, method, version, addr, uri,
                    variable, global_obj, status, request_body, internal,
                    request_body_cache, send, return_method, sub_internal,
                    type, log, except, content_except, content_empty};

EOF

$t->try_run('no njs available')->plan(27);

###############################################################################

like(http_get('/method'), qr/method=GET/, 'r.method');
like(http_get('/version'), qr/version=1.0/, 'r.httpVersion');
like(http_get('/addr'), qr/addr=127.0.0.1/, 'r.remoteAddress');
like(http_get('/uri'), qr/uri=\/uri/, 'r.uri');

like(http_get('/status'), qr/204 No Content/, 'r.status');

like(http_post('/body'), qr/REQ-BODY/, 'request body');
like(http_post('/in_file'), qr/request body is in a file/,
	'request body in file');
like(http_post_big('/body'), qr/200.*^(1234567890){1024}$/ms,
	'request body big');

like(http_get('/send?foo=12345&n=11&foo-2=bar&ndd=&foo-3=z'),
	qr/n=foo, v=12 n=foo-2, v=ba n=foo-3, v=z/, 'r.send');

like(http_get('/return_method?c=200'), qr/200 OK.*\x0d\x0a?\x0d\x0a?$/s,
	'return code');
like(http_get('/return_method?c=200&t=SEE-THIS'), qr/200 OK.*^SEE-THIS$/ms,
	'return text');
like(http_get('/return_method?c=301&t=path'), qr/ 301 .*Location: path/s,
	'return redirect');
like(http_get('/return_method?c=404'), qr/404 Not.*html/s, 'return error page');
like(http_get('/return_method?c=inv'), qr/ 500 /, 'return invalid');

TODO: {
local $TODO = 'not yet'
	unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.5.0';

like(http_get('/type?path=variables.host'), qr/200 OK.*type: string$/s,
	'variables type');
like(http_get('/type?path=rawVariables.host'), qr/200 OK.*type: buffer$/s,
	'rawVariables type');

like(http_post('/type?path=requestText'), qr/200 OK.*type: string$/s,
	'requestText type');
like(http_post('/type?path=requestBuffer'), qr/200 OK.*type: buffer$/s,
	'requestBuffer type');
like(http_post('/request_body_cache'),
	qr/requestText:string requestBuffer:buffer$/s, 'request body cache');

}

like(http_get('/var'), qr/variable=127.0.0.1/, 'r.variables');
like(http_get('/global'), qr/global=njs/, 'global code');
like(http_get('/log'), qr/200 OK/, 'r.log');

TODO: {
local $TODO = 'not yet'
	unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.7.7';

like(http_get('/internal'), qr/parent: false sub: true/, 'r.internal');

}

http_get('/except');
http_get('/content_except');

like(http_get('/content_empty'), qr/500 Internal Server Error/,
	'empty handler');

$t->stop();

ok(index($t->read_file('error.log'), 'SEE-LOG') > 0, 'log js');
ok(index($t->read_file('error.log'), 'at fs.readFileSync') > 0,
	'js_set backtrace');
ok(index($t->read_file('error.log'), 'at JSON.parse') > 0,
	'js_content backtrace');

###############################################################################

sub http_get_hdr {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
FoO: 12345

EOF
}

sub http_get_ihdr {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
foo: 12345
Host: localhost
foo2: bar
X-xxx: more
foo-3: z

EOF
}

sub http_post {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 8" . CRLF .
		CRLF .
		"REQ-BODY";

	return http($p, %extra);
}

sub http_post_big {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 10240" . CRLF .
		CRLF .
		("1234567890" x 1024);

	return http($p, %extra);
}

###############################################################################
