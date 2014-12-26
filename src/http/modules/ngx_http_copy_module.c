
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_array_t            *servers;    /* ngx_http_copy_server_t */
    ngx_int_t               max_cached;
    ngx_msec_t              cached_timeout;
    ngx_flag_t              keepalive;
    ngx_flag_t              force_keepalive;
    ngx_flag_t              unparsed_uri;
} ngx_http_copy_loc_conf_t;


typedef struct {
    ngx_addr_t             *addrs;
    ngx_uint_t              naddrs;
    ngx_uint_t              multiple;

    ngx_queue_t             cache_connections;  /* cached connection list*/
    ngx_int_t               cached;

    ngx_int_t               max_connection;
    ngx_int_t               connection;

    ngx_uint_t              max_fails;
    ngx_uint_t              fails;
    ngx_uint_t              fail_retries;

    time_t                  fail_timeout;
    time_t                  checked;

    ngx_int_t               switch_index;       /* index of switch_on parameter*/
    ngx_flag_t              serial;

    ngx_http_copy_loc_conf_t    *conf;
} ngx_http_copy_server_t;


typedef struct {
    ngx_uint_t                  state;
    off_t                       size;
} ngx_http_copy_chunk_t;


typedef struct ngx_http_copy_request_s ngx_http_copy_request_t;


struct ngx_http_copy_request_s {
    ngx_http_request_t         *r;          /* incoming request */
    ngx_pool_t                 *pool;
    ngx_peer_connection_t       peer;

    ngx_chain_t                *request_bufs;
    ngx_buf_t                  *buffer;

    ngx_output_chain_ctx_t      output;
    ngx_chain_writer_ctx_t      writer;

    ngx_http_request_t          response;   /* used by http response parser */
    ngx_http_status_t           status;     /* used by http response parser */
    off_t                       length;     /* response body length or chunk body size */
    off_t                       input_body_rest;
    ngx_http_copy_chunk_t      *chunk;

    ngx_http_copy_server_t     *cs;         /* used when response is sent back */

    ngx_int_t                 (*process_header)(ngx_http_copy_request_t *cpr);

    ngx_queue_t                 queue;      /* in ngx_http_copy_ctx_t::copy_request */

    /* serial copy */
    ngx_chain_t                *serial_request_bufs;
    ngx_uint_t                  serial_sent;

    unsigned                    discard_body:2;
    unsigned                    request_sent:1;
    unsigned                    keepalive_connect:1;
    unsigned                    connect:1;
    unsigned                    input_body:1;
    unsigned                    serial:1;
};


typedef struct {
    ngx_queue_t                 copy_request;
} ngx_http_copy_ctx_t;


typedef struct {
    /* long time */
    ngx_atomic_t    request_count;
    ngx_atomic_t    response_count;
    ngx_atomic_t    response_ok_count;
    ngx_atomic_t    response_err_count;
    ngx_atomic_t    connect_count;
    ngx_atomic_t    connect_keepalive_count;
    ngx_atomic_t    read_bytes;
    ngx_atomic_t    read_chunk_bytes;
    ngx_atomic_t    read_timeout;
    ngx_atomic_t    write_timeout;

    /* real time */
    ngx_atomic_t    active_connect;
    ngx_atomic_t    active_connect_keepalive;
} ngx_http_copy_status_shm_t;


static ngx_int_t ngx_http_copy_test_connect(ngx_connection_t *c);
static ngx_int_t ngx_http_copy_init(ngx_conf_t *conf);
static ngx_int_t ngx_http_copy_handler(ngx_http_request_t *r);
static char *ngx_http_copy(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_copy_send_request(ngx_http_copy_request_t *cpr);
static char *ngx_http_copy_status(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static void ngx_http_copy_dummy_handler(ngx_event_t *ev);
static ngx_int_t ngx_http_copy_try_keepalive_connection(
    ngx_http_copy_request_t *cpr);
static char *ngx_http_copy_keepalive(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static void *ngx_http_copy_create_loc_conf(ngx_conf_t *conf);
static char *ngx_http_copy_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_copy_init_shm(ngx_conf_t *cf);
static ngx_int_t ngx_chain_buf_add_copy(ngx_pool_t *pool, ngx_chain_t **chain,
    ngx_chain_t *in);
static ngx_int_t ngx_http_copy_parse_status_line(ngx_http_copy_request_t *cpr);

#define ngx_http_copy_server_failed(cs)     \
    do {                                    \
        if ((cs)->max_fails) {              \
            (cs)->fails++;                  \
            (cs)->checked = ngx_time();     \
            if ((cs)->fail_retries == 0) {  \
                (cs)->fail_retries = 10;    \
            }                               \
        }                                   \
    } while (0)

#define ngx_http_copy_server_ok(cs)  \
    do {                                    \
        if ((cs)->fails) {                  \
            (cs)->fails = 0;                \
        }                                   \
    } while (0)

#define NGX_HTTP_COPY_DISCARD_BODY          0x01    /* 0b01 */
#define NGX_HTTP_COPY_DISCARD_CHUNK_BODY    0x02    /* 0b10 */

/* not defined in old nginx (<= 1.2.9) */
#ifndef NGX_HTTP_CONTINUE
#define NGX_HTTP_CONTINUE 100
#endif

static ngx_command_t ngx_http_copy_commands[] = {

    { ngx_string("http_copy"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_1MORE,
      ngx_http_copy,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("http_copy_unparsed_uri"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_copy_loc_conf_t, unparsed_uri),
      NULL },

    { ngx_string("http_copy_keepalive"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_1MORE,
      ngx_http_copy_keepalive,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("http_copy_status"),
      NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
      ngx_http_copy_status,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_http_module_t ngx_http_copy_module_ctx = {
    NULL,                               /* preconfiguration */
    ngx_http_copy_init,                 /* postconfiguration */

    NULL,                               /* create main configuration */
    NULL,                               /* init main configuration */

    NULL,                               /* create server configuration */
    NULL,                               /* merge server configuration */

    ngx_http_copy_create_loc_conf,      /* create location configuration */
    ngx_http_copy_merge_loc_conf        /* merge location configuration */
};


ngx_module_t ngx_http_copy_module = {
    NGX_MODULE_V1,
    &ngx_http_copy_module_ctx,          /* module context */
    ngx_http_copy_commands,             /* module directives */
    NGX_HTTP_MODULE,                    /* module type */
    NULL,                               /* init master */
    NULL,                               /* init module */
    NULL,                               /* init process */
    NULL,                               /* init thread */
    NULL,                               /* exit thread */
    NULL,                               /* exit process */
    NULL,                               /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_input_body_filter_pt ngx_http_next_input_body_filter;

static ngx_http_copy_status_shm_t *copy_status = NULL;

static char ngx_http_copy_version[] = " HTTP/1.0" CRLF;
static char ngx_http_copy_version_11[] = " HTTP/1.1" CRLF;


static ngx_connection_t *
ngx_http_copy_get_keepalive_connection(ngx_http_copy_request_t *cpr)
{
    ngx_http_copy_server_t     *cs = cpr->cs;
    ngx_queue_t                *q;
    ngx_connection_t           *c;

    if (cs->conf->keepalive && ngx_queue_empty(&cs->cache_connections) == 0) {

        /* get connection from connection cache */
        q = ngx_queue_last(&cs->cache_connections);
        c = ngx_queue_data(q, ngx_connection_t, queue);
        ngx_queue_remove(&c->queue);
        cs->cached--;

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, cpr->peer.log, 0,
                       "[copy] keepalive: get no.%d cached connection %p",
                       cs->cached + 1, c);

        /* reinit connection, although ngx_http_copy_connect will init it also */
        c->idle = 0;
        c->data = cpr;
        c->read->handler = NULL;        /* use dummy_handler()? */
        c->write->handler = NULL;

        c->log = cpr->peer.log;
        c->read->log = cpr->peer.log;
        c->write->log = cpr->peer.log;
        c->pool = cpr->pool;

        if (c->read->timer_set) {
            ngx_del_timer(c->read);
        }

        /* assert write timer is deleted */
        if (c->write->timer_set) {
            ngx_del_timer(c->write);
        }

        (void) ngx_atomic_fetch_add(&copy_status->connect_keepalive_count, 1);
        cpr->keepalive_connect = 1;

        /* unnecessary to detect whether cached connection is valid */

        return c;
    }

    return NULL;
}


static void
ngx_http_copy_keepalive_close_handler(ngx_event_t *ev)
{
    ngx_connection_t           *c = ev->data;
    ngx_http_copy_server_t     *cs;
    ngx_int_t                   n;
    char                        buf[1];

    if (ev->timedout) {
        ngx_log_error(NGX_LOG_INFO, ev->log, 0,
                      "[copy] keepalive: cached connection is timed out");
        goto close;
    }

    /*
     * ngx_worker_process_cycle() will set it when receiving EXITING signal.
     * and then it calls c->read->handler(ngx_http_copy_keepalive_close_handler)
     *
     * Note although ngx_drain_connections() could set it, but this connection
     * has been deleted from ngx_cycle->reusable_connections_queue.
     * So ngx_drain_connections() cannot touch this conneciton.
     */
    if (c->close) {
        ngx_log_error(NGX_LOG_INFO, ev->log, 0,
                      "[copy] keepalive: server is exiting");
        goto close;
    }

    /* detect whether backend closed this connection */
    n = recv(c->fd, buf, 1, MSG_PEEK);

    if (n == -1 && ngx_socket_errno == NGX_EAGAIN) {
        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            goto close;
        }

        return;
    }

    /* TCP RESET or TCP HALF CLOSE */
    ngx_log_error(NGX_LOG_INFO, ev->log, 0,
                  "[copy] keepalive: backend closed connection");

close:
    /* TODO: debug cs */
    cs = c->data;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "[copy] keepalive: close no.%d cached connection %p",
                   cs->cached, c);

    /* delete it from connection cache */
    ngx_queue_remove(&c->queue);
    cs->cached--;

    c->pool = NULL;     /* pool in cpr has been destroyed */
    ngx_close_connection(c);
    cs->connection--;
}


static ngx_int_t
ngx_http_copy_try_keepalive_connection(ngx_http_copy_request_t *cpr)
{

    ngx_connection_t           *c = cpr->peer.connection;
    ngx_http_copy_server_t     *cs = cpr->cs;

    if (c == NULL || !cs->conf->keepalive || !cpr->response.keepalive) {
        return 0;
    }

    if (cs->cached >= cs->conf->max_cached) {
        ngx_log_error(NGX_LOG_INFO, ngx_cycle->log, 0,
                      "[copy] keepalive: keepalive connection cache is full");
        return 0;
    }

    if (c->read->eof || c->read->error || c->read->timedout
        || c->write->error || c->write->timedout)
    {
        return 0;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        return 0;
    }

    /* cache valid connections */
    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "[copy] keepalive: save no.%d connection %p",
                   cs->cached + 1, c);

    cpr->peer.connection = NULL;    /* skip ngx_close_connection() */

    /* add to cache: hack c->queue */
    /* delete it from reusable connection list _if necessary_ */
    ngx_reusable_connection(c, 0);
    /* add it to connection cache */
    ngx_queue_insert_head(&cs->cache_connections, &c->queue);
    cs->cached++;

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    ngx_add_timer(c->read, cs->conf->cached_timeout);

    c->write->handler = ngx_http_copy_dummy_handler;
    c->read->handler = ngx_http_copy_keepalive_close_handler;

    c->data = cs;         /* maybe modify cs->connection */
    c->idle = 1;
    c->log = ngx_cycle->log;
    c->read->log = c->log;
    c->write->log = c->log;
    /* c->pool is NULL */

    if (c->read->ready) {
        ngx_http_copy_keepalive_close_handler(c->read);
    }

    return 1;
}


static ngx_int_t
ngx_http_copy_get_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_copy_request_t            *cpr = data;
    ngx_http_copy_server_t             *cs= cpr->cs;

    pc->sockaddr = cs->addrs[0].sockaddr;
    pc->socklen = cs->addrs[0].socklen;
    pc->name = &cs->addrs[0].name;

    pc->connection = ngx_http_copy_get_keepalive_connection(cpr);

    /* no keepalive connection & connections limit */
    if (cs->connection > cs->max_connection && pc->connection == NULL) {
        ngx_log_error(NGX_LOG_INFO, ngx_cycle->log, 0,
                      "[copy] open too many connections");
        return NGX_BUSY;
    }

    return pc->connection ? NGX_DONE : NGX_OK;
}


static void
ngx_http_copy_finalize_request(ngx_http_copy_request_t *cpr)
{
    if (cpr->connect) {
        if (cpr->keepalive_connect) {
            (void) ngx_atomic_fetch_add(&copy_status->active_connect_keepalive,
                                        -1);
        }
        (void) ngx_atomic_fetch_add(&copy_status->active_connect, -1);
    }

    /* finalize before reading whole request body */
    if (cpr->input_body) {
        ngx_log_error(NGX_LOG_INFO, ngx_cycle->log, 0,
                    "[copy] finalize request before reading whole input body");
        ngx_queue_remove(&cpr->queue);
    }

    /* close connection(not cached) */
    if (cpr->peer.connection) {
        cpr->peer.connection->pool = NULL;      /* equal to cpr->pool */
        ngx_close_connection(cpr->peer.connection);
        cpr->cs->connection--;
        cpr->peer.connection = NULL;
    }

    /* free copy request */
    ngx_destroy_pool(cpr->pool);
}


static void
ngx_http_copy_failed_request(ngx_http_copy_request_t *cpr)
{
    ngx_http_copy_server_failed(cpr->cs);
    ngx_http_copy_finalize_request(cpr);
}


static void
ngx_http_copy_next(ngx_http_copy_request_t *cpr)
{
    ngx_http_copy_server_ok(cpr->cs);

    /* serial send request */
    if (cpr->serial) {

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "[copy] serial: no.%d request has been sent",
                       cpr->serial_sent + 1);

        if (++cpr->serial_sent >= cpr->cs->multiple) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "[copy] serial: total requests have been sent");
            goto next;
        }

        if (!cpr->response.keepalive) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "[copy] serial: keepalive is disabled, "
                           "cannot send no.%d request",
                           cpr->serial_sent);
            goto next;
        }

        cpr->request_sent = 0;
        cpr->request_bufs = NULL;
        if (ngx_chain_buf_add_copy(cpr->pool, &cpr->request_bufs,
                                   cpr->serial_request_bufs)
            == NGX_ERROR)
        {
            cpr->serial = 0;
            goto next;
        }

        cpr->discard_body = 0;
        cpr->length = -1;
        cpr->process_header = ngx_http_copy_parse_status_line;
        ngx_memzero(&cpr->response, sizeof(ngx_http_request_t));
        ngx_memzero(&cpr->status, sizeof(ngx_http_status_t));

        if (cpr->buffer != NULL) {
            cpr->buffer->pos = cpr->buffer->start;
            cpr->buffer->last = cpr->buffer->start;
        }

        /* wevent has been deleted, revent will be readded by ngx_http_copy_send_request() */

        (void) ngx_http_copy_send_request(cpr);

        return;
    }

next:
    (void) ngx_http_copy_try_keepalive_connection(cpr);
    ngx_http_copy_finalize_request(cpr);
}


static ngx_int_t
ngx_http_copy_test_connect(ngx_connection_t *c)
{
    int         err;
    socklen_t   len;

    if (c->log->action == NULL) {
        c->log->action = "connecting to backend server";
    }

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT)  {
        if (c->write->pending_eof || c->read->pending_eof) {
            if (c->write->pending_eof) {
                err = c->write->kq_errno;

            } else {
                err = c->read->kq_errno;
            }

            /* ngx_cycle->log->handler dont print 'while %s' */
            ngx_log_error(NGX_LOG_ERR, c->log, err,
                          "[copy] kevent() reported that "
                          "connect() failed while %s",
                          c->log->action);
            return NGX_ERROR;
        }

    }/* else: drop else, let it call getsockopt after kqueue test */

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
            ngx_log_error(NGX_LOG_ERR, c->log, err,
                          "[copy] getsockopt() reported that "
                          "connect() failed while %s",
                          c->log->action);
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static void
ngx_http_copy_dummy_handler(ngx_event_t *ev)
{
    /*
     * When added, wev is triggered at once.
     * So you should use DEBUG log_level to avoid noice.
     */
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0, "[copy] dummy handler");
}


static void
ngx_http_copy_send_request_handler(ngx_event_t *ev)
{
    ngx_connection_t           *c;
    ngx_http_copy_request_t    *cpr;

    c = ev->data;
    cpr = c->data;

    if (c->write->timedout) {

        (void) ngx_atomic_fetch_add(&copy_status->write_timeout, 1);

        ngx_log_error(NGX_LOG_ERR, c->log, 0, "[copy] write timeout while %s",
                      c->log->action);
        ngx_http_copy_failed_request(cpr);
        return;
    }

    (void) ngx_http_copy_send_request(cpr);
}


static void
ngx_http_copy_connected_handler(ngx_event_t *ev)
{
    ngx_connection_t           *c;
    ngx_http_copy_request_t    *cpr;

    c = ev->data;
    cpr = c->data;

    if (c->write->timedout) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0, "[copy] connect timeout while %s",
                      c->log->action);
        ngx_http_copy_failed_request(cpr);
        return;
    }

    ngx_log_error(NGX_LOG_DEBUG, c->log, 0,
                  "[copy] nonblocking connection is established");

    (void) ngx_atomic_fetch_add(&copy_status->connect_count, 1);

    ev->handler = ngx_http_copy_send_request_handler;
    ngx_http_copy_send_request_handler(ev);
}


static void
ngx_http_copy_discard_body(ngx_http_copy_request_t *cpr)
{
    u_char                      buffer[NGX_HTTP_DISCARD_BUFFER_SIZE];
    ngx_connection_t           *c = cpr->peer.connection;
    ssize_t                     n;
    size_t                      size;

    /* recv and discard response body */

    for ( ;; ) {

        /*
         * nginx upstream doesnt do it, which maybe readahead something wrong
         * that client sent
         */
        if (cpr->length == 0) {
            break;
        }

        size = (cpr->length > 0 && cpr->length < NGX_HTTP_DISCARD_BUFFER_SIZE)
             ?  cpr->length
             :  NGX_HTTP_DISCARD_BUFFER_SIZE;

        n = c->recv(c, buffer, size);

        if (n == NGX_AGAIN) {
            break;
        } 

        if (n == NGX_ERROR) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_socket_errno,
                          "[copy] discard body: recv() failed");
            ngx_http_copy_failed_request(cpr);
            return;
        }

        if (n == 0) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "[copy] discard body: backend closed connection");
            ngx_http_copy_failed_request(cpr);
            return;
        }

        /* n > 0 */
        if (cpr->length > 0) {
            cpr->length -= n;

            if (cpr->length < 0) {
                cpr->length = 0;
                ngx_log_error(NGX_LOG_INFO, c->log, 0,
                              "[copy] discard body: response has extra data");
            }
        }

        (void) ngx_atomic_fetch_add(&copy_status->read_bytes, n);
    }

    /* n == NGX_AGAIN */
    if (cpr->length == 0) {
        ngx_http_copy_next(cpr);    /* try keepalive */
        return;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        ngx_http_copy_finalize_request(cpr);
        return;
    }
}


static ngx_int_t
ngx_http_copy_process_one_header(ngx_http_copy_request_t *cpr)
{
    ngx_http_request_t     *r = &cpr->response;
    ngx_keyval_t            h;

    /* assert one header has been parsed */

    h.key.len = r->header_name_end - r->header_name_start;
    h.key.data = r->header_name_start;

    h.value.len = r->header_end - r->header_start;
    h.value.data = r->header_start;

#define header_key_is(s) \
    (h.key.len == sizeof(s) - 1 \
     && ngx_strncmp(h.key.data, (s), sizeof(s) - 1) == 0)

#define header_value_has(s) \
    (ngx_strlcasestrn(h.value.data, h.value.data + h.value.len, \
                      (u_char *)(s), sizeof(s) - 1 - 1/* len - 1 */) \
     != NULL)

    if (header_key_is("Content-Length")) {

        /* Some response of HEAD has "Content-Length" still. */

        if (cpr->length == -1) {
            r->headers_in.content_length_n = ngx_atoof(h.value.data, h.value.len);
            cpr->length = r->headers_in.content_length_n;
        }

    } else if (header_key_is("Connection")) {

        if (header_value_has("close")) {
            r->headers_in.connection_type = NGX_HTTP_CONNECTION_CLOSE;
        }

    } else if (header_key_is("Transfer-Encoding")) {

        if (header_value_has("chunked")) {
            r->chunked = 1;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_copy_parse_header(ngx_http_copy_request_t *cpr)
{
    ngx_http_request_t *r = &cpr->response;
    ngx_int_t           rc;

    /* parse header */

    for ( ;; ) {

        rc = ngx_http_parse_header_line(&cpr->response, cpr->buffer, 1);

        if (rc == NGX_OK) {

            /* process this header */

            (void) ngx_http_copy_process_one_header(cpr);
            continue;
        }

        if (rc == NGX_HTTP_PARSE_HEADER_DONE) {

            /* process response args */

            if (r->chunked) {
                r->headers_in.content_length_n = -1;
                cpr->length = -1;
            }

            if (r->headers_out.status == NGX_HTTP_NO_CONTENT
                || r->headers_out.status == NGX_HTTP_NOT_MODIFIED)
            {
                cpr->length = 0;
            }

            r->keepalive = (r->headers_in.connection_type != NGX_HTTP_CONNECTION_CLOSE);

            return NGX_OK;
        }

        /* rc == NGX_ERROR || rc == NGX_AGAIN */

        return rc;
    }
}


static ngx_int_t
ngx_http_copy_parse_status_line(ngx_http_copy_request_t *cpr)
{
    ngx_int_t   rc;

    /* process status line */

    rc = ngx_http_parse_status_line(&cpr->response, cpr->buffer, &cpr->status);

    if (rc == NGX_AGAIN) {
        return rc;
    }

    if (rc == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "[copy] HTTP response: invalid status line");
        return rc;
    }

    /* rc == NGX_OK */

    cpr->response.headers_out.status = cpr->status.code;
    cpr->response.headers_out.status_line.len = cpr->status.end - cpr->status.start;
    cpr->response.headers_out.status_line.data = cpr->status.start;

    if (cpr->status.http_version < NGX_HTTP_VERSION_11) {
        cpr->response.headers_in.connection_type = NGX_HTTP_CONNECTION_CLOSE;
    }

    cpr->process_header = ngx_http_copy_parse_header;

    return ngx_http_copy_parse_header(cpr);
}


static ngx_int_t
ngx_http_copy_parse_chunked(ngx_http_copy_chunk_t *ctx, ngx_buf_t *buf)
{
    u_char                     *pos, ch, c;
    ngx_int_t                   rc;

    enum {
        sw_chunk_start = 0,
        sw_chunk_size,
        sw_chunk_extension,
        sw_chunk_extension_almost_done,
        sw_chunk_data,
        sw_after_data,
        sw_after_data_almost_done,
        sw_last_chunk_extension,
        sw_last_chunk_extension_almost_done,
        sw_trailer,
        sw_trailer_almost_done,
        sw_trailer_header,
        sw_trailer_header_almost_done
    } state;

    state = ctx->state;

    if (state == sw_chunk_data && ctx->size == 0) {
        state = sw_after_data;
    }

    rc = NGX_AGAIN;

    for (pos = buf->pos; pos < buf->last; pos++) {

        ch = *pos;

        switch (state) {

        case sw_chunk_start:
            if (ch >= '0' && ch <= '9') {
                state = sw_chunk_size;
                ctx->size = ch - '0';
                break;
            }

            c = (u_char) (ch | 0x20);

            if (c >= 'a' && c <= 'f') {
                state = sw_chunk_size;
                ctx->size = c - 'a' + 10;
                break;
            }

            goto invalid;

        case sw_chunk_size:
            if (ch >= '0' && ch <= '9') {
                ctx->size = ctx->size * 16 + (ch - '0');
                break;
            }

            c = (u_char) (ch | 0x20);

            if (c >= 'a' && c <= 'f') {
                ctx->size = ctx->size * 16 + (c - 'a' + 10);
                break;
            }

            if (ctx->size == 0) {

                switch (ch) {
                case CR:
                    state = sw_last_chunk_extension_almost_done;
                    break;
                case LF:
                    state = sw_trailer;
                    break;
                case ';':
                case ' ':
                case '\t':
                    state = sw_last_chunk_extension;
                    break;
                default:
                    goto invalid;
                }

                break;
            }

            switch (ch) {
            case CR:
                state = sw_chunk_extension_almost_done;
                break;
            case LF:
                state = sw_chunk_data;
                break;
            case ';':
            case ' ':
            case '\t':
                state = sw_chunk_extension;
                break;
            default:
                goto invalid;
            }

            break;

        case sw_chunk_extension:
            switch (ch) {
            case CR:
                state = sw_chunk_extension_almost_done;
                break;
            case LF:
                state = sw_chunk_data;
            }
            break;

        case sw_chunk_extension_almost_done:
            if (ch == LF) {
                state = sw_chunk_data;
                break;
            }
            goto invalid;

        case sw_chunk_data:
            rc = NGX_OK;
            goto data;

        case sw_after_data:
            switch (ch) {
            case CR:
                state = sw_after_data_almost_done;
                break;
            case LF:
                state = sw_chunk_start;
            }
            break;

        case sw_after_data_almost_done:
            if (ch == LF) {
                state = sw_chunk_start;
                break;
            }
            goto invalid;

        case sw_last_chunk_extension:
            switch (ch) {
            case CR:
                state = sw_last_chunk_extension_almost_done;
                break;
            case LF:
                state = sw_trailer;
            }
            break;

        case sw_last_chunk_extension_almost_done:
            if (ch == LF) {
                state = sw_trailer;
                break;
            }
            goto invalid;

        case sw_trailer:
            switch (ch) {
            case CR:
                state = sw_trailer_almost_done;
                break;
            case LF:
                goto done;
            default:
                state = sw_trailer_header;
            }
            break;

        case sw_trailer_almost_done:
            if (ch == LF) {
                goto done;
            }
            goto invalid;

        case sw_trailer_header:
            switch (ch) {
            case CR:
                state = sw_trailer_header_almost_done;
                break;
            case LF:
                state = sw_trailer;
            }
            break;

        case sw_trailer_header_almost_done:
            if (ch == LF) {
                state = sw_trailer;
                break;
            }
            goto invalid;

        }
    }

data:

    ctx->state = state;
    buf->pos = pos;

    return rc;

done:

    return NGX_DONE;

invalid:

    return NGX_ERROR;
}


static void
ngx_http_copy_discard_chunk_body(ngx_http_copy_request_t *cpr)
{
    ngx_connection_t           *c = cpr->peer.connection;
    ngx_buf_t                  *buf;
    ngx_http_copy_chunk_t      *chunk;
    ngx_int_t                   rc;
    ssize_t                     n;

    buf = cpr->buffer;
    chunk = cpr->chunk;

    for ( ;; ) {

        /* read response */
        if (buf->pos >= buf->last) {

            buf->pos = buf->start;
            buf->last = buf->start;

            n = c->recv(c, buf->pos, buf->end - buf->start);

            if (n == NGX_AGAIN) {
                if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
                    ngx_http_copy_finalize_request(cpr);
                    return;
                }
                return;
            } 

            if (n == NGX_ERROR) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_socket_errno,
                              "[copy] discard chunk body: recv() failed");
                ngx_http_copy_failed_request(cpr);
                return;
            }

            if (n == 0) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                       "[copy] discard chunk body: backend closed connection");
                ngx_http_copy_failed_request(cpr);
                return;
            }

            /* n > 0 */
            buf->last = buf->pos + n;
        }

        /* discard chunk */
        if (cpr->length > 0) {

            if (cpr->length > buf->last - buf->pos) {
                cpr->length -= buf->last - buf->pos;
                buf->pos = buf->last;
            } else {
                buf->pos += cpr->length;     /* maybe buf->pos == buf->last */
                cpr->length = 0;
            }

            if (cpr->length > 0 || buf->pos == buf->last) {
                continue;
            }
        }

        /* parse chunk */
        rc = ngx_http_copy_parse_chunked(cpr->chunk, buf);

        if (rc == NGX_AGAIN) {
            /* continue to read more data */
            continue;
        }

        if (rc == NGX_OK) {
            /* chunk is parsed, continue to discard chunk body */
            (void) ngx_atomic_fetch_add(&copy_status->read_bytes, chunk->size);
            (void) ngx_atomic_fetch_add(&copy_status->read_chunk_bytes, chunk->size);

            cpr->length = chunk->size;  /* length: size of current chunk */
            chunk->size = 0;            /* chunk->state will goto sw_after_data */

            continue;
        }

        if (rc == NGX_DONE) {
            /* a whole response is parsed */
            ngx_http_copy_next(cpr);    /* try keepalive */
            return;
        }

        /* rc == NGX_ERROR, invalid response */
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "[copy] discard chunk body: "
                      "backend sent invalid chunked response");
        ngx_http_copy_finalize_request(cpr);
        return;
    }
}


static void
ngx_http_copy_discard_response(ngx_http_copy_request_t *cpr)
{
    ngx_int_t                   n, rc;
    ngx_connection_t           *c = cpr->peer.connection;

    c->log->action = "discarding response";
    if (!cpr->request_sent && ngx_http_copy_test_connect(c) != NGX_OK) {
        ngx_http_copy_failed_request(cpr);
        return;
    }

    if (cpr->discard_body == NGX_HTTP_COPY_DISCARD_BODY) {
        ngx_http_copy_discard_body(cpr);
        return;
    } else if (cpr->discard_body == NGX_HTTP_COPY_DISCARD_CHUNK_BODY) {
        ngx_http_copy_discard_chunk_body(cpr);
        return;
    }

    /* create buffer for response, detect for reenterring */
    if (cpr->buffer == NULL) {
        cpr->buffer = ngx_create_temp_buf(cpr->pool, 4096);
        if (cpr->buffer == NULL) {
            ngx_http_copy_finalize_request(cpr);
            return;
        }
    }

    /* recv and parse response header */

    for ( ;; ) {

        /* read response */

        n = c->recv(c, cpr->buffer->last, cpr->buffer->end - cpr->buffer->last);

        if (n == NGX_AGAIN) {
            if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
                ngx_http_copy_finalize_request(cpr);
                return;
            }
            return;
        } 

        /* TODO: status counting */
        if (n == NGX_ERROR) {
            /* if worker_connections is too small, it maybe come here */
            ngx_log_error(NGX_LOG_ERR, c->log, ngx_socket_errno,
                          "[copy] discard response: recv() failed");
            ngx_http_copy_failed_request(cpr);
            return;
        } 

        if (n == 0) {
            ngx_log_error(NGX_LOG_ERR, c->log, 0,
                          "[copy] discard response: backend closed connection");
            ngx_http_copy_failed_request(cpr);
            return;
        }

        /* n > 0: parse response */
        cpr->buffer->last += n;

    parse_header:

        rc = cpr->process_header(cpr);

        if (rc == NGX_ERROR) {
            ngx_http_copy_finalize_request(cpr);
            return;
        }

        if (rc == NGX_OK) {

            /* ignore the "100 Continue" response */

            if (cpr->status.code == NGX_HTTP_CONTINUE) {
                cpr->length = -1;   /* response length */
                cpr->process_header = ngx_http_copy_parse_status_line;
                ngx_memset(&cpr->status, 0x0, sizeof(ngx_http_status_t));
                ngx_memset(&cpr->response, 0x0, sizeof(ngx_http_request_t));
                goto parse_header;
            }

            (void) ngx_atomic_fetch_add(&copy_status->response_count, 1);

            if (cpr->status.code >= NGX_HTTP_OK
                && cpr->status.code < NGX_HTTP_BAD_REQUEST)
            {
                (void) ngx_atomic_fetch_add(&copy_status->response_ok_count, 1);

            } else {
                (void) ngx_atomic_fetch_add(&copy_status->response_err_count, 1);
            }

            /* chunked response */
            if (cpr->response.chunked) {

                cpr->chunk = ngx_pcalloc(cpr->pool, sizeof(ngx_http_copy_chunk_t));
                if (cpr->chunk == NULL) {
                    ngx_http_copy_finalize_request(cpr);
                    return;
                }

                cpr->discard_body = NGX_HTTP_COPY_DISCARD_CHUNK_BODY;
                ngx_http_copy_discard_chunk_body(cpr);
                return;
            }

            /* discard data left in buffer */
            n = cpr->buffer->last - cpr->buffer->pos;
            if (n > 0) {

                (void) ngx_atomic_fetch_add(&copy_status->read_bytes, n);
                cpr->buffer->pos = cpr->buffer->last;
                if (cpr->length > 0) {
                    cpr->length -= n;

                    if (cpr->length < 0) {
                        cpr->length = 0;
                        ngx_log_error(NGX_LOG_INFO, c->log, 0,
                           "[copy] discard response: response has extra data");
                    }
                }
            }

            /* discard response body(headers + body) */
            cpr->discard_body = NGX_HTTP_COPY_DISCARD_BODY;
            ngx_http_copy_discard_body(cpr);

            return;
        }

        /* rc == NGX_AGAIN: read again and parse */

        if (cpr->buffer->last == cpr->buffer->end) {
            ngx_log_error(NGX_LOG_ERR, c->log, 0,
                          "[copy] response header is too big ( > 4096 bytes)");
            ngx_http_copy_finalize_request(cpr);
            return;
        }
    }
}


static void
ngx_http_copy_recv_response_handler(ngx_event_t *ev)
{
    ngx_connection_t           *c;
    ngx_http_copy_request_t    *cpr;

    c = ev->data;
    cpr = c->data;

    if (c->read->timedout) {

        (void) ngx_atomic_fetch_add(&copy_status->read_timeout, 1);

        if (cpr->discard_body == NGX_HTTP_COPY_DISCARD_BODY) {
            ngx_log_error(NGX_LOG_ERR, c->log, 0,
                          "[copy] discard body: read timedout");

        } else if (cpr->discard_body == NGX_HTTP_COPY_DISCARD_CHUNK_BODY) {
            ngx_log_error(NGX_LOG_ERR, c->log, 0,
                          "[copy] discard chunk: read timedout");

        } else if (cpr->buffer == NULL) {
            ngx_log_error(NGX_LOG_ERR, c->log, 0,
                     "[copy] recv response: timedout. No data has been read.");

        } else {
            if (cpr->process_header == ngx_http_copy_parse_status_line) {
                ngx_log_error(NGX_LOG_ERR, c->log, 0,
                              "[copy] parse status line: read timedout.");

            } else {
                ngx_log_error(NGX_LOG_ERR, c->log, 0,
                              "[copy] parse headers: read timedout");
            }

            ngx_log_error(NGX_LOG_INFO, c->log, 0,
                          "[copy] read %d bytes data:\"%*s\"",
                          cpr->buffer->last - cpr->buffer->start,
                          cpr->buffer->last - cpr->buffer->start,
                          cpr->buffer->start);

        }

        ngx_http_copy_failed_request(cpr);
        return;
    }

    ngx_http_copy_discard_response(cpr);
}


static ngx_int_t
ngx_http_copy_send_request(ngx_http_copy_request_t *cpr)
{
    ngx_int_t                   rc;
    ngx_connection_t           *c;

    c = cpr->peer.connection;

    if (!cpr->request_sent && ngx_http_copy_test_connect(c) != NGX_OK) {
        ngx_http_copy_failed_request(cpr);
        return NGX_ERROR;
    }

    rc = ngx_output_chain(&cpr->output, cpr->request_sent ? NULL : cpr->request_bufs);

    cpr->request_sent = 1;

    if (rc == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0, "[copy] cannot send request to backend");
        ngx_http_copy_failed_request(cpr);
        return NGX_ERROR;
    }

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    if (rc == NGX_AGAIN) {
        ngx_add_timer(c->write, 5000); /* TODO: configure this value */

        if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
            ngx_http_copy_finalize_request(cpr);
            return NGX_ERROR;
        }
        return NGX_OK;
    }

    /* rc == NGX_OK */
    if (cpr->input_body) {
        c->log->action = "sending request(input body)";
        ngx_add_timer(c->write, 5000); /* TODO: configure this value */
        return NGX_OK;
    }

    (void) ngx_atomic_fetch_add(&copy_status->request_count, 1);

    ngx_add_timer(c->read, 5000);      /* TODO: configure this value */
    c->log->action = "reading response";

    c->write->handler = ngx_http_copy_dummy_handler;

    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
        ngx_http_copy_finalize_request(cpr);
        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_chain_buf_add_copy(ngx_pool_t *pool, ngx_chain_t **chain, ngx_chain_t *in)
{
    ngx_chain_t    *cl, **ll;

    ll = chain;

    for (cl = *chain; cl; cl = cl->next) {
        ll = &cl->next;
    }

    while (in) {
        cl = ngx_alloc_chain_link(pool);
        if (cl == NULL) {
            return NGX_ERROR;
        }

        cl->buf = ngx_calloc_buf(pool);
        if (cl->buf == NULL) {
            return NGX_ERROR;
        }
        *cl->buf = *in->buf;

        *ll = cl;
        ll = &cl->next;
        in = in->next;
    }

    *ll = NULL;

    return NGX_OK;
}


static ngx_int_t
ngx_http_copy_request(ngx_http_copy_request_t *cpr)
{
    ngx_http_request_t         *r = cpr->r; /* assert cpr->r != NULL*/

    ngx_buf_t                  *b;
    ngx_chain_t                *cl;
    ngx_list_part_t            *part;
    ngx_table_elt_t            *header;

    ngx_uint_t                  i, force_keepalive, unparsed_uri;
    size_t                      len;

    /* force to use HTTP/1.1 and delete "Connection: ..." header */
    force_keepalive = cpr->cs->conf->force_keepalive;
    unparsed_uri = cpr->cs->conf->unparsed_uri;

    /* calculate request(excluding body) length */
    if (unparsed_uri) {
        len = r->method_name.len + 1 + r->unparsed_uri.len;

    } else {
        len = r->method_name.len + 1 + r->uri.len;

        if (r->args.len > 0) {
            len += 1 + r->args.len;
        }
    }
    /* http version length */
    if (force_keepalive || r->http_version == NGX_HTTP_VERSION_11) {
        len += sizeof(ngx_http_copy_version_11) - 1;
    } else {
        len += sizeof(ngx_http_copy_version) - 1;
    }

    /* header length */

    part = &r->headers_in.headers.part;
    header = part->elts;

    for (i = 0; /* void */; i++) {
        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            header = part->elts;
            i = 0;
        }

        if (force_keepalive
            && header[i].key.len == 10
            && ngx_strncmp(header[i].key.data, "Connection", 10) == 0)
        {
            continue;
        }

        len += header[i].key.len + sizeof(": ") - 1
            + header[i].value.len + sizeof(CRLF) - 1;
    }

    len += 2;   /* header end "\r\n" */

    /* copy request */

    b = ngx_create_temp_buf(cpr->pool, len);
    if (b == NULL) {
        return NGX_ERROR;
    }

    cl = ngx_alloc_chain_link(cpr->pool);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    cl->buf = b;

    /* copy request line */

    b->last = ngx_copy(b->last, r->method_name.data,
                       r->method_name.len + 1 /* space char */);

    if (unparsed_uri) {
        b->last = ngx_copy(b->last, r->unparsed_uri.data, r->unparsed_uri.len);

    } else {
        b->last = ngx_copy(b->last, r->uri.data, r->uri.len);

        if (r->args.len > 0) {
            *b->last++ = '?';
            b->last = ngx_copy(b->last, r->args.data, r->args.len);
        }
    }

    if (force_keepalive || r->http_version == NGX_HTTP_VERSION_11) {
        b->last = ngx_cpymem(b->last, ngx_http_copy_version_11,
                sizeof(ngx_http_copy_version_11) - 1);
    } else {
        b->last = ngx_cpymem(b->last, ngx_http_copy_version,
                sizeof(ngx_http_copy_version) - 1);
    }

    /* copy headers */

    for (i = 0; /* void */; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            header = part->elts;
            i = 0;
        }

        if (force_keepalive
            && header[i].key.len == 10
            && ngx_strncmp(header[i].key.data, "Connection", 10) == 0)
        {
            continue;
        }

        b->last = ngx_copy(b->last, header[i].key.data, header[i].key.len);

        *b->last++ = ':'; *b->last++ = ' ';

        b->last = ngx_copy(b->last, header[i].value.data,
                header[i].value.len);

        *b->last++ = CR; *b->last++ = LF;
    }

    /* add "\r\n" at the header end */
    *b->last++ = CR; *b->last++ = LF;

    /* copy body */

    cpr->request_bufs = cl;     /* cl -> status line & headers */

    b->flush = 1;
    cl->next = NULL;

    if (cpr->serial) {
        if (ngx_chain_buf_add_copy(cpr->pool, &cpr->serial_request_bufs,
                                   cpr->request_bufs)
            == NGX_ERROR)
        {
            cpr->serial = 0;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_copy_connect(ngx_http_copy_request_t *cpr)
{
    ngx_http_copy_server_t     *cs = cpr->cs;
    ngx_peer_connection_t      *pc;
    ngx_connection_t           *c;              /* connection to backend */
    ngx_int_t                   rc;

    pc = &cpr->peer;
    pc->log = ngx_cycle->log;
    pc->data = cpr;
    pc->get = ngx_http_copy_get_peer;           /* get conn from cache if keepalive is on */

    rc = ngx_event_connect_peer(pc);

    if (rc == NGX_ERROR || rc == NGX_DECLINED || rc == NGX_BUSY) {
        /*
         * NGX_DECLINED: get new peer, but cannot connect it
         * NGX_BUSY: pc->get() return this value because of max_connections limit.
         * NGX_ERROR: cannot get peer or syscalls error
         */
        if (rc == NGX_DECLINED) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "[copy] cannot connect backend: connect() returns error");

        } else if (rc == NGX_BUSY) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                  "[copy] cannot connect backend: too many worker connections");

        } else {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "[copy] cannot connect backend");
        }

        return NGX_ERROR;
    }

    /* rc == NGX_OK || rc == NGX_DONE (keepalive) || rc == NGX_AGAIN */
    cpr->connect = 1;
    (void) ngx_atomic_fetch_add(&copy_status->active_connect, 1);

    if (rc != NGX_DONE) {
        cs->connection++;
    } else {
        (void) ngx_atomic_fetch_add(&copy_status->active_connect_keepalive, 1);
    }

    c = pc->connection;
    c->data = cpr;
    c->write->handler = ngx_http_copy_send_request_handler;
    c->read->handler = ngx_http_copy_recv_response_handler;
    c->sendfile &= cpr->r->connection->sendfile;

    c->pool = cpr->pool;
    c->log = ngx_cycle->log;
    c->read->log = c->log;
    c->write->log = c->log;

    if (rc == NGX_AGAIN) {
        /*
         * ngx_event_connect_peer will add write event when rc == NGX_AGAIN
         * connected handler: log connect_count and send request
         */
        c->log->action = "connecting to backend server";
        c->write->handler = ngx_http_copy_connected_handler;
        ngx_add_timer(c->write, 5000);

    } else {
        c->log->action = "sending request";
    }

    return rc;
}


static void
ngx_http_copy_cleanup(void *data)
{
    ngx_queue_t                *copy_request, *q;
    ngx_http_copy_request_t    *cpr;

    copy_request = data;

    while (!ngx_queue_empty(copy_request)) {
        q = ngx_queue_last(copy_request);
        cpr = ngx_queue_data(q, ngx_http_copy_request_t, queue);

        ngx_log_error(NGX_LOG_INFO, cpr->r->connection->log, 0,
                "[copy] cleanup request \"%V\" before reading whole input body",
                &cpr->r->uri);

        cpr->r = NULL;
        cpr->input_body = 0;
        ngx_queue_remove(&cpr->queue);
    }
}


static ngx_int_t
ngx_http_copy_init_request(ngx_http_copy_request_t *cpr)
{
    ngx_http_core_loc_conf_t   *clcf;
    ngx_int_t                   rc;

    /* connect backend server */
    rc = ngx_http_copy_connect(cpr);
    if (rc == NGX_ERROR) {
        ngx_http_copy_failed_request(cpr);
        return NGX_ERROR;
    }

    /* copy request */
    if (ngx_http_copy_request(cpr) == NGX_ERROR) {
        ngx_http_copy_finalize_request(cpr);
        return NGX_ERROR;
    }

    /* set output chain context */

    clcf = ngx_http_get_module_loc_conf(cpr->r, ngx_http_core_module);
    cpr->output.alignment = clcf->directio_alignment;
    cpr->output.pool = cpr->pool;
    cpr->output.bufs.num = 1;
    cpr->output.bufs.size = clcf->client_body_buffer_size;
    cpr->output.output_filter = ngx_chain_writer;
    cpr->output.filter_ctx = &cpr->writer;

    /* writer.out .. *writer.last are data waiting to send */
    cpr->writer.out = NULL;
    cpr->writer.last = &cpr->writer.out;
    cpr->writer.connection = cpr->peer.connection;
    cpr->writer.limit = 0;
    cpr->writer.pool = cpr->pool;

    cpr->request_sent = 0;

    if (rc == NGX_AGAIN) {
        return NGX_OK;
    }

    /* send request, rc == NGX_DONE || rc == NGX_OK */
    return ngx_http_copy_send_request(cpr);
}


static ngx_http_copy_request_t *
ngx_http_copy_create_request(ngx_http_request_t *r, ngx_http_copy_server_t *cs)
{
    ngx_pool_t                 *pool;
    ngx_http_copy_request_t    *cpr;
    ngx_http_copy_ctx_t        *ctx;

    /* create request (copied from @r) */
    pool = ngx_create_pool(512, ngx_cycle->log);
    if (pool == NULL) {
        return NULL;
    }

    cpr = ngx_pcalloc(pool, sizeof(ngx_http_copy_request_t));
    if (cpr == NULL) {
        ngx_destroy_pool(pool);
        return NULL;
    }

    cpr->pool = pool;
    cpr->r = r;         /* can only read r, shouldnt modify r */
    cpr->cs = cs; /* used when response is sent back */
    cpr->length = -1;   /* response length */
    cpr->process_header = ngx_http_copy_parse_status_line;
    ngx_queue_init(&cpr->queue);

    if (cs->serial && r->method == NGX_HTTP_GET) {
        cpr->serial = 1;
    }

    /* Reply to HEAD requests has no content. */
    if (r->method == NGX_HTTP_HEAD) {
        cpr->length = 0;
    }

    /* handle input body */
    if ((r->method == NGX_HTTP_PUT || r->method == NGX_HTTP_POST)
        && r->headers_in.content_length_n > 0)
    {
        cpr->input_body = 1;
        cpr->input_body_rest = r->headers_in.content_length_n;
        ctx = ngx_http_get_module_ctx(cpr->r, ngx_http_copy_module);
        ngx_queue_insert_head(&ctx->copy_request, &cpr->queue);
    }

    return cpr;
}


static void
ngx_http_copy_init_requests(ngx_http_request_t *r, ngx_http_copy_server_t *cs)
{
    ngx_http_copy_request_t    *cpr;    /* request copied from @r */
    ngx_http_copy_ctx_t        *ctx;
    ngx_http_cleanup_t         *cln;
    ngx_uint_t                  i;

    /* check whether backend has failed */
    if (cs->max_fails && cs->fails >= cs->max_fails) {

        time_t now = ngx_time();

        if (now - cs->checked <= cs->fail_timeout || cs->fail_retries == 0) {
            ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                          "[copy] skip copying "
                          "because backend \"%V\" has failed",
                          &cs->addrs->name);
            return;
        }

        cs->fail_retries--;
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "[copy] retry to connect, left %d retries",
                      cs->fail_retries);
    }

    /* handle input body */
    if ((r->method == NGX_HTTP_PUT || r->method == NGX_HTTP_POST)
        && (r->headers_in.content_length_n > 0))
    {
        /* init copy context */
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_copy_ctx_t));
        if (ctx == NULL) {
            return;
        }
        ngx_queue_init(&ctx->copy_request);
        ngx_http_set_ctx(r, ctx, ngx_http_copy_module);

        /* add cleanup handler */
        cln = ngx_http_cleanup_add(r, 0 /* zero data size*/);
        if (cln == NULL) {
            return;
        }
        cln->handler = ngx_http_copy_cleanup;   /* called in ngx_http_free_request() */
        cln->data = &ctx->copy_request;
    }

    for (i = 0; i < cs->multiple; i++) {

        /* create request (copied from @r) */
        cpr = ngx_http_copy_create_request(r, cs);
        if (cpr == NULL) {
            break;
        }

        if (ngx_http_copy_init_request(cpr) == NGX_ERROR) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "[copy] should send %d requests, only complete %d requests",
                    cs->multiple, i);
            break;
        }

        if (cpr->serial) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "[copy] serial: has prepared first copied request");
            break;
        }
    }
}


static ngx_int_t
ngx_http_copy_handler(ngx_http_request_t *r)
{
    ngx_http_copy_loc_conf_t   *cplcf;
    ngx_http_copy_server_t     *cs;
    ngx_http_variable_value_t  *vv;
    ngx_uint_t                  i;

    cplcf = ngx_http_get_module_loc_conf(r, ngx_http_copy_module);

    if (cplcf->servers) {

        cs = cplcf->servers->elts;

        for (i = 0; i < cplcf->servers->nelts; i++) {

            /* check switch_on parameter */
            if (cs[i].switch_index != -1) {
                vv = ngx_http_get_indexed_variable(r, cs[i].switch_index);
                if (vv == NULL || vv->valid == 0 || vv->not_found == 1) {
                    continue;
                }

                if (vv->len != 4
                    || ngx_strncasecmp(vv->data, (u_char *) "true", 4))
                {
                    continue;
                }
            }

            cs[i].conf = cplcf;

            ngx_http_copy_init_requests(r, &cs[i]);
        }
    }

    /* let original request continue to run */

    return NGX_DECLINED;
}


static char *
ngx_http_copy_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_copy_loc_conf_t *prev = parent;
    ngx_http_copy_loc_conf_t *conf = child;

    ngx_conf_merge_ptr_value(conf->servers, prev->servers, NULL);
    ngx_conf_merge_value(conf->max_cached, prev->max_cached, (ngx_int_t) 65535);
    ngx_conf_merge_msec_value(conf->cached_timeout, prev->cached_timeout, 60000);
    ngx_conf_merge_value(conf->keepalive, prev->keepalive, 1);
    ngx_conf_merge_value(conf->force_keepalive, prev->force_keepalive, 1);
    ngx_conf_merge_value(conf->unparsed_uri, prev->unparsed_uri, 1);

    return NGX_CONF_OK;
}


static void *
ngx_http_copy_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_copy_loc_conf_t   *cplcf;

    cplcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_copy_loc_conf_t));

    if (cplcf == NULL) {
        return NULL;
    }

    cplcf->servers = NGX_CONF_UNSET_PTR;
    cplcf->max_cached = NGX_CONF_UNSET;
    cplcf->cached_timeout = NGX_CONF_UNSET_MSEC;
    cplcf->keepalive = NGX_CONF_UNSET;
    cplcf->force_keepalive = NGX_CONF_UNSET;
    cplcf->unparsed_uri = NGX_CONF_UNSET;

    return cplcf;
}


static char *
ngx_http_copy_keepalive(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_copy_loc_conf_t   *cplcf = conf;
    ngx_str_t                  *value, time;
    ngx_int_t                   max_cached;
    ngx_uint_t                  i;

    if (cplcf->keepalive != NGX_CONF_UNSET) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (ngx_strcasecmp(value[1].data, (u_char *) "off") == 0) {
        cplcf->keepalive = 0;
        cplcf->force_keepalive = 0;
        return NGX_CONF_OK;
    }

    if (ngx_strcasecmp(value[1].data, (u_char *) "on") == 0) {
        i = 2;
    } else {
        i = 1;
    }

    max_cached = 65535;     /* unlimit by default */

    for (; i < cf->args->nelts; i++) {

        if (ngx_strncmp(value[i].data, "connections=", 12) == 0) {

            max_cached = ngx_atoi(&value[i].data[12], value[i].len - 12);

            if (max_cached == NGX_ERROR || max_cached <= 0 || max_cached > 65535)
            {
                goto invalid;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "timeout=", 8) == 0) {

            time.data = &value[i].data[8];
            time.len = value[i].len - 8;
            cplcf->cached_timeout = ngx_parse_time(&time, 0);

            if (cplcf->cached_timeout == (ngx_msec_t)NGX_ERROR)
            {
                goto invalid;
            }

            continue;
        }

        if (value[i].len == 9
            && ngx_strncmp(value[i].data, "force_off", 9) == 0)
        {
            cplcf->force_keepalive = 0;
            continue;
        }

        goto invalid;
    }

    cplcf->keepalive = 1;
    cplcf->max_cached = max_cached;

    return NGX_CONF_OK;

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static char *
ngx_http_copy(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_copy_loc_conf_t   *cplcf = conf;

    ngx_http_copy_server_t     *cs;
    ngx_str_t                  *value, s, switchon;
    ngx_url_t                   u;
    ngx_int_t                   multiple, max_connection, switch_index;
    ngx_flag_t                  serial;
    ngx_int_t                   max_fails;
    time_t                      fail_timeout;
    ngx_uint_t                  i;

    if (cplcf->servers == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"http_copy off\" conflicts with "
                           "other \"http_copy ...\" directives.");
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;

    if (ngx_strcasecmp(value[1].data, (u_char *) "off") == 0) {
        if (cplcf->servers != NULL && cplcf->servers != NGX_CONF_UNSET_PTR) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "\"http_copy off\" conflicts with "
                               "other \"http_copy ...\" directives.");
            return NGX_CONF_ERROR;
        }
        cplcf->servers = NULL;
        return NGX_CONF_OK;
    }

    /* parse url */
    ngx_memzero(&u, sizeof(ngx_url_t));
    u.url = value[1];
    u.default_port = 80;

    if (ngx_parse_url(cf->pool, &u) != NGX_OK) {
        if (u.err) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "%s in location \"%V\"", u.err, &u.url);
        }

        return NGX_CONF_ERROR;
    }

    /* parse other arguments */
    multiple = 1;           /* 1x by default */
    max_connection = 65535;
    switch_index = -1;
    serial = 0;
    max_fails = 5;
    fail_timeout = 10;

    for (i = 2; i < cf->args->nelts; i++) {

        if (ngx_strncmp(value[i].data, "multiple=", 9) == 0) {

            multiple = ngx_atoi(&value[i].data[9], value[i].len - 9);

            if (multiple == NGX_ERROR || multiple <= 0 || multiple > 10240) {
                goto invalid;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "connections=", 12) == 0) {

            max_connection = ngx_atoi(&value[i].data[12], value[i].len - 12);

            if (max_connection == NGX_ERROR
                || max_connection <= 0 || max_connection > 65535)
            {
                goto invalid;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "max_fails=", 10) == 0) {

            max_fails = ngx_atoi(&value[i].data[10], value[i].len - 10);

            if (max_fails == NGX_ERROR) {
                goto invalid;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "fail_timeout=", 13) == 0) {
            s.len = value[i].len - 13;
            s.data = &value[i].data[13];

            fail_timeout = ngx_parse_time(&s, 1);

            if (fail_timeout == (time_t) NGX_ERROR) {
                goto invalid;
            }

            continue;
        }

        if (value[i].len == 6 && ngx_strncmp(value[i].data, "serial", 6) == 0) {
            serial = 1;
            continue;
        }

        if (ngx_strncmp(value[i].data, "switch_on=", 10) == 0) {

            switchon.data = &value[i].data[10];
            switchon.len = value[i].len - 10;

            if (switchon.data[0] == '$') {
                switchon.data++;
                switchon.len--;
            }

            switch_index = ngx_http_get_variable_index(cf, &switchon);
            if (switch_index == NGX_ERROR) {
                goto invalid;
            }

            continue;
        }

        goto invalid;
    }

    if (cplcf->servers == NGX_CONF_UNSET_PTR) {
        cplcf->servers = ngx_array_create(cf->pool, 4,
                                          sizeof(ngx_http_copy_server_t));
        if (cplcf->servers == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    cs = ngx_array_push(cplcf->servers);
    if (cs == NULL) {
        return NGX_CONF_ERROR;
    }

    /*
     * The fields as following are inited in ngx_http_copy_merge_loc_conf().
     *  .max_cached
     *  .cached_timeout
     *  .keepalive
     *  .force_keepalive
     */

    cs->addrs = u.addrs;
    cs->naddrs = u.naddrs;
    cs->multiple = multiple;
    cs->max_connection = max_connection;
    cs->switch_index = switch_index;
    cs->serial = (multiple == 1) ? 0 : serial;
    cs->max_fails = max_fails;
    cs->fail_timeout = fail_timeout;
    cs->fails = 0;
    cs->fail_retries = 0;
    cs->checked = 0;
    cs->cached = 0;
    cs->connection = 0;
    cs->conf = NULL;
    ngx_queue_init(&cs->cache_connections);

    return ngx_http_copy_init_shm(cf);

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static ngx_int_t
ngx_http_copy_status_handler(ngx_http_request_t *r)
{
    size_t                          size;
    ngx_int_t                       rc;
    ngx_chain_t                     out;
    ngx_buf_t                      *b;
    ngx_http_copy_status_shm_t     *status_shm;
    ngx_atomic_int_t                rq, rp, ok, er, cn, kp, rb, cb, rt, wt;
    ngx_atomic_int_t                acn, akp;


    if (copy_status == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (r->method != NGX_HTTP_GET && r->method != NGX_HTTP_HEAD) {
        return NGX_HTTP_NOT_ALLOWED;
    }

    rc= ngx_http_discard_request_body(r);

    if (rc != NGX_OK) {
        return rc;
    }

    ngx_str_set(&r->headers_out.content_type, "text/plain");

    if (r->method == NGX_HTTP_HEAD) {
        r->headers_out.status = NGX_HTTP_OK;

        rc = ngx_http_send_header(r);
        if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
            return rc;
        }
    }

    /* get status info */
    status_shm = copy_status;

    rq = status_shm->request_count;
    rp = status_shm->response_count;
    ok = status_shm->response_ok_count;
    er = status_shm->response_err_count;
    cn = status_shm->connect_count;
    kp = status_shm->connect_keepalive_count;
    rb = status_shm->read_bytes;
    cb = status_shm->read_chunk_bytes;
    rt = status_shm->read_timeout;
    wt = status_shm->write_timeout;

    acn = status_shm->active_connect;
    akp = status_shm->active_connect_keepalive;

    /* send response */
    size = sizeof("+ long time:\n"
                  "Request: \nResponse: \nResponse(OK): \nResponse(ERROR): \n"
                  "Connect: \nConnect(keepalive): \n"
                  "read:  bytes\nread(chunk)  bytes\n"
                  "read(timeout): \nwrite(timeout): \n\n"
                  "+ real time:\n"
                  "Connect: \nConnect(keepalive): \n") - 1
         + NGX_ATOMIC_T_LEN * 12;

    b = ngx_create_temp_buf(r->pool, size);
    if (b == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    out.buf = b;
    out.next = NULL;

    b->last = ngx_sprintf(b->last,
                          "+ long time:\n"
                          "Request: %uA\nResponse: %uA\n"
                          "Response(OK): %uA\nResponse(ERROR): %uA\n"
                          "Connect: %uA\nConnect(keepalive): %uA\n"
                          "read: %uA bytes\nread(chunk): %uA bytes\n"
                          "read(timeout): %uA\nwrite(timeout): %uA\n\n"
                          "+ real time:\n"
                          "Connect: %uA\nConnect(keepalive): %uA\n",
                          rq, rp, ok, er, cn, kp, rb, cb, rt, wt, acn, akp);

    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = b->last - b->pos;

    b->last_buf = (r == r->main);

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    return ngx_http_output_filter(r, &out);
}


static char *
ngx_http_copy_status(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t   *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_copy_status_handler;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_copy_input_body_filter(ngx_http_request_t *r, ngx_buf_t *buf)
{
    ngx_http_copy_request_t    *cpr;
    ngx_http_copy_ctx_t        *ctx;
    ngx_queue_t                *q, *next;

    size_t                      size;
    ngx_chain_t                 in;
    ngx_buf_t                  *b;

    ctx = ngx_http_get_module_ctx(r, ngx_http_copy_module);
    if (ctx == NULL) {
        return ngx_http_next_input_body_filter(r, buf);
    }

    for (q = ctx->copy_request.next; q != &ctx->copy_request; q = next) {

        cpr = ngx_queue_data(q, ngx_http_copy_request_t, queue);
        next = q->next;

        /* copy buf */
        size = buf->last - buf->pos;
        b = ngx_create_temp_buf(cpr->pool, size);
        if (b == NULL) {
            ngx_http_copy_finalize_request(cpr);
            break;
        }
        b->last = ngx_copy(b->pos, buf->pos, size);

        in.buf = b;
        in.next = NULL;

        if (cpr->request_sent) {
            cpr->request_sent = 0;
            cpr->request_bufs = NULL;
        }

        if (ngx_chain_add_copy(cpr->pool, &cpr->request_bufs, &in)
            == NGX_ERROR)
        {
            ngx_http_copy_finalize_request(cpr);
            break;
        }

        /* dont change connected_handler, which logs status of connect_count */
        if (cpr->peer.connection->write->handler
            != ngx_http_copy_connected_handler)
        {
            cpr->peer.connection->write->handler = ngx_http_copy_send_request_handler;
        }

        /*
         * NOTE: Dont use r->request_body->rest.
         * Tengine calls input body filter before calculating r->reqeust_body->rest.
         * So we should calculate length of rest input body by ourselves.
         */
        cpr->input_body_rest -= size;
        if (cpr->input_body_rest <= 0) {
            cpr->input_body = 0;
            ngx_queue_remove(&cpr->queue);
            ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                          "[copy] read whole input body");
        } else {
            ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                          "[copy] read input body (rest: %d)",
                          cpr->input_body_rest);
        }

        (void) ngx_http_copy_send_request(cpr);
    }

    return ngx_http_next_input_body_filter(r, buf);
}


static ngx_int_t
ngx_http_copy_init_shm_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_http_copy_status_shm_t     *status_shm;
    ngx_slab_pool_t                *shpool;

    if (data) {     /* reload handling */
        shm_zone->data = data;
        copy_status = data;
        return NGX_OK;
    }

    shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;

    status_shm = ngx_slab_alloc(shpool, sizeof(ngx_http_copy_status_shm_t));
    if (status_shm == NULL) {
        return NGX_ERROR;
    }

    ngx_memzero(status_shm, sizeof(ngx_http_copy_status_shm_t));

    shm_zone->data = status_shm;
    copy_status = status_shm;   /* save to global var */

    return NGX_OK;
}


static char *
ngx_http_copy_init_shm(ngx_conf_t *cf)
{
    ngx_str_t           shm_name;
    ngx_uint_t          shm_size;
    ngx_shm_zone_t     *shm_zone;

    ngx_str_set(&shm_name, "ngx_http_copy_status_shm");
    shm_size = 1 * 1024 * 1024;
    shm_zone = ngx_shared_memory_add(cf, &shm_name, shm_size,
                                     &ngx_http_copy_module);
    if (shm_zone == NULL) {
        return "cannot add shared memory";
    }

    shm_zone->init = ngx_http_copy_init_shm_zone;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_copy_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_PREACCESS_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_copy_handler;

    /* tengine input body filter: copy request body */
    ngx_http_next_input_body_filter = ngx_http_top_input_body_filter;
    ngx_http_top_input_body_filter = ngx_http_copy_input_body_filter;

    /* nginx reload: set NULL before ngx_http_copy_init_shm_zone() */
    copy_status = NULL;

    return NGX_OK;
}
