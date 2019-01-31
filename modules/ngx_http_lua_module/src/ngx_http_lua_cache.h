
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_CACHE_H_INCLUDED_
#define _NGX_HTTP_LUA_CACHE_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_cache_loadbuffer(ngx_log_t *log, lua_State *L,
    const u_char *src, size_t src_len, const u_char *cache_key,
    const char *name);
ngx_int_t ngx_http_lua_cache_loadfile(ngx_log_t *log, lua_State *L,
    const u_char *script, const u_char *cache_key);


#endif /* _NGX_HTTP_LUA_CACHE_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
