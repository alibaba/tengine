
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_CONTENT_BY_H_INCLUDED_
#define _NGX_HTTP_LUA_CONTENT_BY_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_content_by_chunk(lua_State *L, ngx_http_request_t *r);
void ngx_http_lua_content_wev_handler(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_content_handler_file(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_content_handler_inline(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_content_handler(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_content_run_posted_threads(lua_State *L,
    ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, int n);


#endif /* _NGX_HTTP_LUA_CONTENT_BY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
