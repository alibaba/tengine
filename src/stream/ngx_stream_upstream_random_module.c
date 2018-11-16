
/*
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_stream.h>


typedef struct {
    ngx_stream_upstream_rr_peer_t          *peer;
    ngx_uint_t                              range;
} ngx_stream_upstream_random_range_t;


typedef struct {
    ngx_uint_t                              two;
    ngx_stream_upstream_random_range_t     *ranges;
} ngx_stream_upstream_random_srv_conf_t;


typedef struct {
    /* the round robin data must be first */
    ngx_stream_upstream_rr_peer_data_t      rrp;

    ngx_stream_upstream_random_srv_conf_t  *conf;
    u_char                                  tries;
} ngx_stream_upstream_random_peer_data_t;


static ngx_int_t ngx_stream_upstream_init_random(ngx_conf_t *cf,
    ngx_stream_upstream_srv_conf_t *us);
static ngx_int_t ngx_stream_upstream_update_random(ngx_pool_t *pool,
    ngx_stream_upstream_srv_conf_t *us);

static ngx_int_t ngx_stream_upstream_init_random_peer(ngx_stream_session_t *s,
    ngx_stream_upstream_srv_conf_t *us);
static ngx_int_t ngx_stream_upstream_get_random_peer(ngx_peer_connection_t *pc,
    void *data);
static ngx_int_t ngx_stream_upstream_get_random2_peer(ngx_peer_connection_t *pc,
    void *data);
static ngx_uint_t ngx_stream_upstream_peek_random_peer(
    ngx_stream_upstream_rr_peers_t *peers,
    ngx_stream_upstream_random_peer_data_t *rp);
static void *ngx_stream_upstream_random_create_conf(ngx_conf_t *cf);
static char *ngx_stream_upstream_random(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


static ngx_command_t  ngx_stream_upstream_random_commands[] = {

    { ngx_string("random"),
      NGX_STREAM_UPS_CONF|NGX_CONF_NOARGS|NGX_CONF_TAKE12,
      ngx_stream_upstream_random,
      NGX_STREAM_SRV_CONF_OFFSET,
      0,
      NULL },

      ngx_null_command
};


static ngx_stream_module_t  ngx_stream_upstream_random_module_ctx = {
    NULL,                                    /* preconfiguration */
    NULL,                                    /* postconfiguration */

    NULL,                                    /* create main configuration */
    NULL,                                    /* init main configuration */

    ngx_stream_upstream_random_create_conf,  /* create server configuration */
    NULL                                     /* merge server configuration */
};


ngx_module_t  ngx_stream_upstream_random_module = {
    NGX_MODULE_V1,
    &ngx_stream_upstream_random_module_ctx,  /* module context */
    ngx_stream_upstream_random_commands,     /* module directives */
    NGX_STREAM_MODULE,                       /* module type */
    NULL,                                    /* init master */
    NULL,                                    /* init module */
    NULL,                                    /* init process */
    NULL,                                    /* init thread */
    NULL,                                    /* exit thread */
    NULL,                                    /* exit process */
    NULL,                                    /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_stream_upstream_init_random(ngx_conf_t *cf,
    ngx_stream_upstream_srv_conf_t *us)
{
    ngx_log_debug0(NGX_LOG_DEBUG_STREAM, cf->log, 0, "init random");

    if (ngx_stream_upstream_init_round_robin(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    us->peer.init = ngx_stream_upstream_init_random_peer;

#if (NGX_STREAM_UPSTREAM_ZONE)
    if (us->shm_zone) {
        return NGX_OK;
    }
#endif

    return ngx_stream_upstream_update_random(cf->pool, us);
}


static ngx_int_t
ngx_stream_upstream_update_random(ngx_pool_t *pool,
    ngx_stream_upstream_srv_conf_t *us)
{
    size_t                                  size;
    ngx_uint_t                              i, total_weight;
    ngx_stream_upstream_rr_peer_t          *peer;
    ngx_stream_upstream_rr_peers_t         *peers;
    ngx_stream_upstream_random_range_t     *ranges;
    ngx_stream_upstream_random_srv_conf_t  *rcf;

    rcf = ngx_stream_conf_upstream_srv_conf(us,
                                            ngx_stream_upstream_random_module);
    peers = us->peer.data;

    size = peers->number * sizeof(ngx_stream_upstream_random_range_t);

    ranges = pool ? ngx_palloc(pool, size) : ngx_alloc(size, ngx_cycle->log);
    if (ranges == NULL) {
        return NGX_ERROR;
    }

    total_weight = 0;

    for (peer = peers->peer, i = 0; peer; peer = peer->next, i++) {
        ranges[i].peer = peer;
        ranges[i].range = total_weight;
        total_weight += peer->weight;
    }

    rcf->ranges = ranges;

    return NGX_OK;
}


static ngx_int_t
ngx_stream_upstream_init_random_peer(ngx_stream_session_t *s,
    ngx_stream_upstream_srv_conf_t *us)
{
    ngx_stream_upstream_random_srv_conf_t   *rcf;
    ngx_stream_upstream_random_peer_data_t  *rp;

    ngx_log_debug0(NGX_LOG_DEBUG_STREAM, s->connection->log, 0,
                   "init random peer");

    rcf = ngx_stream_conf_upstream_srv_conf(us,
                                            ngx_stream_upstream_random_module);

    rp = ngx_palloc(s->connection->pool,
                    sizeof(ngx_stream_upstream_random_peer_data_t));
    if (rp == NULL) {
        return NGX_ERROR;
    }

    s->upstream->peer.data = &rp->rrp;

    if (ngx_stream_upstream_init_round_robin_peer(s, us) != NGX_OK) {
        return NGX_ERROR;
    }

    if (rcf->two) {
        s->upstream->peer.get = ngx_stream_upstream_get_random2_peer;

    } else {
        s->upstream->peer.get = ngx_stream_upstream_get_random_peer;
    }

    rp->conf = rcf;
    rp->tries = 0;

    ngx_stream_upstream_rr_peers_rlock(rp->rrp.peers);

#if (NGX_STREAM_UPSTREAM_ZONE)
    if (rp->rrp.peers->shpool && rcf->ranges == NULL) {
        if (ngx_stream_upstream_update_random(NULL, us) != NGX_OK) {
            ngx_stream_upstream_rr_peers_unlock(rp->rrp.peers);
            return NGX_ERROR;
        }
    }
#endif

    ngx_stream_upstream_rr_peers_unlock(rp->rrp.peers);

    return NGX_OK;
}


static ngx_int_t
ngx_stream_upstream_get_random_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_stream_upstream_random_peer_data_t  *rp = data;

    time_t                               now;
    uintptr_t                            m;
    ngx_uint_t                           i, n;
    ngx_stream_upstream_rr_peer_t       *peer;
    ngx_stream_upstream_rr_peers_t      *peers;
    ngx_stream_upstream_rr_peer_data_t  *rrp;

    ngx_log_debug1(NGX_LOG_DEBUG_STREAM, pc->log, 0,
                   "get random peer, try: %ui", pc->tries);

    rrp = &rp->rrp;
    peers = rrp->peers;

    ngx_stream_upstream_rr_peers_rlock(peers);

    if (rp->tries > 20 || peers->single) {
        ngx_stream_upstream_rr_peers_unlock(peers);
        return ngx_stream_upstream_get_round_robin_peer(pc, rrp);
    }

    pc->cached = 0;
    pc->connection = NULL;

    now = ngx_time();

    for ( ;; ) {

        i = ngx_stream_upstream_peek_random_peer(peers, rp);

        peer = rp->conf->ranges[i].peer;

        n = i / (8 * sizeof(uintptr_t));
        m = (uintptr_t) 1 << i % (8 * sizeof(uintptr_t));

        if (rrp->tried[n] & m) {
            goto next;
        }

        ngx_stream_upstream_rr_peer_lock(peers, peer);

        if (peer->down) {
            ngx_stream_upstream_rr_peer_unlock(peers, peer);
            goto next;
        }

        if (peer->max_fails
            && peer->fails >= peer->max_fails
            && now - peer->checked <= peer->fail_timeout)
        {
            ngx_stream_upstream_rr_peer_unlock(peers, peer);
            goto next;
        }

        if (peer->max_conns && peer->conns >= peer->max_conns) {
            ngx_stream_upstream_rr_peer_unlock(peers, peer);
            goto next;
        }

        break;

    next:

        if (++rp->tries > 20) {
            ngx_stream_upstream_rr_peers_unlock(peers);
            return ngx_stream_upstream_get_round_robin_peer(pc, rrp);
        }
    }

    rrp->current = peer;

    if (now - peer->checked > peer->fail_timeout) {
        peer->checked = now;
    }

    pc->sockaddr = peer->sockaddr;
    pc->socklen = peer->socklen;
    pc->name = &peer->name;

    peer->conns++;

    ngx_stream_upstream_rr_peer_unlock(peers, peer);
    ngx_stream_upstream_rr_peers_unlock(peers);

    rrp->tried[n] |= m;

    return NGX_OK;
}


static ngx_int_t
ngx_stream_upstream_get_random2_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_stream_upstream_random_peer_data_t  *rp = data;

    time_t                               now;
    uintptr_t                            m;
    ngx_uint_t                           i, n, p;
    ngx_stream_upstream_rr_peer_t       *peer, *prev;
    ngx_stream_upstream_rr_peers_t      *peers;
    ngx_stream_upstream_rr_peer_data_t  *rrp;

    ngx_log_debug1(NGX_LOG_DEBUG_STREAM, pc->log, 0,
                   "get random2 peer, try: %ui", pc->tries);

    rrp = &rp->rrp;
    peers = rrp->peers;

    ngx_stream_upstream_rr_peers_wlock(peers);

    if (rp->tries > 20 || peers->single) {
        ngx_stream_upstream_rr_peers_unlock(peers);
        return ngx_stream_upstream_get_round_robin_peer(pc, rrp);
    }

    pc->cached = 0;
    pc->connection = NULL;

    now = ngx_time();

    prev = NULL;

#if (NGX_SUPPRESS_WARN)
    p = 0;
#endif

    for ( ;; ) {

        i = ngx_stream_upstream_peek_random_peer(peers, rp);

        peer = rp->conf->ranges[i].peer;

        if (peer == prev) {
            goto next;
        }

        n = i / (8 * sizeof(uintptr_t));
        m = (uintptr_t) 1 << i % (8 * sizeof(uintptr_t));

        if (rrp->tried[n] & m) {
            goto next;
        }

        if (peer->down) {
            goto next;
        }

        if (peer->max_fails
            && peer->fails >= peer->max_fails
            && now - peer->checked <= peer->fail_timeout)
        {
            goto next;
        }

        if (peer->max_conns && peer->conns >= peer->max_conns) {
            goto next;
        }

        if (prev) {
            if (peer->conns * prev->weight > prev->conns * peer->weight) {
                peer = prev;
                n = p / (8 * sizeof(uintptr_t));
                m = (uintptr_t) 1 << p % (8 * sizeof(uintptr_t));
            }

            break;
        }

        prev = peer;
        p = i;

    next:

        if (++rp->tries > 20) {
            ngx_stream_upstream_rr_peers_unlock(peers);
            return ngx_stream_upstream_get_round_robin_peer(pc, rrp);
        }
    }

    rrp->current = peer;

    if (now - peer->checked > peer->fail_timeout) {
        peer->checked = now;
    }

    pc->sockaddr = peer->sockaddr;
    pc->socklen = peer->socklen;
    pc->name = &peer->name;

    peer->conns++;

    ngx_stream_upstream_rr_peers_unlock(peers);

    rrp->tried[n] |= m;

    return NGX_OK;
}


static ngx_uint_t
ngx_stream_upstream_peek_random_peer(ngx_stream_upstream_rr_peers_t *peers,
    ngx_stream_upstream_random_peer_data_t *rp)
{
    ngx_uint_t  i, j, k, x;

    x = ngx_random() % peers->total_weight;

    i = 0;
    j = peers->number;

    while (j - i > 1) {
        k = (i + j) / 2;

        if (x < rp->conf->ranges[k].range) {
            j = k;

        } else {
            i = k;
        }
    }

    return i;
}


static void *
ngx_stream_upstream_random_create_conf(ngx_conf_t *cf)
{
    ngx_stream_upstream_random_srv_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_stream_upstream_random_srv_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->two = 0;
     */

    return conf;
}


static char *
ngx_stream_upstream_random(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_stream_upstream_random_srv_conf_t  *rcf = conf;

    ngx_str_t                       *value;
    ngx_stream_upstream_srv_conf_t  *uscf;

    uscf = ngx_stream_conf_get_module_srv_conf(cf, ngx_stream_upstream_module);

    if (uscf->peer.init_upstream) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "load balancing method redefined");
    }

    uscf->peer.init_upstream = ngx_stream_upstream_init_random;

    uscf->flags = NGX_STREAM_UPSTREAM_CREATE
                  |NGX_STREAM_UPSTREAM_WEIGHT
                  |NGX_STREAM_UPSTREAM_MAX_CONNS
                  |NGX_STREAM_UPSTREAM_MAX_FAILS
                  |NGX_STREAM_UPSTREAM_FAIL_TIMEOUT
                  |NGX_STREAM_UPSTREAM_DOWN;

    if (cf->args->nelts == 1) {
        return NGX_CONF_OK;
    }

    value = cf->args->elts;

    if (ngx_strcmp(value[1].data, "two") == 0) {
        rcf->two = 1;

    } else {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[1]);
        return NGX_CONF_ERROR;
    }

    if (cf->args->nelts == 2) {
        return NGX_CONF_OK;
    }

    if (ngx_strcmp(value[2].data, "least_conn") != 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[2]);
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}
