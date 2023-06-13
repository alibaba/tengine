#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, body filter.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)
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

        location /append {
            js_body_filter test.append;
            proxy_pass http://127.0.0.1:8081/source;
        }

        location /buffer_type {
            js_body_filter test.buffer_type buffer_type=buffer;
            proxy_pass http://127.0.0.1:8081/source;
        }

        location /forward {
            js_body_filter test.forward buffer_type=string;
            proxy_pass http://127.0.0.1:8081/source;
        }

        location /filter {
            proxy_buffering off;
            js_body_filter test.filter;
            proxy_pass http://127.0.0.1:8081/source;
        }

        location /prepend {
            js_body_filter test.prepend;
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

    var collect = Buffer.from([]);
    function buffer_type(r, data, flags) {
        collect = Buffer.concat([collect, data]);

        if (flags.last) {
            r.sendBuffer(collect, flags);
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

    function filter(r, data, flags) {
        if (flags.last || data.length >= Number(r.args.len)) {
            r.sendBuffer(`\${data}|`, flags);

            if (r.args.dup && !flags.last) {
                r.sendBuffer(data, flags);
            }
        }
    }

    function forward(r, data, flags) {
        r.sendBuffer(data, flags);
    }

    function prepend(r, data, flags) {
        r.sendBuffer("XXX");
        r.sendBuffer(data, flags);
        r.done();
    }

    export default {njs: test_njs, append, buffer_type, filter, forward,
                    prepend, source};

EOF

$t->try_run('no njs body filter')->plan(6);

###############################################################################

like(http_get('/append'), qr/AAABBCDDDDXXX/, 'append');
like(http_get('/buffer_type'), qr/AAABBCDDDD/, 'buffer type');
like(http_get('/forward'), qr/AAABBCDDDD/, 'forward');
like(http_get('/filter?len=3'), qr/AAA|DDDD|/, 'filter 3');
like(http_get('/filter?len=2&dup=1'), qr/AAA|AAABB|BBDDDD|DDDD/,
	'filter 2 dup');
like(http_get('/prepend'), qr/XXXAAABBCDDDD/, 'prepend');

###############################################################################
