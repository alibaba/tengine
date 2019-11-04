# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    if ($ENV{MOCKEAGAIN} eq 'r') {
        $ENV{MOCKEAGAIN} = 'rw';

    } else {
        $ENV{MOCKEAGAIN} = 'w';
    }

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'get helloworld';
}

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 6);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

log_level("debug");
no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: lua_socket_connect_timeout only
--- config
    server_tokens off;
    lua_socket_connect_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- error_log
lua tcp socket connect timeout: 100
lua tcp socket connect timed out, when connecting to 127.0.0.2:12345
--- timeout: 10



=== TEST 2: sock:settimeout() overrides lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 60s;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(150)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- error_log
lua tcp socket connect timeout: 150
lua tcp socket connect timed out, when connecting to 127.0.0.2:12345
--- timeout: 10



=== TEST 3: sock:settimeout(nil) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(nil)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- error_log
lua tcp socket connect timeout: 102
lua tcp socket connect timed out, when connecting to 127.0.0.2:12345



=== TEST 4: sock:settimeout(0) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(0)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- error_log
lua tcp socket connect timeout: 102
lua tcp socket connect timed out, when connecting to 127.0.0.2:12345
--- timeout: 10



=== TEST 5: -1 is bad timeout value
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(-1)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body_like chomp
500 Internal Server Error
--- error_log
bad timeout value
--- error_code: 500



=== TEST 6: lua_socket_read_timeout only
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
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua tcp socket read timeout: 100
lua tcp socket connect timeout: 60000
lua tcp socket read timed out



=== TEST 7: sock:settimeout() overrides lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 60s;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(150)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket read timeout: 150
lua tcp socket read timed out



=== TEST 8: sock:settimeout(nil) does not override lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(nil)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket read timeout: 102
lua tcp socket read timed out



=== TEST 9: sock:settimeout(0) does not override lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(0)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end

        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket read timeout: 102
lua tcp socket read timed out



=== TEST 10: -1 is bad timeout value
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            sock:settimeout(-1)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body_like chomp
500 Internal Server Error
--- error_code: 500
--- error_log
bad timeout value



=== TEST 11: lua_socket_send_timeout only
--- config
    server_tokens off;
    lua_socket_send_timeout 100ms;
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

            local bytes
            bytes, err = sock:send("get helloworld!")
            if bytes then
                ngx.say("sent: ", bytes)
            else
                ngx.say("failed to send: ", err)
            end
        ';
    }
--- request
GET /t
--- stap2
global active = 0
F(ngx_http_lua_socket_send) {
    active = 1
    println(probefunc())
}
probe syscall.send,
    syscall.sendto,
    syscall.writev
{
    if (active && pid() == target()) {
        println(probefunc())
    }
}
--- response_body
connected: 1
failed to send: timeout
--- error_log
lua tcp socket send timeout: 100
lua tcp socket connect timeout: 60000
lua tcp socket write timed out



=== TEST 12: sock:settimeout() overrides lua_socket_send_timeout
--- config
    server_tokens off;
    lua_socket_send_timeout 60s;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(150)

            local bytes
            bytes, err = sock:send("get helloworld!")
            if bytes then
                ngx.say("sent: ", bytes)
            else
                ngx.say("failed to send: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to send: timeout
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 150
lua tcp socket write timed out



=== TEST 13: sock:settimeout(nil) does not override lua_socket_send_timeout
--- config
    server_tokens off;
    lua_socket_send_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(nil)

            local bytes
            bytes, err = sock:send("get helloworld!")
            if bytes then
                ngx.say("sent: ", bytes)
            else
                ngx.say("failed to send: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to send: timeout
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 102
lua tcp socket write timed out



=== TEST 14: sock:settimeout(0) does not override lua_socket_send_timeout
--- config
    server_tokens off;
    lua_socket_send_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(0)

            local bytes
            bytes, err = sock:send("get helloworld!")
            if bytes then
                ngx.say("sent: ", bytes)
            else
                ngx.say("failed to send: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to send: timeout
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 102
lua tcp socket write timed out



=== TEST 15: sock:settimeout(-1) does not override lua_socket_send_timeout
--- config
    server_tokens off;
    lua_socket_send_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            sock:settimeout(-1)

            local bytes
            bytes, err = sock:send("get helloworld!")
            if bytes then
                ngx.say("sent: ", bytes)
            else
                ngx.say("failed to send: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body_like chomp
500 Internal Server Error
--- error_log
bad timeout value
--- error_code: 500



=== TEST 16: exit in user thread (entry thread is still pending on tcpsock:send)
--- config
    location /lua {
        content_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            sock:settimeout(12000)

            local bytes, ok = sock:send("get helloworld!")
            if not bytes then
                ngx.say("failed to send: ", err)
                return
            end

            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_coctx_cleanup) {
    println("lua tcp socket cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 12000
expire timer 100
terminate 2: ok
delete thread 2
lua tcp socket cleanup
delete timer 12000
delete thread 1
free request

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 17: re-connect after timed out
--- config
    server_tokens off;
    lua_socket_connect_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("1: failed to connect: ", err)

                local ok, err = sock:connect("127.0.0.1", ngx.var.server_port)
                if not ok then
                    ngx.say("2: failed to connect: ", err)
                    return
                end

                ngx.say("2: connected: ", ok)
                return
            end

            ngx.say("1: connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
1: failed to connect: timeout
2: connected: 1
--- error_log
lua tcp socket connect timeout: 100
lua tcp socket connect timed out, when connecting to 127.0.0.2:12345
--- timeout: 10



=== TEST 18: re-send on the same object after a send timeout happens
--- config
    server_tokens off;
    lua_socket_send_timeout 100ms;
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

            local bytes
            bytes, err = sock:send("get helloworld!")
            if bytes then
                ngx.say("sent: ", bytes)
            else
                ngx.say("failed to send: ", err)
                bytes, err = sock:send("blah")
                if not bytes then
                    ngx.say("failed to send again: ", err)
                end
            end
        ';
    }
--- request
GET /t
--- stap2
global active = 0
F(ngx_http_lua_socket_send) {
    active = 1
    println(probefunc())
}
probe syscall.send,
    syscall.sendto,
    syscall.writev
{
    if (active && pid() == target()) {
        println(probefunc())
    }
}
--- response_body
connected: 1
failed to send: timeout
failed to send again: closed
--- error_log
lua tcp socket send timeout: 100
lua tcp socket connect timeout: 60000
lua tcp socket write timed out



=== TEST 19: abort when upstream sockets pending on writes
--- config
    server_tokens off;
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

            sock:settimeout(100)
            ngx.thread.spawn(function () ngx.sleep(0.001) ngx.say("done") ngx.exit(200) end)
            local bytes
            bytes, err = sock:send("get helloworld!")
            if bytes then
                ngx.say("sent: ", bytes)
            else
                ngx.say("failed to send: ", err)
            end
        ';
    }
--- request
GET /t
--- stap2
global active = 0
F(ngx_http_lua_socket_send) {
    active = 1
    println(probefunc())
}
probe syscall.send,
    syscall.sendto,
    syscall.writev
{
    if (active && pid() == target()) {
        println(probefunc())
    }
}
--- response_body
connected: 1
done
--- error_log
lua tcp socket send timeout: 100
lua tcp socket connect timeout: 60000
--- no_error_log
lua tcp socket write timed out



=== TEST 20: abort when downstream socket pending on writes
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua '
            ngx.send_headers()
            ngx.flush(true)
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.say("failed to acquire the req socket: ", err)
                return
            end

            sock:settimeout(100)
            ngx.thread.spawn(function ()
                ngx.sleep(0.001)
                ngx.log(ngx.WARN, "quitting request now")
                ngx.exit(200)
            end)
            local bytes
            bytes, err = sock:send("e\\r\\nget helloworld!")
            if bytes then
                ngx.say("sent: ", bytes)
            else
                ngx.say("failed to send: ", err)
            end
        ';
    }
--- request
GET /t
--- stap2
global active = 0
F(ngx_http_lua_socket_send) {
    active = 1
    println(probefunc())
}
probe syscall.send,
    syscall.sendto,
    syscall.writev
{
    if (active && pid() == target()) {
        println(probefunc())
    }
}
--- ignore_response
--- error_log
lua tcp socket send timeout: 100
quitting request now
--- no_error_log
lua tcp socket write timed out
[alert]



=== TEST 21: read timeout on receive(N)
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

            sock:settimeout(10)

            local line
            line, err = sock:receive(3)
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua tcp socket read timeout: 10
lua tcp socket connect timeout: 60000
lua tcp socket read timed out



=== TEST 22: concurrent operations while writing
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

                sock:settimeout(1)
                local res, err = sock:receive(1)
                ngx.say("receive: ", res, " ", err)
            end

            local ok, err = ngx.thread.spawn(f)
            if not ok then
                ngx.say("failed to spawn writer thread: ", err)
                return
            end

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            ngx.say("connect: ", ok, " ", err)

            ready = true

            sock:settimeout(300)
            local bytes, err = sock:send("get helloworld!")
            if not bytes then
                ngx.say("send failed: ", err)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

--- request
GET /t
--- response_body
connect: 1 nil
send: nil socket busy writing
close: nil socket busy writing
getreusedtimes: 0 nil
setkeepalive: nil socket busy writing
connect: nil socket busy writing
receive: nil timeout
send failed: timeout
close: 1 nil

--- no_error_log
[error]



=== TEST 23: timeout overflow detection
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local ok, err = pcall(sock.settimeout, sock, (2 ^ 31) - 1)
            if not ok then
                ngx.say("failed to set timeout: ", err)
            else
                ngx.say("settimeout: ok")
            end

            ok, err = pcall(sock.settimeout, sock, 2 ^ 31)
            if not ok then
                ngx.say("failed to set timeout: ", err)
            else
                ngx.say("settimeout: ok")
            end
        }
    }
--- request
GET /t
--- response_body_like
settimeout: ok
failed to set timeout: bad timeout value
--- no_error_log
[error]
