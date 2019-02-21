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
        content_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
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
        content_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
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
        content_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
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
        content_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
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
        content_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
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
        content_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
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
        content_by_lua '
            ngx.print(ngx.var.request_body or "nil")
        ';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"nil"



=== TEST 8: test override server conf
--- config
    location /proxy {
        proxy_pass http://127.0.0.1:$server_port/hi;
    }
    location /hi {
        echo_request_body;
    }
    location /echo_body {
        lua_need_request_body off;
        content_by_lua '
            ngx.say(ngx.var.request_body or "nil")
            local res = ngx.location.capture(
                "/proxy",
                { method = ngx.HTTP_POST,
                  body = ngx.var.request_body })

            ngx.say(res.status)
        ';
    }
--- request eval
"POST /echo_body
"
--- response_body
nil
200



=== TEST 9: empty POST body
--- config
    location /proxy {
        proxy_pass http://127.0.0.1:$server_port/hi;
    }
    location /hi {
        echo_request_body;
    }
    location /echo_body {
        lua_need_request_body on;
        content_by_lua '
            ngx.say(ngx.var.request_body or "nil")
            local res = ngx.location.capture(
                "/proxy",
                { method = ngx.HTTP_POST,
                  body = ngx.var.request_body })

            ngx.say(res.status)
        ';
    }
--- request eval
"POST /echo_body
"
--- response_body
nil
200



=== TEST 10: on disk request body
--- config
    location /proxy {
        proxy_pass http://127.0.0.1:$server_port/hi;
    }
    location /hi {
        echo_request_body;
    }
    location /echo_body {
        lua_need_request_body on;

        client_max_body_size 100k;
        client_body_buffer_size 1;
        sendfile on;

        content_by_lua '
            local res = ngx.location.capture(
                "/proxy",
                { method = ngx.HTTP_POST,
                  body = ngx.var.request_body })
            ngx.print(res.body)
        ';
    }
--- request eval
"POST /echo_body
" . ('a' x 1024)
--- response_body chomp



=== TEST 11: no modify main request content-length
--- config
    location /foo {
        content_by_lua '
            ngx.location.capture("/other", {body = "hello"})
            ngx.say(ngx.req.get_headers()["Content-Length"] or "nil")
        ';
    }
    location /other {
        echo hi;
    }
--- request
POST /foo
hi
--- response_body
2



=== TEST 12: Expect: 100-Continue
--- config
    location /echo_body {
        lua_need_request_body on;
        content_by_lua '
            ngx.print(ngx.var.request_body or "nil")
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
