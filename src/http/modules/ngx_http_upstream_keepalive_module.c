
/*
 * Copyright (C) Maxim Dounin
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_uint_t                         max_cached;
    ngx_msec_t                         keepalive_timeout;

    ngx_uint_t                         per_server_pool;
    ngx_queue_t                        server_pools;

    ngx_queue_t                        cache;
    ngx_queue_t                        free;

    ngx_http_upstream_init_pt          original_init_upstream;
    ngx_http_upstream_init_peer_pt     original_init_peer;

} ngx_http_upstream_keepalive_srv_conf_t;


typedef struct {
    ngx_http_upstream_keepalive_srv_conf_t  *conf;

    ngx_http_upstream_t               *upstream;

    void                              *data;

    ngx_event_get_peer_pt              original_get_peer;
    ngx_event_free_peer_pt             original_free_peer;

#if (NGX_HTTP_SSL)
    ngx_event_set_peer_session_pt      original_set_session;
    ngx_event_save_peer_session_pt     original_save_session;
#endif

} ngx_http_upstream_keepalive_peer_data_t;


typedef struct {
    ngx_http_upstream_keepalive_srv_conf_t  *conf;

    ngx_queue_t                        queue;
    ngx_connection_t                  *connection;

    ngx_queue_t                       *free;

    socklen_t                          socklen;
    u_char                             sockaddr[NGX_SOCKADDRLEN];

} ngx_http_upstream_keepalive_cache_t;


typedef struct {
    ngx_queue_t                        queue;

    ngx_queue_t                        cache;
    ngx_queue_t                        free;

    socklen_t                          socklen;
    u_char                             sockaddr[NGX_SOCKADDRLEN];

} ngx_http_upstream_keepalive_server_pool_t;


static ngx_int_t ngx_http_upstream_init_keepalive_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_keepalive_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_free_keepalive_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);

static void ngx_http_upstream_keepalive_dummy_handler(ngx_event_t *ev);
static void ngx_http_upstream_keepalive_close_handler(ngx_event_t *ev);
static void ngx_http_upstream_keepalive_close(ngx_connection_t *c);

ngx_http_upstream_keepalive_server_pool_t *
ngx_http_upstream_keepalive_in_server_pools(ngx_queue_t *pools,
    struct sockaddr *sockaddr, socklen_t socklen);


#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_upstream_keepalive_set_session(
    ngx_peer_connection_t *pc, void *data);
static void ngx_http_upstream_keepalive_save_session(ngx_peer_connection_t *pc,
    void *data);
#endif

static void *ngx_http_upstream_keepalive_create_conf(ngx_conf_t *cf);
static char *ngx_http_upstream_keepalive(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_upstream_keepalive_timeout(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);


static ngx_command_t  ngx_http_upstream_keepalive_commands[] = {

    { ngx_string("keepalive"),
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE12,
      ngx_http_upstream_keepalive,
      0,
      0,
      NULL },

    { ngx_string("keepalive_timeout"),
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE1,
      ngx_http_upstream_keepalive_timeout,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_upstream_keepalive_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    ngx_http_upstream_keepalive_create_conf, /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};


ngx_module_t  ngx_http_upstream_keepalive_module = {
    NGX_MODULE_V1,
    &ngx_http_upstream_keepalive_module_ctx, /* module context */
    ngx_http_upstream_keepalive_commands,    /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_upstream_init_keepalive(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_uint_t                               i, j, n;
    ngx_http_upstream_keepalive_srv_conf_t  *kcf;
    ngx_http_upstream_keepalive_cache_t     *cached;

    ngx_http_upstream_server_t                   *server;
    ngx_http_upstream_keepalive_server_pool_t    *server_pool;


    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
                   "init keepalive");

    kcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_keepalive_module);

    if (kcf->original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    kcf->original_init_peer = us->peer.init;

    us->peer.init = ngx_http_upstream_init_keepalive_peer;

    /* allocate cache items and add to free queue */

    if (kcf->per_server_pool && us->servers) {

        server = us->servers->elts;

        ngx_queue_init(&kcf->server_pools);

        for (i = 0; i < us->servers->nelts; i++) {
            for (j = 0; j < server[i].naddrs; j++) {
                if (ngx_http_upstream_keepalive_in_server_pools(
                                                   &kcf->server_pools,
                                                   server[i].addrs[j].sockaddr,
                                                   server[i].addrs[j].socklen))
                {
                    continue;
                }

                server_pool = ngx_pcalloc(cf->pool,
                             sizeof(ngx_http_upstream_keepalive_server_pool_t));
                if (server_pool == NULL) {
                    return NGX_ERROR;
                }

                server_pool->socklen = server[i].addrs[j].socklen;
                ngx_memcpy(&server_pool->sockaddr, server[i].addrs[j].sockaddr,
                           server_pool->socklen);

                ngx_queue_insert_head(&kcf->server_pools, &server_pool->queue);

                cached = ngx_pcalloc(cf->pool,
                                    sizeof(ngx_http_upstream_keepalive_cache_t)
                                    * kcf->max_cached);
                if (cached == NULL) {
                    return NGX_ERROR;
                }

                ngx_queue_init(&server_pool->cache);
                ngx_queue_init(&server_pool->free);

                for (n = 0; n < kcf->max_cached; n++) {
                    ngx_queue_insert_head(&server_pool->free, &cached[n].queue);
                    cached[n].conf = kcf;
                    cached[n].free = &server_pool->free;
                }
            }
        }

    } else {
        cached = ngx_pcalloc(cf->pool,
                    sizeof(ngx_http_upstream_keepalive_cache_t)
                    * kcf->max_cached);
        if (cached == NULL) {
            return NGX_ERROR;
        }

        ngx_queue_init(&kcf->cache);
        ngx_queue_init(&kcf->free);

        for (i = 0; i < kcf->max_cached; i++) {
            ngx_queue_insert_head(&kcf->free, &cached[i].queue);
            cached[i].conf = kcf;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_init_keepalive_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp;
    ngx_http_upstream_keepalive_srv_conf_t   *kcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "init keepalive peer");

    kcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_keepalive_module);

    kp = ngx_palloc(r->pool, sizeof(ngx_http_upstream_keepalive_peer_data_t));
    if (kp == NULL) {
        return NGX_ERROR;
    }

    if (kcf->original_init_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    kp->conf = kcf;
    kp->upstream = r->upstream;
    kp->data = r->upstream->peer.data;
    kp->original_get_peer = r->upstream->peer.get;
    kp->original_free_peer = r->upstream->peer.free;

    r->upstream->peer.data = kp;
    r->upstream->peer.get = ngx_http_upstream_get_keepalive_peer;
    r->upstream->peer.free = ngx_http_upstream_free_keepalive_peer;

#if (NGX_HTTP_SSL)
    kp->original_set_session = r->upstream->peer.set_session;
    kp->original_save_session = r->upstream->peer.save_session;
    r->upstream->peer.set_session = ngx_http_upstream_keepalive_set_session;
    r->upstream->peer.save_session = ngx_http_upstream_keepalive_save_session;
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_get_keepalive_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;
    ngx_http_upstream_keepalive_cache_t      *item;

    ngx_http_upstream_keepalive_server_pool_t    *server_pool;


    ngx_int_t          rc;
    ngx_queue_t       *q, *cache;
    ngx_connection_t  *c;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "get keepalive peer");

    /* ask balancer */

    rc = kp->original_get_peer(pc, kp->data);

    if (rc != NGX_OK) {
        return rc;
    }

    /* search cache for suitable connection */

    if (kp->conf->per_server_pool) {

        server_pool = ngx_http_upstream_keepalive_in_server_pools(
                                                       &kp->conf->server_pools,
                                                       pc->sockaddr,
                                                       pc->socklen);
        if (!ngx_queue_empty(&server_pool->cache)) {
            q = ngx_queue_last(&server_pool->cache);
            item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t,
                                  queue);

            c = item->connection;

            ngx_queue_remove(q);
            ngx_queue_insert_head(&server_pool->free, q);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "get keepalive peer: using connection %p", c);

            if (kp->upstream->state) {
                kp->upstream->state->cached_connection = 1;
            }

            c->idle = 0;
            c->log = pc->log;
            c->read->log = pc->log;
            c->write->log = pc->log;
            c->pool->log = pc->log;

            if (c->read->timer_set) {
                ngx_del_timer(c->read);
            }

            pc->connection = c;
            pc->cached = 1;

            return NGX_DONE;
        }

    } else {
        cache = &kp->conf->cache;

        for (q = ngx_queue_head(cache);
             q != ngx_queue_sentinel(cache);
             q = ngx_queue_next(q))
        {
            item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t,
                                  queue);
            c = item->connection;

            if (ngx_memn2cmp((u_char *) &item->sockaddr,
                             (u_char *) pc->sockaddr,
                             item->socklen, pc->socklen)
                == 0)
            {
                ngx_queue_remove(q);
                ngx_queue_insert_head(&kp->conf->free, q);

                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                               "get keepalive peer: using connection %p", c);

                if (kp->upstream->state) {
                    kp->upstream->state->cached_connection = 1;
                }

                c->idle = 0;
                c->log = pc->log;
                c->read->log = pc->log;
                c->write->log = pc->log;
                c->pool->log = pc->log;

                if (c->read->timer_set) {
                    ngx_del_timer(c->read);
                }

                pc->connection = c;
                pc->cached = 1;

                return NGX_DONE;
            }
        }
    }

    return NGX_OK;
}


static void
ngx_http_upstream_free_keepalive_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;
    ngx_http_upstream_keepalive_cache_t      *item;

    ngx_http_upstream_keepalive_server_pool_t    *server_pool;

    ngx_queue_t          *q;
    ngx_connection_t     *c;
    ngx_http_upstream_t  *u;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "free keepalive peer");

    /* cache valid connections */

    u = kp->upstream;
    c = pc->connection;

    if (state & NGX_PEER_FAILED
        || c == NULL
        || c->read->eof
        || c->read->error
        || c->read->timedout
        || c->write->error
        || c->write->timedout)
    {
        goto invalid;
    }

    if (!u->keepalive) {
        goto invalid;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        goto invalid;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "free keepalive peer: saving connection %p", c);

    if (kp->conf->per_server_pool) {
        server_pool = ngx_http_upstream_keepalive_in_server_pools(
                                                        &kp->conf->server_pools,
                                                        pc->sockaddr,
                                                        pc->socklen);
        if (ngx_queue_empty(&server_pool->free)) {

            q = ngx_queue_last(&server_pool->cache);
            ngx_queue_remove(q);

            item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t,
                                  queue);

            ngx_http_upstream_keepalive_close(item->connection);

        } else {
            q = ngx_queue_head(&server_pool->free);
            ngx_queue_remove(q);

            item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t,
                                  queue);
        }

        item->connection = c;
        ngx_queue_insert_head(&server_pool->cache, q);

    } else {
        if (ngx_queue_empty(&kp->conf->free)) {

            q = ngx_queue_last(&kp->conf->cache);
            ngx_queue_remove(q);

            item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t,
                                  queue);

            ngx_http_upstream_keepalive_close(item->connection);

        } else {
            q = ngx_queue_head(&kp->conf->free);
            ngx_queue_remove(q);

            item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t,
                                  queue);
        }

        item->connection = c;
        ngx_queue_insert_head(&kp->conf->cache, q);
    }

    pc->connection = NULL;

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }
    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    if (kp->conf->keepalive_timeout != NGX_CONF_UNSET_MSEC &&
        kp->conf->keepalive_timeout != 0)
    {
        ngx_add_timer(c->read, kp->conf->keepalive_timeout);
    }

    c->write->handler = ngx_http_upstream_keepalive_dummy_handler;
    c->read->handler = ngx_http_upstream_keepalive_close_handler;

    c->data = item;
    c->idle = 1;
    c->log = ngx_cycle->log;
    c->read->log = ngx_cycle->log;
    c->write->log = ngx_cycle->log;
    c->pool->log = ngx_cycle->log;

    if (!kp->conf->per_server_pool) {
        item->socklen = pc->socklen;
        ngx_memcpy(&item->sockaddr, pc->sockaddr, pc->socklen);
    }

    if (c->read->ready) {
        ngx_http_upstream_keepalive_close_handler(c->read);
    }

invalid:

    kp->original_free_peer(pc, kp->data, state);
}


static void
ngx_http_upstream_keepalive_dummy_handler(ngx_event_t *ev)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "keepalive dummy handler");
}


static void
ngx_http_upstream_keepalive_close_handler(ngx_event_t *ev)
{
    ngx_http_upstream_keepalive_srv_conf_t  *conf;
    ngx_http_upstream_keepalive_cache_t     *item;

    int                n;
    char               buf[1];
    ngx_connection_t  *c;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "keepalive close handler");

    c = ev->data;

    if (c->close) {
        goto close;
    }

    if (c->read->timedout) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                       "keepalive max idle timeout");
        goto close;
    }

    n = recv(c->fd, buf, 1, MSG_PEEK);

    if (n == -1 && ngx_socket_errno == NGX_EAGAIN) {
        /* stale event */

        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            goto close;
        }

        return;
    }

close:

    item = c->data;
    conf = item->conf;

    ngx_http_upstream_keepalive_close(c);

    ngx_queue_remove(&item->queue);

    if (conf->per_server_pool) {
        ngx_queue_insert_head(item->free, &item->queue);

    } else {
        ngx_queue_insert_head(&conf->free, &item->queue);
    }
}


static void
ngx_http_upstream_keepalive_close(ngx_connection_t *c)
{

#if (NGX_HTTP_SSL)

    if (c->ssl) {
        c->ssl->no_wait_shutdown = 1;
        c->ssl->no_send_shutdown = 1;

        if (ngx_ssl_shutdown(c) == NGX_AGAIN) {
            c->ssl->handler = ngx_http_upstream_keepalive_close;
            return;
        }
    }

#endif

    ngx_destroy_pool(c->pool);
    ngx_close_connection(c);
}


#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_upstream_keepalive_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;

    return kp->original_set_session(pc, kp->data);
}


static void
ngx_http_upstream_keepalive_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;

    kp->original_save_session(pc, kp->data);
    return;
}

#endif


static void *
ngx_http_upstream_keepalive_create_conf(ngx_conf_t *cf)
{
    ngx_http_upstream_keepalive_srv_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool,
                       sizeof(ngx_http_upstream_keepalive_srv_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->original_init_upstream = NULL;
     *     conf->original_init_peer = NULL;
     */

    conf->max_cached = 1;
    conf->keepalive_timeout = NGX_CONF_UNSET_MSEC;

    return conf;
}


static char *
ngx_http_upstream_keepalive(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_upstream_srv_conf_t            *uscf;
    ngx_http_upstream_keepalive_srv_conf_t  *kcf;

    ngx_int_t    n;
    ngx_str_t   *value;
    ngx_uint_t   i;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    kcf = ngx_http_conf_upstream_srv_conf(uscf,
                                          ngx_http_upstream_keepalive_module);

    if (kcf->original_init_upstream) {
        return "is duplicate";
    }

    kcf->original_init_upstream = uscf->peer.init_upstream
                                  ? uscf->peer.init_upstream
                                  : ngx_http_upstream_init_round_robin;

    uscf->peer.init_upstream = ngx_http_upstream_init_keepalive;

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

    for (i = 2; i < cf->args->nelts; i++) {

        if (ngx_strcmp(value[i].data, "single") == 0) {
            ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                               "the \"single\" parameter is deprecated");
            continue;
        }

        if (ngx_strcmp(value[i].data, "per_server") == 0) {
            kcf->per_server_pool = 1;
            continue;
        }

        goto invalid;
    }

    return NGX_CONF_OK;

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static char *
ngx_http_upstream_keepalive_timeout(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_http_upstream_srv_conf_t            *uscf;
    ngx_http_upstream_keepalive_srv_conf_t  *kcf;

    ngx_str_t   *value;
    ngx_msec_t   timeout;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    kcf = ngx_http_conf_upstream_srv_conf(uscf,
                                          ngx_http_upstream_keepalive_module);

    if (kcf->keepalive_timeout != NGX_CONF_UNSET_MSEC) {
        return "is duplicate";
    }

    value = cf->args->elts;

    timeout = ngx_parse_time(&value[1], 0);
    if (timeout == (ngx_msec_t) NGX_ERROR) {
        return "invalid value";
    }

    kcf->keepalive_timeout = timeout;

    return NGX_CONF_OK;
}


ngx_http_upstream_keepalive_server_pool_t *
ngx_http_upstream_keepalive_in_server_pools(ngx_queue_t *pools,
    struct sockaddr *sockaddr, socklen_t socklen)
{
    ngx_queue_t                                  *q;
    ngx_http_upstream_keepalive_server_pool_t    *item;

    for (q = ngx_queue_head(pools);
         q != ngx_queue_sentinel(pools);
         q = ngx_queue_next(q))
    {
        item = ngx_queue_data(q, ngx_http_upstream_keepalive_server_pool_t,
                              queue);

        if (ngx_memn2cmp((u_char *) &item->sockaddr,
                         (u_char *) sockaddr,
                         item->socklen, socklen)
            == 0)
        {
            return item;
        }
    }

    return NULL;
}
