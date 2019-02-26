# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 3);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: malloc_trim() every 1 req, in subreq
--- http_config
    lua_malloc_trim 1;
--- config
    location = /t {
        return 200 "ok\n";
    }

    location = /main {
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
    }
--- request
GET /main
--- response_body
ok
ok
ok
ok
ok
--- grep_error_log eval: qr/malloc_trim\(\d+\) returned \d+/
--- grep_error_log_out eval
qr/\Amalloc_trim\(1\) returned [01]
\z/
--- wait: 0.2
--- no_error_log
[error]



=== TEST 2: malloc_trim() every 1 req, in subreq
--- http_config
    lua_malloc_trim 1;
--- config
    location = /t {
        log_subrequest on;
        return 200 "ok\n";
    }

    location = /main {
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
    }
--- request
GET /main
--- response_body
ok
ok
ok
ok
ok
--- grep_error_log eval: qr/malloc_trim\(\d+\) returned \d+/
--- grep_error_log_out eval
qr/\Amalloc_trim\(1\) returned [01]
malloc_trim\(1\) returned [01]
malloc_trim\(1\) returned [01]
malloc_trim\(1\) returned [01]
malloc_trim\(1\) returned [01]
malloc_trim\(1\) returned [01]
\z/
--- wait: 0.2
--- no_error_log
[error]



=== TEST 3: malloc_trim() every 2 req, in subreq
--- http_config
    lua_malloc_trim 2;
--- config
    location = /t {
        log_subrequest on;
        return 200 "ok\n";
    }

    location = /main {
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
    }
--- request
GET /main
--- response_body
ok
ok
ok
ok
ok
--- grep_error_log eval: qr/malloc_trim\(\d+\) returned \d+/
--- grep_error_log_out eval
qr/\Amalloc_trim\(1\) returned [01]
malloc_trim\(1\) returned [01]
malloc_trim\(1\) returned [01]
\z/
--- wait: 0.2
--- no_error_log
[error]



=== TEST 4: malloc_trim() every 3 req, in subreq
--- http_config
    lua_malloc_trim 3;
--- config
    location = /t {
        log_subrequest on;
        return 200 "ok\n";
    }

    location = /main {
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
    }
--- request
GET /main
--- response_body
ok
ok
ok
ok
ok
--- grep_error_log eval: qr/malloc_trim\(\d+\) returned \d+/
--- grep_error_log_out eval
qr/\Amalloc_trim\(1\) returned [01]
malloc_trim\(1\) returned [01]
\z/
--- wait: 0.2
--- no_error_log
[error]



=== TEST 5: malloc_trim() every 2 req, in subreq, big memory usage
--- http_config
    lua_malloc_trim 2;
    lua_package_path "$prefix/html/?.lua;;";
--- config
    location = /t {
        log_subrequest on;
        content_by_lua_block {
            require("foo")()
        }
    }

    location = /main {
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
    }
--- user_files
>>> foo.lua
local ffi = require "ffi"

ffi.cdef[[
    void *malloc(size_t sz);
    void free(void *p);
]]

return function ()
    local t = {}
    for i = 1, 10 do
        t[i] = ffi.C.malloc(1024 * 128)
    end
    for i = 1, 10 do
        ffi.C.free(t[i])
    end
    ngx.say("ok")
end
--- request
GET /main
--- response_body
ok
ok
ok
ok
ok
--- grep_error_log eval: qr/malloc_trim\(\d+\) returned \d+/
--- grep_error_log_out
malloc_trim(1) returned 1
malloc_trim(1) returned 1
malloc_trim(1) returned 1
--- wait: 0.2
--- no_error_log
[error]



=== TEST 6: zero count means off
--- http_config
    lua_malloc_trim 0;
    lua_package_path "$prefix/html/?.lua;;";
--- config
    location = /t {
        content_by_lua_block {
            require("foo")()
        }
    }
--- user_files
>>> foo.lua
local ffi = require "ffi"

ffi.cdef[[
    void *malloc(size_t sz);
    void free(void *p);
]]

return function ()
    local t = {}
    for i = 1, 10 do
        t[i] = ffi.C.malloc(1024 * 128)
    end
    for i = 1, 10 do
        ffi.C.free(t[i])
    end
    ngx.say("ok")
end

--- request
GET /t
--- response_body
ok
--- grep_error_log eval: qr/malloc_trim\(\d+\) returned \d+/
--- grep_error_log_out
--- wait: 0.2
--- no_error_log
malloc_trim() disabled
[error]



=== TEST 7: zero count means off, log_by_lua
--- http_config
    lua_malloc_trim 0;
    lua_package_path "$prefix/html/?.lua;;";
--- config
    location = /t {
        content_by_lua_block {
            require("foo")()
        }
        log_by_lua_block {
            print("Hello from log")
        }
    }
--- user_files
>>> foo.lua
local ffi = require "ffi"

ffi.cdef[[
    void *malloc(size_t sz);
    void free(void *p);
]]

return function ()
    local t = {}
    for i = 1, 10 do
        t[i] = ffi.C.malloc(1024 * 128)
    end
    for i = 1, 10 do
        ffi.C.free(t[i])
    end
    ngx.say("ok")
end

--- request
GET /t
--- response_body
ok
--- grep_error_log eval: qr/malloc_trim\(\d+\) returned \d+/
--- grep_error_log_out
--- wait: 0.2
--- error_log
Hello from log
malloc_trim() disabled
--- no_error_log
[error]



=== TEST 8: malloc_trim() every 1 req
--- http_config
    lua_malloc_trim 1;
--- config
    location = /t {
        return 200 "ok\n";
    }

    location = /main {
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
        echo_location /t;
    }
--- request
GET /main
--- response_body
ok
ok
ok
ok
ok
--- grep_error_log eval: qr/malloc_trim\(\d+\) returned \d+/
--- grep_error_log_out eval
qr/\Amalloc_trim\(1\) returned [01]
\z/
--- wait: 0.2
--- no_error_log
[error]
