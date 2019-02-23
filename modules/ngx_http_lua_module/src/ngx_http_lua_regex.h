
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_REGEX_H_INCLUDED_
#define _NGX_HTTP_LUA_REGEX_H_INCLUDED_


#include "ngx_http_lua_common.h"
#include "ngx_http_lua_script.h"


#if (NGX_PCRE)
void ngx_http_lua_inject_regex_api(lua_State *L);
ngx_int_t ngx_http_lua_ffi_set_jit_stack_size(int size, u_char *errstr,
    size_t *errstr_size);
#endif


#endif /* _NGX_HTTP_LUA_REGEX_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
