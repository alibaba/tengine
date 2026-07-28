/*
 * xQUIC Integration for Dynamic Certificate Module
 *
 * This file is a standalone compilation unit that provides ngx_http_v3_cert_cb_dynamic.
 * ngx_http_v3_cert_cb in ngx_http_xquic.c invokes this function via a forward declaration.
 *
 * When dynamic_cert_enable is on and the shared memory is ready,
 * ngx_http_v3_cert_cb calls this function first and uses the C-module double-buffered
 * rbtree certificate lookup. If the SNI does not match a dynamic certificate, it falls
 * back to the static certificate read directly from SSL_CTX, and no longer falls back
 * to ngx_http_v3_cert_cb_lua.
 *
 * The entire file is guarded by the T_NGX_HAVE_DYNAMIC_CERT macro:
 * the code in this file only takes effect when ngx_http_dynamic_cert_module is compiled in.
 */

#include <ngx_config.h>   /* Include ngx_auto_config.h so that T_NGX_HAVE_DYNAMIC_CERT is visible */

#if (T_NGX_HAVE_DYNAMIC_CERT)

#include "ngx_http_dynamic_cert_module.h"

/* Forward declaration: defined in ngx_http_xquic.c */
extern ngx_int_t ngx_http_find_virtual_server_inner(ngx_connection_t *c,
    ngx_http_virtual_names_t *virtual_names, ngx_str_t *host,
    ngx_http_request_t *r, ngx_http_core_srv_conf_t **cscfp);

/*
 * ngx_http_v3_cert_cb_dynamic_extract_from_ctx
 *
 * Extract the certificate/private key/chain from SSL_CTX and return them to the xQUIC
 * engine through the chain/cert/key pointers. Used by both the dynamic-certificate
 * path and the static-certificate fallback.
 *
 * Returns: XQC_OK on success, XQC_ERROR on failure.
 */
static xqc_int_t
ngx_http_v3_cert_cb_dynamic_extract_from_ctx(SSL_CTX *ctx,
    void **chain, void **cert, void **key,
    const char *sni, const char *source, ngx_log_t *log)
{
    STACK_OF(X509)  *cert_chain;
    X509            *certificate;
    EVP_PKEY        *private_key;
    int              ssl_ret;

    ssl_ret = SSL_CTX_get0_chain_certs(ctx, &cert_chain);
    if (ssl_ret != 1) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|dynamic_cert|xquic: SSL_CTX_get0_chain_certs failed|sni=%s|src=%s|err=%d|",
                      sni, source, ssl_ret);
        return XQC_ERROR;
    }

    certificate = SSL_CTX_get0_certificate(ctx);
    if (certificate == NULL) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|dynamic_cert|xquic: no certificate|sni=%s|src=%s|",
                      sni, source);
        return XQC_ERROR;
    }

    private_key = SSL_CTX_get0_privatekey(ctx);
    if (private_key == NULL) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|dynamic_cert|xquic: no private key|sni=%s|src=%s|",
                      sni, source);
        return XQC_ERROR;
    }

    *chain = cert_chain;
    *cert  = certificate;
    *key   = private_key;

    return XQC_OK;
}

/*
 * ngx_http_v3_cert_cb_dynamic:
 *
 * Provides certificates for the C-module dynamic-certificate path during the xQUIC handshake.
 *
 * Certificate selection order:
 *   1. Dynamic certificate: looked up by SNI via ngx_http_dynamic_cert_lookup_ssl_ctx.
 *      On a hit, the certificate/private key/chain are extracted from the returned SSL_CTX
 *      and passed back to the xQUIC engine through pointers. SSL_set_SSL_CTX() is not used,
 *      to avoid breaking the quic_method of the QUIC SSL object.
 *   2. Static certificate fallback: when the dynamic lookup misses, the static certificate
 *      is read directly from the current server block's SSL_CTX and passed back to the xQUIC
 *      engine via the chain/cert/key pointers.
 *
 * Returns:
 *   XQC_OK    - certificate is ready (returned via the chain/cert/key pointers)
 *   XQC_ERROR - an error occurred
 */
xqc_int_t
ngx_http_v3_cert_cb_dynamic(const char *sni, void **chain,
                             void **cert, void **key, void *conn_user_data)
{
    ngx_int_t                          ret;
    ngx_http_xquic_connection_t       *qc;
    ngx_connection_t                  *c;
    ngx_http_connection_t             *hc;
    ngx_http_core_srv_conf_t          *cscf;
    ngx_http_ssl_srv_conf_t           *sscf;
    ngx_str_t                          host;
    void                              *data;
    SSL_CTX                           *dynamic_ctx;

    qc = (ngx_http_xquic_connection_t *) conn_user_data;
    hc = qc->http_connection;
    c  = qc->connection;

    /*
     * Handling clients without SNI:
     *
     * In the xquic library, xqc_ssl_cert_cb checks the return value of SSL_get_servername:
     *   - Returns NULL (ClientHello has no SNI extension) -> returns XQC_SSL_FAIL directly,
     *     cert_cb is not invoked.
     *   - Returns "" (ClientHello has the SNI extension but the value is an empty string) ->
     *     passes the NULL check, and cert_cb is invoked.
     *
     * So the sni received by this function may be "" (empty string). In that case the
     * port-fallback path is taken:
     *   - Try to look up the certificate using the listening port number as the domain name.
     *   - If port fallback also fails, return NULL and fall back to the static certificate.
     */
    if (sni != NULL && *sni != '\0') {
        host.data = (u_char *) sni;
        host.len  = ngx_strlen(sni);
    } else {
        /* No SNI: do not set host; the subsequent virtual-host lookup will use the default config */
        host.data = NULL;
        host.len  = 0;

        ngx_log_error(NGX_LOG_INFO, c->log, 0,
                      "|dynamic_cert|xquic: SNI is empty, will try port fallback|");
    }

    /* Determine the virtual-host configuration from SNI (only when SNI is present) */
    if (host.data != NULL && host.len > 0) {
        data    = c->data;
        c->data = hc;
        ret = ngx_http_find_virtual_server_inner(c, hc->addr_conf->virtual_names,
                                                 &host, NULL, &cscf);
        c->data = data;

        if (ret == NGX_OK) {
            hc->ssl_servername = ngx_palloc(c->pool, sizeof(ngx_str_t));
            if (hc->ssl_servername == NULL) {
                ngx_log_error(NGX_LOG_ERR, c->log, 0,
                              "|dynamic_cert|xquic: failed to alloc ssl_servername|sni=%s|", sni);
                return XQC_ERROR;
            }
            *hc->ssl_servername = host;
            hc->conf_ctx = cscf->ctx;
        } else {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "xquic dynamic cert: can't find virtual server for \"%s\","
                           " use default", sni);
        }
    }

    /*
     * Attempt dynamic certificate: QUIC-specific lookup (does not call SSL_set_SSL_CTX).
     *
     * Difference from the TLS path:
     *   The TLS path uses ngx_http_dynamic_cert_handler -> SSL_set_SSL_CTX() to switch.
     *   The QUIC path uses ngx_http_dynamic_cert_lookup_ssl_ctx -> returns SSL_CTX *,
     *   and this function extracts the certificate/private key/chain from it and passes
     *   them back to the xQUIC engine via pointers.
     *
     * Reason: in BabaSSL/OpenSSL, SSL_set_SSL_CTX() modifies the method pointer of the
     * SSL object, switching the QUIC method back to the TLS method. This causes the
     * subsequent SSL_do_handshake to go through ssl3_do_write and fail with
     * "called a function you should not call".
     *
     * Note: this does not rely on qc->ssl_conn (it is always NULL at the cert_cb stage).
     * SNI is passed in as the xquic argument, and base_ctx is obtained from sscf->ssl.ctx.
     */
    sscf = ngx_http_get_module_srv_conf(hc->conf_ctx, ngx_http_ssl_module);
    if (sscf == NULL || sscf->ssl.ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "|dynamic_cert|xquic: SSL_CTX not found|sni=%s|", sni);
        return XQC_ERROR;
    }

    dynamic_ctx = ngx_http_dynamic_cert_lookup_ssl_ctx(sni, sscf->ssl.ctx,
                                                       c, c->log);

    if (dynamic_ctx != NULL) {
        /* Dynamic certificate hit: extract cert/key/chain from SSL_CTX and return to xQUIC */
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "xquic dynamic cert: C module found cert for \"%s\"", sni);

        return ngx_http_v3_cert_cb_dynamic_extract_from_ctx(
            dynamic_ctx, chain, cert, key, sni, "dynamic", c->log);
    }

    /*
     * Dynamic certificate miss: fall back to the static certificate read from SSL_CTX.
     * sscf has already been fetched and validated above and can be reused directly.
     * Do not fall back to ngx_http_v3_cert_cb_lua, to avoid triggering Lua logic on the
     * C-module path.
     */
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "xquic dynamic cert: no dynamic cert for \"%s\", fallback to static", sni);

    return ngx_http_v3_cert_cb_dynamic_extract_from_ctx(
        sscf->ssl.ctx, chain, cert, key, sni, "static", c->log);
}

#endif /* T_NGX_HAVE_DYNAMIC_CERT */
