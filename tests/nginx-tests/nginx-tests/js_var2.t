#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module, js_var directive in server | location contexts.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)
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

        js_var $foo;

        location /test {
            js_content test.test;
        }

        location /sub {
            return 200 DONE;
        }

        location /dest {
            js_var $bar a:$arg_a;
            return 200 $bar;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test(r) {
        if (r.args.sub) {
            r.subrequest('/sub')
            .then(reply => {
                r.variables.bar = reply.responseText;
                r.internalRedirect('/dest');
            });

            return;
        }

        r.return(200, `V:\${r.variables[r.args.var]}`);
    }

    export default {test};

EOF

$t->try_run('no njs js_var')->plan(3);

###############################################################################

like(http_get('/test?var=bar&a=qq'), qr/200 OK.*V:a:qq$/s, 'default value');
like(http_get('/test?var=foo'), qr/200 OK.*V:$/s, 'default empty value');
like(http_get('/test?sub=1&var=bar&a=qq'), qr/200 OK.*DONE$/s, 'value set');

###############################################################################
