
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <nginx.h>
#include "ngx_http_lua_capturefilter.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_subrequest.h"


ngx_http_output_header_filter_pt ngx_http_lua_next_header_filter;
ngx_http_output_body_filter_pt ngx_http_lua_next_body_filter;


static ngx_int_t ngx_http_lua_capture_header_filter(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_capture_body_filter(ngx_http_request_t *r,
    ngx_chain_t *in);


ngx_int_t
ngx_http_lua_capture_filter_init(ngx_conf_t *cf)
{
    /* setting up output filters to intercept subrequest responses */
    ngx_http_lua_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_lua_capture_header_filter;

    ngx_http_lua_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_lua_capture_body_filter;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_capture_header_filter(ngx_http_request_t *r)
{
    ngx_http_post_subrequest_t      *psr;
    ngx_http_lua_ctx_t              *old_ctx;
    ngx_http_lua_ctx_t              *ctx;

    ngx_http_lua_post_subrequest_data_t      *psr_data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua capture header filter, uri \"%V\"", &r->uri);

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    dd("old ctx: %p", ctx);

    if (ctx == NULL || ! ctx->capture) {

        psr = r->post_subrequest;

        if (psr != NULL
            && psr->handler == ngx_http_lua_post_subrequest
            && psr->data != NULL)
        {
            /* the lua ctx has been cleared by ngx_http_internal_redirect,
             * resume it from the post_subrequest data
             */
            psr_data = psr->data;

            old_ctx = psr_data->ctx;

            if (ctx == NULL) {
                ctx = old_ctx;
                ngx_http_set_ctx(r, ctx, ngx_http_lua_module);

            } else {
                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "lua restoring ctx with capture %d, index %d",
                               old_ctx->capture, old_ctx->index);

                ctx->capture = old_ctx->capture;
                ctx->index = old_ctx->index;
                ctx->body = NULL;
                ctx->last_body = &ctx->body;
                psr_data->ctx = ctx;
            }
        }
    }

    if (ctx && ctx->capture) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua capturing response body");

        /* force subrequest response body buffer in memory */
        r->filter_need_in_memory = 1;
        r->header_sent = 1;
        ctx->header_sent = 1;

        if (r->method == NGX_HTTP_HEAD) {
            r->header_only = 1;
        }

        return NGX_OK;
    }

    return ngx_http_lua_next_header_filter(r);
}


static ngx_int_t
ngx_http_lua_capture_body_filter(ngx_http_request_t *r, ngx_chain_t *in)
{
    int                              rc;
    ngx_int_t                        eof;
    ngx_http_lua_ctx_t              *ctx;
    ngx_http_lua_ctx_t              *pr_ctx;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua capture body filter, uri \"%V\"", &r->uri);

    if (in == NULL) {
        return ngx_http_lua_next_body_filter(r, NULL);
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (!ctx || !ctx->capture) {
        dd("no ctx or no capture %.*s", (int) r->uri.len, r->uri.data);

        return ngx_http_lua_next_body_filter(r, in);
    }

    if (ctx->run_post_subrequest) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua body filter skipped because post subrequest "
                       "already run");
        return NGX_OK;
    }

    if (r->parent == NULL) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua body filter skipped because no parent request "
                       "found");

        return NGX_ERROR;
    }

    pr_ctx = ngx_http_get_module_ctx(r->parent, ngx_http_lua_module);
    if (pr_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua capture body filter capturing response body, uri "
                   "\"%V\"", &r->uri);

    rc = ngx_http_lua_add_copy_chain(r, pr_ctx, &ctx->last_body, in, &eof);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    dd("add copy chain eof: %d, sr: %d", (int) eof, r != r->main);

    if (eof) {
        ctx->seen_last_for_subreq = 1;
    }

    ngx_http_lua_discard_bufs(r->pool, in);

    return NGX_OK;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
