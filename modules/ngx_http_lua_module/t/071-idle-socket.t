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

=== TEST 1: read events come when socket is idle
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

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("foofoo\\r\\n")
            local line, err, part = reader()
            if line then
                ngx.print("read: ", line)

            else
                ngx.say("failed to read a line: ", err, " [", part, "]")
            end

            ngx.location.capture("/sleep")

            local data, err, part = sock:receive("*a")
            if not data then
                ngx.say("failed to read the 2nd part: ", err)
            else
                ngx.say("2nd part: [", data, "]")
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /sleep {
        echo_sleep 0.5;
        more_clear_headers Date;
    }

    location /foo {
        echo -n foofoo;
        echo_flush;
        echo_sleep 0.3;
        echo -n barbar;
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
Transfer-Encoding: chunked\r
Connection: close\r
\r
6\r
2nd part: [6\r
barbar\r
0\r
\r
]
close: 1 nil
}
--- no_error_log
[error]



=== TEST 2: read timer cleared in time
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            sock:settimeout(400)

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

            ngx.location.capture("/sleep")

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent again: ", bytes)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /sleep {
        echo_sleep 0.5;
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 11
received: OK
request sent again: 11
close: 1 nil
--- no_error_log
[error]



=== TEST 3: connect timer cleared in time
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            sock:settimeout(300)

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            ngx.location.capture("/sleep")

            local req = "flush_all\\r\\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /sleep {
        echo_sleep 0.5;
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 11
close: 1 nil
--- no_error_log
[error]



=== TEST 4: send timer cleared in time
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            sock:settimeout(300)

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

            ngx.location.capture("/sleep")

            local line, err, part = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive a line: ", err, " [", part, "]")
                return
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /sleep {
        echo_sleep 0.5;
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
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



=== TEST 5: set keepalive when system socket recv buffer has unread data
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

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("foofoo\\r\\n")
            local line, err, part = reader()
            if line then
                ngx.print("read: ", line)

            else
                ngx.say("failed to read a line: ", err, " [", part, "]")
            end

            ngx.location.capture("/sleep")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
            end
        ';
    }

    location /sleep {
        echo_sleep 0.5;
        more_clear_headers Date;
    }

    location /foo {
        echo -n foofoo;
        echo_flush;
        echo_sleep 0.3;
        echo -n barbar;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body_like eval
qr{connected: 1
request sent: 57
read: HTTP/1\.1 200 OK\r
Server: nginx\r
Content-Type: text/plain\r
Transfer-Encoding: chunked\r
Connection: close\r
\r
6\r
failed to set keepalive: (?:unread data in buffer|closed|connection in dubious state)
}
--- no_error_log
[error]



=== TEST 6: set keepalive when cosocket recv buffer has unread data
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

            local data, err = sock:receive(1)
            if not data then
                ngx.say("failed to read the 1st byte: ", err)
                return
            end

            ngx.say("read: ", data)

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
            end
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 11
read: O
failed to set keepalive: unread data in buffer
}
--- no_error_log
[error]
