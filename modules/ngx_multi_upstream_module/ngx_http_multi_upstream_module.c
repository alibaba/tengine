
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#include "ngx_multi_upstream_module.h"
#include "ngx_http_multi_upstream_module.h"

typedef struct {
    ngx_uint_t                               max_cached;

    ngx_queue_t                              cache;

    ngx_http_upstream_init_pt                original_init_upstream;
    ngx_http_upstream_init_peer_pt           original_init_peer;

} ngx_http_multi_upstream_srv_conf_t;


typedef struct {
    ngx_http_multi_upstream_srv_conf_t      *conf;

    ngx_queue_t                              queue;
    void                                    *connection;
    void                                    *request;

    socklen_t                                socklen;
    u_char                                   sockaddr[NGX_SOCKADDRLEN];
    uint64_t                                 id;
    unsigned int                             used;
} ngx_http_multi_upstream_cache_t;


typedef struct {
    ngx_http_multi_upstream_srv_conf_t      *conf;

    ngx_http_request_t                      *request;
    ngx_http_upstream_t                     *upstream;

    void                                    *data;

    ngx_event_get_peer_pt                    original_get_peer;
    ngx_event_free_peer_pt                   original_free_peer;
    ngx_event_notify_peer_pt                 original_notify_peer;

#if (NGX_HTTP_SSL)
    ngx_event_set_peer_session_pt            original_set_session;
    ngx_event_save_peer_session_pt           original_save_session;
#endif

} ngx_http_multi_upstream_peer_data_t;


static ngx_int_t ngx_http_multi_upstream_init(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_multi_upstream_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_multi_upstream_get_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_multi_upstream_free_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static void ngx_http_multi_upstream_notify_peer(ngx_peer_connection_t *pc, 
    void *data, ngx_uint_t type);

static ngx_int_t ngx_multi_upstream_get_peer_null(ngx_peer_connection_t *pc,
    void *data);

static ngx_int_t ngx_http_multi_upstream_add_data(ngx_connection_t *c, ngx_http_request_t *r);

#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_multi_upstream_set_session(
    ngx_peer_connection_t *pc, void *data);
static void ngx_http_multi_upstream_save_session(ngx_peer_connection_t *pc,
    void *data);
#endif

static ngx_int_t
ngx_http_multi_upstream_init_connection(ngx_connection_t *c,
    ngx_peer_connection_t *pc, void *data);
static void
ngx_http_multi_upstream_free_fake_request(void *data);

static void *ngx_http_multi_upstream_create_conf(ngx_conf_t *cf);
static char *ngx_http_multi_upstream(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static ngx_command_t  ngx_http_multi_upstream_commands[] = {
    {
        ngx_string("multi"),
        NGX_HTTP_UPS_CONF|NGX_CONF_TAKE1,
        ngx_http_multi_upstream,
        NGX_HTTP_SRV_CONF_OFFSET,
        0,
        NULL 
    },
    
    ngx_null_command
};

static ngx_http_module_t  ngx_http_multi_upstream_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    ngx_http_multi_upstream_create_conf,   /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};

ngx_module_t  ngx_http_multi_upstream_module = {
    NGX_MODULE_V1,
    &ngx_http_multi_upstream_module_ctx,    /* module context */
    ngx_http_multi_upstream_commands,       /* module directives */
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

static char *
ngx_http_multi_upstream(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_upstream_srv_conf_t            *uscf;
    ngx_http_multi_upstream_srv_conf_t      *kcf = conf;

    ngx_int_t    n;
    ngx_str_t   *value;

    if (kcf->max_cached) {
        return "is duplicate";
    }

    /* read options */

    value = cf->args->elts;

    n = ngx_atoi(value[1].data, value[1].len);

    if (n == NGX_ERROR || n == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "multi: invalid value \"%V\" in \"%V\" directive",
                           &value[1], &cmd->name);
        return NGX_CONF_ERROR;
    }

    kcf->max_cached = n;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    kcf->original_init_upstream = uscf->peer.init_upstream
                                  ? uscf->peer.init_upstream
                                  : ngx_http_upstream_init_round_robin;

    uscf->peer.init_upstream = ngx_http_multi_upstream_init;

    return NGX_CONF_OK;
}

static ngx_int_t
ngx_http_multi_upstream_init(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_multi_upstream_srv_conf_t  *kcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
                   "multi: init multi upstream");

    kcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_multi_upstream_module);

    if (kcf->original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    kcf->original_init_peer = us->peer.init;

    us->peer.init = ngx_http_multi_upstream_init_peer;

    return NGX_OK;
}


static ngx_int_t
ngx_http_multi_upstream_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_multi_upstream_peer_data_t  *kp;
    ngx_http_multi_upstream_srv_conf_t   *kcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "multi: init multi upstream peer");

    kcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_multi_upstream_module);

    kp = ngx_pcalloc(r->connection->pool, sizeof(ngx_http_multi_upstream_peer_data_t));
    if (kp == NULL) {
        return NGX_ERROR;
    }

    if (kcf->original_init_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    kp->conf = kcf;
    kp->request = r;
    kp->upstream = r->upstream;
    kp->data = r->upstream->peer.data;
    kp->original_get_peer  = r->upstream->peer.get;
    kp->original_free_peer = r->upstream->peer.free;
    kp->original_notify_peer = r->upstream->peer.notify;

    r->upstream->peer.data = kp;
    r->upstream->peer.get  = ngx_http_multi_upstream_get_peer;
    r->upstream->peer.free = ngx_http_multi_upstream_free_peer;
    r->upstream->peer.notify = ngx_http_multi_upstream_notify_peer;
    r->upstream->multi = 1;

#if (NGX_HTTP_SSL)
    kp->original_set_session  = r->upstream->peer.set_session;
    kp->original_save_session = r->upstream->peer.save_session;
    r->upstream->peer.set_session = ngx_http_multi_upstream_set_session;
    r->upstream->peer.save_session = ngx_http_multi_upstream_save_session;
#endif

    return NGX_OK;
}

static ngx_int_t
ngx_multi_upstream_get_peer_null(ngx_peer_connection_t *pc, void *data)
{
    return NGX_OK;
}

static ngx_int_t
ngx_http_multi_upstream_get_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_multi_upstream_peer_data_t     *kp = data;
    ngx_http_multi_upstream_cache_t         *item, *best;
    ngx_int_t                                rc;
    ngx_uint_t                               cnt;
    ngx_queue_t                             *q, *cache;
    ngx_connection_t                        *c;
    ngx_event_get_peer_pt                    save_handler;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "multi: get multi upstream peer");

    /* ask balancer */

    rc = kp->original_get_peer(pc, kp->data);

    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, pc->log,
                      0, "multi: balancer get: %i", rc);
        return rc;
    }

    /* search cache for suitable connection */
    cache = &kp->conf->cache;

    best = NULL;
    cnt  = 0;

    for (q = ngx_queue_head(cache);
         q != ngx_queue_sentinel(cache);
         q = ngx_queue_next(q))
    {
        item = ngx_queue_data(q, ngx_http_multi_upstream_cache_t, queue);
        c = item->connection;

        ngx_log_error(NGX_LOG_INFO, c->log,
                      0, "multi: connect list, c: %p", c);

        if (ngx_memn2cmp((u_char *) &item->sockaddr, (u_char *) pc->sockaddr,
                         item->socklen, pc->socklen)
            == 0)
        {
            if (best == NULL) {
                best = item;
            } else {
                if (best->used > item->used) {
                    best = item;
                }
            }
            cnt++;
        }
    }

    if (cnt >= kp->conf->max_cached) {
        c = best->connection;
        best->used++;
        goto found;
    }

    /*not find, connect new*/
    save_handler = pc->get;
    pc->get = ngx_multi_upstream_get_peer_null;
    rc = ngx_event_connect_peer(pc);
    pc->get = save_handler;

    if (pc->connection == NULL) {
        ngx_log_error(NGX_LOG_ERR, pc->log,
                      0, "multi: get new connection error");
        return NGX_ERROR;
    }

    c = pc->connection;
    if (ngx_http_multi_upstream_init_connection(c, pc, data) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, pc->log,
                      0, "multi: init new connection failed, c: %p", c);
        return NGX_ERROR;
    }

    ngx_log_error(NGX_LOG_INFO, c->log,
                  0, "multi: get new connection, c: %p, code %d", c, rc);

    if (rc == NGX_OK) {
        ngx_log_error(NGX_LOG_WARN, c->log,
                      0, "multi: get new connection NGX_OK, maybe connected immediately");
        return NGX_DONE;
    } else {
        return rc;
    }

found:
    ngx_log_error(NGX_LOG_INFO, pc->log, 0,
                   "multi: get multi peer, using connection %p", c);

    if (NGX_OK != ngx_http_multi_upstream_add_data(c, kp->request)) {
        return NGX_ERROR;
    }

    pc->connection = c;
    pc->cached = 1;

    return NGX_DONE;
}

static ngx_int_t
ngx_http_multi_upstream_add_data(ngx_connection_t *c, ngx_http_request_t *r)
{
    ngx_multi_connection_t          *multi_c;
    ngx_multi_data_t                *item_data;

    multi_c = ngx_get_multi_connection(c);
    
    item_data = ngx_pcalloc(c->pool, sizeof(ngx_multi_data_t));
    if (item_data == NULL) {
        return NGX_ERROR;
    }

    item_data->data = r;
    ngx_queue_insert_tail(&multi_c->data, &item_data->queue);
    r->multi_item = &item_data->queue;

    return NGX_OK;
}

static void
ngx_http_multi_upstream_free_fake_request(void *data)
{
    ngx_http_request_t  *fake_r = data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, fake_r->connection->log, 0,
                   "multi upstream fake request cleanup: %p", fake_r);

    fake_r->logged = 1;
    ngx_http_free_request(fake_r, 0);
}

ngx_int_t
ngx_http_multi_upstream_init_connection(ngx_connection_t *c,
    ngx_peer_connection_t *pc, void *data)
{
    ngx_http_multi_upstream_peer_data_t  *kp = data;
    ngx_http_multi_upstream_cache_t      *item;
    ngx_multi_connection_t               *multi_c;
    ngx_http_request_t                   *r;
    ngx_http_request_t                   *fake_r;
    ngx_http_log_ctx_t                   *log_ctx;
    ngx_http_upstream_t                  *u, *fake_u;
    ngx_pool_cleanup_t                   *cln;

    c->pool = ngx_create_pool(128, kp->request->connection->log);
    if (c->pool == NULL) {
        return NGX_ERROR;
    }

    item = ngx_pcalloc(c->pool, sizeof(ngx_http_multi_upstream_cache_t));
    if (item == NULL) {
        return NGX_ERROR;
    }

    item->connection = c;
    item->socklen    = pc->socklen;
    item->used       = 1;
    item->conf       = kp->conf;

    ngx_memcpy(&item->sockaddr, pc->sockaddr, pc->socklen);

    ngx_queue_insert_head(&kp->conf->cache, &item->queue);

    //init multi connection
    multi_c = ngx_create_multi_connection(c);
    multi_c->connection = c;
    c->multi_c = multi_c;

    r = kp->request;

    c->data = r->main->http_connection;
    fake_r = ngx_http_create_request(c);
    if (fake_r == NULL) {
        return NGX_ERROR;
    }

    cln = ngx_pool_cleanup_add(c->pool, sizeof(ngx_pool_cleanup_file_t));
    if (cln == NULL) {
        return NGX_ERROR;
    }

    cln->handler = ngx_http_multi_upstream_free_fake_request;
    cln->data = fake_r;

    fake_r->main_conf = r->main_conf;
    fake_r->srv_conf = r->srv_conf;
    fake_r->loc_conf = r->loc_conf;
    fake_r->upstream = ngx_pcalloc(c->pool, sizeof(ngx_http_upstream_t));
    if (fake_r->upstream == NULL) {
        return NGX_ERROR;
    }

    u = r->upstream;
    fake_u = fake_r->upstream;

    //*fake_r->upstream = *r->upstream;
    fake_u->peer.connection = c;
#if (NGX_HAVE_FILE_AIO || NGX_COMPAT)
    fake_u->output.aio_handler = u->output.aio_handler;
#if (NGX_HAVE_AIO_SENDFILE || NGX_COMPAT)
    fake_u->output.aio_preload = u->output.aio_preload;
#endif
#endif

#if (NGX_THREADS || NGX_COMPAT)
    fake_u->output.thread_handler = u->output.thread_handler;
#endif
    fake_u->output.output_filter = u->output.output_filter;
    fake_u->output.pool = fake_r->pool;
    fake_u->writer.pool = fake_r->pool;
    fake_u->input_filter_ctx = fake_r;
    fake_u->conf = u->conf;
    fake_u->upstream = u->upstream;
    fake_u->state = ngx_pcalloc(c->pool, sizeof(ngx_http_upstream_state_t));
    if (fake_u->state == NULL) {
        return NGX_ERROR;
    }

    fake_u->read_event_handler = u->read_event_handler;
    fake_u->write_event_handler = u->write_event_handler;
    fake_u->input_filter_init = u->input_filter_init;
    fake_u->input_filter = u->input_filter;
    fake_u->input_filter_ctx = NULL;
#if (NGX_HTTP_CACHE)
    fake_u->create_key = u->create_key;
#endif
    fake_u->create_request = u->create_request;
    fake_u->reinit_request = u->reinit_request;
    fake_u->process_header = u->process_header;
    fake_u->abort_request = u->abort_request;
    fake_u->finalize_request = u->finalize_request;
    fake_u->rewrite_redirect = u->rewrite_redirect;
    fake_u->rewrite_cookie = u->rewrite_cookie;


    fake_u->multi = 1;

    fake_r->connection = c;

    c->data = fake_r;

    log_ctx = ngx_pcalloc(c->pool, sizeof(ngx_http_log_ctx_t));
    if (log_ctx == NULL) {
        return NGX_ERROR;
    }

    log_ctx->connection = c;
    log_ctx->request = fake_r;
    log_ctx->current_request = fake_r;

    c->log = ngx_pcalloc(c->pool, sizeof(ngx_log_t));
    if (c->log == NULL) {
        return NGX_ERROR;
    }
    *c->log = *kp->request->connection->log;
    c->log->data = log_ctx;
    fake_r->upstream->peer.log = c->log;

    c->log->connection = c->number;
    c->log->handler = NULL;
    c->log->data = log_ctx;
    c->log_error = NGX_ERROR_INFO;

    c->pool->log = c->log;

    c->read->log = c->log;
    c->write->log = c->log;
    fake_r->pool->log = c->log;

    return ngx_http_multi_upstream_add_data(c, kp->request);
}

static void
ngx_http_multi_upstream_free_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_http_multi_upstream_peer_data_t     *kp = data;
    ngx_queue_t                             *q;
    ngx_uint_t                               old_tries;
    ngx_multi_connection_t                  *multi_c;

    ngx_multi_request_t                     *multi_r;
    size_t                                   len;
    ngx_chain_t                             *cl;
    ngx_http_request_t                      *request;

    if (pc->connection == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log,
                      0, "multi: free upstream connection null");
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_STREAM, pc->connection->log, 0, "multi: free multi stream peer");

    multi_c = ngx_get_multi_connection(pc->connection);
    request = kp->request;

    if (request->backend_r) {
        while (!ngx_queue_empty(request->backend_r)) {
            q = ngx_queue_head(request->backend_r);

            ngx_queue_remove(q);

            multi_r = ngx_queue_data(q, ngx_multi_request_t, front_queue);

            //clean send_list on backend connection
            ngx_queue_remove(&multi_r->backend_queue);

            len = 0;
            for (cl = multi_r->out; cl; cl = cl->next) {
                len += ngx_buf_size(cl->buf);
            }

            if (len == 0) {
                //free multi_r and pool
                ngx_destroy_pool(multi_r->pool);
            } else {
                //add leak list wait send finish cleanup
                ngx_queue_insert_tail(&multi_c->leak_list, &multi_r->backend_queue);
            }
        }
    }

    if (request->waiting) {
        ngx_queue_remove(&request->waiting_queue);
        request->waiting = 0;
    }

    ngx_log_error(NGX_LOG_INFO, pc->log, 0, "multi: free request c: %p, r: %p end",
                  pc->connection, request);

    q = request->multi_item;
    if (q) {
        ngx_queue_remove(q);
        request->multi_item = NULL;

        old_tries = pc->tries;

        kp->original_free_peer(pc, kp->data, state);

        //work around single tries is 0
        pc->tries = old_tries - 1;

        ngx_log_error(NGX_LOG_INFO, pc->connection->log,
                0, "multi: free http request %p, %p", request, pc->connection);
    } else {
        ngx_log_error(NGX_LOG_WARN, pc->connection->log,
                0, "multi: free http request not found %p, %p", request, pc->connection);
    }

    pc->connection = NULL;

    return;
}

static void
ngx_http_multi_upstream_notify_peer(ngx_peer_connection_t *pc, 
    void *data, ngx_uint_t type)
{
    ngx_http_multi_upstream_peer_data_t   *kp = data;

    if (kp->original_notify_peer) {
        kp->original_notify_peer(pc, kp->data, type);
    }
}

#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_multi_upstream_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_multi_upstream_peer_data_t  *kp = data;

    return kp->original_set_session(pc, kp->data);
}

static void
ngx_http_multi_upstream_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_multi_upstream_peer_data_t  *kp = data;

    kp->original_save_session(pc, kp->data);
    return;
}

#endif

static void *
ngx_http_multi_upstream_create_conf(ngx_conf_t *cf)
{
    ngx_http_multi_upstream_srv_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool,
                       sizeof(ngx_http_multi_upstream_srv_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->original_init_upstream = NULL;
     *     conf->original_init_peer = NULL;
     *     conf->max_cached = 0;
     */

    ngx_queue_init(&conf->cache);

    return conf;
}

ngx_int_t
ngx_http_multi_upstream_connection_detach(ngx_connection_t *c)
{
    ngx_http_request_t                      *r;
    ngx_http_multi_upstream_srv_conf_t      *kcf;
    ngx_http_upstream_srv_conf_t            *uscf;
    ngx_http_upstream_t                     *u;
    ngx_queue_t                             *cache, *q;
    ngx_http_multi_upstream_cache_t         *item;
    ngx_multi_connection_t                  *multi_c;

    r = c->data;
    u = r->upstream;

    uscf = u->upstream;

    kcf = ngx_http_conf_upstream_srv_conf(uscf, 
            ngx_http_multi_upstream_module);

    multi_c = ngx_get_multi_connection(c);

    //remove pc from backend connection pool
    cache = &kcf->cache;
    
    for (q = ngx_queue_head(cache);
         q != ngx_queue_sentinel(cache);
         q = ngx_queue_next(q))
    {
        item = ngx_queue_data(q, ngx_http_multi_upstream_cache_t, queue);

        if (c == item->connection) {
            //found
            if (!ngx_queue_empty(&multi_c->data)) {
                ngx_log_error(NGX_LOG_WARN, c->log, 
                              0, "multi: multi connection detach not empty %p", c);
            }

            ngx_log_error(NGX_LOG_INFO, c->log, 
                          0, "multi: multi connection detach %p", c);

            ngx_queue_remove(&item->queue);

            return NGX_OK;
        }
    }

    ngx_log_error(NGX_LOG_WARN, c->log, 
                  0, "multi: multi connection detach not found %p", c);

    return NGX_DONE;
}

ngx_int_t
ngx_http_multi_upstream_connection_close(ngx_connection_t *c)
{
#if (NGX_HTTP_SSL)
    /* TODO: do not shutdown persistent connection */
    if (c->ssl) {

        /*
         * We send the "close notify" shutdown alert to the upstream only
         * and do not wait its "close notify" shutdown alert.
         * It is acceptable according to the TLS standard.
         */

        c->ssl->no_wait_shutdown = 1;

        (void) ngx_ssl_shutdown(c);
    }
#endif

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
            "multi: close http upstream connection: %d", c->fd);

    if (c->pool) {
        ngx_destroy_pool(c->pool);
    }

    c->destroyed = 1;

    ngx_close_connection(c);

    return NGX_OK;
}

ngx_flag_t
ngx_http_multi_connection_fake(ngx_http_request_t *r) 
{
    return r->upstream->peer.connection == r->connection;
}
