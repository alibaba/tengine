# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 5 + 4);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;
#$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

$ENV{LUA_PATH} ||=
    '/usr/local/openresty-debug/lualib/?.lua;/usr/local/openresty/lualib/?.lua;;';

no_long_string();
#no_diff();
#log_level 'warn';

no_shuffle();

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        rewrite_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go(port)
            test.go(port)
        ';

        content_by_lua return;
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

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

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body_like
^connected: 1, reused: \d+
request sent: 11
received: OK
connected: 1, reused: [1-9]\d*
request sent: 11
received: OK
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for "]
--- grep_error_log eval
qr/lua tcp socket get keepalive peer: using connection|lua tcp socket keepalive create connection pool for key "[^"]+"/

--- grep_error_log_out eval
[
qq{lua tcp socket keepalive create connection pool for key "127.0.0.1:$ENV{TEST_NGINX_MEMCACHED_PORT}"
lua tcp socket get keepalive peer: using connection
},
"lua tcp socket get keepalive peer: using connection
lua tcp socket get keepalive peer: using connection
"]



=== TEST 2: free up the whole connection pool if no active connections
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        rewrite_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go(port, true)
            test.go(port, false)
        ';

        content_by_lua return;
    }
--- request
GET /t
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port, keepalive)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

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

    if keepalive then
        local ok, err = sock:setkeepalive()
        if not ok then
            ngx.say("failed to set reusable: ", err)
        end

    else
        sock:close()
    end
end
--- response_body_like
^connected: 1, reused: \d+
request sent: 11
received: OK
connected: 1, reused: [1-9]\d*
request sent: 11
received: OK
--- no_error_log
[error]
--- error_log eval
["lua tcp socket get keepalive peer: using connection",
"lua tcp socket keepalive: free connection pool for "]



=== TEST 3: upstream sockets close prematurely
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
   server_tokens off;
   keepalive_timeout 100ms;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        rewrite_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';

        content_by_lua return;
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for "]
--- timeout: 3



=== TEST 4: http keepalive
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
   server_tokens off;
   location /t {
        keepalive_timeout 60s;

        set $port $TEST_NGINX_SERVER_PORT;
        rewrite_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';

        content_by_lua return;
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log eval
["[error]",
"lua tcp socket keepalive close handler: fd:",
"lua tcp socket keepalive: free connection pool for "]
--- timeout: 4



=== TEST 5: lua_socket_keepalive_timeout
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 100ms;

        set $port $TEST_NGINX_SERVER_PORT;
        rewrite_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';

        content_by_lua return;
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 100 ms",
qr/lua tcp socket connection pool size: 30\b/]
--- timeout: 4



=== TEST 6: lua_socket_pool_size
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 100ms;
       lua_socket_pool_size 1;

        set $port $TEST_NGINX_SERVER_PORT;
        rewrite_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';

        content_by_lua return;
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 100 ms",
qr/lua tcp socket connection pool size: 1\b/]
--- timeout: 4



=== TEST 7: "lua_socket_keepalive_timeout 0" means unlimited
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 0;

        set $port $TEST_NGINX_SERVER_PORT;
        rewrite_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';

        content_by_lua return;
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- grep_error_log eval
qr/lua tcp socket keepalive timeout: unlimited|lua tcp socket connection pool size: \d+/
--- grep_error_log_out eval
["lua tcp socket connection pool size: 30
lua tcp socket keepalive timeout: unlimited
",
"lua tcp socket keepalive timeout: unlimited
"]
--- timeout: 4



=== TEST 8: setkeepalive(timeout) overrides lua_socket_keepalive_timeout
--- config
   server_tokens off;
   location /t {
        keepalive_timeout 60s;
        lua_socket_keepalive_timeout 60s;

        set $port $TEST_NGINX_SERVER_PORT;
        rewrite_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive(123)
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';

        content_by_lua return;
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 123 ms",
qr/lua tcp socket connection pool size: 30\b/]
--- timeout: 4



=== TEST 9: sock:setkeepalive(timeout, size) overrides lua_socket_pool_size
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 100ms;
       lua_socket_pool_size 100;

        set $port $TEST_NGINX_SERVER_PORT;
        rewrite_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive(101, 25)
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';

        content_by_lua return;
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 101 ms",
qr/lua tcp socket connection pool size: 25\b/]
--- timeout: 4



=== TEST 10: sock:keepalive_timeout(0) means unlimited
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 1000ms;

        set $port $TEST_NGINX_SERVER_PORT;
        rewrite_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive(0)
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';

        content_by_lua return;
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- grep_error_log eval
qr/lua tcp socket keepalive timeout: unlimited|lua tcp socket connection pool size: \d+/
--- grep_error_log_out eval
["lua tcp socket connection pool size: 30
lua tcp socket keepalive timeout: unlimited
",
"lua tcp socket keepalive timeout: unlimited
"
]
--- timeout: 4



=== TEST 11: sanity (uds)
--- http_config eval
"
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
    server {
        listen unix:$::HtmlDir/nginx.sock;
        default_type 'text/plain';

        server_tokens off;
        location /foo {
            echo foo;
            more_clear_headers Date;
        }
    }
"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        rewrite_by_lua '
            local test = require "test"
            local path = "$TEST_NGINX_HTML_DIR/nginx.sock";
            local port = ngx.var.port
            test.go(path, port)
            test.go(path, port)
        ';

        content_by_lua return;
    }
--- request
GET /t
--- user_files
>>> test.lua
module("test", package.seeall)

function go(path, port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("unix:" .. path)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "GET /foo HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end
    ngx.say("request sent: ", bytes)

    local reader = sock:receiveuntil("\r\n0\r\n\r\n")
    local data, err = reader()

    if not data then
        ngx.say("failed to receive response body: ", err)
        return
    end

    ngx.say("received response of ", #data, " bytes")

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- response_body_like
^connected: 1, reused: \d+
request sent: 61
received response of 119 bytes
connected: 1, reused: [1-9]\d*
request sent: 61
received response of 119 bytes
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for "]
--- grep_error_log eval
qr/lua tcp socket get keepalive peer: using connection|lua tcp socket keepalive create connection pool for key "unix:/
--- grep_error_log_out eval
[qq{lua tcp socket keepalive create connection pool for key "unix:
lua tcp socket get keepalive peer: using connection
},
"lua tcp socket get keepalive peer: using connection
lua tcp socket get keepalive peer: using connection
"
]



=== TEST 12: github issue #108: ngx.location.capture + redis.set_keepalive
--- http_config eval
    qq{
        lua_package_path "$::HtmlDir/?.lua;;";
    }
--- config
    location /t {
        default_type text/html;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #lua_code_cache off;
        lua_need_request_body on;
        rewrite_by_lua_file html/t.lua;
        content_by_lua return;
    }

    location /anyurl {
        internal;
        proxy_pass http://127.0.0.1:$server_port/dummy;
    }

    location = /dummy {
        echo dummy;
    }
--- user_files
>>> t.lua
local sock, err = ngx.socket.connect("127.0.0.1", ngx.var.port)
if not sock then ngx.say(err) return end
sock:send("flush_all\r\n")
sock:receive()
sock:setkeepalive()

sock, err = ngx.socket.connect("127.0.0.1", ngx.var.port)
if not sock then ngx.say(err) return end
local res = ngx.location.capture("/anyurl") --3

ngx.say("ok")
--- request
    GET /t
--- response_body
ok
--- error_log
lua tcp socket get keepalive peer: using connection
--- no_error_log
[error]
[alert]



=== TEST 13: github issue #110: ngx.exit with HTTP_NOT_FOUND causes worker process to exit
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    error_page 404 /404.html;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        access_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go(port)
            ngx.exit(404)
        ';
        echo hello;
    }
--- user_files
>>> 404.html
Not found, dear...
>>> test.lua
module("test", package.seeall)

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect: ", err)
        return
    end

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.log(ngx.ERR, "failed to send request: ", err)
        return
    end

    local line, err, part = sock:receive()
    if not line then
        ngx.log(ngx.ERR, "failed to receive a line: ", err, " [", part, "]")
        return
    end

    -- local ok, err = sock:setkeepalive()
    -- if not ok then
        -- ngx.log(ngx.ERR, "failed to set reusable: ", err)
        -- return
    -- end
end
--- request
GET /t
--- response_body
Not found, dear...
--- error_code: 404
--- no_error_log
[error]
