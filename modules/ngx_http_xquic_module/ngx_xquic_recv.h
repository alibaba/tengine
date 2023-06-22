/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _T_NGX_XQUIC_RECV_H_INCLUDED_
#define _T_NGX_XQUIC_RECV_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_event.h>
#include <ngx_http.h>

#include <xquic/xquic_typedef.h>


typedef struct {
    union {
        struct sockaddr   sockaddr;
        u_char            sa[NGX_SOCKADDRLEN];
    };
    socklen_t             socklen;

    union {
        struct sockaddr   local_sockaddr;
        u_char            lsa[NGX_SOCKADDRLEN];
    };
    socklen_t             local_socklen;

    char                  buf[1500];
    struct {
        char              unused;
        uint64_t          connection_id;
        xqc_cid_t         dcid;
        xqc_cid_t         scid;
    } xquic;

    size_t                len;
} ngx_xquic_recv_packet_t;

ngx_int_t ngx_xquic_recv(ngx_connection_t *c, char *buf, size_t size);
ngx_int_t ngx_xquic_recv_packet(ngx_connection_t *c, ngx_xquic_recv_packet_t *packet, ngx_log_t *log, xqc_engine_t *engine);
void ngx_xquic_event_recv(ngx_event_t *ev);
void ngx_xquic_dispatcher_process_packet(ngx_connection_t *c, ngx_xquic_recv_packet_t *packet);
void ngx_xquic_recv_from_intercom(ngx_xquic_recv_packet_t *packet);
void ngx_xquic_packet_get_cid(ngx_xquic_recv_packet_t *packet, 
    xqc_engine_t *engine);

void ngx_xquic_packet_get_cid_raw(xqc_engine_t *engine, unsigned char *payload, size_t sz,
    xqc_cid_t *dcid, xqc_cid_t *scid);

#if (T_NGX_UDPV2)
void ngx_xquic_dispatcher_process(ngx_connection_t *c, const ngx_udpv2_packet_t *upkt);
#endif

#if (NGX_XQUIC_SUPPORT_CID_ROUTE)
/**
 * generate local CID based on spec of worker ID
 * */
ssize_t     ngx_xquic_generate_route_cid(unsigned char *buf, size_t len, const uint8_t *current_cid_buf, size_t current_cid_buflen);

/**
 * choose the specific worker based on received packets
 * */
ngx_int_t   ngx_xquic_get_target_worker_from_cid(ngx_xquic_recv_packet_t *packet);
#endif

#define NGX_XQUIC_CHECK_MAGIC_BIT(pos) (((*(pos)) & 0x40) == 0x40)
#define NGX_XQUIC_HEALTH_CHECK  "Healthcheck"
#define NGX_XQUIC_HEALTH_CHECK_REQ  "UDPSTATUS"
#define NGX_XQUIC_HEALTH_CHECK_RSP  "UDPOK"

#endif /* _T_NGX_XQUIC_RECV_H_INCLUDED_ */

