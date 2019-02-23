# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('debug'); # to ensure any log-level can be outputted

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: test reading request body
--- config
    location /echo_body {
        lua_need_request_body on;
        rewrite_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"hello\x00\x01\x02
world\x03\x04\xff"



=== TEST 2: test not reading request body
--- config
    location /echo_body {
        lua_need_request_body off;
        rewrite_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"nil"



=== TEST 3: test default setting (not reading request body)
--- config
    location /echo_body {
        rewrite_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"nil"



=== TEST 4: test main conf
--- http_config
    lua_need_request_body on;
--- config
    location /echo_body {
        rewrite_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"hello\x00\x01\x02
world\x03\x04\xff"



=== TEST 5: test server conf
--- config
    lua_need_request_body on;

    location /echo_body {
        rewrite_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"hello\x00\x01\x02
world\x03\x04\xff"



=== TEST 6: test override main conf
--- http_config
    lua_need_request_body on;
--- config
    location /echo_body {
        lua_need_request_body off;
        rewrite_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"nil"



=== TEST 7: test override server conf
--- config
    lua_need_request_body on;

    location /echo_body {
        lua_need_request_body off;
        rewrite_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"nil"



=== TEST 8: Expect: 100-Continue
--- config
    location /echo_body {
        lua_need_request_body on;
        rewrite_by_lua '
            ngx.print(ngx.var.request_body or "nil")
            ngx.exit(200)
        ';
    }
--- request
POST /echo_body
hello world
--- more_headers
Expect: 100-Continue
--- ignore_response
--- no_error_log
[error]
[alert]
http finalize request: 500, "/echo_body?" a:1, c:2
http finalize request: 500, "/echo_body?" a:1, c:0
--- log_level: debug
