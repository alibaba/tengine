#ifndef DDEBUG
#define DDEBUG 0
#endif

#include "ddebug.h"

#include "ngx_http_lua_consts.h"


void
ngx_http_lua_inject_core_consts(lua_State *L)
{
    /* {{{ core constants */
    lua_pushinteger(L, NGX_OK);
    lua_setfield(L, -2, "OK");

    lua_pushinteger(L, NGX_AGAIN);
    lua_setfield(L, -2, "AGAIN");

    lua_pushinteger(L, NGX_DONE);
    lua_setfield(L, -2, "DONE");

    lua_pushinteger(L, NGX_DECLINED);
    lua_setfield(L, -2, "DECLINED");

    lua_pushinteger(L, NGX_ERROR);
    lua_setfield(L, -2, "ERROR");

    lua_pushlightuserdata(L, NULL);
    lua_setfield(L, -2, "null");
    /* }}} */
}


void
ngx_http_lua_inject_http_consts(lua_State *L)
{
    /* {{{ HTTP status constants */
    lua_pushinteger(L, NGX_HTTP_GET);
    lua_setfield(L, -2, "HTTP_GET");

    lua_pushinteger(L, NGX_HTTP_POST);
    lua_setfield(L, -2, "HTTP_POST");

    lua_pushinteger(L, NGX_HTTP_PUT);
    lua_setfield(L, -2, "HTTP_PUT");

    lua_pushinteger(L, NGX_HTTP_HEAD);
    lua_setfield(L, -2, "HTTP_HEAD");

    lua_pushinteger(L, NGX_HTTP_DELETE);
    lua_setfield(L, -2, "HTTP_DELETE");

    lua_pushinteger(L, NGX_HTTP_OPTIONS);
    lua_setfield(L, -2, "HTTP_OPTIONS");
    /* }}} */

    lua_pushinteger(L, NGX_HTTP_OK);
    lua_setfield(L, -2, "HTTP_OK");

    lua_pushinteger(L, NGX_HTTP_CREATED);
    lua_setfield(L, -2, "HTTP_CREATED");

    lua_pushinteger(L, NGX_HTTP_SPECIAL_RESPONSE);
    lua_setfield(L, -2, "HTTP_SPECIAL_RESPONSE");

    lua_pushinteger(L, NGX_HTTP_MOVED_PERMANENTLY);
    lua_setfield(L, -2, "HTTP_MOVED_PERMANENTLY");

    lua_pushinteger(L, NGX_HTTP_MOVED_TEMPORARILY);
    lua_setfield(L, -2, "HTTP_MOVED_TEMPORARILY");

#if defined(nginx_version) && nginx_version >= 8042
    lua_pushinteger(L, NGX_HTTP_SEE_OTHER);
    lua_setfield(L, -2, "HTTP_SEE_OTHER");
#endif

    lua_pushinteger(L, NGX_HTTP_NOT_MODIFIED);
    lua_setfield(L, -2, "HTTP_NOT_MODIFIED");

    lua_pushinteger(L, NGX_HTTP_BAD_REQUEST);
    lua_setfield(L, -2, "HTTP_BAD_REQUEST");

    lua_pushinteger(L, NGX_HTTP_UNAUTHORIZED);
    lua_setfield(L, -2, "HTTP_UNAUTHORIZED");


    lua_pushinteger(L, NGX_HTTP_FORBIDDEN);
    lua_setfield(L, -2, "HTTP_FORBIDDEN");

    lua_pushinteger(L, NGX_HTTP_NOT_FOUND);
    lua_setfield(L, -2, "HTTP_NOT_FOUND");

    lua_pushinteger(L, NGX_HTTP_NOT_ALLOWED);
    lua_setfield(L, -2, "HTTP_NOT_ALLOWED");

    lua_pushinteger(L, 410);
    lua_setfield(L, -2, "HTTP_GONE");

    lua_pushinteger(L, NGX_HTTP_INTERNAL_SERVER_ERROR);
    lua_setfield(L, -2, "HTTP_INTERNAL_SERVER_ERROR");

    lua_pushinteger(L, 501);
    lua_setfield(L, -2, "HTTP_METHOD_NOT_IMPLEMENTED");

    lua_pushinteger(L, NGX_HTTP_SERVICE_UNAVAILABLE);
    lua_setfield(L, -2, "HTTP_SERVICE_UNAVAILABLE");

    lua_pushinteger(L, 504);
    lua_setfield(L, -2, "HTTP_GATEWAY_TIMEOUT");
    /* }}} */
}

