#ifndef _NGX_HTTP_LUA_SET_BY_H_INCLUDED_
#define _NGX_HTTP_LUA_SET_BY_H_INCLUDED_

#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_set_by_chunk(lua_State *L, ngx_http_request_t *r,
    ngx_str_t *val, ngx_http_variable_value_t *args, size_t nargs,
    ngx_str_t *script);
int ngx_http_lua_setby_param_get(lua_State *L, ngx_http_request_t *r);


#endif /* _NGX_HTTP_LUA_SET_BY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
