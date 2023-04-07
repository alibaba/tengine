/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _T_NGX_XQUIC_INTERCOM_INCLUDED_H_
#define _T_NGX_XQUIC_INTERCOM_INCLUDED_H_

#include <ngx_xquic_recv.h>
#include <ngx_http_xquic_module.h>


ngx_int_t ngx_xquic_intercom_init(ngx_cycle_t *cycle, void *engine);
void ngx_xquic_intercom_exit();

void ngx_xquic_intercom_send(ngx_int_t worker_num, ngx_xquic_recv_packet_t *packet);

ngx_int_t ngx_xquic_intercom_packet_hash(ngx_xquic_recv_packet_t *packet);


#endif /* _T_NGX_XQUIC_INTERCOM_INCLUDED_H_ */

