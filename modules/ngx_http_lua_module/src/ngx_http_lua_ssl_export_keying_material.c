
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif


#include "ddebug.h"

#if (NGX_HTTP_SSL)

#include <openssl/ssl.h>

#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_ssl_module.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_ssl_session_fetchby.h"
#include "ngx_http_lua_ssl.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_ssl_export_keying_material.h"


ngx_int_t
ngx_http_lua_ffi_ssl_export_keying_material(ngx_http_request_t *r,
    u_char *out, size_t out_size, const char *label, size_t llen,
    const u_char *context, size_t ctxlen, int use_ctx, char **err)
{
#if defined(OPENSSL_IS_BORINGSSL) || OPENSSL_VERSION_NUMBER < 0x10101000L
    *err = "BoringSSL does not support SSL_export_keying_material";
    return NGX_ERROR;
#elif defined(LIBRESSL_VERSION_NUMBER)
    *err = "LibreSSL does not support SSL_export_keying_material";
    return NGX_ERROR;
#elif OPENSSL_VERSION_NUMBER < 0x10101000L
    *err = "OpenSSL too old";
    return NGX_ERROR;
#else
    ngx_connection_t   *c;
    ngx_ssl_conn_t     *ssl_conn;
    int                 rc;

    c = r->connection;
    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl connection";
        return NGX_ERROR;
    }

    rc = SSL_export_keying_material(ssl_conn, out, out_size, label, llen,
                                    context, ctxlen, use_ctx);
    if (rc == 1) {
        return NGX_OK;
    }

    ngx_ssl_error(NGX_LOG_INFO, c->log, 0,
                  "SSL_export_keying_material rc: %d, error: %s",
                  rc, ERR_error_string(ERR_get_error(), NULL));

    *err = "SSL_export_keying_material() failed";

    return NGX_ERROR;
#endif
}


ngx_int_t
ngx_http_lua_ffi_ssl_export_keying_material_early(ngx_http_request_t *r,
    u_char *out, size_t out_size, const char *label, size_t llen,
    const u_char *context, size_t ctxlen, char **err)
{
#if defined(OPENSSL_IS_BORINGSSL) || OPENSSL_VERSION_NUMBER < 0x10101000L
    *err = "BoringSSL does not support SSL_export_keying_material";
    return NGX_ERROR;
#elif defined(LIBRESSL_VERSION_NUMBER)
    *err = "LibreSSL does not support SSL_export_keying_material";
    return NGX_ERROR;
#elif OPENSSL_VERSION_NUMBER < 0x10101000L
    *err = "OpenSSL too old";
    return NGX_ERROR;
#else
    int                  rc;
    ngx_ssl_conn_t      *ssl_conn;
    ngx_connection_t    *c;

    c = r->connection;
    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl connection";
        return NGX_ERROR;
    }

    rc = SSL_export_keying_material_early(ssl_conn, out, out_size,
                                          label, llen, context, ctxlen);

    if (rc == 1) {
        return NGX_OK;
    }

    ngx_ssl_error(NGX_LOG_INFO, c->log, 0,
                  "SSL_export_keying_material_early rc: %d, error: %s",
                  rc, ERR_error_string(ERR_get_error(), NULL));

    *err = "SSL_export_keying_material_early() failed";

    return NGX_ERROR;
#endif
}

#endif /* NGX_HTTP_SSL */
