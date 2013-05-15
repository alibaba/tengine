# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 6);

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: read chunks (inline)
--- config
    location /read {
        echo -n hello world;
        echo -n hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            print("chunk: [", chunk, "], eof: ", eof)
        ';
    }
--- request
GET /read
--- response_body chop
hello worldhiya globe
--- error_log
chunk: [hello world], eof: false
chunk: [hiya globe], eof: false
chunk: [], eof: true
--- no_error_log
[error]



=== TEST 2: read chunks (file)
--- config
    location /read {
        echo -n hello world;
        echo -n hiya globe;

        body_filter_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
local chunk, eof = ngx.arg[1], ngx.arg[2]
print("chunk: [", chunk, "], eof: ", eof)
--- request
GET /read
--- response_body chop
hello worldhiya globe
--- error_log
chunk: [hello world], eof: false
chunk: [hiya globe], eof: false
chunk: [], eof: true
--- no_error_log
[error]



=== TEST 3: read chunks (user module)
--- http_config
    lua_package_path "$prefix/html/?.lua;;";
--- config
    location /read {
        echo -n hello world;
        echo -n hiya globe;

        body_filter_by_lua '
            local foo = require "foo"
            foo.go()
        ';
    }
--- user_files
>>> foo.lua
module("foo", package.seeall)

function go()
    -- ngx.say("Hello")
    local chunk, eof = ngx.arg[1], ngx.arg[2]
    print("chunk: [", chunk, "], eof: ", eof)
end
--- request
GET /read
--- response_body chop
hello worldhiya globe
--- error_log
chunk: [hello world], eof: false
chunk: [hiya globe], eof: false
chunk: [], eof: true
--- no_error_log
[error]



=== TEST 4: rewrite chunks (upper all)
--- config
    location /t {
        echo hello world;
        echo hiya globe;

        body_filter_by_lua '
            ngx.arg[1] = string.upper(ngx.arg[1])
        ';
    }
--- request
GET /t
--- response_body
HELLO WORLD
HIYA GLOBE
--- no_error_log
[error]



=== TEST 5: rewrite chunks (truncate data)
--- config
    location /t {
        echo hello world;
        echo hiya globe;

        body_filter_by_lua '
            local chunk = ngx.arg[1]
            if string.match(chunk, "hello") then
                ngx.arg[1] = string.upper(chunk)
                ngx.arg[2] = true
                return
            end

            ngx.arg[1] = nil
        ';
    }
--- request
GET /t
--- response_body
HELLO WORLD
--- no_error_log
[error]



=== TEST 6: set eof back and forth
--- config
    location /t {
        echo hello world;
        echo hiya globe;

        body_filter_by_lua '
            local chunk = ngx.arg[1]
            if string.match(chunk, "hello") then
                ngx.arg[1] = string.upper(chunk)
                ngx.arg[2] = true
                ngx.arg[2] = false
                ngx.arg[2] = true
                return
            end

            ngx.arg[1] = nil
            ngx.arg[2] = true
            ngx.arg[2] = false
        ';
    }
--- request
GET /t
--- response_body
HELLO WORLD
--- no_error_log
[error]



=== TEST 7: set eof to original
--- config
    location /t {
        echo hello world;
        echo hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            ngx.arg[2] = eof
        ';
    }
--- request
GET /t
--- response_body
hello world
hiya globe
--- no_error_log
[error]



=== TEST 8: set eof to original
--- config
    location /t {
        echo hello world;
        echo hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            ngx.arg[2] = eof
        ';
    }
--- request
GET /t
--- response_body
hello world
hiya globe
--- no_error_log
[error]



=== TEST 9: fully buffered output (string scalar)
--- config
    location /t {
        echo hello world;
        echo hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            local buf = ngx.ctx.buf

            if eof then
                if buf then
                    ngx.arg[1] = "[" .. buf .. chunk .. "]"
                    return
                end

                return
            end

            if buf then
                ngx.ctx.buf = buf .. chunk
            else
                ngx.ctx.buf = chunk
            end

            ngx.arg[1] = nil
        ';
    }
--- request
GET /t
--- response_body chop
[hello world
hiya globe
]
--- no_error_log
[error]



=== TEST 10: fully buffered output (string table)
--- config
    location /t {
        echo hello world;
        echo hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            local buf = ngx.ctx.buf

            if eof then
                if buf then
                    ngx.arg[1] = {"[", buf, chunk, "]"}
                    return
                end

                return
            end

            if buf then
                ngx.ctx.buf = {buf, chunk}
            else
                ngx.ctx.buf = chunk
            end

            ngx.arg[1] = nil
        ';
    }
--- request
GET /t
--- response_body chop
[hello world
hiya globe
]
--- no_error_log
[error]



=== TEST 11: abort via user error (string)
--- config
    location /t {
        echo hello world;
        echo_flush;
        echo hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            if eof then
                error("something bad happened!")
            end
        ';
    }
--- request
GET /t
--- ignore_response
--- error_log
failed to run body_filter_by_lua*: [string "body_filter_by_lua"]:4: something bad happened!



=== TEST 12: abort via user error (nil)
--- config
    location /t {
        echo hello world;
        echo_flush;
        echo hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            if eof then
                error(nil)
            end
        ';
    }
--- request
GET /t
--- ignore_response
--- error_log
failed to run body_filter_by_lua*: unknown reason



=== TEST 13: abort via return NGX_ERROR
--- config
    location /t {
        echo hello world;
        echo_flush;
        echo hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            if eof then
                return ngx.ERROR
            end
        ';
    }
--- request
GET /t
--- ignore_response
--- no_error_log
[error]



=== TEST 14: using body_filter_by_lua and header_filter_by_lua at the same time
--- config
    location /t {
        content_by_lua '
            ngx.header.content_length = 12
            ngx.say("Hello World")
        ';

        header_filter_by_lua 'ngx.header.content_length = nil';

        body_filter_by_lua '
            ngx.arg[1] = ngx.arg[1] .. "aaa"
        ';
    }
--- request
GET /t
--- response_body chop
Hello World
aaaaaa
--- response_headers
!content-length
--- no_error_log
[error]



=== TEST 15: table arguments to ngx.arg[1] (github issue #54)
--- config
    location /t {
        echo -n hello;

        body_filter_by_lua '
            if ngx.arg[1] ~= "" then
                ngx.arg[1] = {{ngx.arg[1]}, "!", "\\n"}
            end
        ';
    }
--- request
GET /t
--- response_body
hello!
--- no_error_log
[error]



=== TEST 16: fully buffered output (string scalar, buffering to disk by ngx_proxy)
--- config
    location /t {
        proxy_pass http://127.0.0.1:$server_port/stub;
        proxy_buffers 2 256;
        proxy_busy_buffers_size 256;
        proxy_buffer_size 256;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            local buf = ngx.ctx.buf

            if eof then
                if buf then
                    ngx.arg[1] = "[" .. buf .. chunk .. "]"
                    return
                end

                return
            end

            if buf then
                ngx.ctx.buf = buf .. chunk
            else
                ngx.ctx.buf = chunk
            end

            ngx.arg[1] = nil
        ';
    }

    location = /stub {
        echo_duplicate 512 "a";
        echo_duplicate 512 "b";
    }
--- request
GET /t
--- response_body eval
"[" . ("a" x 512) . ("b" x 512) . "]";
--- no_error_log
[error]
--- timeout: 5



=== TEST 17: backtrace
--- config
    location /t {
        body_filter_by_lua '
            function foo()
                bar()
            end

            function bar()
                error("something bad happened")
            end

            foo()
        ';
        echo ok;
    }
--- request
    GET /t
--- ignore_response
--- error_log
something bad happened
stack traceback:
in function 'error'
in function 'bar'
in function 'foo'



=== TEST 18: setting "eof" in subrequests
--- config
    location /t {
        echo_location /read;
        echo_location /read;
    }

    location /read {
        echo -n hello world;
        echo -n hiya globe;

        body_filter_by_lua '
            ngx.arg[2] = 1
        ';
    }
--- request
GET /t
--- response_body chop
hello worldhello world
--- no_error_log
[error]

