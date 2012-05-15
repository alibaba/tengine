#ifndef NGX_HTTP_LUA_CTX_H
#define NGX_HTTP_LUA_CTX_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_ngx_get_ctx(lua_State *L);
int ngx_http_lua_ngx_set_ctx(lua_State *L);
int ngx_http_lua_ngx_set_ctx_helper(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int index);


#endif /* NGX_HTTP_LUA_CTX_H */

