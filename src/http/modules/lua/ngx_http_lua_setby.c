/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_setby.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_time.h"
#include "ngx_http_lua_log.h"
#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_ndk.h"
#include "ngx_http_lua_variable.h"
#include "ngx_http_lua_string.h"
#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_consts.h"
#include "ngx_http_lua_shdict.h"


static void ngx_http_lua_inject_arg_api(lua_State *L,
       size_t nargs,  ngx_http_variable_value_t *args);
static int ngx_http_lua_param_get(lua_State *L);
static void ngx_http_lua_set_by_lua_env(lua_State *L, ngx_http_request_t *r,
        size_t nargs, ngx_http_variable_value_t *args);


ngx_int_t
ngx_http_lua_set_by_chunk(lua_State *L, ngx_http_request_t *r, ngx_str_t *val,
        ngx_http_variable_value_t *args, size_t nargs)
{
    size_t           i;
    ngx_int_t        rc;
    u_char          *err_msg;
    size_t           rlen;
    u_char          *rdata;
#if (NGX_PCRE)
    ngx_pool_t      *old_pool;
#endif

    ngx_http_lua_ctx_t          *ctx;
    ngx_http_cleanup_t          *cln;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));
        if (ctx == NULL) {
            return NGX_ERROR;
        }

        dd("setting new ctx: ctx = %p", ctx);

        ctx->cc_ref = LUA_NOREF;
        ctx->ctx_ref = LUA_NOREF;

        ngx_http_set_ctx(r, ctx, ngx_http_lua_module);

    } else {
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    if (ctx->cleanup == NULL) {
        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            return NGX_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup;
        cln->data = r;
        ctx->cleanup = &cln->handler;
    }

    /*  set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    /*  initialize nginx context in Lua VM, code chunk at stack top    sp = 1 */
    ngx_http_lua_set_by_lua_env(L, r, nargs, args);

    /*  passing directive arguments to the user code */
    for (i = 0; i < nargs; i++) {
        lua_pushlstring(L, (const char *) args[i].data, args[i].len);
    }

#if (NGX_PCRE)
    /* XXX: work-around to nginx regex subsystem */
    old_pool = ngx_http_lua_pcre_malloc_init(r->pool);
#endif

    /*  protected call user code */
    rc = lua_pcall(L, nargs, 1, 0);

#if (NGX_PCRE)
    /* XXX: work-around to nginx regex subsystem */
    ngx_http_lua_pcre_malloc_done(old_pool);
#endif

    if (rc != 0) {
        /*  error occured when running loaded code */
        err_msg = (u_char *) lua_tostring(L, -1);

        if (err_msg != NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-error) %s",
                    err_msg);

            lua_settop(L, 0);    /*  clear remaining elems on stack */
        }

        return NGX_ERROR;
    }

    NGX_LUA_EXCEPTION_TRY {
        rdata = (u_char *) lua_tolstring(L, -1, &rlen);

        if (rdata) {
            val->data = ngx_pcalloc(r->pool, rlen);
            if (val->data == NULL) {
                return NGX_ERROR;
            }

            ngx_memcpy(val->data, rdata, rlen);
            val->len = rlen;

        } else {
            val->data = NULL;
            val->len = 0;
        }

    } NGX_LUA_EXCEPTION_CATCH {
        dd("nginx execution restored");
    }

    /*  clear Lua stack */
    lua_settop(L, 0);

    return NGX_OK;
}


static void
ngx_http_lua_inject_arg_api(lua_State *L, size_t nargs,
        ngx_http_variable_value_t *args)
{
    lua_newtable(L);    /*  .arg table aka {} */

    lua_newtable(L);    /*  the metatable for new param table */
    lua_pushinteger(L, nargs);    /*  1st upvalue: argument number */
    lua_pushlightuserdata(L, args);    /*  2nd upvalue: pointer to arguments */

    lua_pushcclosure(L, ngx_http_lua_param_get, 2);
        /*  binding upvalues to __index meta-method closure */

    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  tie the metatable to param table */

    lua_setfield(L, -2, "arg");    /*  set ngx.arg table */
}


static int
ngx_http_lua_param_get(lua_State *L)
{
    int         idx;
    int         n;

    ngx_http_variable_value_t       *v;

    idx = luaL_checkint(L, 2);

    /*  get number of args from closure */
    n = luaL_checkint(L, lua_upvalueindex(1));

    /*  get args from closure */
    v = lua_touserdata(L, lua_upvalueindex(2));

    if (idx < 0 || idx > n-1) {
        lua_pushnil(L);

    } else {
        lua_pushlstring(L, (const char *) (v[idx].data), v[idx].len);
    }

    return 1;
}


/**
 * Set environment table for the given code closure.
 *
 * Before:
 *         | code closure | <- top
 *         |      ...     |
 *
 * After:
 *         | code closure | <- top
 *         |      ...     |
 * */
static void
ngx_http_lua_set_by_lua_env(lua_State *L, ngx_http_request_t *r, size_t nargs,
        ngx_http_variable_value_t *args)
{
    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    /*  set nginx request pointer to current lua thread's globals table */
    lua_pushlightuserdata(L, r);
    lua_setglobal(L, GLOBALS_SYMBOL_REQUEST);

    /**
     * we want to create empty environment for current script
     *
     * setmetatable({}, {__index = _G})
     *
     * if a function or symbol is not defined in our env, __index will lookup
     * in the global env.
     *
     * all variables created in the script-env will be thrown away at the end
     * of the script run.
     * */
    lua_newtable(L);    /*  new empty environment aka {} */

#if defined(NDK) && NDK
    ngx_http_lua_inject_ndk_api(L);
#endif /* defined(NDK) && NDK */

    /*  {{{ initialize ngx.* namespace */

    lua_createtable(L, 0 /* narr */, 71 /* nrec */);    /*  ngx.* */

    ngx_http_lua_inject_internal_utils(r->connection->log, L);

    ngx_http_lua_inject_core_consts(L);
    ngx_http_lua_inject_http_consts(L);

    ngx_http_lua_inject_log_api(L);
    ngx_http_lua_inject_http_consts(L);
    ngx_http_lua_inject_core_consts(L);
    ngx_http_lua_inject_time_api(L);
    ngx_http_lua_inject_string_api(L);
    ngx_http_lua_inject_variable_api(L);
    ngx_http_lua_inject_req_api_no_io(r->connection->log, L);
    ngx_http_lua_inject_arg_api(L, nargs, args);
#if (NGX_PCRE)
    ngx_http_lua_inject_regex_api(L);
#endif
    ngx_http_lua_inject_shdict_api(lmcf, L);
    ngx_http_lua_inject_misc_api(L);

    lua_setfield(L, -2, "ngx");
    /*  }}} */

    /*  {{{ make new env inheriting main thread's globals table */
    lua_newtable(L);    /*  the metatable for the new env */
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
}

