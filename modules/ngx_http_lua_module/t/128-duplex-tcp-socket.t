# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 2);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: pipelined memcached requests (sent one byte at a time)
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

            local req = "flush_all\\r\\nget foo\\r\\nget bar\\r\\n"
            -- req = "OK"
            local send_idx = 1

            local function writer()
                local sub = string.sub
                while send_idx <= #req do
                    local bytes, err = sock:send(sub(req, send_idx, send_idx))
                    if not bytes then
                        ngx.say("failed to send request: ", err)
                        return
                    end
                    -- if send_idx % 2 == 0 then
                        ngx.sleep(0.001)
                    -- end
                    send_idx = send_idx + 1
                end
                -- ngx.say("request sent.")
            end

            local ok, err = ngx.thread.spawn(writer)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            for i = 1, 3 do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            ok, err = sock:setkeepalive()
            ngx.say("setkeepalive: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body
connected: 1
received: OK
received: END
received: END
setkeepalive: 1 nil

--- no_error_log
[error]



=== TEST 2: read timeout errors won't affect writing
--- config
    server_tokens off;
    lua_socket_log_errors off;
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
            -- req = "OK"
            local send_idx = 1

            sock:settimeout(1)

            local function writer()
                local sub = string.sub
                while send_idx <= #req do
                    local bytes, err = sock:send(sub(req, send_idx, send_idx))
                    if not bytes then
                        ngx.say("failed to send request: ", err)
                        return
                    end
                    ngx.sleep(0.001)
                    send_idx = send_idx + 1
                end
                -- ngx.say("request sent.")
            end

            local ok, err = ngx.thread.spawn(writer)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            local data = ""
            local ntm = 0
            local done = false
            for i = 1, 300 do
                local line, err, part = sock:receive()
                if not line then
                    if part then
                        data = data .. part
                    end
                    if err ~= "timeout" then
                        ngx.say("failed to receive: ", err)
                        return
                    end

                    ntm = ntm + 1

                else
                    data = data .. line
                    ngx.say("received: ", data)
                    done = true
                    break
                end
            end

            if not done then
                ngx.say("partial read: ", data)
            end

            ngx.say("read timed out: ", ntm)
            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body_like chop
^connected: 1
(?:received: OK|failed to send request: timeout
partial read: )
read timed out: [1-9]\d*
close: 1 nil$

--- no_error_log
[error]



=== TEST 3: writes are rejected while reads are not
--- config
    server_tokens off;
    lua_socket_log_errors off;
    location /t {
        #set $port 5000;
        set $port 7658;

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
            -- req = "OK"
            local send_idx = 1

            local function writer()
                local sub = string.sub
                while send_idx <= #req do
                    local bytes, err = sock:send(sub(req, send_idx, send_idx))
                    if not bytes then
                        ngx.say("failed to send request: ", err)
                        return
                    end
                    ngx.sleep(0.001)
                    send_idx = send_idx + 1
                end
                -- ngx.say("request sent.")
            end

            local ok, err = ngx.thread.spawn(writer)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            local data = ""
            local ntm = 0
            local done = false
            for i = 1, 3 do
                local res, err, part = sock:receive(1)
                if not res then
                    ngx.say("failed to receive: ", err)
                    return
                else
                    data = data .. res
                end
                ngx.sleep(0.001)
            end

            ngx.say("received: ", data)
            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body_like chop
^connected: 1
received: OK!
close: (?:nil socket busy writing|1 nil
failed to send request: closed)$

--- tcp_listen: 7658
--- tcp_shutdown: 0
--- tcp_reply: OK!
--- tcp_no_close: 1
--- no_error_log
[error]



=== TEST 4: reads are rejected while writes are not
--- config
    server_tokens off;
    lua_socket_log_errors off;
    location /t {
        #set $port 5000;
        set $port 7658;

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
            -- req = "OK"
            local send_idx = 1

            local function writer()
                local sub = string.sub
                while send_idx <= #req do
                    local bytes, err = sock:send(sub(req, send_idx, send_idx))
                    if not bytes then
                        ngx.say("failed to send request: ", err)
                        return
                    end
                    -- ngx.say("sent: ", bytes)
                    ngx.sleep(0.001)
                    send_idx = send_idx + 1
                end
                ngx.say("request sent.")
                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end

            local ok, err = ngx.thread.spawn(writer)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            local data = ""
            local ntm = 0
            local aborted = false
            for i = 1, 3 do
                if not aborted then
                    local res, err, part = sock:receive(1)
                    if not res then
                        ngx.say("failed to receive: ", err)
                        aborted = true
                    else
                        data = data .. res
                    end
                end

                ngx.sleep(0.001)
            end

            if not aborted then
                ngx.say("received: ", data)
            end
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to receive: closed
request sent.
close: 1 nil

--- stap2
F(ngx_http_lua_socket_tcp_finalize_write_part) {
    print_ubacktrace()
}
--- stap_out2
--- tcp_listen: 7658
--- tcp_shutdown: 1
--- tcp_query eval: "flush_all\r\n"
--- tcp_query_len: 11
--- no_error_log
[error]
--- wait: 0.05



=== TEST 5: concurrent socket operations while connecting
--- config
    server_tokens off;
    lua_socket_log_errors off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()

            local function f()
                ngx.sleep(0.001)
                local res, err = sock:receive(1)
                ngx.say("receive: ", res, " ", err)

                local bytes, err = sock:send("hello")
                ngx.say("send: ", bytes, " ", err)

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)

                local ok, err = sock:getreusedtimes()
                ngx.say("getreusedtimes: ", ok, " ", err)

                local ok, err = sock:setkeepalive()
                ngx.say("setkeepalive: ", ok, " ", err)

                local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
                ngx.say("connect: ", ok, " ", err)
            end

            local ok, err = ngx.thread.spawn(f)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            sock:settimeout(300)
            local ok, err = sock:connect("172.105.207.225", 12345)
            ngx.say("connect: ", ok, " ", err)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body
receive: nil socket busy connecting
send: nil socket busy connecting
close: nil socket busy connecting
getreusedtimes: 0 nil
setkeepalive: nil socket busy connecting
connect: nil socket busy connecting
connect: nil timeout
close: nil closed

--- no_error_log
[error]



=== TEST 6: concurrent operations while resolving
--- config
    server_tokens off;
    lua_socket_log_errors off;
    resolver agentzh.org:12345;
    resolver_timeout 300ms;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()

            local function f()
                ngx.sleep(0.001)
                local res, err = sock:receive(1)
                ngx.say("receive: ", res, " ", err)

                local bytes, err = sock:send("hello")
                ngx.say("send: ", bytes, " ", err)

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)

                local ok, err = sock:getreusedtimes()
                ngx.say("getreusedtimes: ", ok, " ", err)

                local ok, err = sock:setkeepalive()
                ngx.say("setkeepalive: ", ok, " ", err)

                local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
                ngx.say("connect: ", ok, " ", err)
            end

            local ok, err = ngx.thread.spawn(f)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            sock:settimeout(300)
            local ok, err = sock:connect("some2.agentzh.org", 12345)
            ngx.say("connect: ", ok, " ", err)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body
receive: nil closed
send: nil closed
close: nil closed
getreusedtimes: nil closed
setkeepalive: nil closed
connect: nil socket busy connecting
connect: nil some2.agentzh.org could not be resolved (110: Operation timed out)
close: nil closed

--- no_error_log
[error]



=== TEST 7: concurrent operations while reading (receive)
--- config
    server_tokens off;
    lua_socket_log_errors off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ready = false

            local function f()
                while not ready do
                    ngx.sleep(0.001)
                end

                local res, err = sock:receive(1)
                ngx.say("receive: ", res, " ", err)

                local bytes, err = sock:send("flush_all")
                ngx.say("send: ", bytes, " ", err)

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)

                local ok, err = sock:getreusedtimes()
                ngx.say("getreusedtimes: ", ok, " ", err)

                local ok, err = sock:setkeepalive()
                ngx.say("setkeepalive: ", ok, " ", err)

                local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
                ngx.say("connect: ", ok, " ", err)
            end

            local ok, err = ngx.thread.spawn(f)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            sock:settimeout(300)
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            ngx.say("connect: ", ok, " ", err)

            ready = true

            local res, err = sock:receive(1)
            ngx.say("receive: ", res, " ", err)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body
connect: 1 nil
receive: nil socket busy reading
send: 9 nil
close: nil socket busy reading
getreusedtimes: 0 nil
setkeepalive: nil socket busy reading
connect: nil socket busy reading
receive: nil timeout
close: 1 nil

--- no_error_log
[error]



=== TEST 8: concurrent operations while reading (receiveuntil)
--- config
    server_tokens off;
    lua_socket_log_errors off;
    location /t {
        content_by_lua '
            local ready = false
            local sock = ngx.socket.tcp()

            local function f()
                while not ready do
                    ngx.sleep(0.001)
                end

                local res, err = sock:receive(1)
                ngx.say("receive: ", res, " ", err)

                local bytes, err = sock:send("flush_all")
                ngx.say("send: ", bytes, " ", err)

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)

                local ok, err = sock:getreusedtimes()
                ngx.say("getreusedtimes: ", ok, " ", err)

                local ok, err = sock:setkeepalive()
                ngx.say("setkeepalive: ", ok, " ", err)

                local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
                ngx.say("connect: ", ok, " ", err)
            end

            local ok, err = ngx.thread.spawn(f)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            sock:settimeout(300)
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            ngx.say("connect: ", ok, " ", err)

            ready = true

            local it, err = sock:receiveuntil("\\r\\n")
            if not it then
                ngx.say("receiveuntil() failed: ", err)
                return
            end

            local res, err = it()
            ngx.say("receiveuntil() iterator: ", res, " ", err)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body
connect: 1 nil
receive: nil socket busy reading
send: 9 nil
close: nil socket busy reading
getreusedtimes: 0 nil
setkeepalive: nil socket busy reading
connect: nil socket busy reading
receiveuntil() iterator: nil timeout
close: 1 nil

--- no_error_log
[error]
