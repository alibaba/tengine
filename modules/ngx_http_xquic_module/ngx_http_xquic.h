/*
 * Copyright (C) 2020-2026 Alibaba Group Holding Limited
 */

#ifndef _NGX_HTTP_XQUIC_H_INCLUDED_
#define _NGX_HTTP_XQUIC_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_http.h>
#include <ngx_xquic.h>

#include <xquic/xquic_typedef.h>
#include <xquic/xquic.h>
#include <xquic/xqc_http3.h>



typedef struct ngx_http_xquic_connection_s ngx_http_xquic_connection_t;
typedef struct ngx_xquic_list_node_s   ngx_xquic_list_node_t;
typedef struct ngx_xquic_path_s    ngx_xquic_path_t;


#define NGX_XQUIC_CONN_NO_ERR           0
#define NGX_XQUIC_CONN_RECV_ERR         1
#define NGX_XQUIC_CONN_WRITE_ERR        2
#define NGX_XQUIC_CONN_INTERNAL_ERR     3
#define NGX_XQUIC_CONN_HANDSHAKE_ERR    4

#define NGX_XQUIC_MP_PATH_INDEX      7



struct ngx_http_xquic_connection_s {
    ngx_connection_t               *connection;
    ngx_http_connection_t          *http_connection;

    ngx_ssl_conn_t                 *ssl_conn;

    ngx_connection_t               *free_fake_connections;

    ngx_http_v3_stream_t           *free_streams;

    ngx_xquic_list_node_t         **streams_index;

    ngx_xquic_list_node_t         **path_index;

    uint64_t                        connection_id;
    xqc_cid_t                       dcid;

    ngx_uint_t                      processing;

    ngx_uint_t                      streams_cnt;

    uint64_t                        recv_packets_num;

    ngx_pool_t                     *pool;

    struct sockaddr                *peer_sockaddr;
    socklen_t                       peer_socklen;

    struct sockaddr                *local_sockaddr;
    socklen_t                       local_socklen;

    ngx_str_t                       addr_text;

    ngx_str_t                      *sni;

    ngx_msec_t                      start_msec;
    ngx_msec_t                      fb_time;
    ngx_msec_t                      handshake_time;

    uint64_t                        stream_cnt;
    uint64_t                        stream_body_sent;
    uint64_t                        stream_req_time;

    unsigned                        xquic_off:1;
    unsigned                        closing:1;
    unsigned                        logged:1;
    unsigned                        krej_sent:1;
    unsigned                        kshlo_sent:1;
    unsigned                        blocked:1;
    unsigned                        destroyed:1;
    unsigned                        wait_to_close:1;


    void                           *stats_ctx;

    xqc_engine_t                   *engine;
};


typedef enum {
    NGX_XQUIC_PATH_STATE_CLOSED = 0,
    NGX_XQUIC_PATH_STATE_AVAILABLE
} ngx_xquic_path_state_e;

struct ngx_xquic_path_s {
    uint64_t                        path_id;
    xqc_cid_t                       scid;

    ngx_connection_t               *c;
    ngx_http_xquic_connection_t    *qc;
    
    ngx_xquic_path_state_e          path_state;
};


typedef struct {
    ngx_str_t                       name;
    ngx_str_t                       value;
} ngx_http_v3_header_t;


struct ngx_xquic_list_node_s {
    ngx_xquic_list_node_t   *next;
    void                    *entry;
};

struct ngx_http_v3_stream_s {
    ngx_http_request_t           *request;
    ngx_http_xquic_connection_t  *connection;

    ngx_msec_t                    start_msec;
    ngx_msec_t                    req_time;

    uint64_t                      body_sent;
    ngx_uint_t                    queued;

    ngx_buf_t                    *body_buffer;

    uint32_t                      id;

    unsigned                      skip_data:2;
    unsigned                      closed:1;
    unsigned                      header_recvd:1;
    unsigned                      in_closed:1;
    unsigned                      out_closed:1;
    unsigned                      engine_inner_closed:1;
    unsigned                      request_closed:1;
    unsigned                      run_request:1;
    unsigned                      handled:1;
    unsigned                      wait_to_write:1;
    unsigned                      request_freed:1;

    void                         *xquic_stream;
    size_t                        send_offset;

    ngx_chain_t                  *output_queue;
    ngx_chain_t                 **last_chain;
    ngx_chain_t                  *free_bufs;

    void                         *h3_request;
    xqc_http_headers_t            resp_headers;

    ngx_array_t                  *cookies;

#if (T_HEADER_SIZE)
    size_t                        req_header_size;
    size_t                        resp_header_size;
#endif

    size_t                        send_body_max;
    size_t                        send_body_len;
    u_char                       *send_body;

    ngx_int_t                     cancel_status;

    void                         *next;
    ngx_xquic_list_node_t        *list_node;
};


ngx_http_xquic_connection_t * ngx_http_v3_create_connection(ngx_connection_t *lc, const xqc_cid_t *connection_id,
                                struct sockaddr *local_sockaddr, socklen_t local_socklen,
                                struct sockaddr *peer_sockaddr, socklen_t peer_socklen,
                                xqc_engine_t *engine);

void ngx_http_v3_finalize_connection(ngx_http_xquic_connection_t *h3c,
    ngx_uint_t status);

void ngx_http_v3_connection_error(ngx_http_xquic_connection_t *qc, 
    ngx_uint_t err, const char *err_details);

void ngx_http_v3_finalize_paths(ngx_http_xquic_connection_t *qc);

ngx_chain_t *ngx_http_xquic_send_chain(ngx_connection_t *fc, ngx_chain_t *in, off_t limit);

ngx_int_t ngx_http_v3_read_request_body(ngx_http_request_t *r);

ngx_int_t ngx_http_v3_read_unbuffered_request_body(ngx_http_request_t *r);

ngx_int_t ngx_http_v3_process_request_body(ngx_http_request_t *r, u_char *pos,
    size_t size, ngx_uint_t last);

ngx_int_t ngx_http_v3_filter_request_body(ngx_http_request_t *r);

void ngx_http_v3_read_client_request_body_handler(ngx_http_request_t *r);

ngx_int_t ngx_xquic_path_create(ngx_http_xquic_connection_t *qc, 
    xqc_cid_t *connection_id, uint64_t path_id,
    struct sockaddr *local_sockaddr, socklen_t local_socklen,
    struct sockaddr *peer_sockaddr, socklen_t peer_socklen);

int ngx_xquic_path_created_notify(xqc_connection_t *conn,
    const xqc_cid_t *path_scid, uint64_t path_id,
    void *conn_user_data);

void ngx_xquic_path_removed_notify(const xqc_cid_t *scid, uint64_t path_id,
    void *conn_user_data);

xqc_int_t ngx_http_v3_cert_cb(const char *sni, void **chain,
    void **cert, void **key, void *conn_user_data);


#if (T_NGX_HTTP_SSL_FINGERPRINT)

void ngx_http_v3_ssl_msg_cb(int msg_type, 
    const void *msg, size_t msg_len, void *user_data);

#endif

#endif /* _NGX_HTTP_XQUIC_H_INCLUDED_ */

