
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2018 Alibaba Group Holding Limited
 */

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_stream.h>

#include "ngx_multi_upstream_module.h"
#include "ngx_stream_multi_upstream_module.h"

typedef struct {
    ngx_uint_t                               max_cached;

    ngx_queue_t                              cache;

    ngx_stream_upstream_init_pt              original_init_upstream;
    ngx_stream_upstream_init_peer_pt         original_init_peer;

} ngx_stream_multi_upstream_srv_conf_t;


typedef struct {
    ngx_stream_multi_upstream_srv_conf_t    *conf;

    ngx_queue_t                              queue;
    void                                    *connection;
    void                                    *request;

    socklen_t                                socklen;
    u_char                                   sockaddr[NGX_SOCKADDRLEN];
    uint64_t                                 id;
    unsigned int                             used;
} ngx_stream_multi_upstream_cache_t;


typedef struct {
    ngx_stream_multi_upstream_srv_conf_t    *conf;

    ngx_stream_session_t                    *session;
    ngx_stream_upstream_t                   *upstream;

    void                                    *data;

    ngx_event_get_peer_pt                    original_get_peer;
    ngx_event_free_peer_pt                   original_free_peer;
    ngx_event_notify_peer_pt                 original_notify_peer;

#if (NGX_STREAM_SSL)
    ngx_event_set_peer_session_pt            original_set_session;
    ngx_event_save_peer_session_pt           original_save_session;
#endif

} ngx_stream_multi_upstream_peer_data_t;


static ngx_int_t ngx_stream_multi_upstream_init(ngx_conf_t *cf,
    ngx_stream_upstream_srv_conf_t *us);
static ngx_int_t ngx_stream_multi_upstream_init_peer(ngx_stream_session_t *s,
    ngx_stream_upstream_srv_conf_t *us);
static ngx_int_t ngx_stream_multi_upstream_get_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_stream_multi_upstream_free_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static void ngx_stream_multi_upstream_notify_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t type);

static ngx_int_t ngx_multi_upstream_get_peer_null(ngx_peer_connection_t *pc,
    void *data);

static ngx_int_t ngx_stream_multi_upstream_add_data(ngx_connection_t *c, ngx_stream_session_t *s);

#if (NGX_STREAM_SSL)
static ngx_int_t ngx_stream_multi_upstream_set_session(
    ngx_peer_connection_t *pc, void *data);
static void ngx_stream_multi_upstream_save_session(ngx_peer_connection_t *pc,
    void *data);
#endif

static ngx_int_t
ngx_stream_multi_upstream_init_connection(ngx_connection_t *c,
    ngx_peer_connection_t *pc, void *data);

static void *ngx_stream_multi_upstream_create_conf(ngx_conf_t *cf);
static char *ngx_stream_multi_upstream(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static ngx_command_t  ngx_stream_multi_upstream_commands[] = {
    {
        ngx_string("multi"),
        NGX_STREAM_UPS_CONF|NGX_CONF_TAKE1,
        ngx_stream_multi_upstream,
        NGX_STREAM_SRV_CONF_OFFSET,
        0,
        NULL
    },

    ngx_null_command
};

static ngx_stream_module_t  ngx_stream_multi_upstream_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    ngx_stream_multi_upstream_create_conf, /* create server configuration */
    NULL                                   /* merge server configuration */
};


ngx_module_t  ngx_stream_multi_upstream_module = {
    NGX_MODULE_V1,
    &ngx_stream_multi_upstream_module_ctx, /* module context */
    ngx_stream_multi_upstream_commands,    /* module directives */
    NGX_STREAM_MODULE,                     /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};

static char *
ngx_stream_multi_upstream(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_stream_upstream_srv_conf_t          *uscf;
    ngx_stream_multi_upstream_srv_conf_t    *kcf = conf;

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
                           "invalid value \"%V\" in \"%V\" directive",
                           &value[1], &cmd->name);
        return NGX_CONF_ERROR;
    }

    kcf->max_cached = n;

    uscf = ngx_stream_conf_get_module_srv_conf(cf, ngx_stream_upstream_module);

    kcf->original_init_upstream = uscf->peer.init_upstream
                                  ? uscf->peer.init_upstream
                                  : ngx_stream_upstream_init_round_robin;

    uscf->peer.init_upstream = ngx_stream_multi_upstream_init;

    return NGX_CONF_OK;
}

static ngx_int_t
ngx_stream_multi_upstream_init(ngx_conf_t *cf,
    ngx_stream_upstream_srv_conf_t *us)
{
    ngx_stream_multi_upstream_srv_conf_t  *kcf;

    ngx_log_debug0(NGX_LOG_DEBUG_STREAM, cf->log, 0,
                   "multi: init multi stream");

    kcf = ngx_stream_conf_upstream_srv_conf(us,
                                          ngx_stream_multi_upstream_module);

    if (kcf->original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    kcf->original_init_peer = us->peer.init;

    us->peer.init = ngx_stream_multi_upstream_init_peer;

    ngx_queue_init(&kcf->cache);

    return NGX_OK;
}


static ngx_int_t
ngx_stream_multi_upstream_init_peer(ngx_stream_session_t *s,
    ngx_stream_upstream_srv_conf_t *us)
{
    ngx_stream_multi_upstream_peer_data_t  *kp;
    ngx_stream_multi_upstream_srv_conf_t   *kcf;

    ngx_log_debug0(NGX_LOG_DEBUG_STREAM, s->connection->log, 0,
                   "multi: init multi stream peer");

    kcf = ngx_stream_conf_upstream_srv_conf(us,
                                          ngx_stream_multi_upstream_module);

    kp = ngx_palloc(s->connection->pool, sizeof(ngx_stream_multi_upstream_peer_data_t));
    if (kp == NULL) {
        return NGX_ERROR;
    }

    if (kcf->original_init_peer(s, us) != NGX_OK) {
        return NGX_ERROR;
    }

    kp->conf = kcf;
    kp->session = s;
    kp->upstream = s->upstream;
    kp->data = s->upstream->peer.data;
    kp->original_get_peer  = s->upstream->peer.get;
    kp->original_free_peer = s->upstream->peer.free;
    kp->original_notify_peer = s->upstream->peer.notify;

    s->upstream->peer.data = kp;
    s->upstream->peer.get  = ngx_stream_multi_upstream_get_peer;
    s->upstream->peer.free = ngx_stream_multi_upstream_free_peer;
    s->upstream->peer.notify = ngx_stream_multi_upstream_notify_peer;
    s->upstream->multi = 1;

#if (NGX_STREAM_SSL)
    kp->original_set_session  = s->upstream->peer.set_session;
    kp->original_save_session = s->upstream->peer.save_session;
    s->upstream->peer.set_session = ngx_stream_multi_upstream_set_session;
    s->upstream->peer.save_session = ngx_stream_multi_upstream_save_session;
#endif

    return NGX_OK;
}

static ngx_int_t
ngx_multi_upstream_get_peer_null(ngx_peer_connection_t *pc, void *data)
{
    return NGX_OK;
}

static ngx_int_t
ngx_stream_multi_upstream_get_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_stream_multi_upstream_peer_data_t   *kp = data;
    ngx_stream_multi_upstream_cache_t       *item, *best;
    ngx_int_t                                rc;
    ngx_uint_t                              cnt;
    ngx_queue_t                             *q, *cache;
    ngx_connection_t                        *c;
    ngx_event_get_peer_pt                    save_handler;

    ngx_log_debug0(NGX_LOG_DEBUG_STREAM, pc->log, 0,
                   "multi: get multi stream peer");

    /* ask balancer */

    rc = kp->original_get_peer(pc, kp->data);

    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, kp->session->connection->log,
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
        item = ngx_queue_data(q, ngx_stream_multi_upstream_cache_t, queue);
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
        ngx_log_error(NGX_LOG_ERR, kp->session->connection->log,
                      0, "multi: get new connection error");
        return NGX_ERROR;
    }

    c = pc->connection;
    if (ngx_stream_multi_upstream_init_connection(c, pc, data) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, c->log,
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

    if (NGX_OK != ngx_stream_multi_upstream_add_data(c, kp->session)) {
        return NGX_ERROR;
    }

    pc->connection = c;
    pc->cached = 1;

    return NGX_DONE;
}

static ngx_int_t
ngx_stream_multi_upstream_add_data(ngx_connection_t *c, ngx_stream_session_t *s)
{
    ngx_multi_connection_t          *multi_c;
    ngx_multi_data_t                *item_data;

    multi_c = ngx_get_multi_connection(c);

    item_data = ngx_pcalloc(c->pool, sizeof(ngx_multi_data_t));
    if (item_data == NULL) {
        return NGX_ERROR;
    }

    item_data->data = s;
    ngx_queue_insert_tail(&multi_c->data, &item_data->queue);
    s->multi_item = &item_data->queue;

    return NGX_OK;
}

ngx_int_t
ngx_stream_multi_upstream_init_connection(ngx_connection_t *c,
    ngx_peer_connection_t *pc, void *data)
{
    ngx_stream_multi_upstream_peer_data_t  *kp = data;
    ngx_stream_multi_upstream_cache_t      *item;
    ngx_multi_connection_t                 *multi_c;
    ngx_stream_session_t                   *fake_s, *s;

    c->pool = ngx_create_pool(128, kp->session->connection->log);
    if (c->pool == NULL) {
        return NGX_ERROR;
    }

    item = ngx_pcalloc(c->pool, sizeof(ngx_stream_multi_upstream_cache_t));
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
    multi_c = ngx_pcalloc(c->pool, sizeof(ngx_multi_connection_t));
    if (multi_c == NULL) {
        return NGX_ERROR;
    }
    ngx_queue_init(&multi_c->data);

    fake_s = ngx_pcalloc(c->pool, sizeof(ngx_stream_session_t));
    if (fake_s == NULL) {
        return NGX_ERROR;
    }

    //init fake_s
#if 0
    *fake_s = *kp->session;
#endif
    s = kp->session;
    fake_s->signature = s->signature;
    fake_s->connection = c;  //just use backend pc fake
    c->listening = s->connection->listening;
    fake_s->received = s->received;
    fake_s->start_sec = s->start_sec;
    fake_s->start_msec = s->start_msec;
    fake_s->main_conf = s->main_conf;
    fake_s->srv_conf = s->srv_conf;
    fake_s->phase_handler = s->phase_handler;
    fake_s->status = s->status;

    fake_s->ssl = 0;
    fake_s->stat_processing = s->stat_processing;
    fake_s->health_check = s->health_check;

    fake_s->upstream = ngx_pcalloc(c->pool, sizeof(ngx_stream_upstream_t));
    if (fake_s->upstream == NULL) {
        return NGX_ERROR;
    }
#if 0
    *fake_s->upstream = *kp->session->upstream;
#endif
    fake_s->upstream->peer.connection = c;
    fake_s->upstream->peer.name = s->upstream->peer.name;
    fake_s->upstream->free = NULL;
    fake_s->upstream->upstream_out = NULL;
    fake_s->upstream->upstream_busy = NULL;
    fake_s->upstream->downstream_out = NULL;
    fake_s->upstream->downstream_busy = NULL;

    fake_s->upstream->upstream = s->upstream->upstream;
    fake_s->upstream->resolved = NULL;
    fake_s->upstream->state = ngx_pcalloc(c->pool, sizeof(ngx_stream_upstream_state_t));
    if (fake_s->upstream->state == NULL) {
        return NGX_ERROR;
    }
    fake_s->upstream->state->peer = fake_s->upstream->peer.name;
    fake_s->upstream->multi = 1;

    fake_s->ctx = NULL;
    fake_s->upstream_states = NULL;
    fake_s->variables = NULL;
    fake_s->log_handler = NULL;
#if (NGX_PCRE)
    fake_s->ncaptures = s->ncaptures;
    fake_s->captures = NULL;
    fake_s->captures_data = NULL;
#endif

    c->data = fake_s;
    c->multi_c = multi_c;

    c->log = ngx_palloc(c->pool, sizeof(ngx_log_t));
    if (c->log == NULL) {
        return NGX_ERROR;
    }
    *c->log = *kp->session->connection->log;
    c->log->data = fake_s;
    fake_s->upstream->peer.log = c->log;
    c->pool->log = c->log;

    c->read->log = c->log;
    c->write->log = c->log;

    return ngx_stream_multi_upstream_add_data(c, kp->session);
}

static void
ngx_stream_multi_upstream_free_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_stream_multi_upstream_peer_data_t   *kp = data;
    ngx_queue_t                             *q;
    ngx_uint_t                               old_tries;
    ngx_multi_connection_t                  *multi_c;

    ngx_multi_request_t                     *multi_r;
    size_t                                   len;
    ngx_chain_t                             *cl;
    ngx_stream_session_t                    *session;


    if (pc->connection == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log,
                      0, "multi: free upstream connection null");
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_STREAM, pc->log, 0,
                   "multi: free multi stream peer");

    multi_c = ngx_get_multi_connection(pc->connection);

    session = kp->session;
    if (session->backend_r) {
        while (!ngx_queue_empty(session->backend_r)) {
            q = ngx_queue_head(session->backend_r);

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

    if (session->waiting) {
        ngx_queue_remove(&session->waiting_queue);
        session->waiting = 0;
    }

    ngx_log_error(NGX_LOG_INFO, pc->log, 0, "multi: free request c: %p, r: %p end",
                  pc->connection, session);

    q = session->multi_item;
    if (q) {
        ngx_queue_remove(q);
        session->multi_item = NULL;

        old_tries = pc->tries;

        kp->original_free_peer(pc, kp->data, state);

        //work around single tries is 0
        pc->tries = old_tries - 1;

        ngx_log_error(NGX_LOG_INFO, pc->connection->log,
                0, "multi: free stream session %p, %p", session, pc->connection);
    } else {
        ngx_log_error(NGX_LOG_WARN, pc->connection->log,
                      0, "multi: free stream session not found %p, %p",
                      session, pc->connection);
    }

    return;
}

static void
ngx_stream_multi_upstream_notify_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t type)
{
    ngx_stream_multi_upstream_peer_data_t   *kp = data;

    if (kp->original_notify_peer) {
        kp->original_notify_peer(pc, kp->data, type);
    }
}

#if (NGX_STREAM_SSL)

static ngx_int_t
ngx_stream_multi_upstream_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_stream_multi_upstream_peer_data_t  *kp = data;

    return kp->original_set_session(pc, kp->data);
}

static void
ngx_stream_multi_upstream_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_stream_multi_upstream_peer_data_t  *kp = data;

    kp->original_save_session(pc, kp->data);
    return;
}

#endif

static void *
ngx_stream_multi_upstream_create_conf(ngx_conf_t *cf)
{
    ngx_stream_multi_upstream_srv_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool,
                       sizeof(ngx_stream_multi_upstream_srv_conf_t));
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

    return conf;
}

ngx_multi_connection_t*
ngx_stream_session_get_multi_connection(ngx_stream_session_t *s)
{
    ngx_connection_t        *pc;

    pc = s->upstream->peer.connection;

    return ngx_get_multi_connection(pc);
}

ngx_stream_session_t*
ngx_stream_multi_get_session(ngx_connection_t *c)
{
    ngx_stream_session_t        *session;

    ngx_multi_connection_t      *multi_c;
    ngx_queue_t                 *q;
    ngx_multi_data_t            *mdata;

    multi_c = ngx_get_multi_connection(c);

    if (ngx_queue_empty(&multi_c->data)) {
        return NULL;
    } else {
        q = ngx_queue_head(&multi_c->data);
        mdata = ngx_queue_data(q, ngx_multi_data_t, queue);

        session = mdata->data;

        return session;
    }
}

ngx_int_t
ngx_stream_multi_upstream_connection_detach(ngx_connection_t *c)
{
    ngx_stream_session_t                    *session;
    ngx_stream_multi_upstream_srv_conf_t    *kcf;
    ngx_stream_upstream_srv_conf_t          *uscf;
    ngx_stream_upstream_t                   *u;
    ngx_queue_t                             *cache, *q;
    ngx_stream_multi_upstream_cache_t       *item;
    ngx_multi_connection_t                  *multi_c;

    session = c->data;
    u = session->upstream;

    uscf = u->upstream;

    kcf = ngx_stream_conf_upstream_srv_conf(uscf,
            ngx_stream_multi_upstream_module);

    cache = &kcf->cache;

    for (q = ngx_queue_head(cache);
         q != ngx_queue_sentinel(cache);
         q = ngx_queue_next(q))
    {
        item = ngx_queue_data(q, ngx_stream_multi_upstream_cache_t, queue);

        if (c == item->connection) {
            //found
            multi_c = ngx_get_multi_connection(c);
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
ngx_stream_multi_upstream_connection_close(ngx_connection_t *c)
{
    ngx_pool_t *pool = c->pool;

#if (NGX_STREAM_SSL)
    if (c->ssl) {
        c->ssl->no_wait_shutdown = 1;
        (void) ngx_ssl_shutdown(c);
    }
#endif

    ngx_log_error(NGX_LOG_INFO, c->log,
            0, "multi: multi connection real close %p", c);

    ngx_close_connection(c);

    if (pool) {
        ngx_destroy_pool(pool);
    }

    return NGX_OK;
}

ngx_flag_t
ngx_stream_multi_connection_fake(ngx_stream_session_t *s)
{
    return s->upstream->peer.connection == s->connection;
}
