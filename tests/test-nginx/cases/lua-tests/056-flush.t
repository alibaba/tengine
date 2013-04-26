# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    $ENV{TEST_NGINX_POSTPONE_OUTPUT} = 1;
}

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * 44;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: flush wait - content
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- response_body
hello, world
hiya
--- error_log
lua reuse free buf memory 13 >= 5



=== TEST 2: flush no wait - content
--- config
    send_timeout 500ms;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(false)
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
            function f()
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

