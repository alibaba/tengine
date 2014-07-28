
/*
 * Copyright (C) Maxim Dounin
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_channel.h>


typedef struct {
    ngx_uint_t                         max_cached;
    ngx_msec_t                         keepalive_timeout;

    ngx_uint_t                         per_server_pool:1;
    ngx_uint_t                         shared:1;
    void                              *shared_info;

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
    ngx_http_upstream_keepalive_srv_conf_t  *conf; /* must be the top element */

    ngx_queue_t                        queue;
    ngx_connection_t                  *connection;

    socklen_t                          socklen;
    u_char                             sockaddr[NGX_SOCKADDRLEN];

} ngx_http_upstream_keepalive_cache_t;


typedef struct {
    socklen_t                          socklen;
    u_char                             sockaddr[NGX_SOCKADDRLEN];

    ngx_lfstack_t                     *idle_list;
    ngx_lfstack_t                     *free_list;
} ngx_http_upstream_keepalive_shared_srv_t;


typedef struct {
    ngx_http_upstream_keepalive_srv_conf_t  *conf; /* must be the top element */

    ngx_uint_t                         srv_index:16;
    ngx_uint_t                         force_timeout:1;

    ngx_pid_t                          pid;
    ngx_uint_t                         slot;
    ngx_socket_t                       fd;
    ngx_connection_t                  *connection;

    ngx_atomic_t                       next;
} ngx_http_upstream_keepalive_shared_conn_t;


typedef struct {
    void                              *srv;
    ngx_uint_t                         nsrv;
    ngx_uint_t                         worker_processes;
} ngx_http_upstream_keepalive_shared_info_t;


typedef struct {
    ngx_channel_t                      ch;
    ngx_socket_t                       fd;
    void                              *pc;
    void                              *conn;
} ngx_http_upstream_keepalive_channel_data_t;


static ngx_int_t ngx_http_upstream_init_keepalive_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_keepalive_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_free_keepalive_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static ngx_int_t ngx_http_upstream_get_shared_keepalive_peer(
    ngx_peer_connection_t *pc, void *data);
static void ngx_http_upstream_free_shared_keepalive_peer(
    ngx_peer_connection_t *pc, void *data, ngx_uint_t state);

static ngx_int_t ngx_http_upstream_keepalive_channel_send_fd(ngx_channel_t *ch,
    void *data, ngx_log_t *log);
static ngx_int_t ngx_http_upstream_keepalive_channel_recv_fd(ngx_channel_t *ch,
    void *data, ngx_log_t *log);

static void ngx_http_upstream_keepalive_dummy_handler(ngx_event_t *ev);
static void ngx_http_upstream_keepalive_close_handler(ngx_event_t *ev);
static void ngx_http_upstream_keepalive_close(ngx_connection_t *c);


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
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE123,
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


static int ngx_libc_cdecl
ngx_http_upstream_cmp_keepalive_shared_srv(const void *one, const void *two)
{
    ngx_http_upstream_keepalive_shared_srv_t  *first, *second;

    first = (ngx_http_upstream_keepalive_shared_srv_t *) one;
    second = (ngx_http_upstream_keepalive_shared_srv_t *) two;

    return ngx_memn2cmp((u_char *) first->sockaddr,
                        (u_char *) second->sockaddr,
                        first->socklen, second->socklen);
}


static ngx_int_t
ngx_http_upstream_init_keepalive_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_shm_t                                   *shm;
    ngx_cycle_t                                 *cycle;
    ngx_core_conf_t                             *ccf;
    ngx_http_upstream_server_t                  *usrv;
    ngx_http_upstream_srv_conf_t                *us;
    ngx_http_upstream_keepalive_srv_conf_t      *kcf;
    ngx_http_upstream_keepalive_shared_info_t   *info;
    ngx_http_upstream_keepalive_shared_conn_t   *conn;
    ngx_http_upstream_keepalive_shared_srv_t    *srv;
    ngx_uint_t                                   i, j;
    size_t                                       si, sj, sk, offset;

    us = shm_zone->data;
    shm = &shm_zone->shm;

    kcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_keepalive_module);

    cycle = kcf->shared_info;
    kcf->shared_info = NULL;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cycle->log, 0,
                   "init keepalive zone");

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);

    ngx_memzero(shm->addr, shm->size);

    si = sizeof(ngx_http_upstream_keepalive_shared_info_t);

    sj = sizeof(ngx_http_upstream_keepalive_shared_srv_t)
       * us->servers->nelts;

    sk = sizeof(ngx_lfstack_t) * (ccf->worker_processes + 1);

    info = (void *) shm->addr;
    info->srv = shm->addr + si;
    info->nsrv = us->servers->nelts;
    info->worker_processes = ccf->worker_processes;

    kcf->shared_info = info;

    offset = offsetof(ngx_http_upstream_keepalive_shared_conn_t, next);

    srv = info->srv;
    usrv = us->servers->elts;
    for (i = 0; i < info->nsrv; i++) {
        srv[i].socklen = usrv[i].addrs->socklen;

        ngx_memcpy(srv[i].sockaddr, usrv[i].addrs->sockaddr,
                   srv[i].socklen);

        srv[i].idle_list = (ngx_lfstack_t *) ((char *) srv + sj + (sk * i));

        for (j = 0; j < (info->worker_processes + 1); j++) {
            ngx_lfstack_init(&srv[i].idle_list[j], offset);
        }
    }

    ngx_qsort(srv, (size_t) info->nsrv, sizeof(*srv),
              ngx_http_upstream_cmp_keepalive_shared_srv);

    conn = (void *) (shm->addr + si + sj + (sk * info->nsrv));

    if (kcf->per_server_pool == 0) {
        for (i = 0; i < info->nsrv; i++) {
            srv[i].free_list = &srv[0].idle_list[info->worker_processes];
        }

        for (i = 0; i < kcf->max_cached; i++) {
            ngx_lfstack_push(srv[0].free_list, &conn[i]);
        }

        return NGX_OK;
    }

    for (i = 0; i < info->nsrv; i++) {
        srv[i].free_list = &srv[i].idle_list[info->worker_processes];

        for (j = 0; j < kcf->max_cached; j++) {
            ngx_lfstack_push(srv[i].free_list, &conn[i * kcf->max_cached + j]);
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_init_keepalive(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_str_t                                    name;
    ngx_uint_t                                   i;
    ngx_shm_zone_t                              *shm_zone;
    ngx_core_conf_t                             *ccf;
    ngx_http_upstream_keepalive_srv_conf_t      *kcf;
    ngx_http_upstream_keepalive_cache_t         *cached;

    void      **ctx;
    size_t      si, sj, sk, sl, size;

    ctx = (void **) cf->cycle->conf_ctx;
    ccf = (ngx_core_conf_t *) ngx_get_conf(ctx, ngx_core_module);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
                   "init keepalive");

    kcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_keepalive_module);

    if (kcf->original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    kcf->original_init_peer = us->peer.init;

    us->peer.init = ngx_http_upstream_init_keepalive_peer;

    if (kcf->shared) {
        si = sizeof(ngx_http_upstream_keepalive_shared_info_t);

        sj = sizeof(ngx_http_upstream_keepalive_shared_srv_t)
           * us->servers->nelts;

        sk = (sizeof(ngx_lfstack_t) * (ccf->worker_processes + 1))
           * us->servers->nelts;

        sl = sizeof(ngx_http_upstream_keepalive_shared_conn_t)
           * kcf->max_cached;

        if (kcf->per_server_pool) {
            sl *= us->servers->nelts;
        }

        size = si + sj + sk + sl;

        name.len = us->host.len;
        name.data = us->host.data;

        shm_zone = ngx_shared_memory_add(cf, &name, size,
                                         (void *) ngx_current_msec);

        /* shared memory won't be used by slab pool */
        shm_zone->shm.slab = 0;
        shm_zone->data = us;
        shm_zone->init = ngx_http_upstream_init_keepalive_zone;

        kcf->shared_info = cf->cycle;

        return NGX_OK;
    }

    /* allocate cache items and add to free queue */

    cached = ngx_pcalloc(cf->pool,
                sizeof(ngx_http_upstream_keepalive_cache_t) * kcf->max_cached);
    if (cached == NULL) {
        return NGX_ERROR;
    }

    ngx_queue_init(&kcf->cache);
    ngx_queue_init(&kcf->free);

    for (i = 0; i < kcf->max_cached; i++) {
        ngx_queue_insert_head(&kcf->free, &cached[i].queue);
        cached[i].conf = kcf;
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

    if (kcf->shared) {
        r->upstream->peer.get = ngx_http_upstream_get_shared_keepalive_peer;
        r->upstream->peer.free = ngx_http_upstream_free_shared_keepalive_peer;

    } else {
        r->upstream->peer.get = ngx_http_upstream_get_keepalive_peer;
        r->upstream->peer.free = ngx_http_upstream_free_keepalive_peer;
    }

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

    cache = &kp->conf->cache;

    for (q = ngx_queue_head(cache);
         q != ngx_queue_sentinel(cache);
         q = ngx_queue_next(q))
    {
        item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t, queue);
        c = item->connection;

        if (ngx_memn2cmp((u_char *) &item->sockaddr, (u_char *) pc->sockaddr,
                         item->socklen, pc->socklen)
            == 0)
        {
            ngx_queue_remove(q);
            ngx_queue_insert_head(&kp->conf->free, q);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "get keepalive peer: using connection %p", c);

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

    return NGX_OK;
}


static void
ngx_http_upstream_free_keepalive_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;
    ngx_http_upstream_keepalive_cache_t      *item;

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

    if (ngx_queue_empty(&kp->conf->free)) {

        q = ngx_queue_last(&kp->conf->cache);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t, queue);

        ngx_http_upstream_keepalive_close(item->connection);

    } else {
        q = ngx_queue_head(&kp->conf->free);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t, queue);
    }

    item->connection = c;
    ngx_queue_insert_head(&kp->conf->cache, q);

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

    item->socklen = pc->socklen;
    ngx_memcpy(&item->sockaddr, pc->sockaddr, pc->socklen);

    if (c->read->ready) {
        ngx_http_upstream_keepalive_close_handler(c->read);
    }

invalid:

    kp->original_free_peer(pc, kp->data, state);
}


static ngx_int_t
ngx_http_upstream_get_shared_keepalive_peer(ngx_peer_connection_t *pc,
    void *data)
{
    ngx_http_upstream_keepalive_peer_data_t     *kp = data;
    ngx_http_upstream_keepalive_shared_srv_t    *srv, skey;
    ngx_http_upstream_keepalive_shared_info_t   *info;
    ngx_http_upstream_keepalive_shared_conn_t   *conn;
    ngx_http_upstream_keepalive_channel_data_t   cd;

    ngx_int_t          rc;
    ngx_uint_t         i, j, n;
    ngx_connection_t  *c;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "get keepalive peer");

    /* ask balancer */

    rc = kp->original_get_peer(pc, kp->data);

    if (rc != NGX_OK) {
        return rc;
    }

    /* check process status before accessing shared memory */
    if (ngx_exiting || ngx_quit) {
        return NGX_OK;
    }

    /* search shared cache for suitable connection */

    info = kp->conf->shared_info;

    ngx_memcpy(skey.sockaddr, pc->sockaddr, pc->socklen);
    skey.socklen = pc->socklen;

    srv = bsearch(&skey, info->srv, info->nsrv, sizeof(*srv),
                  ngx_http_upstream_cmp_keepalive_shared_srv);

    if (srv == NULL) {
        ngx_log_error(NGX_LOG_ALERT, pc->log, 0,
                      "bsearch failed!");
        return NGX_OK;
    }

    /*
     * try to pop local idle list firstly,
     * if not found search for sibling idle lists
     */
    conn = NULL;
    n = info->worker_processes;
    for (j = 0; j < n; j++) {
        i = (j + ngx_process_idx) % n;

        conn = ngx_lfstack_pop(&srv->idle_list[i]);
        if (conn != NULL) {
            if (conn->pid == ngx_pid ||
                conn->pid == ngx_processes[conn->slot].pid) {
                break;
            }

            /*
             * connection's owner process has been dead,
             * let's reclaim it into free list.
             */
            ngx_lfstack_push(srv->free_list, conn);
        }
    }

    if (conn == NULL) {
        return NGX_OK;
    }

    if (conn->pid != ngx_pid) {
        n = sizeof(ngx_http_upstream_keepalive_channel_data_t);
        j = offsetof(ngx_http_upstream_keepalive_channel_data_t, fd);

        cd.ch.command = NGX_CMD_RPC;
        cd.ch.pid = ngx_pid;
        cd.ch.slot = ngx_process_slot;
        cd.ch.fd = -1;
        cd.ch.rpc = ngx_http_upstream_keepalive_channel_send_fd;
        cd.ch.len = n - j;

        cd.fd = conn->fd;
        cd.pc = pc;
        cd.conn = conn;

        /* ignore EAGAIN */
        if (ngx_write_channel(ngx_processes[conn->slot].channel[0],
                              &cd.ch, n, pc->log)
            == NGX_OK)
        {
            return NGX_YIELD;
        }

        ngx_lfstack_push(&srv->idle_list[i], conn);
        return NGX_OK;
    }

    c = conn->connection;

    ngx_lfstack_push(srv->free_list, conn);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "get keepalive peer: using connection %p", c);

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


static void
ngx_http_upstream_free_shared_keepalive_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state)
{
    ngx_http_upstream_keepalive_peer_data_t     *kp = data;
    ngx_http_upstream_keepalive_shared_srv_t    *srv, skey;
    ngx_http_upstream_keepalive_shared_info_t   *info;
    ngx_http_upstream_keepalive_shared_conn_t   *conn;

    ngx_uint_t            i;
    ngx_connection_t     *c;
    ngx_http_upstream_t  *u;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "free keepalive peer");

    /* check process status before accessing shared memory */
    if (ngx_exiting || ngx_quit) {
        goto invalid;
    }

    /* cache valid connections */

    u = kp->upstream;
    c = pc->connection;
    info = kp->conf->shared_info;

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

    conn = NULL;
    if (kp->conf->per_server_pool == 0) {
        srv = info->srv;
        conn = ngx_lfstack_pop(srv[0].free_list);
        if (conn == NULL) {
            goto invalid;
        }
    }

    ngx_memcpy(skey.sockaddr, pc->sockaddr, pc->socklen);
    skey.socklen = pc->socklen;

    srv = bsearch(&skey, info->srv, info->nsrv, sizeof(*srv),
                  ngx_http_upstream_cmp_keepalive_shared_srv);

    if (srv == NULL) {
        ngx_log_error(NGX_LOG_ALERT, pc->log, 0,
                      "bsearch failed!");
        goto invalid;
    }

    if (kp->conf->per_server_pool) {
        conn = ngx_lfstack_pop(srv->free_list);
        if (conn == NULL) {
            goto invalid;
        }
    }

    conn->connection = c;
    conn->conf = kp->conf;

    conn->pid = ngx_pid;
    conn->slot = ngx_process_slot;
    conn->fd = c->fd;

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

    c->data = conn;
    c->idle = 1;
    c->log = ngx_cycle->log;
    c->read->log = ngx_cycle->log;
    c->write->log = ngx_cycle->log;
    c->pool->log = ngx_cycle->log;

    i = srv - (ngx_http_upstream_keepalive_shared_srv_t *) info->srv;
    conn->srv_index = i;
    conn->force_timeout = 0;

    ngx_lfstack_push(&srv->idle_list[ngx_process_idx], conn);

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
    ngx_http_upstream_keepalive_srv_conf_t      *conf;
    ngx_http_upstream_keepalive_cache_t         *item;
    ngx_http_upstream_keepalive_shared_info_t   *info;
    ngx_http_upstream_keepalive_shared_conn_t   *conn;
    ngx_http_upstream_keepalive_shared_srv_t    *srv;

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

    /* check process status before accessing shared memory */
    if (ngx_exiting || ngx_quit) {
        ngx_http_upstream_keepalive_close(c);
        return;
    }

    conf = *(void **) c->data;
    if (conf->shared) {
        conn = c->data;
        n = conn->srv_index;

        info = conf->shared_info;
        srv = info->srv;

        if (ngx_lfstack_remove(&srv[n].idle_list[ngx_process_idx], conn)
            == NULL)
        {
            /* connection has been used by other worker */

            if (conn->force_timeout == 0) {
                return;
            }

        }
        ngx_lfstack_push(srv[n].free_list, conn);

    } else {
        item = c->data;
        ngx_queue_remove(&item->queue);
        ngx_queue_insert_head(&conf->free, &item->queue);
    }

    ngx_http_upstream_keepalive_close(c);
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
     *     conf->per_server_pool = 0;
     *     conf->shared = 0;
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
        if (ngx_strcmp(value[i].data, "shared") == 0) {
            kcf->shared = 1;
            continue;
        }

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


static ngx_int_t
ngx_http_upstream_keepalive_channel_send_fd(ngx_channel_t *ch, void *data,
    ngx_log_t *log)
{
    ngx_http_upstream_keepalive_shared_srv_t    *srv;
    ngx_http_upstream_keepalive_shared_info_t   *info;
    ngx_http_upstream_keepalive_shared_conn_t   *conn;
    ngx_http_upstream_keepalive_channel_data_t   cd;

    ngx_uint_t              k, n, slot, rc;
    ngx_socket_t            fd;
    ngx_connection_t       *c;
    ngx_peer_connection_t  *pc;

    n = sizeof(ngx_http_upstream_keepalive_channel_data_t);
    k = offsetof(ngx_http_upstream_keepalive_channel_data_t, fd);

    slot = ch->slot;

    ngx_memcpy(&cd.fd, data, ch->len);

    fd = cd.fd;
    pc = cd.pc;
    conn = cd.conn;
    info = conn->conf->shared_info;
    srv = info->srv;

    cd.ch.command = NGX_CMD_RPC;
    cd.ch.pid = ngx_pid;
    cd.ch.slot = ngx_process_slot;
    cd.ch.fd = fd;
    cd.ch.rpc = ngx_http_upstream_keepalive_channel_recv_fd;
    cd.ch.len = n - k;

    cd.fd = -1;
    cd.pc = pc;
    cd.conn = NULL;

    rc = ngx_write_channel(ngx_processes[slot].channel[0], &cd.ch, n, log);
    if (rc != NGX_OK) {
        n = conn->srv_index;
        ngx_lfstack_push(&srv[n].idle_list[ngx_process_idx], conn);
        return rc;
    }

    c = conn->connection;

    /*
     * c->fd has been sent to other worker,
     * close it at this side.
     */

    c->read->timedout = 1;
    conn->force_timeout = 1;

    /*
     * The references of c->fd has been increased,
     * we should delete it from epoll explicitly.
     */
    ngx_del_conn(c, 0);

    ngx_http_upstream_keepalive_close_handler(c->read);

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_keepalive_channel_recv_fd(ngx_channel_t *ch, void *data,
    ngx_log_t *log)
{
    ngx_http_upstream_keepalive_channel_data_t   cd;

    ngx_int_t               n;
    ngx_socket_t            fd;
    ngx_peer_connection_t  *pc;

    n = sizeof(ngx_http_upstream_keepalive_channel_data_t);

    ngx_memcpy(&cd.fd, data, ch->len);

    fd = ch->fd;
    pc = cd.pc;

    n = ngx_event_init_peer_socket(fd, pc, NGX_OK);

#if NGX_DEBUG
    ngx_connection_t *c = pc->connection;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "get keepalive peer: using connection %p", c);
#endif

    pc->cached = 1;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                   "http upstream connect: %i", fd);

    ngx_http_upstream_connect_done(pc->request, pc->upstream, n);

    return NGX_OK;
}
