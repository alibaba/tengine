#ifndef NGX_HTTP_LUA_API_H
#define NGX_HTTP_LUA_API_H


#include <nginx.h>
#include <ngx_core.h>
#include <ngx_http.h>

#include <lua.h>


/* Publich API for other Nginx modules */

lua_State * ngx_http_lua_get_global_state(ngx_conf_t *cf);

ngx_http_request_t *ngx_http_lua_get_request(lua_State *L);

void ngx_http_lua_add_package_preload(ngx_conf_t *cf, const char *package,
    lua_CFunction func);


#endif /* NGX_HTTP_LUA_API_H */

