#ifndef NGX_HTTP_LUA_INITBY_H
#define NGX_HTTP_LUA_INITBY_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_init_by_inline(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
        lua_State *L);

int ngx_http_lua_init_by_file(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
        lua_State *L);


#endif /* NGX_HTTP_LUA_INITBY_H */

