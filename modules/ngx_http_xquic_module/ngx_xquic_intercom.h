/*
 * Copyright (C) 2020-2026 Alibaba Group Holding Limited
 */

#ifndef _T_NGX_XQUIC_INTERCOM_INCLUDED_H_
#define _T_NGX_XQUIC_INTERCOM_INCLUDED_H_

#include <ngx_xquic_recv.h>
#include <ngx_http_xquic_module.h>
#define NGX_XQUIC_LISTENING_DEFAULT_NUM 16

typedef struct {
    ngx_pool_t           *pool;
    ngx_socket_t         *reload_sock; /* 存放reload socket 数组，在master中创建*/
    ngx_array_t          xquic_ls; /* 存放ngx_cycle中quic 监听端口的ngx_listening_t结构体指针 */

    struct sockaddr_un   *addr;
    ngx_int_t            *addrlen;

    ngx_connection_t     *connection;
    ngx_connection_t     *reload_conn; /* reload队列的connection */

    ngx_log_t            *log;

    xqc_engine_t         *xquic_engine;

    ngx_int_t             worker_processes; /* 存放worker数量，当发现reload前后worker数量不一样时，告警出来 */
    ngx_uint_t            reload_expire_time; /* 往reload队列转发的超时时间 */
} ngx_xquic_intercom_ctx_t;


ngx_int_t ngx_xquic_intercom_init(ngx_cycle_t *cycle, void *engine);
void ngx_xquic_intercom_exit();

void ngx_xquic_intercom_send(ngx_int_t worker_num, ngx_xquic_recv_packet_t *packet,
    ngx_xquic_intercom_ctx_t *ctx);

ngx_int_t ngx_xquic_intercom_packet_hash(ngx_xquic_recv_packet_t *packet);
ngx_int_t ngx_xquic_reload_intercom_init(ngx_cycle_t *cycle, void *engine);
ngx_int_t ngx_xquic_intercom_master_init_ctx(ngx_cycle_t *cycle);
#endif /* _T_NGX_XQUIC_INTERCOM_INCLUDED_H_ */

