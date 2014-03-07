
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif


#include "ddebug.h"
#include "ngx_http_lua_req_method.h"
#include "ngx_http_lua_subrequest.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_get_method(lua_State *L);
static int ngx_http_lua_ngx_req_set_method(lua_State *L);


void
ngx_http_lua_inject_req_method_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_method);
    lua_setfield(L, -2, "get_method");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_method);
    lua_setfield(L, -2, "set_method");
}


static int
ngx_http_lua_ngx_req_get_method(lua_State *L)
{
    int                      n;
    ngx_http_request_t      *r;

    n = lua_gettop(L);
    if (n != 0) {
        return luaL_error(L, "only one argument expected but got %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    ngx_http_lua_check_fake_request(L, r);

    lua_pushlstring(L, (char *) r->method_name.data, r->method_name.len);
    return 1;
}


static int
ngx_http_lua_ngx_req_set_method(lua_State *L)
{
    int                  n;
    int                  method;
    ngx_http_request_t  *r;

    n = lua_gettop(L);
    if (n != 1) {
        return luaL_error(L, "only one argument expected but got %d", n);
    }

    method = luaL_checkint(L, 1);

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    ngx_http_lua_check_fake_request(L, r);

    r->method = method;

    switch (method) {
        case NGX_HTTP_GET:
            r->method_name = ngx_http_lua_get_method;
            break;

        case NGX_HTTP_POST:
            r->method_name = ngx_http_lua_post_method;
            break;

        case NGX_HTTP_PUT:
            r->method_name = ngx_http_lua_put_method;
            break;

        case NGX_HTTP_HEAD:
            r->method_name = ngx_http_lua_head_method;
            break;

        case NGX_HTTP_DELETE:
            r->method_name = ngx_http_lua_delete_method;
            break;

        case NGX_HTTP_OPTIONS:
            r->method_name = ngx_http_lua_options_method;
            break;

        case NGX_HTTP_MKCOL:
            r->method_name = ngx_http_lua_mkcol_method;
            break;

        case NGX_HTTP_COPY:
            r->method_name = ngx_http_lua_copy_method;
            break;

        case NGX_HTTP_MOVE:
            r->method_name = ngx_http_lua_move_method;
            break;

        case NGX_HTTP_PROPFIND:
            r->method_name = ngx_http_lua_propfind_method;
            break;

        case NGX_HTTP_PROPPATCH:
            r->method_name = ngx_http_lua_proppatch_method;
            break;

        case NGX_HTTP_LOCK:
            r->method_name = ngx_http_lua_lock_method;
            break;

        case NGX_HTTP_UNLOCK:
            r->method_name = ngx_http_lua_unlock_method;
            break;

        case NGX_HTTP_PATCH:
            r->method_name = ngx_http_lua_patch_method;
            break;

        case NGX_HTTP_TRACE:
            r->method_name = ngx_http_lua_trace_method;
            break;

        default:
            return luaL_error(L, "unsupported HTTP method: %d", method);

    }

    return 0;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
