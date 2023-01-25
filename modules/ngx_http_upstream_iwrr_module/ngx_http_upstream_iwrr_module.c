
/*
 * Copyright (C) 2010-2023 Alibaba Group Holding Limited
 * Copyright (C) 2010-2023 Zhuozhi Ji (jizhuozhi.george@gmail.com)
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#if (NGX_HTTP_UPSTREAM_CHECK)
#include "ngx_http_upstream_check_module.h"
#endif

typedef struct {
    ngx_queue_t                     queue;
    ngx_uint_t                      index;
    ngx_uint_t                      weight;
    ngx_uint_t                      remainder;
    ngx_http_upstream_rr_peer_t    *peer;
} ngx_http_upstream_iwrr_queue_t;

typedef struct ngx_http_upstream_iwrr_srv_conf_s ngx_http_upstream_iwrr_srv_conf_t;

struct ngx_http_upstream_iwrr_srv_conf_s {
    ngx_uint_t                             init_number;
    ngx_http_upstream_iwrr_queue_t        *active;
    ngx_http_upstream_iwrr_queue_t        *expired;
    ngx_http_upstream_iwrr_srv_conf_t     *next;
};

typedef struct {
    /* the round robin data must be first */
    ngx_http_upstream_rr_peer_data_t    rrp;

    ngx_http_upstream_iwrr_srv_conf_t  *uiscf;
} ngx_http_upstream_iwrr_peer_data_t;

static char *ngx_http_upstream_iwrr(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static void *ngx_http_upstream_iwrr_create_srv_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_upstream_init_iwrr(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_init_iwrr_peer(ngx_http_request_t *r, 
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_iwrr_peer(ngx_peer_connection_t *pc,
    void *data);
static ngx_http_upstream_rr_peer_t *ngx_http_upstream_get_iwrr(
    ngx_http_upstream_iwrr_peer_data_t *uip);
static ngx_http_upstream_iwrr_queue_t *ngx_http_upstream_iwrr_queue_next(
    ngx_http_upstream_iwrr_srv_conf_t *uiscf);

static inline ngx_uint_t ngx_http_upstream_iwrr_gcd(ngx_uint_t a, ngx_uint_t b);

static ngx_command_t  ngx_http_upstream_iwrr_commands[] = {

    { ngx_string("iwrr"),
      NGX_HTTP_UPS_CONF|NGX_CONF_NOARGS,
      ngx_http_upstream_iwrr,
      0,
      0,
      NULL },
    
      ngx_null_command
};

static ngx_http_module_t  ngx_http_upstream_iwrr_module_ctx = {
    NULL,                                      /* preconfiguration */
    NULL,                                      /* postconfiguration */

    NULL,                                      /* create main configuration */
    NULL,                                      /* init main configuration */

    ngx_http_upstream_iwrr_create_srv_conf,    /* create server configuration */
    NULL,                                      /* merge server configuration */

    NULL,                                      /* create location configuration */
    NULL                                       /* merge location configuration */
};

ngx_module_t  ngx_http_upstream_iwrr_module = {
    NGX_MODULE_V1,
    &ngx_http_upstream_iwrr_module_ctx,    /* module context */
    ngx_http_upstream_iwrr_commands,       /* module directives */
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

static char *
ngx_http_upstream_iwrr(ngx_conf_t *cf, ngx_command_t *cmd, 
    void *conf)
{
    ngx_http_upstream_srv_conf_t            *uscf;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    if (uscf->peer.init_upstream) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "load balancing method redefined");
    }

    uscf->peer.init_upstream = ngx_http_upstream_init_iwrr;

    uscf->flags = NGX_HTTP_UPSTREAM_CREATE
                  |NGX_HTTP_UPSTREAM_WEIGHT
                  |NGX_HTTP_UPSTREAM_BACKUP
                  |NGX_HTTP_UPSTREAM_MAX_FAILS
                  |NGX_HTTP_UPSTREAM_FAIL_TIMEOUT
#if defined(nginx_version) && nginx_version >= 1011005
                  |NGX_HTTP_UPSTREAM_MAX_CONNS
#endif
                  |NGX_HTTP_UPSTREAM_DOWN;
    
    return NGX_CONF_OK;
}

static void *
ngx_http_upstream_iwrr_create_srv_conf(ngx_conf_t *cf) 
{
    ngx_http_upstream_iwrr_srv_conf_t     *uiscf;

    uiscf = ngx_pcalloc(cf->pool, sizeof(ngx_http_upstream_iwrr_srv_conf_t));
    if (uiscf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     uiscf->active = NULL;
     *     uiscf->expired = NULL;
     *     uiscf->next = NULL;
     */

    uiscf->init_number = NGX_CONF_UNSET_UINT;

    return uiscf;
}

static ngx_int_t
ngx_http_upstream_init_iwrr(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_upstream_rr_peers_t          *peers;
    ngx_http_upstream_rr_peer_t           *peer;
    ngx_http_upstream_iwrr_srv_conf_t     *uiscf;
    ngx_http_upstream_iwrr_queue_t        *item;
    ngx_uint_t                             i, g;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0, "init iwrr");

    if (ngx_http_upstream_init_round_robin(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    us->peer.init = ngx_http_upstream_init_iwrr_peer;

    uiscf = ngx_http_conf_upstream_srv_conf(us, ngx_http_upstream_iwrr_module);

    peers = (ngx_http_upstream_rr_peers_t *) us->peer.data;

    for (peers = (ngx_http_upstream_rr_peers_t *) us->peer.data;
         peers;
         peers = peers->next)
    {

        g = 0;

        for (peer = peers->peer;
             peer;
             peer = peer->next)
        {
            g = ngx_http_upstream_iwrr_gcd(g, peer->weight);
        }

        uiscf->active = ngx_palloc(cf->pool, sizeof(ngx_http_upstream_iwrr_queue_t));
        if (uiscf->active == NULL) {
            return NGX_ERROR;
        }
        ngx_queue_init(&uiscf->active->queue);

        uiscf->expired = ngx_palloc(cf->pool, sizeof(ngx_http_upstream_iwrr_queue_t));
        if (uiscf->active == NULL) {
            return NGX_ERROR;
        }
        ngx_queue_init(&uiscf->expired->queue);

        for (peer = peers->peer, i = 0;
             peer;
             peer = peer->next, i++)
        {

            item = ngx_palloc(cf->pool, sizeof(ngx_http_upstream_iwrr_queue_t));
            if (item == NULL) {
                return NGX_ERROR;
            }

            item->index = i;
            item->weight = peer->weight / g;
            item->remainder = item->weight;
            item->peer = peer;
            ngx_queue_insert_tail(&uiscf->active->queue, &item->queue);
        }

        if (peers->next) {
            uiscf->next = ngx_pcalloc(cf->pool, sizeof(ngx_http_upstream_iwrr_srv_conf_t));
            if (uiscf->next == NULL) {
                return NGX_ERROR;
            }

            uiscf->next->init_number = NGX_CONF_UNSET_UINT;

            uiscf = uiscf->next;
        }
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_upstream_init_iwrr_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_upstream_iwrr_srv_conf_t     *uiscf;
    ngx_http_upstream_iwrr_peer_data_t    *uip;

    uiscf = ngx_http_conf_upstream_srv_conf(us, ngx_http_upstream_iwrr_module);
    if (uiscf == NULL) {
        return NGX_ERROR;
    }

    uip = ngx_palloc(r->pool, sizeof(ngx_http_upstream_iwrr_peer_data_t));
    if (uip == NULL) {
        return NGX_ERROR;
    }

    uip->uiscf = uiscf;
    r->upstream->peer.data = &uip->rrp;

    if (ngx_http_upstream_init_round_robin_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    r->upstream->peer.get = ngx_http_upstream_get_iwrr_peer;

    return NGX_OK;
}

static ngx_int_t
ngx_http_upstream_get_iwrr_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_iwrr_peer_data_t    *uip = data;

    ngx_int_t                                rc;
    ngx_uint_t                               i, n;
    ngx_http_upstream_rr_peer_t             *peer;
    ngx_http_upstream_rr_peers_t            *peers;
    ngx_http_upstream_rr_peer_data_t        *rrp;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                    "get iwrr peer, try: %ui", pc->tries);

    pc->cached = 0;
    pc->connection = NULL;

    rrp = &uip->rrp;

    peers = rrp->peers;
    ngx_http_upstream_rr_peers_wlock(peers);

    if (peers->single) {
        peer = peers->peer;

        if (peer->down) {
            goto failed;
        }

        if (peer->max_conns && peer->conns >= peer->max_conns) {
            goto failed;
        }

#if (NGX_HTTP_UPSTREAM_CHECK)
        if (ngx_http_upstream_check_peer_down(peer->check_index)) {
            goto failed;
        }
#endif
        rrp->current = peer;

    } else {

        /* there are several peers */

        peer = ngx_http_upstream_get_iwrr(uip);

        if (peer == NULL) {
            goto failed;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "get iwrr peer, current: %p %i",
                       peer, peer->current_weight);
    }
    
    pc->sockaddr = peer->sockaddr;
    pc->socklen = peer->socklen;
    pc->name = &peer->name;
#if (T_NGX_HTTP_DYNAMIC_RESOLVE)
    pc->host = &peer->host;
#endif

    peer->conns++;

    ngx_http_upstream_rr_peers_unlock(peers);

    return NGX_OK;


failed:

    if (peers->next) {

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0, "backup servers");

        rrp->peers = peers->next;

        uip->uiscf = uip->uiscf ? uip->uiscf->next : uip->uiscf;

        n = (rrp->peers->number + (8 * sizeof(uintptr_t) - 1))
                / (8 * sizeof(uintptr_t));

        for (i = 0; i < n; i++) {
            rrp->tried[i] = 0;
        }

        ngx_http_upstream_rr_peers_unlock(peers);

        rc = ngx_http_upstream_get_iwrr_peer(pc, uip);

        if (rc != NGX_BUSY) {
            return rc;
        }

        ngx_http_upstream_rr_peers_wlock(peers);
    }

    ngx_http_upstream_rr_peers_unlock(peers);

    pc->name = peers->name;

    return NGX_BUSY;
}

static ngx_http_upstream_rr_peer_t *
ngx_http_upstream_get_iwrr(ngx_http_upstream_iwrr_peer_data_t *uip)
{
    time_t                                 now;
    uintptr_t                              m;
    ngx_uint_t                             i, j, n;
    ngx_http_upstream_rr_peer_t           *peer;
    ngx_http_upstream_rr_peers_t          *peers;
    ngx_http_upstream_rr_peer_data_t      *rrp;
    ngx_http_upstream_iwrr_srv_conf_t     *uiscf;
    ngx_http_upstream_iwrr_queue_t        *item;

    now = ngx_time();

    rrp = &uip->rrp;
    peers = rrp->peers;
    uiscf = uip->uiscf;

#if (T_NGX_HTTP_UPSTREAM_RANDOM)
    if (uiscf->init_number == NGX_CONF_UNSET_UINT) {
        uiscf->init_number = ngx_random() % peers->number;

        for (i = 0; i < uiscf->init_number; i++) {
            ngx_http_upstream_iwrr_queue_next(uiscf);
        }
    }
#endif

    for (j = 0; j < peers->number; j++) {
        item = ngx_http_upstream_iwrr_queue_next(uiscf);

        i = item->index;
        peer = item->peer;

        n = i / (8 * sizeof(uintptr_t));
        m = (uintptr_t) 1 << i % (8 * sizeof(uintptr_t));

        if (rrp->tried[n] & m) {
            continue;
        }

        if (peer->down) {
            continue;
        }

#if (NGX_HTTP_UPSTREAM_CHECK)
        if (ngx_http_upstream_check_peer_down(peer->check_index)) {
            continue;
        }
#endif

        if (peer->max_fails
            && peer->fails >= peer->max_fails
            && now - peer->checked <= peer->fail_timeout)
        {
            continue;
        }

        if (peer->max_conns && peer->conns >= peer->max_conns) {
            continue;
        }

        rrp->current = peer;

        return peer;
    }

    return NULL;
}

static ngx_http_upstream_iwrr_queue_t *
ngx_http_upstream_iwrr_queue_next(ngx_http_upstream_iwrr_srv_conf_t *uiscf)
{
    ngx_http_upstream_iwrr_queue_t      *temp, *item;
    
    if (ngx_queue_empty(&uiscf->active->queue)) {
        temp = uiscf->active;
        uiscf->active = uiscf->expired;
        uiscf->expired = temp;
    }

    item = (ngx_http_upstream_iwrr_queue_t *) ngx_queue_head(&uiscf->active->queue);
    ngx_queue_remove(&item->queue);

    item->remainder--;
    if (item->remainder) {
        ngx_queue_insert_tail(&uiscf->active->queue, &item->queue);
    } else {
        item->remainder = item->weight;
        ngx_queue_insert_tail(&uiscf->expired->queue, &item->queue);
    }

    return item;
}

static inline ngx_uint_t ngx_http_upstream_iwrr_gcd(ngx_uint_t a, ngx_uint_t b)
{
    ngx_uint_t  r;
    while (b) {
        r = a % b;
        a = b;
        b = r;
    }
    return a;
}