/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_xquic_send.h>
#include <ngx_http_xquic_module.h>
#include <ngx_http_v3_stream.h>
#include <xquic/xquic.h>

#if (T_NGX_HAVE_XUDP)
#include <ngx_xudp.h>
#endif

#define NGX_XQUIC_MAX_SEND_MSG_ONCE  XQC_MAX_SEND_MSG_ONCE

static ssize_t ngx_http_xquic_on_write_block(ngx_http_xquic_connection_t *qc, ngx_event_t *wev);

void
ngx_http_xquic_write_handler(ngx_event_t *wev)
{
    ngx_int_t                     rc;
    ngx_connection_t             *c;
    ngx_http_xquic_connection_t  *qc;

    c = wev->data;
    qc = c->data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "|xquic|ngx_http_xquic_write_handler|");

    // del write event
    ngx_del_event(wev, NGX_WRITE_EVENT, 0);

    if (wev->timedout) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "http3 write event timed out");
        c->error = 1;
        ngx_http_v3_connection_error(qc, NGX_XQUIC_CONN_WRITE_ERR, "write event timed out");
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "xquic write handler");

    qc->blocked = 1;

    rc = xqc_conn_continue_send(qc->engine, &qc->dcid);

    if (rc < 0) {

        ngx_log_error(NGX_LOG_WARN, c->log, 0, "|xquic|write handler continue send|rc=%i|", rc);

        c->error = 1;
        ngx_http_v3_connection_error(qc, NGX_XQUIC_CONN_WRITE_ERR, 
                                    "xqc_conn_continue_send err");
        return;
    }

    qc->blocked = 0;

    //ngx_http_v3_handle_connection(qc);
}

ssize_t 
ngx_xquic_server_send(const unsigned char *buf, size_t size,
    const struct sockaddr *peer_addr, socklen_t peer_addrlen, void *user_data)
{

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                                    "|xquic|ngx_xquic_server_send|%p|%z|", buf, size);

    /* while sending reset, user_data may be empty */
    ngx_http_xquic_connection_t *qc = (ngx_http_xquic_connection_t *)user_data; 
    if (qc == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                                    "|xquic|ngx_xquic_server_send|user_conn=NULL|");
        return XQC_SOCKET_ERROR;
    }

    ssize_t res = 0;
    ngx_socket_t fd = qc->connection->fd;
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|xqc_server_send size=%z now=%i|dcid=%s|", 
                    size, ngx_xquic_get_time(), xqc_dcid_str(&qc->dcid));
    do {
        errno = 0;
        res = sendto(fd, buf, size, 0, peer_addr, peer_addrlen);
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                        "|xquic|xqc_server_send write %zd, %s|", res, strerror(errno));

        if ((res < 0) && (errno == EAGAIN)) {
            break;
        }

    } while ((res < 0) && (errno == EINTR));

    if ((res < 0) && (errno == EAGAIN)) {
        return ngx_http_xquic_on_write_block(qc, qc->connection->write);
    } else if (res < 0) {

        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_server_send|socket err|");          
        return XQC_SOCKET_ERROR;
    }

    return res;
}


#if defined(T_NGX_XQUIC_SUPPORT_SENDMMSG)
ssize_t 
ngx_xquic_server_send_mmsg(const struct iovec *msg_iov, unsigned int vlen,
    const struct sockaddr *peer_addr, socklen_t peer_addrlen, void *user_data)
{
    ngx_event_t               *wev;
    ssize_t                    res = 0;
    unsigned int               i = 0;

    struct mmsghdr             msg[NGX_XQUIC_MAX_SEND_MSG_ONCE];

    memset(msg, 0, sizeof(msg));

    ngx_http_xquic_connection_t *qc = (ngx_http_xquic_connection_t *)user_data;

    if (qc == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                                    "|xquic|ngx_xquic_server_send_mmsg|user_conn=NULL|");
        return (ssize_t)NGX_ERROR;
    }

    ngx_socket_t fd = qc->connection->fd;
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_server_send_mmsg|vlen=%z now=%i|dcid=%s|",
                    vlen, ngx_xquic_get_time(), xqc_dcid_str(&qc->dcid));

    wev = qc->connection->write;

#if (T_NGX_UDPV2)
#if (T_NGX_HAVE_XUDP)
    if (ngx_xudp_is_tx_enable(qc->connection)) {
        res = ngx_xudp_sendmmsg(qc->connection, (struct iovec *) msg_iov, vlen, peer_addr, peer_addrlen, /**push*/ 1);
        if (res == vlen) {
            return res;
        }else if(res < vlen) {
            if (res < 0) {
                if (ngx_xudp_error_is_fatal(res)) {
                    goto degrade;
                }
                /* reset res to 0 */
                res = 0;
            }
            ngx_queue_t *q = ngx_udpv2_active_writable_queue(ngx_xudp_get_tx());
            if (q != NULL) {
                ngx_post_event(wev, q);
                return res;
            }
        }
        /* degrade to system */
degrade:
        ngx_xudp_disable_tx(qc->connection);
        if (wev->posted) {
            ngx_delete_posted_event(wev);
        }
    }
#endif
#endif

    for(i = 0 ; i < vlen; i++){
        msg[i].msg_hdr.msg_iov = (struct iovec *) msg_iov + i;
        msg[i].msg_hdr.msg_iovlen = 1;
    }

    res = sendmmsg(fd, msg, vlen, 0);

    if (res < 0 && (errno == EAGAIN)) {
        return ngx_http_xquic_on_write_block(qc, wev);
    } else if (res < 0) {

        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
            "|xquic|ngx_xquic_server_send_mmsg err|total_len=%z now=%i|dcid=%s|send_len=%z|errno=%s|",
            vlen, ngx_xquic_get_time(), xqc_dcid_str(&qc->dcid), res, strerror(errno));
        return XQC_SOCKET_ERROR;
    }

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
            "|xquic|ngx_xquic_server_send_mmsg success|total_len=%z now=%i|dcid=%s|send_len=%z|",
            vlen, ngx_xquic_get_time(), xqc_dcid_str(&qc->dcid), res);


    return res;
}
#endif


static ngx_inline ssize_t
ngx_http_xquic_on_write_block(ngx_http_xquic_connection_t *qc, ngx_event_t *wev)
{
    ngx_http_core_loc_conf_t    *clcf;

    clcf    = ngx_http_get_module_loc_conf(qc->http_connection->conf_ctx,
                                        ngx_http_core_module);

    wev->ready = 0;

    if (ngx_handle_write_event(wev, clcf->send_lowat) != NGX_OK) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
            "|xquic|ngx_handle_write_event err|");
        return XQC_SOCKET_ERROR;
    }
    return XQC_SOCKET_EAGAIN;
}
