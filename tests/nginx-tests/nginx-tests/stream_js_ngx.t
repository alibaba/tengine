#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for stream njs module, ngx object.

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

http {
    %%TEST_GLOBALS_HTTP%%

    js_import test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /njs {
            js_content test.njs;
        }
    }
}

stream {
    js_import test.js;

    js_set $log     test.log;

    server {
        listen  127.0.0.1:8081;
        return  $log;
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function log(s) {
        ngx.log(ngx.INFO, `ngx.log:FOO`);
        ngx.log(ngx.WARN, `ngx.log:BAR`);
        ngx.log(ngx.ERR, `ngx.log:BAZ`);
        return 'OK';
    }

    export default {njs: test_njs, log};

EOF

$t->try_run('no njs ngx')->plan(4);

###############################################################################

TODO: {
local $TODO = 'not yet'
	unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.5.0';

is(stream('127.0.0.1:' . port(8081))->read(), 'OK', 'log var');

$t->stop();

like($t->read_file('error.log'), qr/\[info\].*ngx.log:FOO/, 'ngx.log info');
like($t->read_file('error.log'), qr/\[warn\].*ngx.log:BAR/, 'ngx.log warn');
like($t->read_file('error.log'), qr/\[error\].*ngx.log:BAZ/, 'ngx.log err');

}

###############################################################################
