#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, header filter.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)
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

        location /filter/ {
            js_header_filter test.filter;
            proxy_pass http://127.0.0.1:8081/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header Set-Cookie "BB";
            add_header Set-Cookie "CCCC";

            return 200;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function filter(r) {
        var cookies = r.headersOut['Set-Cookie'];
        var len = r.args.len ? Number(r.args.len) : 0;
        r.headersOut['Set-Cookie'] = cookies.filter(v=>v.length > len);
    }

    export default {njs: test_njs, filter};

EOF

$t->try_run('no njs header filter')->plan(2);

###############################################################################

like(http_get('/filter/?len=1'), qr/Set-Cookie: BB.*Set-Cookie: CCCC.*/ms,
	'all');;
unlike(http_get('/filter/?len=3'), qr/Set-Cookie: BB/,
	'filter');

###############################################################################
