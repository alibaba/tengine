
/*
 * Copyright (C) cfsego
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_uint_t                         max_cached;
    ngx_msec_t                         keepalive_timeout;
    ngx_uint_t                         max_key_length;
    ngx_uint_t                         pool_size;

    ngx_queue_t                        cache;
    ngx_queue_t                        free;
    ngx_queue_t                        dummy;

    ngx_http_upstream_init_pt          original_init_upstream;
    ngx_http_upstream_init_peer_pt     original_init_peer;

    ngx_http_complex_value_t          *slice_key;
    ngx_int_t                          slice_conn;
    ngx_int_t                          slice_var_index;

    ngx_rbtree_t                      *index;
    ngx_queue_t                        index_pool;

} ngx_http_upstream_keepalive_srv_conf_t;


typedef struct {
    u_char                             color;
    u_char                             count;
    u_short                            len;
    ngx_queue_t                        cache; 
    ngx_queue_t                        index;
    u_char                             data[1];
} ngx_http_upstream_keepalive_node_t;


typedef struct {
    ngx_http_upstream_keepalive_srv_conf_t  *conf;

    ngx_http_request_t                *request;
    ngx_http_upstream_t               *upstream;

    void                              *data;

    ngx_event_get_peer_pt              original_get_peer;
    ngx_event_free_peer_pt             original_free_peer;

#if (NGX_HTTP_SSL)
    ngx_event_set_peer_session_pt      original_set_session;
    ngx_event_save_peer_session_pt     original_save_session;
#endif

    ngx_str_t                          key;
    uint32_t                           hash;

} ngx_http_upstream_keepalive_peer_data_t;


typedef struct {
    ngx_http_upstream_keepalive_node_t      *node;
    ngx_http_upstream_keepalive_srv_conf_t  *conf;

    ngx_queue_t                        queue;
    ngx_queue_t                        index;
    ngx_connection_t                  *connection;

    socklen_t                          socklen;
    u_char                             sockaddr[NGX_SOCKADDRLEN];

} ngx_http_upstream_keepalive_cache_t;


static ngx_int_t ngx_http_upstream_init_keepalive_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_keepalive_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_free_keepalive_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static ngx_http_upstream_keepalive_node_t *ngx_http_upstream_keepalive_lookup(
    ngx_http_upstream_keepalive_peer_data_t *kp);

static void ngx_http_upstream_keepalive_dummy_handler(ngx_event_t *ev);
static void ngx_http_upstream_keepalive_close_handler(ngx_event_t *ev);
static void ngx_http_upstream_keepalive_close(ngx_connection_t *c);
static void ngx_http_upstream_keepalive_cleanup(void *data);

static void ngx_http_upstream_keepalive_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel);
static ngx_int_t ngx_http_upstream_keepalive_get_peer_in_slice(
    ngx_peer_connection_t *pc, ngx_http_upstream_keepalive_peer_data_t *kp);
static ngx_int_t
    ngx_http_upstream_do_get_keepalive_peer(ngx_peer_connection_t *pc,
    ngx_queue_t *cache, ngx_queue_t *free, off_t offset);

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
static ngx_int_t ngx_http_upstream_init_keepalive(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);

static ngx_int_t ngx_http_upstream_keepalive_param_skey(ngx_conf_t *cf,
    void *conf, ngx_str_t *val);
static ngx_int_t ngx_http_upstream_keepalive_param_sconn(ngx_conf_t *cf,
    void *conf, ngx_str_t *val);
static ngx_int_t ngx_http_upstream_keepalive_param_dyn(ngx_conf_t *cf,
    void *conf, ngx_str_t *val);
static ngx_int_t ngx_http_upstream_keepalive_param_klen(ngx_conf_t *cf,
    void *conf, ngx_str_t *val);
static ngx_int_t ngx_http_upstream_keepalive_param_psize(ngx_conf_t *cf,
    void *conf, ngx_str_t *val);


static ngx_command_t  ngx_http_upstream_keepalive_commands[] = {

    { ngx_string("keepalive"),
      NGX_HTTP_UPS_CONF|NGX_CONF_1MORE,
      ngx_http_upstream_keepalive,
      NGX_HTTP_SRV_CONF_OFFSET,
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
    ngx_http_upstream_keepalive_commands,  /* module directives */
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


typedef struct {
    ngx_str_t name;
    ngx_int_t (*cb)(ngx_conf_t *cf, void *conf, ngx_str_t *val);
} ngx_http_upstream_keepalive_param;


static ngx_http_upstream_keepalive_param keepalive_params[] = {
    { ngx_string("slice_key"), ngx_http_upstream_keepalive_param_skey },
    { ngx_string("slice_conn"), ngx_http_upstream_keepalive_param_sconn },
    { ngx_string("slice_dyn"), ngx_http_upstream_keepalive_param_dyn },
    { ngx_string("slice_keylen"), ngx_http_upstream_keepalive_param_klen },
    { ngx_string("slice_poolsize"), ngx_http_upstream_keepalive_param_psize }
};


/* DONE */
static void
ngx_http_upstream_keepalive_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel)
{
    ngx_rbtree_node_t                   **p;
    ngx_http_upstream_keepalive_node_t   *ukn, *uknt;

    for ( ;; ) {

        if (node->key < temp->key) {

            p = &temp->left;

        } else if (node->key > temp->key) {

            p = &temp->right;

        } else { /* node->key == temp->key */

            ukn = (ngx_http_upstream_keepalive_node_t *) &node->color;
            uknt = (ngx_http_upstream_keepalive_node_t *) &temp->color;

            p = (ngx_memn2cmp(ukn->data, uknt->data, ukn->len, uknt->len) < 0)
                ? &temp->left : &temp->right;
        }

        if (*p == sentinel) {
            break;
        }

        temp = *p;
    }

    *p = node;
    node->parent = temp;
    node->left = sentinel;
    node->right = sentinel;
    ngx_rbt_red(node);
}


/* DONE */
static ngx_int_t
ngx_http_upstream_keepalive_param_skey(ngx_conf_t *cf, void *conf,
    ngx_str_t *val)
{
    ngx_http_compile_complex_value_t         ccv;
    ngx_http_upstream_keepalive_srv_conf_t  *kcf = conf;

    kcf->slice_key = ngx_palloc(cf->pool,
                                sizeof(ngx_http_complex_value_t));
    if (kcf->slice_key == NULL) {
        return NGX_ERROR;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    ccv.cf = cf;
    ccv.value = val;
    ccv.complex_value = kcf->slice_key;

    return ngx_http_compile_complex_value(&ccv);
}


/* DONE */
static ngx_int_t
ngx_http_upstream_keepalive_param_sconn(ngx_conf_t *cf, void *conf,
    ngx_str_t *val)
{
    ngx_http_upstream_keepalive_srv_conf_t  *kcf = conf;

    kcf->slice_conn = ngx_atoi(val->data, val->len);

    return kcf->slice_conn == NGX_ERROR ? NGX_ERROR : NGX_OK;
}


/* DONE */
static ngx_int_t
ngx_http_upstream_keepalive_param_dyn(ngx_conf_t *cf, void *conf,
    ngx_str_t *val)
{
    ngx_http_upstream_keepalive_srv_conf_t  *kcf = conf;

    kcf->slice_var_index = ngx_http_get_variable_index(cf, val);

    return kcf->slice_var_index == NGX_ERROR ? NGX_ERROR : NGX_OK;
}


/* DONE */
static ngx_int_t
ngx_http_upstream_keepalive_param_klen(ngx_conf_t *cf, void *conf,
    ngx_str_t *val)
{
    ngx_int_t  n;

    ngx_http_upstream_keepalive_srv_conf_t  *kcf = conf;

    n = ngx_atoi(val->data, val->len);
    kcf->max_key_length = n;

    return n == NGX_ERROR ? NGX_ERROR : NGX_OK;
}


/* DONE */
static ngx_int_t
ngx_http_upstream_keepalive_param_psize(ngx_conf_t *cf, void *conf,
    ngx_str_t *val)
{
    ngx_int_t  n;

    ngx_http_upstream_keepalive_srv_conf_t  *kcf = conf;

    n = ngx_atoi(val->data, val->len);
    kcf->pool_size = n;

    return n == NGX_ERROR ? NGX_ERROR : NGX_OK;
}


/* DONE */
static char *
ngx_http_upstream_keepalive(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_int_t    n;
    ngx_str_t   *value, tmp;
    ngx_uint_t   i, j;

    ngx_http_upstream_srv_conf_t            *uscf;
    ngx_http_upstream_keepalive_srv_conf_t  *kcf = conf;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

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

        for (j = 0;
             j < sizeof(keepalive_params)
                              / sizeof(ngx_http_upstream_keepalive_param);
             j++)
        {
            if (value[i].len > keepalive_params[j].name.len + 1
                && ngx_strncmp(value[i].data, keepalive_params[j].name.data,
                               keepalive_params[j].name.len)
                    == 0)
            {
                tmp.data = value[i].data + keepalive_params[j].name.len + 1;
                tmp.len = value[i].len - keepalive_params[j].name.len - 1;

                if (keepalive_params[j].cb(cf, kcf, &tmp) != NGX_OK) {
                    goto invalid;
                }
            }
        }

        goto invalid;
    }

    if (kcf->slice_key && kcf->slice_var_index == NGX_CONF_UNSET
        && kcf->slice_conn == NGX_CONF_UNSET)
    {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "specific either slice_conn or slice_dyn");

        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


/* DONE */
static ngx_int_t
ngx_http_upstream_init_keepalive(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    size_t                                   size;
    u_char                                  *index;
    ngx_uint_t                               i;
    ngx_rbtree_node_t                       *sentinel;
    ngx_pool_cleanup_t                      *cln;
    ngx_http_upstream_keepalive_node_t      *node;
    ngx_http_upstream_keepalive_cache_t     *cached;
    ngx_http_upstream_keepalive_srv_conf_t  *kcf;

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

    cached = ngx_pcalloc(cf->pool,
                sizeof(ngx_http_upstream_keepalive_cache_t) * kcf->max_cached);
    if (cached == NULL) {
        return NGX_ERROR;
    }

    ngx_queue_init(&kcf->cache);
    ngx_queue_init(&kcf->free);
    ngx_queue_init(&kcf->dummy);

    for (i = 0; i < kcf->max_cached; i++) {
        ngx_queue_insert_head(&kcf->free, &cached[i].queue);
        cached[i].conf = kcf;
    }

    if (kcf->slice_key) {
        sentinel = ngx_pcalloc(cf->pool, sizeof(ngx_rbtree_node_t));
        if (sentinel == NULL) {
            return NGX_ERROR;
        }

        size = offsetof(ngx_rbtree_node_t, color)
             + offsetof(ngx_http_upstream_keepalive_node_t, data)
             + kcf->max_key_length;

        index = ngx_pcalloc(cf->pool, size * kcf->pool_size);
        if (index == NULL) {
            return NGX_ERROR;
        }

        ngx_queue_init(&kcf->index_pool);

        for (i = 0; i < kcf->pool_size; i++, index += size) {
            node = (ngx_http_upstream_keepalive_node_t *)
                              (index + offsetof(ngx_rbtree_node_t, color));
            ngx_queue_insert_head(&kcf->index_pool, &node->index);
        }
            
        ngx_rbtree_init(kcf->index, sentinel,
                        ngx_http_upstream_keepalive_insert_value);
    }

    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {
        return NGX_ERROR;
    }

    cln->handler = ngx_http_upstream_keepalive_cleanup;
    cln->data = kcf;

    return NGX_OK;
}


/* DONE */
static void
ngx_http_upstream_keepalive_cleanup(void *data)
{
    ngx_queue_t                              *q, *cache;
    ngx_connection_t                         *c;
    ngx_http_upstream_keepalive_cache_t      *item;
    ngx_http_upstream_keepalive_srv_conf_t   *kcf = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "keepalive cleanup");

    /* destroy all the event and timers */

    cache = &kcf->cache;

    for (q = ngx_queue_head(cache);
         q != ngx_queue_sentinel(cache);
         q = ngx_queue_next(q))
    {
        item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t, queue);
        c = item->connection;

        if (c && c->idle) {
            ngx_http_upstream_keepalive_close(c);
        }
    }
}


/* DONE */
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

    kp = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_keepalive_peer_data_t));
    if (kp == NULL) {
        return NGX_ERROR;
    }

    if (kcf->original_init_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    kp->conf = kcf;
    kp->request = r;

    if (kcf->index) {
        if (ngx_http_complex_value(r, kcf->slice_key, &kp->key) != NGX_OK) {
            return NGX_ERROR;
        }

        kp->hash = ngx_murmur_hash2(kp->key.data, kp->key.len);
    }

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


static ngx_http_upstream_keepalive_node_t *
ngx_http_upstream_keepalive_lookup(ngx_http_upstream_keepalive_peer_data_t *kp)
{
    ngx_int_t                            rc;
    ngx_rbtree_node_t                   *node, *sentinel;
    ngx_http_upstream_keepalive_node_t  *ukn;

    node = kp->conf->index->root;
    sentinel = kp->conf->index->sentinel;

    while (node != sentinel) {

        if (kp->hash < node->key) {
            node = node->left;
            continue;
        }

        if (kp->hash > node->key) {
            node = node->right;
            continue;
        }

        /* hash == node->key */

        ukn = (ngx_http_upstream_keepalive_node_t *) &node->color;

        rc = ngx_memn2cmp(kp->key.data, ukn->data, kp->key.len, ukn->len);

        if (rc == 0) {
            return ukn;
        }

        node = (rc < 0) ? node->left : node->right;
    }

    return NULL;
}


/* DONE */
static ngx_int_t
ngx_http_upstream_keepalive_get_peer_in_slice(ngx_peer_connection_t *pc,
    ngx_http_upstream_keepalive_peer_data_t *kp)
{
    ngx_int_t                            rc;
    ngx_http_upstream_keepalive_node_t  *ukn;

    ukn = ngx_http_upstream_keepalive_lookup(kp);

    if (ukn) {
        rc = ngx_http_upstream_do_get_keepalive_peer(
                    pc,
                    &ukn->cache,
                    &kp->conf->free,
                    offsetof(ngx_http_upstream_keepalive_cache_t, index));

        if (rc == NGX_DONE) {
            ukn->count--;
        }

        return rc;
    }

    return NGX_OK;
}


/* DONE */
static ngx_int_t
ngx_http_upstream_do_get_keepalive_peer(ngx_peer_connection_t *pc,
    ngx_queue_t *cache, ngx_queue_t *free, off_t offset)
{
    ngx_queue_t       *q;
    ngx_connection_t  *c;

    ngx_http_upstream_keepalive_cache_t  *item;

    for (q = ngx_queue_head(cache);
         q != ngx_queue_sentinel(cache);
         q = ngx_queue_next(q))
    {
        item = (ngx_http_upstream_keepalive_cache_t *) ((u_char *) q - offset);
        c = item->connection;

        if (ngx_memn2cmp((u_char *) &item->sockaddr, (u_char *) pc->sockaddr,
                         item->socklen, pc->socklen)
            == 0)
        {
            ngx_queue_remove(&item->index);
            ngx_queue_remove(&item->queue);
            ngx_queue_insert_head(free, &item->queue);

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


/* DONE */
static ngx_int_t
ngx_http_upstream_get_keepalive_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;

    ngx_int_t  rc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "get keepalive peer");

    /* ask balancer */

    rc = kp->original_get_peer(pc, kp->data);

    if (rc != NGX_OK) {
        return rc;
    }

    /* search cache for suitable connection */

    if (kp->conf->index) {
        return ngx_http_upstream_keepalive_get_peer_in_slice(pc, kp);
    }

    return ngx_http_upstream_do_get_keepalive_peer(
                        pc,
                        &kp->conf->cache,
                        &kp->conf->free,
                        offsetof(ngx_http_upstream_keepalive_cache_t, queue));
}


/* DONE */
static void
ngx_http_upstream_free_keepalive_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_http_upstream_keepalive_node_t       *ukn;
    ngx_http_upstream_keepalive_cache_t      *item;
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;

    ngx_int_t                   n;
    ngx_queue_t                *q;
    ngx_connection_t           *c;
    ngx_rbtree_node_t          *node;
    ngx_http_upstream_t        *u;
    ngx_http_variable_value_t  *v;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "free keepalive peer");

    /* cache valid connections */

    u = kp->upstream;
    c = pc->connection;
    ukn = NULL;

    if (state & NGX_PEER_FAILED
        || c == NULL
        || c->read->eof
        || c->read->error
        || c->read->timedout
        || c->write->error
        || c->write->timedout)
    {
        goto closed;
    }

    if (!u->keepalive) {
        goto closed;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        goto closed;
    }

    if (kp->conf->index) {
        if (kp->conf->slice_var_index != NGX_CONF_UNSET) {
            v = ngx_http_get_indexed_variable(kp->request,
                                              kp->conf->slice_var_index);

            if (v == NULL || v->not_found || v->valid == 0) {
                ngx_log_error(NGX_LOG_WARN, pc->log, 0,
                              "keepalive slice: variable is uninitialized");
                goto closed;
            }

            n = ngx_atoi(v->data, v->len);
            if (n == NGX_ERROR) {
                ngx_log_error(NGX_LOG_WARN, pc->log, 0,
                              "keepalive slice: invalid variable value");
                goto closed;
            }

        } else {
            n = kp->conf->slice_conn;
        }

        if (n == 0) {
            ngx_log_error(NGX_LOG_INFO, pc->log, 0,
                          "keepalive slice: closed, disabled");
            goto closed;
        }

        ukn = ngx_http_upstream_keepalive_lookup(kp);
        if (ukn && ukn->count >= n) {
            ngx_log_error(NGX_LOG_INFO, pc->log, 0,
                          "keepalive slice: closed, too many conn");
            goto closed;
        }

        if (ngx_queue_empty(&kp->conf->index_pool)) {
            ngx_log_error(NGX_LOG_INFO, pc->log, 0,
                          "keepalive slice: closed, full pool");
            goto closed;
        }

        if (ukn == NULL) {
            q = ngx_queue_head(&kp->conf->index_pool);
            ngx_queue_remove(q);
            ukn = ngx_queue_data(q, ngx_http_upstream_keepalive_node_t, index);
            node = (ngx_rbtree_node_t *)
                         ((u_char *) ukn - offsetof(ngx_rbtree_node_t, color));

            node->key = kp->hash;
            ukn->len = ngx_min(kp->conf->max_key_length, kp->key.len);
            ngx_memcpy(ukn->data, kp->key.data, ukn->len);
            ngx_rbtree_insert(kp->conf->index, node);
            ngx_queue_init(&ukn->cache);
            ukn->count = 0;
        }
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "free keepalive peer: saving connection %p", c);

    if (ngx_queue_empty(&kp->conf->free)) {

        q = ngx_queue_last(&kp->conf->cache);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t, queue);
        ngx_queue_remove(&item->index);

        ngx_http_upstream_keepalive_close(item->connection);

    } else {
        q = ngx_queue_head(&kp->conf->free);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_upstream_keepalive_cache_t, queue);
    }

    item->connection = c;
    ngx_queue_insert_head(&kp->conf->cache, q);
    if (ukn) {
        ngx_queue_insert_head(&ukn->cache, &item->index);
        ukn->count++;
        item->node = ukn;

    } else {
        ngx_queue_insert_head(&kp->conf->dummy, &item->index);
        item->node = NULL;
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

    item->socklen = pc->socklen;
    ngx_memcpy(&item->sockaddr, pc->sockaddr, pc->socklen);

    if (c->read->ready) {
        ngx_http_upstream_keepalive_close_handler(c->read);
    }

closed:

    kp->original_free_peer(pc, kp->data, state);
}


/* DONE */
static void
ngx_http_upstream_keepalive_dummy_handler(ngx_event_t *ev)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "keepalive dummy handler");
}


/* DONE */
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
    ngx_queue_remove(&item->index);
    ngx_queue_insert_head(&conf->free, &item->queue);

    if (item->node) {
        item->node->count--;
    }
}


/* DONE */
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

/* DONE */
static ngx_int_t
ngx_http_upstream_keepalive_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;

    return kp->original_set_session(pc, kp->data);
}


/* DONE */
static void
ngx_http_upstream_keepalive_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_keepalive_peer_data_t  *kp = data;

    kp->original_save_session(pc, kp->data);
    return;
}

#endif


/* DONE */
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
     *     conf->slice_key = NULL;
     *     conf->sentinel = NULL;
     *     conf->index = NULL;
     */

    conf->max_cached = 1;
    conf->pool_size = 20;
    conf->max_key_length = 40;   /* 128B at length */
    conf->keepalive_timeout = NGX_CONF_UNSET_MSEC;
    conf->slice_var_index = NGX_CONF_UNSET;
    conf->slice_conn = NGX_CONF_UNSET;

    return conf;
}


/* DONE */
static char *
ngx_http_upstream_keepalive_timeout(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_http_upstream_srv_conf_t  *uscf;
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

