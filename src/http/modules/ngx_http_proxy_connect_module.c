/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


#define NGX_HTTP_PROXY_CONNECT_ESTABLISTHED     \
    "HTTP/1.0 200 Connection Established\r\n"   \
    "Proxy-agent: Tengine\r\n\r\n"


typedef struct ngx_http_proxy_connect_upstream_s
    ngx_http_proxy_connect_upstream_t;

typedef void (*ngx_http_proxy_connect_upstream_handler_pt)(
    ngx_http_request_t *r, ngx_http_proxy_connect_upstream_t *u);


typedef struct {
    ngx_flag_t                       accept_connect;
    ngx_array_t                     *allow_ports;

    ngx_msec_t                       read_timeout;
    ngx_msec_t                       send_timeout;
    ngx_msec_t                       connect_timeout;

    size_t                           send_lowat;
    size_t                           buffer_size;
} ngx_http_proxy_connect_loc_conf_t;


struct ngx_http_proxy_connect_upstream_s {
    ngx_http_proxy_connect_loc_conf_t             *conf;

    ngx_http_proxy_connect_upstream_handler_pt     read_event_handler;
    ngx_http_proxy_connect_upstream_handler_pt     write_event_handler;

    ngx_peer_connection_t            peer;

    ngx_http_request_t              *request;

    ngx_http_upstream_resolved_t    *resolved;

    ngx_buf_t                        from_client;

    ngx_output_chain_ctx_t           output;

    ngx_buf_t                        buffer;

    ngx_flag_t                       connected;
};


typedef struct {
    ngx_http_proxy_connect_upstream_t           *u;

    ngx_flag_t                      send_established;
    ngx_flag_t                      send_established_done;

    ngx_buf_t                       buf;

} ngx_http_proxy_connect_ctx_t;


static char *ngx_http_proxy_connect(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_proxy_connect_allow(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static void *ngx_http_proxy_connect_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_proxy_connect_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static void ngx_http_proxy_connect_write_downstream(ngx_http_request_t *r);
static void ngx_http_proxy_connect_read_downstream(ngx_http_request_t *r);
static void ngx_http_proxy_connect_send_handler(ngx_http_request_t *r);


static ngx_command_t  ngx_http_proxy_connect_commands[] = {

    { ngx_string("proxy_connect"),
      NGX_HTTP_SRV_CONF|NGX_CONF_NOARGS,
      ngx_http_proxy_connect,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, accept_connect),
      NULL },

    { ngx_string("proxy_connect_allow"),
      NGX_HTTP_SRV_CONF|NGX_CONF_1MORE,
      ngx_http_proxy_connect_allow,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("proxy_connect_read_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, read_timeout),
      NULL },

    { ngx_string("proxy_connect_send_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, send_timeout),
      NULL },

    { ngx_string("proxy_connect_connect_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, connect_timeout),
      NULL },

    { ngx_string("proxy_connect_send_lowat"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, send_lowat),
      NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_proxy_connect_module_ctx = {
    NULL,   /* preconfiguration */
    NULL,                                   /* postconfiguration */

    NULL,                                   /* create main configuration */
    NULL,                                   /* init main configuration */

    NULL,                                   /* create server configuration */
    NULL,                                   /* merge server configuration */

    ngx_http_proxy_connect_create_loc_conf, /* create location configuration */
    ngx_http_proxy_connect_merge_loc_conf   /* merge location configuration */
};


ngx_module_t  ngx_http_proxy_connect_module = {
    NGX_MODULE_V1,
    &ngx_http_proxy_connect_module_ctx,     /* module context */
    ngx_http_proxy_connect_commands,        /* module directives */
    NGX_HTTP_MODULE,                        /* module type */
    NULL,                                   /* init master */
    NULL,                                   /* init module */
    NULL,                                   /* init process */
    NULL,                                   /* init thread */
    NULL,                                   /* exit thread */
    NULL,                                   /* exit process */
    NULL,                                   /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_proxy_connect_get_peer(ngx_peer_connection_t *pc, void *data)
{
    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_test_connect(ngx_connection_t *c)
{
    int        err;
    socklen_t  len;

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT)  {
        if (c->write->pending_eof || c->read->pending_eof) {
            if (c->write->pending_eof) {
                err = c->write->kq_errno;

            } else {
                err = c->read->kq_errno;
            }

            c->log->action = "connecting to upstream";
            (void) ngx_connection_error(c, err,
                                    "kevent() reported that connect() failed");
            return NGX_ERROR;
        }

    } else
#endif
    {
        err = 0;
        len = sizeof(int);

        /*
         * BSDs and Linux return 0 and set a pending error in err
         * Solaris returns -1 and sets errno
         */

        if (getsockopt(c->fd, SOL_SOCKET, SO_ERROR, (void *) &err, &len)
            == -1)
        {
            err = ngx_errno;
        }

        if (err) {
            c->log->action = "connecting to upstream(proxy_connect)";
            (void) ngx_connection_error(c, err, "connect() failed");
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static void
ngx_http_proxy_connect_finalize_request(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u, ngx_int_t rc)
{
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "finalize proxy_conncet upstream request: %i", rc);

    r->keepalive = 0;

    if (u->resolved && u->resolved->ctx) {
        ngx_resolve_name_done(u->resolved->ctx);
        u->resolved->ctx = NULL;
    }

    if (u->peer.free && u->peer.sockaddr) {
        u->peer.free(&u->peer, u->peer.data, 0);
        u->peer.sockaddr = NULL;
    }

    if (u->peer.connection) {

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "close proxy_connect upstream connection: %d",
                       u->peer.connection->fd);

        if (u->peer.connection->pool) {
            ngx_destroy_pool(u->peer.connection->pool);
        }

        ngx_close_connection(u->peer.connection);
    }

    u->peer.connection = NULL;

    if (rc == NGX_DECLINED) {
        return;
    }

    r->connection->log->action = "sending to client";

    if (rc == NGX_HTTP_REQUEST_TIME_OUT
        || rc == NGX_HTTP_CLIENT_CLOSED_REQUEST)
    {
        ngx_http_finalize_request(r, rc);
        return;
    }

    if (u->connected && rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        rc = NGX_ERROR;
    }

    ngx_http_finalize_request(r, rc);
}


static void
ngx_http_proxy_connect_send_connection_established(ngx_http_request_t *r)
{
    ngx_int_t                              n;
    ngx_buf_t                             *b;
    ngx_connection_t                      *c;
    ngx_http_core_loc_conf_t              *clcf;
    ngx_http_proxy_connect_upstream_t     *u;
    ngx_http_proxy_connect_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);
    c = r->connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect send 200 connection estatbilshed");

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    u = ctx->u;

    b = &ctx->buf;

    ctx->send_established = 1;
    u->connected = 1;

    for (;;) {
        n = c->send(c, b->pos, b->last - b->pos);

        if (n >= 0) {
            b->pos += n;

            if (b->pos == b->last) {
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                              "proxy_connect sent 200 connection estatbilshed");

                if (c->write->timer_set) {
                    ngx_del_timer(c->write);
                }

                ctx->send_established_done = 1;

                r->write_event_handler =
                                        ngx_http_proxy_connect_write_downstream;
                r->read_event_handler = ngx_http_proxy_connect_read_downstream;

                if (ngx_handle_write_event(c->write, clcf->send_lowat)
                    != NGX_OK)
                {
                    ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
                    return;
                }

                if (r->header_in->last > r->header_in->pos || c->read->ready) {
                    r->read_event_handler(r);
                    return;
                }

                return;
            }

            /* keep sending more data */
            continue;
        }

        /* NGX_ERROR || NGX_AGAIN */
        break;
    }

    if (n == NGX_ERROR) {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
        return;
    }

    /* n == NGX_AGAIN */
    r->write_event_handler = ngx_http_proxy_connect_send_handler;

    ngx_add_timer(c->write, clcf->send_timeout);

    if (ngx_handle_write_event(c->write, clcf->send_lowat) != NGX_OK) {
        ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    return;
}


static void
ngx_http_proxy_connect_tunnel(ngx_http_request_t *r,
    ngx_uint_t from_upstream, ngx_uint_t do_write)
{
    size_t                              size;
    ssize_t                             n;
    ngx_buf_t                          *b;
    ngx_connection_t                   *c, *downstream, *upstream, *dst, *src;
    ngx_http_core_loc_conf_t           *clcf;
    ngx_http_proxy_connect_ctx_t       *ctx;
    ngx_http_proxy_connect_upstream_t  *u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    c = r->connection;
    u = ctx->u;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http proxy_connect, fu:%ui", from_upstream);

    downstream = c;
    upstream = u->peer.connection;

    if (from_upstream) {
        src = upstream;
        dst = downstream;
        b = &u->buffer;

    } else {
        src = downstream;
        dst = upstream;
        b = &u->from_client;

        if (r->header_in->last > r->header_in->pos) {
            b = r->header_in;
            b->end = b->last;
            do_write = 1;
        }

        if (b->start == NULL) {
            b->start = ngx_palloc(r->pool, u->conf->buffer_size);
            if (b->start == NULL) {
                ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
                return;
            }

            b->pos = b->start;
            b->last = b->start;
            b->end = b->start + u->conf->buffer_size;
            b->temporary = 1;
        }
    }

    for ( ;; ) {

        if (do_write) {

            size = b->last - b->pos;

            if (size && dst->write->ready) {

                n = dst->send(dst, b->pos, size);

                if (n == NGX_AGAIN) {
                    break;
                }

                if (n == NGX_ERROR) {
                    ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
                    return;
                }

                if (n > 0) {
                    b->pos += n;

                    if (b->pos == b->last) {
                        b->pos = b->start;
                        b->last = b->start;
                    }
                }
            }
        }

        size = b->end - b->last;

        if (size && src->read->ready) {

            n = src->recv(src, b->last, size);

            if (n == NGX_AGAIN || n == 0) {
                break;
            }

            if (n > 0) {
                do_write = 1;
                b->last += n;

                continue;
            }

            if (n == NGX_ERROR) {
                src->read->eof = 1;
            }
        }

        break;
    }

    if ((upstream->read->eof && u->buffer.pos == u->buffer.last)
        || (downstream->read->eof && u->from_client.pos == u->from_client.last)
        || (downstream->read->eof && upstream->read->eof))
    {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "http proxy_connect done");
        ngx_http_proxy_connect_finalize_request(r, u, 0);
        return;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (ngx_handle_write_event(upstream->write, u->conf->send_lowat)
        != NGX_OK)
    {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
        return;
    }

    if (upstream->write->active && !upstream->write->ready) {
        ngx_add_timer(upstream->write, u->conf->send_timeout);

    } else if (upstream->write->timer_set) {
        ngx_del_timer(upstream->write);
    }

    if (ngx_handle_read_event(upstream->read, 0) != NGX_OK) {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
        return;
    }

    if (upstream->read->active && !upstream->read->ready) {
        if (from_upstream) {
            ngx_add_timer(upstream->read, u->conf->read_timeout);
        }

    } else if (upstream->read->timer_set) {
        ngx_del_timer(upstream->read);
    }

    if (ngx_handle_write_event(downstream->write, clcf->send_lowat)
        != NGX_OK)
    {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
        return;
    }

    if (ngx_handle_read_event(downstream->read, 0) != NGX_OK) {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
        return;
    }

    if (downstream->write->active && !downstream->write->ready) {
        ngx_add_timer(downstream->write, clcf->send_timeout);

    } else if (downstream->write->timer_set) {
        ngx_del_timer(downstream->write);
    }

    if (downstream->read->active && !downstream->read->ready) {
        if (!from_upstream) {
            ngx_add_timer(downstream->read, clcf->client_body_timeout);
        }

    } else if (downstream->read->timer_set) {
        ngx_del_timer(downstream->read);
    }
}


static void
ngx_http_proxy_connect_read_downstream(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_ctx_t       *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (r->connection->read->timedout) {
        r->connection->timedout = 1;
        ngx_connection_error(r->connection, NGX_ETIMEDOUT, "client timed out");
        ngx_http_proxy_connect_finalize_request(r, ctx->u,
                                                NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    ngx_http_proxy_connect_tunnel(r, 0, 0);
}


static void
ngx_http_proxy_connect_write_downstream(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_ctx_t       *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (r->connection->write->timedout) {
        r->connection->timedout = 1;
        ngx_connection_error(r->connection, NGX_ETIMEDOUT, "client timed out");
        ngx_http_proxy_connect_finalize_request(r, ctx->u,
                                                NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    ngx_http_proxy_connect_tunnel(r, 1, 1);
}


static void
ngx_http_proxy_connect_read_upstream(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u)
{
    ngx_connection_t                    *c;
    ngx_http_proxy_connect_ctx_t        *ctx;
    ngx_http_proxy_connect_loc_conf_t   *plcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect upstream read handler");

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);
    plcf = ngx_http_get_module_loc_conf(r, ngx_http_proxy_connect_module);

    c = u->peer.connection;

    if (c->read->timedout) {
        ngx_connection_error(c, NGX_ETIMEDOUT, "upstream timed out");
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_GATEWAY_TIME_OUT);
        return;
    }

    if (!ctx->send_established &&
        ngx_http_proxy_connect_test_connect(c) != NGX_OK)
    {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        return;
    }

    if (u->buffer.start == NULL) {
        u->buffer.start = ngx_palloc(r->pool, u->conf->buffer_size);
        if (u->buffer.start == NULL) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        u->buffer.pos = u->buffer.start;
        u->buffer.last = u->buffer.start;
        u->buffer.end = u->buffer.start + u->conf->buffer_size;
        u->buffer.temporary = 1;
    }

    if (!ctx->send_established_done) {
        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        return;
    }

    ngx_http_proxy_connect_tunnel(r, 1, 0);
}


static void
ngx_http_proxy_connect_write_upstream(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u)
{
    ngx_connection_t  *c;
    ngx_http_proxy_connect_ctx_t          *ctx;

    c = u->peer.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect upstream write handler");

    if (c->write->timedout) {
        ngx_connection_error(c, NGX_ETIMEDOUT,
                             "upstream timed out(proxy_connect)");
        ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_GATEWAY_TIME_OUT);
        return;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    if (!ctx->send_established &&
        ngx_http_proxy_connect_test_connect(c) != NGX_OK)
    {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        return;
    }

    if (!ctx->send_established) {
        ngx_http_proxy_connect_send_connection_established(r);
    }

    if (!ctx->send_established_done) {
        if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        return;
    }

    ngx_http_proxy_connect_tunnel(r, 0, 1);
}


static void
ngx_http_proxy_connect_send_handler(ngx_http_request_t *r)
{
    ngx_connection_t                 *c;
    ngx_http_proxy_connect_ctx_t     *ctx;

    c = r->connection;
    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect send connection estatbilshed handler");

    if (c->write->timedout) {
        c->timedout = 1;
        ngx_connection_error(c, NGX_ETIMEDOUT,
                             "client timed out(proxy_connect)");
        ngx_http_proxy_connect_finalize_request(r, ctx->u,
                                                NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    if (ctx->buf.pos != ctx->buf.last) {
        ngx_http_proxy_connect_send_connection_established(r);
    }
}


static void
ngx_http_proxy_connect_upstream_handler(ngx_event_t *ev)
{
    ngx_connection_t                    *c;
    ngx_http_request_t                  *r;
    ngx_http_log_ctx_t                  *lctx;
    ngx_http_proxy_connect_upstream_t   *u;

    c = ev->data;
    u = c->data;

    r = u->request;
    c = r->connection;

    lctx = c->log->data;
    lctx->current_request = r;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http proxy_connect upstream handler: \"%V:%V\"",
                   &r->connect_host, &r->connect_port);

    if (ev->write) {
        u->write_event_handler(r, u);

    } else {
        u->read_event_handler(r, u);
    }

    ngx_http_run_posted_requests(c);
}


static void
ngx_http_proxy_connect_process_connect(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u)
{
    ngx_int_t                        rc;
    ngx_connection_t                *c;
    ngx_peer_connection_t           *pc;
    ngx_http_upstream_resolved_t    *ur;


    r->connection->log->action = "connecting to upstream(proxy_connect)";

    pc = &u->peer;
    ur = u->resolved;

    pc->sockaddr = ur->sockaddr;
    pc->socklen = ur->socklen;
    pc->name = &ur->host;

    pc->get = ngx_http_proxy_connect_get_peer;

    rc = ngx_event_connect_peer(&u->peer);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect upstream connect: %i", rc);

    if (rc == NGX_ERROR) {
        ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    if (rc == NGX_BUSY) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "no live connection");
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        return;
    }

    if (rc == NGX_DECLINED) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "connection error");
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        return;
    }

    /* rc == NGX_OK || rc == NGX_AGAIN || rc == NGX_DONE */

    c = pc->connection;

    c->data = u;

    c->write->handler = ngx_http_proxy_connect_upstream_handler;
    c->read->handler = ngx_http_proxy_connect_upstream_handler;

    u->write_event_handler = ngx_http_proxy_connect_write_upstream;
    u->read_event_handler = ngx_http_proxy_connect_read_upstream;

    c->sendfile &= r->connection->sendfile;
    c->log = r->connection->log;

    if (c->pool == NULL) {

        c->pool = ngx_create_pool(128, r->connection->log);
        if (c->pool == NULL) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }
    }

    c->pool->log = c->log;
    c->read->log = c->log;
    c->write->log = c->log;

    if (rc == NGX_AGAIN) {
        ngx_add_timer(c->write, u->conf->connect_timeout);
        return;
    }

    ngx_http_proxy_connect_send_connection_established(r);
}


static void
ngx_http_proxy_connect_resolve_handler(ngx_resolver_ctx_t *ctx)
{
    u_char                                      *p;
    ngx_int_t                                    i, len;
    ngx_connection_t                            *c;
    struct sockaddr_in                          *sin;
    ngx_http_request_t                          *r;
    ngx_http_upstream_resolved_t                *ur;
    ngx_http_proxy_connect_upstream_t           *u;

    u = ctx->data;
    r = u->request;
    ur = u->resolved;
    c = r->connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect resolve handler");

    if (ctx->state) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "%V could not be resolved (%i: %s)",
                      &ctx->name, ctx->state,
                      ngx_resolver_strerror(ctx->state));

        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        goto failed;
    }

    ur->naddrs = ctx->naddrs;
    ur->addrs = ctx->addrs;

#if (NGX_DEBUG)
    {
    in_addr_t   addr;
    ngx_uint_t  i;

    for (i = 0; i < ctx->naddrs; i++) {
        addr = ntohl(ur->addrs[i]);

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "name was resolved to %ud.%ud.%ud.%ud",
                       (addr >> 24) & 0xff, (addr >> 16) & 0xff,
                       (addr >> 8) & 0xff, addr & 0xff);
    }
    }
#endif

    if (ur->naddrs == 0) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "%V could not be resolved", &ctx->name);

        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        goto failed;
    }

    if (ur->naddrs == 1) {
        i = 0;

    } else {
        i = ngx_random() % ur->naddrs;
    }

    len = NGX_INET_ADDRSTRLEN + sizeof(":65536") - 1;

    p = ngx_pnalloc(r->pool, len + sizeof(struct sockaddr_in));
    if (p == NULL) {
        ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);

        return;
    }

    sin = (struct sockaddr_in *) &p[len];
    ngx_memzero(sin, sizeof(struct sockaddr_in));

    len = ngx_inet_ntop(AF_INET, &ur->addrs[i], p, NGX_INET_ADDRSTRLEN);
    len = ngx_sprintf(&p[len], ":%d", ur->port) - p;

    sin->sin_family = AF_INET;
    sin->sin_port = htons(ur->port);
    sin->sin_addr.s_addr = ur->addrs[i];

    ur->sockaddr = (struct sockaddr *) sin;
    ur->socklen = sizeof(struct sockaddr_in);

    ur->host.data = p;
    ur->host.len = len;
    ur->naddrs = 1;

    ngx_resolve_name_done(ctx);
    ur->ctx = NULL;

    ngx_http_proxy_connect_process_connect(r, u);

failed:

    ngx_http_run_posted_requests(c);
}


static ngx_int_t
ngx_http_proxy_connect_upstream_create(ngx_http_request_t *r,
    ngx_http_proxy_connect_ctx_t *ctx)
{
    ngx_http_proxy_connect_upstream_t       *u;

    u = ngx_pcalloc(r->pool, sizeof(ngx_http_proxy_connect_upstream_t));
    if (u == NULL) {
        return NGX_ERROR;
    }

    ctx->u = u;

    u->peer.log = r->connection->log;
    u->peer.log_error = NGX_ERROR_ERR;

    u->request = r;

    return NGX_OK;
}


static void
ngx_http_proxy_connect_check_broken_connection(ngx_http_request_t *r,
    ngx_event_t *ev)
{
    int                                 n;
    char                                buf[1];
    ngx_err_t                           err;
    ngx_int_t                           event;
    ngx_connection_t                   *c;
    ngx_http_proxy_connect_ctx_t       *ctx;
    ngx_http_proxy_connect_upstream_t  *u;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "http proxy_connect check client, write event:%d, \"%V:%V\"",
                   ev->write, &r->connect_host, &r->connect_port);

    c = r->connection;
    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);
    u = ctx->u;

    if (c->error) {
        if ((ngx_event_flags & NGX_USE_LEVEL_EVENT) && ev->active) {

            event = ev->write ? NGX_WRITE_EVENT : NGX_READ_EVENT;

            if (ngx_del_event(ev, event, 0) != NGX_OK) {
                ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
                return;
            }
        }

        ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_CLIENT_CLOSED_REQUEST);

        return;
    }

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT) {

        if (!ev->pending_eof) {
            return;
        }

        ev->eof = 1;
        c->error = 1;

        if (ev->kq_errno) {
            ev->error = 1;
        }

        if (u->peer.connection) {
            ngx_log_error(NGX_LOG_INFO, ev->log, ev->kq_errno,
                          "kevent() reported that client prematurely closed "
                          "connection, so upstream connection is closed too");
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_CLIENT_CLOSED_REQUEST);
            return;
        }

        ngx_log_error(NGX_LOG_INFO, ev->log, ev->kq_errno,
                      "kevent() reported that client prematurely closed "
                      "connection");

        if (u->peer.connection == NULL) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_CLIENT_CLOSED_REQUEST);
        }

        return;
    }

#endif

    n = recv(c->fd, buf, 1, MSG_PEEK);

    err = ngx_socket_errno;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ev->log, err,
                   "http proxy_connect upstream recv(): %d", n);

    if (ev->write && (n >= 0 || err == NGX_EAGAIN)) {
        return;
    }

    if ((ngx_event_flags & NGX_USE_LEVEL_EVENT) && ev->active) {

        event = ev->write ? NGX_WRITE_EVENT : NGX_READ_EVENT;

        if (ngx_del_event(ev, event, 0) != NGX_OK) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }
    }

    if (n > 0) {
        return;
    }

    if (n == -1) {
        if (err == NGX_EAGAIN) {
            return;
        }

        ev->error = 1;

    } else { /* n == 0 */
        err = 0;
    }

    ev->eof = 1;
    c->error = 1;

    if (u->peer.connection) {
        ngx_log_error(NGX_LOG_INFO, ev->log, err,
                      "client prematurely closed connection, "
                      "so upstream connection is closed too");
        ngx_http_proxy_connect_finalize_request(r, u,
                                           NGX_HTTP_CLIENT_CLOSED_REQUEST);
        return;
    }

    ngx_log_error(NGX_LOG_INFO, ev->log, err,
                  "client prematurely closed connection");

    if (u->peer.connection == NULL) {
        ngx_http_proxy_connect_finalize_request(r, u,
                                           NGX_HTTP_CLIENT_CLOSED_REQUEST);
    }
}


static void
ngx_http_proxy_connect_rd_check_broken_connection(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_check_broken_connection(r, r->connection->read);
}


static void
ngx_http_proxy_connect_wr_check_broken_connection(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_check_broken_connection(r, r->connection->write);
}


static ngx_int_t
ngx_http_proxy_connect_handler(ngx_http_request_t *r)
{
    in_port_t                           *p;
    ngx_url_t                            url;
    ngx_uint_t                           i, allow;
    ngx_resolver_ctx_t                  *rctx, temp;
    ngx_http_core_loc_conf_t            *clcf;
    ngx_http_proxy_connect_ctx_t        *ctx;
    ngx_http_proxy_connect_upstream_t   *u;
    ngx_http_proxy_connect_loc_conf_t   *plcf;

    plcf = ngx_http_get_module_loc_conf(r, ngx_http_proxy_connect_module);

    allow = 0;

    if (plcf->allow_ports) {
        p = plcf->allow_ports->elts;

        for (i = 0; i < plcf->allow_ports->nelts; i++) {
            if (r->connect_port_n == p[i]) {
                allow = 1;
                break;
            }
        }

    } else {
        if (r->connect_port_n == 443 || r->connect_port_n == 563) {
            allow = 1;
        }
    }

    if (allow == 0) {
        return NGX_HTTP_FORBIDDEN;
    }

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_proxy_connect_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->buf.pos = (u_char *) NGX_HTTP_PROXY_CONNECT_ESTABLISTHED;
    ctx->buf.last = ctx->buf.pos +
                    sizeof(NGX_HTTP_PROXY_CONNECT_ESTABLISTHED) - 1;
    ctx->buf.memory = 1;

    ngx_http_set_ctx(r, ctx, ngx_http_proxy_connect_module);

    if (ngx_http_proxy_connect_upstream_create(r, ctx) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    u = ctx->u;

    u->conf = plcf;

    ngx_memzero(&url, sizeof(ngx_url_t));

    url.url.len = r->connect_host.len;
    url.url.data = r->connect_host.data;
    url.default_port = r->connect_port_n;
    url.no_resolve = 1;

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        if (url.err) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "%s in connect host \"%V\"", url.err, &url.url);
            return NGX_HTTP_FORBIDDEN;
        }

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    r->read_event_handler = ngx_http_proxy_connect_rd_check_broken_connection;
    r->write_event_handler = ngx_http_proxy_connect_wr_check_broken_connection;

    u->resolved = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_resolved_t));
    if (u->resolved == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (url.addrs && url.addrs[0].sockaddr) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "connect network address given directly");

        u->resolved->sockaddr = url.addrs[0].sockaddr;
        u->resolved->socklen = url.addrs[0].socklen;
        u->resolved->naddrs = 1;
        u->resolved->host = url.addrs[0].name;

    } else {
        u->resolved->host = r->connect_host;
        u->resolved->port = (in_port_t) r->connect_port_n;
    }

    if (u->resolved->sockaddr) {
        r->main->count++;

        ngx_http_proxy_connect_process_connect(r, u);

        return NGX_DONE;
    }

    temp.name = r->connect_host;
    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    rctx = ngx_resolve_start(clcf->resolver, &temp);
    if (rctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to start the resolver");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (rctx == NGX_NO_RESOLVER) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "no resolver defined to resolve %V", &r->connect_host);
        return NGX_HTTP_BAD_GATEWAY;
    }

    rctx->name = r->connect_host;
    rctx->type = NGX_RESOLVE_A;
    rctx->handler = ngx_http_proxy_connect_resolve_handler;
    rctx->data = u;
    rctx->timeout = clcf->resolver_timeout;

    u->resolved->ctx = rctx;

    r->main->count++;

    if (ngx_resolve_name(rctx) != NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "proxy_connect fail to run resolver immediately");

        u->resolved->ctx = NULL;
        r->main->count--;
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    return NGX_DONE;
}


static char *
ngx_http_proxy_connect_allow(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    in_port_t                           *p;
    ngx_int_t                            port;
    ngx_uint_t                           i;
    ngx_str_t                           *value;
    ngx_http_proxy_connect_loc_conf_t   *plcf = conf;

    if (plcf->allow_ports != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    plcf->allow_ports = ngx_array_create(cf->pool, 2, sizeof(in_port_t));
    if (plcf->allow_ports == NULL) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {
        port = ngx_atoi(value[i].data, value[i].len);

        if (port == NGX_ERROR || port < 1 || port > 65535) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid value \"%V\" in \"%V\" directive",
                               &cf->args[i], &cmd->name);
            return  NGX_CONF_ERROR;
        }

        p = ngx_array_push(plcf->allow_ports);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        *p = port;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_proxy_connect(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t   *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_proxy_connect_handler;
    clcf->accept_connect = 1;

    return NGX_CONF_OK;
}


static void *
ngx_http_proxy_connect_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_proxy_connect_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_proxy_connect_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    conf->accept_connect = NGX_CONF_UNSET;
    conf->allow_ports = NGX_CONF_UNSET_PTR;

    conf->connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->send_timeout = NGX_CONF_UNSET_MSEC;
    conf->read_timeout = NGX_CONF_UNSET_MSEC;

    conf->send_lowat = NGX_CONF_UNSET_SIZE;
    conf->buffer_size = NGX_CONF_UNSET_SIZE;

    return conf;
}


static char *
ngx_http_proxy_connect_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_proxy_connect_loc_conf_t    *prev = parent;
    ngx_http_proxy_connect_loc_conf_t    *conf = child;

    ngx_conf_merge_value(conf->accept_connect, prev->accept_connect, 0);
    ngx_conf_merge_ptr_value(conf->allow_ports, prev->allow_ports, NULL);

    ngx_conf_merge_msec_value(conf->connect_timeout,
                              prev->connect_timeout, 60000);

    ngx_conf_merge_msec_value(conf->send_timeout, prev->send_timeout, 60000);

    ngx_conf_merge_msec_value(conf->read_timeout, prev->read_timeout, 60000);

    ngx_conf_merge_size_value(conf->send_lowat, prev->send_lowat, 0);

    ngx_conf_merge_size_value(conf->buffer_size, prev->buffer_size, 16384);

    return NGX_CONF_OK;
}
