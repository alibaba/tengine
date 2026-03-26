# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

no_long_string();
#no_diff();
#log_level 'warn';

run_tests();

__DATA__

=== TEST 1: memcached read lines
--- config
    server_tokens off;
    location /t {
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

            local readline = sock:receiveuntil("\\r\\n")
            local line, err, part = readline()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive a line: ", err, " [", part, "]")
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
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



=== TEST 2: http read lines
--- no_http2
--- config
    server_tokens off;
    location /t {
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

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local readline = sock:receiveuntil("\\r\\n")
            local line, err, part

            for i = 1, 7 do
                line, err, part = readline()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
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
qq{connected: 1
request sent: 57
read: HTTP/1.1 200 OK
read: Server: nginx
read: Content-Type: text/plain
read: Content-Length: 4
read: Connection: close
read: 
failed to read a line: closed [foo
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 3: http read all the headers in a single run
--- no_http2
--- config
    server_tokens off;
    location /t {
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

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local line, err, part

            for i = 1, 2 do
                line, err, part = read_headers()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
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
qq{connected: 1
request sent: 57
read: HTTP/1.1 200 OK\r
Server: nginx\r
Content-Type: text/plain\r
Content-Length: 4\r
Connection: close
failed to read a line: closed [foo
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 4: ambiguous boundary patterns (abcabd)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("abcabd")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("abcabcabd")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abc
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 5: ambiguous boundary patterns (aa)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("aa")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        content_by_lua 'ngx.say("abcabcaad")';
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abcabc
failed to read a line: closed [d
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 6: ambiguous boundary patterns (aaa)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("aaa")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo abaabcaaaef;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abaabc
failed to read a line: closed [ef
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 7: ambiguous boundary patterns (aaaaad)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("aaaaad")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo baaaaaaaaeaaaaaaadf;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: baaaaaaaaeaa
failed to read a line: closed [f
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 8: ambiguous boundary patterns (aaaaad), small buffer, 2 bytes
--- no_http2
--- config
    server_tokens off;
    lua_socket_buffer_size 2;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("aaaaad")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo baaaaaaaaeaaaaaaadf;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: baaaaaaaaeaa
failed to read a line: closed [f
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 9: ambiguous boundary patterns (aaaaad), small buffer, 1 byte
--- no_http2
--- config
    server_tokens off;
    lua_socket_buffer_size 1;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("aaaaad")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo baaaaaaaaeaaaaaaadf;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: baaaaaaaaeaa
failed to read a line: closed [f
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 10: ambiguous boundary patterns (abcabdabcabe)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("abcabdabcabe")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo abcabdabcabdabcabe;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abcabd
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 11: ambiguous boundary patterns (abcabdabcabe 2)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("abcabdabcabe")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo abcabdabcabcabdabcabe;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abcabdabc
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 12: ambiguous boundary patterns (abcabdabcabe 3)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("abcabdabcabe")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo abcabcabdabcabe;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abc
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 13: ambiguous boundary patterns (abcabdabcabe 4)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("abcabdabcabe")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo ababcabdabcabe;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: ab
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 14: ambiguous boundary patterns (--abc)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("--abc")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo -- ----abc;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: --
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 15: ambiguous boundary patterns (--abc)
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("--abc")

            for i = 1, 6 do
                local line, err, part = reader(4)
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo "hello, world ----abc";
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: hell
read: o, w
read: orld
read:  --
failed to read a line: nil [nil]
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 16: ambiguous boundary patterns (--abc), small buffer
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_buffer_size 1;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("--abc")

            for i = 1, 6 do
                local line, err, part = reader(4)
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo "hello, world ----abc";
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: hell
read: o, w
read: orld
read:  --
failed to read a line: nil [nil]
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 17: ambiguous boundary patterns (--abc), small buffer, mixed by other reading calls
--- no_http2
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_buffer_size 1;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("--abc")

            for i = 1, 7 do
                local line, err, part = reader(4)
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a chunk: ", err, " [", part, "]")
                end

                local data, err, part = sock:receive(1)
                if not data then
                    ngx.say("failed to read a byte: ", err, " [", part, "]")
                    break
                else
                    ngx.say("read one byte: ", data)
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo "hello, world ----abc";
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: hell
read one byte: o
read: , wo
read one byte: r
read: ld -
read one byte: -
read: 
read one byte: 

failed to read a chunk: nil [nil]
failed to read a byte: closed []
close: 1 nil
}
--- no_error_log
[error]



=== TEST 18: ambiguous boundary patterns (abcabd), small buffer
--- no_http2
--- config
    server_tokens off;
    lua_socket_buffer_size 3;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("abcabd")

            for i = 1, 2 do
                local line, err, part = reader()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo abcabcabd;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abc
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 19: long patterns
this exposed a memory leak in receiveuntil
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.req.socket()
            if not sock then
                ngx.say("failed to get req socket: ", err)
                return
            end
            local reader, err = sock:receiveuntil("------------------------------------------- abcdefghijklmnopqrstuvwxyz")
            if not reader then
                ngx.say("failed to get reader: ", err)
                return
            end
            ngx.say("ok")
        ';
    }
--- request
    POST /t

--- more_headers: Content-Length: 1024
--- response_body
ok
--- no_error_log
[error]
--- skip_eval: 3:$ENV{TEST_NGINX_USE_HTTP3}



=== TEST 20: add pending bytes
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_buffer_size 1;

        content_by_lua '
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("--abc")

            for i = 1, 4 do
                local line, err, part = reader(2)
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo -- -----abc;
        more_clear_headers Date;
    }
--- request
GET /t

--- response_body eval
qq{connected: 1
request sent: 57
read: --
read: -
failed to read a line: nil [nil]
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 21: ambiguous boundary patterns (--abc), mixed by other reading calls consume boundary
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\r\n\r\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("--abc")

            for i = 1, 5 do
                local line, err, part = reader(2)
                if not line then
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                    break

                else
                    ngx.say("read: ", line)
                end

                local data, err, part = sock:receive(1)
                if not data then
                    ngx.say("failed to read a byte: ", err, " [", part, "]")
                    break

                else
                    ngx.say("read one byte: ", data)
                end
            end

            local line, err, part = reader(2)
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

    location /foo {
        echo -- ----abc----abc-;
        more_clear_headers Date;
    }
--- request
GET /t

--- response_body eval
qq{connected: 1
request sent: 57
read: --
read one byte: -
read: -a
read one byte: b
read: c-
read one byte: -
read: 
read one byte: -
failed to read a line: nil [nil]
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 22: ambiguous boundary patterns (--abc), mixed by other reading calls (including receiveuntil) consume boundary
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\r\n\r\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader1 = sock:receiveuntil("--abc")
            local reader2 = sock:receiveuntil("-ab")

            local line, err, part = reader1(2)
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            local data, err, part = sock:receive(1)
            if not data then
                ngx.say("failed to read a byte: ", err, " [", part, "]")

            else
                ngx.say("read one byte: ", data)
            end

            local line, err, part = reader1(1)
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            local line, err, part = reader2(2)
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            local line, err, part = reader1()
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            local line, err, part = reader1()
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

    location /foo {
        echo -- ------abd----abc;
        more_clear_headers Date;
    }
--- request
GET /t

--- response_body eval
qq{connected: 1
request sent: 57
read: --
read one byte: -
read: -
read: -
read: d--
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 23: ambiguous boundary patterns (--abc), mixed by other reading calls consume boundary, small buffer
--- config
    lua_socket_buffer_size 3;
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\r\n\r\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader = sock:receiveuntil("--abc")

            for i = 1, 5 do
                local line, err, part = reader(2)
                if not line then
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                    break

                else
                    ngx.say("read: ", line)
                end

                local data, err, part = sock:receive(1)
                if not data then
                    ngx.say("failed to read a byte: ", err, " [", part, "]")
                    break

                else
                    ngx.say("read one byte: ", data)
                end
            end

            local line, err, part = reader(2)
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

    location /foo {
        echo -- ----abc----abc-;
        more_clear_headers Date;
    }
--- request
GET /t

--- response_body eval
qq{connected: 1
request sent: 57
read: --
read one byte: -
read: -a
read one byte: b
read: c-
read one byte: -
read: 
read one byte: -
failed to read a line: nil [nil]
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 24: ambiguous boundary patterns (--abc), mixed by other reading calls (including receiveuntil) consume boundary, small buffer
--- config
    lua_socket_buffer_size 3;
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\r\n\r\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            local reader1 = sock:receiveuntil("--abc")
            local reader2 = sock:receiveuntil("-ab")

            local line, err, part = reader1(2)
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            local data, err, part = sock:receive(1)
            if not data then
                ngx.say("failed to read a byte: ", err, " [", part, "]")

            else
                ngx.say("read one byte: ", data)
            end

            local line, err, part = reader1(1)
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            local line, err, part = reader2(2)
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            local line, err, part = reader1()
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            local line, err, part = reader1()
            if not line then
                ngx.say("failed to read a line: ", err, " [", part, "]")

            else
                ngx.say("read: ", line)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

    location /foo {
        echo -- ------abd----abc;
        more_clear_headers Date;
    }
--- request
GET /t

--- response_body eval
qq{connected: 1
request sent: 57
read: --
read one byte: -
read: -
read: -
read: d--
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 25: ambiguous boundary patterns (ab1ab2), ends half way
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\r\n\r\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            if true then
                local reader = sock:receiveuntil("ab1ab2")

                local line, err, part = reader(2)
                if not line then
                    ngx.say("failed to read a line: ", err, " [", part, "]")

                else
                    ngx.say("read: ", line)
                end
            end

            collectgarbage("collect")

            local data, err, part = sock:receive(3)
            if not data then
                ngx.say("failed to read three bytes: ", err, " [", part, "]")

            else
                ngx.say("read three bytes: ", data)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

    location /foo {
        echo -- ab1ab1;
        more_clear_headers Date;
    }
--- request
GET /t

--- response_body eval
qq{connected: 1
request sent: 57
read: ab1
read three bytes: ab1
close: 1 nil
}
--- no_error_log
[error]



=== TEST 26: ambiguous boundary patterns (ab1ab2), ends half way, small buffer
--- config
    lua_socket_buffer_size 3;
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            -- collectgarbage("collect")

            local sock = ngx.socket.tcp()
            local port = ngx.var.port

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

            local read_headers = sock:receiveuntil("\r\n\r\n")
            local headers, err, part = read_headers()
            if not headers then
                ngx.say("failed to read headers: ", err, " [", part, "]")
            end

            if true then
                local reader = sock:receiveuntil("ab1ab2")

                local line, err, part = reader(2)
                if not line then
                    ngx.say("failed to read a line: ", err, " [", part, "]")

                else
                    ngx.say("read: ", line)
                end
            end

            collectgarbage("collect")

            local data, err, part = sock:receive(3)
            if not data then
                ngx.say("failed to read three bytes: ", err, " [", part, "]")

            else
                ngx.say("read three bytes: ", data)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

    location /foo {
        echo -- ab1ab1;
        more_clear_headers Date;
    }
--- request
GET /t

--- response_body eval
qq{connected: 1
request sent: 57
read: ab1
read three bytes: ab1
close: 1 nil
}
--- no_error_log
[error]
--- skip_eval: 3:$ENV{TEST_NGINX_USE_HTTP3}
