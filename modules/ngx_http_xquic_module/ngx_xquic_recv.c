/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */


#include <ngx_xquic_recv.h>
#include <ngx_xquic_intercom.h>
#include <ngx_http_xquic_module.h>
#include <ngx_xquic.h>

#include <xquic/xquic.h>
#include <xquic/xqc_errno.h>


ngx_inline void
ngx_xquic_packet_get_cid_raw(xqc_engine_t *engine, unsigned char *payload, size_t sz, 
    xqc_cid_t *dcid, xqc_cid_t *scid)
{
    uint8_t cid_len = xqc_engine_config_get_cid_len(engine);
    ngx_int_t rc = xqc_packet_parse_cid(dcid, scid, cid_len, payload, sz);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                    "|xquic|xqc_packet_parse_cid err|%i|config_cid_len:%d|dcid_len:%d|scid_len:%d|pkt_sz:%d|",
                        rc, cid_len, dcid->cid_len, scid->cid_len, sz);
    }
}


void
ngx_xquic_packet_get_cid(ngx_xquic_recv_packet_t *packet,
    xqc_engine_t *engine)
{
    return ngx_xquic_packet_get_cid_raw(engine, (unsigned char *)packet->buf, packet->len, &packet->xquic.dcid, &packet->xquic.scid);
}

ngx_int_t
ngx_xquic_recv(ngx_connection_t *c, char *buf, size_t size)
{
    ssize_t       n;
    ngx_err_t     err;
    ngx_event_t  *rev;

    rev = c->read;

    do {
        n = recv(c->fd, buf, size, 0);

        ngx_log_debug3(NGX_LOG_DEBUG_EVENT, c->log, 0,
                       "ngx_quic_recv: fd:%d %d of %d", c->fd, n, size);

        if (n >= 0) {
            return n;
        }

        err = ngx_socket_errno;

        if (err == NGX_EAGAIN || err == NGX_EINTR) {
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, err,
                           "ngx_quic_recv: recv() not ready");
            n = NGX_AGAIN;
        } else if (err == NGX_ECONNREFUSED) {
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, err,
                           "ngx_quic_recv: recv() get icmp");
            n = NGX_DONE;
        } else {
            n = ngx_connection_error(c, err, "quic recv() failed");
            break;
        }
    } while (err == NGX_EINTR);

    rev->ready = 0;

    if (n == NGX_ERROR) {
        rev->error = 1;
    }

    return n;
}



ngx_int_t
ngx_xquic_recv_packet(ngx_connection_t *c, 
    ngx_xquic_recv_packet_t *packet, ngx_log_t *log, xqc_engine_t *engine)
{
    ssize_t                          n;
    struct iovec                     iov[1];
    struct msghdr                    msg;
    ngx_err_t                        err;

#if (NGX_HAVE_MSGHDR_MSG_CONTROL)

#if (NGX_HAVE_IP_PKTINFO)
    u_char             msg_control[CMSG_SPACE(sizeof(struct in_pktinfo))];
#elif (NGX_HAVE_IP_RECVDSTADDR)
    u_char             msg_control[CMSG_SPACE(sizeof(struct in_addr))];
#endif

#if (NGX_HAVE_INET6 && NGX_HAVE_IPV6_RECVPKTINFO)
    u_char             msg_control6[CMSG_SPACE(sizeof(struct in6_pktinfo))];
#endif

#endif
    
    iov[0].iov_base = (void *) &packet->buf;
    iov[0].iov_len = sizeof(packet->buf);

    msg.msg_name = &packet->sockaddr;
    msg.msg_namelen = NGX_SOCKADDRLEN;
    msg.msg_iov = iov;
    msg.msg_iovlen = 1;

#if (NGX_HAVE_MSGHDR_MSG_CONTROL)

#if (NGX_HAVE_IP_RECVDSTADDR || NGX_HAVE_IP_PKTINFO)
    if (packet->local_sockaddr.sa_family == AF_INET) {
        msg.msg_control = &msg_control;
        msg.msg_controllen = sizeof(msg_control);
    }
#endif

#if (NGX_HAVE_INET6 && NGX_HAVE_IPV6_RECVPKTINFO)
    if (packet->local_sockaddr.sa_family == AF_INET6) {
        msg.msg_control = &msg_control6;
        msg.msg_controllen = sizeof(msg_control6);
    }
#endif

#endif

    do {
        n = recvmsg(c->fd, &msg, 0);

        if (n >= 0) {
            break;
        }

        err = ngx_socket_errno;

        if (err == NGX_EAGAIN || err == NGX_EINTR) {
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, err,
                           "ngx_quic_recv_packet: recvmsg() not ready");
            n = NGX_AGAIN;
        } else if (err == NGX_ECONNREFUSED) {
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, err,
                           "ngx_quic_recv_packet: recvmsg() get icmp");
            n = NGX_DONE;
        } else {
            n = ngx_connection_error(c, err, "quic recvmsg() failed");
            break;
        }
    } while (err == NGX_EINTR);

    if (n < 0) {
        return n;
    }

    packet->len = n;
    packet->socklen = msg.msg_namelen;

#if (NGX_HAVE_MSGHDR_MSG_CONTROL)

    {
        struct cmsghdr   *cmsg;
        struct sockaddr  *sockaddr = &packet->local_sockaddr;
        socklen_t        *socklen  = &packet->local_socklen;

        for (cmsg = CMSG_FIRSTHDR(&msg);
                cmsg != NULL;
                cmsg = CMSG_NXTHDR(&msg, cmsg))
        {

#if (NGX_HAVE_IP_RECVDSTADDR)

            if (cmsg->cmsg_level == IPPROTO_IP
                    && cmsg->cmsg_type == IP_RECVDSTADDR
                    && packet->local_sockaddr.sa_family == AF_INET)
            {
                struct in_addr      *addr;
                struct sockaddr_in  *sin;

                addr = (struct in_addr *) CMSG_DATA(cmsg);
                sin = (struct sockaddr_in *) sockaddr;
                sin->sin_family = AF_INET;
                sin->sin_addr = *addr;
                *socklen = sizeof(struct sockaddr_in);

                break;
            }

#elif (NGX_HAVE_IP_PKTINFO)

            if (cmsg->cmsg_level == IPPROTO_IP
                    && cmsg->cmsg_type == IP_PKTINFO
                    && packet->local_sockaddr.sa_family == AF_INET)
            {
                struct in_pktinfo   *pkt;
                struct sockaddr_in  *sin;

                pkt = (struct in_pktinfo *) CMSG_DATA(cmsg);
                sin = (struct sockaddr_in *) sockaddr;
                sin->sin_family = AF_INET;
                sin->sin_addr = pkt->ipi_addr;
                *socklen = sizeof(struct sockaddr_in);

                break;
            }

#endif

#if (NGX_HAVE_INET6 && NGX_HAVE_IPV6_RECVPKTINFO)

            if (cmsg->cmsg_level == IPPROTO_IPV6
                    && cmsg->cmsg_type == IPV6_PKTINFO
                    && packet->local_sockaddr.sa_family == AF_INET6)
            {
                struct in6_pktinfo   *pkt6;
                struct sockaddr_in6  *sin6;

                pkt6 = (struct in6_pktinfo *) CMSG_DATA(cmsg);
                sin6 = (struct sockaddr_in6 *) sockaddr;
                sin6->sin6_family = AF_INET6;
                sin6->sin6_addr = pkt6->ipi6_addr;
                *socklen = sizeof(struct sockaddr_in6);

                break;
            }

#endif

        }
    }

#endif

#if (NGX_DEBUG)
    {
        ngx_str_t caddr, saddr;
        u_char    ctext[NGX_SOCKADDR_STRLEN];
        u_char    stext[NGX_SOCKADDR_STRLEN];

        if (log->log_level & NGX_LOG_DEBUG_EVENT) {
            caddr.data = ctext;
            caddr.len = ngx_sock_ntop(&packet->sockaddr, packet->socklen, ctext,
                    NGX_SOCKADDR_STRLEN, 1);
            saddr.data = stext;
            saddr.len = ngx_sock_ntop(&packet->local_sockaddr, packet->local_socklen, stext,
                    NGX_SOCKADDR_STRLEN, 1);

            ngx_log_debug4(NGX_LOG_DEBUG_EVENT, log, 0,
                    "ngx_xquic_recv_packet: %V->%V fd:%d n:%z",
                    &caddr, &saddr, c->fd, n);
        }

    }
#endif

    /* get dcid here */
    ngx_xquic_packet_get_cid(packet, engine);

    return NGX_OK;
}



void
ngx_xquic_event_recv(ngx_event_t *ev)
{
    ngx_int_t                         rc;
    ngx_listening_t                  *ls;
    ngx_connection_t                 *lc;
    ngx_event_conf_t                 *ecf;
    static ngx_xquic_recv_packet_t    packet;
    ngx_http_xquic_main_conf_t       *qmcf;

    ecf = ngx_event_get_conf(ngx_cycle->conf_ctx, ngx_event_core_module);

    if (ngx_event_flags & NGX_USE_RTSIG_EVENT) {
        ev->available = 1;
    } else if (!(ngx_event_flags & NGX_USE_KQUEUE_EVENT)) {
        ev->available = ecf->multi_accept;
    }

    lc = ev->data;
    ls = lc->listening;
    ev->ready = 0;

    qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);

    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "ngx_xquic_event_recv on %V, ready: %d",
                   &ls->addr_text, ev->available);

    do {
        packet.local_socklen = ls->socklen;
        ngx_memcpy(&packet.local_sockaddr, ls->sockaddr, ls->socklen);

        rc = ngx_xquic_recv_packet(lc, &packet, ev->log, qmcf->xquic_engine);
        if (rc != NGX_OK) {
            ngx_log_debug1(NGX_LOG_DEBUG_EVENT, ev->log, ngx_socket_errno,
                           "ngx_xquic_recv_packet: return rc=%i.", rc);
            goto finish_recv;
        }

#if (NGX_STAT_STUB)
        (void) ngx_atomic_fetch_add(ngx_stat_accepted, 1);
#endif

        ngx_accept_disabled = ngx_cycle->connection_n / 8
                              - ngx_cycle->free_connection_n;

        ngx_xquic_dispatcher_process_packet(lc, &packet);

        if (ngx_event_flags & NGX_USE_KQUEUE_EVENT) {
            ev->available --;
        }
    } while (ev->available);

finish_recv:
    xqc_engine_finish_recv(qmcf->xquic_engine);
}



void
ngx_xquic_dispatcher_process_packet(ngx_connection_t *c, ngx_xquic_recv_packet_t *packet)
{

    if (ngx_terminate || ngx_exiting) {
        return;
    }

    if (c->data == NULL) {
        ngx_log_error(NGX_LOG_WARN, c->log, 0,
                      "|xquic|ngx_xquic_dispatcher_process_packet: engine NULL|");
        return;
    }

    /* check QUIC magic bit */
    if (!NGX_XQUIC_CHECK_MAGIC_BIT(packet->buf)) {
        ngx_log_error(NGX_LOG_WARN, c->log, 0,
                      "|xquic|invalid packet head|");
        return;
    }

    /* check healthcheck */
    if (packet->len >= sizeof(NGX_XQUIC_HEALTH_CHECK)
        && ngx_strncmp(packet->buf, NGX_XQUIC_HEALTH_CHECK, sizeof(NGX_XQUIC_HEALTH_CHECK)-1) == 0) 
    {
        ngx_log_debug(NGX_LOG_DEBUG, c->log, 0,
                      "|xquic|health check|");
        return;
    }

    /* check healthcheck, REQ/RSP mode */
    if (packet->len == sizeof(NGX_XQUIC_HEALTH_CHECK_REQ)-1
        && ngx_strncmp(packet->buf, NGX_XQUIC_HEALTH_CHECK_REQ, sizeof(NGX_XQUIC_HEALTH_CHECK_REQ)-1) == 0)
    {
        ngx_log_debug(NGX_LOG_DEBUG, c->log, 0,
                      "|xquic|health check, req/rsp mode|");
        sendto(c->fd, NGX_XQUIC_HEALTH_CHECK_RSP, sizeof(NGX_XQUIC_HEALTH_CHECK_RSP)-1, 0, &packet->sockaddr, packet->socklen);
        return;
    }
    
    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);

#if (NGX_DEBUG)
    {
        ngx_str_t  addr, addr2;
        u_char     text[NGX_SOCKADDR_STRLEN], text2[NGX_SOCKADDR_STRLEN];
        if (c->log->log_level & NGX_LOG_DEBUG_EVENT) {
            addr.data = text;
            addr.len = ngx_sock_ntop(&packet->local_sockaddr, packet->local_socklen, text,
                                     NGX_SOCKADDR_STRLEN, 1);
            addr2.data = text2;
            addr2.len = ngx_sock_ntop(&packet->sockaddr, packet->socklen, text2,
                                     NGX_SOCKADDR_STRLEN, 1);

            ngx_log_debug3(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "|xquic|ngx_xquic_dispatcher_process_packet: %V -> %V len:%d|",
                           &addr2, &addr, packet->len);
        }
    }
#endif


    ngx_int_t worker_num = ngx_xquic_intercom_packet_hash(packet);

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|packet_get_cid|dcid=%s|targetWorkerId=%i|ngx_worker=%ui|", 
                    xqc_dcid_str(&packet->xquic.dcid), worker_num, ngx_worker);

    if (ngx_worker != (ngx_uint_t) worker_num) {
        ngx_xquic_intercom_send(worker_num, packet);
        return;
    }

    uint64_t recv_time = ngx_xquic_get_time();
    ngx_log_error(NGX_LOG_DEBUG, c->log, 0,
                    "|xquic|xqc_server_read_handler recv_size=%zd, recv_time=%llu|", 
                    packet->len, recv_time);

    if (xqc_engine_packet_process(qmcf->xquic_engine, (u_char *)packet->buf, packet->len,
                                  (struct sockaddr *) &(packet->local_sockaddr), packet->local_socklen,
                                  (struct sockaddr *) &(packet->sockaddr), packet->socklen, 
                                  (xqc_msec_t) recv_time, c) != 0) 
    {
        ngx_log_error(NGX_LOG_DEBUG, c->log, 0,
                    "|xquic|xqc_server_read_handler: packet process err|");
        return;
    }
}


static u_short
ngx_xquic_sockaddr_port(struct sockaddr *sa)
{
    u_short               port;
    struct sockaddr_in   *sin;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6  *sin6;
#endif

    switch (sa->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:
        sin6 = (struct sockaddr_in6 *) sa;
        port = sin6->sin6_port;
        break;
#endif
 
    default: /* AF_INET */
        sin = (struct sockaddr_in *) sa;
        port = sin->sin_port;
        break;
    }

    return port;
}



ngx_int_t
ngx_xquic_cmp_sockaddr(struct sockaddr *sa1, struct sockaddr *sa2)
{
    struct sockaddr_in   *sin1, *sin2;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6  *sin61, *sin62;
#endif

    if (sa1->sa_family != sa2->sa_family) {
        return NGX_DECLINED;
    }    

    switch (sa1->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:
        sin61 = (struct sockaddr_in6 *) sa1;
        sin62 = (struct sockaddr_in6 *) sa2;

        if (sin61->sin6_port != sin62->sin6_port) {
            return NGX_DECLINED;
        }    

        if (ngx_memcmp(&sin61->sin6_addr, &sin62->sin6_addr, 16) != 0) { 
            return NGX_DECLINED;
        }    

        break;
#endif

    default: /* AF_INET */

        sin1 = (struct sockaddr_in *) sa1;
        sin2 = (struct sockaddr_in *) sa2;

        if (sin1->sin_port != sin2->sin_port) {
            return NGX_DECLINED;
        }    

        if (sin1->sin_addr.s_addr != sin2->sin_addr.s_addr) {
            return NGX_DECLINED;
        }    

        break;
    }    

    return NGX_OK;
}




void
ngx_xquic_recv_from_intercom(ngx_xquic_recv_packet_t *packet)
{
    u_char                  text[NGX_SOCKADDR_STRLEN];
    ngx_str_t               addr;
    ngx_uint_t              i;
    ngx_listening_t        *ls;
    ngx_connection_t       *c;

    if (ngx_terminate || ngx_exiting) {
        return;
    }

    ls = (ngx_listening_t *) ngx_cycle->listening.elts;
    for (i = 0; i < ngx_cycle->listening.nelts; i++) {

#if !(T_RELOAD)
#if (NGX_HAVE_REUSEPORT)
        if (ls[i].reuseport && ls[i].worker != ngx_worker) {
            continue;
        }
#endif
#endif

        if (ls[i].fd == -1) {
            continue;
        }

        if (!ls[i].xquic) {
            continue;
        }

        if (ls[i].wildcard) {
            /* listen on *:port  */

            if ((ls[i].sockaddr)->sa_family != packet->local_sockaddr.sa_family) {
                continue;
            }

            if (ngx_xquic_sockaddr_port(ls[i].sockaddr) != ngx_xquic_sockaddr_port(&packet->local_sockaddr)) {
                continue;
            }
        } else {
            if (ngx_xquic_cmp_sockaddr(ls[i].sockaddr, &packet->local_sockaddr) != NGX_OK) {
                continue;
            }
        }

        c = ls[i].connection;

        ngx_xquic_dispatcher_process_packet(c, packet);

        return;
    }

    addr.data = text;
    addr.len = ngx_sock_ntop(&packet->local_sockaddr, packet->local_socklen, text,
                             NGX_SOCKADDR_STRLEN, 1);

    ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                  "|xquic|recv_from_intercom: can't find dispatcher for packet|by address %V|",
                  &addr);
}

#if (T_NGX_UDPV2)

static void
ngx_xquic_udpv2_dispatch_packet(xqc_engine_t *engine, const ngx_udpv2_packet_t *upkt, void *user_data)
{
    uint64_t recv_time;
    recv_time = upkt->pkt_micrs ? upkt->pkt_micrs : ngx_xquic_get_time();

    if (xqc_engine_packet_process(engine, (u_char *)upkt->pkt_payload, upkt->pkt_sz,
                                  (struct sockaddr *) &(upkt->pkt_local_sockaddr), upkt->pkt_local_socklen,
                                  (struct sockaddr *) &(upkt->pkt_sockaddr), upkt->pkt_socklen,
                                  (xqc_msec_t) recv_time, user_data) != 0)
    {
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|xqc_server_read_handler: packet process err|");
        return;
    }
}

void
ngx_xquic_dispatcher_process(ngx_connection_t *c, const ngx_udpv2_packet_t *upkt)
{

    ngx_http_xquic_main_conf_t  *qmcf;

    if (ngx_terminate || ngx_exiting) {
        return;
    }

    if (c->data == NULL) {
        ngx_log_error(NGX_LOG_WARN, c->log, 0,
                      "|xquic|ngx_xquic_dispatcher_process_packet: engine NULL|");
        return;
    }

    qmcf = (ngx_http_xquic_main_conf_t *)(c->data);

    /* check QUIC magic bit */
    if (!NGX_XQUIC_CHECK_MAGIC_BIT(upkt->pkt_payload)) {
        ngx_log_error(NGX_LOG_WARN, c->log, 0,
                      "|xquic|invalid packet head|");
        return;
    }

    /* check healthcheck */
    if (upkt->pkt_sz >= sizeof(NGX_XQUIC_HEALTH_CHECK)
        && ngx_strncmp(upkt->pkt_payload, NGX_XQUIC_HEALTH_CHECK, sizeof(NGX_XQUIC_HEALTH_CHECK)-1) == 0)
    {
        ngx_log_debug(NGX_LOG_DEBUG, c->log, 0,
                      "|xquic|health check|");
        return;
    }

    /* check healthcheck, REQ/RSP mode */
    if (upkt->pkt_sz == sizeof(NGX_XQUIC_HEALTH_CHECK_REQ)-1
        && ngx_strncmp(upkt->pkt_payload, NGX_XQUIC_HEALTH_CHECK_REQ, sizeof(NGX_XQUIC_HEALTH_CHECK_REQ)-1) == 0)
    {
        ngx_log_debug(NGX_LOG_DEBUG, c->log, 0,
                      "|xquic|health check, req/rsp mode|");
        sendto(c->fd, NGX_XQUIC_HEALTH_CHECK_RSP, sizeof(NGX_XQUIC_HEALTH_CHECK_RSP)-1, 0, &(upkt->pkt_sockaddr.sockaddr), upkt->pkt_socklen);
        return;
    }

#if (NGX_DEBUG)
    {
        ngx_str_t  addr, addr2;
        u_char     text[NGX_SOCKADDR_STRLEN], text2[NGX_SOCKADDR_STRLEN];
        if (c->log->log_level & NGX_LOG_DEBUG_EVENT) {
            addr.data = text;
            addr.len = ngx_sock_ntop((struct sockaddr *) &(upkt->pkt_local_sockaddr), upkt->pkt_local_socklen, text,
                                     NGX_SOCKADDR_STRLEN, 1);
            addr2.data = text2;
            addr2.len = ngx_sock_ntop((struct sockaddr *) &(upkt->pkt_sockaddr), upkt->pkt_socklen, text2,
                                     NGX_SOCKADDR_STRLEN, 1);

            ngx_log_debug3(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "|xquic|ngx_xquic_dispatcher_process: %V -> %V len:%d|",
                           &addr2, &addr, upkt->pkt_sz);
        }
    }
#endif

    ngx_xquic_udpv2_dispatch_packet(qmcf->xquic_engine, upkt, c);
}
#endif