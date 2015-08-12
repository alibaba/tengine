
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_COROUTINE_H_INCLUDED_
#define _NGX_HTTP_LUA_COROUTINE_H_INCLUDED_


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_coroutine_api(ngx_log_t *log, lua_State *L);

int ngx_http_lua_coroutine_create_helper(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_http_lua_co_ctx_t **pcoctx);


#endif /* _NGX_HTTP_LUA_COROUTINE_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
