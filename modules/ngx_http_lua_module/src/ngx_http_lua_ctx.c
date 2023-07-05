
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_util.h"
#include "ngx_http_lua_ssl.h"
#include "ngx_http_lua_ctx.h"


typedef struct {
    int              ref;
    lua_State       *vm;
} ngx_http_lua_ngx_ctx_cleanup_data_t;


static ngx_int_t ngx_http_lua_ngx_ctx_add_cleanup(ngx_http_request_t *r,
    ngx_pool_t *pool, int ref);
static void ngx_http_lua_ngx_ctx_cleanup(void *data);


int
ngx_http_lua_ngx_set_ctx_helper(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, int index)
{
    ngx_pool_t              *pool;

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

        pool = r->pool;
        if (ngx_http_lua_ngx_ctx_add_cleanup(r, pool, ctx->ctx_ref) != NGX_OK) {
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


int
ngx_http_lua_ffi_get_ctx_ref(ngx_http_request_t *r, int *in_ssl_phase,
    int *ssl_ctx_ref)
{
    ngx_http_lua_ctx_t              *ctx;
#if (NGX_HTTP_SSL)
    ngx_http_lua_ssl_ctx_t          *ssl_ctx;
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_HTTP_LUA_FFI_NO_REQ_CTX;
    }

    if (ctx->ctx_ref >= 0 || in_ssl_phase == NULL) {
        return ctx->ctx_ref;
    }

    *in_ssl_phase = ctx->context & (NGX_HTTP_LUA_CONTEXT_SSL_CERT
                                    | NGX_HTTP_LUA_CONTEXT_SSL_CLIENT_HELLO
                                    | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH
                                    | NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE);
    *ssl_ctx_ref = LUA_NOREF;

#if (NGX_HTTP_SSL)
    if (r->connection->ssl != NULL) {
        ssl_ctx = ngx_http_lua_ssl_get_ctx(r->connection->ssl->connection);

        if (ssl_ctx != NULL) {
            *ssl_ctx_ref = ssl_ctx->ctx_ref;
        }
    }
#endif

    return LUA_NOREF;
}


int
ngx_http_lua_ffi_set_ctx_ref(ngx_http_request_t *r, int ref)
{
    ngx_pool_t                      *pool;
    ngx_http_lua_ctx_t              *ctx;
#if (NGX_HTTP_SSL)
    ngx_connection_t                *c;
    ngx_http_lua_ssl_ctx_t          *ssl_ctx;
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_HTTP_LUA_FFI_NO_REQ_CTX;
    }

#if (NGX_HTTP_SSL)
    if (ctx->context & (NGX_HTTP_LUA_CONTEXT_SSL_CERT
                        | NGX_HTTP_LUA_CONTEXT_SSL_CLIENT_HELLO
                        | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH
                        | NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE))
    {
        ssl_ctx = ngx_http_lua_ssl_get_ctx(r->connection->ssl->connection);
        if (ssl_ctx == NULL) {
            return NGX_ERROR;
        }

        ssl_ctx->ctx_ref = ref;
        c = ngx_ssl_get_connection(r->connection->ssl->connection);
        pool = c->pool;

    } else {
        pool = r->pool;
    }

#else
    pool = r->pool;
#endif

    ctx->ctx_ref = ref;

    if (ngx_http_lua_ngx_ctx_add_cleanup(r, pool, ref) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_ngx_ctx_add_cleanup(ngx_http_request_t *r, ngx_pool_t *pool,
    int ref)
{
    lua_State                   *L;
    ngx_pool_cleanup_t          *cln;
    ngx_http_lua_ctx_t          *ctx;

    ngx_http_lua_ngx_ctx_cleanup_data_t    *data;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    L = ngx_http_lua_get_lua_vm(r, ctx);

    cln = ngx_pool_cleanup_add(pool,
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
