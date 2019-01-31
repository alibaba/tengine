# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    $ENV{TEST_NGINX_POSTPONE_OUTPUT} = 1;
}

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * 60;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: flush wait - content
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(true)
            if not ok then
                ngx.log(ngx.ERR, "flush failed: ", err)
                return
            end
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- response_body
hello, world
hiya
--- no_error_log
[error]
--- error_log
lua reuse free buf chain, but reallocate memory because 5 >= 0



=== TEST 2: flush no wait - content
--- config
    send_timeout 500ms;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(false)
            if not ok then
                ngx.log(ngx.ERR, "flush failed: ", err)
                return
            end
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- response_body
hello, world
hiya



=== TEST 3: flush wait - rewrite
--- config
    location /test {
        rewrite_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
        ';
        content_by_lua return;
    }
--- request
GET /test
--- response_body
hello, world
hiya



=== TEST 4: flush no wait - rewrite
--- config
    location /test {
        rewrite_by_lua '
            ngx.say("hello, world")
            ngx.flush(false)
            ngx.say("hiya")
        ';
        content_by_lua return;
    }
--- request
GET /test
--- response_body
hello, world
hiya



=== TEST 5: http 1.0 (sync)
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
            ngx.flush(true)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
Content-Length: 23
--- timeout: 5
--- error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op



=== TEST 6: http 1.0 (async)
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(false)
            if not ok then
                ngx.log(ngx.WARN, "1: failed to flush: ", err)
            end
            ngx.say("hiya")
            local ok, err = ngx.flush(false)
            if not ok then
                ngx.log(ngx.WARN, "2: failed to flush: ", err)
            end
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
Content-Length: 23
--- error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op
1: failed to flush: buffering
2: failed to flush: buffering
--- timeout: 5



=== TEST 7: flush wait - big data
--- config
    location /test {
        content_by_lua '
            ngx.say(string.rep("a", 1024 * 64))
            ngx.flush(true)
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- response_body
hello, world
hiya
--- SKIP



=== TEST 8: flush wait - content
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.flush(true)
        ';
    }
    location /sub {
        echo sub;
    }
--- request
GET /test
--- response_body
hello, world
sub



=== TEST 9: http 1.0 (sync + buffering off)
--- config
    lua_http10_buffering off;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
            ngx.flush(true)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
!Content-Length
--- timeout: 5
--- no_error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op



=== TEST 10: http 1.0 (async)
--- config
    lua_http10_buffering on;
    location /test {
        lua_http10_buffering off;
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(false)
            ngx.say("hiya")
            ngx.flush(false)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
!Content-Length
--- no_error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op
--- timeout: 5



=== TEST 11: http 1.0 (sync) - buffering explicitly off
--- config
    location /test {
        lua_http10_buffering on;
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
            ngx.flush(true)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
Content-Length: 23
--- timeout: 5
--- error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op



=== TEST 12: http 1.0 (async) - buffering explicitly off
--- config
    location /test {
        lua_http10_buffering on;
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(false)
            ngx.say("hiya")
            ngx.flush(false)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
Content-Length: 23
--- error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op
--- timeout: 5



=== TEST 13: flush wait in a user coroutine
--- config
    location /test {
        content_by_lua '
            local function f()
                ngx.say("hello, world")
                ngx.flush(true)
                coroutine.yield()
                ngx.say("hiya")
            end
            local c = coroutine.create(f)
            ngx.say(coroutine.resume(c))
            ngx.say(coroutine.resume(c))
        ';
    }
--- request
GET /test
--- stap2
F(ngx_http_lua_wev_handler) {
    printf("wev handler: wev:%d\n", $r->connection->write->ready)
}

global ids, cur

function gen_id(k) {
    if (ids[k]) return ids[k]
    ids[k] = ++cur
    return cur
}

F(ngx_http_handler) {
    delete ids
    cur = 0
}

/*
F(ngx_http_lua_run_thread) {
    id = gen_id($ctx->cur_co)
    printf("run thread %d\n", id)
}

probe process("/usr/local/openresty-debug/luajit/lib/libluajit-5.1.so.2").function("lua_resume") {
    id = gen_id($L)
    printf("lua resume %d\n", id)
}
*/

M(http-lua-user-coroutine-resume) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("resume %x in %x\n", c, p)
}

M(http-lua-entry-coroutine-yield) {
    println("entry coroutine yield")
}

/*
F(ngx_http_lua_coroutine_yield) {
    printf("yield %x\n", gen_id($L))
}
*/

M(http-lua-user-coroutine-yield) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("yield %x in %x\n", c, p)
}

F(ngx_http_lua_atpanic) {
    printf("lua atpanic(%d):", gen_id($L))
    print_ubacktrace();
}

M(http-lua-user-coroutine-create) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("create %x in %x\n", c, p)
}

F(ngx_http_lua_ngx_exec) { println("exec") }

F(ngx_http_lua_ngx_exit) { println("exit") }

F(ngx_http_writer) { println("http writer") }

--- response_body
hello, world
true
hiya
true
--- error_log
lua reuse free buf memory 13 >= 5



=== TEST 14: flush before sending out the header
--- config
    location /test {
        content_by_lua '
            ngx.flush()
            ngx.status = 404
            ngx.say("not found")
        ';
    }
--- request
GET /test
--- response_body
not found
--- error_code: 404
--- no_error_log
[error]



=== TEST 15: flush wait - gzip
--- config
    gzip             on;
    gzip_min_length  1;
    gzip_types       text/plain;

    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(true)
            if not ok then
                ngx.log(ngx.ERR, "flush failed: ", err)
                return
            end
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- more_headers
Accept-Encoding: gzip
--- response_body_like: .{15}
--- response_headers
Content-Encoding: gzip
--- no_error_log
[error]



=== TEST 16: flush wait - gunzip
--- config
    location /test {
        gunzip on;
        content_by_lua '
            local f, err = io.open(ngx.var.document_root .. "/gzip.bin", "r")
            if not f then
                ngx.say("failed to open file: ", err)
                return
            end
            local data = f:read(100)
            ngx.header.content_encoding = "gzip"
            ngx.print(data)
            local ok, err = ngx.flush(true)
            if not ok then
                ngx.log(ngx.ERR, "flush failed: ", err)
                return
            end
            data = f:read("*a")
            ngx.print(data)
        ';
    }
--- user_files eval
">>> gzip.bin
\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03\x62\x64\x62\x62\x61\x62\x64\x63\x61\xe4\xe0\xe2\xe6\xe4\x61\xe4\xe4\xe7\x63\x12\xe4\xe1\xe0\x60\x14\x12\xe3\x91\xe4\xe4\xe4\x13\x60\xe3\x95\x12\x90\x15\xe0\x11\x50\x92\xd1\x16\x17\xe2\xd3\x17\x14\x11\x95\x95\x57\x96\x63\x37\xd2\x36\xd6\x51\x34\xb1\xe6\x62\x17\x95\xb0\x77\x60\xe3\x96\x33\x95\xb6\x91\x75\x97\x30\xe4\x66\x0c\xd0\xe3\xe0\xb5\xd3\x33\xf6\x90\x16\xb2\x90\x77\x56\x31\xe7\x55\x32\x11\x74\xe0\x02\x00\x00\x00\xff\xff\xcb\xc8\xac\x4c\xe4\x02\x00\x19\x15\xa9\x77\x6a\x00\x00\x00"
--- request
GET /test
--- ignore_response
--- no_error_log
[error]



=== TEST 17: limit_rate
--- config
    location /test {
        limit_rate 150;
        content_by_lua '
            local begin = ngx.now()
            for i = 1, 2 do
                ngx.print(string.rep("a", 100))
                local ok, err = ngx.flush(true)
                if not ok then
                    ngx.log(ngx.ERR, "failed to flush: ", err)
                end
            end
            local elapsed = ngx.now() - begin
            ngx.log(ngx.WARN, "lua writes elapsed ", elapsed, " sec")
        ';
    }
--- request
GET /test
--- response_body eval
"a" x 200
--- error_log eval
[
qr/lua writes elapsed [12](?:\.\d+)? sec/,
qr/lua flush requires waiting: buffered 0x[0-9a-f]+, delayed:1/,
]

--- no_error_log
[error]
--- timeout: 4
