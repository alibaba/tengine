
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_util.h"
#include "ngx_http_lua_sleep.h"
#include "ngx_http_lua_contentby.h"


static int ngx_http_lua_ngx_sleep(lua_State *L);
static void ngx_http_lua_sleep_handler(ngx_event_t *ev);
static void ngx_http_lua_sleep_cleanup(void *data);
static ngx_int_t ngx_http_lua_sleep_resume(ngx_http_request_t *r);


static int
ngx_http_lua_ngx_sleep(lua_State *L)
{
    int                          n;
    ngx_int_t                    delay; /* in msec */
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    n = lua_gettop(L);
    if (n != 1) {
        return luaL_error(L, "attempt to pass %d arguments, but accepted 1", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    delay = (ngx_int_t) (luaL_checknumber(L, 1) * 1000);

    if (delay < 0) {
        return luaL_error(L, "invalid sleep duration \"%d\"", delay);
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
    if (coctx == NULL) {
        return luaL_error(L, "no co ctx found");
    }

    coctx->data = r;

    coctx->sleep.handler = ngx_http_lua_sleep_handler;
    coctx->sleep.data = coctx;
    coctx->sleep.log = r->connection->log;

    dd("adding timer with delay %lu ms, r:%.*s", (unsigned long) delay,
       (int) r->uri.len, r->uri.data);

    ngx_add_timer(&coctx->sleep, (ngx_msec_t) delay);

    coctx->cleanup = ngx_http_lua_sleep_cleanup;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua ready to sleep for %d ms", delay);

    return lua_yield(L, 0);
}


void
ngx_http_lua_sleep_handler(ngx_event_t *ev)
{
    ngx_connection_t        *c;
    ngx_http_request_t      *r;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_log_ctx_t      *log_ctx;
    ngx_http_lua_co_ctx_t   *coctx;

    coctx = ev->data;

    r = coctx->data;
    c = r->connection;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        return;
    }

    log_ctx = c->log->data;
    log_ctx->current_request = r;

    coctx->cleanup = NULL;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua sleep timer expired: \"%V?%V\"", &r->uri, &r->args);

    ctx->cur_co_ctx = coctx;

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_sleep_resume(r);

    } else {
        ctx->resume_handler = ngx_http_lua_sleep_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
}


void
ngx_http_lua_inject_sleep_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_sleep);
    lua_setfield(L, -2, "sleep");
}


static void
ngx_http_lua_sleep_cleanup(void *data)
{
    ngx_http_lua_co_ctx_t          *coctx = data;

    if (coctx->sleep.timer_set) {
        dd("cleanup: deleting timer for ngx.sleep");

        ngx_del_timer(&coctx->sleep);
    }
}


static ngx_int_t
ngx_http_lua_sleep_resume(ngx_http_request_t *r)
{
    lua_State                   *vm;
    ngx_connection_t            *c;
    ngx_int_t                    rc;
    ngx_http_lua_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);

    rc = ngx_http_lua_run_thread(vm, r, ctx, 0);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx);
    }

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
