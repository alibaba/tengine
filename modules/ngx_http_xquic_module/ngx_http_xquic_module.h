/*
 * Copyright (C) 2020-2026 Alibaba Group Holding Limited
 */

#ifndef _NGX_HTTP_XQUIC_MODULE_H_INCLUDED_
#define _NGX_HTTP_XQUIC_MODULE_H_INCLUDED_


#include <ngx_core.h>
#include <ngx_config.h>
#include <ngx_http.h>
#include <xquic/xquic.h>


#define ngx_http_xquic_index_size(qmcf)  (qmcf->streams_index_mask + 1)
#define ngx_http_xquic_index(qmcf, sid)  (((sid) >> 1) & qmcf->streams_index_mask)

#define NGX_XQUIC_DEFAULT_DOMAIN_SOCKET_PATH "/dev/shm/tengine/xquic"
#define NGX_XQUIC_DEFAULT_RELOAD_SOCKET_PATH "/dev/shm/tengine_reload/xquic_reload"
#define NGX_XQUIC_HC_FILE_PATH_LEN 512

typedef struct {
    xqc_engine_t               *xquic_engine;
    xqc_engine_ssl_config_t     engine_ssl_config;

    ngx_event_t                 engine_ev_timer;

    ngx_fd_t                    log_fd;

    ngx_str_t                   certificate;
    ngx_str_t                   certificate_key;
    ngx_str_t                   session_ticket_key;
    ngx_str_t                   stateless_reset_token_key;
    ngx_str_t                   token_key_list[XQC_TOKEN_MAX_KEY_VERSION];
    int                         tk_max_version;                     
    ngx_str_t                   token_key_file;

    ngx_str_t                   log_file_path;
    ngx_uint_t                  log_level;

    size_t                      intercom_pool_size;
    ngx_str_t                   intercom_socket_path;

    ngx_str_t                   intercom_reload_socket_path;

    ngx_str_t                   congestion_control;
    ngx_int_t                   initcwnd;
    ngx_int_t                   mincwnd;
    ngx_int_t                   init_rtt_us;
    ngx_int_t                   init_pto_us;
    ngx_flag_t                  pacing_on;
    ngx_flag_t                  enable_keylog;

    ngx_flag_t                  new_udp_hash;

    ngx_int_t                   socket_rcvbuf;
    ngx_int_t                   socket_sndbuf;
    ngx_int_t                   intercom_socket_rcvbuf;
    ngx_int_t                   intercom_socket_sndbuf;

    ngx_uint_t                  conn_max_streams_can_create;

    ngx_uint_t                  streams_index_mask;

    /* for HTTP/3 */
    size_t                      qpack_encoder_dynamic_table_capacity;
    size_t                      qpack_decoder_dynamic_table_capacity;

    ngx_flag_t                  qpack_compat_duplicate;

    /* for qlog event */
    ngx_flag_t                  enable_qlog_event;
    ngx_uint_t                  event_importance;
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

    ngx_uint_t                  sndq_packets_used_max;

    /* packet limit of a single 1-rtt key */
    ngx_uint_t                  keyupdate_pkt_threshold;

    /* max idle timeout */
    ngx_uint_t                  idle_time_out;

    ngx_uint_t                  enable_multipath;

    ngx_uint_t                  enable_fec;
    ngx_uint_t                  fec_mp_mode;
    ngx_str_t                   fec_encoder_scheme;
    ngx_str_t                   fec_decoder_scheme;
    ngx_int_t                   fec_code_rate;
    ngx_uint_t                  symbol_number_per_block;
    ngx_uint_t                  fec_blk_log_mod;
    ngx_uint_t                  fec_packet_mask_mode;
    ngx_flag_t                  fec_log_on;
    ngx_msec_t                  fec_conn_queue_rpr_timeout;
    ngx_uint_t                  fec_stream_level_on;

    ngx_uint_t                  ack_frequency;
    ngx_uint_t                  pmtud_probing_interval;
    ngx_uint_t                  probing_pkt_out_size;
    ngx_uint_t                  init_pkt_out_size;
    ngx_flag_t                  control_pto_value;

    ngx_uint_t                  enable_pmtud;
    ngx_flag_t                  manually_send;
    ngx_flag_t                  enable_marking_reinjection;
    ngx_str_t                   multipath_scheduler;

    ngx_uint_t                  mp_enable_reinjection;
    ngx_str_t                   reinjection_control;

    ngx_int_t                   reinj_flexible_deadline_srtt_factor; /* alpha * 100 */
    ngx_uint_t                  reinj_hard_deadline;
    ngx_uint_t                  reinj_deadline_lower_bound;
    ngx_uint_t                  mp_sched_rtt_thr_high;
    ngx_uint_t                  mp_sched_rtt_thr_low;
    ngx_uint_t                  mp_sched_bw_Bps_thr;
    ngx_uint_t                  mp_sched_loss_percent_high;
    ngx_uint_t                  mp_sched_loss_percent_low;
    ngx_uint_t                  mp_sched_pto_thr;

    ngx_uint_t                  path_unreachable_pto_count;
    ngx_uint_t                  standby_path_probe_timeout;

    ngx_str_t                   hc_file;
    ngx_uint_t                  hash_conflict_threshold;
    ngx_uint_t                  conn_hash_size;
#ifdef XQC_PROTECT_POOL_MEM
    ngx_flag_t                  enable_mempool_protection;
#endif
#if (T_NGX_CC_DEFENSE)
    ngx_uint_t                  cc_req_threshold;

#endif

    /* max streams configuration */
    ngx_uint_t                  max_streams_bidi;
    ngx_uint_t                  max_streams_uni;

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

ngx_int_t ngx_xquic_ssl_get_protocol(SSL *ssl, ngx_pool_t *pool, ngx_str_t *s);

ngx_int_t ngx_xquic_ssl_get_cipher_name(SSL *ssl, ngx_pool_t *pool, ngx_str_t *s);

ngx_int_t ngx_xquic_ssl_get_session_reused(SSL *ssl, ngx_pool_t *pool, ngx_str_t *s);

ngx_int_t ngx_http_xquic_check_hc_file(ngx_http_xquic_main_conf_t *qmcf);
#endif /* _NGX_HTTP_XQUIC_MODULE_H_INCLUDED_ */

