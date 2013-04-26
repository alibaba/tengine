
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <nginx.h>
#include "ngx_http_lua_accessby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_cache.h"


static ngx_int_t ngx_http_lua_access_by_chunk(lua_State *L,
    ngx_http_request_t *r);


ngx_int_t
ngx_http_lua_access_handler(ngx_http_request_t *r)
{
    ngx_int_t                   rc;
    ngx_http_lua_ctx_t         *ctx;
    ngx_http_lua_loc_conf_t    *llcf;
    ngx_http_lua_main_conf_t   *lmcf;
    ngx_http_phase_handler_t    tmp, *ph, *cur_ph, *last_ph;
    ngx_http_core_main_conf_t  *cmcf;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua access handler, uri:\"%V\" c:%ud", &r->uri,
                   r->main->count);

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    if (!lmcf->postponed_to_access_phase_end) {

        lmcf->postponed_to_access_phase_end = 1;

        cmcf = ngx_http_get_module_main_conf(r, ngx_http_core_module);

        ph = cmcf->phase_engine.handlers;
        cur_ph = &ph[r->phase_handler];

        /* we should skip the post_access phase handler here too */
        last_ph = &ph[cur_ph->next - 2];

        dd("ph cur: %d, ph next: %d", (int) r->phase_handler,
           (int) (cur_ph->next - 2));

#if 0
        if (cur_ph == last_ph) {
            dd("XXX our handler is already the last access phase handler");
        }
#endif

        if (cur_ph < last_ph) {
            dd("swaping the contents of cur_ph and last_ph...");

            tmp = *cur_ph;

            memmove(cur_ph, cur_ph + 1,
                    (last_ph - cur_ph) * sizeof (ngx_http_phase_handler_t));

            *last_ph = tmp;

            r->phase_handler--; /* redo the current ph */

            return NGX_DECLINED;
        }
    }

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->access_handler == NULL) {
        dd("no access handler found");
        return NGX_DECLINED;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    dd("ctx = %p", ctx);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }
    }

    dd("entered? %d", (int) ctx->entered_access_phase);

    if (ctx->entered_access_phase) {
        dd("calling wev handler");
        rc = ctx->resume_handler(r);
        dd("wev handler returns %d", (int) rc);

        if (rc == NGX_ERROR || rc == NGX_DONE || rc >= NGX_OK) {
            return rc;
        }

        return NGX_DECLINED;
    }

    if (ctx->waiting_more_body) {
        dd("WAITING MORE BODY");
        return NGX_DONE;
    }

    if (llcf->force_read_body && !ctx->read_body_done) {
        r->request_body_in_single_buf = 1;
        r->request_body_in_persistent_file = 1;
        r->request_body_in_clean_file = 1;

        rc = ngx_http_read_client_request_body(r,
                                       ngx_http_lua_generic_phase_post_read);

        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
#if (nginx_version < 1002006) ||                                             \
        (nginx_version >= 1003000 && nginx_version < 1003009)
            r->main->count--;
#endif

            return rc;
        }

        if (rc == NGX_AGAIN) {
            ctx->waiting_more_body = 1;
            return NGX_DONE;
        }
    }

    dd("calling access handler");
    return llcf->access_handler(r);
}


ngx_int_t
ngx_http_lua_access_handler_inline(ngx_http_request_t *r)
{
    char                      *err;
    ngx_int_t                  rc;
    lua_State                 *L;
    ngx_http_lua_loc_conf_t   *llcf;
    ngx_http_lua_main_conf_t  *lmcf;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    L = lmcf->lua;

    /*  load Lua inline script (w/ cache) sp = 1 */
    rc = ngx_http_lua_cache_loadbuffer(L, llcf->access_src.value.data,
                                       llcf->access_src.value.len,
                                       llcf->access_src_key,
                                       "access_by_lua", &err,
                                       llcf->enable_code_cache ? 1 : 0);

    if (rc != NGX_OK) {
        if (err == NULL) {
            err = "unknown error";
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to load Lua inlined code: %s", err);

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    return ngx_http_lua_access_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_access_handler_file(ngx_http_request_t *r)
{
    char                      *err;
    u_char                    *script_path;
    ngx_int_t                  rc;
    ngx_str_t                  eval_src;
    lua_State                 *L;
    ngx_http_lua_loc_conf_t   *llcf;
    ngx_http_lua_main_conf_t  *lmcf;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    /* Eval nginx variables in code path string first */
    if (ngx_http_complex_value(r, &llcf->access_src, &eval_src) != NGX_OK) {
        return NGX_ERROR;
    }

    script_path = ngx_http_lua_rebase_path(r->pool, eval_src.data,
                                           eval_src.len);

    if (script_path == NULL) {
        return NGX_ERROR;
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    L = lmcf->lua;

    /*  load Lua script file (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadfile(L, script_path, llcf->access_src_key,
                                     &err, llcf->enable_code_cache ? 1 : 0);

    if (rc != NGX_OK) {
        if (err == NULL) {
            err = "unknown error";
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to load lua inlined code: %s", err);

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*  make sure we have a valid code chunk */
    assert(lua_isfunction(L, -1));

    return ngx_http_lua_access_by_chunk(L, r);
}


static ngx_int_t
ngx_http_lua_access_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    int                  co_ref;
    ngx_int_t            rc;
    lua_State           *co;
    ngx_connection_t    *c;
    ngx_http_lua_ctx_t  *ctx;
    ngx_http_cleanup_t  *cln;

    ngx_http_lua_loc_conf_t     *llcf;

    /*  {{{ new coroutine to handle request */
    co = ngx_http_lua_new_thread(r, L, &co_ref);

    if (co == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "lua: failed to create new coroutine "
                      "to handle request");

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*  move code closure to new coroutine */
    lua_xmove(L, co, 1);

    /*  set closure's env table to new coroutine's globals table */
    lua_pushvalue(co, LUA_GLOBALSINDEX);
    lua_setfenv(co, -2);

    /*  save nginx request in coroutine globals table */
    lua_pushlightuserdata(co, &ngx_http_lua_request_key);
    lua_pushlightuserdata(co, r);
    lua_rawset(co, LUA_GLOBALSINDEX);
    /*  }}} */

    /*  {{{ initialize request context */
    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    dd("ctx = %p", ctx);

    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_http_lua_reset_ctx(r, L, ctx);

    ctx->entered_access_phase = 1;

    ctx->cur_co_ctx = &ctx->entry_co_ctx;
    ctx->cur_co_ctx->co = co;
    ctx->cur_co_ctx->co_ref = co_ref;

    /*  }}} */

    /*  {{{ register request cleanup hooks */
    if (ctx->cleanup == NULL) {
        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup;
        cln->data = r;
        ctx->cleanup = &cln->handler;
    }
    /*  }}} */

    ctx->context = NGX_HTTP_LUA_CONTEXT_ACCESS;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->check_client_abort) {
        r->read_event_handler = ngx_http_lua_rd_check_broken_connection;

    } else {
        r->read_event_handler = ngx_http_block_reading;
    }

    rc = ngx_http_lua_run_thread(L, r, ctx, 0);

    dd("returned %d", (int) rc);

    if (rc == NGX_ERROR || rc >= NGX_OK) {
        return rc;
    }

    c = r->connection;

    if (rc == NGX_AGAIN) {
        rc = ngx_http_lua_run_posted_threads(c, L, r, ctx);

        if (rc == NGX_ERROR || rc == NGX_DONE || rc >= NGX_OK) {
            return rc;
        }

        return NGX_DECLINED;
    }

    if (rc == NGX_DONE) {
        ngx_http_finalize_request(r, NGX_DONE);

        rc = ngx_http_lua_run_posted_threads(c, L, r, ctx);

        if (rc == NGX_ERROR || rc == NGX_DONE || rc >= NGX_OK) {
            return rc;
        }

        return NGX_DECLINED;
    }

    return NGX_DECLINED;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
