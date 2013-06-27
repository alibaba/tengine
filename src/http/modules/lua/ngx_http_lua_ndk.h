
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_NDK_H_INCLUDED_
#define _NGX_HTTP_LUA_NDK_H_INCLUDED_


#include "ngx_http_lua_common.h"


#if defined(NDK) && NDK
void ngx_http_lua_inject_ndk_api(lua_State *L);
#endif


#endif /* _NGX_HTTP_LUA_NDK_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
