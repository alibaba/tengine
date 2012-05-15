# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    $ENV{MOCKEAGAIN} = 'w';

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'get helloworld';
}

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 10);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();
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
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("www.taobao.com", 12345)
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
lua socket connect timeout: 100
lua socket connect timed out



=== TEST 2: sock:settimeout() overrides lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 60s;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(150)
            local ok, err = sock:connect("www.taobao.com", 12345)
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
lua socket connect timeout: 150
lua socket connect timed out



=== TEST 3: sock:settimeout(nil) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(nil)
            local ok, err = sock:connect("www.taobao.com", 12345)
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
lua socket connect timeout: 102
lua socket connect timed out



=== TEST 4: sock:settimeout(0) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(0)
            local ok, err = sock:connect("www.taobao.com", 12345)
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
lua socket connect timeout: 102
lua socket connect timed out



=== TEST 5: sock:settimeout(-1) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(-1)
            local ok, err = sock:connect("www.taobao.com", 12345)
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
lua socket connect timeout: 102
lua socket connect timed out



=== TEST 6: lua_socket_read_timeout only
--- config
    server_tokens off;
    lua_socket_read_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER;
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
lua socket read timeout: 100
lua socket connect timeout: 60000
lua socket read timed out



=== TEST 7: sock:settimeout() overrides lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 60s;
    #resolver $TEST_NGINX_RESOLVER;
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
lua socket connect timeout: 60000
lua socket read timeout: 150
lua socket read timed out



=== TEST 8: sock:settimeout(nil) does not override lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
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
lua socket connect timeout: 60000
lua socket read timeout: 102
lua socket read timed out



=== TEST 9: sock:settimeout(0) does not override lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
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
lua socket connect timeout: 60000
lua socket read timeout: 102
lua socket read timed out



=== TEST 10: sock:settimeout(-1) does not override lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

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
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua socket read timeout: 102
lua socket connect timeout: 60000
lua socket read timed out



=== TEST 11: lua_socket_send_timeout only
--- config
    server_tokens off;
    lua_socket_send_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER;
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
--- response_body
connected: 1
failed to send: timeout
--- error_log
lua socket send timeout: 100
lua socket connect timeout: 60000
lua socket write timed out



=== TEST 12: sock:settimeout() overrides lua_socket_send_timeout
--- config
    server_tokens off;
    lua_socket_send_timeout 60s;
    #resolver $TEST_NGINX_RESOLVER;
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
lua socket connect timeout: 60000
lua socket send timeout: 150
lua socket write timed out



=== TEST 13: sock:settimeout(nil) does not override lua_socket_send_timeout
--- config
    server_tokens off;
    lua_socket_send_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
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
lua socket connect timeout: 60000
lua socket send timeout: 102
lua socket write timed out



=== TEST 14: sock:settimeout(0) does not override lua_socket_send_timeout
--- config
    server_tokens off;
    lua_socket_send_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
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
lua socket connect timeout: 60000
lua socket send timeout: 102
lua socket write timed out



=== TEST 15: sock:settimeout(-1) does not override lua_socket_send_timeout
--- config
    server_tokens off;
    lua_socket_send_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

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
--- response_body
connected: 1
failed to send: timeout
--- error_log
lua socket send timeout: 102
lua socket connect timeout: 60000
lua socket write timed out

