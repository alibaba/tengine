#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for stream njs module, stream session object.

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

    js_set $test     test.test;

    js_import test.js;

    server {
        listen  127.0.0.1:8081;
        return  $test$status;
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function to_string(s) {
        return s.toString() === '[object Stream Session]';
    }

    function define_prop(s) {
        Object.defineProperty(s.variables, 'status', {value:400});
        return s.variables.status == 400;
    }

    function in_operator(s) {
        return ['status', 'unknown']
               .map(v=>v in s.variables)
               .toString() === 'true,false';
    }

    function redefine_proto(s) {
        s[0] = 'a';
        s[1] = 'b';
        s.length = 2;
        Object.setPrototypeOf(s, Array.prototype);
        return s.join('|') === 'a|b';
    }

    function get_own_prop_descs(s) {
        return Object.getOwnPropertyDescriptors(s)['on'].value === s.on;
    }

    function test(s) {
        return [ to_string,
                 define_prop,
                 in_operator,
                 redefine_proto,
                 get_own_prop_descs,
               ].every(v=>v(s));
    }

    export default {test};

EOF

$t->try_run('no njs stream session object')->plan(1);

###############################################################################

is(stream('127.0.0.1:' . port(8081))->read(), 'true400', 'var set');

###############################################################################
