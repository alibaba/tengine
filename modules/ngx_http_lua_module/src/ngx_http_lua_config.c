
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_config.h"
#include "api/ngx_http_lua_api.h"


static int ngx_http_lua_config_prefix(lua_State *L);
static int ngx_http_lua_config_configure(lua_State *L);


void
ngx_http_lua_inject_config_api(lua_State *L)
{
    /* ngx.config */

    lua_createtable(L, 0, 6 /* nrec */);    /* .config */

#if (NGX_DEBUG)
    lua_pushboolean(L, 1);
#else
    lua_pushboolean(L, 0);
#endif
    lua_setfield(L, -2, "debug");

    lua_pushcfunction(L, ngx_http_lua_config_prefix);
    lua_setfield(L, -2, "prefix");

    lua_pushinteger(L, nginx_version);
    lua_setfield(L, -2, "nginx_version");

    lua_pushinteger(L, ngx_http_lua_version);
    lua_setfield(L, -2, "ngx_lua_version");

    lua_pushcfunction(L, ngx_http_lua_config_configure);
    lua_setfield(L, -2, "nginx_configure");

    lua_pushliteral(L, "http");
    lua_setfield(L, -2, "subsystem");

    lua_setfield(L, -2, "config");
}


static int
ngx_http_lua_config_prefix(lua_State *L)
{
    lua_pushlstring(L, (char *) ngx_cycle->prefix.data,
                    ngx_cycle->prefix.len);
    return 1;
}


static int
ngx_http_lua_config_configure(lua_State *L)
{
    lua_pushliteral(L, NGX_CONFIGURE);
    return 1;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
