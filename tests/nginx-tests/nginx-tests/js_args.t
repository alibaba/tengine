#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, arguments tests.

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

    js_set $test_iter     test.iter;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /njs {
            js_content test.njs;
        }

        location /iter {
            return 200 $test_iter;
        }

        location /keys {
            js_content test.keys;
        }

        location /object {
            js_content test.object;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function iter(r) {
        var s = '', a;
        for (a in r.args) {
            if (a.substr(0, 3) == 'foo') {
                s += r.args[a];
            }
        }

        return s;
    }

    function keys(r) {
        r.return(200, Object.keys(r.args).sort());
    }

    function object(r) {
        r.return(200, JSON.stringify(r.args));
    }

    export default {njs: test_njs, iter, keys, object};

EOF

$t->try_run('no njs')->plan(15);

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

TODO: {
local $TODO = 'not yet'
    unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.7.6';

like(http_get('/iter?foo=12345&foo2=bar&nn=22&foo-3=z'), qr/12345barz/,
	'r.args iteration');
like(http_get('/iter?foo=123&foo2=&foo3&foo4=456'), qr/123456/,
	'r.args iteration 2');
like(http_get('/iter?foo=123&foo2=&foo3'), qr/123/, 'r.args iteration 3');
like(http_get('/iter?foo=123&foo2='), qr/123/, 'r.args iteration 4');
like(http_get('/iter?foo=1&foo=2'), qr/1,2/m, 'r.args iteration 5');

like(http_get('/keys?b=1&c=2&a=5'), qr/a,b,c/m, 'r.args sorted keys');
like(http_get('/keys?b=1&b=2'), qr/b/m, 'r.args duplicate keys');
like(http_get('/keys?b=1&a&c='), qr/a,b,c/m, 'r.args empty value');

is(get_json('/object'), '{}', 'empty object');
is(get_json('/object?a=1&b=2&c=3'), '{"a":"1","b":"2","c":"3"}',
	'ordinary object');
is(get_json('/object?a=1&A=2'), '{"A":"2","a":"1"}',
	'case sensitive object');
is(get_json('/object?a=1&A=2&a=3'), '{"A":"2","a":["1","3"]}',
	'duplicate keys object');
is(get_json('/object?%61=1&a=2'), '{"a":["1","2"]}',
	'keys percent-encoded object');
is(get_json('/object?a=%62%63&b=%63%64'), '{"a":"bc","b":"cd"}',
	'values percent-encoded object');
is(get_json('/object?a=%6&b=%&c=%%&d=%zz'),
	'{"a":"%6","b":"%","c":"%%","d":"%zz"}',
	'values percent-encoded broken object');
}

###############################################################################
