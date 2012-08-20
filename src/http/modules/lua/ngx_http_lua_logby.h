#ifndef NGX_HTTP_LUA_LOGBY_H
#define NGX_HTTP_LUA_LOGBY_H


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_log_handler(ngx_http_request_t *r);

ngx_int_t ngx_http_lua_log_handler_inline(ngx_http_request_t *r);

ngx_int_t ngx_http_lua_log_handler_file(ngx_http_request_t *r);

void ngx_http_lua_inject_logby_ngx_api(ngx_conf_t *cf, lua_State *L);


#endif /* NGX_HTTP_LUA_LOGBY_H */

