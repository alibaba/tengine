
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_LOGBY_H_INCLUDED_
#define _NGX_HTTP_LUA_LOGBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_log_handler(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_log_handler_inline(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_log_handler_file(ngx_http_request_t *r);


#endif /* _NGX_HTTP_LUA_LOGBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
