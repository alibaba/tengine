package t::StapThread;

use strict;
use warnings;

our $GCScript = <<'_EOC_';
global ids, cur
global in_req = 0
global alive_reqs

function gen_id(k) {
    if (ids[k]) return ids[k]
    ids[k] = ++cur
    return cur
}

F(ngx_http_handler) {
    if (!alive_reqs[$r] && $r == $r->main) {
        in_req++
        alive_reqs[$r] = 1

        if (in_req == 1) {
            delete ids
            cur = 0
        }
    }
}

F(ngx_http_free_request) {
    if (alive_reqs[$r]) {
        in_req--
        delete alive_reqs[$r]
    }
}

F(ngx_http_terminate_request) {
    if (alive_reqs[$r]) {
        in_req--
        delete alive_reqs[$r]
    }
}

M(http-lua-user-thread-spawn) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("spawn user thread %x in %x\n", c, p)
}

M(http-lua-thread-delete) {
    t = gen_id($arg2)
    printf("delete thread %x\n", t)
}

M(http-lua-user-coroutine-create) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("create %x in %x\n", c, p)
}

M(http-lua-coroutine-done) {
    t = gen_id($arg2)
    printf("terminate %d: %s\n", t, $arg3 ? "ok" : "fail")
    #print_ubacktrace()
}

_EOC_

our $StapScript = <<'_EOC_';
global ids, cur
global timers
global in_req = 0
global co_status
global alive_reqs

function gen_id(k) {
    if (ids[k]) return ids[k]
    ids[k] = ++cur
    return cur
}

F(ngx_http_handler) {
    if (!alive_reqs[$r] && $r == $r->main) {
        in_req++
        alive_reqs[$r] = 1

        printf("in req: %d\n", in_req)

        if (in_req == 1) {
            delete ids
            cur = 0
            co_status[0] = "running"
            co_status[1] = "suspended"
            co_status[2] = "normal"
            co_status[3] = "dead"
        }
    }
}

F(ngx_http_free_request) {
    if (alive_reqs[$r]) {
        in_req--
        println("free request")
        delete alive_reqs[$r]
    }
}

F(ngx_http_terminate_request) {
    if (alive_reqs[$r]) {
        in_req--
        println("terminate request")
        delete alive_reqs[$r]
    }
}

F(ngx_http_lua_post_thread) {
    id = gen_id($coctx->co)
    printf("post thread %d\n", id)
}

M(timer-add) {
    timers[$arg1] = $arg2
    printf("add timer %d\n", $arg2)
}

M(timer-del) {
    printf("delete timer %d\n", timers[$arg1])
    delete timers[$arg1]
}

M(timer-expire) {
    printf("expire timer %d\n", timers[$arg1])
    delete timers[$arg1]
}

F(ngx_http_lua_sleep_handler) {
    printf("sleep handler called\n")
}

F(ngx_http_lua_run_thread) {
    id = gen_id($ctx->cur_co_ctx->co)
    printf("run thread %d\n", id)
    #if (id == 1) {
        #print_ubacktrace()
    #}
}

probe process("/usr/local/openresty-debug/luajit/lib/libluajit-5.1.so.2").function("lua_resume") {
    id = gen_id($L)
    printf("lua resume %d\n", id)
}

M(http-lua-user-thread-spawn) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("spawn uthread %x in %x\n", c, p)
}

M(http-lua-thread-delete) {
    t = gen_id($arg2)
    uthreads = @cast($arg3, "ngx_http_lua_ctx_t")->uthreads
    printf("delete thread %x (uthreads %d)\n", t, uthreads)
    #print_ubacktrace()
}

M(http-lua-run-posted-thread) {
    t = gen_id($arg2)
    printf("run posted thread %d (status %s)\n", t, co_status[$arg3])
}

M(http-lua-user-coroutine-resume) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("resume %x in %x\n", c, p)
}

M(http-lua-thread-yield) {
    t = gen_id($arg2)
    printf("thread %d yield\n", t)
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

F(ngx_http_lua_run_posted_threads) {
    printf("run posted threads\n")
}

F(ngx_http_finalize_request) {
    printf("finalize request %s: rc:%d c:%d a:%d\n", ngx_http_req_uri($r), $rc, $r->main->count, $r == $r->main);
    #if ($rc == -1) {
        #print_ubacktrace()
    #}
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: %s rc=%d, status=%d a=%d\n", ngx_http_req_uri($r), $rc,
         $r->headers_out->status, $r == $r->main)
    #print_ubacktrace()
}
M(http-subrequest-done) {
    printf("subrequest %s done\n", ngx_http_req_uri($r))
}
M(http-subrequest-wake-parent) {
    printf("subrequest wake parent %s\n", ngx_http_req_uri($r->parent))
}
M(http-lua-user-coroutine-create) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("create %x in %x\n", c, p)
}

F(ngx_http_lua_ngx_exec) { println("exec") }

F(ngx_http_lua_ngx_exit) { println("exit") }
F(ngx_http_lua_ffi_exit) { println("exit") }

F(ngx_http_lua_req_body_cleanup) {
    println("lua req body cleanup")
}

F(ngx_http_read_client_request_body) {
    println("read client request body")
}

F(ngx_http_lua_finalize_coroutines) {
    println("finalize coroutines")
}

F(ngx_http_lua_ngx_exit) {
    println("ngx.exit() called")
}

F(ngx_http_lua_ffi_exit) {
    println("ngx.exit() called")
}

F(ngx_http_lua_sleep_resume) {
    println("lua sleep resume")
}

M(http-lua-coroutine-done) {
    t = gen_id($arg2)
    printf("terminate coro %d: %s, waited by parent:%d, child cocotx: %p\n", t, $arg3 ? "ok" : "fail", $ctx->cur_co_ctx->waited_by_parent, $ctx->cur_co_ctx)
    //print_ubacktrace()
}

F(ngx_http_lua_ngx_echo) {
    println("ngx.print or ngx.say")
}

F(ngx_http_lua_del_all_threads) {
    println("del all threads")
}

/*
M(http-lua-info) {
    msg = user_string($arg1)
    printf("lua info: %s\n", msg)
}
*/

M(http-lua-user-thread-wait) {
    p = gen_id($arg1)
    c = gen_id($arg2)
    printf("lua thread %d waiting on %d, child coctx: %p\n", p, c, $sub_coctx)
}
_EOC_

1;
