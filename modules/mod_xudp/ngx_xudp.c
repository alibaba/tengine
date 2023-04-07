/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_xudp.h>
#include <ngx_xudp_internal.h>
#include <netinet/in.h>

xudp         *ngx_xudp_engine  = NULL;
xudp_conf    ngx_xudp_conf     = {0};

#if (T_NGX_XQUIC)
struct kern_xquic ngx_xudp_xquic_kern_cid_route_info = {0};
#endif

ngx_listening_t *
ngx_xudp_get_tx(void) {
    return ngx_cycle->xudp_ctx ? ngx_cycle->xudp_ctx->tx : NULL;
}

ssize_t
ngx_xudp_sendmmsg(ngx_connection_t *c ,struct iovec *msg_iov, unsigned int vlen,
                  const struct sockaddr *peer_addr, socklen_t peer_addrlen, int push)
{
    ngx_listening_t    *tx;
    ngx_connection_t   *tx_c;
    ngx_xudp_channel_t *xudp_ch;
    struct xudp_addr    xaddr;
    ngx_event_t        *wev;
    unsigned int        packet_count;
    int err, xudp_flags;

    tx = ngx_xudp_get_tx();
    /* xudp off */
    if (tx == NULL) {
        /* force sendmmsg degrade */
        return NGX_DECLINED;
    }

    tx_c    = tx->connection;
    wev     = tx_c->write;
    xudp_ch = tx->ngx_xudp_ch;

    memcpy(&xaddr.to, peer_addr, peer_addrlen);
    memcpy(&xaddr.from, c->local_sockaddr, c->local_socklen);

    xudp_flags = XUDP_FLAG_SRC_PORT | XUDP_FLAG_SRC_IP;

    if (c->local_sockaddr->sa_family == AF_INET) {
        struct sockaddr_in *v4 = (struct sockaddr_in*) (c->local_sockaddr);
        if (v4->sin_addr.s_addr == INADDR_ANY) {
            xudp_flags &= (~XUDP_FLAG_SRC_IP);
        }
    }else if (c->local_sockaddr->sa_family == AF_INET6){
        struct sockaddr_in6 *v6 = (struct sockaddr_in6*) (c->local_sockaddr);
        if (IN6_IS_ADDR_UNSPECIFIED(&v6->sin6_addr)) {
            xudp_flags &= (~XUDP_FLAG_SRC_IP);
        }
    }

    /**
     * xudp send data:
     * 1. move the send buffer to xudp_send_channel
     * if the threshold (100) of buffer is reached, buffer will be flush to NIC immediately
     * 2. flush data to NIC via xudp_commit_channel actively
    * */
    for(packet_count = 0; packet_count < vlen; packet_count++) {
        err = xudp_send_channel(xudp_ch->ch, msg_iov->iov_base, msg_iov->iov_len, (struct sockaddr *) &xaddr, xudp_flags);
        msg_iov++;
        if (err < 0) {
            if (ngx_xudp_error_is_fatal(err)) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "|xudp|nginx|xudp_send_channel failed [%d]", err);
                return err;
            }
            break;
        }
    }

    if (packet_count < vlen) {
        wev->ready = 0;
    }

    if (packet_count > 0) {
        if (!push) {
            ngx_post_event(&(xudp_ch->commit), &ngx_posted_commit);
        }else {
            /* flush data to NIC actively */
            err = xudp_commit_channel(xudp_ch->ch);
            if (err < 0 && ngx_xudp_error_is_fatal(err)) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "|xudp|nginx|xudp_commit_channel failed [err:%d]", err);
                return err;
            }
        }
    }

    return packet_count;
}