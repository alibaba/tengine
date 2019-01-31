
/*
 * Copyright (C) by OpenResty Inc.
 */


#ifndef _NGX_HTTP_LUA_INPUT_FILTERS_H_INCLUDED_
#define _NGX_HTTP_LUA_INPUT_FILTERS_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_read_bytes(ngx_buf_t *src, ngx_chain_t *buf_in,
    size_t *rest, ssize_t bytes, ngx_log_t *log);

ngx_int_t ngx_http_lua_read_all(ngx_buf_t *src, ngx_chain_t *buf_in,
    ssize_t bytes, ngx_log_t *log);

ngx_int_t ngx_http_lua_read_any(ngx_buf_t *src, ngx_chain_t *buf_in,
    size_t *max, ssize_t bytes, ngx_log_t *log);

ngx_int_t ngx_http_lua_read_line(ngx_buf_t *src, ngx_chain_t *buf_in,
    ssize_t bytes, ngx_log_t *log);


#endif /* _NGX_HTTP_LUA_INPUT_FILTERS_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
