
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_uri.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_set_uri(lua_State *L);


void
ngx_http_lua_inject_req_uri_api(ngx_log_t *log, lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_uri);
    lua_setfield(L, -2, "set_uri");
}


static int
ngx_http_lua_ngx_req_set_uri(lua_State *L)
{
    ngx_http_request_t          *r;
    size_t                       len;
    u_char                      *p;
    int                          n;
    int                          jump = 0;
    ngx_http_lua_ctx_t          *ctx;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 arguments but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_http_lua_check_fake_request(L, r);

    p = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        return luaL_error(L, "attempt to use zero-length uri");
    }

    if (n == 2) {

        luaL_checktype(L, 2, LUA_TBOOLEAN);
        jump = lua_toboolean(L, 2);

        if (jump) {

            ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
            if (ctx == NULL) {
                return luaL_error(L, "no ctx found");
            }

            dd("rewrite: %d, access: %d, content: %d",
               (int) ctx->entered_rewrite_phase,
               (int) ctx->entered_access_phase,
               (int) ctx->entered_content_phase);

            ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE);

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua set uri jump to \"%*s\"", len, p);

            ngx_http_lua_check_if_abortable(L, ctx);
        }
    }

    r->uri.data = ngx_palloc(r->pool, len);
    if (r->uri.data == NULL) {
        return luaL_error(L, "no memory");
    }

    ngx_memcpy(r->uri.data, p, len);

    r->uri.len = len;

    r->internal = 1;
    r->valid_unparsed_uri = 0;

    ngx_http_set_exten(r);

    if (jump) {
        r->uri_changed = 1;

        return lua_yield(L, 0);
    }

    r->valid_location = 0;
    r->uri_changed = 0;

    return 0;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
