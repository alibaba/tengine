# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 21);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed []
close: 1 nil
--- no_error_log
[error]



=== TEST 2: no trailing newline
--- config
    server_tokens off;
    location /t {
        #set $port 1234;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
            ngx.say("closed")
        ';
    }

    location /foo {
        content_by_lua 'ngx.print("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 3
received: Connection: close
received: 
failed to receive a line: closed [foo]
closed
--- no_error_log
[error]



=== TEST 3: no resolver defined
--- config
    server_tokens off;
    location /t {
        #set $port 1234;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("agentzh.org", port)
            if not ok then
                ngx.say("failed to connect: ", err)
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: no resolver defined to resolve "agentzh.org"
connected: nil
failed to send request: closed
--- error_log
attempt to send data on a closed socket:



=== TEST 4: with resolver
--- timeout: 10
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = 80
            local ok, err = sock:connect("agentzh.org", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET / HTTP/1.0\\r\\nHost: agentzh.org\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local line, err = sock:receive()
            if line then
                ngx.say("first line received: ", line)

            else
                ngx.say("failed to receive the first line: ", err)
            end

            line, err = sock:receive()
            if line then
                ngx.say("second line received: ", line)

            else
                ngx.say("failed to receive the second line: ", err)
            end
        ';
    }

--- request
GET /t
--- response_body_like
connected: 1
request sent: 56
first line received: HTTP\/1\.1 200 OK
second line received: (?:Date|Server): .*?
--- no_error_log
[error]
--- timeout: 10



=== TEST 5: connection refused (tcp)
--- config
    location /test {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 16787)
            ngx.say("connect: ", ok, " ", err)

            local bytes
            bytes, err = sock:send("hello")
            ngx.say("send: ", bytes, " ", err)

            local line
            line, err = sock:receive()
            ngx.say("receive: ", line, " ", err)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }
--- request
    GET /test
--- response_body
connect: nil connection refused
send: nil closed
receive: nil closed
close: nil closed
--- error_log eval
qr/connect\(\) failed \(\d+: Connection refused\)/



=== TEST 6: connection timeout (tcp)
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_socket_connect_timeout 100ms;
    lua_socket_send_timeout 100ms;
    lua_socket_read_timeout 100ms;
    resolver_timeout 3s;
    location /test {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.2", 12345)
            ngx.say("connect: ", ok, " ", err)

            local bytes
            bytes, err = sock:send("hello")
            ngx.say("send: ", bytes, " ", err)

            local line
            line, err = sock:receive()
            ngx.say("receive: ", line, " ", err)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }
--- request
    GET /test
--- response_body
connect: nil timeout
send: nil closed
receive: nil closed
close: nil closed
--- error_log
lua tcp socket connect timed out, when connecting to 127.0.0.2:12345
--- timeout: 10



=== TEST 7: not closed manually
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
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
--- no_error_log
[error]



=== TEST 8: resolver error (host not found)
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = 80
            local ok, err = sock:connect("blah-blah-not-found.agentzh.org", port)
            print("connected: ", ok, " ", err, " ", not ok)
            if not ok then
                ngx.say("failed to connect: ", err)
            end

            ngx.say("connected: ", ok)

            local req = "GET / HTTP/1.0\\r\\nHost: agentzh.org\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)
        ';
    }
--- request
GET /t
--- response_body_like
^failed to connect: blah-blah-not-found\.agentzh\.org could not be resolved(?: \(3: Host not found\))?
connected: nil
failed to send request: closed$
--- error_log
attempt to send data on a closed socket
--- timeout: 10



=== TEST 9: resolver error (timeout)
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 1ms;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = 80
            local ok, err = sock:connect("blah-blah-not-found.agentzh.org", port)
            print("connected: ", ok, " ", err, " ", not ok)
            if not ok then
                ngx.say("failed to connect: ", err)
            end

            ngx.say("connected: ", ok)

            local req = "GET / HTTP/1.0\\r\\nHost: agentzh.org\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)
        ';
    }
--- request
GET /t
--- response_body_like
^failed to connect: blah-blah-not-found\.agentzh\.org could not be resolved(?: \(\d+: (?:Operation timed out|Host not found)\))?
connected: nil
failed to send request: closed$
--- error_log
attempt to send data on a closed socket



=== TEST 10: explicit *l pattern for receive
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err = sock:receive("*l")
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err)
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed
close: 1 nil
--- no_error_log
[error]



=== TEST 11: *a pattern for receive
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local data, err = sock:receive("*a")
            if data then
                ngx.say("receive: ", data)
                ngx.say("err: ", err)

            else
                ngx.say("failed to receive: ", err)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
"connected: 1
request sent: 57
receive: HTTP/1.1 200 OK\r
Server: nginx\r
Content-Type: text/plain\r
Content-Length: 4\r
Connection: close\r
\r
foo

err: nil
close: 1 nil
"
--- no_error_log
[error]



=== TEST 12: mixing *a and *l patterns for receive
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local line, err = sock:receive("*l")
            if line then
                ngx.say("receive: ", line)
                ngx.say("err: ", err)

            else
                ngx.say("failed to receive: ", err)
            end

            local data
            data, err = sock:receive("*a")
            if data then
                ngx.say("receive: ", data)
                ngx.say("err: ", err)

            else
                ngx.say("failed to receive: ", err)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
"connected: 1
request sent: 57
receive: HTTP/1.1 200 OK
err: nil
receive: Server: nginx\r
Content-Type: text/plain\r
Content-Length: 4\r
Connection: close\r
\r
foo

err: nil
close: 1 nil
"
--- no_error_log
[error]



=== TEST 13: receive by chunks
--- timeout: 5
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local data, err, partial = sock:receive(10)
                if data then
                    local len = string.len(data)
                    if len == 10 then
                        ngx.print("[", data, "]")
                    else
                        ngx.say("ERROR: returned invalid length of data: ", len)
                    end

                else
                    ngx.say("failed to receive a line: ", err, " [", partial, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
"connected: 1
request sent: 57
[HTTP/1.1 2][00 OK\r
Ser][ver: nginx][\r
Content-][Type: text][/plain\r
Co][ntent-Leng][th: 4\r
Con][nection: c][lose\r
\r
fo]failed to receive a line: closed [o
]
close: 1 nil
"
--- no_error_log
[error]



=== TEST 14: receive by chunks (very small buffer)
--- timeout: 5
--- config
    server_tokens off;
    lua_socket_buffer_size 1;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local data, err, partial = sock:receive(10)
                if data then
                    local len = string.len(data)
                    if len == 10 then
                        ngx.print("[", data, "]")
                    else
                        ngx.say("ERROR: returned invalid length of data: ", len)
                    end

                else
                    ngx.say("failed to receive a line: ", err, " [", partial, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
"connected: 1
request sent: 57
[HTTP/1.1 2][00 OK\r
Ser][ver: nginx][\r
Content-][Type: text][/plain\r
Co][ntent-Leng][th: 4\r
Con][nection: c][lose\r
\r
fo]failed to receive a line: closed [o
]
close: 1 nil
"
--- no_error_log
[error]



=== TEST 15: line reading (very small buffer)
--- config
    server_tokens off;
    lua_socket_buffer_size 1;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed []
close: 1 nil
--- no_error_log
[error]



=== TEST 16: ngx.socket.connect (working)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local port = ngx.var.port
            local sock, err = ngx.socket.connect("127.0.0.1", port)
            if not sock then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected.")

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected.
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed []
close: 1 nil
--- no_error_log
[error]



=== TEST 17: ngx.socket.connect() shortcut (connection refused)
--- config
    location /test {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local sock, err = sock:connect("127.0.0.1", 16787)
            if not sock then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes
            bytes, err = sock:send("hello")
            ngx.say("send: ", bytes, " ", err)

            local line
            line, err = sock:receive()
            ngx.say("receive: ", line, " ", err)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }
--- request
    GET /test

--- stap2
M(http-lua-info) {
    printf("tcp resume: %p\n", $coctx)
    print_ubacktrace()
}

--- response_body
failed to connect: connection refused
--- error_log eval
qr/connect\(\) failed \(\d+: Connection refused\)/



=== TEST 18: receive by chunks (stringified size)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local data, err, partial = sock:receive("10")
                if data then
                    local len = string.len(data)
                    if len == 10 then
                        ngx.print("[", data, "]")
                    else
                        ngx.say("ERROR: returned invalid length of data: ", len)
                    end

                else
                    ngx.say("failed to receive a line: ", err, " [", partial, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
"connected: 1
request sent: 57
[HTTP/1.1 2][00 OK\r
Ser][ver: nginx][\r
Content-][Type: text][/plain\r
Co][ntent-Leng][th: 4\r
Con][nection: c][lose\r
\r
fo]failed to receive a line: closed [o
]
close: 1 nil
"
--- no_error_log
[error]



=== TEST 19: cannot survive across request boundary (send)
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local test = require "test"
            test.go(ngx.var.port)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function go(port)
    if not sock then
        sock = ngx.socket.tcp()
        local port = ngx.var.port
        local ok, err = sock:connect("127.0.0.1", port)
        if not ok then
            ngx.say("failed to connect: ", err)
            return
        end

        ngx.say("connected: ", ok)
    end

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end
    ngx.say("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        ngx.say("received: ", line)

    else
        ngx.say("failed to receive a line: ", err, " [", part, "]")
    end
end
--- request
GET /t
--- response_body_like eval
"^(?:connected: 1
request sent: 11
received: OK|failed to send request: closed)\$"



=== TEST 20: cannot survive across request boundary (receive)
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local test = require "test"
            test.go(ngx.var.port)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function go(port)
    if not sock then
        sock = ngx.socket.tcp()
        local port = ngx.var.port
        local ok, err = sock:connect("127.0.0.1", port)
        if not ok then
            ngx.say("failed to connect: ", err)
            return
        end

        ngx.say("connected: ", ok)

    else
        local line, err, part = sock:receive()
        if line then
            ngx.say("received: ", line)

        else
            ngx.say("failed to receive a line: ", err, " [", part, "]")
        end
        return
    end

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end
    ngx.say("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        ngx.say("received: ", line)

    else
        ngx.say("failed to receive a line: ", err, " [", part, "]")
    end
end

--- stap2
M(http-lua-info) {
    printf("tcp resume\n")
    print_ubacktrace()
}
--- request
GET /t
--- response_body_like eval
qr/^(?:connected: 1
request sent: 11
received: OK|failed to receive a line: closed \[nil\])$/



=== TEST 21: cannot survive across request boundary (close)
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local test = require "test"
            test.go(ngx.var.port)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function go(port)
    if not sock then
        sock = ngx.socket.tcp()
        local port = ngx.var.port
        local ok, err = sock:connect("127.0.0.1", port)
        if not ok then
            ngx.say("failed to connect: ", err)
            return
        end

        ngx.say("connected: ", ok)

    else
        local ok, err = sock:close()
        if ok then
            ngx.say("successfully closed")

        else
            ngx.say("failed to close: ", err)
        end
        return
    end

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end
    ngx.say("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        ngx.say("received: ", line)

    else
        ngx.say("failed to receive a line: ", err, " [", part, "]")
    end
end
--- request
GET /t
--- response_body_like eval
qr/^(?:connected: 1
request sent: 11
received: OK|failed to close: closed)$/



=== TEST 22: cannot survive across request boundary (connect)
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local test = require "test"
            test.go(ngx.var.port)
            test.go(ngx.var.port)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function go(port)
    if not sock then
        sock = ngx.socket.tcp()
        local port = ngx.var.port
        local ok, err = sock:connect("127.0.0.1", port)
        if not ok then
            ngx.say("failed to connect: ", err)
            return
        end

        ngx.say("connected: ", ok)

    else
        local port = ngx.var.port
        local ok, err = sock:connect("127.0.0.1", port)
        if not ok then
            ngx.say("failed to connect again: ", err)
            return
        end

        ngx.say("connected again: ", ok)
    end

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end
    ngx.say("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        ngx.say("received: ", line)

    else
        ngx.say("failed to receive a line: ", err, " [", part, "]")
    end
end
--- request
GET /t
--- response_body_like eval
qr/^(?:connected(?: again)?: 1
request sent: 11
received: OK
){2}$/
--- error_log
lua reuse socket upstream ctx
--- no_error_log
[error]
--- SKIP



=== TEST 23: connect again immediately
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected again: ", ok)

            local req = "flush_all\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local line, err, part = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive a line: ", err, " [", part, "]")
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
--- response_body
connected: 1
connected again: 1
request sent: 11
received: OK
close: 1 nil
--- no_error_log
[error]
--- error_log eval
["lua reuse socket upstream", "lua tcp socket reconnect without shutting down"]



=== TEST 24: two sockets mix together
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port1 $TEST_NGINX_MEMCACHED_PORT;
        set $port2 $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock1 = ngx.socket.tcp()
            local sock2 = ngx.socket.tcp()

            local port1 = ngx.var.port1
            local port2 = ngx.var.port2

            local ok, err = sock1:connect("127.0.0.1", port1)
            if not ok then
                ngx.say("1: failed to connect: ", err)
                return
            end

            ngx.say("1: connected: ", ok)

            ok, err = sock2:connect("127.0.0.1", port2)
            if not ok then
                ngx.say("2: failed to connect: ", err)
                return
            end

            ngx.say("2: connected: ", ok)

            local req1 = "flush_all\\r\\n"
            local bytes, err = sock1:send(req1)
            if not bytes then
                ngx.say("1: failed to send request: ", err)
                return
            end
            ngx.say("1: request sent: ", bytes)

            local req2 = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            local bytes, err = sock2:send(req2)
            if not bytes then
                ngx.say("2: failed to send request: ", err)
                return
            end
            ngx.say("2: request sent: ", bytes)

            local line, err, part = sock1:receive()
            if line then
                ngx.say("1: received: ", line)

            else
                ngx.say("1: failed to receive a line: ", err, " [", part, "]")
            end

            line, err, part = sock2:receive()
            if line then
                ngx.say("2: received: ", line)

            else
                ngx.say("2: failed to receive a line: ", err, " [", part, "]")
            end

            ok, err = sock1:close()
            ngx.say("1: close: ", ok, " ", err)

            ok, err = sock2:close()
            ngx.say("2: close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
1: connected: 1
2: connected: 1
1: request sent: 11
2: request sent: 57
1: received: OK
2: received: HTTP/1.1 200 OK
1: close: 1 nil
2: close: 1 nil
--- no_error_log
[error]



=== TEST 25: send tables of string fragments (with integers too)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = {"GET", " ", "/foo", " HTTP/", 1, ".", 0, "\\r\\n",
                         "Host: localhost\\r\\n", "Connection: close\\r\\n",
                         "\\r\\n"}
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed []
close: 1 nil
--- no_error_log
[error]



=== TEST 26: send tables of string fragments (bad type "nil")
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = {"GET", " ", "/foo", " HTTP/", nil, 1, ".", 0, "\\r\\n",
                         "Host: localhost\\r\\n", "Connection: close\\r\\n",
                         "\\r\\n"}
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
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
--- ignore_response
--- error_log
bad argument #1 to 'send' (bad data type nil found)



=== TEST 27: send tables of string fragments (bad type "boolean")
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = {"GET", " ", "/foo", " HTTP/", true, 1, ".", 0, "\\r\\n",
                         "Host: localhost\\r\\n", "Connection: close\\r\\n",
                         "\\r\\n"}
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
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
--- ignore_response
--- error_log
bad argument #1 to 'send' (bad data type boolean found)



=== TEST 28: send tables of string fragments (bad type ngx.null)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = {"GET", " ", "/foo", " HTTP/", ngx.null, 1, ".", 0, "\\r\\n",
                         "Host: localhost\\r\\n", "Connection: close\\r\\n",
                         "\\r\\n"}
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
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
--- ignore_response
--- error_log
bad argument #1 to 'send' (bad data type userdata found)



=== TEST 29: cosocket before location capture (tcpsock:send did not clear u->waiting)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "flush_all\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local line, err, part = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive a line: ", err, " [", part, "]")
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)

            local resp = ngx.location.capture("/memc")
            if type(resp) ~= "table" then
                ngx.say("bad resp: type ", type(resp), ": ", resp)
                return
            end

            ngx.print("subrequest: ", resp.status, ", ", resp.body)
        ';
    }

    location /memc {
        set $memc_cmd flush_all;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
GET /t
--- response_body eval
"connected: 1
request sent: 11
received: OK
close: 1 nil
subrequest: 200, OK\r
"
--- no_error_log
[error]



=== TEST 30: CR in a line
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo "foo\r\rbar\rbaz";
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 13
received: Connection: close
received: 
received: foobarbaz
failed to receive a line: closed []
close: nil closed
--- no_error_log
[error]
--- SKIP



=== TEST 31: receive(0)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local data, err, part = sock:receive(0)
            if not data then
                ngx.say("failed to receive(0): ", err)
                return
            end

            ngx.say("receive(0): [", data, "]")

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
--- response_body
connected: 1
request sent: 57
receive(0): []
close: 1 nil
--- no_error_log
[error]



=== TEST 32: send("")
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local bytes, err = sock:send("")
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("send(\\"\\"): ", bytes)

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
--- response_body
connected: 1
request sent: 57
send(""): 0
close: 1 nil
--- no_error_log
[error]
[alert]



=== TEST 33: github issue #215: Handle the posted requests in lua cosocket api (failed to resolve)
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;

    location = /sub {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("xxx", 80)
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
GET /lua

--- stap
F(ngx_resolve_name_done) {
    println("resolve name done")
    #print_ubacktrace()
}

--- stap_out
resolve name done

--- response_body_like chop
^failed to connect to xxx: xxx could not be resolved.*?Host not found

--- no_error_log
[error]



=== TEST 34: github issue #215: Handle the posted requests in lua cosocket api (successfully resolved)
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

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect(server, 80)
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

--- stap
F(ngx_http_lua_socket_resolve_handler) {
    println("lua socket resolve handler")
}

F(ngx_http_lua_socket_tcp_conn_retval_handler) {
    println("lua socket tcp connect retval handler")
}

F(ngx_http_run_posted_requests) {
    println("run posted requests")
}

--- stap_out_like
run posted requests
lua socket resolve handler
run posted requests
lua socket tcp connect retval handler
run posted requests

--- no_error_log
[error]
--- timeout: 10



=== TEST 35: connection refused (tcp) - lua_socket_log_errors off
--- config
    location /test {
        lua_socket_log_errors off;
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 16787)
            ngx.say("connect: ", ok, " ", err)

            local bytes
            bytes, err = sock:send("hello")
            ngx.say("send: ", bytes, " ", err)

            local line
            line, err = sock:receive()
            ngx.say("receive: ", line, " ", err)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }
--- request
    GET /test
--- response_body
connect: nil connection refused
send: nil closed
receive: nil closed
close: nil closed
--- no_error_log eval
[qr/connect\(\) failed \(\d+: Connection refused\)/]



=== TEST 36: reread after a read time out happen (receive -> receive)
--- config
    server_tokens off;
    lua_socket_read_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)

                line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive: ", err)
                end
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
failed to receive: timeout
--- error_log
lua tcp socket read timeout: 100
lua tcp socket connect timeout: 60000
lua tcp socket read timed out



=== TEST 37: successful reread after a read time out happen (receive -> receive)
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", ngx.var.server_port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send("GET /back HTTP/1.1\\r\\nHost: localhost\\r\\n\\r\\n")
            if not bytes then
                ngx.say("failed to send: ", err)
                return
            end

            local reader = sock:receiveuntil("\\r\\n\\r\\n")
            local header, err = reader()
            if not header then
                ngx.say("failed to read the response header: ", err)
                return
            end

            sock:settimeout(100)

            local data, err, partial = sock:receive(100)
            if data then
                ngx.say("received: ", data)
            else
                ngx.say("failed to receive: ", err, ", partial: ", partial)

                sock:settimeout(123)
                ngx.sleep(0.1)
                local line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end
                ngx.say("received: ", line)

                local line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end
                ngx.say("received: ", line)
            end
        ';
    }

    location /back {
        content_by_lua '
            ngx.print("hi")
            ngx.flush(true)
            ngx.sleep(0.2)
            ngx.print("world")
        ';
    }
--- request
GET /t
--- response_body eval
"failed to receive: timeout, partial: 2\r
hi\r

received: 5
received: world
"
--- error_log
lua tcp socket read timed out
--- no_error_log
[alert]



=== TEST 38: successful reread after a read time out happen (receive -> receiveuntil)
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", ngx.var.server_port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send("GET /back HTTP/1.1\\r\\nHost: localhost\\r\\n\\r\\n")
            if not bytes then
                ngx.say("failed to send: ", err)
                return
            end

            local reader = sock:receiveuntil("\\r\\n\\r\\n")
            local header, err = reader()
            if not header then
                ngx.say("failed to read the response header: ", err)
                return
            end

            sock:settimeout(100)

            local data, err, partial = sock:receive(100)
            if data then
                ngx.say("received: ", data)
            else
                ngx.say("failed to receive: ", err, ", partial: ", partial)

                ngx.sleep(0.1)

                sock:settimeout(123)
                local reader = sock:receiveuntil("\\r\\n")

                local line, err = reader()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end
                ngx.say("received: ", line)

                local line, err = reader()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end
                ngx.say("received: ", line)
            end
        ';
    }

    location /back {
        content_by_lua '
            ngx.print("hi")
            ngx.flush(true)
            ngx.sleep(0.2)
            ngx.print("world")
        ';
    }
--- request
GET /t
--- response_body eval
"failed to receive: timeout, partial: 2\r
hi\r

received: 5
received: world
"
--- error_log
lua tcp socket read timed out
--- no_error_log
[alert]



=== TEST 39: successful reread after a read time out happen (receiveuntil -> receiveuntil)
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", ngx.var.server_port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send("GET /back HTTP/1.1\\r\\nHost: localhost\\r\\n\\r\\n")
            if not bytes then
                ngx.say("failed to send: ", err)
                return
            end

            local reader = sock:receiveuntil("\\r\\n\\r\\n")
            local header, err = reader()
            if not header then
                ngx.say("failed to read the response header: ", err)
                return
            end

            sock:settimeout(100)

            local reader = sock:receiveuntil("no-such-terminator")
            local data, err, partial = reader()
            if data then
                ngx.say("received: ", data)
            else
                ngx.say("failed to receive: ", err, ", partial: ", partial)

                ngx.sleep(0.1)

                sock:settimeout(123)

                local reader = sock:receiveuntil("\\r\\n")

                local line, err = reader()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end
                ngx.say("received: ", line)

                local line, err = reader()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end
                ngx.say("received: ", line)
            end
        ';
    }

    location /back {
        content_by_lua '
            ngx.print("hi")
            ngx.flush(true)
            ngx.sleep(0.2)
            ngx.print("world")
        ';
    }
--- request
GET /t
--- response_body eval
"failed to receive: timeout, partial: 2\r
hi\r

received: 5
received: world
"
--- error_log
lua tcp socket read timed out
--- no_error_log
[alert]



=== TEST 40: successful reread after a read time out happen (receiveuntil -> receive)
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", ngx.var.server_port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send("GET /back HTTP/1.1\\r\\nHost: localhost\\r\\n\\r\\n")
            if not bytes then
                ngx.say("failed to send: ", err)
                return
            end

            local reader = sock:receiveuntil("\\r\\n\\r\\n")
            local header, err = reader()
            if not header then
                ngx.say("failed to read the response header: ", err)
                return
            end

            sock:settimeout(100)

            local reader = sock:receiveuntil("no-such-terminator")
            local data, err, partial = reader()
            if data then
                ngx.say("received: ", data)
            else
                ngx.say("failed to receive: ", err, ", partial: ", partial)

                ngx.sleep(0.1)

                sock:settimeout(123)

                local line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end
                ngx.say("received: ", line)

                local line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end
                ngx.say("received: ", line)
            end
        ';
    }

    location /back {
        content_by_lua '
            ngx.print("hi")
            ngx.flush(true)
            ngx.sleep(0.2)
            ngx.print("world")
        ';
    }
--- request
GET /t
--- response_body eval
"failed to receive: timeout, partial: 2\r
hi\r

received: 5
received: world
"
--- error_log
lua tcp socket read timed out
--- no_error_log
[alert]



=== TEST 41: receive(0)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local data, err = sock:receive(0)
            if not data then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("received: ", data)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
connected: 1
received: 
close: 1 nil
--- no_error_log
[error]



=== TEST 42: empty options table
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port, {})
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
connected: 1
close: 1 nil
--- no_error_log
[error]



=== TEST 43: u->coctx left over bug
--- config
    server_tokens off;
    location = /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local ready = false
            local fatal = false

            local function f()
                local line, err, part = sock:receive()
                if not line then
                    ngx.say("failed to receive the 1st line: ", err, " [", part, "]")
                    fatal = true
                    return
                end
                ready = true
                ngx.sleep(1)
            end

            local st = ngx.thread.spawn(f)
            while true do
                if fatal then
                    return
                end

                if not ready then
                    ngx.sleep(0.01)
                else
                    break
                end
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    -- ngx.say("received: ", line)

                else
                    -- ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
            ngx.exit(0)
        ';
    }

    location /foo {
        content_by_lua 'ngx.sleep(0.1) ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
connected: 1
request sent: 57
close: 1 nil
--- no_error_log
[error]
--- error_log
lua clean up the timer for pending ngx.sleep



=== TEST 44: bad request tries to connect
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
                test.new_sock()
            end
            local sock = test.get_sock()
            local ok, err = sock:connect("127.0.0.1", ngx.var.port)
            if not ok then
                ngx.say("failed to connect: ", err)
            else
                ngx.say("connected")
            end
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function new_sock()
    sock = ngx.socket.tcp()
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^connected
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):7: bad request/

--- no_error_log
[alert]



=== TEST 45: bad request tries to receive
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
                local ok, err = sock:connect("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                else
                    ngx.say("connected")
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
    sock = ngx.socket.tcp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^connected
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):14: bad request/

--- no_error_log
[alert]



=== TEST 46: bad request tries to send
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
                local ok, err = sock:connect("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                else
                    ngx.say("connected")
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
    sock = ngx.socket.tcp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^connected
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):14: bad request/

--- no_error_log
[alert]



=== TEST 47: bad request tries to close
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
                local ok, err = sock:connect("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                else
                    ngx.say("connected")
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
    sock = ngx.socket.tcp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^connected
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):14: bad request/

--- no_error_log
[alert]



=== TEST 48: bad request tries to set keepalive
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
                local ok, err = sock:connect("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                else
                    ngx.say("connected")
                end
                return
            end
            local sock = test.get_sock()
            sock:setkeepalive()
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function new_sock()
    sock = ngx.socket.tcp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^connected
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):14: bad request/

--- no_error_log
[alert]



=== TEST 49: bad request tries to receiveuntil
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
                local ok, err = sock:connect("127.0.0.1", ngx.var.port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                else
                    ngx.say("connected")
                end
                return
            end
            local sock = test.get_sock()
            local it, err = sock:receiveuntil("abc")
            if it then
                it()
            end
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock

function new_sock()
    sock = ngx.socket.tcp()
    return sock
end

function get_sock()
    return sock
end
--- request
GET /main
--- response_body_like eval
qr/^connected
<html.*?500 Internal Server Error/ms

--- error_log eval
qr/runtime error: content_by_lua\(nginx\.conf:\d+\):16: bad request/

--- no_error_log
[alert]



=== TEST 50: cosocket resolving aborted by coroutine yielding failures (require)
--- http_config
    lua_package_path "$prefix/html/?.lua;;";
    resolver $TEST_NGINX_RESOLVER ipv6=off;

--- config
    location = /t {
        content_by_lua '
            package.loaded.myfoo = nil
            require "myfoo"
        ';
    }
--- request
    GET /t
--- user_files
>>> myfoo.lua
local sock = ngx.socket.tcp()
local ok, err = sock:connect("agentzh.org", 12345)
if not ok then
    ngx.log(ngx.ERR, "failed to connect: ", err)
    return
end

--- response_body_like: 500 Internal Server Error
--- wait: 0.3
--- error_code: 500
--- error_log
resolve name done
runtime error: attempt to yield across C-call boundary
--- no_error_log
[alert]



=== TEST 51: cosocket resolving aborted by coroutine yielding failures (xpcall err)
--- http_config
    lua_package_path "$prefix/html/?.lua;;";
    resolver $TEST_NGINX_RESOLVER ipv6=off;

--- config
    location = /t {
        content_by_lua '
            local function f()
                return error(1)
            end
            local function err()
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("agentzh.org", 12345)
                if not ok then
                    ngx.log(ngx.ERR, "failed to connect: ", err)
                    return
                end
            end
            xpcall(f, err)
            ngx.say("ok")
        ';
    }
--- request
    GET /t
--- response_body
ok
--- wait: 0.3
--- error_log
resolve name done
--- no_error_log
[error]
[alert]
could not cancel



=== TEST 52: tcp_nodelay on
--- config
    tcp_nodelay on;
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t

--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed []
close: 1 nil
--- error_log
lua socket tcp_nodelay
--- no_error_log
[error]



=== TEST 53: tcp_nodelay off
--- config
    tcp_nodelay off;
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t

--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed []
close: 1 nil
--- no_error_log
lua socket tcp_nodelay
[error]



=== TEST 54: IPv6
--- http_config
    server_tokens off;

    server {
        listen [::1]:$TEST_NGINX_SERVER_PORT;

        location /foo {
            content_by_lua 'ngx.say("foo")';
            more_clear_headers Date;
        }
    }
--- config
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("[::1]", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed []
close: 1 nil
--- no_error_log
[error]
--- skip_eval: 3: system("ping6 -c 1 ::1 >/dev/null 2>&1") ne 0



=== TEST 55: kill a thread with a connecting socket
--- config
    server_tokens off;
    lua_socket_connect_timeout 1s;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        content_by_lua '
            local sock

            local thr = ngx.thread.spawn(function ()
                sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.2", 12345)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)
            end)

            ngx.sleep(0.002)
            ngx.thread.kill(thr)
            ngx.sleep(0.001)

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to setkeepalive: ", err)
            else
                ngx.say("setkeepalive: ", ok)
            end
        ';
    }

--- request
GET /t
--- response_body
failed to setkeepalive: closed
--- error_log
lua tcp socket connect timeout: 100
--- timeout: 10



=== TEST 56: reuse cleanup
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            for i = 1, 2 do
                local ok, err = sock:connect("127.0.0.1", port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local req = "GET /foo HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send request: ", err)
                    return
                end

                ngx.say("request sent: ", bytes)

                while true do
                    local line, err, part = sock:receive()
                    if not line then
                        ngx.say("failed to receive a line: ", err, " [", part, "]")
                        break
                    end
                end

                ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end
        }
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
connected: 1
request sent: 57
failed to receive a line: closed []
close: 1 nil
connected: 1
request sent: 57
failed to receive a line: closed []
close: 1 nil
--- error_log
lua http cleanup reuse



=== TEST 57: reuse cleanup in ngx.timer (fake_request)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local total_send_bytes = 0
            local port = ngx.var.port

            local function network()
                local sock = ngx.socket.tcp()

                local ok, err = sock:connect("127.0.0.1", port)
                if not ok then
                    ngx.log(ngx.ERR, "failed to connect: ", err)
                    return
                end

                local req = "GET /foo HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.log(ngx.ERR, "failed to send request: ", err)
                    return
                end

                total_send_bytes = total_send_bytes + bytes

                while true do
                    local line, err, part = sock:receive()
                    if not line then
                        break
                    end
                end

                ok, err = sock:close()
            end

            local done = false

            local function double_network()
                network()
                network()
                done = true
            end

            local ok, err = ngx.timer.at(0, double_network)
            if not ok then
                ngx.say("failed to create timer: ", err)
            end

            local i = 1
            while not done do
                local time = 0.005 * i
                if time > 0.1 then
                    time = 0.1
                end
                ngx.sleep(time)
                i = i + 1
            end

            collectgarbage("collect")

            ngx.say("total_send_bytes: ", total_send_bytes)
        }
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
total_send_bytes: 114
--- error_log
lua http cleanup reuse



=== TEST 58: free cleanup in ngx.timer (without sock:close)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local total_send_bytes = 0
            local port = ngx.var.port

            local function network()
                local sock = ngx.socket.tcp()

                local ok, err = sock:connect("127.0.0.1", port)
                if not ok then
                    ngx.log(ngx.ERR, "failed to connect: ", err)
                    return
                end

                local req = "GET /foo HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.log(ngx.ERR, "failed to send request: ", err)
                    return
                end

                total_send_bytes = total_send_bytes + bytes

                while true do
                    local line, err, part = sock:receive()
                    if not line then
                        break
                    end
                end
            end

            local done = false

            local function double_network()
                network()
                network()
                done = true
            end

            local ok, err = ngx.timer.at(0, double_network)
            if not ok then
                ngx.say("failed to create timer: ", err)
            end

            local i = 1
            while not done do
                local time = 0.005 * i
                if time > 0.1 then
                    time = 0.1
                end
                ngx.sleep(time)
                i = i + 1
            end

            collectgarbage("collect")

            ngx.say("total_send_bytes: ", total_send_bytes)
        }
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
total_send_bytes: 114
--- no_error_log
[error]



=== TEST 59: reuse cleanup in subrequest
--- config
    server_tokens off;
    location /t {
        echo_location /tt;
    }

    location /tt {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            for i = 1, 2 do
                local ok, err = sock:connect("127.0.0.1", port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"

                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send request: ", err)
                    return
                end

                ngx.say("request sent: ", bytes)

                while true do
                    local line, err, part = sock:receive()
                    if not line then
                        ngx.say("failed to receive a line: ", err, " [", part, "]")
                        break
                    end
                end

                ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("foo")';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
connected: 1
request sent: 57
failed to receive a line: closed []
close: 1 nil
connected: 1
request sent: 57
failed to receive a line: closed []
close: 1 nil
--- error_log
lua http cleanup reuse



=== TEST 60: setkeepalive on socket already shutdown
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, "failed to close socket: ", err)
                return
            end

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.log(ngx.ERR, "failed to setkeepalive: ", err)
            end
        }
    }
--- request
GET /t
--- response_body
connected: 1
--- error_log
failed to setkeepalive: closed



=== TEST 61: options_table is nil
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            local ok, err = sock:connect("127.0.0.1", port, nil)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "flush_all\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local line, err, part = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive a line: ", err, " [", part, "]")
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 11
received: OK
close: 1 nil
--- no_error_log
[error]



=== TEST 62: resolver send query failing immediately in connect()
this case did not clear coctx->cleanup properly and would lead to memory invalid accesses.

this test case requires the following iptables rule to work properly:

sudo iptables -I OUTPUT 1 -p udp --dport 10086 -j REJECT

--- config
    location /t {
        resolver 127.0.0.1:10086 ipv6=off;
        resolver_timeout 10ms;

        content_by_lua_block {
            local sock = ngx.socket.tcp()

            for i = 1, 3 do -- retry
                local ok, err = sock:connect("www.google.com", 80)
                if not ok then
                    ngx.say("failed to connect: ", err)
                end
            end

            ngx.say("hello!")
        }
    }
--- request
GET /t
--- response_body_like
failed to connect: www.google.com could not be resolved(?: \(\d+: Operation timed out\))?
failed to connect: www.google.com could not be resolved(?: \(\d+: Operation timed out\))?
failed to connect: www.google.com could not be resolved(?: \(\d+: Operation timed out\))?
hello!
--- error_log eval
qr{\[alert\] .*? send\(\) failed \(\d+: Operation not permitted\) while resolving}



=== TEST 63: the upper bound of port range should be 2^16 - 1
--- config
    location /t {
        content_by_lua_block {
            local sock, err = ngx.socket.connect("127.0.0.1", 65536)
            if not sock then
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



=== TEST 64: send boolean and nil
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local function send(data)
                local bytes, err = sock:send(data)
                if not bytes then
                    ngx.say("failed to send request: ", err)
                    return
                end
            end

            local req = "GET /foo HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\nTest: "
            send(req)
            send(true)
            send(false)
            send(nil)
            send("\r\n\r\n")

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)
                else
                    break
                end
            end

            ok, err = sock:close()
        }
    }

    location /foo {
        server_tokens off;
        more_clear_headers Date;
        echo $http_test;
    }

--- request
GET /t
--- response_body
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Connection: close
received: 
received: truefalsenil
--- no_error_log
[error]



=== TEST 65: receiveany method in cosocket
--- config
    server_tokens off;
    location = /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(500)
            assert(sock:connect("127.0.0.1", ngx.var.port))
            local req = {
                'GET /foo HTTP/1.0\r\n',
                'Host: localhost\r\n',
                'Connection: close\r\n\r\n',
            }
            local ok, err = sock:send(req)
            if not ok then
                ngx.say("send request failed: ", err)
                return
            end

            -- skip http header
            while true do
                local data, err, _ = sock:receive('*l')
                if err then
                    ngx.say('unexpected error occurs when receiving http head: ', err)
                    return
                end

                if #data == 0 then -- read last line of head
                    break
                end
            end

            -- receive http body
            while true do
                local data, err = sock:receiveany(1024)
                if err then
                    if err ~= 'closed' then
                        ngx.say('unexpected err: ', err)
                    end
                    break
                end
                ngx.say(data)
            end

            sock:close()
        }
    }

    location = /foo {
        content_by_lua_block {
            local resp = {
                '1',
                '22',
                'hello world',
            }

            local length = 0
            for _, v in ipairs(resp) do
                length = length + #v
            end

            -- flush http header
            ngx.header['Content-Length'] = length
            ngx.flush(true)
            ngx.sleep(0.01)

            -- send http body
            for _, v in ipairs(resp) do
                ngx.print(v)
                ngx.flush(true)
                ngx.sleep(0.01)
            end
        }
    }

--- request
GET /t
--- response_body
1
22
hello world
--- no_error_log
[error]
--- error_log
lua tcp socket read any



=== TEST 66: receiveany send data after read side closed
--- config
    server_tokens off;
    location = /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(500)
            assert(sock:connect("127.0.0.1", 7658))

            while true do
                local data, err = sock:receiveany(1024)
                if err then
                    if err ~= 'closed' then
                        ngx.say('unexpected err: ', err)
                        break
                    end

                    local data = "send data after read side closed"
                    local bytes, err = sock:send(data)
                    if not bytes then
                        ngx.say(err)
                    end

                    break
                end
                ngx.say(data)
            end

            sock:close()
        }
    }

--- request
GET /t
--- tcp_listen: 7658
--- tcp_shutdown: 1
--- tcp_query eval: "send data after read side closed"
--- tcp_query_len: 32
--- response_body
--- no_error_log
[error]



=== TEST 67: receiveany with limited, max <= 0
--- config
    location = /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(500)
            assert(sock:connect("127.0.0.1", ngx.var.port))

            local function receiveany_say_err(...)
                local ok, err = pcall(sock.receiveany, sock, ...)
                if not ok then
                    ngx.say(err)
                end
            end


            receiveany_say_err(0)
            receiveany_say_err(-1)
            receiveany_say_err()
            receiveany_say_err(nil)
        }
    }

--- response_body
bad argument #2 to '?' (bad max argument)
bad argument #2 to '?' (bad max argument)
expecting 2 arguments (including the object), but got 1
bad argument #2 to '?' (bad max argument)
--- request
GET /t
--- no_error_log
[error]



=== TEST 68: receiveany with limited, max is larger than data
--- config
    server_tokens off;
    location = /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(500)
            assert(sock:connect("127.0.0.1", ngx.var.port))
            local req = {
                'GET /foo HTTP/1.0\r\n',
                'Host: localhost\r\n',
                'Connection: close\r\n\r\n',
            }
            local ok, err = sock:send(req)
            if not ok then
                ngx.say("send request failed: ", err)
                return
            end

            while true do
                local data, err, _ = sock:receive('*l')
                if err then
                    ngx.say('unexpected error occurs when receiving http head: ', err)
                    return
                end

                if #data == 0 then -- read last line of head
                    break
                end
            end

            local data, err = sock:receiveany(128)
            if err then
                if err ~= 'closed' then
                    ngx.say('unexpected err: ', err)
                end
            else
                ngx.say(data)
            end

            sock:close()
        }
    }

    location = /foo {
        content_by_lua_block {
            local resp = 'hello world'
            local length = #resp

            ngx.header['Content-Length'] = length
            ngx.flush(true)
            ngx.sleep(0.01)

            ngx.print(resp)
        }
    }

--- request
GET /t
--- response_body
hello world
--- no_error_log
[error]
--- error_log
lua tcp socket calling receiveany() method to read at most 128 bytes



=== TEST 69: receiveany with limited, max is smaller than data
--- config
    server_tokens off;
    location = /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(500)
            assert(sock:connect("127.0.0.1", ngx.var.port))
            local req = {
                'GET /foo HTTP/1.0\r\n',
                'Host: localhost\r\n',
                'Connection: close\r\n\r\n',
            }
            local ok, err = sock:send(req)
            if not ok then
                ngx.say("send request failed: ", err)
                return
            end

            while true do
                local data, err, _ = sock:receive('*l')
                if err then
                    ngx.say('unexpected error occurs when receiving http head: ', err)
                    return
                end

                if #data == 0 then -- read last line of head
                    break
                end
            end

            while true do
                local data, err = sock:receiveany(7)
                if err then
                    if err ~= 'closed' then
                        ngx.say('unexpected err: ', err)
                    end
                    break

                else
                    ngx.say(data)
                end
            end

            sock:close()
        }
    }

    location = /foo {
        content_by_lua_block {
            local resp = 'hello world'
            local length = #resp

            ngx.header['Content-Length'] = length
            ngx.flush(true)
            ngx.sleep(0.01)

            ngx.print(resp)
        }
    }

--- request
GET /t
--- response_body
hello w
orld
--- no_error_log
[error]
--- error_log
lua tcp socket calling receiveany() method to read at most 7 bytes



=== TEST 70: send tables of string fragments (with floating point number too)
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = {"GET", " ", "/foo", " HTTP/", 1, ".", 0, "\r\n",
                         "Host: localhost\r\n", "Connection: close\r\n",
                         "Foo: ", 3.1415926, "\r\n",
                         "\r\n"}
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

    location /foo {
        content_by_lua_block {
            ngx.say(ngx.req.get_headers()["Foo"])
        }
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 73
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 10
received: Connection: close
received: 
received: 3.1415926
failed to receive a line: closed []
close: 1 nil
--- no_error_log
[error]



=== TEST 71: send numbers
the maximum number of significant digits is 14 in lua
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = {"GET", " ", "/foo", " HTTP/", 1, ".", 0, "\r\n",
                         "Host: localhost\r\n", "Connection: close\r\n",
                         "Foo: "}
            -- req = "OK"

            local total_bytes = 0;
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            total_bytes = total_bytes + bytes;

            bytes, err = sock:send(3.14159265357939723846)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            total_bytes = total_bytes + bytes;

            bytes, err = sock:send(31415926)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            total_bytes = total_bytes + bytes;

            bytes, err = sock:send("\r\n\r\n")
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            total_bytes = total_bytes + bytes;

            ngx.say("request sent: ", total_bytes)

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

    location /foo {
        content_by_lua_block {
            ngx.say(ngx.req.get_headers()["Foo"])
        }
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 87
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 24
received: Connection: close
received: 
received: 3.141592653579431415926
failed to receive a line: closed []
close: 1 nil
--- no_error_log
[error]



=== TEST 72: port is not number
--- config
    server_tokens off;
    location = /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(500)

            local ok, err = sock:connect("127.0.0.1")
            if not ok then
                ngx.say("connect failed: ", err)
            end

            local ok, err = sock:connect("127.0.0.1", nil)
            if not ok then
                ngx.say("connect failed: ", err)
            end

            local ok, err = sock:connect("127.0.0.1", {})
            if not ok then
                ngx.say("connect failed: ", err)
            end

            ngx.say("finish")
        }
    }

--- request
GET /t
--- response_body
connect failed: missing the port number
connect failed: missing the port number
connect failed: missing the port number
finish
--- no_error_log
[error]



=== TEST 73: reset the buffer pos when keepalive
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            for i = 1, 10
            do
                local sock = ngx.socket.tcp()
                local port = ngx.var.port
                local ok, err = sock:connect("127.0.0.1", port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                local req = "GET /hi HTTP/1.1\r\nHost: localhost\r\n\r\n"

                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send request: ", err)
                    return
                end

                local line, err, part = sock:receive()
                if not line then
                    ngx.say("receive err: ", err)
                    return
                end

                data, err = sock:receiveany(4096)
                if not data then
                    ngx.say("receiveany er: ", err)
                    return
                end

                ok, err = sock:setkeepalive(10000, 32)
                if not ok then
                    ngx.say("reused times: ", i, ", setkeepalive err: ", err)
                    return
                end
            end
            ngx.say("END")
        }
    }

    location /hi {
        keepalive_requests 3;
        content_by_lua_block {
            ngx.say("Hello")
        }

        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
reused times: 3, setkeepalive err: closed
--- no_error_log
[error]
--- skip_eval: 3: $ENV{TEST_NGINX_EVENT_TYPE} && $ENV{TEST_NGINX_EVENT_TYPE} ne 'epoll'
