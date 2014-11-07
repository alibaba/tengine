
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SUBREQUEST_H_INCLUDED_
#define _NGX_HTTP_LUA_SUBREQUEST_H_INCLUDED_


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_subrequest_api(lua_State *L);
ngx_int_t ngx_http_lua_post_subrequest(ngx_http_request_t *r, void *data,
    ngx_int_t rc);


extern ngx_str_t  ngx_http_lua_get_method;
extern ngx_str_t  ngx_http_lua_put_method;
extern ngx_str_t  ngx_http_lua_post_method;
extern ngx_str_t  ngx_http_lua_head_method;
extern ngx_str_t  ngx_http_lua_delete_method;
extern ngx_str_t  ngx_http_lua_options_method;
extern ngx_str_t  ngx_http_lua_copy_method;
extern ngx_str_t  ngx_http_lua_move_method;
extern ngx_str_t  ngx_http_lua_lock_method;
extern ngx_str_t  ngx_http_lua_mkcol_method;
extern ngx_str_t  ngx_http_lua_propfind_method;
extern ngx_str_t  ngx_http_lua_proppatch_method;
extern ngx_str_t  ngx_http_lua_unlock_method;
extern ngx_str_t  ngx_http_lua_patch_method;
extern ngx_str_t  ngx_http_lua_trace_method;


typedef struct ngx_http_lua_post_subrequest_data_s {
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *pr_co_ctx;

} ngx_http_lua_post_subrequest_data_t;


#endif /* _NGX_HTTP_LUA_SUBREQUEST_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
