#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, ngx object.

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

        location /log {
            js_content test.log;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function level(r) {
        switch (r.args.level) {
        case 'INFO': return ngx.INFO;
        case 'WARN': return ngx.WARN;
        case 'ERR': return ngx.ERR;
        default:
            throw Error(`Unknown log level:"\${r.args.level}"`);
        }
    }

    function log(r) {
        ngx.log(level(r), `ngx.log:\${r.args.text}`);
        r.return(200);
    }

    export default {njs: test_njs, log};

EOF

$t->try_run('no njs ngx')->plan(3);

###############################################################################

http_get('/log?level=INFO&text=FOO');
http_get('/log?level=WARN&text=BAR');
http_get('/log?level=ERR&text=BAZ');

$t->stop();

like($t->read_file('error.log'), qr/\[info\].*ngx.log:FOO/, 'ngx.log info');
like($t->read_file('error.log'), qr/\[warn\].*ngx.log:BAR/, 'ngx.log warn');
like($t->read_file('error.log'), qr/\[error\].*ngx.log:BAZ/, 'ngx.log err');

###############################################################################
