
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_CONSTS_H_INCLUDED_
#define _NGX_HTTP_LUA_CONSTS_H_INCLUDED_


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_http_consts(lua_State *L);
void ngx_http_lua_inject_core_consts(lua_State *L);


#endif /* _NGX_HTTP_LUA_CONSTS_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
