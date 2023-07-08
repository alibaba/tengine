
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_HEADERS_OUT_H_INCLUDED_
#define _NGX_HTTP_LUA_HEADERS_OUT_H_INCLUDED_


#include "ngx_http_lua_common.h"


#if (NGX_DARWIN)
typedef struct {
    ngx_http_request_t   *r;
    const char           *key_data;
    size_t                key_len;
    int                   is_nil;
    const char           *sval;
    size_t                sval_len;
    void                 *mvals;
    size_t                mvals_len;
    int                   override;
    char                **errmsg;
} ngx_http_lua_set_resp_header_params_t;
#endif


ngx_int_t ngx_http_lua_set_output_header(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_str_t key, ngx_str_t value, unsigned override);
int ngx_http_lua_get_output_header(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_str_t *key);
ngx_int_t ngx_http_lua_init_builtin_headers_out(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf);


#endif /* _NGX_HTTP_LUA_HEADERS_OUT_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
