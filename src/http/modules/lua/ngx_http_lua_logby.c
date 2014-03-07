
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_logby.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_time.h"
#include "ngx_http_lua_log.h"
#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_variable.h"
#include "ngx_http_lua_string.h"
#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_consts.h"
#include "ngx_http_lua_shdict.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_exception.h"


static ngx_int_t ngx_http_lua_log_by_chunk(lua_State *L, ngx_http_request_t *r);


static void
ngx_http_lua_log_by_lua_env(lua_State *L, ngx_http_request_t *r)
{
    /*  set nginx request pointer to current lua thread's globals table */
    ngx_http_lua_set_req(L, r);

    /**
     * we want to create empty environment for current script
     *
	 * newt = {}
	 * newt["_G"] = newt
     * setmetatable(newt, {__index = _G})
     *
     * if a function or symbol is not defined in our env, __index will lookup
     * in the global env.
     *
     * all variables created in the script-env will be thrown away at the end
     * of the script run.
     * */
    ngx_http_lua_create_new_global_table(L, 0 /* narr */, 1 /* nrec */);

    /*  {{{ make new env inheriting main thread's globals table */
    lua_createtable(L, 0, 1);    /*  the metatable for the new env */
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
}


ngx_int_t
ngx_http_lua_log_handler(ngx_http_request_t *r)
{
    ngx_http_lua_loc_conf_t     *llcf;
    ngx_int_t                    rc;
    lua_State                   *L;
    ngx_http_lua_ctx_t          *ctx;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua log handler, uri:\"%V\" c:%ud", &r->uri,
                   r->main->count);

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->log_handler == NULL) {
        dd("no log handler found");
        return NGX_DECLINED;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    dd("ctx = %p", ctx);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_ERROR;
        }
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_LOG;

    dd("calling log handler");
    rc = llcf->log_handler(r);

    /* we must release the ngx.ctx table here because request cleanup runs
     * before log phase handlers */

    if (ctx->ctx_ref != LUA_NOREF) {
        L = ngx_http_lua_get_lua_vm(r, ctx);
        ngx_http_lua_release_ngx_ctx_table(r->connection->log, L, ctx);
    }

    return rc;
}


ngx_int_t
ngx_http_lua_log_handler_inline(ngx_http_request_t *r)
{
    lua_State                   *L;
    ngx_int_t                    rc;
    ngx_http_lua_loc_conf_t     *llcf;

    dd("log by lua inline");

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    L = ngx_http_lua_get_lua_vm(r, NULL);

    /*  load Lua inline script (w/ cache) sp = 1 */
    rc = ngx_http_lua_cache_loadbuffer(L, llcf->log_src.value.data,
                                       llcf->log_src.value.len,
                                       llcf->log_src_key, "log_by_lua");
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return ngx_http_lua_log_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_log_handler_file(ngx_http_request_t *r)
{
    lua_State                       *L;
    ngx_int_t                        rc;
    u_char                          *script_path;
    ngx_http_lua_loc_conf_t         *llcf;
    ngx_str_t                        eval_src;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (ngx_http_complex_value(r, &llcf->log_src, &eval_src) != NGX_OK) {
        return NGX_ERROR;
    }

    script_path = ngx_http_lua_rebase_path(r->pool, eval_src.data,
                                           eval_src.len);

    if (script_path == NULL) {
        return NGX_ERROR;
    }

    L = ngx_http_lua_get_lua_vm(r, NULL);

    /*  load Lua script file (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadfile(L, script_path, llcf->log_src_key);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return ngx_http_lua_log_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_log_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    ngx_int_t        rc;
    u_char          *err_msg;
    size_t           len;
#if (NGX_PCRE)
    ngx_pool_t      *old_pool;
#endif

    /*  set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    NGX_LUA_EXCEPTION_TRY {

        /* initialize nginx context in Lua VM, code chunk at stack top sp = 1 */
        ngx_http_lua_log_by_lua_env(L, r);

#if (NGX_PCRE)
        /* XXX: work-around to nginx regex subsystem */
        old_pool = ngx_http_lua_pcre_malloc_init(r->pool);
#endif

        lua_pushcfunction(L, ngx_http_lua_traceback);
        lua_insert(L, 1);  /* put it under chunk and args */

        /*  protected call user code */
        rc = lua_pcall(L, 0, 1, 1);

        lua_remove(L, 1);  /* remove traceback function */

#if (NGX_PCRE)
        /* XXX: work-around to nginx regex subsystem */
        ngx_http_lua_pcre_malloc_done(old_pool);
#endif

        if (rc != 0) {
            /*  error occured when running loaded code */
            err_msg = (u_char *) lua_tolstring(L, -1, &len);

            if (err_msg == NULL) {
                err_msg = (u_char *) "unknown reason";
                len = sizeof("unknown reason") - 1;
            }

            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "failed to run log_by_lua*: %*s", len, err_msg);

            lua_settop(L, 0);    /*  clear remaining elems on stack */

            return NGX_ERROR;
        }

    } NGX_LUA_EXCEPTION_CATCH {

        dd("nginx execution restored");
        return NGX_ERROR;
    }

    /*  clear Lua stack */
    lua_settop(L, 0);

    return NGX_OK;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
