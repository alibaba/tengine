
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SSL_H_INCLUDED_
#define _NGX_HTTP_LUA_SSL_H_INCLUDED_


#include "ngx_http_lua_common.h"


#if (NGX_HTTP_SSL)


typedef struct {
    ngx_connection_t        *connection; /* original true connection */
    ngx_http_request_t      *request;
    ngx_pool_cleanup_pt     *cleanup;

    ngx_ssl_session_t       *session;    /* return value for openssl's
                                          * session_get_cb */

    ngx_str_t                session_id;

#ifdef HAVE_PROXY_SSL_PATCH
    X509_STORE_CTX          *x509_store;
    ngx_pool_t              *pool;
#endif

    int                      exit_code;  /* exit code for openssl's
                                            set_client_hello_cb or
                                            set_cert_cb callback or
                                            SSL_CTX_set_cert_verify_callback */

    int                      ctx_ref;  /*  reference to anchor
                                           request ctx data in lua
                                           registry */

#ifdef HAVE_PROXY_SSL_PATCH
    /* same size as count field of ngx_http_request_t */
    unsigned                 original_request_count:16;
#endif
    unsigned                 done:1;
    unsigned                 aborted:1;

    unsigned                 entered_client_hello_handler:1;
    unsigned                 entered_cert_handler:1;
    unsigned                 entered_sess_fetch_handler:1;
#ifdef HAVE_PROXY_SSL_PATCH
    unsigned                 entered_proxy_ssl_verify_handler:1;
#endif
} ngx_http_lua_ssl_ctx_t;


typedef struct {
    ngx_ssl_t     *ssl;
    ngx_fd_t       fd;
    ngx_str_t      name;
} ngx_http_lua_ssl_key_log_t;


ngx_int_t ngx_http_lua_ssl_init(ngx_log_t *log);


extern int ngx_http_lua_ssl_ctx_index;
extern int ngx_http_lua_ssl_key_log_index;


#endif


#endif  /* _NGX_HTTP_LUA_SSL_H_INCLUDED_ */
