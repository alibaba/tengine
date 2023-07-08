# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

#connect 0.0.0.1 on newer kernel won't return EINVAL
#so add an route with cmd: sudo ip route add prohibit 0.0.0.1/32

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 9);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: simple logging
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
'[lua] balancer_by_lua(nginx.conf:27):2: hello from balancer by lua! while connecting to upstream,',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]
--- no_error_log
[warn]



=== TEST 2: exit 403
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
            ngx.exit(403)
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 403 Forbidden
--- error_code: 403
--- error_log
[lua] balancer_by_lua(nginx.conf:27):2: hello from balancer by lua! while connecting to upstream,
--- no_error_log eval
[
'[warn]',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]



=== TEST 3: exit OK
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
            ngx.exit(ngx.OK)
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
'[lua] balancer_by_lua(nginx.conf:27):2: hello from balancer by lua! while connecting to upstream,',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]
--- no_error_log
[warn]



=== TEST 4: ngx.var works
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("1: variable foo = ", ngx.var.foo)
            ngx.var.foo = tonumber(ngx.var.foo) + 1
            print("2: variable foo = ", ngx.var.foo)
        }
    }
--- config
    location = /t {
        set $foo 32;
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
"1: variable foo = 32",
"2: variable foo = 33",
qr/\[crit\] .* connect\(\) .*? failed/,
]
--- no_error_log
[warn]



=== TEST 5: ngx.req.get_headers works
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("header foo: ", ngx.req.get_headers()["foo"])
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- more_headers
Foo: bar
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
"header foo: bar",
qr/\[crit\] .* connect\(\) .*? failed/,
]
--- no_error_log
[warn]



=== TEST 6: ngx.req.get_uri_args() works
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("arg foo: ", (ngx.req.get_uri_args())["foo"])
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t?baz=blah&foo=bar
--- more_headers
Foo: bar
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
["arg foo: bar",
qr/\[crit\] .* connect\(\) .*? failed/,
]
--- no_error_log
[warn]



=== TEST 7: ngx.req.get_method() works
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("method: ", ngx.req.get_method())
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- more_headers
Foo: bar
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
"method: GET",
qr/\[crit\] .* connect\(\) .*? failed/,
]
--- no_error_log
[warn]



=== TEST 8: simple logging (by_lua_file)
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_file html/a.lua;
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- user_files
>>> a.lua
print("hello from balancer by lua!")
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
'[lua] a.lua:1: hello from balancer by lua! while connecting to upstream,',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]
--- no_error_log
[warn]



=== TEST 9: cosockets are disabled
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            local sock, err = ngx.socket.tcp()
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/\[error\] .*? failed to run balancer_by_lua\*: balancer_by_lua\(nginx\.conf:27\):2: API disabled in the context of balancer_by_lua\*/



=== TEST 10: ngx.sleep is disabled
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            ngx.sleep(0.1)
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/\[error\] .*? failed to run balancer_by_lua\*: balancer_by_lua\(nginx\.conf:27\):2: API disabled in the context of balancer_by_lua\*/



=== TEST 11: get_phase
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("I am in phase ", ngx.get_phase())
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- grep_error_log eval: qr/I am in phase \w+/
--- grep_error_log_out
I am in phase balancer
--- error_log eval
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"}
--- no_error_log
[error]



=== TEST 12: code cache off
--- http_config
    lua_package_path "$TEST_NGINX_SERVER_ROOT/html/?.lua;;";

    lua_code_cache off;

    upstream backend {
        server 127.0.0.1:$TEST_NGINX_SERVER_PORT;
        balancer_by_lua_block {
            require("test")
        }
    }
--- config
    location = /t {
        echo_location /main;
        echo_location /update;
        echo_location /main;
    }

    location = /update {
        content_by_lua_block {
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("$TEST_NGINX_SERVER_ROOT/html/test.lua", "w"))
            f:write("print('me: ', 101)")
            f:close()
            ngx.say("updated")
        }
    }

    location = /main {
        proxy_pass http://backend/back;
    }

    location = /back {
        echo ok;
    }
--- request
    GET /t
--- user_files
>>> test.lua
print("me: ", 32)
return {}
--- response_body
ok
updated
ok
--- grep_error_log eval: qr/\bme: \w+/
--- grep_error_log_out
me: 32
me: 101
--- no_error_log
[error]



=== TEST 13: lua subrequests
--- http_config
    lua_code_cache off;

    upstream backend {
        server 127.0.0.1:$TEST_NGINX_SERVER_PORT;
        balancer_by_lua_block {
            print("ctx counter: ", ngx.ctx.count)
            if not ngx.ctx.count then
                ngx.ctx.count = 1
            else
                ngx.ctx.count = ngx.ctx.count + 1
            end
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local res = ngx.location.capture("/main")
            ngx.print(res.body)
            res = ngx.location.capture("/main")
            ngx.print(res.body)
        }
    }

    location = /main {
        proxy_pass http://backend/back;
    }

    location = /back {
        echo ok;
    }
--- request
    GET /t
--- response_body
ok
ok
--- grep_error_log eval: qr/\bctx counter: \w+/
--- grep_error_log_out
ctx counter: nil
ctx counter: nil
--- no_error_log
[error]



=== TEST 14: ngx.log(ngx.ERR, ...) github #816
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            ngx.log(ngx.ERR, "hello from balancer by lua!")
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
'[lua] balancer_by_lua(nginx.conf:27):2: hello from balancer by lua! while connecting to upstream,',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]
--- no_error_log
[warn]



=== TEST 15: test if exceed proxy_next_upstream_limit
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";

    proxy_next_upstream_tries 5;
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            local b = require "ngx.balancer"

            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            if ngx.ctx.tries >= 6 then
                ngx.log(ngx.ERR, "retry count exceed limit")
                ngx.exit(500)
            end

            ngx.ctx.tries = ngx.ctx.tries + 1
            print("retry counter: ", ngx.ctx.tries)

            local ok, err = b.set_more_tries(2)
            if not ok then
                return error("failed to set more tries: ", err)
            elseif err then
                ngx.log(ngx.WARN, "set more tries: ", err)
            end

            assert(b.set_current_peer("127.0.0.1", 81))
        }
    }
--- config
    location = /t {
        proxy_pass http://backend/back;
    }

    location = /back {
        return 404;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- grep_error_log eval: qr/\bretry counter: \w+/
--- grep_error_log_out
retry counter: 1
retry counter: 2
retry counter: 3
retry counter: 4
retry counter: 5

--- error_log
set more tries: reduced tries due to limit



=== TEST 16: set_more_tries bugfix
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";
	proxy_next_upstream_tries 0;
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            local balancer = require "ngx.balancer"
			local ctx = ngx.ctx
			if not ctx.has_run then
				ctx.has_run = true
				local _, err = balancer.set_more_tries(3)
				if err then
					ngx.log(ngx.ERR, "failed to set more tries: ", err)
				end
			end
			balancer.set_current_peer("127.0.0.1", 81)
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- error_code: 502
--- grep_error_log eval: qr/http next upstream, \d+/
--- grep_error_log_out
http next upstream, 2
http next upstream, 2
http next upstream, 2
http next upstream, 2
--- no_error_log
failed to set more tries: reduced tries due to limit
[alert]



=== TEST 17: recreate_request buffer bugfix
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1;

        location / {
            return 200 "it works";
        }
    }

    upstream foo {
        server 127.0.0.1:$TEST_NGINX_RAND_PORT_1 max_fails=0;
        server 127.0.0.1:$TEST_NGINX_RAND_PORT_2 max_fails=0 weight=9999;

        balancer_by_lua_block {
            local bal = require "ngx.balancer"

            assert(bal.recreate_request())
        }
    }

--- config
    location = /t {
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_pass http://foo;
    }
--- request
GET /t
--- error_code: 200
--- error_log
connect() failed (111: Connection refused) while connecting to upstream
--- no_error_log
upstream sent more data than specified in "Content-Length" header while reading upstream
[alert]



=== TEST 18: error in balancer_by_llua_block
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            ngx.say("hello"
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
 "failed to load inlined Lua code: balancer_by_lua(nginx.conf:27):3: ')' expected (to close '(' at line 2) near '<eof>'",
--- no_error_log
[warn]
