# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 8 + 61);

#no_diff();
no_long_string();

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;

worker_connections(1024);
run_tests();

__DATA__

=== TEST 1: simple at
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local function f(premature)
                print("elapsed: ", ngx.now() - begin)
                print("timer prematurely expired: ", premature)
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

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]
timer prematurely expired: true

--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.0(?:4[4-9]|5[0-6])\d*, context: ngx\.timer, client: \d+\.\d+\.\d+\.\d+, server: 0\.0\.0\.0:\d+/,
"lua ngx.timer expired",
"http lua close fake http connection",
"timer prematurely expired: false",
]
--- grep_error_log eval: qr/lua caching unused lua thread|lua reusing cached lua thread/
--- grep_error_log_out eval
[
    "lua caching unused lua thread
lua caching unused lua thread
",
    "lua reusing cached lua thread
lua reusing cached lua thread
lua caching unused lua thread
lua caching unused lua thread
",
]



=== TEST 2: globals are shared
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local function f()
                foo = 3
                print("elapsed: ", ngx.now() - begin)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.06)
            ngx.say("foo = ", foo)
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
foo = 3

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.0(?:4[4-9]|5[0-6])/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 3: lua variable sharing via upvalue
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local foo
            local function f()
                foo = 3
                print("elapsed: ", ngx.now() - begin)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.06)
            ngx.say("foo = ", foo)
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
foo = 3

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.0(?:4[4-9]|5[0-6])/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 4: simple at (sleep in the timer callback)
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local function f()
                print("my lua timer handler")
                ngx.sleep(0.2)
                print("elapsed: ", ngx.now() - begin)
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
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.3
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
qr/\[lua\] .*? my lua timer handler/,
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.(?:1[4-9]|2[0-6]?)/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 5: tcp cosocket in timer handler (short connections)
--- config
    server_tokens off;

    location = /gc {
        content_by_lua_block {
            local c = collectgarbage("count")
            ngx.say("before: ", c)
            collectgarbage("collect")
            c = collectgarbage("count")
            ngx.say("after: ", c)
        }
    }

    location = /t {
        content_by_lua '
            collectgarbage()
            -- ngx.say("gc size: ", collectgarbage("count"))
            local begin = ngx.now()
            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end
            local function f()
                print("my lua timer handler")
                local sock = ngx.socket.tcp()
                local port = $TEST_NGINX_SERVER_PORT
                local ok, err = sock:connect("127.0.0.1", port)
                if not ok then
                    fail("failed to connect: ", err)
                    return
                end

                print("connected: ", ok)

                local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
                -- req = "OK"

                local bytes, err = sock:send(req)
                if not bytes then
                    fail("failed to send request: ", err)
                    return
                end

                print("request sent: ", bytes)

                while true do
                    local line, err, part = sock:receive()
                    if line then
                        print("received: ", line)

                    else
                        if err == "closed" then
                            break
                        end
                        fail("failed to receive a line: ", err, " [", part, "]")
                        break
                    end
                end

                ok, err = sock:close()
                print("close: ", ok, " ", err)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            -- ngx.sleep(0.1)
            ngx.say("registered timer")
        ';
    }

    location = /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
qr/\[lua\] .*? my lua timer handler/,
"lua ngx.timer expired",
"http lua close fake http connection",
"connected: 1",
"request sent: 57",
"received: HTTP/1.1 200 OK",
qr/received: Server: \S+/,
"received: Content-Type: text/plain",
"received: Content-Length: 4",
"received: Connection: close",
"received: foo",
"close: 1 nil",
]



=== TEST 6: tcp cosocket in timer handler (keep-alive connections)
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"

--- config
    location = /t {
        content_by_lua '
            local begin = ngx.now()
            local function f()
                print("my lua timer handler")

                local test = require "test"
                local port = $TEST_NGINX_MEMCACHED_PORT
                test.go(port)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }

--- user_files
>>> test.lua
module("test", package.seeall)

local function fail(...)
    ngx.log(ngx.ERR, ...)
end

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        fail("failed to connect: ", err)
        return
    end

    print("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        fail("failed to send request: ", err)
        return
    end
    print("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        print("received: ", line)

    else
        fail("failed to receive a line: ", err, " [", part, "]")
    end

    local ok, err = sock:setkeepalive()
    if not ok then
        fail("failed to set reusable: ", err)
    end
end

--- request
GET /t
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
qr/\[lua\] .*? my lua timer handler/,
"lua ngx.timer expired",
"http lua close fake http connection",
qr/go\(\): connected: 1, reused: \d+/,
"go(): request sent: 11",
"go(): received: OK",
]



=== TEST 7: 0 timer
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local function f()
                print("elapsed: ", ngx.now() - begin)
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0(?:[^.]|\.00)/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 8: udp cosocket in timer handler
--- config
    location = /t {
        content_by_lua '
            local begin = ngx.now()
            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end
            local function f()
                print("my lua timer handler")
                local socket = ngx.socket
                -- local socket = require "socket"

                local udp = socket.udp()

                local port = $TEST_NGINX_MEMCACHED_PORT
                udp:settimeout(1000) -- 1 sec

                local ok, err = udp:setpeername("127.0.0.1", port)
                if not ok then
                    fail("failed to connect: ", err)
                    return
                end

                print("connected: ", ok)

                local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
                local ok, err = udp:send(req)
                if not ok then
                    fail("failed to send: ", err)
                    return
                end

                local data, err = udp:receive()
                if not data then
                    fail("failed to receive data: ", err)
                    return
                end
                print("received ", #data, " bytes: ", data)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }

    location = /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
qr/\[lua\] .*? my lua timer handler/,
"lua ngx.timer expired",
"http lua close fake http connection",
"connected: 1",
"received 12 bytes: \x{00}\x{01}\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}"
]



=== TEST 9: simple at (sleep in the timer callback) - log_by_lua
--- config
    location /t {
        echo hello world;
        log_by_lua '
            local begin = ngx.now()
            local function f()
                print("my lua timer handler")
                ngx.sleep(0.02)
                print("elapsed: ", ngx.now() - begin)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to set timer: ", err)
                return
            end
            print("registered timer")
        ';
    }
--- request
GET /t
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 2: ok
delete thread 2

--- response_body
hello world

--- wait: 0.3
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"registered timer",
qr/\[lua\] .*? my lua timer handler/,
qr/\[lua\] log_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.0(?:6[4-9]|7[0-9]|8[1-3])/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 10: tcp cosocket in timer handler (keep-alive connections) - log_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"

--- config
    location = /t {
        echo hello;
        log_by_lua '
            local begin = ngx.now()
            local function f()
                print("my lua timer handler")

                local test = require "test"
                local port = $TEST_NGINX_MEMCACHED_PORT
                test.go(port)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to set timer: ", err)
                return
            end
            print("registered timer")
        ';
    }

--- user_files
>>> test.lua
module("test", package.seeall)

local function fail(...)
    ngx.log(ngx.ERR, ...)
end

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        fail("failed to connect: ", err)
        return
    end

    print("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        fail("failed to send request: ", err)
        return
    end
    print("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        print("received: ", line)

    else
        fail("failed to receive a line: ", err, " [", part, "]")
    end

    local ok, err = sock:setkeepalive()
    if not ok then
        fail("failed to set reusable: ", err)
    end
end

--- request
GET /t
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 2: ok
delete thread 2

--- response_body
hello

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"registered timer",
qr/\[lua\] .*? my lua timer handler/,
"lua ngx.timer expired",
"http lua close fake http connection",
qr/go\(\): connected: 1, reused: \d+/,
"go(): request sent: 11",
"go(): received: OK",
]



=== TEST 11: tcp cosocket in timer handler (keep-alive connections) - header_filter_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"

--- config
    location = /t {
        echo hello;
        header_filter_by_lua '
            local begin = ngx.now()
            local function f()
                print("my lua timer handler")

                local test = require "test"
                local port = $TEST_NGINX_MEMCACHED_PORT
                test.go(port)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to set timer: ", err)
                return
            end
            print("registered timer")
        ';
    }

--- user_files
>>> test.lua
module("test", package.seeall)

local function fail(...)
    ngx.log(ngx.ERR, ...)
end

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        fail("failed to connect: ", err)
        return
    end

    print("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        fail("failed to send request: ", err)
        return
    end
    print("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        print("received: ", line)

    else
        fail("failed to receive a line: ", err, " [", part, "]")
    end

    local ok, err = sock:setkeepalive()
    if not ok then
        fail("failed to set reusable: ", err)
    end
end

--- request
GET /t
--- stap2 eval: $::StapScript
--- stap3
global count = 0
F(ngx_http_lua_header_filter) {
    if (count++ == 10) {
        println("header filter")
        print_ubacktrace()
    }
}

--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 2: ok
delete thread 2

--- response_body
hello

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"registered timer",
qr/\[lua\] .*? my lua timer handler/,
"lua ngx.timer expired",
"http lua close fake http connection",
qr/go\(\): connected: 1, reused: \d+/,
"go(): request sent: 11",
"go(): received: OK",
]



=== TEST 12: tcp cosocket in timer handler (keep-alive connections) - body_filter_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"

--- config
    location = /t {
        echo hello;
        body_filter_by_lua '
            local begin = ngx.now()
            local function f()
                print("my lua timer handler")

                local test = require "test"
                local port = $TEST_NGINX_MEMCACHED_PORT
                test.go(port)
            end
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to set timer: ", err)
                return
            end
            print("registered timer")
        ';
    }

--- user_files
>>> test.lua
module("test", package.seeall)

local function fail(...)
    ngx.log(ngx.ERR, ...)
end

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        fail("failed to connect: ", err)
        return
    end

    print("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        fail("failed to send request: ", err)
        return
    end
    print("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        print("received: ", line)

    else
        fail("failed to receive a line: ", err, " [", part, "]")
    end

    local ok, err = sock:setkeepalive()
    if not ok then
        fail("failed to set keep alive: ", err)
    end
end

--- request
GET /t
--- stap2 eval: $::StapScript
--- stap3
global count = 0
F(ngx_http_lua_header_filter) {
    if (count++ == 10) {
        println("header filter")
        print_ubacktrace()
    }
}

--- stap eval: $::GCScript
--- stap_out_like chop
create 2 in 1
create 3 in 1
(?:terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3
|terminate 3: ok
delete thread 3
terminate 2: ok
delete thread 2)$

--- response_body
hello

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"registered timer",
qr/\[lua\] .*? my lua timer handler/,
"lua ngx.timer expired",
"http lua close fake http connection",
qr/go\(\): connected: 1, reused: \d+/,
"go(): request sent: 11",
"go(): received: OK",
]



=== TEST 13: tcp cosocket in timer handler (keep-alive connections) - set_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"

--- config
    location = /t {
        set_by_lua $a '
            local begin = ngx.now()
            local function f()
                print("my lua timer handler")

                local test = require "test"
                local port = $TEST_NGINX_MEMCACHED_PORT
                test.go(port)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to set timer: ", err)
                return
            end
            print("registered timer")
            return 32
        ';
        echo $a;
    }

--- user_files
>>> test.lua
module("test", package.seeall)

local function fail(...)
    ngx.log(ngx.ERR, ...)
end

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        fail("failed to connect: ", err)
        return
    end

    print("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        fail("failed to send request: ", err)
        return
    end
    print("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        print("received: ", line)

    else
        fail("failed to receive a line: ", err, " [", part, "]")
    end

    local ok, err = sock:setkeepalive()
    if not ok then
        fail("failed to set reusable: ", err)
    end
end

--- request
GET /t
--- stap2 eval: $::StapScript
--- stap3
global count = 0
F(ngx_http_lua_header_filter) {
    if (count++ == 10) {
        println("header filter")
        print_ubacktrace()
    }
}

--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 2: ok
delete thread 2

--- response_body
32

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"registered timer",
qr/\[lua\] .*? my lua timer handler/,
"lua ngx.timer expired",
"http lua close fake http connection",
qr/go\(\): connected: 1, reused: \d+/,
"go(): request sent: 11",
"go(): received: OK",
]



=== TEST 14: coroutine API
--- config
    location /t {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield
            local function f()
                local function f()
                    local cnt = 0
                    for i = 1, 20 do
                        print("cnt = ", cnt)
                        cy()
                        cnt = cnt + 1
                    end
                end

                local c = cc(f)
                for i=1,3 do
                    cr(c)
                    print("after resume, i = ", i)
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

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
create 3 in 2
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"lua ngx.timer expired",
"http lua close fake http connection",
"cnt = 0",
"after resume, i = 1",
"cnt = 1",
"after resume, i = 2",
"cnt = 2",
"after resume, i = 3",
]



=== TEST 15: ngx.thread API
--- config
    location /t {
        content_by_lua '
            local function fail (...)
                ngx.log(ngx.ERR, ...)
            end
            local function handle()
                local function f()
                    print("hello in thread")
                    return "done"
                end

                local t, err = ngx.thread.spawn(f)
                if not t then
                    fail("failed to spawn thread: ", err)
                    return
                end

                print("thread created: ", coroutine.status(t))

                collectgarbage()

                local ok, res = ngx.thread.wait(t)
                if not ok then
                    fail("failed to run thread: ", res)
                    return
                end

                print("wait result: ", res)
            end
            local ok, err = ngx.timer.at(0.01, handle)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
create 3 in 2
spawn user thread 3 in 2
terminate 3: ok
delete thread 3
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"lua ngx.timer expired",
"http lua close fake http connection",
"hello in thread",
"thread created: zombie",
"wait result: done",
]



=== TEST 16: shared dict
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location /t {
        content_by_lua '
            local function f()
                local dogs = ngx.shared.dogs
                dogs:set("foo", 32)
                dogs:set("bah", 10502)
                local val = dogs:get("foo")
                print("get foo: ", val, " ", type(val))
                val = dogs:get("bah")
                print("get bah: ", val, " ", type(val))
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

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"lua ngx.timer expired",
"http lua close fake http connection",
"get foo: 32 number",
"get bah: 10502 number",
]



=== TEST 17: ngx.exit(0)
--- config
    location /t {
        content_by_lua '
            local function f()
                local function g()
                    print("BEFORE ngx.exit")
                    ngx.exit(0)
                end
                g()
                print("CANNOT REACH HERE")
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
"lua ngx.timer expired",
"http lua close fake http connection",
"BEFORE ngx.exit",
]
--- no_error_log
CANNOT REACH HERE
API disabled



=== TEST 18: ngx.exit(403)
--- config
    location /t {
        content_by_lua '
            local function f()
                local function g()
                    print("BEFORE ngx.exit")
                    ngx.exit(403)
                end
                g()
                print("CANNOT REACH HERE")
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
[error]
[alert]
[crit]
CANNOT REACH HERE
API disabled

--- error_log eval
[
"lua ngx.timer expired",
"http lua close fake http connection",
"BEFORE ngx.exit",
]



=== TEST 19: exit in user thread (entry thread is still pending on ngx.sleep)
--- config
    location /t {
        content_by_lua '
            local function handle()
                local function f()
                    print("hello in thread")
                    ngx.sleep(0.1)
                    ngx.exit(0)
                end

                print("BEFORE thread spawn")
                ngx.thread.spawn(f)
                print("AFTER thread spawn")
                ngx.sleep(1)
                print("entry thread END")
            end
            local ok, err = ngx.timer.at(0.05, handle)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 1000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
    /*
    if (tm == 1000) {
        print_ubacktrace()
    }
    */
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_sleep_cleanup) {
    println("lua sleep cleanup")
}
_EOC_

--- stap_out_like chop
(?:create 2 in 1
terminate 1: ok
delete thread 1
free request
create 3 in 2
spawn user thread 3 in 2
add timer 100
add timer 1000
expire timer 100
terminate 3: ok
delete thread 3
lua sleep cleanup
delete timer 1000
delete thread 2|create 2 in 1
terminate 1: ok
delete thread 1
create 3 in 2
spawn user thread 3 in 2
add timer 100
add timer 1000
free request
expire timer 100
terminate 3: ok
delete thread 3
lua sleep cleanup
delete timer 1000
delete thread 2)$

--- response_body
registered timer

--- wait: 0.2
--- no_error_log
[error]
[alert]
[crit]
API disabled
entry thread END

--- error_log eval
[
"lua ngx.timer expired",
"http lua close fake http connection",
"BEFORE thread spawn",
"hello in thread",
"AFTER thread spawn",
]



=== TEST 20: chained timers (0 delay)
--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local function g()
                s = s .. "[g]"
                print("trace: ", s)
            end

            local function f()
                local ok, err = ngx.timer.at(0, g)
                if not ok then
                    fail("failed to set timer: ", err)
                    return
                end
                s = s .. "[f]"
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
create 3 in 2
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
'lua ngx.timer expired',
'http lua close fake http connection',
qr/trace: \[m\]\[f\]\[g\], context: ngx\.timer, client: \d+\.\d+\.\d+\.\d+, server: 0\.0\.0\.0:\d+/,
]



=== TEST 21: chained timers (non-zero delay)
--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local function g()
                s = s .. "[g]"
                print("trace: ", s)
            end

            local function f()
                local ok, err = ngx.timer.at(0.01, g)
                if not ok then
                    fail("failed to set timer: ", err)
                    return
                end
                s = s .. "[f]"
            end
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
create 3 in 2
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log
lua ngx.timer expired
http lua close fake http connection
trace: [m][f][g]



=== TEST 22: multiple parallel timers
--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local function g()
                s = s .. "[g]"
                print("trace: ", s)
            end

            local function f()
                s = s .. "[f]"
            end
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                fail("failed to set timer: ", err)
                return
            end
            local ok, err = ngx.timer.at(0.01, g)
            if not ok then
                fail("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log
lua ngx.timer expired
http lua close fake http connection
trace: [m][f][g]



=== TEST 23: lua_max_pending_timers
--- http_config
    lua_max_pending_timers 1;
--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local function g()
                s = s .. "[g]"
                print("trace: ", s)
            end

            local function f()
                s = s .. "[f]"
            end
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer f: ", err)
                return
            end
            local ok, err = ngx.timer.at(0.01, g)
            if not ok then
                ngx.say("failed to set timer g: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
failed to set timer g: too many pending timers

--- wait: 0.1
--- no_error_log
[alert]
[crit]
[error]

--- error_log
lua ngx.timer expired
http lua close fake http connection



=== TEST 24: lua_max_pending_timers (just not exceeding)
--- http_config
    lua_max_pending_timers 2;
--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local function g()
                s = s .. "[g]"
                print("trace: ", s)
            end

            local function f()
                s = s .. "[f]"
            end
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer f: ", err)
                return
            end
            local ok, err = ngx.timer.at(0.01, g)
            if not ok then
                ngx.say("failed to set timer g: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]
[error]

--- error_log
lua ngx.timer expired
http lua close fake http connection
trace: [m][f][g]



=== TEST 25: lua_max_pending_timers - chained timers (non-zero delay) - not exceeding
--- http_config
    lua_max_pending_timers 1;

--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local function g()
                s = s .. "[g]"
                print("trace: ", s)
            end

            local function f()
                local ok, err = ngx.timer.at(0.01, g)
                if not ok then
                    fail("failed to set timer: ", err)
                    return
                end
                s = s .. "[f]"
            end
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
create 3 in 2
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log
lua ngx.timer expired
http lua close fake http connection
trace: [m][f][g]



=== TEST 26: lua_max_pending_timers - chained timers (zero delay) - not exceeding
--- http_config
    lua_max_pending_timers 1;

--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local function g()
                s = s .. "[g]"
                print("trace: ", s)
            end

            local function f()
                local ok, err = ngx.timer.at(0, g)
                if not ok then
                    fail("failed to set timer: ", err)
                    return
                end
                s = s .. "[f]"
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
create 3 in 2
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]

--- error_log
lua ngx.timer expired
http lua close fake http connection
trace: [m][f][g]



=== TEST 27: lua_max_running_timers (just not enough)
--- http_config
    lua_max_running_timers 1;
--- config
    location /t {
        content_by_lua '
            collectgarbage()
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local f, g

            g = function ()
                ngx.sleep(0.01)
            end

            f = function ()
                ngx.sleep(0.01)
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer f: ", err)
                return
            end
            local ok, err = ngx.timer.at(0, g)
            if not ok then
                ngx.say("failed to set timer g: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[crit]
[error]

--- error_log eval
[
qr/\[alert\] .*? lua failed to run timer with function defined at =content_by_lua\(nginx.conf:\d+\):11: 1 lua_max_running_timers are not enough/,
"lua ngx.timer expired",
"http lua close fake http connection",
]



=== TEST 28: lua_max_running_timers (just enough)
--- http_config
    lua_max_running_timers 2;
--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local f, g

            g = function ()
                ngx.sleep(0.01)
            end

            f = function ()
                ngx.sleep(0.01)
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer f: ", err)
                return
            end
            local ok, err = ngx.timer.at(0, g)
            if not ok then
                ngx.say("failed to set timer g: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]
[error]

--- error_log
lua ngx.timer expired
http lua close fake http connection



=== TEST 29: lua_max_running_timers (just enough) - 2
--- http_config
    lua_max_running_timers 2;
--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local f, g

            g = function ()
                ngx.timer.at(0.02, f)
                ngx.sleep(0.01)
            end

            f = function ()
                ngx.sleep(0.01)
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer f: ", err)
                return
            end
            local ok, err = ngx.timer.at(0, g)
            if not ok then
                ngx.say("failed to set timer g: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
terminate 1: ok
delete thread 1
create 4 in 3
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3
terminate 4: ok
delete thread 4

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[alert]
[crit]
[error]

--- error_log
lua ngx.timer expired
http lua close fake http connection



=== TEST 30: user args
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local function f(premature, a, b, c)
                print("elapsed: ", ngx.now() - begin)
                print("timer prematurely expired: ", premature)
                print("timer user args: ", a, " ", b, " ", c)
            end
            local ok, err = ngx.timer.at(0.05, f, 1, "hello", true)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]
timer prematurely expired: true

--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.0(?:4[4-9]|5[0-6])\d*, context: ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection",
"timer prematurely expired: false",
"timer user args: 1 hello true",
]



=== TEST 31: use of ngx.ctx
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local function f(premature)
                ngx.ctx.s = "hello"
                print("elapsed: ", ngx.now() - begin)
                print("timer prematurely expired: ", premature)
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
        ';
    }
--- request
GET /t

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
[alert]
[crit]
timer prematurely expired: true

--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: .*?, context: ngx\.timer/,
"lua ngx.timer expired",
"http lua close fake http connection",
"timer prematurely expired: false",
"lua release ngx.ctx at ref ",
]



=== TEST 32: syslog error log
--- http_config
    #error_log syslog:server=127.0.0.1:12345 error;
--- config
    location /t {
        content_by_lua '
            local function f()
                ngx.log(ngx.ERR, "Bad bad bad")
            end
            ngx.timer.at(0, f)
            ngx.sleep(0.001)
            ngx.say("ok")
        ';
    }
--- log_level: error
--- error_log_file: syslog:server=127.0.0.1:12345
--- udp_listen: 12345
--- udp_query eval: qr/Bad bad bad/
--- udp_reply: hello
--- wait: 0.1
--- request
    GET /t
--- response_body
ok
--- error_log
Bad bad bad
--- skip_nginx: 4: < 1.7.1



=== TEST 33: log function location when failed to run a timer
--- http_config
    lua_max_running_timers 1;
--- config
    location /t {
        content_by_lua_block {
            local function g()
                ngx.sleep(0.01)
            end

            local function f()
                ngx.sleep(0.01)
            end

            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to create timer f: ", err)
                return
            end

            local ok, err = ngx.timer.at(0, g)
            if not ok then
                ngx.say("failed to create timer g: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- wait: 0.1
--- error_log eval
qr/\[alert\] .*? lua failed to run timer with function defined at =content_by_lua\(nginx.conf:\d+\):2: 1 lua_max_running_timers are not enough/
--- no_error_log
[crit]
[error]



=== TEST 34: log function location when failed to run a timer (anonymous function)
--- http_config
    lua_max_running_timers 1;
--- config
    location /t {
        content_by_lua_block {
            local function f()
                ngx.sleep(0.01)
            end

            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer f: ", err)
                return
            end

            local ok, err = ngx.timer.at(0, function()
                ngx.sleep(0.01)
            end)

            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- wait: 0.1
--- error_log eval
qr/\[alert\] .*? lua failed to run timer with function defined at =content_by_lua\(nginx.conf:\d+\):12: 1 lua_max_running_timers are not enough/
--- no_error_log
[crit]
[error]



=== TEST 35: log function location when failed to run a timer (lua file)
--- user_files
>>> test.lua
local _M = {}

function _M.run()
    ngx.sleep(0.01)
end

return _M
--- http_config
    lua_package_path '$TEST_NGINX_HTML_DIR/?.lua;./?.lua;;';
    lua_max_running_timers 1;
--- config
    location /t {
        content_by_lua_block {
            local test = require "test"

            local ok, err = ngx.timer.at(0, test.run)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            local ok, err = ngx.timer.at(0, test.run)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- wait: 0.1
--- no_error_log
[crit]
[error]
--- error_log eval
qr/\[alert\] .*? lua failed to run timer with function defined at @.+\/test.lua:3: 1 lua_max_running_timers are not enough/



=== TEST 36: log function location when failed to run a timer with args (lua file)
--- user_files
>>> test.lua
local _M = {}

function _M.run(premature, arg)
    ngx.sleep(0.01)
end

return _M
--- http_config
    lua_package_path '$TEST_NGINX_HTML_DIR/?.lua;./?.lua;;';
    lua_max_running_timers 1;
--- config
    location /t {
        content_by_lua_block {
            local test = require "test"

            local ok, err = ngx.timer.at(0, test.run, "arg")
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            local ok, err = ngx.timer.at(0, test.run, "arg")
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- wait: 0.1
--- no_error_log
[crit]
[error]
--- error_log eval
qr/\[alert\] .*? lua failed to run timer with function defined at @.+\/test.lua:3: 1 lua_max_running_timers are not enough/
