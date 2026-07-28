/*
 * Copyright (C) 2020-2026 Alibaba Group Holding Limited
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
                    size, ngx_xquic_get_time(), xqc_dcid_str(qc->engine, &qc->dcid));
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

/*
 * ngx_xquic_send_packet_early sends a packet via the listen connection.
 * Typically called when ngx_http_xquic_connection_t has not yet been created
 * or cannot be used, e.g. when sending a retry packet.
 */
ssize_t
ngx_xquic_send_packet_early(const unsigned char *buf, size_t size,
    const struct sockaddr *peer_addr, socklen_t peer_addrlen, void *user_data)
{
    ssize_t res = 0;
    if (user_data == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "|xquic|ngx_xquic_send_packet_early failed|");
        return XQC_ERROR;
    }
    ngx_connection_t *c = user_data;
    ngx_socket_t fd = c->fd;
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_send_packet_early size=%z now=%i", 
                    size, ngx_xquic_get_time());
    do {
        errno = 0;
        res = sendto(fd, buf, size, 0, peer_addr, peer_addrlen);

        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                      "|xquic|ngx_xquic_send_packet_early write %zd, %s|",
                      res, strerror(errno));
        if ((res < 0) && (errno == EAGAIN)) {
            break;
        }

    } while ((res < 0) && (errno == EINTR));

    if (res < 0) { /* EAGAIN also counts as failure: data cannot be cached and resent later */
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_send_packet_early|socket err|res:%z|errno:%s",
                    res, strerror(errno));
        return XQC_SOCKET_ERROR;
    }

    return res;
}


ssize_t
ngx_xquic_stateless_reset(const unsigned char *buf, size_t size,
    const struct sockaddr *peer_addr, socklen_t peer_addrlen,
    const struct sockaddr *local_addr, socklen_t local_addrlen,
    void *user_data)
{
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                  "|xquic|ngx_xquic_stateless_reset|%p|%z|", buf, size);

    /* get ngx_connection_t, the user_data is the user_data from
       xqc_engine_packet_process */

    return ngx_xquic_send_packet_early((unsigned char *)buf, size, peer_addr, peer_addrlen, user_data);
}

ssize_t 
ngx_xquic_server_mp_send(uint64_t path_id, 
    const unsigned char *buf, size_t size,
    const struct sockaddr *peer_addr, socklen_t peer_addrlen,
    void *conn_user_data)
{
    ngx_xquic_list_node_t       *node = NULL;
    ngx_uint_t                   index = 0;
    ngx_xquic_path_t            *path = NULL;
    ngx_socket_t                 fd = (ngx_socket_t)-1;

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                  "|xquic|ngx_xquic_server_mp_send|%p|%z|", buf, size);

    /* while sending reset, user_data may be empty */
    ngx_http_xquic_connection_t *qc = (ngx_http_xquic_connection_t *)conn_user_data; 
    if (qc == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                      "|xquic|ngx_xquic_server_mp_send|user_conn=NULL|");
        return XQC_SOCKET_ERROR;
    }

    if (path_id == XQC_INITIAL_PATH_ID) {

        fd = qc->connection->fd;

    } else {

        /* find path */
        index = path_id & NGX_XQUIC_MP_PATH_INDEX;
        for (node = qc->path_index[index]; node != NULL; node = node->next) {
        
            path = node->entry;
        
            if (path != NULL 
                && path->path_id == path_id
                && path->path_state == NGX_XQUIC_PATH_STATE_AVAILABLE) 
            {        
                fd = path->c->fd;
                break;
            }
        }
    }

    if (fd == (ngx_socket_t)-1) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_server_mp_send|can't get fd|%ui|", path_id);   

        return XQC_SOCKET_ERROR;
    }

    ssize_t res = 0;
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_server_mp_send|size=%z now=%i|dcid=%s|fd=%d|", 
                    size, ngx_xquic_get_time(), xqc_dcid_str(qc->engine, &qc->dcid), fd);
    do {
        errno = 0;
        res = sendto(fd, buf, size, 0, peer_addr, peer_addrlen);
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                        "|xquic|ngx_xquic_server_mp_send|write %zd, %s|", res, strerror(errno));

        if ((res < 0) && (errno == EAGAIN)) {
            break;
        }

    } while ((res < 0) && (errno == EINTR));

    if ((res < 0) && (errno == EAGAIN)) {
        return ngx_http_xquic_on_write_block(qc, qc->connection->write);

    } else if (res < 0) {

        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_server_mp_send|socket err|");          
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
                    vlen, ngx_xquic_get_time(), xqc_dcid_str(qc->engine, &qc->dcid));

    wev = qc->connection->write;

#if (T_NGX_UDPV2)
#if (T_NGX_HAVE_XUDP)
    if (ngx_xudp_is_tx_enable(qc->connection)) {
        res = ngx_xudp_sendmmsg(qc->connection, (struct iovec *) msg_iov, vlen, peer_addr, peer_addrlen, /**push*/ 1);
        if (res == vlen) {
            return res;
        }else if(res < vlen) {
            if (res <= 0) {
                //if (ngx_xudp_error_is_fatal(res)) {
                /* Always degrade on any xudp send error to avoid xudp bugs affecting packet delivery */
                ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                              "|xquic|ngx_xquic_server_send_mmsg|xudp degrade|dcid=%s|",
                              xqc_dcid_str(qc->engine, &qc->dcid));
                goto degrade;
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

    for (i = 0 ; i < vlen; i++) {
        msg[i].msg_hdr.msg_name = (void *)peer_addr;
        msg[i].msg_hdr.msg_namelen = peer_addrlen;
        msg[i].msg_hdr.msg_iov = (struct iovec *) msg_iov + i;
        msg[i].msg_hdr.msg_iovlen = 1;
    }

    res = sendmmsg(fd, msg, vlen, 0);

    if (res < 0 && (errno == EAGAIN)) {
        return ngx_http_xquic_on_write_block(qc, wev);
    } else if (res < 0) {

        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                      "|xquic|ngx_xquic_server_send_mmsg err|total_len=%z now=%i|dcid=%s|send_len=%z|errno=%s|",
                      vlen, ngx_xquic_get_time(), xqc_dcid_str(qc->engine, &qc->dcid), res, strerror(errno));
        return XQC_SOCKET_ERROR;
    }

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
            "|xquic|ngx_xquic_server_send_mmsg success|total_len=%z now=%i|dcid=%s|send_len=%z|",
            vlen, ngx_xquic_get_time(), xqc_dcid_str(qc->engine, &qc->dcid), res);


    return res;
}


ssize_t 
ngx_xquic_server_mp_send_mmsg(uint64_t path_id, 
    const struct iovec *msg_iov, unsigned int vlen,
    const struct sockaddr *peer_addr, socklen_t peer_addrlen,
    void *conn_user_data)
{
    ngx_event_t               *wev;
    ssize_t                    res = 0;
    unsigned int               i = 0;

    ngx_xquic_list_node_t     *node = NULL;
    ngx_uint_t                 index = 0;
    ngx_xquic_path_t          *path = NULL;
    ngx_socket_t               fd = (ngx_socket_t)-1;
    ngx_connection_t          *ngx_conn = NULL;
    xqc_cid_t                 *cid;
    u_char                     text[NGX_SOCKADDR_STRLEN];
    ngx_str_t                  addr_text;

    struct mmsghdr             msg[NGX_XQUIC_MAX_SEND_MSG_ONCE];

    memset(msg, 0, sizeof(msg));

    ngx_http_xquic_connection_t *qc = (ngx_http_xquic_connection_t *)conn_user_data;

    if (qc == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                                    "|xquic|ngx_xquic_server_mp_send_mmsg|user_conn=NULL|");
        return (ssize_t)NGX_ERROR;
    }

    if (path_id == XQC_INITIAL_PATH_ID) {

        fd = qc->connection->fd;
        ngx_conn = qc->connection;
        cid = &qc->dcid;

    } else {

        /* find path */
        index = path_id & NGX_XQUIC_MP_PATH_INDEX;
        for (node = qc->path_index[index]; node != NULL; node = node->next) {
        
            path = node->entry;
        
            if (path != NULL 
                && path->path_id == path_id
                && path->path_state == NGX_XQUIC_PATH_STATE_AVAILABLE) 
            {        
                fd = path->c->fd;
                ngx_conn = path->c;
                cid = &path->scid;
                break;
            }
        }
    }

    if (fd == (ngx_socket_t)-1 || ngx_conn == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_server_mp_send_mmsg|can't get fd|%uL|", path_id);   

        return XQC_SOCKET_ERROR;
    }

    addr_text.data = text;
    addr_text.len = ngx_sock_ntop((struct sockaddr *)peer_addr, peer_addrlen,
                             text, NGX_SOCKADDR_STRLEN, 1);

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|ngx_xquic_server_mp_send_mmsg|vlen=%z now=%i|dcid=%s|path=%uL|addr=%V|",
                    vlen, ngx_xquic_get_time(), xqc_dcid_str(qc->engine, cid), path_id, &addr_text);

    wev = ngx_conn->write;

#if (T_NGX_UDPV2)
#if (T_NGX_HAVE_XUDP)
    if (ngx_xudp_is_tx_enable(ngx_conn)) {
        res = ngx_xudp_sendmmsg(ngx_conn, msg_iov, vlen, peer_addr, peer_addrlen, /**push*/ 1);
        if (res == vlen) {
            return res;
        }else if(res < vlen) {
            if (res <= 0) {
                //if (ngx_xudp_error_is_fatal(res)) {
                /* Always degrade on any xudp send error to avoid xudp bugs affecting packet delivery */
                ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                              "|xquic|ngx_xquic_server_mp_send_mmsg|xudp degrade|dcid=%s|path=%uL|addr=%V|",
                              xqc_dcid_str(qc->engine, cid), path_id, &addr_text);
                goto degrade;
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
        ngx_xudp_disable_tx(ngx_conn);
        if (wev->posted) {
            ngx_delete_posted_event(wev);
        }
    }
#endif
#endif

    for(i = 0 ; i < vlen; i++){
        msg[i].msg_hdr.msg_name = (void *)peer_addr;
        msg[i].msg_hdr.msg_namelen = peer_addrlen;
        msg[i].msg_hdr.msg_iov = (struct iovec *)(msg_iov + i);
        msg[i].msg_hdr.msg_iovlen = 1;
    }

    res = sendmmsg(fd, msg, vlen, 0);

    if (res < 0 && (errno == EAGAIN)) {
        return ngx_http_xquic_on_write_block(qc, wev);

    } else if (res < 0) {

        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
            "|xquic|ngx_xquic_server_mp_send_mmsg|err|total_len=%z now=%i|dcid=%s|send_len=%z|errno:%d, %s|",
            vlen, ngx_xquic_get_time(), xqc_dcid_str(qc->engine, &qc->dcid), res, errno, strerror(errno));
        return XQC_SOCKET_ERROR;
    }

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
            "|xquic|ngx_xquic_server_mp_send_mmsg|success|total_len=%z now=%i|dcid=%s|send_len=%z|",
            vlen, ngx_xquic_get_time(), xqc_dcid_str(qc->engine, &qc->dcid), res);


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
