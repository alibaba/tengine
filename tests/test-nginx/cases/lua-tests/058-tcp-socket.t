# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 95;

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

#no_long_string();
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
close: nil closed
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
    resolver $TEST_NGINX_RESOLVER;
    resolver_timeout 1s;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = 80
            local ok, err = sock:connect("direct.agentzh.org", port)
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
--- response_body
connected: 1
request sent: 56
first line received: HTTP/1.1 200 OK
second line received: Server: ngx_openresty
--- no_error_log
[error]



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
    resolver $TEST_NGINX_RESOLVER;
    lua_socket_connect_timeout 100ms;
    lua_socket_send_timeout 100ms;
    lua_socket_read_timeout 100ms;
    resolver_timeout 1s;
    location /test {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("agentzh.org", 12345)
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
lua tcp socket connect timed out



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
    resolver $TEST_NGINX_RESOLVER;
    resolver_timeout 1s;
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
--- timeout: 5



=== TEST 9: resolver error (timeout)
--- config
    server_tokens off;
    resolver 8.8.8.8;
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
^failed to connect: blah-blah-not-found\.agentzh\.org could not be resolved(?: \(\d+: Operation timed out\))?
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
close: nil closed
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
close: nil closed
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
close: nil closed
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
close: nil closed
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
close: nil closed
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
close: nil closed
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
close: nil closed
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

            ok, err = sock:close()
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
close: nil closed
"
--- no_error_log
[error]



=== TEST 19: cannot survive across request boundary (send)
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
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
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
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
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
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
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
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



=== TEST 25: send tables of string fragments
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
close: nil closed
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



=== TEST 33: github issue #215: Handle the posted requests in lua cosocket api (failed to resolve)
--- config
    resolver 8.8.8.8;

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
    resolver 8.8.8.8;

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
                ngx.say("failed to connect to agentzh.org: ", err)
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

F(ngx_http_lua_socket_tcp_connect_retval_handler) {
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

