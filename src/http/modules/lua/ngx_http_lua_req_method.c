
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

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

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

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

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

        default:
            return luaL_error(L, "unsupported HTTP method: %d", method);

    }

    return 0;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
