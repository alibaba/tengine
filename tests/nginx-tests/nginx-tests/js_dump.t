#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, request object dump.

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

    js_import test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /dump {
            js_content test.dump;
        }

        location /stringify {
            js_content test.stringify;
        }

        location /stringify_subrequest {
            js_content test.stringify_subrequest;
        }

        location /js_sub {
            return 201 '{$request_method}';
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function dump(r) {
        r.headersOut.baz = 'bar';
        r.return(200, njs.dump(r));
    }

    function stringify(r) {
        r.headersOut.baz = 'bar';
        var obj = JSON.parse(JSON.stringify(r));
        r.return(200, JSON.stringify(obj));
    }

    function stringify_subrequest(r) {
        r.subrequest('/js_sub', reply => {
            r.return(200, JSON.stringify(reply))
        });
    }

    export default {dump, stringify, stringify_subrequest};

EOF

$t->try_run('no njs dump')->plan(3);

###############################################################################

like(http(
	'GET /dump?v=1&t=x HTTP/1.0' . CRLF
	. 'Foo: bar' . CRLF
	. 'Foo2: bar2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/method:'GET'/, 'njs.dump(r)');

like(http(
	'GET /stringify?v=1&t=x HTTP/1.0' . CRLF
	. 'Foo: bar' . CRLF
	. 'Foo2: bar2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/headersOut":\{"baz":"bar"}/, 'JSON.stringify(r)');

like(http(
	'GET /stringify_subrequest HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/"status":201/, 'JSON.stringify(reply)');

###############################################################################
