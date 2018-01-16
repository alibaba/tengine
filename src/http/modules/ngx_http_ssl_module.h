
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#ifndef _NGX_HTTP_SSL_H_INCLUDED_
#define _NGX_HTTP_SSL_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_flag_t                      enable;

#if (NGX_HTTP_SSL && NGX_SSL_ASYNC)
    ngx_flag_t                      async_enable;
#endif

    ngx_ssl_t                       ssl;

    ngx_flag_t                      prefer_server_ciphers;

    ngx_uint_t                      protocols;

    ngx_uint_t                      verify;
    ngx_uint_t                      verify_depth;

    size_t                          buffer_size;

    ssize_t                         builtin_session_cache;

    time_t                          session_timeout;

    ngx_array_t                    *certificates;
    ngx_array_t                    *certificate_keys;

    ngx_str_t                       dhparam;
    ngx_str_t                       ecdh_curve;
    ngx_str_t                       client_certificate;
    ngx_str_t                       trusted_certificate;
    ngx_str_t                       crl;

    ngx_str_t                       ciphers;

    ngx_array_t                    *passwords;

    ngx_shm_zone_t                 *shm_zone;

    ngx_flag_t                      session_tickets;
    ngx_array_t                    *session_ticket_keys;

    ngx_flag_t                      stapling;
    ngx_flag_t                      stapling_verify;
    ngx_str_t                       stapling_file;
    ngx_str_t                       stapling_responder;

    ngx_flag_t                      early_data;

    u_char                         *file;
    ngx_uint_t                      line;
} ngx_http_ssl_srv_conf_t;

typedef struct {
    ngx_flag_t                      verify_exception;
} ngx_http_ssl_loc_conf_t;


extern ngx_module_t  ngx_http_ssl_module;


#endif /* _NGX_HTTP_SSL_H_INCLUDED_ */
