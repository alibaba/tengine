
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_coroutine.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_probe.h"


/*
 * Design:
 *
 * In order to support using ngx.* API in Lua coroutines, we have to create
 * new coroutine in the main coroutine instead of the calling coroutine
 */


static int ngx_http_lua_coroutine_create(lua_State *L);
static int ngx_http_lua_coroutine_resume(lua_State *L);
static int ngx_http_lua_coroutine_yield(lua_State *L);
static int ngx_http_lua_coroutine_status(lua_State *L);


static const ngx_str_t
    ngx_http_lua_co_status_names[] =
    {
        ngx_string("running"),
        ngx_string("suspended"),
        ngx_string("normal"),
        ngx_string("dead"),
        ngx_string("zombie")
    };



static int
ngx_http_lua_coroutine_create(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    return ngx_http_lua_coroutine_create_helper(L, r, ctx, NULL);
}


int
ngx_http_lua_coroutine_create_helper(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_http_lua_co_ctx_t **pcoctx)
{
    lua_State                     *vm;  /* the Lua VM */
    lua_State                     *co;  /* new coroutine to be created */
    ngx_http_lua_co_ctx_t         *coctx; /* co ctx for the new coroutine */

    luaL_argcheck(L, lua_isfunction(L, 1) && !lua_iscfunction(L, 1), 1,
                 "Lua function expected");

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT
                               | NGX_HTTP_LUA_CONTEXT_TIMER);

    vm = ngx_http_lua_get_lua_vm(r, ctx);

    /* create new coroutine on root Lua state, so it always yields
     * to main Lua thread
     */
    co = lua_newthread(vm);

    ngx_http_lua_probe_user_coroutine_create(r, L, co);

    coctx = ngx_http_lua_get_co_ctx(co, ctx);
    if (coctx == NULL) {
        coctx = ngx_http_lua_create_co_ctx(r, ctx);
        if (coctx == NULL) {
            return luaL_error(L, "no memory");
        }

    } else {
        ngx_memzero(coctx, sizeof(ngx_http_lua_co_ctx_t));
        coctx->co_ref = LUA_NOREF;
    }

    coctx->co = co;
    coctx->co_status = NGX_HTTP_LUA_CO_SUSPENDED;

    /* make new coroutine share globals of the parent coroutine.
     * NOTE: globals don't have to be separated! */
    ngx_http_lua_get_globals_table(L);
    lua_xmove(L, co, 1);
    ngx_http_lua_set_globals_table(co);

    lua_xmove(vm, L, 1);    /* move coroutine from main thread to L */

    lua_pushvalue(L, 1);    /* copy entry function to top of L*/
    lua_xmove(L, co, 1);    /* move entry function from L to co */

    if (pcoctx) {
        *pcoctx = coctx;
    }

#ifdef NGX_LUA_USE_ASSERT
    coctx->co_top = 1;
#endif

    return 1;    /* return new coroutine to Lua */
}


static int
ngx_http_lua_coroutine_resume(lua_State *L)
{
    lua_State                   *co;
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;
    ngx_http_lua_co_ctx_t       *p_coctx; /* parent co ctx */

    co = lua_tothread(L, 1);

    luaL_argcheck(L, co, 1, "coroutine expected");

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT
                               | NGX_HTTP_LUA_CONTEXT_TIMER);

    p_coctx = ctx->cur_co_ctx;
    if (p_coctx == NULL) {
        return luaL_error(L, "no parent co ctx found");
    }

    coctx = ngx_http_lua_get_co_ctx(co, ctx);
    if (coctx == NULL) {
        return luaL_error(L, "no co ctx found");
    }

    ngx_http_lua_probe_user_coroutine_resume(r, L, co);

    if (coctx->co_status != NGX_HTTP_LUA_CO_SUSPENDED) {
        dd("coroutine resume: %d", coctx->co_status);

        lua_pushboolean(L, 0);
        lua_pushfstring(L, "cannot resume %s coroutine",
                        ngx_http_lua_co_status_names[coctx->co_status].data);
        return 2;
    }

    p_coctx->co_status = NGX_HTTP_LUA_CO_NORMAL;

    coctx->parent_co_ctx = p_coctx;

    dd("set coroutine to running");
    coctx->co_status = NGX_HTTP_LUA_CO_RUNNING;

    ctx->co_op = NGX_HTTP_LUA_USER_CORO_RESUME;
    ctx->cur_co_ctx = coctx;

    /* yield and pass args to main thread, and resume target coroutine from
     * there */
    return lua_yield(L, lua_gettop(L) - 1);
}


static int
ngx_http_lua_coroutine_yield(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT
                               | NGX_HTTP_LUA_CONTEXT_TIMER);

    coctx = ctx->cur_co_ctx;

    coctx->co_status = NGX_HTTP_LUA_CO_SUSPENDED;

    ctx->co_op = NGX_HTTP_LUA_USER_CORO_YIELD;

    if (!coctx->is_uthread && coctx->parent_co_ctx) {
        dd("set coroutine to running");
        coctx->parent_co_ctx->co_status = NGX_HTTP_LUA_CO_RUNNING;

        ngx_http_lua_probe_user_coroutine_yield(r, coctx->parent_co_ctx->co, L);

    } else {
        ngx_http_lua_probe_user_coroutine_yield(r, NULL, L);
    }

    /* yield and pass retvals to main thread,
     * and resume parent coroutine there */
    return lua_yield(L, lua_gettop(L));
}


void
ngx_http_lua_inject_coroutine_api(ngx_log_t *log, lua_State *L)
{
    int         rc;

    /* new coroutine table */
    lua_createtable(L, 0 /* narr */, 14 /* nrec */);

    /* get old coroutine table */
    lua_getglobal(L, "coroutine");

    /* set running to the old one */
    lua_getfield(L, -1, "running");
    lua_setfield(L, -3, "running");

    lua_getfield(L, -1, "create");
    lua_setfield(L, -3, "_create");

    lua_getfield(L, -1, "resume");
    lua_setfield(L, -3, "_resume");

    lua_getfield(L, -1, "yield");
    lua_setfield(L, -3, "_yield");

    lua_getfield(L, -1, "status");
    lua_setfield(L, -3, "_status");

    /* pop the old coroutine */
    lua_pop(L, 1);

    lua_pushcfunction(L, ngx_http_lua_coroutine_create);
    lua_setfield(L, -2, "__create");

    lua_pushcfunction(L, ngx_http_lua_coroutine_resume);
    lua_setfield(L, -2, "__resume");

    lua_pushcfunction(L, ngx_http_lua_coroutine_yield);
    lua_setfield(L, -2, "__yield");

    lua_pushcfunction(L, ngx_http_lua_coroutine_status);
    lua_setfield(L, -2, "__status");

    lua_setglobal(L, "coroutine");

    /* inject coroutine APIs */
    {
        const char buf[] =
            "local keys = {'create', 'yield', 'resume', 'status'}\n"
            "local getfenv = getfenv\n"
            "for _, key in ipairs(keys) do\n"
               "local std = coroutine['_' .. key]\n"
               "local ours = coroutine['__' .. key]\n"
               "local raw_ctx = ngx._phase_ctx\n"
               "coroutine[key] = function (...)\n"
                    "local r = getfenv(0).__ngx_req\n"
                    "if r then\n"
                        "local ctx = raw_ctx(r)\n"
                        /* ignore header and body filters */
                        "if ctx ~= 0x020 and ctx ~= 0x040 then\n"
                            "return ours(...)\n"
                        "end\n"
                    "end\n"
                    "return std(...)\n"
                "end\n"
            "end\n"
            "local create, resume = coroutine.create, coroutine.resume\n"
            "coroutine.wrap = function(f)\n"
               "local co = create(f)\n"
               "return function(...) return select(2, resume(co, ...)) end\n"
            "end\n"
            "package.loaded.coroutine = coroutine";

#if 0
            "debug.sethook(function () collectgarbage() end, 'rl', 1)"
#endif
            ;

        rc = luaL_loadbuffer(L, buf, sizeof(buf) - 1, "=coroutine.wrap");
    }

    if (rc != 0) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "failed to load Lua code for coroutine.wrap(): %i: %s",
                      rc, lua_tostring(L, -1));

        lua_pop(L, 1);
        return;
    }

    rc = lua_pcall(L, 0, 0, 0);
    if (rc != 0) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "failed to run the Lua code for coroutine.wrap(): %i: %s",
                      rc, lua_tostring(L, -1));
        lua_pop(L, 1);
    }
}


static int
ngx_http_lua_coroutine_status(lua_State *L)
{
    lua_State                     *co;  /* new coroutine to be created */
    ngx_http_request_t            *r;
    ngx_http_lua_ctx_t            *ctx;
    ngx_http_lua_co_ctx_t         *coctx; /* co ctx for the new coroutine */

    co = lua_tothread(L, 1);

    luaL_argcheck(L, co, 1, "coroutine expected");

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT
                               | NGX_HTTP_LUA_CONTEXT_TIMER);

    coctx = ngx_http_lua_get_co_ctx(co, ctx);
    if (coctx == NULL) {
        lua_pushlstring(L, (const char *)
                        ngx_http_lua_co_status_names[NGX_HTTP_LUA_CO_DEAD].data,
                        ngx_http_lua_co_status_names[NGX_HTTP_LUA_CO_DEAD].len);
        return 1;
    }

    dd("co status: %d", coctx->co_status);

    lua_pushlstring(L, (const char *)
                    ngx_http_lua_co_status_names[coctx->co_status].data,
                    ngx_http_lua_co_status_names[coctx->co_status].len);
    return 1;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
