
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include <nginx.h>
#include "ngx_http_lua_server_rewriteby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_cache.h"

static ngx_int_t ngx_http_lua_server_rewrite_by_chunk(lua_State *L,
    ngx_http_request_t *r);

ngx_int_t
ngx_http_lua_server_rewrite_handler(ngx_http_request_t *r)
{
    ngx_int_t                    rc;
    lua_State                   *L;
    ngx_http_lua_srv_conf_t     *lscf;
    ngx_http_lua_loc_conf_t     *llcf;
    ngx_http_lua_ctx_t          *ctx;

    /* XXX we need to take into account ngx_rewrite's location dump */
    if (r->uri_changed) {
        return NGX_DECLINED;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua server rewrite handler, uri:\"%V\" c:%ud", &r->uri,
                    r->main->count);

    lscf = ngx_http_get_module_srv_conf(r, ngx_http_lua_module);
    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
    L = ngx_http_lua_get_lua_vm(r, NULL);

    if (lscf->srv.server_rewrite_handler == NULL) {
        dd("no rewrite handler found");
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

    dd("entered? %d", (int) ctx->entered_server_rewrite_phase);

    if (ctx->entered_server_rewrite_phase) {
        dd("rewriteby: calling wev handler");
        rc = ctx->resume_handler(r);
        dd("rewriteby: wev handler returns %d", (int) rc);

        if (rc == NGX_OK) {
            rc = NGX_DECLINED;
        }

        if (rc == NGX_DECLINED) {
            if (r->header_sent) {
                dd("header already sent");

                /* response header was already generated in rewrite_by_lua*,
                 * so it is no longer safe to proceed to later phases
                 * which may generate responses again */

                if (!ctx->eof) {
                    dd("eof not yet sent");

                    rc = ngx_http_lua_send_chain_link(r, ctx, NULL
                                                    /* indicate last_buf */);
                    if (rc == NGX_ERROR || rc > NGX_OK) {
                        return rc;
                    }
                }

                return NGX_HTTP_OK;
            }

            r->write_event_handler = ngx_http_core_run_phases;
            ctx->entered_server_rewrite_phase = 0;

            return NGX_DECLINED;
        }

        return rc;
    }

    if (ctx->waiting_more_body) {
        return NGX_DONE;
    }

    /* TODO: lscf do not have force_read_body */
    if (llcf->force_read_body && !ctx->read_body_done) {
        r->request_body_in_single_buf = 1;
        r->request_body_in_persistent_file = 1;
        r->request_body_in_clean_file = 1;

        rc = ngx_http_read_client_request_body(r,
                                          ngx_http_lua_generic_phase_post_read);

        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return rc;
        }

        if (rc == NGX_AGAIN) {
            ctx->waiting_more_body = 1;
            return NGX_DONE;
        }
    }

    dd("calling server rewrite handler");
    return lscf->srv.server_rewrite_handler(r, lscf, L);
}


ngx_int_t
ngx_http_lua_server_rewrite_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t                    rc;

    dd("server_rewrite by lua inline");


    /*  load Lua inline script (w/ cache) sp = 1 */
    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       lscf->srv.server_rewrite_src.value.data,
                                       lscf->srv.server_rewrite_src.value.len,
                                       &lscf->srv.server_rewrite_src_ref,
                                       lscf->srv.server_rewrite_src_key,
                                       (const char *)
                                       lscf->srv.server_rewrite_chunkname);
    if (rc != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    return ngx_http_lua_server_rewrite_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_server_rewrite_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t                        rc;
    u_char                          *script_path;
    ngx_str_t                        eval_src;


    if (ngx_http_complex_value(r, &lscf->srv.server_rewrite_src,
                               &eval_src) != NGX_OK)
    {
        return NGX_ERROR;
    }

    script_path = ngx_http_lua_rebase_path(r->pool, eval_src.data,
        eval_src.len);

    if (script_path == NULL) {
        return NGX_ERROR;
    }

    /*  load Lua script file (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadfile(r->connection->log, L, script_path,
                                     &lscf->srv.server_rewrite_src_ref,
                                     lscf->srv.server_rewrite_src_key);
    if (rc != NGX_OK) {
        if (rc < NGX_HTTP_SPECIAL_RESPONSE) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        return rc;
    }

    return ngx_http_lua_server_rewrite_by_chunk(L, r);
}


static ngx_int_t
ngx_http_lua_server_rewrite_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    int                      co_ref;
    lua_State               *co;
    ngx_int_t                rc;
    ngx_uint_t               nreqs;
    ngx_event_t             *rev;
    ngx_connection_t        *c;
    ngx_http_lua_ctx_t      *ctx;
    ngx_pool_cleanup_t      *cln;

    ngx_http_lua_loc_conf_t     *llcf;

    /*  {{{ new coroutine to handle request */
    co = ngx_http_lua_new_thread(r, L, &co_ref);

    if (co == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "lua: failed to create new coroutine to handle request");

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*  move code closure to new coroutine */
    lua_xmove(L, co, 1);

#ifndef OPENRESTY_LUAJIT
    /*  set closure's env table to new coroutine's globals table */
    ngx_http_lua_get_globals_table(co);
    lua_setfenv(co, -2);
#endif

    /*  save nginx request in coroutine globals table */
    ngx_http_lua_set_req(co, r);

    /*  {{{ initialize request context */
    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    dd("ctx = %p", ctx);

    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_http_lua_reset_ctx(r, L, ctx);

    ctx->entered_server_rewrite_phase = 1;

    ctx->cur_co_ctx = &ctx->entry_co_ctx;
    ctx->cur_co_ctx->co = co;
    ctx->cur_co_ctx->co_ref = co_ref;
#ifdef NGX_LUA_USE_ASSERT
    ctx->cur_co_ctx->co_top = 1;
#endif

    ngx_http_lua_attach_co_ctx_to_L(co, ctx->cur_co_ctx);

    /*  }}} */

    /*  {{{ register request cleanup hooks */
    if (ctx->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(r->pool, 0);
        if (cln == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup_handler;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;
    }
    /*  }}} */

    ctx->context = NGX_HTTP_LUA_CONTEXT_SERVER_REWRITE;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->check_client_abort) {
        r->read_event_handler = ngx_http_lua_rd_check_broken_connection;

#if (NGX_HTTP_V2)
        if (!r->stream) {
#endif

        rev = r->connection->read;

        if (!rev->active) {
            if (ngx_add_event(rev, NGX_READ_EVENT, 0) != NGX_OK) {
                return NGX_ERROR;
            }
        }

#if (NGX_HTTP_V2)
        }
#endif

    } else {
        r->read_event_handler = ngx_http_block_reading;
    }

    c = r->connection;
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(L, r, ctx, 0);

    if (rc == NGX_ERROR || rc > NGX_OK) {
        return rc;
    }

    if (rc == NGX_AGAIN) {
        rc = ngx_http_lua_run_posted_threads(c, L, r, ctx, nreqs);

    } else if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        rc = ngx_http_lua_run_posted_threads(c, L, r, ctx, nreqs);
    }

    if (rc == NGX_OK || rc == NGX_DECLINED) {
        if (r->header_sent) {
            dd("header already sent");

            /* response header was already generated in rewrite_by_lua*,
             * so it is no longer safe to proceed to later phases
             * which may generate responses again */

            if (!ctx->eof) {
                dd("eof not yet sent");

                rc = ngx_http_lua_send_chain_link(r, ctx, NULL
                                                  /* indicate last_buf */);
                if (rc == NGX_ERROR || rc > NGX_OK) {
                    return rc;
                }
            }

            return NGX_HTTP_OK;
        }

        r->write_event_handler = ngx_http_core_run_phases;
        ctx->entered_server_rewrite_phase = 0;

        return NGX_DECLINED;
    }

    return rc;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
