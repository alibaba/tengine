
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_EXITWORKERBY_H_INCLUDED_
#define _NGX_HTTP_LUA_EXITWORKERBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_exit_worker_by_inline(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L);

ngx_int_t ngx_http_lua_exit_worker_by_file(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L);

void ngx_http_lua_exit_worker(ngx_cycle_t *cycle);


#endif /* _NGX_HTTP_LUA_EXITWORKERBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
