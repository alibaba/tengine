# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks() + 15);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

log_level 'warn';

no_long_string();
#no_diff();
#no_shuffle();
check_accum_error_log();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected")

            local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t
--- response_body eval
"connected\nreceived 12 bytes: \x{00}\x{01}\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}"
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua udp socket receive buffer size: 65536



=== TEST 2: multiple parallel queries
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected")

            local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            req = "\\0\\2\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            ngx.sleep(0.05)

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("1: received ", #data, " bytes: ", data)

            data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("2: received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t
--- response_body_like eval
"^connected\n"
."1: received 12 bytes: "
."\x{00}[\1\2]\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}"
."2: received 12 bytes: "
."\x{00}[\1\2]\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}\$"
--- no_error_log
[error]



=== TEST 3: access a TCP interface
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected")

            local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t
--- response_body
connected
failed to receive data: connection refused
--- error_log eval
qr/recv\(\) failed \(\d+: Connection refused\)/



=== TEST 4: access conflicts of connect() on shared udp objects
--- http_config
    lua_package_path '$prefix/html/?.lua;;';
--- config
    server_tokens off;
    location /main {
        content_by_lua '
            local reqs = {}
            for i = 1, 170 do
                table.insert(reqs, {"/t"})
            end
            local resps = {ngx.location.capture_multi(reqs)}
            for i = 1, 170 do
                ngx.say(resps[i].status)
            end
        ';
    }

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local port = ngx.var.port
            local foo = require "foo"
            local udp = foo.get_udp()

            udp:settimeout(100) -- 100 ms

            local ok, err = udp:setpeername("127.0.0.1", port)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(500)
            end

            ngx.say("connected")

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- user_files
>>> foo.lua
module("foo", package.seeall)

local udp

function get_udp()
    if not udp then
        udp = ngx.socket.udp()
    end

    return udp
end

--- stap2
M(http-lua-info) {
    printf("udp resume: %p\n", $coctx)
    print_ubacktrace()
}

--- request
GET /main
--- response_body_like: \b500\b
--- error_log eval
qr/content_by_lua\(nginx\.conf:\d+\):8: bad request/



=== TEST 5: access conflicts of receive() on shared udp objects
--- http_config
    lua_package_path '$prefix/html/?.lua;;';
--- config
    server_tokens off;
    location /main {
        content_by_lua '
            local reqs = {}
            for i = 1, 170 do
                table.insert(reqs, {"/t"})
            end
            local resps = {ngx.location.capture_multi(reqs)}
            for i = 1, 170 do
                ngx.say(resps[i].status)
            end
        ';
    }

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local port = ngx.var.port
            local foo = require "foo"
            local udp = foo.get_udp(port)

            local data, err = udp:receive()
            if not data then
                ngx.log(ngx.ERR, "failed to receive data: ", err)
                return ngx.exit(500)
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- user_files
>>> foo.lua
module("foo", package.seeall)

local udp

function get_udp(port)
    if not udp then
        udp = ngx.socket.udp()

        udp:settimeout(100) -- 100ms

        local ok, err = udp:setpeername("127.0.0.1", port)
        if not ok then
            ngx.log(ngx.ERR, "failed to connect: ", err)
            return ngx.exit(500)
        end
    end

    return udp
end
--- request
GET /main
--- response_body_like: \b500\b
--- error_log eval
qr/content_by_lua\(nginx\.conf:\d+\):6: bad request/



=== TEST 6: connect again immediately
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local sock = ngx.socket.udp()
            local port = ngx.var.port

            local ok, err = sock:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            ok, err = sock:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected again: ", ok)

            local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            local ok, err = sock:send(req)
            if not ok then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", ok)

            local line, err = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive: ", err)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
"connected: 1
connected again: 1
request sent: 1
received: \0\1\0\0\0\1\0\0OK\r\n
close: 1 nil
"
--- no_error_log
[error]
--- error_log eval
["lua reuse socket upstream", "lua udp socket reconnect without shutting down"]
--- log_level: debug



=== TEST 7: recv timeout
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.udp()
            sock:settimeout(100) -- 100 ms

            local ok, err = sock:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local line, err = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive: ", err)
            end

            -- ok, err = sock:close()
            -- ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua udp socket read timed out



=== TEST 8: with an explicit receive buffer size argument
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected")

            local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            local data, err = udp:receive(1400)
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t
--- response_body eval
"connected\nreceived 12 bytes: \x{00}\x{01}\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}"
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua udp socket receive buffer size: 1400



=== TEST 9: read timeout and re-receive
--- config
    location = /t {
        content_by_lua '
            local udp = ngx.socket.udp()
            udp:settimeout(30)
            local ok, err = udp:setpeername("127.0.0.1", 19232)
            if not ok then
                ngx.say("failed to setpeername: ", err)
                return
            end
            local ok, err = udp:send("blah")
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end
            for i = 1, 2 do
                local data, err = udp:receive()
                if err == "timeout" then
                    -- continue
                else
                    if not data then
                        ngx.say("failed to receive: ", err)
                        return
                    end
                    ngx.say("received: ", data)
                    return
                end
            end

            ngx.say("timed out")
        ';
    }
--- udp_listen: 19232
--- udp_reply: hello world
--- udp_reply_delay: 45ms
--- request
GET /t
--- response_body
received: hello world
--- error_log
lua udp socket read timed out



=== TEST 10: access the google DNS server (using IP addr)
--- config
    server_tokens off;
    location /t {
        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            udp:settimeout(5000) -- 5 sec

            local ok, err = udp:setpeername("$TEST_NGINX_RESOLVER", 53)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "\\0}\\1\\0\\0\\1\\0\\0\\0\\0\\0\\0\\3www\\6google\\3com\\0\\0\\1\\0\\1"

            -- ngx.print(req)
            -- do return end

            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end

            if string.match(data, "\\3www\\6google\\3com") then
                ngx.say("received a good response.")
            else
                ngx.say("received a bad response: ", #data, " bytes: ", data)
            end
        ';
    }
--- request
GET /t
--- response_body
received a good response.
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua udp socket receive buffer size: 65536
--- no_check_leak



=== TEST 11: access the google DNS server (using domain names)
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            -- avoid flushing google in "check leak" testing mode:
            local counter = package.loaded.counter
            if not counter then
                counter = 1
            elseif counter >= 2 then
                return ngx.exit(503)
            else
                counter = counter + 1
            end
            package.loaded.counter = counter

            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            udp:settimeout(2000) -- 2 sec

            local ok, err = udp:setpeername("google-public-dns-a.google.com", 53)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "\\0}\\1\\0\\0\\1\\0\\0\\0\\0\\0\\0\\3www\\6google\\3com\\0\\0\\1\\0\\1"

            -- ngx.print(req)
            -- do return end

            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end

            if string.match(data, "\\3www\\6google\\3com") then
                ngx.say("received a good response.")
            else
                ngx.say("received a bad response: ", #data, " bytes: ", data)
            end
        ';
    }
--- request
GET /t
--- response_body
received a good response.
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua udp socket receive buffer size: 65536
--- no_check_leak



=== TEST 12: github issue #215: Handle the posted requests in lua cosocket api (failed to resolve)
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 5s;

    location = /sub {
        content_by_lua '
            local sock = ngx.socket.udp()
            local ok, err = sock:setpeername("xxx", 80)
            if not ok then
                ngx.say("failed to connect to xxx: ", err)
                return
            end
            ngx.say("successfully connected to xxx!")
            sock:close()
        ';
    }

    location = /lua {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
        ';
    }
--- request
GET /sub

--- stap
F(ngx_resolve_name_done) {
    println("resolve name done")
}

--- stap_out
resolve name done

--- response_body_like chop
^failed to connect to xxx: xxx could not be resolved.*?Host not found

--- no_error_log
[error]
--- timeout: 10



=== TEST 13: github issue #215: Handle the posted requests in lua cosocket api (successfully resolved)
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 5s;

    location = /sub {
        content_by_lua '
            if not package.i then
                package.i = 1
            end

            local servers = {"openresty.org", "agentzh.org", "sregex.org"}
            local server = servers[package.i]
            package.i = package.i + 1

            local sock = ngx.socket.udp()
            local ok, err = sock:setpeername(server, 80)
            if not ok then
                ngx.say("failed to connect to ", server, ": ", err)
                return
            end
            ngx.say("successfully connected to xxx!")
            sock:close()
        ';
    }

    location = /lua {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
successfully connected to xxx!

--- no_error_log
[error]
--- timeout: 10



=== TEST 14: datagram unix domain socket
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("unix:a.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected")

            local req = "hello,\\nserver"
            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t

--- udp_listen: a.sock
--- udp_reply
hello,
client

--- response_body
connected
received 14 bytes: hello,
client

--- stap2
probe syscall.socket, syscall.connect {
    print(name, "(", argstr, ")")
}

probe syscall.socket.return, syscall.connect.return {
    println(" = ", retstr)
}
--- no_error_log
[error]
[crit]
--- skip_eval: 3: $^O ne 'linux'



=== TEST 15: bad request tries to setpeer
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    server_tokens off;
    location = /main {
        echo_location /t?reset=1;
        echo_location /t;
    }
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local test = require "test"
            if ngx.var.arg_reset then
                local sock = test.new_sock()
                local ok, err = sock:setpeername("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to set peer: ", err)
                else
                    ngx.say("peer set")
                end
                return
            end
            local sock = test.get_sock()
            sock:setpeername("127.0.0.1", ngx.var.port)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function new_sock()
    sock = ngx.socket.udp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^peer set
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):14: bad request/

--- no_error_log
[alert]



=== TEST 16: bad request tries to send
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    server_tokens off;
    location = /main {
        echo_location /t?reset=1;
        echo_location /t;
    }
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local test = require "test"
            if ngx.var.arg_reset then
                local sock = test.new_sock()
                local ok, err = sock:setpeername("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to set peer: ", err)
                else
                    ngx.say("peer set")
                end
                return
            end
            local sock = test.get_sock()
            sock:send("a")
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function new_sock()
    sock = ngx.socket.udp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^peer set
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):14: bad request/

--- no_error_log
[alert]



=== TEST 17: bad request tries to receive
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    server_tokens off;
    location = /main {
        echo_location /t?reset=1;
        echo_location /t;
    }
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local test = require "test"
            if ngx.var.arg_reset then
                local sock = test.new_sock()
                local ok, err = sock:setpeername("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to set peer: ", err)
                else
                    ngx.say("peer set")
                end
                return
            end
            local sock = test.get_sock()
            sock:receive()
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function new_sock()
    sock = ngx.socket.udp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^peer set
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):14: bad request/

--- no_error_log
[alert]



=== TEST 18: bad request tries to close
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    server_tokens off;
    location = /main {
        echo_location /t?reset=1;
        echo_location /t;
    }
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local test = require "test"
            if ngx.var.arg_reset then
                local sock = test.new_sock()
                local ok, err = sock:setpeername("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to set peer: ", err)
                else
                    ngx.say("peer set")
                end
                return
            end
            local sock = test.get_sock()
            sock:close()
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function new_sock()
    sock = ngx.socket.udp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^peer set
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):14: bad request/

--- no_error_log
[alert]



=== TEST 19: the upper bound of port range should be 2^16 - 1
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.udp()
            local ok, err = sock:setpeername("127.0.0.1", 65536)
            if not ok then
                ngx.say("failed to connect: ", err)
            end
        }
    }
--- request
GET /t
--- response_body
failed to connect: bad port number: 65536
--- no_error_log
[error]



=== TEST 20: send boolean and nil
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local socket = ngx.socket
            local udp = socket.udp()
            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", ngx.var.port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local function send(data)
                local bytes, err = udp:send(data)
                if not bytes then
                    ngx.say("failed to send: ", err)
                    return
                end
                ngx.say("sent ok")
            end

            send(true)
            send(false)
            send(nil)
        }
    }
--- request
GET /t
--- response_body
sent ok
sent ok
sent ok
--- no_error_log
[error]
--- grep_error_log eval
qr/send: fd:\d+ \d+ of \d+/
--- grep_error_log_out eval
qr/send: fd:\d+ 4 of 4
send: fd:\d+ 5 of 5
send: fd:\d+ 3 of 3/
--- log_level: debug



=== TEST 21: send numbers
Note: maximum number of digits after the decimal-point character is 13
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local socket = ngx.socket
            local udp = socket.udp()
            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", ngx.var.port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local function send(data)
                local bytes, err = udp:send(data)
                if not bytes then
                    ngx.say("failed to send: ", err)
                    return
                end
                ngx.say("sent ok")
            end

            send(123456)
            send(3.141926)
            send(3.141592653579397238)
        }
    }
--- request
GET /t
--- response_body
sent ok
sent ok
sent ok
--- no_error_log
[error]
--- grep_error_log eval
qr/send: fd:\d+ \d+ of \d+/
--- grep_error_log_out eval
qr/send: fd:\d+ 6 of 6
send: fd:\d+ 8 of 8
send: fd:\d+ 15 of 15/
--- log_level: debug



=== TEST 22: send tables of string fragments (with numbers too)
the maximum number of significant digits is 14 in lua
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local socket = ngx.socket
            local udp = socket.udp()
            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", ngx.var.port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local function send(data)
                local bytes, err = udp:send(data)
                if not bytes then
                    ngx.say("failed to send: ", err)
                    return
                end
                ngx.say("sent ok")
            end

            send({"integer: ", 1234567890123})
            send({"float: ", 3.1419265})
            send({"float: ", 3.141592653579397238})
        }
    }
--- request
GET /t
--- response_body
sent ok
sent ok
sent ok
--- no_error_log
[error]
--- grep_error_log eval
qr/send: fd:\d+ \d+ of \d+/
--- grep_error_log_out eval
qr/send: fd:\d+ 22 of 22
send: fd:\d+ 16 of 16
send: fd:\d+ 22 of 22/
--- log_level: debug
