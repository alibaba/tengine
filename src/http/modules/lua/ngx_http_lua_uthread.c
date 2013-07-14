
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_uthread.h"
#include "ngx_http_lua_coroutine.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_probe.h"


#if 1
#undef ngx_http_lua_probe_info
#define ngx_http_lua_probe_info(msg)
#endif


static int ngx_http_lua_uthread_spawn(lua_State *L);
static int ngx_http_lua_uthread_wait(lua_State *L);


void
ngx_http_lua_inject_uthread_api(ngx_log_t *log, lua_State *L)
{
    /* new thread table */
    lua_newtable(L);

    lua_pushcfunction(L, ngx_http_lua_uthread_spawn);
    lua_setfield(L, -2, "spawn");

    lua_pushcfunction(L, ngx_http_lua_uthread_wait);
    lua_setfield(L, -2, "wait");

    lua_setfield(L, -2, "thread");
}


static int
ngx_http_lua_uthread_spawn(lua_State *L)
{
    int                           n;
    ngx_http_request_t           *r;
    ngx_http_lua_ctx_t           *ctx;
    ngx_http_lua_co_ctx_t        *coctx = NULL;

    n = lua_gettop(L);

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_coroutine_create_helper(L, r, ctx, &coctx);

    /* anchor the newly created coroutine into the Lua registry */

    lua_pushlightuserdata(L, &ngx_http_lua_coroutines_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushvalue(L, -2);
    coctx->co_ref = luaL_ref(L, -2);
    lua_pop(L, 1);

    if (n > 1) {
        lua_replace(L, 1);
        lua_xmove(L, coctx->co, n - 1);
    }

    coctx->is_uthread = 1;
    ctx->uthreads++;

    coctx->co_status = NGX_HTTP_LUA_CO_RUNNING;
    ctx->co_op = NGX_HTTP_LUA_USER_THREAD_RESUME;

    ctx->cur_co_ctx->thread_spawn_yielded = 1;

    if (ngx_http_lua_post_thread(r, ctx, ctx->cur_co_ctx) != NGX_OK) {
        return luaL_error(L, "out of memory");
    }

    coctx->parent_co_ctx = ctx->cur_co_ctx;
    ctx->cur_co_ctx = coctx;

    ngx_http_lua_probe_user_thread_spawn(r, L, coctx->co);

    return lua_yield(L, 1);
}


static int
ngx_http_lua_uthread_wait(lua_State *L)
{
    int                          i, nargs, nrets;
    lua_State                   *sub_co;
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx, *sub_coctx;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    coctx = ctx->cur_co_ctx;

    nargs = lua_gettop(L);

    for (i = 1; i <= nargs; i++) {
        sub_co = lua_tothread(L, i);

        luaL_argcheck(L, sub_co, i, "lua thread expected");

        sub_coctx = ngx_http_lua_get_co_ctx(sub_co, ctx);
        if (sub_coctx == NULL) {
            return luaL_error(L, "no co ctx found for the ngx.thread "
                              "instance given");
        }

        if (!sub_coctx->is_uthread) {
            return luaL_error(L, "attempt to wait on a coroutine that is "
                              "not a user thread");
        }

        if (sub_coctx->parent_co_ctx != coctx) {
            return luaL_error(L, "only the parent coroutine can wait on the "
                              "thread");
        }

        switch (sub_coctx->co_status) {
        case NGX_HTTP_LUA_CO_ZOMBIE:

            ngx_http_lua_probe_info("found zombie child");

            nrets = lua_gettop(sub_coctx->co);

            dd("child retval count: %d, %s: %s", n,
                    luaL_typename(sub_coctx->co, -1),
                    lua_tostring(sub_coctx->co, -1));

            if (nrets) {
                lua_xmove(sub_coctx->co, L, nrets);
            }

#if 1
            ngx_http_lua_del_thread(r, L, ctx, sub_coctx);
            ctx->uthreads--;
#endif

            return nrets;

        default:
            /* still alive */
            break;
        }

        ngx_http_lua_probe_user_thread_wait(L, sub_coctx->co);
        sub_coctx->waited_by_parent = 1;
    }

    return lua_yield(L, 0);
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
