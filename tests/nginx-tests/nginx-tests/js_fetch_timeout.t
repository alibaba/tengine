#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, fetch method timeout.

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

        location /njs {
            js_content test.njs;
        }

        location /normal_timeout {
            js_content test.timeout_test;
        }

        location /short_timeout {
            js_fetch_timeout 200ms;
            js_content test.timeout_test;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location /normal_reply {
            js_content test.normal_reply;
        }

        location /delayed_reply {
            js_content test.delayed_reply;
        }
    }
}

EOF

my $p1 = port(8081);

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    async function timeout_test(r) {
        let rs = await Promise.allSettled([
            'http://127.0.0.1:$p1/normal_reply',
            'http://127.0.0.1:$p1/delayed_reply',
        ].map(v => ngx.fetch(v)));

        let bs = rs.map(v => ({s: v.status, v: v.value ? v.value.headers.X
                                                       : v.reason}));

        r.return(200, njs.dump(bs));
    }

    function normal_reply(r) {
        r.headersOut.X = 'N';
        r.return(200);
    }

    function delayed_reply(r) {
        r.headersOut.X = 'D';
        setTimeout((r) => { r.return(200); }, 250, r, 0);
    }

     export default {njs: test_njs, timeout_test, normal_reply, delayed_reply};
EOF

$t->try_run('no js_fetch_timeout')->plan(2);

###############################################################################

like(http_get('/normal_timeout'),
	qr/\[\{s:'fulfilled',v:'N'},\{s:'fulfilled',v:'D'}]$/s,
	'normal timeout');
like(http_get('/short_timeout'),
	qr/\[\{s:'fulfilled',v:'N'},\{s:'rejected',v:Error: read timed out}]$/s,
	'short timeout');

###############################################################################
