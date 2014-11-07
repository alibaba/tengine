# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4 + 1);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

our $ServerRoot = server_root();

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: set a global lua var
--- http_config
    init_worker_by_lua '
        foo = ngx.md5("hello world")
    ';
--- config
    location /t {
        content_by_lua '
            ngx.say("foo = ", foo)
        ';
    }
--- request
    GET /t
--- response_body
foo = 5eb63bbbe01eeed093cb22bb8f5acdc3
--- no_error_log
[error]



=== TEST 2: no ngx.say()
--- http_config
    init_worker_by_lua '
        ngx.say("hello")
    ';
--- config
    location /t {
        content_by_lua '
            ngx.say("foo = ", foo)
        ';
    }
--- request
    GET /t
--- response_body
foo = nil
--- error_log
API disabled in the context of init_worker_by_lua*



=== TEST 3: timer.at
--- http_config
    init_worker_by_lua '
        _G.my_counter = 0
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end
        local function handler(premature)
            warn("timer expired (premature: ", premature, "; counter: ",
                 _G.my_counter, ")")
            _G.my_counter = _G.my_counter + 1
        end
        local ok, err = ngx.timer.at(0, handler)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
        end
        warn("created timer: ", ok)
    ';
--- config
    location /t {
        content_by_lua '
            -- ngx.sleep(0.001)
            ngx.say("my_counter = ", _G.my_counter)
            _G.my_counter = _G.my_counter + 1
        ';
    }
--- request
    GET /t
--- response_body
my_counter = 1
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): created timer: 1
warn(): timer expired (premature: false; counter: 0)

--- no_error_log
[error]



=== TEST 4: timer.at + cosocket
--- http_config
    init_worker_by_lua '
        _G.done = false
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end
        local function error(...)
            ngx.log(ngx.ERR, ...)
        end
        local function handler(premature)
            warn("timer expired (premature: ", premature, ")")

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                error("failed to connect: ", err)
                _G.done = true
                return
            end

            local req = "flush_all\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                error("failed to send request: ", err)
                _G.done = true
                return
            end

            warn("request sent: ", bytes)

            local line, err, part = sock:receive()
            if line then
                warn("received: ", line)
            else
                error("failed to receive a line: ", err, " [", part, "]")
            end
            _G.done = true
        end

        local ok, err = ngx.timer.at(0, handler)
        if not ok then
            error("failed to create timer: ", err)
        end
        warn("created timer: ", ok)
    ';
--- config
    location = /t {
        content_by_lua '
            local waited = 0
            local sleep = ngx.sleep
            while not _G.done do
                local delay = 0.001
                sleep(delay)
                waited = waited + delay
                if waited > 1 then
                    ngx.say("timed out")
                    return
                end
            end
            ngx.say("ok")
        ';
    }
--- request
    GET /t
--- response_body
ok
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): created timer: 1
warn(): timer expired (premature: false)
warn(): request sent: 11
warn(): received: OK

--- log_level: debug
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 60000
lua tcp socket read timeout: 60000
--- no_error_log
[error]



=== TEST 5: init_worker_by_lua_file (simple global var)
--- http_config
    init_worker_by_lua_file html/foo.lua;
--- config
    location /t {
        content_by_lua '
            ngx.say("foo = ", foo)
        ';
    }
--- user_files
>>> foo.lua
foo = ngx.md5("hello world")
--- request
    GET /t
--- response_body
foo = 5eb63bbbe01eeed093cb22bb8f5acdc3
--- no_error_log
[error]



=== TEST 6: timer.at + cosocket (by_lua_file)
--- main_config
env TEST_NGINX_MEMCACHED_PORT;
--- http_config
    init_worker_by_lua_file html/foo.lua;
--- user_files
>>> foo.lua
_G.done = false
local function warn(...)
    ngx.log(ngx.WARN, ...)
end
local function error(...)
    ngx.log(ngx.ERR, ...)
end
local function handler(premature)
    warn("timer expired (premature: ", premature, ")")

    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1",
                                 os.getenv("TEST_NGINX_MEMCACHED_PORT"))
    if not ok then
        error("failed to connect: ", err)
        _G.done = true
        return
    end

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        error("failed to send request: ", err)
        _G.done = true
        return
    end

    warn("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        warn("received: ", line)
    else
        error("failed to receive a line: ", err, " [", part, "]")
    end
    _G.done = true
end

local ok, err = ngx.timer.at(0, handler)
if not ok then
    error("failed to create timer: ", err)
end
warn("created timer: ", ok)

--- config
    location = /t {
        content_by_lua '
            local waited = 0
            local sleep = ngx.sleep
            while not _G.done do
                local delay = 0.001
                sleep(delay)
                waited = waited + delay
                if waited > 1 then
                    ngx.say("timed out")
                    return
                end
            end
            ngx.say("ok")
        ';
    }
--- request
    GET /t
--- response_body
ok
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): created timer: 1
warn(): timer expired (premature: false)
warn(): request sent: 11
warn(): received: OK

--- log_level: debug
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 60000
lua tcp socket read timeout: 60000
--- no_error_log
[error]



=== TEST 7: ngx.ctx
--- http_config
    init_worker_by_lua '
        ngx.ctx.foo = "hello world"
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end
        warn("foo = ", ngx.ctx.foo)
    ';
--- config
    location /t {
        echo ok;
    }
--- request
    GET /t
--- response_body
ok
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): foo = hello world
--- no_error_log
[error]



=== TEST 8: print
--- http_config
    init_worker_by_lua '
        print("md5 = ", ngx.md5("hello world"))
    ';
--- config
    location /t {
        echo ok;
    }
--- request
    GET /t
--- response_body
ok
--- no_error_log
[error]
--- error_log
md5 = 5eb63bbbe01eeed093cb22bb8f5acdc3



=== TEST 9: unescape_uri
--- http_config
    init_worker_by_lua '
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end

        warn(ngx.unescape_uri("hello%20world"))
    ';
--- config
    location /t {
        echo ok;
    }
--- request
    GET /t
--- response_body
ok
--- no_error_log
[error]
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): hello world



=== TEST 10: escape_uri
--- http_config
    init_worker_by_lua '
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end

        warn(ngx.escape_uri("hello world"))
    ';
--- config
    location /t {
        echo ok;
    }
--- request
    GET /t
--- response_body
ok
--- no_error_log
[error]
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): hello%20world



=== TEST 11: ngx.re
--- http_config
    init_worker_by_lua '
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end

        warn((ngx.re.sub("hello world", "world", "XXX", "jo")))
    ';
--- config
    location /t {
        echo ok;
    }
--- request
    GET /t
--- response_body
ok
--- no_error_log
[error]
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): hello XXX



=== TEST 12: ngx.http_time
--- http_config
    init_worker_by_lua '
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end

        warn(ngx.http_time(5678))
    ';
--- config
    location /t {
        echo ok;
    }
--- request
    GET /t
--- response_body
ok
--- no_error_log
[error]
--- grep_error_log eval: qr/warn\(\): .*?(?=, context)/
--- grep_error_log_out
warn(): Thu, 01 Jan 1970 01:34:38 GMT



=== TEST 13: cosocket with resolver
--- timeout: 10
--- http_config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    resolver_timeout 3s;
    init_worker_by_lua '
        -- global
        logs = ""
        done = false
        local function say(...)
            logs = logs .. table.concat({...}) .. "\\n"
        end

        local function handler()
            local sock = ngx.socket.tcp()
            local port = 80
            local ok, err = sock:connect("agentzh.org", port)
            if not ok then
                say("failed to connect: ", err)
                done = true
                return
            end

            say("connected: ", ok)

            local req = "GET / HTTP/1.0\\r\\nHost: agentzh.org\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                say("failed to send request: ", err)
                done = true
                return
            end

            say("request sent: ", bytes)

            local line, err = sock:receive()
            if line then
                say("first line received: ", line)

            else
                say("failed to receive the first line: ", err)
            end

            line, err = sock:receive()
            if line then
                say("second line received: ", line)

            else
                say("failed to receive the second line: ", err)
            end

            done = true
        end

        local ok, err = ngx.timer.at(0, handler)
        if not ok then
            say("failed to create timer: ", err)
        else
            say("timer created")
        end
    ';

--- config
    location = /t {
        content_by_lua '
            local i = 0
            while not done and i < 3000 do
                ngx.sleep(0.001)
                i = i + 1
            end
            ngx.print(logs)
        ';
    }
--- request
GET /t
--- response_body
timer created
connected: 1
request sent: 56
first line received: HTTP/1.1 200 OK
second line received: Server: openresty
--- no_error_log
[error]
--- timeout: 10



=== TEST 14: connection refused (tcp) - log_errors on by default
--- http_config
    init_worker_by_lua '
        logs = ""
        done = false
        local function say(...)
            logs = logs .. table.concat{...} .. "\\n"
        end

        local function handler()
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 16787)
            if not ok then
                say("failed to connect: ", err)
            else
                say("connect: ", ok, " ", err)
            end
        end

        local ok, err = ngx.timer.at(0, handler)
        if not ok then
            say("failed to create timer: ", err)
        else
            say("timer created")
        end
    ';

--- config
    location = /t {
        content_by_lua '
            local i = 0
            while not done and i < 1000 do
                ngx.sleep(0.001)
                i = i + 1
            end
            ngx.print(logs)
        ';
    }

--- request
    GET /t
--- response_body
timer created
failed to connect: connection refused
--- error_log eval
qr/connect\(\) failed \(\d+: Connection refused\)/



=== TEST 15: connection refused (tcp) - log_errors explicitly on
--- http_config
    lua_socket_log_errors on;
    init_worker_by_lua '
        logs = ""
        done = false
        local function say(...)
            logs = logs .. table.concat{...} .. "\\n"
        end

        local function handler()
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 16787)
            if not ok then
                say("failed to connect: ", err)
            else
                say("connect: ", ok, " ", err)
            end
        end

        local ok, err = ngx.timer.at(0, handler)
        if not ok then
            say("failed to create timer: ", err)
        else
            say("timer created")
        end
    ';

--- config
    location = /t {
        content_by_lua '
            local i = 0
            while not done and i < 1000 do
                ngx.sleep(0.001)
                i = i + 1
            end
            ngx.print(logs)
        ';
    }

--- request
    GET /t
--- response_body
timer created
failed to connect: connection refused
--- error_log eval
qr/connect\(\) failed \(\d+: Connection refused\)/



=== TEST 16: connection refused (tcp) - log_errors explicitly off
--- http_config
    lua_socket_log_errors off;
    init_worker_by_lua '
        logs = ""
        done = false
        local function say(...)
            logs = logs .. table.concat{...} .. "\\n"
        end

        local function handler()
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 16787)
            if not ok then
                say("failed to connect: ", err)
            else
                say("connect: ", ok, " ", err)
            end
        end

        local ok, err = ngx.timer.at(0, handler)
        if not ok then
            say("failed to create timer: ", err)
        else
            say("timer created")
        end
    ';

--- config
    location = /t {
        content_by_lua '
            local i = 0
            while not done and i < 1000 do
                ngx.sleep(0.001)
                i = i + 1
            end
            ngx.print(logs)
        ';
    }

--- request
    GET /t
--- response_body
timer created
failed to connect: connection refused
--- no_error_log eval
[
'qr/connect\(\) failed \(\d+: Connection refused\)/',
'[error]',
]



=== TEST 17: init_by_lua + proxy_temp_path which has side effects in cf->cycle->paths
--- http_config eval
qq{
    proxy_temp_path $::ServerRoot/proxy_temp;
    init_worker_by_lua '
        local a = 2 + 3
    ';
}
--- config
    location /t {
        echo ok;
    }
--- request
    GET /t
--- response_body
ok
--- no_error_log
[error]
[alert]
[emerg]

