
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SSL_EXPORT_KEYING_MATERIAL_H_INCLUDED_
#define _NGX_HTTP_LUA_SSL_EXPORT_KEYING_MATERIAL_H_INCLUDED_

#include "ngx_http_lua_common.h"

#if (NGX_HTTP_SSL)
ngx_int_t ngx_http_lua_ffi_ssl_export_keying_material(ngx_http_request_t *r,
    u_char *out, size_t out_size, const char *label, size_t llen,
    const u_char *ctx, size_t ctxlen, int use_ctx, char **err);

ngx_int_t ngx_http_lua_ffi_ssl_export_keying_material_early(
    ngx_http_request_t *r, u_char *out, size_t out_size, const char *label,
    size_t llen, const u_char *ctx, size_t ctxlen, char **err);
#endif

#endif /* _NGX_HTTP_LUA_SSL_EXPORT_KEYING_MATERIAL_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
