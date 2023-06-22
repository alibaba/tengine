/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _NGX_HTTP_XQUIC_MODULE_H_INCLUDED_
#define _NGX_HTTP_XQUIC_MODULE_H_INCLUDED_


#include <ngx_core.h>
#include <ngx_config.h>
#include <ngx_http.h>
#include <xquic/xquic.h>


#define ngx_http_xquic_index_size(qmcf)  (qmcf->streams_index_mask + 1)
#define ngx_http_xquic_index(qmcf, sid)  (((sid) >> 1) & qmcf->streams_index_mask)

typedef struct {
    xqc_engine_t               *xquic_engine;
    xqc_engine_ssl_config_t     engine_ssl_config;

    ngx_event_t                 engine_ev_timer;

    ngx_fd_t                    log_fd;

    ngx_str_t                   certificate;
    ngx_str_t                   certificate_key;
    ngx_str_t                   session_ticket_key;
    ngx_str_t                   stateless_reset_token_key;

    ngx_str_t                   log_file_path;
    ngx_uint_t                  log_level;

    size_t                      intercom_pool_size;
    ngx_str_t                   intercom_socket_path;

    ngx_str_t                   congestion_control;
    ngx_flag_t                  pacing_on;

    ngx_flag_t                  new_udp_hash;

    ngx_int_t                   socket_rcvbuf;
    ngx_int_t                   socket_sndbuf;

    ngx_uint_t                  conn_max_streams_can_create;

    ngx_uint_t                  streams_index_mask;

    /* for HTTP/3 */
    size_t                      qpack_encoder_dynamic_table_capacity;
    size_t                      qpack_decoder_dynamic_table_capacity;
#if (T_NGX_UDPV2)
    /* udp bacth */
    ngx_event_t                 udpv2_batch;
#endif

#if (NGX_XQUIC_SUPPORT_CID_ROUTE)
    /* for cid route , 0 for off, other for on*/
    ngx_flag_t                  cid_route;
    uint32_t                    cid_len;
    ngx_uint_t                  cid_server_id_offset;
    ngx_uint_t                  cid_server_id_length;
    ngx_uint_t                  cid_worker_id_offset;
    /* salt range start from zero */
    uint32_t                    cid_worker_id_salt_range;
    uint32_t                    cid_worker_id_secret;
#endif

    /* max concurrent quic connection count */
    ngx_uint_t                  max_quic_concurrent_connection_cnt;
    /* max concurrent connection created per second */
    ngx_uint_t                  max_quic_cps;
    /* max concurrent incoming query per second */
    ngx_uint_t                  max_quic_qps;
    
    /* anti-amplification limit */
    ngx_uint_t                  anti_amplification_limit;

    /* packet limit of a single 1-rtt key */
    ngx_uint_t                  keyupdate_pkt_threshold;
} ngx_http_xquic_main_conf_t;


typedef struct {

    ngx_uint_t               support_versions;

    ngx_flag_t               post_enable;

    ngx_msec_t               idle_conn_timeout;
    ngx_msec_t               max_idle_conn_timeout;

    ngx_msec_t               time_wait;
    ngx_uint_t               time_wait_max_conns;

    size_t                   session_flow_control_window;
    size_t                   stream_flow_control_window;

//    ngx_quic_certificate_t  *cert;
} ngx_http_xquic_srv_conf_t;


extern ngx_module_t ngx_http_xquic_module;
extern ngx_http_xquic_main_conf_t *ngx_http_xquic_main_conf;


#if (NGX_XQUIC_SUPPORT_CID_ROUTE)
/**
 * init xquic cid route stuff
 * @return NGX_OK on success, other for failed
 * */
ngx_int_t ngx_xquic_init_cid_route(ngx_cycle_t *, ngx_http_xquic_main_conf_t *qmcf);
#endif

ngx_int_t ngx_xquic_ssl_get_protocol(SSL *ssl, ngx_pool_t *pool,
    ngx_str_t *s);
ngx_int_t ngx_xquic_ssl_get_cipher_name(SSL *ssl, ngx_pool_t *pool,
    ngx_str_t *s);
ngx_int_t ngx_xquic_ssl_get_session_reused(SSL *ssl, ngx_pool_t *pool,
    ngx_str_t *s);

#endif /* _NGX_HTTP_XQUIC_MODULE_H_INCLUDED_ */

