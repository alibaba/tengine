
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


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

    lua_pushinteger(L, NGX_HTTP_MKCOL);
    lua_setfield(L, -2, "HTTP_MKCOL");

    lua_pushinteger(L, NGX_HTTP_COPY);
    lua_setfield(L, -2, "HTTP_COPY");

    lua_pushinteger(L, NGX_HTTP_MOVE);
    lua_setfield(L, -2, "HTTP_MOVE");

    lua_pushinteger(L, NGX_HTTP_PROPFIND);
    lua_setfield(L, -2, "HTTP_PROPFIND");

    lua_pushinteger(L, NGX_HTTP_PROPPATCH);
    lua_setfield(L, -2, "HTTP_PROPPATCH");

    lua_pushinteger(L, NGX_HTTP_LOCK);
    lua_setfield(L, -2, "HTTP_LOCK");

    lua_pushinteger(L, NGX_HTTP_UNLOCK);
    lua_setfield(L, -2, "HTTP_UNLOCK");

    lua_pushinteger(L, NGX_HTTP_PATCH);
    lua_setfield(L, -2, "HTTP_PATCH");

    lua_pushinteger(L, NGX_HTTP_TRACE);
    lua_setfield(L, -2, "HTTP_TRACE");
    /* }}} */

    lua_pushinteger(L, NGX_HTTP_CONTINUE);
    lua_setfield(L, -2, "HTTP_CONTINUE");

    lua_pushinteger(L, NGX_HTTP_SWITCHING_PROTOCOLS);
    lua_setfield(L, -2, "HTTP_SWITCHING_PROTOCOLS");

    lua_pushinteger(L, NGX_HTTP_OK);
    lua_setfield(L, -2, "HTTP_OK");

    lua_pushinteger(L, NGX_HTTP_CREATED);
    lua_setfield(L, -2, "HTTP_CREATED");

    lua_pushinteger(L, NGX_HTTP_ACCEPTED);
    lua_setfield(L, -2, "HTTP_ACCEPTED");

    lua_pushinteger(L, NGX_HTTP_NO_CONTENT);
    lua_setfield(L, -2, "HTTP_NO_CONTENT");

    lua_pushinteger(L, NGX_HTTP_PARTIAL_CONTENT);
    lua_setfield(L, -2, "HTTP_PARTIAL_CONTENT");

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

    lua_pushinteger(L, NGX_HTTP_PERMANENT_REDIRECT);
    lua_setfield(L, -2, "HTTP_PERMANENT_REDIRECT");

    lua_pushinteger(L, NGX_HTTP_NOT_MODIFIED);
    lua_setfield(L, -2, "HTTP_NOT_MODIFIED");

    lua_pushinteger(L, NGX_HTTP_TEMPORARY_REDIRECT);
    lua_setfield(L, -2, "HTTP_TEMPORARY_REDIRECT");

    lua_pushinteger(L, NGX_HTTP_BAD_REQUEST);
    lua_setfield(L, -2, "HTTP_BAD_REQUEST");

    lua_pushinteger(L, NGX_HTTP_UNAUTHORIZED);
    lua_setfield(L, -2, "HTTP_UNAUTHORIZED");

    lua_pushinteger(L, 402);
    lua_setfield(L, -2, "HTTP_PAYMENT_REQUIRED");

    lua_pushinteger(L, NGX_HTTP_FORBIDDEN);
    lua_setfield(L, -2, "HTTP_FORBIDDEN");

    lua_pushinteger(L, NGX_HTTP_NOT_FOUND);
    lua_setfield(L, -2, "HTTP_NOT_FOUND");

    lua_pushinteger(L, NGX_HTTP_NOT_ALLOWED);
    lua_setfield(L, -2, "HTTP_NOT_ALLOWED");

    lua_pushinteger(L, 406);
    lua_setfield(L, -2, "HTTP_NOT_ACCEPTABLE");

    lua_pushinteger(L, NGX_HTTP_REQUEST_TIME_OUT);
    lua_setfield(L, -2, "HTTP_REQUEST_TIMEOUT");

    lua_pushinteger(L, NGX_HTTP_CONFLICT);
    lua_setfield(L, -2, "HTTP_CONFLICT");

    lua_pushinteger(L, 410);
    lua_setfield(L, -2, "HTTP_GONE");

    lua_pushinteger(L, 426);
    lua_setfield(L, -2, "HTTP_UPGRADE_REQUIRED");

    lua_pushinteger(L, 429);
    lua_setfield(L, -2, "HTTP_TOO_MANY_REQUESTS");

    lua_pushinteger(L, 451);
    lua_setfield(L, -2, "HTTP_ILLEGAL");

    lua_pushinteger(L, NGX_HTTP_CLOSE);
    lua_setfield(L, -2, "HTTP_CLOSE");

    lua_pushinteger(L, NGX_HTTP_INTERNAL_SERVER_ERROR);
    lua_setfield(L, -2, "HTTP_INTERNAL_SERVER_ERROR");

    lua_pushinteger(L, NGX_HTTP_NOT_IMPLEMENTED);
    lua_setfield(L, -2, "HTTP_METHOD_NOT_IMPLEMENTED");

    lua_pushinteger(L, NGX_HTTP_BAD_GATEWAY);
    lua_setfield(L, -2, "HTTP_BAD_GATEWAY");

    lua_pushinteger(L, NGX_HTTP_SERVICE_UNAVAILABLE);
    lua_setfield(L, -2, "HTTP_SERVICE_UNAVAILABLE");

    lua_pushinteger(L, NGX_HTTP_GATEWAY_TIME_OUT);
    lua_setfield(L, -2, "HTTP_GATEWAY_TIMEOUT");

    lua_pushinteger(L, 505);
    lua_setfield(L, -2, "HTTP_VERSION_NOT_SUPPORTED");

    lua_pushinteger(L, NGX_HTTP_INSUFFICIENT_STORAGE);
    lua_setfield(L, -2, "HTTP_INSUFFICIENT_STORAGE");

    /* }}} */
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
