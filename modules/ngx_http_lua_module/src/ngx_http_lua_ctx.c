
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_util.h"
#include "ngx_http_lua_ctx.h"


typedef struct {
    int              ref;
    lua_State       *vm;
} ngx_http_lua_ngx_ctx_cleanup_data_t;


static ngx_int_t ngx_http_lua_ngx_ctx_add_cleanup(ngx_http_request_t *r,
    int ref);
static void ngx_http_lua_ngx_ctx_cleanup(void *data);


int
ngx_http_lua_ngx_get_ctx(lua_State *L)
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

    if (ctx->ctx_ref == LUA_NOREF) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua create ngx.ctx table for the current request");

        lua_pushliteral(L, ngx_http_lua_ctx_tables_key);
        lua_rawget(L, LUA_REGISTRYINDEX);
        lua_createtable(L, 0 /* narr */, 4 /* nrec */);
        lua_pushvalue(L, -1);
        ctx->ctx_ref = luaL_ref(L, -3);

        if (ngx_http_lua_ngx_ctx_add_cleanup(r, ctx->ctx_ref) != NGX_OK) {
            return luaL_error(L, "no memory");
        }

        return 1;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua fetching existing ngx.ctx table for the current "
                   "request");

    lua_pushliteral(L, ngx_http_lua_ctx_tables_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_rawgeti(L, -1, ctx->ctx_ref);

    return 1;
}


int
ngx_http_lua_ngx_set_ctx(lua_State *L)
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

        lua_pushliteral(L, ngx_http_lua_ctx_tables_key);
        lua_rawget(L, LUA_REGISTRYINDEX);
        lua_pushvalue(L, index);
        ctx->ctx_ref = luaL_ref(L, -2);
        lua_pop(L, 1);

        if (ngx_http_lua_ngx_ctx_add_cleanup(r, ctx->ctx_ref) != NGX_OK) {
            return luaL_error(L, "no memory");
        }

        return 0;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua fetching existing ngx.ctx table for the current "
                   "request");

    lua_pushliteral(L, ngx_http_lua_ctx_tables_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    luaL_unref(L, -1, ctx->ctx_ref);
    lua_pushvalue(L, index);
    ctx->ctx_ref = luaL_ref(L, -2);
    lua_pop(L, 1);

    return 0;
}


#ifndef NGX_LUA_NO_FFI_API
int
ngx_http_lua_ffi_get_ctx_ref(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_HTTP_LUA_FFI_NO_REQ_CTX;
    }

    return ctx->ctx_ref;
}


int
ngx_http_lua_ffi_set_ctx_ref(ngx_http_request_t *r, int ref)
{
    ngx_http_lua_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_HTTP_LUA_FFI_NO_REQ_CTX;
    }

    ctx->ctx_ref = ref;

    if (ngx_http_lua_ngx_ctx_add_cleanup(r, ref) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}
#endif /* NGX_LUA_NO_FFI_API */


static ngx_int_t
ngx_http_lua_ngx_ctx_add_cleanup(ngx_http_request_t *r, int ref)
{
    lua_State                   *L;
    ngx_pool_cleanup_t          *cln;
    ngx_http_lua_ctx_t          *ctx;

    ngx_http_lua_ngx_ctx_cleanup_data_t    *data;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    L = ngx_http_lua_get_lua_vm(r, ctx);

    cln = ngx_pool_cleanup_add(r->pool,
                               sizeof(ngx_http_lua_ngx_ctx_cleanup_data_t));
    if (cln == NULL) {
        return NGX_ERROR;
    }

    cln->handler = ngx_http_lua_ngx_ctx_cleanup;

    data = cln->data;
    data->vm = L;
    data->ref = ref;

    return NGX_OK;
}


static void
ngx_http_lua_ngx_ctx_cleanup(void *data)
{
    lua_State       *L;

    ngx_http_lua_ngx_ctx_cleanup_data_t    *clndata = data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua release ngx.ctx at ref %d", clndata->ref);

    L = clndata->vm;

    lua_pushliteral(L, ngx_http_lua_ctx_tables_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    luaL_unref(L, -1, clndata->ref);
    lua_pop(L, 1);
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
