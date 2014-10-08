#ifndef NGX_HTTP_LUA_ARGS
#define NGX_HTTP_LUA_ARGS


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_req_args_api(lua_State *L);

int ngx_http_lua_parse_args(lua_State *L, u_char *buf, u_char *last, int max);

#endif /* NGX_HTTP_LUA_ARGS */

