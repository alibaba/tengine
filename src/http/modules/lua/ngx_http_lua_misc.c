#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_ctx.h"


static int ngx_http_lua_ngx_get(lua_State *L);
static int ngx_http_lua_ngx_set(lua_State *L);


void
ngx_http_lua_inject_misc_api(lua_State *L)
{
    /* ngx. getter and setter */
    lua_createtable(L, 0, 2); /* metatable for .ngx */
    lua_pushcfunction(L, ngx_http_lua_ngx_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_ngx_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);
}


static int
ngx_http_lua_ngx_get(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p;
    size_t                       len;
    ngx_http_lua_ctx_t          *ctx;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    p = (u_char *) luaL_checklstring(L, -1, &len);

    dd("ngx get %s", p);

    if (len == sizeof("status") - 1 &&
            ngx_strncmp(p, "status", sizeof("status") - 1) == 0)
    {
        lua_pushnumber(L, (lua_Number) r->headers_out.status);
        return 1;
    }

    if (len == sizeof("ctx") - 1 &&
            ngx_strncmp(p, "ctx", sizeof("ctx") - 1) == 0)
    {
        return ngx_http_lua_ngx_get_ctx(L);
    }

    if (len == sizeof("is_subrequest") - 1 &&
            ngx_strncmp(p, "is_subrequest", sizeof("is_subrequest") - 1) == 0)
    {
        lua_pushboolean(L, r != r->main);
        return 1;
    }

    if (len == sizeof("headers_sent") - 1
        && ngx_strncmp(p, "headers_sent", sizeof("headers_sent") - 1) == 0)
    {
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        dd("headers sent: %d", ctx->headers_sent);

        lua_pushboolean(L, ctx->headers_sent ? 1 : 0);
        return 1;
    }

    dd("key %s not matched", p);

    lua_pushnil(L);
    return 1;
}


static int
ngx_http_lua_ngx_set(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p;
    size_t                       len;
    ngx_http_lua_ctx_t          *ctx;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    /* we skip the first argument that is the table */
    p = (u_char *) luaL_checklstring(L, 2, &len);

    if (len == sizeof("status") - 1
        && ngx_strncmp(p, "status", sizeof("status") - 1) == 0)
    {
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        if (ctx->headers_sent) {
            return luaL_error(L, "attempt to set ngx.status after "
                    "sending out response headers");
        }

        /* get the value */
        r->headers_out.status = (ngx_uint_t) luaL_checknumber(L, 3);
        return 0;
    }

    if (len == sizeof("ctx") - 1
        && ngx_strncmp(p, "ctx", sizeof("ctx") - 1) == 0)
    {
        return ngx_http_lua_ngx_set_ctx(L);
    }

    return luaL_error(L, "attempt to write to ngx. with the key \"%s\"", p);
}

