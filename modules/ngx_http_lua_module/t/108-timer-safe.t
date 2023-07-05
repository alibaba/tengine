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

plan tests => repeat_each() * (blocks() * 8 + 60);

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
            local function f()
                print("elapsed: ", ngx.now() - begin)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.05)
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
terminate 1: ok
delete thread 1

--- response_body
registered timer

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



=== TEST 2: simple at (sleep in the timer callback)
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local function f()
                print("my lua timer handler")
                ngx.sleep(0.2)
                print("elapsed: ", ngx.now() - begin)
            end
            local ok, err = ngx.timer.at(0.5, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.5)
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

--- wait: 0.5
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
qr/\[lua\] .*? my lua timer handler/,
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.(?:6[4-9]|7[0-6])/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 3: tcp cosocket in timer handler (short connections)
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
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
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.02)
        ';
    }

    location = /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- stap2 eval: $::StapScript
--- stap3 eval: $::GCScript
--- stap_out2
create 2 in 1
terminate 1: ok
delete thread 1
terminate 3: ok
delete thread 3
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



=== TEST 4: tcp cosocket in timer handler (keep-alive connections)
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
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.02)
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
--- stap3 eval: $::GCScript
--- stap_out2
create 2 in 1
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

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



=== TEST 5: 0 timer
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

--- wait: 0.02
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



=== TEST 6: udp cosocket in timer handler
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
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.05)
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
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

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



=== TEST 7: simple at (sleep in the timer callback) - log_by_lua
--- config
    location /t {
        echo hello world;
        echo_sleep 0.07;
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

--- wait: 0.15
--- no_error_log
[error]
[alert]
[crit]

--- error_log eval
[
"registered timer",
qr/\[lua\] .*? my lua timer handler/,
qr/\[lua\] log_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.0(?:6[4-9]|7[0-9]|8[0-6])/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 8: tcp cosocket in timer handler (keep-alive connections) - log_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"

--- config
    location = /t {
        echo hello;
        echo_sleep 0.01;
        log_by_lua '
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



=== TEST 9: tcp cosocket in timer handler (keep-alive connections) - header_filter_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"

--- config
    location = /t {
        echo hello;
        echo_sleep 0.01;
        header_filter_by_lua '
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



=== TEST 10: tcp cosocket in timer handler (keep-alive connections) - body_filter_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"

--- config
    location = /t {
        echo_sleep 0.01;
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



=== TEST 11: tcp cosocket in timer handler (keep-alive connections) - set_by_lua
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
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to set timer: ", err)
                return
            end
            print("registered timer")
            return 32
        ';
        echo $a;
        echo_sleep 0.01;
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



=== TEST 12: coroutine API
--- config
    location /t {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield
            local function f()
                function f()
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
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.01)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 2
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

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



=== TEST 13: ngx.thread API
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
            ngx.sleep(0.02)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 2
spawn user thread 3 in 2
terminate 3: ok
delete thread 3
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

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



=== TEST 14: shared dict
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
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.02)
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
terminate 1: ok
delete thread 1

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



=== TEST 15: ngx.exit(0)
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
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.01)
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



=== TEST 16: ngx.exit(403)
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
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.01)
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



=== TEST 17: exit in user thread (entry thread is still pending on ngx.sleep)
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
            local ok, err = ngx.timer.at(0.01, handle)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.12)
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

--- stap_out
create 2 in 1
create 3 in 2
spawn user thread 3 in 2
add timer 100
add timer 1000
expire timer 100
terminate 3: ok
delete thread 3
lua sleep cleanup
delete timer 1000
delete thread 2
terminate 1: ok
delete thread 1
free request

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



=== TEST 18: chained timers (non-zero delay)
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
            ngx.sleep(0.03)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 2
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3
terminate 1: ok
delete thread 1

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
