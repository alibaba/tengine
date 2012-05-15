/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef NGX_HTTP_LUA_ACCESSBY_H
#define NGX_HTTP_LUA_ACCESSBY_H


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_access_handler(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_access_handler_inline(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_access_handler_file(ngx_http_request_t *r);


#endif /* NGX_HTTP_LUA_ACCESSBY_H */

