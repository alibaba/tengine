#ifndef NGX_HTTP_LUA_REGEX_H
#define NGX_HTTP_LUA_REGEX_H


#include "ngx_http_lua_common.h"
#include "ngx_http_lua_script.h"


#if (NGX_PCRE)
void ngx_http_lua_inject_regex_api(lua_State *L);
#endif


#endif /* NGX_HTTP_LUA_REGEX_H */

