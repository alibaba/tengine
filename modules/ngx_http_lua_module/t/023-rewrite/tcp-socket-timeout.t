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

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 8);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

no_long_string();
no_diff();
run_tests();

__DATA__

=== TEST 1: lua_socket_connect_timeout only
--- config
    server_tokens off;
    lua_socket_connect_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t1 {
        rewrite_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';

        content_by_lua return;
    }
--- request
GET /t1
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
    lua_socket_log_errors off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t2 {
        rewrite_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(150)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';

        content_by_lua return;
    }
--- request
GET /t2
--- response_body
failed to connect: timeout
--- error_log
lua tcp socket connect timeout: 150
--- no_error_log
[error]
[alert]
--- timeout: 10



=== TEST 3: sock:settimeout(nil) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_log_errors off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    #resolver_timeout 3s;
    location /t3 {
        rewrite_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(nil)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';

        content_by_lua return;
    }
--- request
GET /t3
--- response_body
failed to connect: timeout
--- error_log
lua tcp socket connect timeout: 102
--- no_error_log
[error]
[alert]
--- timeout: 5



=== TEST 4: sock:settimeout(0) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    lua_socket_log_errors off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t4 {
        rewrite_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(0)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';

        content_by_lua return;
    }
--- request
GET /t4
--- response_body
failed to connect: timeout
--- error_log
lua tcp socket connect timeout: 102
--- timeout: 5
--- no_error_log
[error]
[alert]
--- timeout: 10



=== TEST 5: -1 is bad timeout value
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    lua_socket_log_errors off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t5 {
        rewrite_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(-1)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';

        content_by_lua return;
    }
--- request
GET /t5
--- response_body_like chomp
500 Internal Server Error
--- error_log
bad timeout value
--- timeout: 10
--- error_code: 500



=== TEST 6: lua_socket_read_timeout only
--- config
    server_tokens off;
    lua_socket_read_timeout 100ms;
    location /t {
        rewrite_by_lua '
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

        content_by_lua return;
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
        rewrite_by_lua '
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

        content_by_lua return;
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
        rewrite_by_lua '
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

        content_by_lua return;
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
        rewrite_by_lua '
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

        content_by_lua return;
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
        rewrite_by_lua '
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

        content_by_lua return;
    }
--- request
GET /t
--- response_body_like chomp
500 Internal Server Error
--- error_log
bad timeout value
--- timeout: 10
--- error_code: 500



=== TEST 11: lua_socket_send_timeout only
--- config
    server_tokens off;
    lua_socket_send_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        rewrite_by_lua '
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

        content_by_lua return;
    }
--- request
GET /t
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
        rewrite_by_lua '
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

        content_by_lua return;
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
        rewrite_by_lua '
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

        content_by_lua return;
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
        rewrite_by_lua '
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

        content_by_lua return;
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



=== TEST 15: -1 is bad timeout value
--- config
    server_tokens off;
    lua_socket_send_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        rewrite_by_lua '
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

        content_by_lua return;
    }
--- request
GET /t
--- response_body_like chomp
500 Internal Server Error
--- error_log
bad timeout value
--- timeout: 10
--- error_code: 500
