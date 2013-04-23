#ifndef NGX_HTTP_LUA_SUBREQUEST_H
#define NGX_HTTP_LUA_SUBREQUEST_H


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_subrequest_api(lua_State *L);
void ngx_http_lua_handle_subreq_responses(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx);
ngx_int_t ngx_http_lua_post_subrequest(ngx_http_request_t *r, void *data,
        ngx_int_t rc);


extern ngx_str_t  ngx_http_lua_get_method;
extern ngx_str_t  ngx_http_lua_put_method;
extern ngx_str_t  ngx_http_lua_post_method;
extern ngx_str_t  ngx_http_lua_head_method;
extern ngx_str_t  ngx_http_lua_delete_method;
extern ngx_str_t  ngx_http_lua_options_method;


#endif /* NGX_HTTP_LUA_SUBREQUEST_H */

