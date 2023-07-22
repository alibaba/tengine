/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _NGX_HTTP_V3_STREAM_H_INCLUDED_
#define _NGX_HTTP_V3_STREAM_H_INCLUDED_


#include <ngx_core.h>
#include <ngx_config.h>
#include <ngx_http.h>
#include <ngx_http_xquic.h>

#include <xquic/xquic.h>
#include <xquic/xqc_http3.h>


#define NGX_HTTP_V3_DATA_DISCARD         1
#define NGX_HTTP_V3_DATA_ERROR           2
#define NGX_HTTP_V3_DATA_INTERNAL_ERROR  3



int ngx_http_v3_request_create_notify(xqc_h3_request_t *h3_request, void *user_data);
int ngx_http_v3_request_close_notify(xqc_h3_request_t *h3_request, void *user_data);
int ngx_http_v3_request_write_notify(xqc_h3_request_t *h3_request, void *user_data);
int ngx_http_v3_request_read_notify(xqc_h3_request_t *h3_request, xqc_request_notify_flag_t flag,
    void *user_data);
int ngx_http_v3_request_send(xqc_h3_request_t *h3_request, 
    ngx_http_v3_stream_t *user_stream);

ngx_int_t ngx_http_v3_init_request_body(ngx_http_request_t *r);
ngx_int_t ngx_http_v3_recv_body(ngx_http_request_t *r, ngx_http_v3_stream_t *stream, 
    xqc_h3_request_t *h3_request);


void ngx_http_v3_close_stream(ngx_http_v3_stream_t *h3_stream, ngx_int_t rc);

#endif /* _NGX_HTTP_V3_STREAM_H_INCLUDED_ */

