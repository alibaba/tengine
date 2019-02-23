
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_EXCEPTION_H_INCLUDED_
#define _NGX_HTTP_LUA_EXCEPTION_H_INCLUDED_


#include "ngx_http_lua_common.h"


#define NGX_LUA_EXCEPTION_TRY                                                \
    if (setjmp(ngx_http_lua_exception) == 0)

#define NGX_LUA_EXCEPTION_CATCH                                              \
    else

#define NGX_LUA_EXCEPTION_THROW(x)                                           \
    longjmp(ngx_http_lua_exception, (x))


extern jmp_buf ngx_http_lua_exception;


int ngx_http_lua_atpanic(lua_State *L);


#endif /* _NGX_HTTP_LUA_EXCEPTION_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
