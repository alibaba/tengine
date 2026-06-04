/*
 * Copyright (C) 2020-2026 Alibaba Group Holding Limited
 */

#include <ngx_http_xquic_module.h>
#include <ngx_xquic.h>
#include <ngx_xquic_intercom.h>
#include <unistd.h>


#define NGX_XQUIC_LOG_REPORT    0
#define NGX_XQUIC_LOG_FATAL     1
#define NGX_XQUIC_LOG_ERROR     2
#define NGX_XQUIC_LOG_WARN      3
#define NGX_XQUIC_LOG_STATS     4
#define NGX_XQUIC_LOG_INFO      5
#define NGX_XQUIC_LOG_DEBUG     6

#define NGX_XQUIC_QLOG_EVENT_SELECTED    0
#define NGX_XQUIC_QLOG_EVENT_CORE        1
#define NGX_XQUIC_QLOG_EVENT_BASE        2
#define NGX_XQUIC_QLOG_EVENT_EXTRA       3
#define NGX_XQUIC_QLOG_EVENT_REMOVED     4

#define NGX_INTERCOM_SEND_RECV_BUF_SIZE (1024*1024*2) /* Send/recv buffer size for the intercom queue and the reload queue */
#define NGX_XQUIC_HASH_CONFLICT_THRESHOLD_FOR_LOG   10

#define NGX_XQUIC_MAX_FILE_NAME_SIZE                512
typedef ngx_int_t (*ngx_ssl_variable_handler_pt)(SSL *ssl, ngx_pool_t *pool, ngx_str_t *s);


static ngx_str_t ngx_xquic_log_levels[] = {
    ngx_string("report"),  
    ngx_string("fatal"),
    ngx_string("error"),
    ngx_string("warn"),
    ngx_string("stats"),    
    ngx_string("info"),
    ngx_string("debug"),
    ngx_null_string
};


static ngx_str_t ngx_qlog_event_importances[] = {
    ngx_string("selected"),
    ngx_string("core"),
    ngx_string("base"),    
    ngx_string("extra"),
    ngx_string("removed"),
    ngx_null_string
};


static ngx_int_t ngx_http_xquic_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static void ngx_http_xquic_off_set_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_xquic_off_get_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_xquic_connection_id_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_xquic_request_info_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_xquic_stream_id_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_xquic_ssl_static_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_xquic_ssl_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_xquic_add_variables(ngx_conf_t *cf);
static char * ngx_http_xquic_streams_index_mask(ngx_conf_t *cf, void *post, void *data);
static char * ngx_http_xquic_set_log_level(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char * ngx_http_xquic_set_qlog_importance(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char * ngx_http_xquic_reinj_flexible_deadline_srtt_factor(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char * ngx_http_xquic_fec_code_rate(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static void * ngx_http_xquic_create_main_conf(ngx_conf_t *cf);
static char * ngx_http_xquic_init_main_conf(ngx_conf_t *cf, void *conf);
static void * ngx_http_xquic_create_srv_conf(ngx_conf_t *cf);
static char * ngx_http_xquic_merge_srv_conf(ngx_conf_t *cf, void *parent, void *child);
static ngx_int_t ngx_http_xquic_process_init(ngx_cycle_t *cycle);
static void ngx_http_xquic_process_exit(ngx_cycle_t *cycle);
static ngx_int_t ngx_http_xquic_init(ngx_conf_t *cf);
static ngx_int_t ngx_http_xquic_access_handler(ngx_http_request_t *r);
static char * ngx_http_set_xquic_status(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_xquic_module_init(ngx_cycle_t *cycle);


static char *ngx_conf_read_xquic_token_key(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_xquic_read_token_key_file(ngx_str_t *tk_file,
    ngx_http_xquic_main_conf_t *qmcf, ngx_conf_t *cf);

ngx_http_xquic_main_conf_t *ngx_http_xquic_main_conf = NULL;


static ngx_conf_post_t  ngx_http_xquic_streams_index_mask_post =
    { ngx_http_xquic_streams_index_mask };


static ngx_command_t  ngx_http_xquic_commands[] = {

    { ngx_string("xquic_ssl_certificate"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, certificate),
      NULL },

    { ngx_string("xquic_ssl_certificate_key"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, certificate_key),
      NULL },
      
    { ngx_string("xquic_ssl_session_ticket_key"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, session_ticket_key),
      NULL },

    { ngx_string("xquic_stateless_reset_token_key"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, stateless_reset_token_key),
      NULL },

    /*
     * Support rotation among multiple versions of token keys. The configuration format for
     * each version of token_key is "version:token_key", with the version and token_key
     * separated by a colon. Example with multiple versions:
     *   xquic_token_key 10:token_key1 9:token_key2 8:token_key3;
     * Up to 4 token-key versions are supported. Version numbers are incremented by 1.
     * By default the latest version (the largest version number) is used for encryption.
     */
    { ngx_string("xquic_token_key"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1234,
      ngx_conf_read_xquic_token_key,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

    /*
     * Support reading token keys from a file, with each line in the file using the format:
     *   version1:token_key1
     * Up to 4 versions are supported. If the file contains more than 4 versions, or has
     * duplicates, the format is considered invalid.
     * Only one of xquic_token_key and xquic_token_key_file needs to be configured. If both
     * are configured, having the same version appear in multiple places will fail validation.
     */
    { ngx_string("xquic_token_key_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, token_key_file),
      NULL },

    { ngx_string("xquic_log_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, log_file_path),
      NULL },

    { ngx_string("xquic_use_new_udp_hash"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, new_udp_hash),
      NULL },

    { ngx_string("xquic_log_level"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_xquic_set_log_level,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, log_level),
      NULL },

    { ngx_string("xquic_enable_qlog_event"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, enable_qlog_event),
      NULL },

    { ngx_string("xquic_qlog_event_importance"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_xquic_set_qlog_importance,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, event_importance),
      NULL },

    { ngx_string("xquic_socket_sndbuf"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, socket_sndbuf),
      NULL },

    { ngx_string("xquic_qpack_encoder_dynamic_table_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, qpack_encoder_dynamic_table_capacity),
      NULL },

    { ngx_string("xquic_qpack_decoder_dynamic_table_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, qpack_decoder_dynamic_table_capacity),
      NULL },

    { ngx_string("xquic_qpack_compat_duplicate"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, qpack_compat_duplicate),
      NULL },

    { ngx_string("xquic_socket_rcvbuf"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, socket_rcvbuf),
      NULL },

    { ngx_string("xquic_intercom_socket_rcvbuf"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, intercom_socket_rcvbuf),
      NULL },
    
    { ngx_string("xquic_intercom_socket_sndbuf"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, intercom_socket_sndbuf),
      NULL },

    { ngx_string("xquic_congestion_control"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, congestion_control),
      NULL },

    { ngx_string("xquic_init_cwnd_pkt"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, initcwnd),
      NULL },

    { ngx_string("xquic_min_cwnd_pkt"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, mincwnd),
      NULL },

    { ngx_string("xquic_init_rtt_us"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, init_rtt_us),
      NULL },

    { ngx_string("xquic_init_pto_us"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, init_pto_us),
      NULL },

    { ngx_string("xquic_pacing"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, pacing_on),
      NULL },

    { ngx_string("xquic_manually_send"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, manually_send),
      NULL },

    { ngx_string("xquic_enable_keylog"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, enable_keylog),
      NULL },

    { ngx_string("xquic_streams_index_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, streams_index_mask),
      &ngx_http_xquic_streams_index_mask_post },

#if (NGX_XQUIC_SUPPORT_CID_ROUTE)

    { ngx_string("xquic_cid_route"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, cid_route),
      NULL },

    { ngx_string("xquic_server_id_offset"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, cid_server_id_offset),
      NULL },

    { ngx_string("xquic_server_id_length"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, cid_server_id_length),
      NULL },

    { ngx_string("xquic_worker_id_offset"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, cid_worker_id_offset),
      NULL },

#endif


    { ngx_string("xquic_max_concurrent_connection_cnt"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, max_quic_concurrent_connection_cnt),
      NULL },

    { ngx_string("xquic_max_cps"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, max_quic_cps),
      NULL },

    { ngx_string("xquic_max_qps"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, max_quic_qps),
      NULL },

    { ngx_string("xquic_conn_hash_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, conn_hash_size),
      NULL },

    { ngx_string("xquic_hash_conflict_threshold"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, hash_conflict_threshold),
      NULL },
    { ngx_string("xquic_status"),
      NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS|NGX_CONF_TAKE1,
      ngx_http_set_xquic_status,
      0,
      0,
      NULL },

    { ngx_string("xquic_anti_amplification_limit"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, anti_amplification_limit),
      NULL },

    { ngx_string("xquic_sndq_packets_used_max"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, sndq_packets_used_max),
      NULL },

    { ngx_string("xquic_keyupdate_pkt_threshold"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, keyupdate_pkt_threshold),
      NULL },

    { ngx_string("xquic_idle_time_out"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, idle_time_out),
      NULL },

    { ngx_string("xquic_enable_multipath"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, enable_multipath),
      NULL },

    { ngx_string("xquic_enable_fec"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, enable_fec),
      NULL },

    { ngx_string("xquic_fec_mp_mode"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, fec_mp_mode),
      NULL },
    
    { ngx_string("xquic_fec_code_rate"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_xquic_fec_code_rate,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },
    
    { ngx_string("xquic_symbol_number_per_block"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, symbol_number_per_block),
      NULL },

    { ngx_string("xquic_fec_encoder_scheme"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, fec_encoder_scheme),
      NULL },

    { ngx_string("xquic_fec_decoder_scheme"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, fec_decoder_scheme),
      NULL },

    { ngx_string("xquic_enable_pmtud"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, enable_pmtud),
      NULL },

    { ngx_string("xquic_fec_log_on"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, fec_log_on),
      NULL },

    { ngx_string("xquic_fec_blk_log_mod"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, fec_blk_log_mod),
      NULL },

    { ngx_string("xquic_fec_packet_mask_mode"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, fec_packet_mask_mode),
      NULL },

    { ngx_string("xquic_fec_conn_queue_rpr_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, fec_conn_queue_rpr_timeout),
      NULL },

    { ngx_string("xquic_fec_stream_level"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, fec_stream_level_on),
      NULL },

#ifdef XQC_PROTECT_POOL_MEM    
    { ngx_string("xquic_enable_mempool_protection"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, enable_mempool_protection),
      NULL },
#endif
    
    { ngx_string("xquic_enable_marking_reinjection"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, enable_marking_reinjection),
      NULL },

    { ngx_string("xquic_multipath_scheduler"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, multipath_scheduler),
      NULL },

    { ngx_string("xquic_mp_enable_reinjection"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, mp_enable_reinjection),
      NULL },

    { ngx_string("xquic_reinjection_control"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, reinjection_control),
      NULL },

    { ngx_string("xquic_reinj_flexible_deadline_srtt_factor"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_xquic_reinj_flexible_deadline_srtt_factor,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("xquic_reinj_hard_deadline"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, reinj_hard_deadline),
      NULL },

    { ngx_string("xquic_reinj_deadline_lower_bound"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, reinj_deadline_lower_bound),
      NULL },

    { ngx_string("xquic_mp_sched_rtt_thr_high"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, mp_sched_rtt_thr_high),
      NULL },
    
    { ngx_string("xquic_mp_sched_rtt_thr_low"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, mp_sched_rtt_thr_low),
      NULL },

    { ngx_string("xquic_mp_sched_bw_Bps_thr"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, mp_sched_bw_Bps_thr),
      NULL },

    { ngx_string("xquic_mp_sched_loss_percent_high"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, mp_sched_loss_percent_high),
      NULL },

    { ngx_string("xquic_mp_sched_loss_percent_low"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, mp_sched_loss_percent_low),
      NULL },

    { ngx_string("xquic_mp_sched_pto_thr"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, mp_sched_pto_thr),
      NULL },

    { ngx_string("xquic_path_unreachable_pto_count"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, path_unreachable_pto_count),
      NULL },

    { ngx_string("xquic_standby_path_probe_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, standby_path_probe_timeout),
      NULL },

    { ngx_string("xquic_health_check_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, hc_file),
      NULL },

    { ngx_string("xquic_ack_frequency"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, ack_frequency),
      NULL },

    { ngx_string("xquic_use_smaller_pto"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, control_pto_value),
      NULL },
    
    { ngx_string("xquic_pmtud_probing_interval"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, pmtud_probing_interval),
      NULL },

    { ngx_string("xquic_probing_pkt_out_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, probing_pkt_out_size),
      NULL },

    { ngx_string("xquic_init_pkt_out_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, init_pkt_out_size),
      NULL },

    { ngx_string("xquic_max_streams_bidi"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, max_streams_bidi),
      NULL },

    { ngx_string("xquic_max_streams_uni"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_xquic_main_conf_t, max_streams_uni),
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_xquic_module_ctx = {
    ngx_http_xquic_add_variables,          /* preconfiguration */
    ngx_http_xquic_init,                   /* postconfiguration */

    ngx_http_xquic_create_main_conf,       /* create main configuration */
    ngx_http_xquic_init_main_conf,         /* init main configuration */

    ngx_http_xquic_create_srv_conf,        /* create server configuration */
    ngx_http_xquic_merge_srv_conf,         /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};


ngx_module_t  ngx_http_xquic_module = {
    NGX_MODULE_V1,
    &ngx_http_xquic_module_ctx,            /* module context */
    ngx_http_xquic_commands,               /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    ngx_http_xquic_module_init,            /* init module */
    ngx_http_xquic_process_init,           /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    ngx_http_xquic_process_exit,           /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_variable_t  ngx_http_xquic_vars[] = {

    { ngx_string("xquic"), NULL,
      ngx_http_xquic_variable, 0, 0, 0 },

    { ngx_string("xquic_off"),
      ngx_http_xquic_off_set_variable,
      ngx_http_xquic_off_get_variable,
      0, NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_string("xquic_connection_id"), NULL,
      ngx_http_xquic_connection_id_variable, 0, 0, 0 },

    { ngx_string("xquic_request_info"), NULL,
      ngx_http_xquic_request_info_variable, 0, 0, 0 },

    { ngx_string("xquic_stream_id"), NULL,
      ngx_http_xquic_stream_id_variable, 0, 0, 0 },

    { ngx_string("xquic_ssl_protocol"), NULL, ngx_xquic_ssl_static_variable,
      (uintptr_t) ngx_xquic_ssl_get_protocol, NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_string("xquic_ssl_cipher"), NULL, ngx_xquic_ssl_static_variable,
      (uintptr_t) ngx_xquic_ssl_get_cipher_name, NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_string("xquic_ssl_session_reused"), NULL, ngx_xquic_ssl_variable,
      (uintptr_t) ngx_xquic_ssl_get_session_reused, NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_null_string, NULL, NULL, 0, 0, 0 }
};


int
ngx_http_xquic_parse_token_key(ngx_str_t *raw, int *version, ngx_str_t *key)
{
    size_t         i = 0;
    int            ret = NGX_ERROR;
    unsigned char *p = raw->data;

    for (i = 0; i < raw->len; i++) {
        if (p[i] == ':') {
            int ver = ngx_atoi(raw->data, i);
            if (ver == NGX_ERROR) {
                return NGX_ERROR;
            }
            *version = ver;
            key->data = p + i + 1;
            key->len = raw->len - i - 1;
            if (key->len == 0) {
                return NGX_ERROR;
            }
            return NGX_OK;
        }
    }
    return ret;
}


static char *
ngx_conf_read_xquic_token_key(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_uint_t                  i = 0;
    int                         max_version = 0;
    ngx_str_t                  *value;
    ngx_http_xquic_main_conf_t *qmcf = conf;

    if (qmcf == NULL) {
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|xquic qmcf NULL|");
        return NGX_CONF_ERROR;
    }
    value = cf->args->elts;
    for (i = 1; i < cf->args->nelts; i++) {
        int ret, ver = 0;
        ngx_str_t key = {0, NULL};
        ret = ngx_http_xquic_parse_token_key(&value[i], &ver, &key);
        if (ret != NGX_OK) {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|xquic parse token key error:%V|", &value[i]);
            return NGX_CONF_ERROR;
        }
        if (ver > max_version) {
            max_version = ver;
        }
        int index = ver & XQC_TOKEN_VERSION_MASK;
        if (qmcf->token_key_list[index].len > 0) {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|token key version duplicate, version:%d|", ver);
            return NGX_CONF_ERROR;
        }
        if (key.len > 0 && key.len < XQC_TOKEN_MAX_KEY_LEN) {
            qmcf->token_key_list[index].len = key.len;
            qmcf->token_key_list[index].data = key.data;
        } else {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|token key length invalid, len:%d|", key.len);
            return NGX_CONF_ERROR;
        }
    }

    qmcf->tk_max_version = max_version;
    return NGX_CONF_OK;

}


static ngx_int_t
ngx_http_xquic_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    v->not_found = 1;

    if (r->xqstream) {
        v->len = sizeof("xquic") - 1;
        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;
        v->data = (u_char *) "xquic";
    }

    return NGX_OK;
}


static void
ngx_http_xquic_off_set_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_http_xquic_connection_t  *qc;

    if (r->xqstream) {
        qc = r->xqstream->connection;
        if (v->len == 2 && ngx_strncasecmp(v->data, (u_char *) "on", 2) == 0) {
            qc->xquic_off = 1;
        } else if (v->len == 3 && ngx_strncasecmp(v->data, (u_char *) "off", 3) == 0) {
            qc->xquic_off = 0;
        }
    }
}

static ngx_int_t
ngx_http_xquic_off_get_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_http_xquic_connection_t  *qc;

    v->not_found = 1;

    if (r->xqstream) {
        qc = r->xqstream->connection;

        v->data = ngx_pnalloc(r->pool, sizeof("off") - 1);
        if (v->data == NULL) {
            return NGX_ERROR;
        }

        if (qc->xquic_off == 0) {
            v->len = 3;
            v->data[0] = 'o';
            v->data[1] = 'f';
            v->data[2] = 'f';
        } else {
            v->len = 2;
            v->data[0] = 'o';
            v->data[1] = 'n';
        }

        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;
    }

    return NGX_OK;
}



static ngx_int_t
ngx_http_xquic_connection_id_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char                       *p;
    ngx_http_xquic_connection_t  *qc;

    v->not_found = 1;

    if (r->xqstream != NULL && r->xqstream->connection != NULL) {
        qc = r->xqstream->connection;

        p = ngx_pnalloc(r->pool, qc->dcid.cid_len * 2);
        if (p == NULL) {
            return NGX_ERROR;
        }

        v->len = ngx_snprintf(p, qc->dcid.cid_len * 2, "%s", xqc_dcid_str(qc->engine, &qc->dcid)) - p;
        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;
        v->data = p;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_xquic_request_info_variable(ngx_http_request_t *r,
                                     ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char *p;
    const int size = 128;

    v->not_found = 1;

    if (r->xqstream != NULL && r->xqstream->connection != NULL && r->xqstream->h3_request != NULL) {

        p = ngx_pnalloc(r->pool, size);
        if (p == NULL) {
            return NGX_ERROR;
        }

        v->len = xqc_h3_request_stats_print(r->xqstream->h3_request, (char *) p, size);
        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;
        v->data = p;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_xquic_stream_id_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char                      *p;

    v->not_found = 1;

    if (r->xqstream) {
        p = ngx_pnalloc(r->pool, NGX_INT64_LEN);
        if (p == NULL) {
            return NGX_ERROR;
        }

        v->len = ngx_snprintf(p, NGX_OFF_T_LEN, "%O", r->xqstream->id) - p;
        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;
        v->data = p;
     }

    return NGX_OK;
}



static ngx_int_t
ngx_http_xquic_add_variables(ngx_conf_t *cf)
{
    ngx_http_variable_t  *var, *v;

    for (v = ngx_http_xquic_vars; v->name.len; v++) {
        var = ngx_http_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }

        var->get_handler = v->get_handler;
        var->set_handler = v->set_handler;
        var->data = v->data;
    }

    return NGX_OK;
}


static char *
ngx_http_xquic_streams_index_mask(ngx_conf_t *cf, void *post, void *data)
{
    ngx_uint_t *np = data;

    ngx_uint_t  mask;

    mask = *np - 1;

    if (*np == 0 || (*np & mask)) {
        return "must be a power of two";
    }

    *np = mask;

    return NGX_CONF_OK;
}


static char *
ngx_http_xquic_set_log_level(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t        *value;
    ngx_uint_t        i;
    ngx_http_xquic_main_conf_t *qmcf = conf;

    value = cf->args->elts;

    if (qmcf->log_level != NGX_CONF_UNSET_UINT) {
        return "is duplicate";
    }

    for (i = 0; i <= NGX_XQUIC_LOG_DEBUG; i++) {
        if (value[1].len == ngx_xquic_log_levels[i].len
            && ngx_strncmp(value[1].data, ngx_xquic_log_levels[i].data, value[1].len) == 0)
        {
            qmcf->log_level = i;
            return NGX_CONF_OK;
        }
    }

    return "invalid log level";
}


static char *
ngx_http_xquic_set_qlog_importance(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t        *value;
    ngx_uint_t        i;
    ngx_http_xquic_main_conf_t *qmcf = conf;

    value = cf->args->elts;

    if (qmcf->event_importance != NGX_CONF_UNSET_UINT) {
        return "is duplicate";
    }

    for (i = 0; i <= NGX_XQUIC_LOG_DEBUG; i++) {
        if (value[1].len == ngx_qlog_event_importances[i].len
            && ngx_strncmp(value[1].data, ngx_qlog_event_importances[i].data, value[1].len) == 0)
        {
            qmcf->event_importance = i;
            return NGX_CONF_OK;
        }
    }

    return "invalid qlog importance";
}

static char *
ngx_http_xquic_fec_code_rate(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                  *value;
    ngx_http_xquic_main_conf_t *qmcf = conf;

    value = cf->args->elts;

    if (qmcf->fec_code_rate != NGX_CONF_UNSET) {
        return "is duplicate";
    }

    value = cf->args->elts;

    qmcf->fec_code_rate = ngx_atofp(value[1].data, value[1].len, 2);
    if (qmcf->fec_code_rate == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[1]);
        return NGX_CONF_ERROR;
    }
    return NGX_CONF_OK;
}

static char *
ngx_http_xquic_reinj_flexible_deadline_srtt_factor(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                  *value;
    ngx_http_xquic_main_conf_t *qmcf = conf;

    value = cf->args->elts;

    if (qmcf->reinj_flexible_deadline_srtt_factor != NGX_CONF_UNSET) {
        return "is duplicate";
    }

    value = cf->args->elts;
    qmcf->reinj_flexible_deadline_srtt_factor = ngx_atofp(value[1].data, value[1].len, 2);
    if (qmcf->reinj_flexible_deadline_srtt_factor == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[1]);
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK; 
}

static void *
ngx_http_xquic_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_xquic_main_conf_t *qmcf;

    qmcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_xquic_main_conf_t));
    if (qmcf == NULL) {
        return NULL;
    }

    /* set by ngx_pcalloc
     *     qmcf->intercom_socket_path = { NULL, 0 };
     *     qmcf->congestion_control = { NULL, 0 };
     */

    qmcf->log_level = NGX_CONF_UNSET_UINT;
    qmcf->enable_qlog_event = NGX_CONF_UNSET;
    qmcf->event_importance = NGX_CONF_UNSET_UINT;
    qmcf->intercom_pool_size = NGX_CONF_UNSET_SIZE;
    qmcf->new_udp_hash = NGX_CONF_UNSET;
    qmcf->conn_max_streams_can_create = NGX_CONF_UNSET_UINT;

    qmcf->socket_rcvbuf = NGX_CONF_UNSET;
    qmcf->socket_sndbuf = NGX_CONF_UNSET;
    qmcf->intercom_socket_rcvbuf = NGX_CONF_UNSET;
    qmcf->intercom_socket_sndbuf = NGX_CONF_UNSET;
    qmcf->initcwnd = NGX_CONF_UNSET;
    qmcf->mincwnd = NGX_CONF_UNSET;
    qmcf->init_rtt_us = NGX_CONF_UNSET;
    qmcf->init_pto_us = NGX_CONF_UNSET;

    qmcf->streams_index_mask = NGX_CONF_UNSET_UINT;

    qmcf->pacing_on = NGX_CONF_UNSET;
    qmcf->manually_send = NGX_CONF_UNSET;
    qmcf->enable_keylog = NGX_CONF_UNSET;

    qmcf->qpack_encoder_dynamic_table_capacity = NGX_CONF_UNSET_SIZE;
    qmcf->qpack_decoder_dynamic_table_capacity = NGX_CONF_UNSET_SIZE;
    qmcf->qpack_compat_duplicate               = NGX_CONF_UNSET;

#if (NGX_XQUIC_SUPPORT_CID_ROUTE)
    qmcf->cid_route             = NGX_CONF_UNSET;
    qmcf->cid_server_id_offset  = NGX_CONF_UNSET_UINT;
    qmcf->cid_server_id_length  = NGX_CONF_UNSET_UINT;
    qmcf->cid_worker_id_offset  = NGX_CONF_UNSET_UINT;
#endif

    qmcf->max_quic_concurrent_connection_cnt = NGX_CONF_UNSET_UINT;
    qmcf->max_quic_cps = NGX_CONF_UNSET_UINT;
    qmcf->max_quic_qps = NGX_CONF_UNSET_UINT;
    qmcf->hash_conflict_threshold = NGX_CONF_UNSET_UINT;
    qmcf->conn_hash_size = NGX_CONF_UNSET_UINT;

    qmcf->anti_amplification_limit = NGX_CONF_UNSET_UINT;

    qmcf->sndq_packets_used_max = NGX_CONF_UNSET_UINT;

    qmcf->keyupdate_pkt_threshold = NGX_CONF_UNSET_UINT;

    qmcf->idle_time_out = NGX_CONF_UNSET_UINT;

    qmcf->enable_multipath = NGX_CONF_UNSET_UINT;
    qmcf->enable_pmtud = NGX_CONF_UNSET_UINT;
#ifdef XQC_PROTECT_POOL_MEM
    qmcf->enable_mempool_protection = NGX_CONF_UNSET;
#endif
    qmcf->enable_marking_reinjection = NGX_CONF_UNSET;
    qmcf->mp_enable_reinjection  = NGX_CONF_UNSET_UINT;

    qmcf->reinj_flexible_deadline_srtt_factor = NGX_CONF_UNSET;
    qmcf->reinj_hard_deadline = NGX_CONF_UNSET_UINT;
    qmcf->reinj_deadline_lower_bound = NGX_CONF_UNSET_UINT;
    qmcf->mp_sched_rtt_thr_high = NGX_CONF_UNSET_UINT;
    qmcf->mp_sched_rtt_thr_low = NGX_CONF_UNSET_UINT;
    qmcf->mp_sched_bw_Bps_thr = NGX_CONF_UNSET_UINT;
    qmcf->mp_sched_loss_percent_high = NGX_CONF_UNSET_UINT;
    qmcf->mp_sched_loss_percent_low = NGX_CONF_UNSET_UINT;
    qmcf->mp_sched_pto_thr = NGX_CONF_UNSET_UINT;

    qmcf->path_unreachable_pto_count = NGX_CONF_UNSET_UINT;
    qmcf->standby_path_probe_timeout = NGX_CONF_UNSET_UINT;

    qmcf->enable_fec = NGX_CONF_UNSET_UINT;
    qmcf->fec_mp_mode = NGX_CONF_UNSET_UINT;
    qmcf->fec_code_rate = NGX_CONF_UNSET;
    qmcf->symbol_number_per_block = NGX_CONF_UNSET_UINT;
    qmcf->ack_frequency = NGX_CONF_UNSET_UINT;
    qmcf->control_pto_value = NGX_CONF_UNSET;
    qmcf->pmtud_probing_interval = NGX_CONF_UNSET_UINT;
    qmcf->probing_pkt_out_size = NGX_CONF_UNSET_UINT;
    qmcf->init_pkt_out_size = NGX_CONF_UNSET_UINT;
    qmcf->fec_blk_log_mod = NGX_CONF_UNSET_UINT;
    qmcf->fec_packet_mask_mode = NGX_CONF_UNSET_UINT;
    qmcf->fec_log_on = NGX_CONF_UNSET;
    qmcf->fec_conn_queue_rpr_timeout = NGX_CONF_UNSET_MSEC;
    qmcf->fec_stream_level_on = NGX_CONF_UNSET_UINT;

    int i;
    for (i = 0; i < XQC_TOKEN_MAX_KEY_VERSION; i++) {
        qmcf->token_key_list[i].data = NULL;
        qmcf->token_key_list[i].len = 0;
    }   
    qmcf->tk_max_version = 0;
    qmcf->token_key_file.data = NULL;
    qmcf->token_key_file.len = 0;

    qmcf->max_streams_bidi = NGX_CONF_UNSET_UINT;
    qmcf->max_streams_uni = NGX_CONF_UNSET_UINT;

    ngx_http_xquic_main_conf = qmcf;

    return qmcf;
}


static ngx_int_t ngx_http_xquic_read_token_key_file(ngx_str_t *tk_file,
        ngx_http_xquic_main_conf_t *qmcf,
        ngx_conf_t *cf)
{
    char file_name[NGX_XQUIC_MAX_FILE_NAME_SIZE];
    char line_buf[XQC_TOKEN_MAX_KEY_LEN];

    if (tk_file->len == 0 || tk_file->data == NULL) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0, "|xquic|xquic token file not set, using default token key|");
        return NGX_OK;
    }
    if (tk_file->len > sizeof(file_name) - 1) {
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|xquic token file name too long|%d|", tk_file->len);
        return NGX_ERROR;
    }
    ngx_memcpy(file_name, tk_file->data, tk_file->len);
    file_name[tk_file->len] = '\0';
    FILE *fp = fopen(file_name, "r");
    if (fp == NULL) {
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|xquic token file open failed|%V|", tk_file);
        return NGX_ERROR;
    }

    int max_version = 0;
    ngx_str_t *tk;
    while (fgets(line_buf, sizeof(line_buf), fp) != NULL) {
        size_t len = strlen(line_buf);
        if (len == sizeof(line_buf) - 1 && line_buf[len] != '\n') {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|token key file one line length exceed|");
            return NGX_ERROR;
        }
        if (len <= 1) {
            continue; /* ignore blank lines */
        }
        /* replace '\n' to '\0' at the end of line */
        if (line_buf[len - 1] == '\n') {
            line_buf[len - 1] = '\0';
            len--;
        }
        ngx_str_t raw = {len, (u_char *) line_buf};
        ngx_str_t key = {0, NULL};
        int ret, ver = 0;
        ret = ngx_http_xquic_parse_token_key(&raw, &ver, &key);
        if (ret != NGX_OK) {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|xquic parse token key failed|");
            return NGX_ERROR;
        }
        if (ver > max_version) {
            max_version = ver;
        }
        int index = ver & XQC_TOKEN_VERSION_MASK;
        if (qmcf->token_key_list[index].len > 0) {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|token key version duplicate|version:%d|", ver); 
            return NGX_ERROR;
        }
        if (key.len > 0 && key.data != NULL) {
            tk = &qmcf->token_key_list[index];
            tk->data = ngx_pcalloc(cf->pool, key.len);
            if (tk->data == NULL) {
                ngx_conf_log_error(NGX_LOG_ERR, cf, 0, "|xquic|token data alloc error|alloc length:%d|", key.len);\
                return NGX_ERROR;
            }
            ngx_memcpy(tk->data, key.data, key.len);
            tk->len = key.len;
        } else {
            return NGX_ERROR; 
        }
    }

    qmcf->tk_max_version = max_version;
    fclose(fp);
    return NGX_OK;
}

static char *
ngx_http_xquic_init_main_conf(ngx_conf_t *cf, void *conf)
{
    ngx_http_xquic_main_conf_t *qmcf = conf;

    if (qmcf->log_level == NGX_CONF_UNSET_UINT) {
        qmcf->log_level = NGX_XQUIC_LOG_ERROR;
    }

    if (qmcf->enable_qlog_event == NGX_CONF_UNSET) {
        qmcf->enable_qlog_event = 0;
    }

    if (qmcf->event_importance == NGX_CONF_UNSET_UINT) {
        qmcf->event_importance = NGX_XQUIC_QLOG_EVENT_SELECTED;
    }

    if (qmcf->intercom_pool_size == NGX_CONF_UNSET_SIZE) {
        qmcf->intercom_pool_size = 4096;
    }

    if (qmcf->new_udp_hash == NGX_CONF_UNSET) {
        qmcf->new_udp_hash = 0;
    }

    if (qmcf->socket_rcvbuf == NGX_CONF_UNSET) {
        qmcf->socket_rcvbuf = 1*1024*1024;
    }

    if (qmcf->socket_sndbuf == NGX_CONF_UNSET) {
        qmcf->socket_sndbuf = 1*1024*1024;
    }

    if (qmcf->intercom_socket_rcvbuf == NGX_CONF_UNSET) {
        qmcf->intercom_socket_rcvbuf = NGX_INTERCOM_SEND_RECV_BUF_SIZE;
    }
    if (qmcf->intercom_socket_sndbuf == NGX_CONF_UNSET) {
        qmcf->intercom_socket_sndbuf = NGX_INTERCOM_SEND_RECV_BUF_SIZE;
    }

    if (qmcf->initcwnd == NGX_CONF_UNSET) {
        qmcf->initcwnd = 0;
    }

    if (qmcf->mincwnd == NGX_CONF_UNSET) {
        qmcf->mincwnd = 0;
    }

    if (qmcf->init_rtt_us == NGX_CONF_UNSET) {
        qmcf->init_rtt_us = 0;
    }

    if (qmcf->init_pto_us == NGX_CONF_UNSET) {
        qmcf->init_pto_us = 0;
    }

    if (qmcf->conn_max_streams_can_create == NGX_CONF_UNSET_UINT) {
        qmcf->conn_max_streams_can_create = 4096;
    }

    if (qmcf->streams_index_mask == NGX_CONF_UNSET_UINT) {
        qmcf->streams_index_mask = 32 - 1;
    }

    if (qmcf->intercom_socket_path.data == NULL) {
        qmcf->intercom_socket_path.data = (u_char *) NGX_XQUIC_DEFAULT_DOMAIN_SOCKET_PATH;
        qmcf->intercom_socket_path.len = sizeof(NGX_XQUIC_DEFAULT_DOMAIN_SOCKET_PATH) - 1;
    }
    if (qmcf->intercom_reload_socket_path.data == NULL) {
        qmcf->intercom_reload_socket_path.data = (u_char *)NGX_XQUIC_DEFAULT_RELOAD_SOCKET_PATH;
        qmcf->intercom_reload_socket_path.len = sizeof(NGX_XQUIC_DEFAULT_RELOAD_SOCKET_PATH) - 1;
    }

    if (qmcf->certificate.data == NULL) {
        ngx_str_set(&(qmcf->certificate), "./server.crt");
    }

    if (qmcf->certificate_key.data == NULL) {
        ngx_str_set(&(qmcf->certificate_key), "./server.key");
    }

    if (qmcf->session_ticket_key.data == NULL) {
        ngx_str_set(&(qmcf->session_ticket_key), "./session_ticket.key");
    }

    if (qmcf->stateless_reset_token_key.data == NULL) {
        ngx_str_set(&(qmcf->stateless_reset_token_key), ".@34dshj+={}");
    }

    if (qmcf->token_key_file.len > 0 && qmcf->token_key_file.data != NULL) {
        if (ngx_http_xquic_read_token_key_file(&qmcf->token_key_file, qmcf, cf) != NGX_OK) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "|xquic|xquic read token key file error|");
            return NGX_CONF_ERROR;
        } 
    }
    int i;
    for (i = 0; i < XQC_TOKEN_MAX_KEY_VERSION; i++) {
        ngx_str_t *tk = &qmcf->token_key_list[i];
        if (tk->len == 0) {
            ngx_str_set(tk, "~!@#1234qwerasdf");
        }
    }

    if (qmcf->log_file_path.data == NULL) {
        ngx_str_set(&(qmcf->log_file_path), "./xquic_log");
    }

    if (qmcf->congestion_control.data == NULL) {
        ngx_str_set(&(qmcf->congestion_control), "cubic");
    }

    if (qmcf->pacing_on == NGX_CONF_UNSET) {
        qmcf->pacing_on = 0;
    }

    if (qmcf->manually_send == NGX_CONF_UNSET) {
        qmcf->manually_send = 0;
    }

    if (qmcf->enable_keylog == NGX_CONF_UNSET) {
        qmcf->enable_keylog = 0;
    }

    if (qmcf->qpack_encoder_dynamic_table_capacity == NGX_CONF_UNSET_SIZE) {
        qmcf->qpack_encoder_dynamic_table_capacity = 16 * 1024;
    }

    if (qmcf->qpack_decoder_dynamic_table_capacity == NGX_CONF_UNSET_SIZE) {
        qmcf->qpack_decoder_dynamic_table_capacity = 16 * 1024;
    }

    if (qmcf->qpack_compat_duplicate == NGX_CONF_UNSET) {
        qmcf->qpack_compat_duplicate = 1;
    }

    if (qmcf->hash_conflict_threshold == NGX_CONF_UNSET_UINT) {
        qmcf->hash_conflict_threshold = NGX_XQUIC_HASH_CONFLICT_THRESHOLD_FOR_LOG;
    }

#if (NGX_XQUIC_SUPPORT_CID_ROUTE)

#define NGX_QUIC_CID_ROUTE_FIRST_OCTER              (1)
#define NGX_QUIC_CID_ROUTE_SERVER_ID                (3)
#define NGX_QUIC_CID_ROUTE_ENTROPY                  (4)

#define NGX_QUIC_CID_ROUTE_WORKER_ID_OFFSET         (NGX_QUIC_CID_ROUTE_FIRST_OCTER + NGX_QUIC_CID_ROUTE_SERVER_ID + NGX_QUIC_CID_ROUTE_ENTROPY)

    ngx_conf_init_uint_value(qmcf->cid_server_id_offset, NGX_QUIC_CID_ROUTE_FIRST_OCTER);
    ngx_conf_init_uint_value(qmcf->cid_server_id_length, NGX_QUIC_CID_ROUTE_SERVER_ID);
    ngx_conf_init_uint_value(qmcf->cid_worker_id_offset, NGX_QUIC_CID_ROUTE_WORKER_ID_OFFSET);

    /* enable by default */
    if (qmcf->cid_route != 0) {
        qmcf->cid_route = 1;
        ngx_xquic_init_cid_route(cf->cycle, qmcf);
    }

    /* overlap */
    if (qmcf->cid_worker_id_offset < qmcf->cid_server_id_offset + qmcf->cid_server_id_length 
        && qmcf->cid_worker_id_offset + T_NGX_QUIC_CID_ROUTE_WORKER_ID_LENGTH > qmcf->cid_server_id_offset)
    {
        return "|xquic|overlap server id and worker id|";
    }

    /* get cid length */
    qmcf->cid_len = ngx_max(qmcf->cid_worker_id_offset + T_NGX_QUIC_CID_ROUTE_WORKER_ID_LENGTH, qmcf->cid_server_id_offset + qmcf->cid_server_id_length);

#define NGX_QUIC_CID_MAX_LEN  (20)
    if (qmcf->cid_len > NGX_QUIC_CID_MAX_LEN) {
        return "|xquic|exceed max cid length|";
    }
#undef NGX_QUIC_CID_MAX_LEN

    /* entropy space check */
    if (qmcf->cid_len - T_NGX_QUIC_CID_ROUTE_WORKER_ID_LENGTH - qmcf->cid_server_id_length < NGX_QUIC_CID_ROUTE_ENTROPY) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "|xquic|insufficient entropy space|");
    }

#undef NGX_QUIC_CID_ROUTE_WORKER_ID_OFFSET
#undef NGX_QUIC_CID_ROUTE_ENTROPY
#undef NGX_QUIC_CID_ROUTE_SERVER_ID
#undef NGX_QUIC_CID_ROUTE_FIRST_OCTER

#endif


    return NGX_CONF_OK;
}


static void *
ngx_http_xquic_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_xquic_srv_conf_t *qscf;

    qscf = ngx_pcalloc(cf->pool, sizeof(ngx_http_xquic_srv_conf_t));
    if (qscf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc
     *     qscf->support_versions = 0;
     */

    qscf->post_enable = NGX_CONF_UNSET;

    qscf->idle_conn_timeout = NGX_CONF_UNSET_MSEC;
    qscf->max_idle_conn_timeout = NGX_CONF_UNSET_MSEC;

    qscf->time_wait = NGX_CONF_UNSET_MSEC;
    qscf->time_wait_max_conns = NGX_CONF_UNSET_UINT;

    qscf->session_flow_control_window = NGX_CONF_UNSET_SIZE;
    qscf->stream_flow_control_window = NGX_CONF_UNSET_SIZE;

    return qscf;
}

static char *
ngx_http_xquic_merge_srv_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_xquic_srv_conf_t *prev = parent;
    ngx_http_xquic_srv_conf_t *conf = child;

    ngx_conf_merge_msec_value(conf->idle_conn_timeout,
                              prev->idle_conn_timeout, 30000);

    ngx_conf_merge_msec_value(conf->max_idle_conn_timeout,
                              prev->max_idle_conn_timeout, 60000);

    ngx_conf_merge_msec_value(conf->time_wait, prev->time_wait, 200000);
    ngx_conf_merge_uint_value(conf->time_wait_max_conns,
                              prev->time_wait_max_conns, 10000);

    ngx_conf_merge_size_value(conf->session_flow_control_window,
                              prev->session_flow_control_window, 1 *1024 * 1024);
    ngx_conf_merge_size_value(conf->stream_flow_control_window,
                              prev->stream_flow_control_window, 128 * 1024);

    return NGX_CONF_OK;
}

static ngx_int_t
ngx_http_xquic_module_init(ngx_cycle_t *cycle) 
{
    if (ngx_http_xquic_main_conf == NULL) {
        /* if nginx.conf without http {} then xquic main conf equal null */
        return NGX_OK;
    }
    
    if (ngx_xquic_intercom_master_init_ctx(cycle) == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0, 
                "|xquic|ngx_http_xquic_module_init intercom init error|");
        return NGX_ERROR; 
    }

    return NGX_OK;
}
ngx_int_t 
ngx_http_xquic_check_hc_file(ngx_http_xquic_main_conf_t *qmcf)
{
    char hc_file_chars[NGX_XQUIC_HC_FILE_PATH_LEN] = {0};

    if (qmcf->hc_file.data != NULL 
        && qmcf->hc_file.len > 0 
        && qmcf->hc_file.len < NGX_XQUIC_HC_FILE_PATH_LEN)
    {
        ngx_memcpy(hc_file_chars, qmcf->hc_file.data, qmcf->hc_file.len);
    }

    if (hc_file_chars[0] == 0) {
        /* do not check the file */
        return NGX_OK;
    }

    if (access(hc_file_chars, F_OK) == 0) {
        return NGX_OK;

    } else {
        return NGX_ERROR;
    }
}

static ngx_int_t
ngx_http_xquic_process_init(ngx_cycle_t *cycle)
{
    if (ngx_http_xquic_main_conf == NULL) {
        /* if nginx.conf without http {} then xquic main conf equal null */
        return NGX_OK;
    }

    if (ngx_xquic_process_init(cycle) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}

static void
ngx_http_xquic_process_exit(ngx_cycle_t *cycle)
{
    if (ngx_http_xquic_main_conf == NULL) {
        return;
    }

    ngx_xquic_process_exit(cycle);
}


static ngx_int_t
ngx_http_xquic_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt         *h;
    ngx_http_core_main_conf_t   *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_ACCESS_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_xquic_access_handler;

    

    return NGX_OK;
}


static ngx_int_t
ngx_http_xquic_access_handler(ngx_http_request_t *r)
{
    ngx_http_xquic_connection_t   *qc;

    if (!r->xqstream) {
        return NGX_DECLINED;
    }

    qc = r->xqstream->connection;

    if (qc->xquic_off) {
        ngx_log_debug(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                      "xquic access handler: quic off");

        return NGX_HTTP_CLIENT_CLOSED_REQUEST;
    }

    // ngx_http_quic_status_init(qc, &(r->headers_in.host)->value);

    return NGX_DECLINED;
}


static ngx_int_t
ngx_http_xquic_status_handler(ngx_http_request_t *r)
{
    size_t             size;
    ngx_int_t          rc;
    ngx_buf_t         *b;
    ngx_chain_t        out;
    ngx_atomic_int_t   cps, active, rq, limit_conns, limit_reqs;

    if (r->method != NGX_HTTP_GET && r->method != NGX_HTTP_HEAD) {
        return NGX_HTTP_NOT_ALLOWED;
    }

    rc = ngx_http_discard_request_body(r);

    if (rc != NGX_OK) {
        return rc;
    }

    r->headers_out.content_type_len = sizeof("text/plain") - 1;
    ngx_str_set(&r->headers_out.content_type, "text/plain");
    r->headers_out.content_type_lowcase = NULL;

    if (r->method == NGX_HTTP_HEAD) {
        r->headers_out.status = NGX_HTTP_OK;

        rc = ngx_http_send_header(r);

        if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
            return rc;
        }
    }

    size = sizeof("xquic: accepts active requests limit_conns limit_requests\n") - 1
           + 8 + 5 * NGX_ATOMIC_T_LEN;

    b = ngx_create_temp_buf(r->pool, size);
    if (b == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    out.buf = b;
    out.next = NULL;

    cps = *ngx_stat_quic_conns;
    active = *ngx_stat_quic_concurrent_conns;
    rq = *ngx_stat_quic_queries;
    limit_conns = *ngx_stat_quic_conns_refused;
    limit_reqs = *ngx_stat_quic_queries_refused;

    b->last = ngx_cpymem(b->last, "xquic: accepts active requests limit_conns limit_requests\n",
                         sizeof("xquic: accepts active requests limit_conns limit_requests\n") - 1);

    b->last = ngx_sprintf(b->last, " %uA %uA %uA %uA %uA \n", cps, active, rq, limit_conns, limit_reqs);

    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = b->last - b->pos;

    b->last_buf = (r == r->main) ? 1 : 0;
    b->last_in_chain = 1;

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    return ngx_http_output_filter(r, &out);
}


static char *
ngx_http_set_xquic_status(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t  *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_xquic_status_handler;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_xquic_ssl_static_variable(ngx_http_request_t *r,
                              ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ssl_variable_handler_pt   handler = (ngx_ssl_variable_handler_pt) data;
    size_t                        len;
    ngx_str_t                     s;
    ngx_http_xquic_connection_t  *qc;

    if (r->xqstream && r->xqstream->connection)  {
        qc = r->xqstream->connection;
        if (qc->ssl_conn) {
            (void) handler(qc->ssl_conn, NULL, &s);
            v->data = s.data;
            for (len = 0; v->data[len]; len++) { /* void */ }
            v->len = len;
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
ngx_xquic_ssl_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v,
                       uintptr_t data)
{
    ngx_ssl_variable_handler_pt   handler = (ngx_ssl_variable_handler_pt) data;
    ngx_str_t                     s;
    ngx_http_xquic_connection_t  *qc;

    if (r->xqstream && r->xqstream->connection)  {
        qc = r->xqstream->connection;
        if (qc->ssl_conn) {
            if (handler(qc->ssl_conn, r->pool, &s) != NGX_OK) {
                return NGX_ERROR;
            }

            v->len = s.len;
            v->data = s.data;

            if (v->len) {
                v->valid = 1;
                v->no_cacheable = 0;
                v->not_found = 0;

                return NGX_OK;
            }
        }
    }

    v->not_found = 1;

    return NGX_OK;
}


ngx_int_t
ngx_xquic_ssl_get_protocol(SSL *ssl, ngx_pool_t *pool, ngx_str_t *s)
{
    s->data = (u_char *) SSL_get_version(ssl);
    return NGX_OK;
}


ngx_int_t
ngx_xquic_ssl_get_cipher_name(SSL *ssl, ngx_pool_t *pool, ngx_str_t *s)
{
    s->data = (u_char *) SSL_get_cipher_name(ssl);
    return NGX_OK;
}


ngx_int_t
ngx_xquic_ssl_get_session_reused(SSL *ssl, ngx_pool_t *pool, ngx_str_t *s)
{
    if (SSL_session_reused(ssl)) {
        ngx_str_set(s, "r");

    } else {
        ngx_str_set(s, ".");
    }

    return NGX_OK;
}
void
ngx_http_xquic_close_reuseport_fd(ngx_cycle_t *cycle)
{
    ngx_listening_t   *ls;
    ngx_uint_t         i = 0;
    ngx_connection_t  *c;
#if (T_DYRELOAD)
    ngx_listening_t  **lsp;
    ngx_uint_t         j = 0;
    lsp = cycle->listening.elts;
    for (j = 0; j < cycle->listening.nelts; j++) {
        ls = lsp[j];
#else
    ls = cycle->listening.elts;
    for (i = 0; i < cycle->listening.nelts; i++) {
#endif

        if (ls[i].xquic
            && ls[i].reuseport
            && ngx_process == NGX_PROCESS_WORKER
            && ls[i].worker == ngx_worker) 
        {
            if (ls[i].fd == -1) {
                continue;
            }
            c = ls[i].connection;
            if (c) {
                if (c->read && c->read->active) { /* Clean up the read event */
                    if (ngx_event_flags & NGX_USE_EPOLL_EVENT) {
                        ngx_del_event(c->read, NGX_READ_EVENT, 0);
                    } else {
                        ngx_del_event(c->read, NGX_READ_EVENT, NGX_CLOSE_EVENT);
                    }   
                }
                ngx_free_connection(c);
                c->fd = (ngx_socket_t) -1;
            }

            if (ngx_close_socket(ls[i].fd) == -1) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_socket_errno,
                        "|xquic|close fd failed,fd: %d, addr: %V|", ls[i].fd, &ls[i].addr_text);
            }
            ls[i].fd = (ngx_socket_t) -1;
        }
    }

}

