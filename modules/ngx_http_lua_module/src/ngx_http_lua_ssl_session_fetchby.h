
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SSL_SESSION_FETCHBY_H_INCLUDED_
#define _NGX_HTTP_LUA_SSL_SESSION_FETCHBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


#if (NGX_HTTP_SSL)
ngx_int_t ngx_http_lua_ssl_sess_fetch_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

ngx_int_t ngx_http_lua_ssl_sess_fetch_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

char *ngx_http_lua_ssl_sess_fetch_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

char *ngx_http_lua_ssl_sess_fetch_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);

ngx_ssl_session_t *ngx_http_lua_ssl_sess_fetch_handler(
    ngx_ssl_conn_t *ssl_conn,
#if OPENSSL_VERSION_NUMBER >= 0x10100003L
    const
#endif
    u_char *id, int len, int *copy);
#endif


#endif /* _NGX_HTTP_LUA_SSL_SESSION_FETCHBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
