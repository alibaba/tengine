#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_ctx.h"


int
ngx_http_lua_ngx_get_ctx(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    if (ctx->ctx_ref == LUA_NOREF) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua create ngx.ctx table for the current request");

        lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_REQ_CTX_REF);
        lua_newtable(L);
        lua_pushvalue(L, -1);
        ctx->ctx_ref = luaL_ref(L, -3);
        return 1;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua fetching existing ngx.ctx table for the current request");

    lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_REQ_CTX_REF);
    lua_rawgeti(L, -1, ctx->ctx_ref);

    return 1;
}


int
ngx_http_lua_ngx_set_ctx(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    return ngx_http_lua_ngx_set_ctx_helper(L, r, ctx, 3);
}


int
ngx_http_lua_ngx_set_ctx_helper(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int index)
{
    if (index < 0) {
        index = lua_gettop(L) + index + 1;
    }

    if (ctx->ctx_ref == LUA_NOREF) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua create ngx.ctx table for the current request");

        lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_REQ_CTX_REF);
        lua_pushvalue(L, index);
        ctx->ctx_ref = luaL_ref(L, -2);
        lua_pop(L, 1);
        return 0;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua fetching existing ngx.ctx table for the current request");

    lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_REQ_CTX_REF);
    luaL_unref(L, -1, ctx->ctx_ref);
    lua_pushvalue(L, index);
    ctx->ctx_ref = luaL_ref(L, -2);
    lua_pop(L, 1);

    return 0;
}

