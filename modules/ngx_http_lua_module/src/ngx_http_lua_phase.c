
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"


int
ngx_http_lua_ffi_get_phase(ngx_http_request_t *r, char **err)
{
    ngx_http_lua_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no request context";
        return NGX_ERROR;
    }

    return ctx->context;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
