#!/usr/bin/perl

# (C) Vadim Zhestikov
# (C) Nginx, Inc.

# Tests for stream njs module, js_preload_object directive.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_return/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    js_preload_object g1 from g.json;

    js_set $test foo.bar.p;

    js_import lib.js;
    js_import foo from ./main.js;

    server {
        listen  127.0.0.1:8081;
        return  $test;
    }

    server {
        listen      127.0.0.1:8082;
        js_access   lib.access;
        js_preread  lib.preread;
        js_filter   lib.filter;
        proxy_pass  127.0.0.1:8083;
    }

    server {
        listen  127.0.0.1:8083;
        return  "x";
    }
}

EOF

$t->write_file('lib.js', <<EOF);
    var res = '';

    function access(s) {
        res += g1.a;
        s.allow();
    }

    function preread(s) {
        s.on('upload', function (data) {
            res += g1.b[1];
            if (res.length >= 3) {
                s.done();
            }
        });
    }

    function filter(s) {
        s.on('upload', function(data, flags) {
            s.send(data);
            res += g1.c.prop[0].a;
        });

        s.on('download', function(data, flags) {
            if (!flags.last) {
                res += g1.b[3];
                s.send(data);

            } else {
                res += g1.b[4];
                s.send(res, {last:1});
                s.off('download');
            }
        });
    }

    export default {access, preread, filter};

EOF

$t->write_file('main.js', <<EOF);
    export default {bar: {p(s) {return g1.b[2]}}};

EOF

$t->write_file('g.json',
	'{"a":1, "b":[1,2,"element",4,5], "c":{"prop":[{"a":3}]}}');

$t->try_run('no js_preload_object available')->plan(2);

###############################################################################

is(stream('127.0.0.1:' . port(8081))->read(), 'element', 'foo.bar.p');
is(stream('127.0.0.1:' . port(8082))->io('0'), 'x122345', 'lib.access');

###############################################################################
