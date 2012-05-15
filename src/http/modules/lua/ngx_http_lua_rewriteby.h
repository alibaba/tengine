/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef NGX_HTTP_LUA_REWRITEBY_H
#define NGX_HTTP_LUA_REWRITEBY_H


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_rewrite_handler(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_rewrite_handler_inline(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_rewrite_handler_file(ngx_http_request_t *r);


#endif /* NGX_HTTP_LUA_REWRITEBY_H */

