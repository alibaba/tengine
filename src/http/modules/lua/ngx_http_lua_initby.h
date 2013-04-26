
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_INITBY_H_INCLUDED_
#define _NGX_HTTP_LUA_INITBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


int ngx_http_lua_init_by_inline(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
        lua_State *L);

int ngx_http_lua_init_by_file(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
        lua_State *L);


#endif /* _NGX_HTTP_LUA_INITBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
