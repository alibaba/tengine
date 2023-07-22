
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_CACHE_H_INCLUDED_
#define _NGX_HTTP_LUA_CACHE_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_cache_loadbuffer(ngx_log_t *log, lua_State *L,
    const u_char *src, size_t src_len, int *cache_ref, const u_char *cache_key,
    const char *name);
ngx_int_t ngx_http_lua_cache_loadfile(ngx_log_t *log, lua_State *L,
    const u_char *script, int *cache_ref, const u_char *cache_key);
u_char *ngx_http_lua_gen_chunk_cache_key(ngx_conf_t *cf, const char *tag,
    const u_char *src, size_t src_len);
u_char *ngx_http_lua_gen_file_cache_key(ngx_conf_t *cf, const u_char *src,
    size_t src_len);


#endif /* _NGX_HTTP_LUA_CACHE_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
