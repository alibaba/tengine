#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, fetch method.

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

        location /njs {
            js_content test.njs;
        }

        location /broken {
            js_content test.broken;
        }

        location /broken_response {
            js_content test.broken_response;
        }

        location /body {
            js_content test.body;
        }

        location /body_special {
            js_content test.body_special;
        }

        location /chain {
            js_content test.chain;
        }

        location /chunked {
            js_content test.chunked;
        }

        location /header {
            js_content test.header;
        }

        location /header_iter {
            js_content test.header_iter;
        }

        location /multi {
            js_content test.multi;
        }

        location /property {
            js_content test.property;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  aaa;

        location /loc {
            js_content test.loc;
        }

        location /json { }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  bbb;

        location /loc {
            js_content test.loc;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  ccc;

        location /loc {
            js_content test.loc;
        }
    }
}

EOF

my $p0 = port(8080);
my $p1 = port(8081);
my $p2 = port(8082);

$t->write_file('json', '{"a":[1,2], "b":{"c":"FIELD"}}');

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function body(r) {
        var loc = r.args.loc;
        var getter = r.args.getter;

        function query(obj) {
            var path = r.args.path;
            var retval = (getter == 'arrayBuffer') ? Buffer.from(obj).toString()
                                                   : obj;

            if (path) {
                retval = path.split('.').reduce((a, v) => a[v], obj);
            }

            return JSON.stringify(retval);
        }

        ngx.fetch(`http://127.0.0.1:$p0/\${loc}`, {headers: {Host: 'aaa'}})
        .then(reply => reply[getter]())
        .then(data => r.return(200, query(data)))
        .catch(e => r.return(501, e.message))
    }

    function property(r) {
        var opts = {headers:{Host: 'aaa'}};

        if (r.args.code) {
            opts.headers.code = r.args.code;
        }

        var p = ngx.fetch('http://127.0.0.1:$p0/loc', opts)

        if (r.args.readBody) {
            p = p.then(rep =>
                 rep.text().then(body => {rep.text = body; return rep;}))
        }

        p.then(reply => r.return(200, reply[r.args.pr]))
        .catch(e => r.return(501, e.message))
    }

    function process_errors(r, tests) {
        var results = [];

        tests.forEach(args => {
            ngx.fetch.apply(r, args)
            .then(reply => {
                r.return(400, '["unexpected then"]');
            })
            .catch(e => {
                results.push(e.message);

                if (results.length == tests.length) {
                    results.sort();
                    r.return(200, JSON.stringify(results));
                }
            })
        })
    }

    function broken(r) {
        var tests = [
            ['http://127.0.0.1:1/loc'],
            ['http://127.0.0.1:80800/loc'],
            [Symbol.toStringTag],
        ];

        return process_errors(r, tests);
    }

    function broken_response(r) {
        var tests = [
            ['http://127.0.0.1:$p2/status_line'],
            ['http://127.0.0.1:$p2/length'],
            ['http://127.0.0.1:$p2/header'],
            ['http://127.0.0.1:$p2/headers'],
            ['http://127.0.0.1:$p2/content_length'],
        ];

        return process_errors(r, tests);
    }

    function chain(r) {
        var results = [];
        var reqs = [
             ['http://127.0.0.1:$p0/loc', {headers: {Host:'aaa'}}],
             ['http://127.0.0.1:$p0/loc', {headers: {Host:'bbb'}}],
           ];

           function next(reply) {
              if (reqs.length == 0) {
                 r.return(200, "SUCCESS");
                 return;
              }

              ngx.fetch.apply(r, reqs.pop())
              .then(next)
              .catch(e => r.return(400, e.message))
           }

           next();
    }

    function chunked(r) {
        var results = [];
        var tests = [
            ['http://127.0.0.1:$p2/big', {max_response_body_size:128000}],
            ['http://127.0.0.1:$p2/big/ok', {max_response_body_size:128000}],
            ['http://127.0.0.1:$p2/chunked'],
            ['http://127.0.0.1:$p2/chunked/ok'],
            ['http://127.0.0.1:$p2/chunked/big', {max_response_body_size:128}],
            ['http://127.0.0.1:$p2/chunked/big'],
        ];

        function collect(v) {
            results.push(v);

            if (results.length == tests.length) {
                results.sort();
                r.return(200, JSON.stringify(results));
            }
        }

        tests.forEach(args => {
            ngx.fetch.apply(r, args)
            .then(reply => reply.text())
            .then(body => collect(body.length))
            .catch(e => collect(e.message))
        })
    }

    function header(r) {
        var url = `http://127.0.0.1:$p2/\${r.args.loc}`;
        var method = r.args.method ? r.args.method : 'get';

        var p = ngx.fetch(url)

        if (r.args.readBody) {
            p = p.then(rep =>
                 rep.text().then(body => {rep.text = body; return rep;}))
        }

        p.then(reply => {
            var h = reply.headers[method](r.args.h);
            r.return(200, njs.dump(h));
        })
        .catch(e => r.return(501, e.message))
    }

    async function body_special(r) {
        let reply = await ngx.fetch(`http://127.0.0.1:$p2/\${r.args.loc}`);
        let body = await reply.text();

        r.return(200, body);
    }

    async function header_iter(r) {
        let url = `http://127.0.0.1:$p2/\${r.args.loc}`;

        let response = await ngx.fetch(url);

        let headers = response.headers;
        let out = [];
        for (let key in response.headers) {
            if (key != 'Connection') {
                out.push(`\${key}:\${headers.get(key)}`);
            }
        }

        r.return(200, njs.dump(out));
    }

    function multi(r) {
        var results = [];
        var tests = [
             [
              'http://127.0.0.1:$p0/loc',
               { headers: {Code: 201, Host: 'aaa'}},
             ],
             [
              'http://127.0.0.1:$p0/loc',
               { method:'POST', headers: {Code: 401, Host: 'bbb'}, body: 'OK'},
             ],
             [
              'http://127.0.0.1:$p1/loc',
               { method:'PATCH',
                 headers: {foo:undefined, bar:'xxx', Host: 'ccc'}},
             ],
           ];

        function cmp(a,b) {
            if (a.b > b.b) {return 1;}
            if (a.b < b.b) {return -1;}
            return 0
        }

        tests.forEach(args => {
            ngx.fetch.apply(r, args)
            .then(rep =>
                 rep.text().then(body => {rep.text = body; return rep;}))
            .then(rep => {
                results.push({b:rep.text,
                              c:rep.status,
                              u:rep.url});

                if (results.length == tests.length) {
                    results.sort(cmp);
                    r.return(200, JSON.stringify(results));
                }
            })
            .catch(e => {
                r.return(400, `["\${e.message}"]`);
                throw e;
            })
        })

        if (r.args.throw) {
            throw 'Oops';
        }
    }

    function str(v) { return v ? v : ''};

    function loc(r) {
        var v = r.variables;
        var body = str(r.requestText);
        var foo = str(r.headersIn.foo);
        var bar = str(r.headersIn.bar);
        var c = r.headersIn.code ? Number(r.headersIn.code) : 200;
        r.return(c, `\${v.host}:\${v.request_method}:\${foo}:\${bar}:\${body}`);
    }

     export default {njs: test_njs, body, broken, broken_response, body_special,
                     chain, chunked, header, header_iter, multi, loc, property};
EOF

$t->try_run('no njs.fetch')->plan(31);

$t->run_daemon(\&http_daemon, port(8082));
$t->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

like(http_get('/body?getter=arrayBuffer&loc=loc'), qr/200 OK.*"aaa:GET:::"$/s,
	'fetch body arrayBuffer');
like(http_get('/body?getter=text&loc=loc'), qr/200 OK.*"aaa:GET:::"$/s,
	'fetch body text');
like(http_get('/body?getter=json&loc=json&path=b.c'),
	qr/200 OK.*"FIELD"$/s, 'fetch body json');
like(http_get('/body?getter=json&loc=loc'), qr/501/s,
	'fetch body json invalid');
like(http_get('/body_special?loc=parted'), qr/200 OK.*X{32000}$/s,
	'fetch body parted');
like(http_get('/property?pr=bodyUsed'), qr/false$/s,
	'fetch bodyUsed false');
like(http_get('/property?pr=bodyUsed&readBody=1'), qr/true$/s,
	'fetch bodyUsed true');
like(http_get('/property?pr=ok'), qr/200 OK.*true$/s,
	'fetch ok true');
like(http_get('/property?pr=ok&code=401'), qr/200 OK.*false$/s,
	'fetch ok false');
like(http_get('/property?pr=redirected'), qr/200 OK.*false$/s,
	'fetch redirected false');
like(http_get('/property?pr=statusText'), qr/200 OK.*OK$/s,
	'fetch statusText OK');
like(http_get('/property?pr=statusText&code=403'), qr/200 OK.*Forbidden$/s,
	'fetch statusText Forbidden');
like(http_get('/property?pr=type'), qr/200 OK.*basic$/s,
	'fetch type');
like(http_get('/header?loc=duplicate_header&h=BAR'), qr/200 OK.*c$/s,
	'fetch header');
like(http_get('/header?loc=duplicate_header&h=BARR'), qr/200 OK.*null$/s,
	'fetch no header');
like(http_get('/header?loc=duplicate_header&h=foo'), qr/200 OK.*a,b$/s,
	'fetch header duplicate');
like(http_get('/header?loc=duplicate_header&h=BAR&method=getAll'),
	qr/200 OK.*\['c']$/s, 'fetch getAll header');
like(http_get('/header?loc=duplicate_header&h=BARR&method=getAll'),
	qr/200 OK.*\[]$/s, 'fetch getAll no header');
like(http_get('/header?loc=duplicate_header&h=FOO&method=getAll'),
	qr/200 OK.*\['a','b']$/s, 'fetch getAll duplicate');
like(http_get('/header?loc=duplicate_header&h=bar&method=has'),
	qr/200 OK.*true$/s, 'fetch header has');
like(http_get('/header?loc=duplicate_header&h=buz&method=has'),
	qr/200 OK.*false$/s, 'fetch header does not have');
like(http_get('/header?loc=chunked/big&h=BAR&readBody=1'), qr/200 OK.*xxx$/s,
	'fetch chunked header');
is(get_json('/multi'),
	'[{"b":"aaa:GET:::","c":201,"u":"http://127.0.0.1:'.$p0.'/loc"},' .
	'{"b":"bbb:POST:::OK","c":401,"u":"http://127.0.0.1:'.$p0.'/loc"},' .
	'{"b":"ccc:PATCH::xxx:","c":200,"u":"http://127.0.0.1:'.$p1.'/loc"}]',
	'fetch multi');
like(http_get('/multi?throw=1'), qr/500/s, 'fetch destructor');
is(get_json('/broken'),
	'[' .
	'"connect failed",' .
	'"failed to convert url arg",' .
	'"invalid url"]', 'fetch broken');
is(get_json('/broken_response'),
	'["invalid fetch content length",' .
	'"invalid fetch header",' .
	'"invalid fetch status line",' .
	'"prematurely closed connection",' .
	'"prematurely closed connection"]', 'fetch broken response');
is(get_json('/chunked'),
	'[10,100010,25500,' .
	'"invalid fetch chunked response",' .
	'"prematurely closed connection",' .
	'"very large fetch chunked response"]', 'fetch chunked');
like(http_get('/chain'), qr/200 OK.*SUCCESS$/s, 'fetch chain');

TODO: {
todo_skip 'leaves coredump', 1 unless $ENV{TEST_NGINX_UNSAFE}
	or http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.7.4';

like(http_get('/header_iter?loc=duplicate_header_large'),
	qr/\['A:a','B:a','C:a','D:a','E:a','F:a','G:a','H:a','Foo:a,b']$/s,
	'fetch header duplicate large');

}

TODO: {
local $TODO = 'not yet'
	unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.7.7';

like(http_get('/body_special?loc=no_content_length'),
	qr/200 OK.*CONTENT-BODY$/s, 'fetch body without content-length');
like(http_get('/body_special?loc=no_content_length/parted'),
	qr/200 OK.*X{32000}$/s, 'fetch body without content-length parted');

}

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

###############################################################################

sub http_daemon {
	my $port = shift;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . $port,
		Listen => 5,
		Reuse => 1
	) or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri eq '/status_line') {
			print $client
				"HTTP/1.1 2A";

		} elsif ($uri eq '/content_length') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: " . CRLF .
				"Connection: close" . CRLF .
				CRLF;

		} elsif ($uri eq '/header') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"@#" . CRLF .
				"Connection: close" . CRLF .
				CRLF;

		} elsif ($uri eq '/duplicate_header') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Foo: a" . CRLF .
				"bar: c" . CRLF .
				"Foo: b" . CRLF .
				"Connection: close" . CRLF .
				CRLF;

		} elsif ($uri eq '/duplicate_header_large') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"A: a" . CRLF .
				"B: a" . CRLF .
				"C: a" . CRLF .
				"D: a" . CRLF .
				"E: a" . CRLF .
				"F: a" . CRLF .
				"G: a" . CRLF .
				"H: a" . CRLF .
				"Foo: a" . CRLF .
				"Foo: b" . CRLF .
				"Connection: close" . CRLF .
				CRLF;

		} elsif ($uri eq '/headers') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Connection: close" . CRLF;

		} elsif ($uri eq '/length') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: 100" . CRLF .
				"Connection: close" . CRLF .
				CRLF .
				"unfinished" . CRLF;

		} elsif ($uri eq '/parted') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: 32000" . CRLF .
				"Connection: close" . CRLF .
				CRLF;

			for (1 .. 4) {
				select undef, undef, undef, 0.01;
				print $client "X" x 8000;
			}

		} elsif ($uri eq '/no_content_length') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Connection: close" . CRLF .
				CRLF .
				"CONTENT-BODY";

		} elsif ($uri eq '/no_content_length/parted') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Connection: close" . CRLF .
				CRLF;

			for (1 .. 4) {
				select undef, undef, undef, 0.01;
				print $client "X" x 8000;
			}

		} elsif ($uri eq '/big') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: 100100" . CRLF .
				"Connection: close" . CRLF .
				CRLF;
			for (1 .. 1000) {
				print $client ("X" x 98) . CRLF;
			}
			print $client "unfinished" . CRLF;

		} elsif ($uri eq '/big/ok') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Content-Length: 100010" . CRLF .
				"Connection: close" . CRLF .
				CRLF;
			for (1 .. 1000) {
				print $client ("X" x 98) . CRLF;
			}
			print $client "finished" . CRLF;

		} elsif ($uri eq '/chunked') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Transfer-Encoding: chunked" . CRLF .
				"Connection: close" . CRLF .
				CRLF .
				"ff" . CRLF .
				"unfinished" . CRLF;

		} elsif ($uri eq '/chunked/ok') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Transfer-Encoding: chunked" . CRLF .
				"Connection: close" . CRLF .
				CRLF .
				"a" . CRLF .
				"finished" . CRLF .
				CRLF . "0" . CRLF . CRLF;
		} elsif ($uri eq '/chunked/big') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Transfer-Encoding: chunked" . CRLF .
				"Bar: xxx" . CRLF .
				"Connection: close" . CRLF .
				CRLF;

			for (1 .. 100) {
				print $client "ff" . CRLF . ("X" x 255) . CRLF;
			}

		    print $client  "0" . CRLF . CRLF;
		}
	}
}

###############################################################################
