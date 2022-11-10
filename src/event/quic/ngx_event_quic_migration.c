
/*
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_event_quic_connection.h>


static void ngx_quic_set_connection_path(ngx_connection_t *c,
    ngx_quic_path_t *path);
static ngx_int_t ngx_quic_validate_path(ngx_connection_t *c,
    ngx_quic_path_t *path);
static ngx_int_t ngx_quic_send_path_challenge(ngx_connection_t *c,
    ngx_quic_path_t *path);
static ngx_quic_path_t *ngx_quic_get_path(ngx_connection_t *c, ngx_uint_t tag);


ngx_int_t
ngx_quic_handle_path_challenge_frame(ngx_connection_t *c,
    ngx_quic_header_t *pkt, ngx_quic_path_challenge_frame_t *f)
{
    ngx_quic_frame_t        frame, *fp;
    ngx_quic_connection_t  *qc;

    qc = ngx_quic_get_connection(c);

    ngx_memzero(&frame, sizeof(ngx_quic_frame_t));

    frame.level = ssl_encryption_application;
    frame.type = NGX_QUIC_FT_PATH_RESPONSE;
    frame.u.path_response = *f;

    /*
     * RFC 9000, 8.2.2.  Path Validation Responses
     *
     * A PATH_RESPONSE frame MUST be sent on the network path where the
     * PATH_CHALLENGE frame was received.
     */

    /*
     * An endpoint MUST expand datagrams that contain a PATH_RESPONSE frame
     * to at least the smallest allowed maximum datagram size of 1200 bytes.
     */
    if (ngx_quic_frame_sendto(c, &frame, 1200, pkt->path) != NGX_OK) {
        return NGX_ERROR;
    }

    if (pkt->path == qc->path) {
        /*
         * RFC 9000, 9.3.3.  Off-Path Packet Forwarding
         *
         * An endpoint that receives a PATH_CHALLENGE on an active path SHOULD
         * send a non-probing packet in response.
         */

        fp = ngx_quic_alloc_frame(c);
        if (fp == NULL) {
            return NGX_ERROR;
        }

        fp->level = ssl_encryption_application;
        fp->type = NGX_QUIC_FT_PING;

        ngx_quic_queue_frame(qc, fp);
    }

    return NGX_OK;
}


ngx_int_t
ngx_quic_handle_path_response_frame(ngx_connection_t *c,
    ngx_quic_path_challenge_frame_t *f)
{
    ngx_uint_t              rst;
    ngx_queue_t            *q;
    ngx_quic_path_t        *path, *prev;
    ngx_quic_connection_t  *qc;

    qc = ngx_quic_get_connection(c);

    /*
     * RFC 9000, 8.2.3.  Successful Path Validation
     *
     * A PATH_RESPONSE frame received on any network path validates the path
     * on which the PATH_CHALLENGE was sent.
     */

    for (q = ngx_queue_head(&qc->paths);
         q != ngx_queue_sentinel(&qc->paths);
         q = ngx_queue_next(q))
    {
        path = ngx_queue_data(q, ngx_quic_path_t, queue);

        if (!path->validating) {
            continue;
        }

        if (ngx_memcmp(path->challenge1, f->data, sizeof(f->data)) == 0
            || ngx_memcmp(path->challenge2, f->data, sizeof(f->data)) == 0)
        {
            goto valid;
        }
    }

    ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, 0,
                   "quic stale PATH_RESPONSE ignored");

    return NGX_OK;

valid:

    /*
     * RFC 9000, 9.4.  Loss Detection and Congestion Control
     *
     * On confirming a peer's ownership of its new address,
     * an endpoint MUST immediately reset the congestion controller
     * and round-trip time estimator for the new path to initial values
     * unless the only change in the peer's address is its port number.
     */

    rst = 1;

    prev = ngx_quic_get_path(c, NGX_QUIC_PATH_BACKUP);

    if (prev != NULL) {

        if (ngx_cmp_sockaddr(prev->sockaddr, prev->socklen,
                             path->sockaddr, path->socklen, 0)
            == NGX_OK)
        {
            /* address did not change */
            rst = 0;
        }
    }

    if (rst) {
        ngx_memzero(&qc->congestion, sizeof(ngx_quic_congestion_t));

        qc->congestion.window = ngx_min(10 * qc->tp.max_udp_payload_size,
                                   ngx_max(2 * qc->tp.max_udp_payload_size,
                                           14720));
        qc->congestion.ssthresh = (size_t) -1;
        qc->congestion.recovery_start = ngx_current_msec;
    }

    /*
     * RFC 9000, 9.3.  Responding to Connection Migration
     *
     *  After verifying a new client address, the server SHOULD
     *  send new address validation tokens (Section 8) to the client.
     */

    if (ngx_quic_send_new_token(c, path) != NGX_OK) {
        return NGX_ERROR;
    }

    ngx_log_error(NGX_LOG_INFO, c->log, 0,
                  "quic path seq:%uL addr:%V successfully validated",
                  path->seqnum, &path->addr_text);

    ngx_quic_path_dbg(c, "is validated", path);

    path->validated = 1;
    path->validating = 0;
    path->limited = 0;

    return NGX_OK;
}


ngx_quic_path_t *
ngx_quic_new_path(ngx_connection_t *c,
    struct sockaddr *sockaddr, socklen_t socklen, ngx_quic_client_id_t *cid)
{
    ngx_queue_t            *q;
    ngx_quic_path_t        *path;
    ngx_quic_connection_t  *qc;

    qc = ngx_quic_get_connection(c);

    if (!ngx_queue_empty(&qc->free_paths)) {

        q = ngx_queue_head(&qc->free_paths);
        path = ngx_queue_data(q, ngx_quic_path_t, queue);

        ngx_queue_remove(&path->queue);

        ngx_memzero(path, sizeof(ngx_quic_path_t));

    } else {

        path = ngx_pcalloc(c->pool, sizeof(ngx_quic_path_t));
        if (path == NULL) {
            return NULL;
        }
    }

    ngx_queue_insert_tail(&qc->paths, &path->queue);

    path->cid = cid;
    cid->used = 1;

    path->limited = 1;

    path->seqnum = qc->path_seqnum++;

    path->sockaddr = &path->sa.sockaddr;
    path->socklen = socklen;
    ngx_memcpy(path->sockaddr, sockaddr, socklen);

    path->addr_text.data = path->text;
    path->addr_text.len = ngx_sock_ntop(sockaddr, socklen, path->text,
                                        NGX_SOCKADDR_STRLEN, 1);

    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, c->log, 0,
                   "quic path seq:%uL created addr:%V",
                   path->seqnum, &path->addr_text);
    return path;
}


static ngx_quic_path_t *
ngx_quic_get_path(ngx_connection_t *c, ngx_uint_t tag)
{
    ngx_queue_t            *q;
    ngx_quic_path_t        *path;
    ngx_quic_connection_t  *qc;

    qc = ngx_quic_get_connection(c);

    for (q = ngx_queue_head(&qc->paths);
         q != ngx_queue_sentinel(&qc->paths);
         q = ngx_queue_next(q))
    {
        path = ngx_queue_data(q, ngx_quic_path_t, queue);

        if (path->tag == tag) {
            return path;
        }
    }

    return NULL;
}


ngx_int_t
ngx_quic_set_path(ngx_connection_t *c, ngx_quic_header_t *pkt)
{
    off_t                   len;
    ngx_queue_t            *q;
    ngx_quic_path_t        *path, *probe;
    ngx_quic_socket_t      *qsock;
    ngx_quic_send_ctx_t    *ctx;
    ngx_quic_client_id_t   *cid;
    ngx_quic_connection_t  *qc;

    qc = ngx_quic_get_connection(c);
    qsock = ngx_quic_get_socket(c);

    len = pkt->raw->last - pkt->raw->start;

    if (c->udp->buffer == NULL) {
        /* first ever packet in connection, path already exists  */
        path = qc->path;
        goto update;
    }

    probe = NULL;

    for (q = ngx_queue_head(&qc->paths);
         q != ngx_queue_sentinel(&qc->paths);
         q = ngx_queue_next(q))
    {
        path = ngx_queue_data(q, ngx_quic_path_t, queue);

        if (ngx_cmp_sockaddr(&qsock->sockaddr.sockaddr, qsock->socklen,
                             path->sockaddr, path->socklen, 1)
            == NGX_OK)
        {
            goto update;
        }

        if (path->tag == NGX_QUIC_PATH_PROBE) {
            probe = path;
        }
    }

    /* packet from new path, drop current probe, if any */

    ctx = ngx_quic_get_send_ctx(qc, pkt->level);

    /*
     * only accept highest-numbered packets to prevent connection id
     * exhaustion by excessive probing packets from unknown paths
     */
    if (pkt->pn != ctx->largest_pn) {
        return NGX_DONE;
    }

    if (probe && ngx_quic_free_path(c, probe) != NGX_OK) {
        return NGX_ERROR;
    }

    /* new path requires new client id */
    cid = ngx_quic_next_client_id(c);
    if (cid == NULL) {
        ngx_log_error(NGX_LOG_INFO, c->log, 0,
                      "quic no available client ids for new path");
        /* stop processing of this datagram */
        return NGX_DONE;
    }

    path = ngx_quic_new_path(c, &qsock->sockaddr.sockaddr, qsock->socklen, cid);
    if (path == NULL) {
        return NGX_ERROR;
    }

    path->tag = NGX_QUIC_PATH_PROBE;

    /*
     * client arrived using new path and previously seen DCID,
     * this indicates NAT rebinding (or bad client)
     */
    if (qsock->used) {
        pkt->rebound = 1;
    }

update:

    qsock->used = 1;
    pkt->path = path;

    /* TODO: this may be too late in some cases;
     *       for example, if error happens during decrypt(), we cannot
     *       send CC, if error happens in 1st packet, due to amplification
     *       limit, because path->received = 0
     *
     *       should we account garbage as received or only decrypting packets?
     */
    path->received += len;

    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, c->log, 0,
                   "quic packet len:%O via sock seq:%L path seq:%uL",
                   len, (int64_t) qsock->sid.seqnum, path->seqnum);
    ngx_quic_path_dbg(c, "status", path);

    return NGX_OK;
}


ngx_int_t
ngx_quic_free_path(ngx_connection_t *c, ngx_quic_path_t *path)
{
    ngx_quic_connection_t  *qc;

    qc = ngx_quic_get_connection(c);

    ngx_queue_remove(&path->queue);
    ngx_queue_insert_head(&qc->free_paths, &path->queue);

    /*
     * invalidate CID that is no longer usable for any other path;
     * this also requests new CIDs from client
     */
    if (path->cid) {
        if (ngx_quic_free_client_id(c, path->cid) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, c->log, 0,
                   "quic path seq:%uL addr:%V retired",
                   path->seqnum, &path->addr_text);

    return NGX_OK;
}


static void
ngx_quic_set_connection_path(ngx_connection_t *c, ngx_quic_path_t *path)
{
    size_t  len;

    ngx_memcpy(c->sockaddr, path->sockaddr, path->socklen);
    c->socklen = path->socklen;

    if (c->addr_text.data) {
        len = ngx_min(c->addr_text.len, path->addr_text.len);

        ngx_memcpy(c->addr_text.data, path->addr_text.data, len);
        c->addr_text.len = len;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, c->log, 0,
                   "quic send path set to seq:%uL addr:%V",
                   path->seqnum, &path->addr_text);
}


ngx_int_t
ngx_quic_handle_migration(ngx_connection_t *c, ngx_quic_header_t *pkt)
{
    ngx_quic_path_t        *next, *bkp;
    ngx_quic_send_ctx_t    *ctx;
    ngx_quic_connection_t  *qc;

    /* got non-probing packet via non-active path */

    qc = ngx_quic_get_connection(c);

    ctx = ngx_quic_get_send_ctx(qc, pkt->level);

    /*
     * RFC 9000, 9.3.  Responding to Connection Migration
     *
     * An endpoint only changes the address to which it sends packets in
     * response to the highest-numbered non-probing packet.
     */
    if (pkt->pn != ctx->largest_pn) {
        return NGX_OK;
    }

    next = pkt->path;

    /*
     * RFC 9000, 9.3.3:
     *
     * In response to an apparent migration, endpoints MUST validate the
     * previously active path using a PATH_CHALLENGE frame.
     */
    if (pkt->rebound) {

        /* NAT rebinding: client uses new path with old SID */
        if (ngx_quic_validate_path(c, qc->path) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    if (qc->path->validated) {

        if (next->tag != NGX_QUIC_PATH_BACKUP) {
            /* can delete backup path, if any */
            bkp = ngx_quic_get_path(c, NGX_QUIC_PATH_BACKUP);

            if (bkp && ngx_quic_free_path(c, bkp) != NGX_OK) {
                return NGX_ERROR;
            }
        }

        qc->path->tag = NGX_QUIC_PATH_BACKUP;
        ngx_quic_path_dbg(c, "is now backup", qc->path);

    } else {
        if (ngx_quic_free_path(c, qc->path) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    /* switch active path to migrated */
    qc->path = next;
    qc->path->tag = NGX_QUIC_PATH_ACTIVE;

    ngx_quic_set_connection_path(c, next);

    if (!next->validated && !next->validating) {
        if (ngx_quic_validate_path(c, next) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    ngx_log_error(NGX_LOG_INFO, c->log, 0,
                  "quic migrated to path seq:%uL addr:%V",
                  qc->path->seqnum, &qc->path->addr_text);

    ngx_quic_path_dbg(c, "is now active", qc->path);

    return NGX_OK;
}


static ngx_int_t
ngx_quic_validate_path(ngx_connection_t *c, ngx_quic_path_t *path)
{
    ngx_msec_t              pto;
    ngx_quic_send_ctx_t    *ctx;
    ngx_quic_connection_t  *qc;

    qc = ngx_quic_get_connection(c);

    ngx_log_debug1(NGX_LOG_DEBUG_EVENT, c->log, 0,
                   "quic initiated validation of path seq:%uL", path->seqnum);

    path->validating = 1;

    if (RAND_bytes(path->challenge1, 8) != 1) {
        return NGX_ERROR;
    }

    if (RAND_bytes(path->challenge2, 8) != 1) {
        return NGX_ERROR;
    }

    if (ngx_quic_send_path_challenge(c, path) != NGX_OK) {
        return NGX_ERROR;
    }

    ctx = ngx_quic_get_send_ctx(qc, ssl_encryption_application);
    pto = ngx_quic_pto(c, ctx);

    path->expires = ngx_current_msec + pto;
    path->tries = NGX_QUIC_PATH_RETRIES;

    if (!qc->path_validation.timer_set) {
        ngx_add_timer(&qc->path_validation, pto);
    }

    return NGX_OK;
}


static ngx_int_t
ngx_quic_send_path_challenge(ngx_connection_t *c, ngx_quic_path_t *path)
{
    ngx_quic_frame_t  frame;

    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, c->log, 0,
                   "quic path seq:%uL send path_challenge tries:%ui",
                   path->seqnum, path->tries);

    ngx_memzero(&frame, sizeof(ngx_quic_frame_t));

    frame.level = ssl_encryption_application;
    frame.type = NGX_QUIC_FT_PATH_CHALLENGE;

    ngx_memcpy(frame.u.path_challenge.data, path->challenge1, 8);

    /*
     * RFC 9000, 8.2.1.  Initiating Path Validation
     *
     * An endpoint MUST expand datagrams that contain a PATH_CHALLENGE frame
     * to at least the smallest allowed maximum datagram size of 1200 bytes,
     * unless the anti-amplification limit for the path does not permit
     * sending a datagram of this size.
     */

     /* same applies to PATH_RESPONSE frames */
    if (ngx_quic_frame_sendto(c, &frame, 1200, path) != NGX_OK) {
        return NGX_ERROR;
    }

    ngx_memcpy(frame.u.path_challenge.data, path->challenge2, 8);

    if (ngx_quic_frame_sendto(c, &frame, 1200, path) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


void
ngx_quic_path_validation_handler(ngx_event_t *ev)
{
    ngx_msec_t              now;
    ngx_queue_t            *q;
    ngx_msec_int_t          left, next, pto;
    ngx_quic_path_t        *path, *bkp;
    ngx_connection_t       *c;
    ngx_quic_send_ctx_t    *ctx;
    ngx_quic_connection_t  *qc;

    c = ev->data;
    qc = ngx_quic_get_connection(c);

    ctx = ngx_quic_get_send_ctx(qc, ssl_encryption_application);
    pto = ngx_quic_pto(c, ctx);

    next = -1;
    now = ngx_current_msec;

    q = ngx_queue_head(&qc->paths);

    while (q != ngx_queue_sentinel(&qc->paths)) {

        path = ngx_queue_data(q, ngx_quic_path_t, queue);
        q = ngx_queue_next(q);

        if (!path->validating) {
            continue;
        }

        left = path->expires - now;

        if (left > 0) {

            if (next == -1 || left < next) {
                next = left;
            }

            continue;
        }

        if (--path->tries) {
            path->expires = ngx_current_msec + pto;

            if (next == -1 || pto < next) {
                next = pto;
            }

            /* retransmit */
            (void) ngx_quic_send_path_challenge(c, path);

            continue;
        }

        ngx_log_debug1(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                       "quic path seq:%uL validation failed", path->seqnum);

        /* found expired path */

        path->validated = 0;
        path->validating = 0;
        path->limited = 1;


        /* RFC 9000, 9.3.2.  On-Path Address Spoofing
         *
         * To protect the connection from failing due to such a spurious
         * migration, an endpoint MUST revert to using the last validated
         * peer address when validation of a new peer address fails.
         */

        if (qc->path == path) {
            /* active path validation failed */

            bkp = ngx_quic_get_path(c, NGX_QUIC_PATH_BACKUP);

            if (bkp == NULL) {
                qc->error = NGX_QUIC_ERR_NO_VIABLE_PATH;
                qc->error_reason = "no viable path";
                ngx_quic_close_connection(c, NGX_ERROR);
                return;
            }

            qc->path = bkp;
            qc->path->tag = NGX_QUIC_PATH_ACTIVE;

            ngx_quic_set_connection_path(c, qc->path);

            ngx_log_error(NGX_LOG_INFO, c->log, 0,
                          "quic path seq:%uL addr:%V is restored from backup",
                          qc->path->seqnum, &qc->path->addr_text);

            ngx_quic_path_dbg(c, "is active", qc->path);
        }

        if (ngx_quic_free_path(c, path) != NGX_OK) {
            ngx_quic_close_connection(c, NGX_ERROR);
            return;
        }
    }

    if (next != -1) {
        ngx_add_timer(&qc->path_validation, next);
    }
}
