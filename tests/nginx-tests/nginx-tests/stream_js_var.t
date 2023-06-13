#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for stream njs module, js_var directive.

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

    js_import test.js;

    js_var $foo;
    js_var $bar a:$remote_addr;
    js_set $var test.varr;

    server {
        listen  127.0.0.1:8081;
        return  $bar$foo;
    }

    server {
        listen  127.0.0.1:8082;
        return  $var$foo;
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function varr(s) {
        s.variables.foo = 'xxx';
        return '';
    }

    export default {varr};
EOF

$t->try_run('no stream js_var')->plan(2);

###############################################################################

is(stream('127.0.0.1:' . port(8081))->io('###'), 'a:127.0.0.1',
	'default value');
is(stream('127.0.0.1:' . port(8082))->io('###'), 'xxx', 'value set');

###############################################################################
