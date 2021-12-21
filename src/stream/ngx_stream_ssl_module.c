
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_stream.h>


typedef ngx_int_t (*ngx_ssl_variable_handler_pt)(ngx_connection_t *c,
    ngx_pool_t *pool, ngx_str_t *s);


#define NGX_DEFAULT_CIPHERS     "HIGH:!aNULL:!MD5"
#define NGX_DEFAULT_ECDH_CURVE  "auto"


static ngx_int_t ngx_stream_ssl_handler(ngx_stream_session_t *s);
static ngx_int_t ngx_stream_ssl_init_connection(ngx_ssl_t *ssl,
    ngx_connection_t *c);
static void ngx_stream_ssl_handshake_handler(ngx_connection_t *c);
#ifdef SSL_CTRL_SET_TLSEXT_HOSTNAME
int ngx_stream_ssl_servername(ngx_ssl_conn_t *ssl_conn, int *ad, void *arg);
#endif
#ifdef SSL_R_CERT_CB_ERROR
static int ngx_stream_ssl_certificate(ngx_ssl_conn_t *ssl_conn, void *arg);
#endif
static ngx_int_t ngx_stream_ssl_static_variable(ngx_stream_session_t *s,
    ngx_stream_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_stream_ssl_variable(ngx_stream_session_t *s,
    ngx_stream_variable_value_t *v, uintptr_t data);

static ngx_int_t ngx_stream_ssl_add_variables(ngx_conf_t *cf);
static void *ngx_stream_ssl_create_conf(ngx_conf_t *cf);
static char *ngx_stream_ssl_merge_conf(ngx_conf_t *cf, void *parent,
    void *child);

static ngx_int_t ngx_stream_ssl_compile_certificates(ngx_conf_t *cf,
    ngx_stream_ssl_conf_t *conf);

static char *ngx_stream_ssl_password_file(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_stream_ssl_session_cache(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_stream_ssl_init(ngx_conf_t *cf);

#if (NGX_STREAM_SNI)
int ngx_stream_ssl_servername(ngx_ssl_conn_t *ssl_conn, int *ad,
    void *arg);
#endif

#if (T_NGX_HAVE_DTLS)
static char *ngx_stream_set_ssl_protocols(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
#endif

static ngx_conf_bitmask_t  ngx_stream_ssl_protocols[] = {
    { ngx_string("SSLv2"), NGX_SSL_SSLv2 },
    { ngx_string("SSLv3"), NGX_SSL_SSLv3 },
    { ngx_string("TLSv1"), NGX_SSL_TLSv1 },
    { ngx_string("TLSv1.1"), NGX_SSL_TLSv1_1 },
    { ngx_string("TLSv1.2"), NGX_SSL_TLSv1_2 },
    { ngx_string("TLSv1.3"), NGX_SSL_TLSv1_3 },

#if (T_NGX_HAVE_DTLS)
    { ngx_string("DTLSv1"), NGX_SSL_DTLSv1 },
    { ngx_string("DTLSv1.2"), NGX_SSL_DTLSv1_2 },
#endif
    { ngx_null_string, 0 }
};


static ngx_conf_enum_t  ngx_stream_ssl_verify[] = {
    { ngx_string("off"), 0 },
    { ngx_string("on"), 1 },
    { ngx_string("optional"), 2 },
    { ngx_string("optional_no_ca"), 3 },
    { ngx_null_string, 0 }
};


static ngx_command_t  ngx_stream_ssl_commands[] = {

    { ngx_string("ssl_handshake_timeout"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, handshake_timeout),
      NULL },

    { ngx_string("ssl_certificate"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_array_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, certificates),
      NULL },

    { ngx_string("ssl_certificate_key"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_array_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, certificate_keys),
      NULL },

    { ngx_string("ssl_password_file"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_stream_ssl_password_file,
      NGX_STREAM_SRV_CONF_OFFSET,
      0,
      NULL },

#if (T_NGX_SSL_NTLS)
    { ngx_string("enable_ntls"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, enable_ntls),
      NULL },

    { ngx_string("ssl_enc_certificate"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, enc_certificate),
      NULL },

    { ngx_string("ssl_enc_certificate_key"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, enc_certificate_key),
      NULL },

    { ngx_string("ssl_sign_certificate"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, sign_certificate),
      NULL },

    { ngx_string("ssl_sign_certificate_key"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, sign_certificate_key),
      NULL },
#endif

    { ngx_string("ssl_dhparam"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, dhparam),
      NULL },

    { ngx_string("ssl_ecdh_curve"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, ecdh_curve),
      NULL },

    { ngx_string("ssl_protocols"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_1MORE,
#if (T_NGX_HAVE_DTLS)
      ngx_stream_set_ssl_protocols,
#else
      ngx_conf_set_bitmask_slot,
#endif
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, protocols),
      &ngx_stream_ssl_protocols },

    { ngx_string("ssl_ciphers"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, ciphers),
      NULL },

    { ngx_string("ssl_verify_client"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_enum_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, verify),
      &ngx_stream_ssl_verify },

    { ngx_string("ssl_verify_depth"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, verify_depth),
      NULL },

    { ngx_string("ssl_client_certificate"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, client_certificate),
      NULL },

    { ngx_string("ssl_trusted_certificate"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, trusted_certificate),
      NULL },

    { ngx_string("ssl_prefer_server_ciphers"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, prefer_server_ciphers),
      NULL },

    { ngx_string("ssl_session_cache"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE12,
      ngx_stream_ssl_session_cache,
      NGX_STREAM_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("ssl_session_tickets"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, session_tickets),
      NULL },

    { ngx_string("ssl_session_ticket_key"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_array_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, session_ticket_keys),
      NULL },

    { ngx_string("ssl_session_timeout"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_sec_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, session_timeout),
      NULL },

    { ngx_string("ssl_crl"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, crl),
      NULL },

#if (NGX_STREAM_SNI)
    { ngx_string("ssl_sni_force"),
      NGX_STREAM_MAIN_CONF|NGX_STREAM_SRV_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_STREAM_SRV_CONF_OFFSET,
      offsetof(ngx_stream_ssl_conf_t, sni_force),
      NULL },
#endif

      ngx_null_command
};


static ngx_stream_module_t  ngx_stream_ssl_module_ctx = {
    ngx_stream_ssl_add_variables,          /* preconfiguration */
    ngx_stream_ssl_init,                   /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    ngx_stream_ssl_create_conf,            /* create server configuration */
    ngx_stream_ssl_merge_conf              /* merge server configuration */
};


ngx_module_t  ngx_stream_ssl_module = {
    NGX_MODULE_V1,
    &ngx_stream_ssl_module_ctx,            /* module context */
    ngx_stream_ssl_commands,               /* module directives */
    NGX_STREAM_MODULE,                     /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_stream_variable_t  ngx_stream_ssl_vars[] = {

    { ngx_string("ssl_protocol"), NULL, ngx_stream_ssl_static_variable,
      (uintptr_t) ngx_ssl_get_protocol, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_cipher"), NULL, ngx_stream_ssl_static_variable,
      (uintptr_t) ngx_ssl_get_cipher_name, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_ciphers"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_ciphers, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_curves"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_curves, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_session_id"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_session_id, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_session_reused"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_session_reused, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_server_name"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_server_name, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_cert"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_certificate, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_raw_cert"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_raw_certificate,
      NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_escaped_cert"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_escaped_certificate,
      NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_s_dn"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_subject_dn, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_i_dn"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_issuer_dn, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_serial"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_serial_number, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_fingerprint"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_fingerprint, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_verify"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_client_verify, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_v_start"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_client_v_start, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_v_end"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_client_v_end, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_client_v_remain"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_client_v_remain, NGX_STREAM_VAR_CHANGEABLE, 0 },

#if (T_NGX_SSL_HANDSHAKE_TIME)
    /* $ssl_shandshakd_time deprecated and will be removed in the next release */
    { ngx_string("ssl_handshakd_time"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_handshake_time, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_handshake_time"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_handshake_time, NGX_STREAM_VAR_CHANGEABLE, 0 },

    { ngx_string("ssl_handshake_time_msec"), NULL, ngx_stream_ssl_variable,
      (uintptr_t) ngx_ssl_get_handshake_time_msec, NGX_STREAM_VAR_CHANGEABLE, 0 },
#endif

      ngx_stream_null_variable
};


static ngx_str_t ngx_stream_ssl_sess_id_ctx = ngx_string("STREAM");


static ngx_int_t
ngx_stream_ssl_handler(ngx_stream_session_t *s)
{
    long                    rc;
    X509                   *cert;
    ngx_int_t               rv;
    ngx_connection_t       *c;
    ngx_stream_ssl_conf_t  *sslcf;

    if (!s->ssl) {
        return NGX_OK;
    }

    c = s->connection;

    sslcf = ngx_stream_get_module_srv_conf(s, ngx_stream_ssl_module);

    if (c->ssl == NULL) {
        c->log->action = "SSL handshaking";

        rv = ngx_stream_ssl_init_connection(&sslcf->ssl, c);

        if (rv != NGX_OK) {
            return rv;
        }
    }

    if (sslcf->verify) {
        rc = SSL_get_verify_result(c->ssl->connection);

        if (rc != X509_V_OK
            && (sslcf->verify != 3 || !ngx_ssl_verify_error_optional(rc)))
        {
            ngx_log_error(NGX_LOG_INFO, c->log, 0,
                          "client SSL certificate verify error: (%l:%s)",
                          rc, X509_verify_cert_error_string(rc));

            ngx_ssl_remove_cached_session(c->ssl->session_ctx,
                                       (SSL_get0_session(c->ssl->connection)));
            return NGX_ERROR;
        }

        if (sslcf->verify == 1) {
            cert = SSL_get_peer_certificate(c->ssl->connection);

            if (cert == NULL) {
                ngx_log_error(NGX_LOG_INFO, c->log, 0,
                              "client sent no required SSL certificate");

                ngx_ssl_remove_cached_session(c->ssl->session_ctx,
                                       (SSL_get0_session(c->ssl->connection)));
                return NGX_ERROR;
            }

            X509_free(cert);
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_stream_ssl_init_connection(ngx_ssl_t *ssl, ngx_connection_t *c)
{
    ngx_int_t                    rc;
    ngx_stream_session_t        *s;
    ngx_stream_ssl_conf_t       *sslcf;
    ngx_stream_core_srv_conf_t  *cscf;

    s = c->data;

    cscf = ngx_stream_get_module_srv_conf(s, ngx_stream_core_module);

    if (
#if (T_NGX_HAVE_DTLS)
        c->type == SOCK_STREAM &&
#endif
        cscf->tcp_nodelay && ngx_tcp_nodelay(c) != NGX_OK) {
        return NGX_ERROR;
    }

    if (ngx_ssl_create_connection(ssl, c, 0) != NGX_OK) {
        return NGX_ERROR;
    }

#if (T_NGX_SSL_HANDSHAKE_TIME)
    {
    /* ssl handshake start time */
    ngx_time_t *tp = ngx_timeofday();
    c->ssl->handshake_start_msec = tp->sec * 1000 + tp->msec;
    }
#endif
#if (T_NGX_SSL_NTLS)
    sslcf = ngx_stream_get_module_srv_conf(s, ngx_stream_ssl_module);

    if (sslcf->enable_ntls) {
        SSL_enable_ntls(c->ssl->connection);
    }
#endif

    rc = ngx_ssl_handshake(c);

    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    if (rc == NGX_AGAIN) {
#if (T_NGX_SSL_NTLS)
        ;
#else
        sslcf = ngx_stream_get_module_srv_conf(s, ngx_stream_ssl_module);
#endif
        ngx_add_timer(c->read, sslcf->handshake_timeout);

        c->ssl->handler = ngx_stream_ssl_handshake_handler;

        return NGX_AGAIN;
    }

    /* rc == NGX_OK */

    return NGX_OK;
}


static void
ngx_stream_ssl_handshake_handler(ngx_connection_t *c)
{
    ngx_stream_session_t  *s;

    s = c->data;

    if (!c->ssl->handshaked) {
        ngx_stream_finalize_session(s, NGX_STREAM_INTERNAL_SERVER_ERROR);
        return;
    }

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    ngx_stream_core_run_phases(s);
}

#ifdef NGX_STREAM_SNI
static ngx_int_t
ngx_stream_find_virtual_server(ngx_connection_t *c,
    ngx_stream_virtual_names_t *virtual_names, ngx_str_t *host,
    ngx_stream_core_srv_conf_t **cscfp)
{
    ngx_stream_core_srv_conf_t  *cscf;

    if (virtual_names == NULL) {
        return NGX_DECLINED;
    }

    cscf = ngx_hash_find_combined(&virtual_names->names,
                                  ngx_hash_key(host->data, host->len),
                                  host->data, host->len);

    if (cscf) {
        *cscfp = cscf;
        return NGX_OK;
    }

    return NGX_DECLINED;
}

int
ngx_stream_ssl_servername(ngx_ssl_conn_t *ssl_conn, int *ad, void *arg)
{
    ngx_str_t                   host;
    const char                 *servername;
    ngx_connection_t           *c;
    ngx_stream_session_t       *s;
    ngx_stream_ssl_conf_t      *sscf;
    ngx_stream_core_srv_conf_t *cscf;

    c = ngx_ssl_get_connection(ssl_conn);
    s = c->data;

    servername = SSL_get_servername(ssl_conn, TLSEXT_NAMETYPE_host_name);

    if (servername == NULL) {
        goto not_match;
    }

    if (c->ssl->renegotiation) {
        return SSL_TLSEXT_ERR_NOACK;
    }

    host.len = ngx_strlen(servername);
    if (host.len == 0) {
        goto not_match;
    }

    host.data = (u_char *) servername;


    if (ngx_stream_find_virtual_server(c, s->addr_conf->virtual_names, &host,
                                       &cscf)
        != NGX_OK)
    {
        goto not_match;
    }

    ngx_set_connection_log(c, cscf->error_log);

    s->main_conf = cscf->ctx->main_conf;
    s->srv_conf  = cscf->ctx->srv_conf;

    sscf = ngx_stream_get_module_srv_conf(cscf->ctx, ngx_stream_ssl_module);

    if (sscf->ssl.ctx) {
        SSL_set_SSL_CTX(ssl_conn, sscf->ssl.ctx);

        /*
         * SSL_set_SSL_CTX() only changes certs as of 1.0.0d
         * adjust other things we care about
         */

        SSL_set_verify(ssl_conn, SSL_CTX_get_verify_mode(sscf->ssl.ctx),
                       SSL_CTX_get_verify_callback(sscf->ssl.ctx));

        SSL_set_verify_depth(ssl_conn, SSL_CTX_get_verify_depth(sscf->ssl.ctx));

#ifdef SSL_CTRL_CLEAR_OPTIONS
        /* only in 0.9.8m+ */
        SSL_clear_options(ssl_conn, SSL_get_options(ssl_conn) &
                                    ~SSL_CTX_get_options(sscf->ssl.ctx));
#endif

        SSL_set_options(ssl_conn, SSL_CTX_get_options(sscf->ssl.ctx));
    }

    return SSL_TLSEXT_ERR_OK;

not_match:
    sscf = ngx_stream_get_module_srv_conf(s, ngx_stream_ssl_module);

    if (sscf->sni_force) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "SSL sni not match, sni:%s, reject", servername?servername:"NULL");
        return SSL_TLSEXT_ERR_ALERT_FATAL;

    } else {
        return SSL_TLSEXT_ERR_NOACK;
    }
}

#else
#ifdef SSL_CTRL_SET_TLSEXT_HOSTNAME

int
ngx_stream_ssl_servername(ngx_ssl_conn_t *ssl_conn, int *ad, void *arg)
{
    return SSL_TLSEXT_ERR_OK;
}

#endif
#endif

#ifdef SSL_R_CERT_CB_ERROR

int
ngx_stream_ssl_certificate(ngx_ssl_conn_t *ssl_conn, void *arg)
{
    ngx_str_t                    cert, key;
    ngx_uint_t                   i, nelts;
    ngx_connection_t            *c;
    ngx_stream_session_t        *s;
    ngx_stream_ssl_conf_t       *sslcf;
    ngx_stream_complex_value_t  *certs, *keys;

    c = ngx_ssl_get_connection(ssl_conn);

    if (c->ssl->handshaked) {
        return 0;
    }

    s = c->data;

    sslcf = arg;

    nelts = sslcf->certificate_values->nelts;
    certs = sslcf->certificate_values->elts;
    keys = sslcf->certificate_key_values->elts;

    for (i = 0; i < nelts; i++) {

        if (ngx_stream_complex_value(s, &certs[i], &cert) != NGX_OK) {
            return 0;
        }

        ngx_log_debug1(NGX_LOG_DEBUG_STREAM, c->log, 0,
                       "ssl cert: \"%s\"", cert.data);

        if (ngx_stream_complex_value(s, &keys[i], &key) != NGX_OK) {
            return 0;
        }

        ngx_log_debug1(NGX_LOG_DEBUG_STREAM, c->log, 0,
                       "ssl key: \"%s\"", key.data);

        if (ngx_ssl_connection_certificate(c, c->pool, &cert, &key,
                                           sslcf->passwords)
            != NGX_OK)
        {
            return 0;
        }
    }

    return 1;
}

#endif


static ngx_int_t
ngx_stream_ssl_static_variable(ngx_stream_session_t *s,
    ngx_stream_variable_value_t *v, uintptr_t data)
{
    ngx_ssl_variable_handler_pt  handler = (ngx_ssl_variable_handler_pt) data;

    size_t     len;
    ngx_str_t  str;

    if (s->connection->ssl) {

        (void) handler(s->connection, NULL, &str);

        v->data = str.data;

        for (len = 0; v->data[len]; len++) { /* void */ }

        v->len = len;
        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;

        return NGX_OK;
    }

    v->not_found = 1;

    return NGX_OK;
}


static ngx_int_t
ngx_stream_ssl_variable(ngx_stream_session_t *s,
    ngx_stream_variable_value_t *v, uintptr_t data)
{
    ngx_ssl_variable_handler_pt  handler = (ngx_ssl_variable_handler_pt) data;

    ngx_str_t  str;

    if (s->connection->ssl) {

        if (handler(s->connection, s->connection->pool, &str) != NGX_OK) {
            return NGX_ERROR;
        }

        v->len = str.len;
        v->data = str.data;

        if (v->len) {
            v->valid = 1;
            v->no_cacheable = 0;
            v->not_found = 0;

            return NGX_OK;
        }
    }

    v->not_found = 1;

    return NGX_OK;
}


static ngx_int_t
ngx_stream_ssl_add_variables(ngx_conf_t *cf)
{
    ngx_stream_variable_t  *var, *v;

    for (v = ngx_stream_ssl_vars; v->name.len; v++) {
        var = ngx_stream_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }

        var->get_handler = v->get_handler;
        var->data = v->data;
    }

    return NGX_OK;
}


static void *
ngx_stream_ssl_create_conf(ngx_conf_t *cf)
{
    ngx_stream_ssl_conf_t  *scf;

    scf = ngx_pcalloc(cf->pool, sizeof(ngx_stream_ssl_conf_t));
    if (scf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     scf->listen = 0;
     *     scf->protocols = 0;
     *     scf->certificate_values = NULL;
     *     scf->dhparam = { 0, NULL };
     *     scf->ecdh_curve = { 0, NULL };
     *     scf->client_certificate = { 0, NULL };
     *     scf->trusted_certificate = { 0, NULL };
     *     scf->crl = { 0, NULL };
     *     scf->ciphers = { 0, NULL };
     *     scf->shm_zone = NULL;
     */

    scf->handshake_timeout = NGX_CONF_UNSET_MSEC;
    scf->certificates = NGX_CONF_UNSET_PTR;
    scf->certificate_keys = NGX_CONF_UNSET_PTR;
    scf->passwords = NGX_CONF_UNSET_PTR;
    scf->prefer_server_ciphers = NGX_CONF_UNSET;
    scf->verify = NGX_CONF_UNSET_UINT;
    scf->verify_depth = NGX_CONF_UNSET_UINT;
    scf->builtin_session_cache = NGX_CONF_UNSET;
    scf->session_timeout = NGX_CONF_UNSET;
    scf->session_tickets = NGX_CONF_UNSET;
    scf->session_ticket_keys = NGX_CONF_UNSET_PTR;

#if (NGX_STREAM_SNI)
    scf->sni_force = NGX_CONF_UNSET;
#endif

#if (T_NGX_SSL_NTLS)
    scf->enable_ntls = NGX_CONF_UNSET;
#endif
    return scf;
}


static char *
ngx_stream_ssl_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_stream_ssl_conf_t *prev = parent;
    ngx_stream_ssl_conf_t *conf = child;

    ngx_pool_cleanup_t  *cln;

    ngx_conf_merge_msec_value(conf->handshake_timeout,
                         prev->handshake_timeout, 60000);

    ngx_conf_merge_value(conf->session_timeout,
                         prev->session_timeout, 300);

    ngx_conf_merge_value(conf->prefer_server_ciphers,
                         prev->prefer_server_ciphers, 0);

    ngx_conf_merge_bitmask_value(conf->protocols, prev->protocols,
                         (NGX_CONF_BITMASK_SET|NGX_SSL_TLSv1
                          |NGX_SSL_TLSv1_1|NGX_SSL_TLSv1_2));

    ngx_conf_merge_uint_value(conf->verify, prev->verify, 0);
    ngx_conf_merge_uint_value(conf->verify_depth, prev->verify_depth, 1);

    ngx_conf_merge_ptr_value(conf->certificates, prev->certificates, NULL);
    ngx_conf_merge_ptr_value(conf->certificate_keys, prev->certificate_keys,
                         NULL);

    ngx_conf_merge_ptr_value(conf->passwords, prev->passwords, NULL);

#if (T_NGX_SSL_NTLS)
    ngx_conf_merge_value(conf->enable_ntls, prev->enable_ntls, 0);
    ngx_conf_merge_str_value(conf->enc_certificate,
                             prev->enc_certificate, "");
    ngx_conf_merge_str_value(conf->enc_certificate_key,
                             prev->enc_certificate_key, "");
    ngx_conf_merge_str_value(conf->sign_certificate,
                             prev->sign_certificate, "");
    ngx_conf_merge_str_value(conf->sign_certificate_key,
                             prev->sign_certificate_key, "");
#endif

    ngx_conf_merge_str_value(conf->dhparam, prev->dhparam, "");

    ngx_conf_merge_str_value(conf->client_certificate, prev->client_certificate,
                         "");
    ngx_conf_merge_str_value(conf->trusted_certificate,
                         prev->trusted_certificate, "");
    ngx_conf_merge_str_value(conf->crl, prev->crl, "");

    ngx_conf_merge_str_value(conf->ecdh_curve, prev->ecdh_curve,
                         NGX_DEFAULT_ECDH_CURVE);

    ngx_conf_merge_str_value(conf->ciphers, prev->ciphers, NGX_DEFAULT_CIPHERS);

#if (NGX_STREAM_SNI)
    ngx_conf_merge_value(conf->sni_force, prev->sni_force, 0);
    if (!conf->listen)
#endif

    conf->ssl.log = cf->log;

    if (!conf->listen) {
        return NGX_CONF_OK;
    }

    if (conf->certificates == NULL
#if (T_NGX_SSL_NTLS)
        && conf->enc_certificate.len == 0
        && conf->sign_certificate.len == 0
#endif
    ) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
#if (T_NGX_SSL_NTLS)
                      "no \"ssl_certificate\", \"ssl_enc_certificate\" or "
                      "\"ssl_sign_certificate\" is defined for "
#else
                      "no \"ssl_certificate\" is defined for "
#endif
                      "the \"listen ... ssl\" directive in %s:%ui",
                      conf->file, conf->line);
        return NGX_CONF_ERROR;
    }
#if (T_NGX_SSL_NTLS)
    if (conf->certificates != NULL) {
#endif
    if (conf->certificate_keys == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "no \"ssl_certificate_key\" is defined for "
                      "the \"listen ... ssl\" directive in %s:%ui",
                      conf->file, conf->line);
        return NGX_CONF_ERROR;
    }

    if (conf->certificate_keys->nelts < conf->certificates->nelts) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "no \"ssl_certificate_key\" is defined "
                      "for certificate \"%V\" and "
                      "the \"listen ... ssl\" directive in %s:%ui",
                      ((ngx_str_t *) conf->certificates->elts)
                      + conf->certificates->nelts - 1,
                      conf->file, conf->line);
        return NGX_CONF_ERROR;
    }
#if (T_NGX_SSL_NTLS)
    }

    if (conf->enc_certificate.len != 0 || conf->sign_certificate.len != 0) {
        if (conf->enc_certificate.len == 0) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "no \"ssl_enc_certificate\" is defined for "
                          "the \"ssl\" directive in %s:%ui",
                          conf->file, conf->line);
            return NGX_CONF_ERROR;
        }

        if (conf->sign_certificate.len == 0) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "no \"ssl_sign_certificate\" is defined for "
                          "the \"ssl\" directive in %s:%ui",
                          conf->file, conf->line);
            return NGX_CONF_ERROR;
        }

        if (conf->enc_certificate_key.len == 0) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "no \"ssl_enc_certificate_key\" is defined for "
                          "the \"ssl\" directive in %s:%ui",
                          conf->file, conf->line);
            return NGX_CONF_ERROR;
        }

        if (conf->sign_certificate_key.len == 0) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "no \"ssl_sign_certificate_key\" is defined for "
                          "the \"ssl\" directive in %s:%ui",
                          conf->file, conf->line);
            return NGX_CONF_ERROR;
        }
    }
#endif

    if (ngx_ssl_create(&conf->ssl, conf->protocols, NULL) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {
        ngx_ssl_cleanup_ctx(&conf->ssl);
        return NGX_CONF_ERROR;
    }

    cln->handler = ngx_ssl_cleanup_ctx;
    cln->data = &conf->ssl;

#if (NGX_STREAM_SNI)
#if (SSL_CTRL_SET_TLSEXT_HOSTNAME)
    if (SSL_CTX_set_tlsext_servername_callback(conf->ssl.ctx,
                                               ngx_stream_ssl_servername)
        == 0)
    {
#endif
        ngx_log_error(NGX_LOG_WARN, cf->log, 0,
            "nginx was built with SNI support, however, now it is linked "
            "dynamically to an OpenSSL library which has no tlsext support, "
            "therefore SNI is not available");
#if (SSL_CTRL_SET_TLSEXT_HOSTNAME)
    }
#endif
#else
#ifdef SSL_CTRL_SET_TLSEXT_HOSTNAME
    SSL_CTX_set_tlsext_servername_callback(conf->ssl.ctx,
                                           ngx_stream_ssl_servername);
#endif
#endif

    if (ngx_stream_ssl_compile_certificates(cf, conf) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    if (conf->certificate_values) {

#ifdef SSL_R_CERT_CB_ERROR

        /* install callback to lookup certificates */

        SSL_CTX_set_cert_cb(conf->ssl.ctx, ngx_stream_ssl_certificate, conf);

#else
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "variables in "
                      "\"ssl_certificate\" and \"ssl_certificate_key\" "
                      "directives are not supported on this platform");
        return NGX_CONF_ERROR;
#endif

    } else {

        /* configure certificates */

        if (ngx_ssl_certificates(cf, &conf->ssl, conf->certificates,
                                 conf->certificate_keys, conf->passwords)
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }
    }
#if (T_NGX_SSL_NTLS)
    if (conf->enc_certificate.len != 0) {
        if (ngx_ssl_certificate(cf, &conf->ssl, &conf->enc_certificate,
                                &conf->enc_certificate_key, conf->passwords,
                                SSL_ENC_CERT)
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }
    }

    if (conf->sign_certificate.len != 0) {
        if (ngx_ssl_certificate(cf, &conf->ssl, &conf->sign_certificate,
                                &conf->sign_certificate_key, conf->passwords,
                                SSL_SIGN_CERT)
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }
    }
#endif
    if (ngx_ssl_ciphers(cf, &conf->ssl, &conf->ciphers,
                        conf->prefer_server_ciphers)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    if (conf->verify) {

        if (conf->client_certificate.len == 0 && conf->verify != 3) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "no ssl_client_certificate for ssl_verify_client");
            return NGX_CONF_ERROR;
        }

        if (ngx_ssl_client_certificate(cf, &conf->ssl,
                                       &conf->client_certificate,
                                       conf->verify_depth)
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }

        if (ngx_ssl_trusted_certificate(cf, &conf->ssl,
                                        &conf->trusted_certificate,
                                        conf->verify_depth)
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }

        if (ngx_ssl_crl(cf, &conf->ssl, &conf->crl) != NGX_OK) {
            return NGX_CONF_ERROR;
        }
    }

    if (ngx_ssl_dhparam(cf, &conf->ssl, &conf->dhparam) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    if (ngx_ssl_ecdh_curve(cf, &conf->ssl, &conf->ecdh_curve) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    ngx_conf_merge_value(conf->builtin_session_cache,
                         prev->builtin_session_cache, NGX_SSL_NONE_SCACHE);

    if (conf->shm_zone == NULL) {
        conf->shm_zone = prev->shm_zone;
    }

    if (ngx_ssl_session_cache(&conf->ssl, &ngx_stream_ssl_sess_id_ctx,
                              conf->certificates, conf->builtin_session_cache,
                              conf->shm_zone, conf->session_timeout)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    ngx_conf_merge_value(conf->session_tickets,
                         prev->session_tickets, 1);

#ifdef SSL_OP_NO_TICKET
    if (!conf->session_tickets) {
        SSL_CTX_set_options(conf->ssl.ctx, SSL_OP_NO_TICKET);
    }
#endif

    ngx_conf_merge_ptr_value(conf->session_ticket_keys,
                         prev->session_ticket_keys, NULL);

    if (ngx_ssl_session_ticket_keys(cf, &conf->ssl, conf->session_ticket_keys)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_stream_ssl_compile_certificates(ngx_conf_t *cf,
    ngx_stream_ssl_conf_t *conf)
{
    ngx_str_t                           *cert, *key;
    ngx_uint_t                           i, nelts;
    ngx_stream_complex_value_t          *cv;
    ngx_stream_compile_complex_value_t   ccv;

#if (T_NGX_SSL_NTLS)
    if (conf->certificates == NULL)
        return NGX_OK;
#endif
    cert = conf->certificates->elts;
    key = conf->certificate_keys->elts;
    nelts = conf->certificates->nelts;

    for (i = 0; i < nelts; i++) {

        if (ngx_stream_script_variables_count(&cert[i])) {
            goto found;
        }

        if (ngx_stream_script_variables_count(&key[i])) {
            goto found;
        }
    }

    return NGX_OK;

found:

    conf->certificate_values = ngx_array_create(cf->pool, nelts,
                                           sizeof(ngx_stream_complex_value_t));
    if (conf->certificate_values == NULL) {
        return NGX_ERROR;
    }

    conf->certificate_key_values = ngx_array_create(cf->pool, nelts,
                                           sizeof(ngx_stream_complex_value_t));
    if (conf->certificate_key_values == NULL) {
        return NGX_ERROR;
    }

    for (i = 0; i < nelts; i++) {

        cv = ngx_array_push(conf->certificate_values);
        if (cv == NULL) {
            return NGX_ERROR;
        }

        ngx_memzero(&ccv, sizeof(ngx_stream_compile_complex_value_t));

        ccv.cf = cf;
        ccv.value = &cert[i];
        ccv.complex_value = cv;
        ccv.zero = 1;

        if (ngx_stream_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_ERROR;
        }

        cv = ngx_array_push(conf->certificate_key_values);
        if (cv == NULL) {
            return NGX_ERROR;
        }

        ngx_memzero(&ccv, sizeof(ngx_stream_compile_complex_value_t));

        ccv.cf = cf;
        ccv.value = &key[i];
        ccv.complex_value = cv;
        ccv.zero = 1;

        if (ngx_stream_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    conf->passwords = ngx_ssl_preserve_passwords(cf, conf->passwords);
    if (conf->passwords == NULL) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static char *
ngx_stream_ssl_password_file(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_stream_ssl_conf_t  *scf = conf;

    ngx_str_t  *value;

    if (scf->passwords != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    value = cf->args->elts;

    scf->passwords = ngx_ssl_read_password_file(cf, &value[1]);

    if (scf->passwords == NULL) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}

#if (T_NGX_HAVE_DTLS)
static char *
ngx_stream_set_ssl_protocols(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_stream_ssl_conf_t  *scf = conf;

    char  *rv;

    rv = ngx_conf_set_bitmask_slot(cf, cmd, conf);

    if (rv != NGX_CONF_OK) {
        return rv;
    }

    /* DTLS protocol requires corresponding TLS version to be set */

    if (scf->protocols & NGX_SSL_DTLSv1) {
        scf->protocols |= NGX_SSL_TLSv1;
    }

    if (scf->protocols & NGX_SSL_DTLSv1_2) {
        scf->protocols |= NGX_SSL_TLSv1_2;
    }

    return NGX_CONF_OK;
}
#endif

static char *
ngx_stream_ssl_session_cache(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_stream_ssl_conf_t  *scf = conf;

    size_t       len;
    ngx_str_t   *value, name, size;
    ngx_int_t    n;
    ngx_uint_t   i, j;

    value = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {

        if (ngx_strcmp(value[i].data, "off") == 0) {
            scf->builtin_session_cache = NGX_SSL_NO_SCACHE;
            continue;
        }

        if (ngx_strcmp(value[i].data, "none") == 0) {
            scf->builtin_session_cache = NGX_SSL_NONE_SCACHE;
            continue;
        }

        if (ngx_strcmp(value[i].data, "builtin") == 0) {
            scf->builtin_session_cache = NGX_SSL_DFLT_BUILTIN_SCACHE;
            continue;
        }

        if (value[i].len > sizeof("builtin:") - 1
            && ngx_strncmp(value[i].data, "builtin:", sizeof("builtin:") - 1)
               == 0)
        {
            n = ngx_atoi(value[i].data + sizeof("builtin:") - 1,
                         value[i].len - (sizeof("builtin:") - 1));

            if (n == NGX_ERROR) {
                goto invalid;
            }

            scf->builtin_session_cache = n;

            continue;
        }

        if (value[i].len > sizeof("shared:") - 1
            && ngx_strncmp(value[i].data, "shared:", sizeof("shared:") - 1)
               == 0)
        {
            len = 0;

            for (j = sizeof("shared:") - 1; j < value[i].len; j++) {
                if (value[i].data[j] == ':') {
                    break;
                }

                len++;
            }

            if (len == 0) {
                goto invalid;
            }

            name.len = len;
            name.data = value[i].data + sizeof("shared:") - 1;

            size.len = value[i].len - j - 1;
            size.data = name.data + len + 1;

            n = ngx_parse_size(&size);

            if (n == NGX_ERROR) {
                goto invalid;
            }

            if (n < (ngx_int_t) (8 * ngx_pagesize)) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "session cache \"%V\" is too small",
                                   &value[i]);

                return NGX_CONF_ERROR;
            }

            scf->shm_zone = ngx_shared_memory_add(cf, &name, n,
                                                   &ngx_stream_ssl_module);
            if (scf->shm_zone == NULL) {
                return NGX_CONF_ERROR;
            }

            scf->shm_zone->init = ngx_ssl_session_cache_init;

            continue;
        }

        goto invalid;
    }

    if (scf->shm_zone && scf->builtin_session_cache == NGX_CONF_UNSET) {
        scf->builtin_session_cache = NGX_SSL_NO_BUILTIN_SCACHE;
    }

    return NGX_CONF_OK;

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid session cache \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static ngx_int_t
ngx_stream_ssl_init(ngx_conf_t *cf)
{
    ngx_stream_handler_pt        *h;
    ngx_stream_core_main_conf_t  *cmcf;
#if (T_NGX_HAVE_DTLS)
    ngx_uint_t                    i;
    ngx_stream_listen_t          *ls;
    ngx_stream_conf_ctx_t       *sctx;
    ngx_stream_ssl_conf_t       **sscfp, *sscf;
    ngx_stream_core_srv_conf_t  **cscfp, *cscf;
#endif

    cmcf = ngx_stream_conf_get_module_main_conf(cf, ngx_stream_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_STREAM_SSL_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_stream_ssl_handler;

#if (T_NGX_HAVE_DTLS)
    cmcf = ngx_stream_conf_get_module_main_conf(cf, ngx_stream_core_module);

    ls = cmcf->listen.elts;

    for (i = 0; i < cmcf->listen.nelts; i++) {
        if (ls[i].ssl) {
            sctx = ls[i].ctx;

            sscfp = (ngx_stream_ssl_conf_t **)sctx->srv_conf;
            cscfp = (ngx_stream_core_srv_conf_t **)sctx->srv_conf;

            sscf = sscfp[ngx_stream_ssl_module.ctx_index];
            cscf = cscfp[ngx_stream_core_module.ctx_index];

            if (sscf->certificates == NULL
#if (T_NGX_SSL_NTLS)
                && sscf->sign_certificate.len == 0
                && sscf->enc_certificate.len == 0
#endif
            ) {
                ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
#if (T_NGX_SSL_NTLS)
                              "no \"ssl_certificate\", \"ssl_enc_certificate\" "
                              "or \"ssl_sign_certificate\" is defined "
#else
                              "no \"ssl_certificate\" is defined "
#endif
                              "in server listening on SSL port at %s:%ui",
                              cscf->file_name, cscf->line);
                return NGX_ERROR;
            }

            if (ls[i].type == SOCK_DGRAM) {
                if (!(sscf->protocols & NGX_SSL_DTLSv1
                      || sscf->protocols & NGX_SSL_DTLSv1_2))
                {
                    ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                                  "\"ssl_protocols\" does not enable DTLS in a "
                                  "server listening on UDP SSL port at %s:%ui",
                                   cscf->file_name, cscf->line);
                    return NGX_ERROR;
                }

            } else {
                if (sscf->protocols & NGX_SSL_DTLSv1
                    || sscf->protocols & NGX_SSL_DTLSv1_2 )
                {
                    ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                                  "\"ssl_protocols\" includes DTLS in a server "
                                  "listening on SSL port at %s:%ui",
                                  cscf->file_name, cscf->line);
                    return NGX_ERROR;
                }
            }
        }
    }
#endif

    return NGX_OK;
}
