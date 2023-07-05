# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 11);

#no_diff();
no_long_string();

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
failed to run body_filter_by_lua*: body_filter_by_lua(nginx.conf:49):4: something bad happened!



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
            local bar
            local function foo()
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



=== TEST 19: Lua file does not exist
--- config
    location /lua {
        echo ok;
        body_filter_by_lua_file html/test2.lua;
    }
--- user_files
>>> test.lua
v = ngx.var["request_uri"]
ngx.print("request_uri: ", v, "\n")
--- request
GET /lua?a=1&b=2
--- ignore_response
--- error_log eval
qr/failed to load external Lua file ".*?test2\.lua": cannot open .*? No such file or directory/



=== TEST 20: overwrite eof
--- config
    location /read {
        return 200 "hello world";

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            if eof then
                ngx.arg[2] = false
            end
        ';
    }

    location = /t {
        content_by_lua '
            local res = ngx.location.capture("/read")
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /t
--- response_body
truncated: true
--- no_error_log
[error]
[alert]



=== TEST 21: zero-size bufs
--- config
    location = /t {
        echo hello;
        echo world;

        body_filter_by_lua '
            ngx.arg[1] = ""
        ';
    }
--- request
GET /t
--- response_body
--- no_error_log
[error]
[alert]



=== TEST 22: body filter + ngx.say() (github issue #386)
--- config
    postpone_output 1;
    location = /t {
        header_filter_by_lua 'ngx.header.content_length = nil';

        body_filter_by_lua '
            -- do return end
            if not ngx.ctx.chunks then
                ngx.ctx.chunks = {}
            end

            table.insert(ngx.ctx.chunks, ngx.arg[1])
            print("got chunk ", ngx.arg[1])
            ngx.arg[1] = nil

            if ngx.arg[2] then
                print("seen eof: ", string.upper(table.concat(ngx.ctx.chunks)))
                ngx.arg[1] = string.upper(table.concat(ngx.ctx.chunks))
            end
        ';

        content_by_lua '
            for i = 1, 10 do
                assert(ngx.say("hello world"))
            end
        ';
    }
--- request
GET /t
--- response_body eval
"HELLO WORLD\n" x 10

--- stap2
global active = 1
F(ngx_http_lua_body_filter_by_chunk) {
    printf("body filter by lua: %p: %s\n", $in, ngx_chain_dump($in))
}

F(ngx_http_write_filter) {
    printf("write filter: %p: %s\n", $in, ngx_chain_dump($in))
}


F(ngx_output_chain) {
    #printf("ctx->in: %s\n", ngx_chain_dump($ctx->in))
    #printf("ctx->busy: %s\n", ngx_chain_dump($ctx->busy))
    printf("output chain %p: %s\n", $in, ngx_chain_dump($in))
}
F(ngx_linux_sendfile_chain) {
    printf("linux sendfile chain: %s\n", ngx_chain_dump($in))
}
F(ngx_chain_writer) {
    printf("chain writer ctx out: %p\n", $data)
    printf("nginx chain writer: %s\n", ngx_chain_dump($in))
}
probe syscall.writev {
    if (active && pid() == target()) {
        printf("writev(%s)", ngx_iovec_dump($vec, $vlen))
        /*
        for (i = 0; i < $vlen; i++) {
            printf(" %p [%s]", $vec[i]->iov_base, text_str(user_string_n($vec[i]->iov_base, $vec[i]->iov_len)))
        }
        */
    }
}
probe syscall.writev.return {
    if (active && pid() == target()) {
        printf(" = %s\n", retstr)
    }
}

--- stap_out2
--- no_error_log
[error]
[alert]



=== TEST 23: body filter + ngx.say() (github issue #386), with flush
--- config
    location = /t {
        header_filter_by_lua 'ngx.header.content_length = nil';

        body_filter_by_lua '
            -- do return end
            if not ngx.ctx.chunks then
                ngx.ctx.chunks = {}
            end

            table.insert(ngx.ctx.chunks, ngx.arg[1])
            print("got chunk ", ngx.arg[1])
            ngx.arg[1] = nil

            if ngx.arg[2] then
                print("seen eof: ", string.upper(table.concat(ngx.ctx.chunks)))
                ngx.arg[1] = string.upper(table.concat(ngx.ctx.chunks))
            end
        ';

        content_by_lua '
            for i = 1, 10 do
                assert(ngx.say("hello world"))
                ngx.flush(true)
            end
        ';
    }
--- request
GET /t
--- response_body eval
"HELLO WORLD\n" x 10

--- stap
F(ngx_http_write_filter) {
    for (cl = $in; cl; cl = @cast(cl, "ngx_chain_t")->next) {
        if (@cast(cl, "ngx_chain_t")->buf->flush) {
            printf("seen flush buf.\n")
        }

        if (@cast(cl, "ngx_chain_t")->buf->last_buf) {
            printf("seen last buf.\n")
        }
    }
}

--- stap_out_like eval
qr/^(?:seen flush buf\.
){10,}seen last buf\.
$/

--- stap2
global active = 1
F(ngx_http_lua_body_filter_by_chunk) {
    printf("body filter by lua: %p: %s\n", $in, ngx_chain_dump($in))
}

F(ngx_http_write_filter) {
    printf("write filter: %p: %s\n", $in, ngx_chain_dump($in))
}

F(ngx_http_charset_body_filter) {
    printf("charset body filter: %p: %s\n", $in, ngx_chain_dump($in))
}

F(ngx_output_chain) {
    #printf("ctx->in: %s\n", ngx_chain_dump($ctx->in))
    #printf("ctx->busy: %s\n", ngx_chain_dump($ctx->busy))
    printf("output chain %p: %s\n", $in, ngx_chain_dump($in))
}

F(ngx_linux_sendfile_chain) {
    printf("linux sendfile chain: %s\n", ngx_chain_dump($in))
}

F(ngx_chain_writer) {
    printf("chain writer ctx out: %p\n", $data)
    printf("nginx chain writer: %s\n", ngx_chain_dump($in))
}

probe syscall.writev {
    if (active && pid() == target()) {
        printf("writev(%s)", ngx_iovec_dump($vec, $vlen))
        /*
        for (i = 0; i < $vlen; i++) {
            printf(" %p [%s]", $vec[i]->iov_base, text_str(user_string_n($vec[i]->iov_base, $vec[i]->iov_len)))
        }
        */
    }
}

probe syscall.writev.return {
    if (active && pid() == target()) {
        printf(" = %s\n", retstr)
    }
}

--- stap_out2
--- no_error_log
[error]
[alert]



=== TEST 24: clear ngx.arg[1] and then read it
--- config
    location /t {
        echo hello;
        echo world;

        body_filter_by_lua '
            ngx.arg[1] = nil
            local data = ngx.arg[1]
            print([[data chunk: "]], data, [["]])

            ngx.arg[1] = ""
            data = ngx.arg[1]
            print([[data chunk 2: "]], data, [["]])
        ';
    }
--- request
GET /t
--- response_body
--- log_level: info
--- grep_error_log eval: qr/data chunk(?: \d+)?: [^,]+/
--- grep_error_log_out
data chunk: ""
data chunk 2: ""
data chunk: ""
data chunk 2: ""
data chunk: ""
data chunk 2: ""
--- no_error_log
[error]
[alert]



=== TEST 25: clear ngx.arg[1] and then read ngx.arg[2]
--- config
    location /t {
        echo hello;
        echo world;

        body_filter_by_lua '
            ngx.arg[1] = nil
            local eof = ngx.arg[2]
            print([[eof: ]], eof)

            ngx.arg[1] = ""
            eof = ngx.arg[2]
            print([[eof 2: ]], eof)
        ';
    }
--- request
GET /t
--- response_body
--- log_level: info
--- grep_error_log eval: qr/eof(?: \d+)?: [^,]+/
--- grep_error_log_out
eof: false
eof 2: false
eof: false
eof 2: false
eof: true
eof 2: true

--- no_error_log
[error]
[alert]



=== TEST 26: no ngx.print
--- config
    location /lua {
        echo ok;
        body_filter_by_lua "ngx.print(32) return 1";
    }
--- request
GET /lua
--- ignore_response
--- error_log
API disabled in the context of body_filter_by_lua*



=== TEST 27: syntax error in body_filter_by_lua_block
--- config
    location /lua {

        body_filter_by_lua_block {
            'for end';
        }
        content_by_lua_block {
            ngx.say("Hello world")
        }
    }
--- request
GET /lua
--- ignore_response
--- error_log
failed to load inlined Lua code: body_filter_by_lua(nginx.conf:41):2: unexpected symbol near ''for end''
--- no_error_log
no_such_error1
no_such_error2



=== TEST 28: syntax error in second body_by_lua_block
--- config
    location /foo {
        body_filter_by_lua_block {
            'for end';
        }
        content_by_lua_block {
            ngx.say("Hello world")
        }
    }

    location /lua {
        body_filter_by_lua_block {
            'for end';
        }
        content_by_lua_block {
            ngx.say("Hello world")
        }
    }
--- request
GET /lua
--- ignore_response
--- error_log
failed to load inlined Lua code: body_filter_by_lua(nginx.conf:49):2: unexpected symbol near ''for end''
--- no_error_log
no_such_error1
no_such_error2
