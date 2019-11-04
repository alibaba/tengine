
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_BALANCER_H_INCLUDED_
#define _NGX_HTTP_LUA_BALANCER_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_balancer_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

ngx_int_t ngx_http_lua_balancer_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

char *ngx_http_lua_balancer_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

char *ngx_http_lua_balancer_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


#endif /* _NGX_HTTP_LUA_BALANCER_H_INCLUDED_ */
