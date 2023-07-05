# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4 + 4);

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
    resolver $TEST_NGINX_RESOLVER ipv6=off;
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
--- response_body_like
connected: 1
request sent: 56
first line received: HTTP\/1\.1 200 OK
second line received: (?:Date|Server): .*?
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
qr/connect\(\) failed \(\d+: Connection refused\), context: ngx\.timer$/



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



=== TEST 18: syslog error log
--- http_config
    #error_log syslog:server=127.0.0.1:12345 error;
    init_worker_by_lua '
        done = false
        os.execute("sleep 0.1")
        ngx.log(ngx.ERR, "Bad bad bad")
        done = true
    ';
--- config
    location /t {
        content_by_lua '
            while not done do
                ngx.sleep(0.001)
            end
            ngx.say("ok")
        ';
    }
--- log_level: error
--- error_log_file: syslog:server=127.0.0.1:12345
--- udp_listen: 12345
--- udp_query eval: qr/Bad bad bad/
--- udp_reply: hello
--- wait: 0.1
--- request
    GET /t
--- response_body
ok
--- error_log
Bad bad bad
--- skip_nginx: 4: < 1.7.1



=== TEST 19: fake module calls ngx_http_conf_get_module_srv_conf in its merge_srv_conf callback (GitHub issue #554)
This also affects merge_loc_conf
--- http_config
    init_worker_by_lua return;
--- config
    location = /t {
        return 200 ok;
    }
--- request
GET /t
--- response_body chomp
ok
--- no_error_log
[error]



=== TEST 20: destroy Lua VM in cache processes (without privileged agent or shdict)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    proxy_cache_path /tmp/cache levels=1:2 keys_zone=cache:1m;

    #lua_shared_dict dummy 500k;

    init_by_lua_block {
        require "resty.core.regex"
        assert(ngx.re.match("hello, world", [[hello, \w+]], "joi"))
        assert(ngx.re.match("hi, world", [[hi, \w+]], "ji"))
    }

--- config
    location = /t {
        return 200;
    }
--- request
    GET /t
--- grep_error_log eval: qr/lua close the global Lua VM \S+ in the cache helper process \d+|lua close the global Lua VM \S+$/
--- grep_error_log_out eval
qr/\A(?:lua close the global Lua VM ([0-9A-F]+) in the cache helper process \d+
lua close the global Lua VM \1
lua close the global Lua VM \1 in the cache helper process \d+
lua close the global Lua VM \1
|lua close the global Lua VM ([0-9A-F]+) in the cache helper process \d+
lua close the global Lua VM \2 in the cache helper process \d+
lua close the global Lua VM \2
lua close the global Lua VM \2
|lua close the global Lua VM ([0-9A-F]+)
lua close the global Lua VM \3 in the cache helper process \d+
lua close the global Lua VM \3
lua close the global Lua VM \3 in the cache helper process \d+
|lua close the global Lua VM ([0-9A-F]+)
lua close the global Lua VM \4 in the cache helper process \d+
lua close the global Lua VM \4 in the cache helper process \d+
lua close the global Lua VM \4
)(?:lua close the global Lua VM [0-9A-F]+
)*\z/
--- no_error_log
[error]
start privileged agent process



=== TEST 21: destroy Lua VM in cache processes (without privileged agent but with shdict)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    proxy_cache_path /tmp/cache levels=1:2 keys_zone=cache:1m;

    lua_shared_dict dummy 500k;

    init_by_lua_block {
        require "resty.core.regex"
        assert(ngx.re.match("hello, world", [[hello, \w+]], "joi"))
        assert(ngx.re.match("hi, world", [[hi, \w+]], "ji"))
    }

--- config
    location = /t {
        return 200;
    }
--- request
    GET /t
--- grep_error_log eval: qr/lua close the global Lua VM \S+ in the cache helper process \d+|lua close the global Lua VM \S+$/
--- grep_error_log_out eval
qr/\A(?:lua close the global Lua VM ([0-9A-F]+) in the cache helper process \d+
lua close the global Lua VM \1
lua close the global Lua VM \1 in the cache helper process \d+
lua close the global Lua VM \1
|lua close the global Lua VM ([0-9A-F]+) in the cache helper process \d+
lua close the global Lua VM \2 in the cache helper process \d+
lua close the global Lua VM \2
lua close the global Lua VM \2
|lua close the global Lua VM ([0-9A-F]+)
lua close the global Lua VM \3 in the cache helper process \d+
lua close the global Lua VM \3
lua close the global Lua VM \3 in the cache helper process \d+
)(?:lua close the global Lua VM [0-9A-F]+
|lua close the global Lua VM ([0-9A-F]+)
lua close the global Lua VM \4 in the cache helper process \d+
lua close the global Lua VM \4 in the cache helper process \d+
lua close the global Lua VM \4 
lua close the global Lua VM \4
)*\z/
--- no_error_log
[error]
start privileged agent process



=== TEST 22: destroy Lua VM in cache processes (with privileged agent)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    #lua_shared_dict dogs 1m;

    proxy_cache_path /tmp/cache levels=1:2 keys_zone=cache:1m;

    init_by_lua_block {
        assert(require "ngx.process".enable_privileged_agent())
        require "resty.core.regex"
        assert(ngx.re.match("hello, world", [[hello, \w+]], "joi"))
        assert(ngx.re.match("hi, world", [[hi, \w+]], "ji"))
    }

--- config
    location = /t {
        return 200;
    }
--- request
    GET /t
--- grep_error_log eval: qr/lua close the global Lua VM \S+ in the cache helper process \d+|lua close the global Lua VM \S+$/
--- grep_error_log_out eval
qr/\A(?:lua close the global Lua VM ([0-9A-F]+) in the cache helper process \d+
lua close the global Lua VM \1
lua close the global Lua VM \1 in the cache helper process \d+
lua close the global Lua VM \1
|lua close the global Lua VM ([0-9A-F]+) in the cache helper process \d+
lua close the global Lua VM \2 in the cache helper process \d+
lua close the global Lua VM \2
lua close the global Lua VM \2
|lua close the global Lua VM ([0-9A-F]+)
lua close the global Lua VM \3 in the cache helper process \d+
lua close the global Lua VM \3
lua close the global Lua VM \3 in the cache helper process \d+
|lua close the global Lua VM ([0-9A-F]+)
lua close the global Lua VM \4 in the cache helper process \d+
lua close the global Lua VM \4 in the cache helper process \d+
lua close the global Lua VM \4
)(?:lua close the global Lua VM [0-9A-F]+
)*\z/
--- error_log eval
qr/start privileged agent process \d+/
--- no_error_log
[error]



=== TEST 23: destroy Lua VM in cache processes (with init worker and privileged agent)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    #lua_shared_dict dogs 1m;

    proxy_cache_path /tmp/cache levels=1:2 keys_zone=cache:1m;

    init_by_lua_block {
        assert(require "ngx.process".enable_privileged_agent())
        require "resty.core.regex"
        assert(ngx.re.match("hello, world", [[hello, \w+]], "joi"))
        assert(ngx.re.match("hi, world", [[hi, \w+]], "ji"))
    }

    init_worker_by_lua_block {
        ngx.log(ngx.WARN, "hello from init worker by lua")
    }

--- config
    location = /t {
        return 200;
    }
--- request
    GET /t
--- grep_error_log eval: qr/hello from init worker by lua/
--- grep_error_log_out
hello from init worker by lua
hello from init worker by lua

--- error_log eval
[
qr/start privileged agent process \d+$/,
qr/lua close the global Lua VM ([0-9A-F]+) in the cache helper process \d+$/,
qr/lua close the global Lua VM ([0-9A-F]+)$/,
]
--- no_error_log
[error]



=== TEST 24: destroy Lua VM in cache processes (with init worker but without privileged agent)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    #lua_shared_dict dogs 1m;

    proxy_cache_path /tmp/cache levels=1:2 keys_zone=cache:1m;

    init_by_lua_block {
        require "resty.core.regex"
        assert(ngx.re.match("hello, world", [[hello, \w+]], "joi"))
        assert(ngx.re.match("hi, world", [[hi, \w+]], "ji"))
    }

    init_worker_by_lua_block {
        ngx.log(ngx.WARN, "hello from init worker by lua")
    }

--- config
    location = /t {
        return 200;
    }
--- request
    GET /t

--- grep_error_log eval: qr/hello from init worker by lua/
--- grep_error_log_out
hello from init worker by lua

--- error_log eval
[
qr/lua close the global Lua VM ([0-9A-F]+) in the cache helper process \d+$/,
qr/lua close the global Lua VM ([0-9A-F]+)$/,
]
--- no_error_log
[error]
start privileged agent process



=== TEST 25: syntax error in init_worker_by_lua_block
--- http_config
    init_worker_by_lua_block {
        ngx.log(ngx.debug, "pass")
        error("failed to init"
        ngx.log(ngx.debug, "unreachable")
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say("hello world")
        }
    }
--- request
    GET /t
--- response_body
hello world
--- error_log
init_worker_by_lua error: init_worker_by_lua(nginx.conf:25):4: ')' expected (to close '(' at line 3) near 'ngx'
--- no_error_log
no_such_error_log



=== TEST 26: syntax error in init_worker_by_lua_file
--- http_config
    init_worker_by_lua_file html/init.lua;
--- config
    location /t {
        content_by_lua_block {
            ngx.say("hello world")
        }
    }
--- user_files
>>> init.lua
    ngx.log(ngx.debug, "pass")
    error("failed to init"
    ngx.log(ngx.debug, "unreachable")

--- request
    GET /t
--- response_body
hello world
--- error_log eval
qr|init_worker_by_lua_file error: .*?t/servroot\w*/html/init.lua:3: '\)' expected \(to close '\(' at line 2\) near 'ngx'|
--- no_error_log
no_such_error_log
