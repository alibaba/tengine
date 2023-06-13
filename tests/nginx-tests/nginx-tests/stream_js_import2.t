#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for stream njs module, js_import directive in server context.

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

    server {
        listen  127.0.0.1:8081;
        js_import foo from ./main.js;
        js_set $test foo.bar.p;
        return  $test;
    }

    server {
        listen      127.0.0.1:8082;

        js_import lib.js;

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
        res += '1';
        s.allow();
    }

    function preread(s) {
        s.on('upload', function (data) {
            res += '2';
            if (res.length >= 3) {
                s.done();
            }
        });
    }

    function filter(s) {
        s.on('upload', function(data, flags) {
            s.send(data);
            res += '3';
        });

        s.on('download', function(data, flags) {
            if (!flags.last) {
                res += '4';
                s.send(data);

            } else {
                res += '5';
                s.send(res, {last:1});
                s.off('download');
            }
        });
    }

    export default {access, preread, filter};

EOF

$t->write_file('main.js', <<EOF);
    export default {bar: {p(s) {return "P-TEST"}}};

EOF

$t->try_run('no njs available')->plan(2);

###############################################################################

is(stream('127.0.0.1:' . port(8081))->read(), 'P-TEST', 'foo.bar.p');
is(stream('127.0.0.1:' . port(8082))->io('0'), 'x122345', 'lib.access');

###############################################################################
