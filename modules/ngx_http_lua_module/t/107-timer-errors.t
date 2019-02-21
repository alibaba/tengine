# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 7);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: accessing nginx variables
--- config
    location /t {
        content_by_lua '
            local function f()
                print("uri: ", ngx.var.uri)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 2: reading ngx.status
--- config
    location /t {
        content_by_lua '
            local function f()
                print("uri: ", ngx.status)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 3: writing ngx.status
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.status = 200
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 4: ngx.req.raw_header
--- config
    location /t {
        content_by_lua '
            local function f()
                print("raw header: ", ngx.req.raw_header())
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 5: ngx.req.get_headers
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.get_headers()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 6: ngx.req.set_header
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.set_header("Foo", 32)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 7: ngx.req.clear_header
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.clear_header("Foo")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 8: ngx.req.set_uri
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.set_uri("/foo")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 9: ngx.req.set_uri_args
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.set_uri_args("foo")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 10: ngx.redirect()
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.redirect("/foo")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 11: ngx.exec()
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.exec("/foo")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 12: ngx.say()
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.say("hello")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 13: ngx.print()
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.print("hello")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 14: ngx.flush()
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.flush()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 15: ngx.send_headers()
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.send_headers()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 16: ngx.req.get_uri_args()
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.get_uri_args()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 17: ngx.req.read_body
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.read_body()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 18: ngx.req.discard_body
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.discard_body()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 19: ngx.req.init_body
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.init_body()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 20: ngx.header
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.header.Foo = 3
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 21: ngx.on_abort
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.on_abort(f)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 22: ngx.location.capture
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.location.capture("/")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 23: ngx.location.capture_multi
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.location.capture_multi{{"/"}}
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 24: ngx.req.get_method
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.get_method()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 25: ngx.req.set_method
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.set_method(ngx.HTTP_POST)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 26: ngx.req.http_version
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.http_version()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 27: ngx.req.get_post_args
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.get_post_args()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 28: ngx.req.get_body_data
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.get_body_data()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 29: ngx.req.get_body_file
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.get_body_file()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 30: ngx.req.set_body_data
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.set_body_data("hello")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 31: ngx.req.set_body_file
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.set_body_file("hello")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 32: ngx.req.append_body
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.append_body("hello")
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 33: ngx.req.finish_body
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.req.finish_body()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.2
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 34: ngx.headers_sent
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.headers_sent()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the current context/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 35: ngx.eof
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.eof()
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 36: ngx.req.socket
--- config
    location /t {
        content_by_lua '
            local function f()
                local sock, err = ngx.req.socket()
                if not sock then
                    ngx.log(ngx.ERR, "failed to get req sock: ", err)
                end
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]

--- error_log eval
[
qr/\[error\] .*? runtime error: content_by_lua\(nginx\.conf:\d+\):3: API disabled in the context of ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection"
]
