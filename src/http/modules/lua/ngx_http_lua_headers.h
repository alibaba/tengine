#ifndef NGX_HTTP_LUA_HEADERS_H
#define NGX_HTTP_LUA_HEADERS_H


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_resp_header_api(lua_State *L);
void ngx_http_lua_inject_req_header_api(lua_State *L);


#endif /* NGX_HTTP_LUA_HEADERS_H */

