
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_HEADERS_H_INCLUDED_
#define _NGX_HTTP_LUA_HEADERS_H_INCLUDED_


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_resp_header_api(lua_State *L);
void ngx_http_lua_inject_req_header_api(lua_State *L);
void ngx_http_lua_create_headers_metatable(ngx_log_t *log, lua_State *L);
#if (nginx_version >= 1011011)
void ngx_http_lua_ngx_raw_header_cleanup(void *data);
#endif


#endif /* _NGX_HTTP_LUA_HEADERS_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
