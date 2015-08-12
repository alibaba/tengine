
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_H_INCLUDED_
#define _NGX_HTTP_TFS_H_INCLUDED_


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_tfs_common.h>
#include <ngx_http_tfs_json.h>
#include <ngx_http_tfs_protocol.h>
#include <ngx_http_tfs_restful.h>
#include <ngx_http_connection_pool.h>
#include <ngx_http_tfs_rc_server_info.h>
#include <ngx_http_tfs_block_cache.h>
#include <ngx_http_tfs_duplicate.h>
#include <ngx_http_tfs_raw_fsname.h>
#include <ngx_http_tfs_peer_connection.h>
#include <ngx_http_tfs_tair_helper.h>
#include <ngx_http_tfs_timers.h>


typedef ngx_table_elt_t *(*ngx_http_tfs_create_header_pt)
    (ngx_http_request_t *r);


typedef struct {
    ngx_str_t                      state_msg;
    ngx_int_t                      state;
} ngx_http_tfs_state_t;


typedef struct {
    uint32_t                       ds_count;
    ngx_http_tfs_inet_t           *ds_addrs;
    int32_t                        version;
    int32_t                        lease_id;
} ngx_http_tfs_block_info_t;


typedef struct {
    uint32_t                       block_id;
    uint64_t                       file_id;
    int64_t                        offset;  /* offset in the file */
    uint32_t                       size;
    uint32_t                       crc;
} NGX_PACKED ngx_http_tfs_segment_info_t;


typedef struct {
    u_char                         file_name[NGX_HTTP_TFS_FILE_NAME_LEN];
    int64_t                        offset;
    uint32_t                       size;
    uint32_t                       crc;
} NGX_PACKED ngx_http_tfs_tmp_segment_info_t;


struct ngx_http_tfs_segment_data_s {
    uint8_t                        cache_hit;
    ngx_http_tfs_segment_info_t    segment_info;
    /* read/write offset inside this segment */
    uint32_t                       oper_offset;
    /* read/write size inside this segment */
    uint32_t                       oper_size;
    union {
        uint64_t                   write_file_number;
    };
    ngx_http_tfs_block_info_t      block_info;
    ngx_uint_t                     ds_retry;
    ngx_uint_t                     ds_index;
    ngx_chain_t                   *data;
    ngx_chain_t                   *orig_data; /* for write retry */
} NGX_PACKED;


typedef struct {
    uint8_t                        still_have; /* for custom file */
    uint32_t                       cluster_id;
    uint32_t                       open_mode;
    /* not for large_file's data */
    int64_t                        file_offset;
    uint64_t                       left_length;
    uint64_t                       file_hole_size;
    uint32_t                       last_write_segment_index;
    uint32_t                       segment_index;
    uint32_t                       segment_count;
    ngx_http_tfs_segment_data_t   *segment_data;
    uint32_t                       curr_batch_count;
} NGX_PACKED ngx_http_tfs_file_t;


struct  ngx_http_tfs_upstream_s {
    ngx_str_t                      lock_file;
    ngx_msec_t                     rcs_interval;

    ngx_str_t                      rcs_zone_name;
    ngx_shm_zone_t                *rcs_shm_zone;
    ngx_http_tfs_rc_ctx_t         *rc_ctx;
    uint8_t                        rcserver_index;
    uint32_t                       rc_servers_count;
    uint64_t                       rc_servers[NGX_HTTP_TFS_MAX_RCSERVER_COUNT];

    /* upstream name and port */
    in_port_t                      port;
    ngx_str_t                      host;
    ngx_addr_t                    *ups_addr;

    struct sockaddr_in             local_addr;
    u_char                         local_addr_text[NGX_INET_ADDRSTRLEN];

    ngx_flag_t                     enable_rcs;

    ngx_http_tfs_timers_data_t    *timer_data;

    unsigned                       used:1;
};


struct  ngx_http_tfs_loc_conf_s {
    ngx_msec_t                     timeout;

    size_t                         max_temp_file_size;
    size_t                         temp_file_write_size;

    size_t                         busy_buffers_size_conf;

    uint64_t                       meta_root_server;
    ngx_http_tfs_meta_table_t      meta_server_table;

    ngx_http_tfs_upstream_t       *upstream;
};


typedef struct {

    ngx_log_t                     *log;
} ngx_http_tfs_srv_conf_t;


struct  ngx_http_tfs_main_conf_s {
    ngx_msec_t                     tfs_connect_timeout;
    ngx_msec_t                     tfs_send_timeout;
    ngx_msec_t                     tfs_read_timeout;

    ngx_msec_t                     tair_timeout;
    ngx_http_tfs_tair_instance_t   dup_instances[NGX_HTTP_TFS_MAX_CLUSTER_COUNT];

    size_t                         send_lowat;
    size_t                         buffer_size;
    size_t                         body_buffer_size;
    size_t                         busy_buffers_size;

    ngx_shm_zone_t                *block_cache_shm_zone;

    ngx_flag_t                     enable_remote_block_cache;
    ngx_http_tfs_tair_instance_t   remote_block_cache_instance;
    ngx_http_tfs_local_block_cache_ctx_t *local_block_cache_ctx;

    ngx_http_connection_pool_t    *conn_pool;

    uint32_t                       cluster_id;

    ngx_array_t                    upstreams;
};


typedef ngx_int_t (*tfs_peer_handler_pt)(ngx_http_tfs_t *t);
typedef void (*ngx_http_tfs_handler_pt)(ngx_http_request_t *r,
    ngx_http_tfs_t *t);
typedef ngx_int_t (*ngx_http_tfs_sub_process_pt)(ngx_http_tfs_t *t);


typedef struct {
    ngx_list_t                     headers;

    ngx_uint_t                     status_n;
    ngx_str_t                      status_line;

    ngx_table_elt_t               *status;
    ngx_table_elt_t               *date;
    ngx_table_elt_t               *server;
    ngx_table_elt_t               *connection;

    ngx_table_elt_t               *expires;
    ngx_table_elt_t               *etag;
    ngx_table_elt_t               *x_accel_expires;
    ngx_table_elt_t               *x_accel_redirect;
    ngx_table_elt_t               *x_accel_limit_rate;

    ngx_table_elt_t               *content_type;
    ngx_table_elt_t               *content_length;

    ngx_table_elt_t               *last_modified;
    ngx_table_elt_t               *location;
    ngx_table_elt_t               *accept_ranges;
    ngx_table_elt_t               *www_authenticate;

#if (NGX_HTTP_GZIP)
    ngx_table_elt_t               *content_encoding;
#endif

    off_t                          content_length_n;

    ngx_array_t                    cache_control;
} ngx_http_tfs_headers_in_t;


struct ngx_http_tfs_s {
    ngx_http_tfs_handler_pt        read_event_handler;
    ngx_http_tfs_handler_pt        write_event_handler;

    ngx_http_tfs_peer_connection_t *tfs_peer;
    ngx_http_tfs_peer_connection_t *tfs_peer_servers;
    uint8_t                       tfs_peer_count;

    ngx_http_tfs_loc_conf_t       *loc_conf;
    ngx_http_tfs_srv_conf_t       *srv_conf;
    ngx_http_tfs_main_conf_t      *main_conf;

    ngx_http_tfs_restful_ctx_t     r_ctx;

    ngx_output_chain_ctx_t         output;
    ngx_chain_writer_ctx_t         writer;

    ngx_chain_t                   *request_bufs;
    ngx_chain_t                   *send_body;
    ngx_pool_t                    *pool;

    ngx_buf_t                      header_buffer;

    ngx_chain_t                   *recv_chain;

    ngx_chain_t                   *out_bufs;
    ngx_chain_t                   *busy_bufs;
    ngx_chain_t                   *free_bufs;

    ngx_http_tfs_rcs_info_t       *rc_info_node;
    ngx_rbtree_node_t             *node;

    ngx_uint_t                     logical_cluster_index;
    ngx_uint_t                     rw_cluster_index;

    /* keep alive */
    ngx_queue_t                   *curr_ka_queue;

    /* header pointer */
    void                          *header;
    ngx_int_t                      header_size;

    tfs_peer_handler_pt            create_request;
    tfs_peer_handler_pt            input_filter;
    tfs_peer_handler_pt            retry_handler;
    tfs_peer_handler_pt            process_request_body;
    tfs_peer_handler_pt            finalize_request;
    tfs_peer_handler_pt            decline_handler;

    void                          *finalize_data;
    void                          *data;

    ngx_int_t                      request_sent;
    ngx_uint_t                     sent_size;
    off_t                          length;

    ngx_log_t                     *log;

    ngx_int_t                      parse_state;

    /* final file name */
    ngx_str_t                      file_name;

    ngx_int_t                      state;

    /* custom file */
    ngx_http_tfs_custom_meta_info_t meta_info;
    ngx_str_t                      last_file_path;
    int64_t                        last_file_pid;
    uint8_t                        last_file_type;
    ngx_int_t                     *dir_lens;
    ngx_int_t                      last_dir_level;
    uint16_t                       orig_action;
    ngx_array_t                    file_holes;

    ngx_http_tfs_headers_in_t      headers_in;

    /* delete */
    ngx_int_t                      group_count;
    ngx_int_t                      group_seq;

    /* name ip */
    ngx_http_tfs_inet_t            name_server_addr;
    ngx_str_t                      name_server_addr_text;

    ngx_http_tfs_json_gen_t       *json_output;

    ngx_uint_t                     status;
    ngx_str_t                      status_line;
    ngx_int_t                      tfs_status;

    uint64_t                       output_size;

    /* de-duplicate info */
    ngx_http_tfs_dedup_ctx_t       dedup_ctx;

    /* stat info */
    ngx_http_tfs_stat_info_t       stat_info;

    /* file info */
    ngx_chain_t                   *meta_segment_data;
    ngx_http_tfs_file_t            file;
    ngx_http_tfs_segment_head_t   *seg_head;
    ngx_http_tfs_raw_file_stat_t   file_stat;
    ngx_buf_t                     *readv2_rsp_tail_buf;
    uint8_t                        read_ver;
    uint8_t                        retry_count;

    /* block cache */
    ngx_http_tfs_block_cache_ctx_t block_cache_ctx;

    /* for parallel write segments */
    ngx_http_tfs_t                *parent;
    ngx_http_tfs_t                *next;
    ngx_http_tfs_t                *free_sts;
    ngx_http_tfs_sub_process_pt    sp_callback;
    uint32_t                       sp_count;
    uint32_t                       sp_done_count;
    uint32_t                       sp_fail_count;
    uint32_t                       sp_succ_count;
    uint32_t                       sp_curr;
    unsigned                       sp_ready:1;

    unsigned                       header_only:1;
    unsigned                       has_split_frag:1;
    /* for custrom file read */
    unsigned                       is_first_segment:1;

    unsigned                       use_dedup:1;
    unsigned                       is_stat_dup_file:1;
    unsigned                       is_large_file:1;
    unsigned                       is_process_meta_seg:1;
    unsigned                       retry_curr_ns:1;
    unsigned                       request_timeout:1;
    unsigned                       client_abort:1;
    unsigned                       is_rolling_back:1;
    unsigned                       header_sent:1;
};


ngx_int_t ngx_http_tfs_init(ngx_http_tfs_t *t);
void ngx_http_tfs_finalize_request(ngx_http_request_t *r,
    ngx_http_tfs_t *t, ngx_int_t rc);
void ngx_http_tfs_finalize_state(ngx_http_tfs_t *t, ngx_int_t rc);
ngx_int_t ngx_http_tfs_reinit(ngx_http_request_t *r, ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_connect(ngx_http_tfs_t *t);
/* block cache related */
ngx_int_t ngx_http_tfs_lookup_block_cache(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_batch_lookup_block_cache(ngx_http_tfs_t *t);
void ngx_http_tfs_remove_block_cache(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);

ngx_int_t ngx_http_tfs_set_output_appid(ngx_http_tfs_t *t, uint64_t app_id);
void ngx_http_tfs_set_custom_initial_parameters(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_misc_ctx_init(ngx_http_tfs_t *t,
    ngx_http_tfs_rcs_info_t *rc_node);

/* dedup related */
ngx_int_t ngx_http_tfs_get_duplicate_info(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_set_duplicate_info(ngx_http_tfs_t *t);

/* sub process related */
ngx_int_t ngx_http_tfs_batch_process_start(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_batch_process_end(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_batch_process_next(ngx_http_tfs_t *t);


#endif /* _NGX_TFS_H_INCLUDED_ */
