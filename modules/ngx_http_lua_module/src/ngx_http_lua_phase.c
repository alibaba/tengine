
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_phase.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_ctx.h"


static int ngx_http_lua_ngx_get_phase(lua_State *L);


static int
ngx_http_lua_ngx_get_phase(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    r = ngx_http_lua_get_req(L);

    /* If we have no request object, assume we are called from the "init"
     * phase. */

    if (r == NULL) {
        lua_pushliteral(L, "init");
        return 1;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    switch (ctx->context) {
    case NGX_HTTP_LUA_CONTEXT_SET:
        lua_pushliteral(L, "set");
        break;

    case NGX_HTTP_LUA_CONTEXT_REWRITE:
        lua_pushliteral(L, "rewrite");
        break;

    case NGX_HTTP_LUA_CONTEXT_ACCESS:
        lua_pushliteral(L, "access");
        break;

    case NGX_HTTP_LUA_CONTEXT_CONTENT:
        lua_pushliteral(L, "content");
        break;

    case NGX_HTTP_LUA_CONTEXT_LOG:
        lua_pushliteral(L, "log");
        break;

    case NGX_HTTP_LUA_CONTEXT_HEADER_FILTER:
        lua_pushliteral(L, "header_filter");
        break;

    case NGX_HTTP_LUA_CONTEXT_BODY_FILTER:
        lua_pushliteral(L, "body_filter");
        break;

    case NGX_HTTP_LUA_CONTEXT_TIMER:
        lua_pushliteral(L, "timer");
        break;

    default:
        return luaL_error(L, "unknown phase: %d", (int) ctx->context);
    }

    return 1;
}


void
ngx_http_lua_inject_phase_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_get_phase);
    lua_setfield(L, -2, "get_phase");
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
