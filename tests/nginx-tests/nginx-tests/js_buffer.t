#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, buffer properties.

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

eval { require JSON::PP; };
plan(skip_all => "JSON::PP not installed") if $@;

my $t = Test::Nginx->new()->has(qw/http rewrite proxy/)
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

        location /return {
            js_content test.return;
        }

        location /req_body {
            js_content test.req_body;
        }

        location /res_body {
            js_content test.res_body;
        }

        location /res_text {
            js_content test.res_text;
        }

        location /binary_var {
            js_content test.binary_var;
        }

        location /p/ {
            proxy_pass http://127.0.0.1:8081/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location /sub1 {
            return 200 '{"a": {"b": 1}}';
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function test_return(r) {
        var body = Buffer.from("body: ");
        body = Buffer.concat([body, Buffer.from(r.args.text)]);
        r.return(200, body);
    }

    function req_body(r) {
        var body = r.requestBuffer;
        var view = new DataView(body.buffer);
        view.setInt8(2, 'c'.charCodeAt(0));
        r.return(200, JSON.parse(body).c.b);
    }

    function type(v) {return Buffer.isBuffer(v) ? 'buffer' : (typeof v);}

    function res_body(r) {
        r.subrequest('/p/sub1')
        .then(reply => {
            var body = reply.responseBuffer;
            var view = new DataView(body.buffer);
            view.setInt8(2, 'c'.charCodeAt(0));
            body = JSON.parse(body);
            body.type = type(reply.responseBuffer);
            r.return(200, JSON.stringify(body));
        })
    }

    function res_text(r) {
        r.subrequest('/p/sub1')
        .then(reply => {
            var body = JSON.parse(reply.responseText);
            body.type = type(reply.responseText);
            r.return(200, JSON.stringify(body));
        })
    }

    function binary_var(r) {
        var test = r.rawVariables.binary_remote_addr
                   .equals(Buffer.from([127,0,0,1]));
        r.return(200, test);
    }

    export default {njs: test_njs, return: test_return, req_body, res_body,
                    res_text, binary_var};

EOF

$t->try_run('no njs buffer')->plan(5);

###############################################################################

like(http_get('/return?text=FOO'), qr/200 OK.*body: FOO$/s,
	'return buffer');
like(http_post('/req_body'), qr/200 OK.*BAR$/s, 'request buffer');
is(get_json('/res_body'), '{"c":{"b":1},"type":"buffer"}', 'response buffer');
is(get_json('/res_text'), '{"a":{"b":1},"type":"string"}', 'response text');
like(http_get('/binary_var'), qr/200 OK.*true$/s,
	'binary var');

###############################################################################

sub recode {
	my $json;
	eval { $json = JSON::PP::decode_json(shift) };

	if ($@) {
		return "<failed to parse JSON>";
	}

	JSON::PP->new()->canonical()->encode($json);
}

sub get_json {
	http_get(shift) =~ /\x0d\x0a?\x0d\x0a?(.*)/ms;
	recode($1);
}

sub http_post {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 17" . CRLF .
		CRLF .
		"{\"a\":{\"b\":\"BAR\"}}";

	return http($p, %extra);
}

###############################################################################
