# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 3);

no_root_location();

no_long_string();
run_tests();

__DATA__

=== TEST 1: rewrite args (string with \r)
--- config
    location /foo {
        rewrite_by_lua_block {
            ngx.req.set_uri_args("a\rb")
        }
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/echo;
    }
    location /echo {
        content_by_lua_block {
            ngx.say(ngx.var.request_uri);
        }
    }
--- request
GET /foo?world
--- error_code: 200
--- response_body
/echo?a%0Db



=== TEST 2: rewrite args (string with \n)
--- config
    location /foo {
        rewrite_by_lua_block {
            ngx.req.set_uri_args("a\nb")
        }
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/echo;
    }
    location /echo {
        content_by_lua_block {
            ngx.say(ngx.var.request_uri);
        }
    }
--- request
GET /foo?world
--- response_body
/echo?a%0Ab



=== TEST 3: rewrite args (string with \0)
--- config
    location /foo {
        rewrite_by_lua_block {
            ngx.req.set_uri_args("a\0b")
        }
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/echo;
    }
    location /echo {
        content_by_lua_block {
            ngx.say(ngx.var.request_uri);
        }
    }
--- request
GET /foo?world
--- response_body
/echo?a%00b



=== TEST 4: rewrite args (string arg with 'lang=中文')
ngx.req.set_uri_args with string argument should be carefully encoded.
For backward compatibility, we are allowed to pass such parameters.
--- config
    location /foo {
        rewrite_by_lua_block {
            ngx.req.set_uri_args("lang=中文")
        }
        content_by_lua_block {
            ngx.say(ngx.var.arg_lang)
        }
    }
--- request
GET /foo?world
--- response_body
中文
--- no_error_log
[error]



=== TEST 5: rewrite args (string arg with '语言=chinese')
ngx.req.set_uri_args with string argument should be carefully encoded.
For backward compatibility, we are allowed to pass such parameters.
--- config
    location /foo {
        rewrite_by_lua_block {
            ngx.req.set_uri_args("语言=chinese")
        }
        content_by_lua_block {
            ngx.say(ngx.var.arg_语言)
        }
    }
--- request
GET /foo?world
--- response_body
chinese
--- no_error_log
[error]



=== TEST 6: rewrite args (string arg with '语言=中文')
ngx.req.set_uri_args with string argument should be carefully encoded.
For backward compatibility, we are allowed to pass such parameters.
--- config
    location /foo {
        rewrite_by_lua_block {
            ngx.req.set_uri_args("语言=中文")
        }
        content_by_lua_block {
            ngx.say(ngx.var.arg_语言)
        }
    }
--- request
GET /foo?world
--- response_body
中文
--- no_error_log
[error]
