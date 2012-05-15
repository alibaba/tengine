#ifndef NGX_HTTP_LUA_NDK_H
#define NGX_HTTP_LUA_NDK_H


#include "ngx_http_lua_common.h"


#if defined(NDK) && NDK
void ngx_http_lua_inject_ndk_api(lua_State *L);
#endif


#endif /* NGX_HTTP_LUA_NDK_H */

