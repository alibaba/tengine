
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#ifndef _NGX_STREAM_SSL_H_INCLUDED_
#define _NGX_STREAM_SSL_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_stream.h>


typedef struct {
    ngx_msec_t       handshake_timeout;

    ngx_flag_t       prefer_server_ciphers;

    ngx_ssl_t        ssl;

    ngx_uint_t       listen;
    ngx_uint_t       protocols;

    ngx_uint_t       verify;
    ngx_uint_t       verify_depth;

    ssize_t          builtin_session_cache;

    time_t           session_timeout;

    ngx_array_t     *certificates;
    ngx_array_t     *certificate_keys;

    ngx_array_t     *certificate_values;
    ngx_array_t     *certificate_key_values;

    ngx_str_t        dhparam;
    ngx_str_t        ecdh_curve;
    ngx_str_t        client_certificate;
    ngx_str_t        trusted_certificate;
    ngx_str_t        crl;

    ngx_str_t        ciphers;

    ngx_array_t     *passwords;

    ngx_shm_zone_t  *shm_zone;

    ngx_flag_t       session_tickets;
    ngx_array_t     *session_ticket_keys;

    u_char          *file;
    ngx_uint_t       line;

#if (T_NGX_SSL_NTLS)
    ngx_flag_t       enable_ntls;
    ngx_str_t        enc_certificate;
    ngx_str_t        enc_certificate_key;
    ngx_str_t        sign_certificate;
    ngx_str_t        sign_certificate_key;
#endif
#if (NGX_STREAM_SNI)
    ngx_flag_t       sni_force;
#endif
} ngx_stream_ssl_conf_t;


extern ngx_module_t  ngx_stream_ssl_module;


#endif /* _NGX_STREAM_SSL_H_INCLUDED_ */
