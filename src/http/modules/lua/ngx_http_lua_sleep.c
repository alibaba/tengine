#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_util.h"
#include "ngx_http_lua_sleep.h"
#include "ngx_http_lua_contentby.h"


static int ngx_http_lua_ngx_sleep(lua_State *L);
static void ngx_http_lua_sleep_handler(ngx_event_t *ev);


static int
ngx_http_lua_ngx_sleep(lua_State *L)
{
    int                          n;
    ngx_int_t                    delay; /* in msec */
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    n = lua_gettop(L);
    if (n != 1) {
        return luaL_error(L, "attempt to pass %d arguments, but accepted 1", n);
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    delay = luaL_checknumber(L, 1) * 1000;

    if (delay < 0) {
        return luaL_error(L, "invalid sleep duration \"%d\"", delay);
    }

    if (delay == 0) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua sleep for 0ms");
        return 0;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ctx->sleep.handler = ngx_http_lua_sleep_handler;
    ctx->sleep.data = r;
    ctx->sleep.log = r->connection->log;

    dd("adding timer with delay %lu ms, r:%.*s", (unsigned long) delay,
            (int) r->uri.len, r->uri.data);

    ngx_add_timer(&ctx->sleep, (ngx_msec_t) delay);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua ready to sleep for %d ms", delay);

    if (ctx->entered_content_phase) {
        dd("set write event handler");
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    return lua_yield(L, 0);
}


void
ngx_http_lua_sleep_handler(ngx_event_t *ev)
{
    ngx_connection_t        *c;
    ngx_http_request_t      *r;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_log_ctx_t      *log_ctx;

    r = ev->data;
    c = r->connection;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        return;
    }

    log_ctx = c->log->data;
    log_ctx->current_request = r;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua sleep handler: \"%V?%V\"", &r->uri, &r->args);

    if (!ctx->sleep.timedout) {
        dd("reach lua sleep event handler without timeout!");
        return;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua sleep timer expired: \"%V?%V\"", &r->uri, &r->args);

    if (ctx->sleep.timer_set) {
        dd("deleting timer for lua_sleep");
        ngx_del_timer(&ctx->sleep);
    }

    if (ctx->entered_content_phase) {
        ngx_http_lua_wev_handler(r);

    } else {
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

