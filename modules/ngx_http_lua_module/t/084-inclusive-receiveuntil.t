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

=== TEST 1: ambiguous boundary patterns (abcabd) - inclusive mode
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

            local reader = sock:receiveuntil("abcabd", { inclusive = true })

            for i = 1, 3 do
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
        echo abcabcabdabcabd;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abcabcabd
read: abcabd
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 2: ambiguous boundary patterns (abcabdabcabe 4) - inclusive mode
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

            local reader = sock:receiveuntil("abcabdabcabe", { inclusive = true })

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
read: ababcabdabcabe
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 3: ambiguous boundary patterns (abcabd) - inclusive mode - small buffers
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

            local reader = sock:receiveuntil("abcabd", { inclusive = true })

            for i = 1, 3 do
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
        echo abcabcabdabcabd;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abcabcabd
read: abcabd
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 4: inclusive option value nil
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

            local reader = sock:receiveuntil("aa", { inclusive = nil })

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
        echo abcabcaad;
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



=== TEST 5: inclusive option value false
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

            local reader = sock:receiveuntil("aa", { inclusive = false })

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
        echo abcabcaad;
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



=== TEST 6: inclusive option value true (aa)
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

            local reader = sock:receiveuntil("aa", { inclusive = true })

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
        echo abcabcaad;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: abcabcaa
failed to read a line: closed [d
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 7: bad inclusive option value type
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

            local reader = sock:receiveuntil("aa", { inclusive = "true" })

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
        echo abcabcaad;
        more_clear_headers Date;
    }
--- request
GET /t
--- ignore_response
--- error_log
bad "inclusive" option value type: string
--- no_error_log
[alert]
[warn]



=== TEST 8: bad option table
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

            local reader = sock:receiveuntil("aa", { inclusive = "true" })

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
        echo abcabcaad;
        more_clear_headers Date;
    }
--- request
GET /t
--- ignore_response
--- error_log
bad "inclusive" option value type: string
--- no_error_log
[alert]
[warn]



=== TEST 9: ambiguous boundary patterns (--abc), small buffer
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

            local reader = sock:receiveuntil("--abc", { inclusive = true })

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
read:  ----abc
failed to read a line: nil [nil]
failed to read a line: closed [
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 10: ambiguous boundary patterns (--abc), small buffer, mixed by other reading calls
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

            local reader = sock:receiveuntil("--abc", { inclusive = true })

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
read: --abc
read one byte: 

failed to read a chunk: nil [nil]
failed to read a byte: closed []
close: 1 nil
}
--- no_error_log
[error]
