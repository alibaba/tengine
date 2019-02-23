
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_BODYFILTERBY_H_INCLUDED_
#define _NGX_HTTP_LUA_BODYFILTERBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


extern ngx_http_output_body_filter_pt ngx_http_lua_next_filter_body_filter;


ngx_int_t ngx_http_lua_body_filter_init(void);
ngx_int_t ngx_http_lua_body_filter_by_chunk(lua_State *L,
    ngx_http_request_t *r, ngx_chain_t *in);
ngx_int_t ngx_http_lua_body_filter_inline(ngx_http_request_t *r,
    ngx_chain_t *in);
ngx_int_t ngx_http_lua_body_filter_file(ngx_http_request_t *r,
    ngx_chain_t *in);
int ngx_http_lua_body_filter_param_get(lua_State *L, ngx_http_request_t *r);
int ngx_http_lua_body_filter_param_set(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx);


#endif /* _NGX_HTTP_LUA_BODYFILTERBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
