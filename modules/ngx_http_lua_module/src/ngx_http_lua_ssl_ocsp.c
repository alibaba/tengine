
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#if (NGX_HTTP_SSL)


#include "ngx_http_lua_common.h"


#ifdef NGX_HTTP_LUA_USE_OCSP
static int ngx_http_lua_ssl_empty_status_callback(ngx_ssl_conn_t *ssl_conn,
    void *data);
#endif


int
ngx_http_lua_ffi_ssl_get_ocsp_responder_from_der_chain(
    const char *chain_data, size_t chain_len, unsigned char *out,
    size_t *out_size, char **err)
{
#ifndef NGX_HTTP_LUA_USE_OCSP

    *err = "no OCSP support";
    return NGX_ERROR;

#else

    int                        rc = NGX_OK;
    BIO                       *bio = NULL;
    char                      *s;
    X509                      *cert = NULL, *issuer = NULL;
    size_t                     len;
    STACK_OF(OPENSSL_STRING)  *aia = NULL;

    /* certificate */

    bio = BIO_new_mem_buf((char *) chain_data, chain_len);
    if (bio == NULL) {
        *err = "BIO_new_mem_buf() failed";
        rc = NGX_ERROR;
        goto done;
    }

    cert = d2i_X509_bio(bio, NULL);
    if (cert == NULL) {
        *err = "d2i_X509_bio() failed";
        rc = NGX_ERROR;
        goto done;
    }

    /* responder */

    aia = X509_get1_ocsp(cert);
    if (aia == NULL) {
        rc = NGX_DECLINED;
        goto done;
    }

#if OPENSSL_VERSION_NUMBER >= 0x10000000L
    s = sk_OPENSSL_STRING_value(aia, 0);
#else
    s = sk_value(aia, 0);
#endif
    if (s == NULL) {
        rc = NGX_DECLINED;
        goto done;
    }

    len = ngx_strlen(s);
    if (len > *out_size) {
        len = *out_size;
        rc = NGX_BUSY;

    } else {
        rc = NGX_OK;
        *out_size = len;
    }

    ngx_memcpy(out, s, len);

    X509_email_free(aia);
    aia = NULL;

    /* issuer */

    if (BIO_eof(bio)) {
        *err = "no issuer certificate in chain";
        rc = NGX_ERROR;
        goto done;
    }

    issuer = d2i_X509_bio(bio, NULL);
    if (issuer == NULL) {
        *err = "d2i_X509_bio() failed";
        rc = NGX_ERROR;
        goto done;
    }

    if (X509_check_issued(issuer, cert) != X509_V_OK) {
        *err = "issuer certificate not next to leaf";
        rc = NGX_ERROR;
        goto done;
    }

    X509_free(issuer);
    X509_free(cert);
    BIO_free(bio);

    return rc;

done:

    if (aia) {
        X509_email_free(aia);
    }

    if (issuer) {
        X509_free(issuer);
    }

    if (cert) {
        X509_free(cert);
    }

    if (bio) {
        BIO_free(bio);
    }

    if (rc == NGX_ERROR) {
        ERR_clear_error();
    }

    return rc;

#endif  /* NGX_HTTP_LUA_USE_OCSP */
}


int
ngx_http_lua_ffi_ssl_create_ocsp_request(const char *chain_data,
    size_t chain_len, unsigned char *out, size_t *out_size, char **err)
{
#ifndef NGX_HTTP_LUA_USE_OCSP

    *err = "no OCSP support";
    return NGX_ERROR;

#else

    int                        rc = NGX_ERROR;
    BIO                       *bio = NULL;
    X509                      *cert = NULL, *issuer = NULL;
    size_t                     len;
    OCSP_CERTID               *id;
    OCSP_REQUEST              *ocsp = NULL;

    /* certificate */

    bio = BIO_new_mem_buf((char *) chain_data, chain_len);
    if (bio == NULL) {
        *err = "BIO_new_mem_buf() failed";
        goto failed;
    }

    cert = d2i_X509_bio(bio, NULL);
    if (cert == NULL) {
        *err = "d2i_X509_bio() failed";
        goto failed;
    }

    if (BIO_eof(bio)) {
        *err = "no issuer certificate in chain";
        goto failed;
    }

    issuer = d2i_X509_bio(bio, NULL);
    if (issuer == NULL) {
        *err = "d2i_X509_bio() failed";
        goto failed;
    }

    ocsp = OCSP_REQUEST_new();
    if (ocsp == NULL) {
        *err = "OCSP_REQUEST_new() failed";
        goto failed;
    }

    id = OCSP_cert_to_id(NULL, cert, issuer);
    if (id == NULL) {
        *err = "OCSP_cert_to_id() failed";
        goto failed;
    }

    if (OCSP_request_add0_id(ocsp, id) == NULL) {
        *err = "OCSP_request_add0_id() failed";
        goto failed;
    }

    len = i2d_OCSP_REQUEST(ocsp, NULL);
    if (len <= 0) {
        *err = "i2d_OCSP_REQUEST() failed";
        goto failed;
    }

    if (len > *out_size) {
        *err = "output buffer too small";
        *out_size = len;
        rc = NGX_BUSY;
        goto failed;
    }

    len = i2d_OCSP_REQUEST(ocsp, &out);
    if (len <=  0) {
        *err = "i2d_OCSP_REQUEST() failed";
        goto failed;
    }

    *out_size = len;

    OCSP_REQUEST_free(ocsp);
    X509_free(issuer);
    X509_free(cert);
    BIO_free(bio);

    return NGX_OK;

failed:

    if (ocsp) {
        OCSP_REQUEST_free(ocsp);
    }

    if (issuer) {
        X509_free(issuer);
    }

    if (cert) {
        X509_free(cert);
    }

    if (bio) {
        BIO_free(bio);
    }

    ERR_clear_error();

    return rc;

#endif  /* NGX_HTTP_LUA_USE_OCSP */
}


int
ngx_http_lua_ffi_ssl_validate_ocsp_response(const u_char *resp,
    size_t resp_len, const char *chain_data, size_t chain_len,
    u_char *errbuf, size_t *errbuf_size)
{
#ifndef NGX_HTTP_LUA_USE_OCSP

    *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                "no OCSP support") - errbuf;
    return NGX_ERROR;

#else

    int                    n;
    BIO                   *bio = NULL;
    X509                  *cert = NULL, *issuer = NULL;
    OCSP_CERTID           *id = NULL;
    OCSP_RESPONSE         *ocsp = NULL;
    OCSP_BASICRESP        *basic = NULL;
    STACK_OF(X509)        *chain = NULL;
    ASN1_GENERALIZEDTIME  *thisupdate, *nextupdate;

    ocsp = d2i_OCSP_RESPONSE(NULL, &resp, resp_len);
    if (ocsp == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "d2i_OCSP_RESPONSE() failed") - errbuf;
        goto error;
    }

    n = OCSP_response_status(ocsp);

    if (n != OCSP_RESPONSE_STATUS_SUCCESSFUL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP response not successful (%d: %s)",
                                    n, OCSP_response_status_str(n)) - errbuf;
        goto error;
    }

    basic = OCSP_response_get1_basic(ocsp);
    if (basic == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP_response_get1_basic() failed")
                       - errbuf;
        goto error;
    }

    /* get issuer certificate from chain */

    bio = BIO_new_mem_buf((char *) chain_data, chain_len);
    if (bio == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "BIO_new_mem_buf() failed")
                       - errbuf;
        goto error;
    }

    cert = d2i_X509_bio(bio, NULL);
    if (cert == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "d2i_X509_bio() failed")
                       - errbuf;
        goto error;
    }

    if (BIO_eof(bio)) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "no issuer certificate in chain")
                       - errbuf;
        goto error;
    }

    issuer = d2i_X509_bio(bio, NULL);
    if (issuer == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "d2i_X509_bio() failed") - errbuf;
        goto error;
    }

    chain = sk_X509_new_null();
    if (chain == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "sk_X509_new_null() failed") - errbuf;
        goto error;
    }

    (void) sk_X509_push(chain, issuer);

    if (OCSP_basic_verify(basic, chain, NULL, OCSP_NOVERIFY) != 1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP_basic_verify() failed") - errbuf;
        goto error;
    }

    id = OCSP_cert_to_id(NULL, cert, issuer);
    if (id == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP_cert_to_id() failed") - errbuf;
        goto error;
    }

    if (OCSP_resp_find_status(basic, id, &n, NULL, NULL,
                              &thisupdate, &nextupdate)
        != 1)
    {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "certificate status not found in the "
                                    "OCSP response") - errbuf;
        goto error;
    }

    if (n != V_OCSP_CERTSTATUS_GOOD) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "certificate status \"%s\" in the OCSP "
                                    "response", OCSP_cert_status_str(n))
                       - errbuf;
        goto error;
    }

    if (OCSP_check_validity(thisupdate, nextupdate, 300, -1) != 1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP_check_validity() failed") - errbuf;
        goto error;
    }

    sk_X509_free(chain);
    X509_free(cert);
    X509_free(issuer);
    BIO_free(bio);
    OCSP_CERTID_free(id);
    OCSP_BASICRESP_free(basic);
    OCSP_RESPONSE_free(ocsp);

    return NGX_OK;

error:

    if (chain) {
        sk_X509_free(chain);
    }

    if (id) {
        OCSP_CERTID_free(id);
    }

    if (basic) {
        OCSP_BASICRESP_free(basic);
    }

    if (ocsp) {
        OCSP_RESPONSE_free(ocsp);
    }

    if (cert) {
        X509_free(cert);
    }

    if (issuer) {
        X509_free(issuer);
    }

    if (bio) {
        BIO_free(bio);
    }

    ERR_clear_error();

    return NGX_ERROR;

#endif  /* NGX_HTTP_LUA_USE_OCSP */
}


#ifdef NGX_HTTP_LUA_USE_OCSP
static int
ngx_http_lua_ssl_empty_status_callback(ngx_ssl_conn_t *ssl_conn, void *data)
{
    return SSL_TLSEXT_ERR_OK;
}
#endif


int
ngx_http_lua_ffi_ssl_set_ocsp_status_resp(ngx_http_request_t *r,
    const u_char *resp, size_t resp_len, char **err)
{
#ifndef NGX_HTTP_LUA_USE_OCSP

    *err = "no OCSP support";
    return NGX_ERROR;

#else

    u_char                  *p;
    SSL_CTX                 *ctx;
    ngx_ssl_conn_t          *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

#ifdef SSL_CTRL_GET_TLSEXT_STATUS_REQ_TYPE
    if (SSL_get_tlsext_status_type(ssl_conn) == -1) {
#else
    if (ssl_conn->tlsext_status_type == -1) {
#endif
        dd("no ocsp status req from client");
        return NGX_DECLINED;
    }

    /* we have to register an empty status callback here otherwise
     * OpenSSL won't send the response staple. */

    ctx = SSL_get_SSL_CTX(ssl_conn);
    SSL_CTX_set_tlsext_status_cb(ctx,
                                 ngx_http_lua_ssl_empty_status_callback);

    p = OPENSSL_malloc(resp_len);
    if (p == NULL) {
        *err = "OPENSSL_malloc() failed";
        return NGX_ERROR;
    }

    ngx_memcpy(p, resp, resp_len);

    dd("set ocsp resp: resp_len=%d", (int) resp_len);
    (void) SSL_set_tlsext_status_ocsp_resp(ssl_conn, p, resp_len);

    return NGX_OK;

#endif  /* NGX_HTTP_LUA_USE_OCSP */
}


#endif  /* NGX_HTTP_SSL */
