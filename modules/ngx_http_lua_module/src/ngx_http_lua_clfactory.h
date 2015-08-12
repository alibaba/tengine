
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_CLFACTORY_H_INCLUDED_
#define _NGX_HTTP_LUA_CLFACTORY_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_clfactory_loadfile(lua_State *L, const char *filename);
ngx_int_t ngx_http_lua_clfactory_loadbuffer(lua_State *L, const char *buff,
    size_t size, const char *name);


#endif /* _NGX_HTTP_LUA_CLFACTORY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
