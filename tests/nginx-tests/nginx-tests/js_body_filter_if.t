#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, body filter, if context.

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

        location /filter {
            if ($arg_name ~ "prepend") {
                js_body_filter test.prepend;
            }

            if ($arg_name ~ "append") {
                js_body_filter test.append;
            }

            js_body_filter test.should_not_be_called;

            proxy_pass http://127.0.0.1:8081/source;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location /source {
            postpone_output 1;
            js_content test.source;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function append(r, data, flags) {
        r.sendBuffer(data, {last:false});

        if (flags.last) {
            r.sendBuffer("XXX", flags);
        }
    }

    function chain(chunks, i) {
        if (i < chunks.length) {
            chunks.r.send(chunks[i++]);
            setTimeout(chunks.chain, chunks.delay, chunks, i);

        } else {
            chunks.r.finish();
        }
    }

    function source(r) {
        var chunks = ['AAA', 'BB', 'C', 'DDDD'];
        chunks.delay = 5;
        chunks.r = r;
        chunks.chain = chain;

        r.status = 200;
        r.sendHeader();
        chain(chunks, 0);
    }

    function prepend(r, data, flags) {
        r.sendBuffer("XXX");
        r.sendBuffer(data, flags);
        r.done();
    }

    export default {njs: test_njs, append, prepend, source};

EOF

$t->try_run('no njs body filter')->plan(2);

###############################################################################

like(http_get('/filter?name=append'), qr/AAABBCDDDDXXX/, 'append');
like(http_get('/filter?name=prepend'), qr/XXXAAABBCDDDD/, 'prepend');

###############################################################################
