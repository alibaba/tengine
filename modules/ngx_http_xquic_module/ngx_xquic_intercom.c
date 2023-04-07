/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_xquic_intercom.h>

typedef struct {
    ngx_pool_t           *pool;

    ngx_connection_t     *connection;

    struct sockaddr_un   *addr;
    ngx_int_t            *addrlen;

    ngx_log_t            *log;

    xqc_engine_t         *xquic_engine;
} ngx_xquic_intercom_ctx_t;

static ngx_int_t ngx_xquic_intercom_create_socket(ngx_xquic_intercom_ctx_t *ctx, const char *path);
static void ngx_xquic_intercom_recv_handler(ngx_event_t *rev);

static uint64_t ngx_xquic_stat_send_cnt = 0;
static uint64_t ngx_xquic_stat_recv_cnt = 0;
static uint64_t ngx_xquic_stat_send_eagain_cnt = 0;

static ngx_xquic_intercom_ctx_t *ctx = NULL;

ngx_int_t
ngx_xquic_intercom_init(ngx_cycle_t *cycle, void *engine)
{
    u_char                       path[4096] = { 0 };
    ngx_int_t                    i;
    ngx_pool_t                  *pool;
    ngx_core_conf_t             *ccf;
    ngx_http_xquic_main_conf_t  *qmcf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);
 
    if (ccf->worker_processes <= 1 || ngx_process != NGX_PROCESS_WORKER) {
        return NGX_OK;
    }

    qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);

    pool = ngx_create_pool(qmcf->intercom_pool_size, cycle->log);
    if (pool == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_init: create pool size %d failed|",
                      qmcf->intercom_pool_size);
        return NGX_ERROR;
    }

    ctx = ngx_pcalloc(pool, sizeof(ngx_xquic_intercom_ctx_t));
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_init: create ctx failed|");
        return NGX_ERROR;
    }

    ctx->pool = pool;
    ctx->log = cycle->log;
    ctx->xquic_engine = engine;

    ctx->addr = ngx_pcalloc(pool, ccf->worker_processes * sizeof(struct sockaddr_un));
    if (ctx->addr == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "ngx_xquic_intercom_init: alloc addr failed");
        return NGX_ERROR;
    }

    ctx->addrlen = ngx_pcalloc(pool, ccf->worker_processes * sizeof(ngx_int_t));
    if (ctx->addrlen == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "ngx_xquic_intercom_init: alloc addrlen failed");
        return NGX_ERROR;
    }

    *ngx_snprintf(path, sizeof(path), "%V", &qmcf->intercom_socket_path) = 0;

    if (ngx_create_full_path(path, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH)) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "ngx_xquic_intercom_init: failed to create path: %s", (char *) path);

        return NGX_ERROR;
    }

    for (i = 0; i < ccf->worker_processes; i++) {
        *ngx_snprintf(path, sizeof(path), "%V#%uD", &qmcf->intercom_socket_path, i) = 0;

        if ((ngx_uint_t) i == ngx_worker) {
            if (ngx_xquic_intercom_create_socket(ctx, (const char *) path) != NGX_OK) {
                return NGX_ERROR;
            }
        } else {
            ctx->addr[i].sun_family = AF_UNIX;
            ngx_memcpy(ctx->addr[i].sun_path, path, strlen((const char *)path));
            ctx->addrlen[i] = strlen((const char *) path) + sizeof(ctx->addr[i].sun_family);
        }
    }

    return NGX_OK;
}

void
ngx_xquic_intercom_exit()
{
    if (ctx) {
        ngx_close_connection(ctx->connection);
        ngx_destroy_pool(ctx->pool);
    }   
}

static ngx_int_t
ngx_xquic_intercom_create_socket(ngx_xquic_intercom_ctx_t *ctx, const char *path)
{
    socklen_t            addr_len;
    ngx_event_t         *rev;
    ngx_socket_t         s;
    ngx_connection_t    *c;
    struct sockaddr_un   addr;

    unlink((const char *) path);

    s = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (s == (ngx_socket_t) -1) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, ngx_socket_errno,
                      "|xquic|intercom create unix domain socket failed|");
        return NGX_ERROR;
    }

    c = ngx_get_connection(s, ctx->log);
    if (c == NULL) {
        if (ngx_close_socket(s) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ctx->log, ngx_socket_errno,
                          "|xquic|intercom close socket failed|");
        }

        return NGX_ERROR;
    }

    ngx_memzero(&addr, sizeof(addr));

    addr.sun_family = AF_UNIX;
    ngx_memcpy(addr.sun_path, path, strlen((const char *) path));

    addr_len = strlen((const char *) path) + sizeof(addr.sun_family);

    if (ngx_nonblocking(s) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, ngx_socket_errno,
                      "|xquic|intercom set nonblocking failed|");
        goto failed;
    }

    if (bind(s, (struct sockaddr *) &addr, addr_len) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, ngx_socket_errno,
                      "|xquic|intercom bind() to %s failed|", path);

        goto failed;
    }

    c->pool = ctx->pool;
    c->log = ctx->log;
    c->data = ctx;

    rev = c->read;
    rev->log = ctx->log;
    rev->data = c;
    rev->handler = ngx_xquic_intercom_recv_handler;

    if (ngx_add_event(rev, NGX_READ_EVENT, 0) != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, 0,
                      "|xquic|intercom add read event failed|");
        goto failed;
    }

    ctx->connection = c;

    ngx_log_debug1(NGX_LOG_DEBUG_CORE, ctx->log, 0,
                   "|xquic|intercom create socket %s|", path);

    return NGX_OK;

failed:
    ngx_close_connection(c);
    return NGX_ERROR;
}


static void
ngx_xquic_intercom_recv_handler(ngx_event_t *rev)
{
    ngx_int_t                n;
    ngx_err_t                err;
    ngx_connection_t        *c;
    ngx_xquic_recv_packet_t   packet;
    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);


    c = rev->data;

    for ( ;; ) {
        n = recv(c->fd, (void *) &packet, sizeof(ngx_xquic_recv_packet_t), 0);

        if (n < 0) {
            err = ngx_socket_errno;

            if (err == NGX_EAGAIN || err == NGX_EINTR) {
                ngx_log_debug0(NGX_LOG_DEBUG_EVENT, rev->log, 0,
                               "|xquic|ngx_quic_intercom_recv_handler: recv() not ready|");
            } else {
                ngx_log_error(NGX_LOG_ERR, rev->log, ngx_socket_errno,
                              "|xquic|ngx_quic_intercom_recv_handler: recv() failed|");
            }

            goto finish_recv;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_EVENT, rev->log, 0,
                       "|xquic|ngx_quic_intercom_recv_handler: worker %d recv connection_id %s packet|",
                       ngx_worker, xqc_dcid_str(&packet.xquic.dcid));

        if (n != sizeof(ngx_xquic_recv_packet_t)) {
            ngx_log_error(NGX_LOG_ERR, rev->log, ngx_socket_errno,
                          "|xquic|ngx_quic_intercom_recv_handler: worker %d recv connection_id %s packet error %d|",
                          ngx_worker, xqc_dcid_str(&packet.xquic.dcid), n);
        } else {
            ngx_xquic_stat_recv_cnt++;
            ngx_xquic_recv_from_intercom(&packet);
        }
    }

finish_recv:
    xqc_engine_finish_recv(qmcf->xquic_engine);
}

void
ngx_xquic_intercom_send(ngx_int_t worker_num, ngx_xquic_recv_packet_t *packet)
{
    ngx_int_t           n;
    ngx_err_t           err;
    ngx_connection_t   *c;

    c = ctx->connection;

    n = sendto(c->fd, packet, sizeof(ngx_xquic_recv_packet_t), 0,
               &ctx->addr[worker_num], ctx->addrlen[worker_num]);

    ngx_xquic_stat_send_cnt++;

    ngx_log_debug6(NGX_LOG_DEBUG_EVENT, ctx->log, 0,
                   "|xquic|intercom_send: worker %d -> %d send connection_id %s packet, "
                   "recv(%ul), send(%ul), eagain(%ul)|",
                   ngx_worker, worker_num, xqc_dcid_str(&packet->xquic.dcid),
                   ngx_xquic_stat_recv_cnt, ngx_xquic_stat_send_cnt, ngx_xquic_stat_send_eagain_cnt);

    if (n < 0) {
        err = ngx_socket_errno;

        if (err == NGX_EAGAIN || err == NGX_EINTR) {
            ngx_xquic_stat_send_eagain_cnt++;
            if (ngx_xquic_stat_send_eagain_cnt % 100 == 1) {
                ngx_log_error(NGX_LOG_ERR, ctx->log, ngx_socket_errno,
                             "|xquic|ngx_xquic_intercom_send: worker %d -> %d send packet error, "
                             "recv(%ul), send(%ul), eagain(%ul)|",
                             ngx_worker, worker_num,
                             ngx_xquic_stat_recv_cnt, ngx_xquic_stat_send_cnt, ngx_xquic_stat_send_eagain_cnt);
            }
        } else {
            ngx_log_error(NGX_LOG_ERR, ctx->log, ngx_socket_errno,
                          "|xquic|ngx_xquic_intercom_send: worker %d -> %d send connection_id %ul packet error|",
                          ngx_worker, worker_num, packet->xquic.connection_id);
        }

        return;
    }

    if (n != sizeof(ngx_xquic_recv_packet_t)) {
        ngx_log_error(NGX_LOG_ERR, ctx->log, ngx_socket_errno,
                      "|xquic|ngx_xquic_intercom_send: worker %d -> %d send connection_id %ul packet uncomplete(%d != %d)|",
                      ngx_worker, worker_num, packet->xquic.connection_id, n, sizeof(ngx_xquic_recv_packet_t));
    }
}


ngx_int_t
ngx_xquic_intercom_packet_hash(ngx_xquic_recv_packet_t *packet)
{
    ngx_core_conf_t *ccf;
    ngx_int_t target_worker;

    if (ctx == NULL) {
        return ngx_worker;
    }

#if (NGX_XQUIC_SUPPORT_CID_ROUTE)
    if (ngx_xquic_is_cid_route_on((ngx_cycle_t *) ngx_cycle)) {
        return ngx_xquic_get_target_worker_from_cid(packet);
    }
#endif

    ccf = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx, ngx_core_module);
    target_worker = ngx_murmur_hash2(packet->xquic.dcid.cid_buf, packet->xquic.dcid.cid_len)
                                                % ccf->worker_processes;


    return target_worker;
}

