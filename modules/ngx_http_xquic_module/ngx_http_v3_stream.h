/*
 * Copyright (C) 2020-2026 Alibaba Group Holding Limited
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

/*
 * Custom recv() for HTTP/3 upgraded connections (e.g. WebSocket).
 *
 * After a 101 Switching Protocols upgrade, ngx_http_upstream_process_upgraded()
 * calls src->recv() on the downstream (client-side) connection to read
 * upgraded frames.  For HTTP/3 the downstream is a QUIC fake connection
 * whose recv pointer is NULL — QUIC body data must be pulled via
 * xqc_h3_request_recv_body(), not via a socket read.  Calling a NULL recv
 * pointer causes SIGSEGV.
 *
 * This function is installed as fc->recv inside ngx_http_upstream_upgrade()
 * when r->http_version == NGX_HTTP_VERSION_30, so that the generic upstream
 * tunnel loop works without any further changes.
 */
ssize_t ngx_http_v3_upgrade_recv(ngx_connection_t *c, u_char *buf,
    size_t size);

/*
 * Custom send() for HTTP/3 upgraded connections (e.g. WebSocket).
 *
 * After a 101 Switching Protocols upgrade, ngx_http_upstream_process_upgraded()
 * calls dst->send() on the downstream (client-side) connection to write
 * upgraded frames received from the upstream.  For HTTP/3 the downstream is
 * a QUIC fake connection whose send pointer is NULL — QUIC body data must be
 * pushed via xqc_h3_request_send_body(), not via a socket write.  Calling a
 * NULL send pointer causes SIGSEGV (same root cause as the recv crash).
 *
 * This function is installed as fc->send inside ngx_http_upstream_upgrade()
 * when r->http_version == NGX_HTTP_VERSION_30, complementing the recv fix.
 */
ssize_t ngx_http_v3_upgrade_send(ngx_connection_t *c, u_char *buf,
    size_t size);

#endif /* _NGX_HTTP_V3_STREAM_H_INCLUDED_ */

