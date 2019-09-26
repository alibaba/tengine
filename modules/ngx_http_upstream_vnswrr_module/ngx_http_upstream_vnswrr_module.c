
/*
 *  Copyright (C) 2010-2019 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#if (NGX_HTTP_UPSTREAM_CHECK)
#include "ngx_http_upstream_check_module.h"
#endif


typedef struct  ngx_http_upstream_rr_vpeers_s ngx_http_upstream_rr_vpeers_t;


struct ngx_http_upstream_rr_vpeers_s {
    ngx_int_t                    rindex;
    ngx_http_upstream_rr_peer_t *vpeer;
};


typedef struct ngx_http_upstream_vnswrr_srv_conf_s
    ngx_http_upstream_vnswrr_srv_conf_t;


struct ngx_http_upstream_vnswrr_srv_conf_s {
    ngx_uint_t                            vnumber;
    ngx_uint_t                            last_number;
    ngx_uint_t                            init_number;
    ngx_http_upstream_rr_peer_t          *last_peer;
    ngx_http_upstream_rr_vpeers_t        *vpeers;
    ngx_http_upstream_vnswrr_srv_conf_t  *next;
};


typedef struct {
    /* the round robin data must be first */
    ngx_http_upstream_rr_peer_data_t      rrp;

    ngx_http_upstream_vnswrr_srv_conf_t  *uvnscf;
} ngx_http_upstream_vnswrr_peer_data_t;


static char *ngx_http_upstream_vnswrr(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static void *ngx_http_upstream_vnswrr_create_srv_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_upstream_init_vnswrr(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_init_vnswrr_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_vnswrr_peer(ngx_peer_connection_t *pc,
    void *data);
static ngx_int_t ngx_http_upstream_get_rr_peer(ngx_http_upstream_rr_peers_t *peers,
    ngx_http_upstream_rr_peer_t **rpeer);
static ngx_http_upstream_rr_peer_t *ngx_http_upstream_get_vnswrr(
    ngx_http_upstream_vnswrr_peer_data_t *vnsp);
static void ngx_http_upstream_init_virtual_peers(
    ngx_http_upstream_rr_peers_t *peers,
    ngx_http_upstream_vnswrr_srv_conf_t *uvnscf,
    ngx_uint_t s, ngx_uint_t e);


static ngx_command_t  ngx_http_upstream_vnswrr_commands[] = {

    { ngx_string("vnswrr"),
      NGX_HTTP_UPS_CONF|NGX_CONF_NOARGS,
      ngx_http_upstream_vnswrr,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_upstream_vnswrr_module_ctx = {
    NULL,                                      /* preconfiguration */
    NULL,                                      /* postconfiguration */

    NULL,                                      /* create main configuration */
    NULL,                                      /* init main configuration */

    ngx_http_upstream_vnswrr_create_srv_conf,  /* create server configuration */
    NULL,                                      /* merge server configuration */

    NULL,                                      /* create location configuration */
    NULL                                       /* merge location configuration */
};


ngx_module_t  ngx_http_upstream_vnswrr_module = {
    NGX_MODULE_V1,
    &ngx_http_upstream_vnswrr_module_ctx,  /* module context */
    ngx_http_upstream_vnswrr_commands,     /* module directives */
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


static void *
ngx_http_upstream_vnswrr_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_upstream_vnswrr_srv_conf_t *uvnscf;

    uvnscf = ngx_pcalloc(cf->pool, sizeof(ngx_http_upstream_vnswrr_srv_conf_t));
    if (uvnscf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     uvnscf->vnumber = 0;
     *     uvnscf->vpeers = NULL;
     *     uvnscf->last_peer = NULL;
     *     uvnscf->next = NULL;
     */

    uvnscf->init_number = NGX_CONF_UNSET_UINT;
    uvnscf->last_number = NGX_CONF_UNSET_UINT;

    return uvnscf;
}


static char *
ngx_http_upstream_vnswrr(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_upstream_srv_conf_t  *uscf;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    if (uscf->peer.init_upstream) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "load balancing method redefined");
    }

    uscf->peer.init_upstream = ngx_http_upstream_init_vnswrr;

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


static ngx_int_t
ngx_http_upstream_init_vnswrr(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_upstream_rr_peers_t           *peers, *backup;
    ngx_http_upstream_vnswrr_srv_conf_t    *uvnscf, *ubvnscf;


    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0, "init vnswrr");

    if (ngx_http_upstream_init_round_robin(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    uvnscf = ngx_http_conf_upstream_srv_conf(us,
                                ngx_http_upstream_vnswrr_module);
    if (uvnscf == NULL) {
        return NGX_ERROR;
    }

    uvnscf->init_number = NGX_CONF_UNSET_UINT;
    uvnscf->last_number = NGX_CONF_UNSET_UINT;
    uvnscf->last_peer = NULL;
    uvnscf->next = NULL;

    us->peer.init = ngx_http_upstream_init_vnswrr_peer;

    peers = (ngx_http_upstream_rr_peers_t *) us->peer.data;
    if (peers->weighted) {
        uvnscf->vpeers = ngx_pcalloc(cf->pool,
                                    sizeof(ngx_http_upstream_rr_vpeers_t)
                                    * peers->total_weight);
        if (uvnscf->vpeers == NULL) {
            return NGX_ERROR;
        }

        ngx_http_upstream_init_virtual_peers(peers, uvnscf, 0, peers->number);

    }

    /* backup peers */
    backup = peers->next;
    if (backup) {
        ubvnscf = ngx_pcalloc(cf->pool,
                              sizeof(ngx_http_upstream_vnswrr_srv_conf_t));
        if (ubvnscf == NULL) {
            return NGX_ERROR;
        }

        ubvnscf->init_number = NGX_CONF_UNSET_UINT;
        ubvnscf->last_number = NGX_CONF_UNSET_UINT;
        ubvnscf->last_peer = NULL;

        uvnscf->next = ubvnscf;

        if (!backup->weighted) {
            return NGX_OK;
        }

        ubvnscf->vpeers = ngx_pcalloc(cf->pool,
                                      sizeof(ngx_http_upstream_rr_vpeers_t)
                                      * backup->total_weight);
        if (ubvnscf->vpeers == NULL) {
            return NGX_ERROR;
        }

        ngx_http_upstream_init_virtual_peers(backup, ubvnscf, 0, backup->number);
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_init_vnswrr_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_upstream_vnswrr_srv_conf_t    *uvnscf;
    ngx_http_upstream_vnswrr_peer_data_t   *vnsp;

    uvnscf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_vnswrr_module);

    vnsp = ngx_palloc(r->pool, sizeof(ngx_http_upstream_vnswrr_peer_data_t));
    if (vnsp == NULL) {
        return NGX_ERROR;
    }

    vnsp->uvnscf = uvnscf;
    r->upstream->peer.data = &vnsp->rrp;

    if (ngx_http_upstream_init_round_robin_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    r->upstream->peer.get = ngx_http_upstream_get_vnswrr_peer;

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_get_vnswrr_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_vnswrr_peer_data_t  *vnsp = data;

    ngx_int_t                              rc;
    ngx_uint_t                             i, n;
    ngx_http_upstream_rr_peer_t           *peer;
    ngx_http_upstream_rr_peers_t          *peers;
    ngx_http_upstream_rr_peer_data_t      *rrp;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "get vnswrr peer, try: %ui", pc->tries);

    pc->cached = 0;
    pc->connection = NULL;

    rrp = &vnsp->rrp;

    peers = rrp->peers;
    ngx_http_upstream_rr_peers_wlock(peers);

    if (peers->single) {
        peer = peers->peer;

        if (peer->down) {
            goto failed;
        }

#if defined(nginx_version) && nginx_version >= 1011005
        if (peer->max_conns && peer->conns >= peer->max_conns) {
            goto failed;
        }
#endif

#if (NGX_HTTP_UPSTREAM_CHECK)
        if (ngx_http_upstream_check_peer_down(peer->check_index)) {
            goto failed;
        }
#endif
        rrp->current = peer;

    } else {

        /* there are several peers */

        peer = ngx_http_upstream_get_vnswrr(vnsp);

        if (peer == NULL) {
            goto failed;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "get vnswrr peer, current: %p %i",
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

        vnsp->uvnscf = vnsp->uvnscf ? vnsp->uvnscf->next : vnsp->uvnscf;

        n = (rrp->peers->number + (8 * sizeof(uintptr_t) - 1))
                / (8 * sizeof(uintptr_t));

        for (i = 0; i < n; i++) {
            rrp->tried[i] = 0;
        }

        ngx_http_upstream_rr_peers_unlock(peers);

        rc = ngx_http_upstream_get_vnswrr_peer(pc, vnsp);

        if (rc != NGX_BUSY) {
            return rc;
        }

        ngx_http_upstream_rr_peers_wlock(peers);
    }

    ngx_http_upstream_rr_peers_unlock(peers);

    pc->name = peers->name;

    return NGX_BUSY;
}


static ngx_int_t
ngx_http_upstream_get_rr_peer(ngx_http_upstream_rr_peers_t *peers,
    ngx_http_upstream_rr_peer_t **rpeer)
{
    ngx_int_t                      total;
    ngx_uint_t                     i, p;
    ngx_http_upstream_rr_peer_t  *peer, *best;

    best = NULL;
    p = 0;
    total = 0;
    for (peer = peers->peer, i = 0; peer; peer = peer->next, i++) {
        peer->current_weight += peer->effective_weight;
        total += peer->effective_weight;

        if (best == NULL || peer->current_weight > best->current_weight) {
            best = peer;
            p = i;
        }
    }

    *rpeer = best;
    if (best == NULL) {
        return NGX_ERROR;
    }

    best->current_weight -= total;

    return p;
}


static ngx_http_upstream_rr_peer_t *
ngx_http_upstream_get_vnswrr(ngx_http_upstream_vnswrr_peer_data_t  *vnsp)
{
    time_t                                  now;
    uintptr_t                               m;
    ngx_uint_t                              i, n, p, flag, begin_number;
    ngx_http_upstream_rr_peer_t            *peer, *best;
    ngx_http_upstream_rr_peers_t           *peers;
    ngx_http_upstream_rr_vpeers_t          *vpeers;
    ngx_http_upstream_rr_peer_data_t       *rrp;
    ngx_http_upstream_vnswrr_srv_conf_t    *uvnscf;

    now = ngx_time();

    best = NULL;

#if (NGX_SUPPRESS_WARN)
    p = 0;
#endif

    rrp = &vnsp->rrp;
    peers = rrp->peers;
    uvnscf = vnsp->uvnscf;
    vpeers = uvnscf->vpeers;

    if (uvnscf->last_number == NGX_CONF_UNSET_UINT) {
        uvnscf->init_number = ngx_random() % peers->number;

        if (peers->weighted) {
            peer = vpeers[uvnscf->init_number].vpeer;

        } else {
            for (peer = peers->peer, i = 0; i < uvnscf->init_number; i++) {
                peer = peer->next;
            }
        }

        uvnscf->last_number = uvnscf->init_number;
        uvnscf->last_peer = peer;
    }

    if (peers->weighted) {
        /* batch initialization vpeers at runtime. */
        if (uvnscf->vnumber != peers->total_weight
            && (uvnscf->last_number + 1 == uvnscf->vnumber))
        {
            n = peers->total_weight - uvnscf->vnumber;
            if (n > peers->number) {
                n = peers->number;
            }

            ngx_http_upstream_init_virtual_peers(peers, uvnscf, uvnscf->vnumber,
			                         n + uvnscf->vnumber);

        }

        begin_number = (uvnscf->last_number + 1) % uvnscf->vnumber;
        peer = vpeers[begin_number].vpeer;

    } else {
        if (uvnscf->last_peer && uvnscf->last_peer->next) {
            begin_number = (uvnscf->last_number + 1) % peers->number;
            peer = uvnscf->last_peer->next;

        } else {
            begin_number = 0;
            peer = peers->peer;
        }
    }

    for (i = begin_number, flag = 1; i != begin_number || flag;
         i = peers->weighted
         ? ((i + 1) % uvnscf->vnumber) : ((i + 1) % peers->number),
         peer = peers->weighted
         ? vpeers[i].vpeer : (peer->next ? peer->next : peers->peer))
    {

        flag = 0;
        if (peers->weighted) {

            n = peers->total_weight - uvnscf->vnumber;
            if (n > peers->number) {
                n = peers->number;
            }

            ngx_http_upstream_init_virtual_peers(peers, uvnscf, uvnscf->vnumber,
			                         n + uvnscf->vnumber);

            n = vpeers[i].rindex / (8 * sizeof(uintptr_t));
            m = (uintptr_t) 1 << vpeers[i].rindex % (8 * sizeof(uintptr_t));

        } else {
            n =  i / (8 * sizeof(uintptr_t));
            m = (uintptr_t) 1 << i % (8 * sizeof(uintptr_t));
        }

        if (rrp->tried[n] & m) {
            continue;
        }

        if (peer->down) {
            continue;
        }

        if (peer->max_fails
            && peer->fails >= peer->max_fails
            && now - peer->checked <= peer->fail_timeout)
        {
            continue;
        }

#if defined(nginx_version) && nginx_version >= 1011005
        if (peer->max_conns && peer->conns >= peer->max_conns) {
            continue;
        }
#endif

#if (NGX_HTTP_UPSTREAM_CHECK)
        if (ngx_http_upstream_check_peer_down(peer->check_index)) {
            continue;
        }
#endif

        best = peer;
        uvnscf->last_peer = peer;
        uvnscf->last_number = i;
        p = i;
        break;
    }

    if (best == NULL) {
        return NULL;
    }

    rrp->current = best;

    if (peers->weighted) {
        n = vpeers[p].rindex / (8 * sizeof(uintptr_t));
        m = (uintptr_t) 1 << vpeers[p].rindex % (8 * sizeof(uintptr_t));

    } else {
        n = p / (8 * sizeof(uintptr_t));
        m = (uintptr_t) 1 << p % (8 * sizeof(uintptr_t));
    }

    rrp->tried[n] |= m;

    if (now - best->checked > best->fail_timeout) {
        best->checked = now;
    }

    return best;
}


static void 
ngx_http_upstream_init_virtual_peers(ngx_http_upstream_rr_peers_t *peers,
                                     ngx_http_upstream_vnswrr_srv_conf_t *uvnscf,
                                     ngx_uint_t s, ngx_uint_t e)
{
    ngx_uint_t                              i;
    ngx_int_t                               rindex;
    ngx_http_upstream_rr_peer_t            *peer;
    ngx_http_upstream_rr_vpeers_t          *vpeers;

    if (uvnscf == NULL || peers == NULL) {
        return;
    }

    vpeers = uvnscf->vpeers;
    
    for (i = s; i < e; i++) {
        rindex = ngx_http_upstream_get_rr_peer(peers, &peer);
        if (rindex == NGX_ERROR) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "get rr peer is null in upstream \"%V\" ",
                          peers->name);
            if (i != 0) {
                i--;
            }
    
            continue;
        }
    
        vpeers[i].vpeer = peer;
        vpeers[i].rindex = rindex;
    }
    
    uvnscf->vnumber = i;

    return;
}
