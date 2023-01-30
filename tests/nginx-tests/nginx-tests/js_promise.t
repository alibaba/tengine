#!/usr/bin/perl

# (C) Nginx, Inc.

# Promise tests for http njs module.

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

        location /promise {
            js_content test.promise;
        }

        location /promise_throw {
            js_content test.promise_throw;
        }

        location /promise_pure {
            js_content test.promise_pure;
        }

        location /timeout {
            js_content test.timeout;
        }

        location /sub_token {
            js_content test.sub_token;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    var global_token = '';

    function test_njs(r) {
        r.return(200, njs.version);
    }

    function promise(r) {
        promisified_subrequest(r, '/sub_token', 'code=200&token=a')
        .then(reply => {
            var data = JSON.parse(reply.responseText);

            if (data['token'] !== "a") {
                throw new Error('token is not "a"');
            }

            return data['token'];
        })
        .then(token => {
            promisified_subrequest(r, '/sub_token', 'code=200&token=b')
            .then(reply => {
                var data = JSON.parse(reply.responseText);

                r.return(200, '{"token": "' + data['token'] + '"}');
            })
            .catch(() => {
                throw new Error("failed promise() test");
            });
        })
        .catch(() => {
            r.return(500);
        });
    }

    function promise_throw(r) {
        promisified_subrequest(r, '/sub_token', 'code=200&token=x')
        .then(reply => {
            var data = JSON.parse(reply.responseText);

            if (data['token'] !== "a") {
                throw data['token'];
            }

            return data['token'];
        })
        .then(() => {
            r.return(500);
        })
        .catch(token => {
            r.return(200, '{"token": "' + token + '"}');
        });
    }

    function promise_pure(r) {
        var count = 0;

        Promise.resolve(true)
        .then(() => count++)
        .then(() => not_exist_ref)
        .finally(() => count++)
        .catch(() => {
            r.return((count != 2) ? 500 : 200);
        });
    }

    function timeout(r) {
        promisified_subrequest(r, '/sub_token', 'code=200&token=R')
        .then(reply => JSON.parse(reply.responseText))
        .then(data => {
            setTimeout(timeout_cb, 50, r, '/sub_token', 'code=200&token=T');
            return data;
        })
        .then(data => {
            setTimeout(timeout_cb, 1, r, '/sub_token', 'code=200&token='
                                                        + data['token']);
        })
        .catch(() => {
            r.return(500);
        });
    }

    function timeout_cb(r, url, args) {
        promisified_subrequest(r, url, args)
        .then(reply => {
            if (global_token == '') {
                var data = JSON.parse(reply.responseText);

                global_token = data['token'];

                r.return(200, '{"token": "' + data['token'] + '"}');
            }
        })
        .catch(() => {
            r.return(500);
        });
    }

    function promisified_subrequest(r, uri, args) {
        return new Promise((resolve, reject) => {
            r.subrequest(uri, args, (reply) => {
                if (reply.status < 400) {
                    resolve(reply);
                } else {
                    reject(reply);
                }
            });
        })
    }

    function sub_token(r) {
        var code = r.variables.arg_code;
        var token = r.variables.arg_token;

        r.return(parseInt(code), '{"token": "'+ token +'"}');
    }

    export default {njs:test_njs, promise, promise_throw, promise_pure,
                    timeout, sub_token};

EOF

$t->try_run('no njs available')->plan(4);

###############################################################################

like(http_get('/promise'), qr/{"token": "b"}/, "Promise");
like(http_get('/promise_throw'), qr/{"token": "x"}/, "Promise throw and catch");
like(http_get('/timeout'), qr/{"token": "R"}/, "Promise with timeout");
like(http_get('/promise_pure'), qr/200 OK/, "events handling");

###############################################################################
