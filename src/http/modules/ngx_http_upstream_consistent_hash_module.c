
/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include <ngx_md5.h>

#define NGX_CHASH_GREAT                     1
#define NGX_CHASH_EQUAL                     0
#define NGX_CHASH_LESS                      -1
#define NGX_CHASH_VIRTUAL_NODE_NUMBER       160

#ifdef NGX_HTTP_UPSTREAM_CHECK

#define ngx_http_upstream_chash_check_peer_down(peer)                         \
    ngx_http_upstream_check_peer_down((peer)->check_index)

#else

#define ngx_http_upstream_chash_check_peer_down(peer) 0

#endif

#define ngx_chash_diff_abs(a, b) (((a) > (b)) ? (a - b) : (b - a))


typedef struct {
    ngx_event_t                 *ev;
    ngx_ebtree_t                *tree;
    ngx_ebtree_node_t            ebnode;
    ngx_http_upstream_rr_peer_t *peer;
} ngx_http_upstream_chash_server_t;


typedef struct {
    ngx_array_t                    *values;
    ngx_array_t                    *lengths;
    ngx_ebtree_t                   *tree;

    ngx_http_upstream_init_pt       original_init_upstream;
    ngx_http_upstream_init_peer_pt  original_init_peer;
} ngx_http_upstream_chash_srv_conf_t;


typedef struct {
    void                               *data;
    uint32_t                            hash;
    ngx_http_upstream_chash_server_t   *server;
    ngx_http_upstream_chash_srv_conf_t *ucscf;

#if (NGX_HTTP_SSL)

    ngx_event_set_peer_session_pt       original_set_session;
    ngx_event_save_peer_session_pt      original_save_session;

#endif

} ngx_http_upstream_chash_peer_data_t;


static void *ngx_http_upstream_chash_create_srv_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_upstream_init_chash(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_init_chash_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_chash_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_free_chash_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static char *ngx_http_upstream_chash(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_upstream_chash_delete_server(
    ngx_http_upstream_chash_server_t *server);

#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_upstream_chash_set_session(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_chash_save_session(ngx_peer_connection_t *pc,
    void *data);
#endif


static ngx_event_t      *events;
static ngx_connection_t *empty_connections;

static ngx_command_t ngx_http_upstream_chash_commands[] = {

    { ngx_string("consistent_hash"),
      NGX_HTTP_UPS_CONF | NGX_CONF_TAKE1,
      ngx_http_upstream_chash,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t ngx_http_upstream_consistent_hash_module_ctx = {
    NULL,                   /* preconfiguration */
    NULL,                   /* postconfiguration */

    NULL,                   /* create main configuration */
    NULL,                   /* init main configuration */

    ngx_http_upstream_chash_create_srv_conf,
                            /* create server configuration*/
    NULL,                   /* merge server configuration */

    NULL,                   /* create location configuration */
    NULL                    /* merge location configuration */
};

ngx_module_t ngx_http_upstream_consistent_hash_module = {
    NGX_MODULE_V1,
    &ngx_http_upstream_consistent_hash_module_ctx,
                            /* module context */
    ngx_http_upstream_chash_commands,
                            /* module directives */
    NGX_HTTP_MODULE,        /* module type */
    NULL,                   /* init master */
    NULL,                   /* init module */
    NULL,                   /* init process */
    NULL,                   /* init thread */
    NULL,                   /* exit thread */
    NULL,                   /* exit process */
    NULL,                   /* exit master */
    NGX_MODULE_V1_PADDING
};


static void *
ngx_http_upstream_chash_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_upstream_chash_srv_conf_t *ucscf;

    ucscf = ngx_pcalloc(cf->pool, sizeof(ngx_http_upstream_chash_srv_conf_t));
    if (ucscf == NULL) {
        return NULL;
    }

    return ucscf;
}


static void
ngx_http_upstream_chash_recover(ngx_event_t *ev)
{
    ngx_uint_t                        i, n;
    ngx_array_t                      *down_servers;
    ngx_connection_t                 *ec;
    ngx_http_upstream_chash_server_t *server, **p;

    if (ngx_quit ||  ngx_exiting || ngx_terminate) {
        return;
    }

    ec = ev->data;
    down_servers = ec->data;
    p = down_servers->elts;
    n = down_servers->nelts;
    if (n > 0) {
        server = p[0];
        if ((ngx_http_upstream_chash_check_peer_down(server->peer))) {
            ngx_add_timer(server->ev, 10000);
            return;
        }
        server->peer->down = 0;
        server->peer->fails = 0;
    }

    down_servers->nelts = 0;
    for (i = 0; i <n; i--) {
        server = p[i];
        ngx_ebtree_insert(server->tree, &server->ebnode);
    }
}


static ngx_int_t
ngx_http_upstream_init_chash(ngx_conf_t *cf, ngx_http_upstream_srv_conf_t *us)
{
    u_char                               hash_buf[256];
    ngx_int_t                            j, weight;
    ngx_uint_t                           sid, id, hash_len;
    ngx_uint_t                           i, n;
    ngx_array_t                         *array;
    ngx_http_upstream_rr_peer_t         *peer;
    ngx_http_upstream_rr_peers_t        *peers;
    ngx_http_upstream_chash_server_t    *server;
    ngx_http_upstream_chash_srv_conf_t  *ucscf;
    
    ucscf = ngx_http_conf_upstream_srv_conf(us,
                                     ngx_http_upstream_consistent_hash_module);

    if (ucscf->original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    ucscf->original_init_peer = us->peer.init;
    us->peer.init = ngx_http_upstream_init_chash_peer;

    ucscf->tree = ngx_ebtree_create(cf->pool);
    if (ucscf->tree == NULL) {
        return NGX_ERROR;
    }

    peers = (ngx_http_upstream_rr_peers_t *) us->peer.data;
    if (peers == NULL) {
        return NGX_ERROR;
    }

    n = peers->number;
    empty_connections = ngx_pcalloc(cf->pool, n * sizeof(ngx_connection_t));
    if (empty_connections == NULL) {
        return NGX_ERROR;
    }

    events = ngx_pcalloc(cf->pool, n * sizeof(ngx_event_t));
    if (events == NULL) {
        return NGX_ERROR;
    }

    for (i = 0; i < n; i++) {
        peer = &peers->peer[i];
        sid = (ngx_uint_t) ngx_atoi(peer->id.data, peer->id.len);
        
        if (sid == (ngx_uint_t) NGX_ERROR || sid > 65535) {
            ngx_snprintf(hash_buf, 256, "%V%Z", &peer->name);
            hash_len = ngx_strlen(hash_buf);
            sid = ngx_murmur_hash2(hash_buf, hash_len);
        }

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, cf->log, 0, "server id %d", sid);
        weight = peer->weight * NGX_CHASH_VIRTUAL_NODE_NUMBER;

        if (weight >= 1 << 14) {
            ngx_log_error(NGX_LOG_WARN, cf->log, 0,
                          "weigth[%d] is too large, is must be less than %d",
                          weight / NGX_CHASH_VIRTUAL_NODE_NUMBER,
                          (1 << 14) / NGX_CHASH_VIRTUAL_NODE_NUMBER);
            weight = 1 << 14;
        }

        array = ngx_array_create(cf->pool, weight,
                                 sizeof(ngx_http_upstream_chash_server_t));
        if (array == NULL) {
            return NGX_ERROR;
        }

        empty_connections[i].data = array;
        events[i].data = &empty_connections[i];
        events[i].log = &cf->cycle->new_log;
        events[i].handler = ngx_http_upstream_chash_recover;

        for (j = 0; j < weight; j++) {
            server = ngx_pcalloc(cf->pool,
                                 sizeof(ngx_http_upstream_chash_server_t));
            if (server == NULL) {
                return NGX_ERROR;
            }
            server->peer = peer;
            id = sid * 256 * 16 + j;
            server->ebnode.key = ngx_murmur_hash2((u_char *) (&id), 4);
            server->tree = ucscf->tree;
            server->ebnode.data = server;
            server->ev = &events[i];
            ngx_ebtree_insert(ucscf->tree, &server->ebnode);
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_init_chash_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_str_t                            hash_value;
    ngx_http_upstream_chash_srv_conf_t  *ucscf;
    ngx_http_upstream_chash_peer_data_t *uchpd;

    ucscf = ngx_http_conf_upstream_srv_conf(us,
                                     ngx_http_upstream_consistent_hash_module);

    uchpd = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_chash_peer_data_t));
    if (uchpd == NULL) {
        return NGX_ERROR;
    }

    if (ucscf->original_init_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    uchpd->ucscf = ucscf;
    if (ngx_http_script_run(r, &hash_value,
                ucscf->lengths->elts, 0, ucscf->values->elts) == NULL) {
        return NGX_ERROR;
    }
    uchpd->hash = ngx_murmur_hash2(hash_value.data, hash_value.len);
    uchpd->data = r->upstream->peer.data;

    r->upstream->peer.get = ngx_http_upstream_get_chash_peer;
    r->upstream->peer.free = ngx_http_upstream_free_chash_peer;
    r->upstream->peer.data = uchpd;

#if (NGX_HTTP_SSL)
    uchpd->original_set_session = r->upstream->peer.set_session;
    uchpd->original_save_session = r->upstream->peer.save_session;
    r->upstream->peer.set_session = ngx_http_upstream_chash_set_session;
    r->upstream->peer.save_session = ngx_http_upstream_chash_save_session;
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_get_chash_peer(ngx_peer_connection_t *pc, void *data)
{
    uint32_t                             diff_ge, diff_le;
    ngx_int_t                            rc;
    ngx_ebtree_node_t                   *node, *node_ge, *node_le;
    ngx_http_upstream_rr_peer_t         *peer;
    ngx_http_upstream_chash_server_t    *server;
    ngx_http_upstream_chash_srv_conf_t  *ucscf;
    ngx_http_upstream_chash_peer_data_t *uchpd = data;

    ucscf = uchpd->ucscf;

    pc->cached = 0;
    pc->connection = NULL;

    while (1) {

        node_le = ngx_ebtree_le(ucscf->tree, uchpd->hash);
        node_ge = ngx_ebtree_ge(ucscf->tree, uchpd->hash);

        if (node_le == NULL) {
            if (node_ge == NULL) {
                ngx_log_error(NGX_LOG_ERR, pc->log, 0, "all servers are down");
                return NGX_BUSY;
            }
            node = node_ge;

        } else if (node_ge == NULL) {
            node = node_le;

        } else {
            diff_le = ngx_chash_diff_abs(node_le->key, uchpd->hash);
            diff_ge = ngx_chash_diff_abs(node_ge->key, uchpd->hash);
            node = diff_le <= diff_ge ? node_le : node_ge;
        }

        server = (ngx_http_upstream_chash_server_t *) node->data;
        if (ngx_http_upstream_chash_check_peer_down(server->peer)) {
            rc = ngx_http_upstream_chash_delete_server(server);
            if (rc != NGX_OK) {
                return rc;
            }
            continue;
        }
        break;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "consistent hash [peer name]:%V %ud",
                   &server->peer->name, server->ebnode.key);

    uchpd->server = server;
    peer = server->peer;

    pc->name = &peer->name;
    pc->sockaddr = peer->sockaddr;
    pc->socklen = peer->socklen;

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_chash_delete_server(ngx_http_upstream_chash_server_t *server)
{
    ngx_array_t      *down_servers;
    ngx_connection_t *ec;
    ngx_http_upstream_chash_server_t **p;

    ec = server->ev->data;
    down_servers = ec->data;

    p = ngx_array_push(down_servers);
    if (p == NULL) {
        return NGX_ERROR;
    }
    *p = server;

    ngx_ebtree_delete(&server->ebnode);
    if (!server->ev->timer_set) {
        ngx_add_timer(server->ev, 10000);
    }

    return NGX_OK;
}


static void
ngx_http_upstream_free_chash_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_http_upstream_chash_peer_data_t *uchpd = data;

    ngx_log_debug(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                  "consistent hash free  peer %ui", state);

    if (uchpd->server == NULL) {
        return;
    }

    if (state & NGX_PEER_FAILED) {
        uchpd->server->peer->fails++;
        if (uchpd->server->peer->max_fails
            && uchpd->server->peer->fails >= uchpd->server->peer->max_fails)
        {
            ngx_log_error(NGX_LOG_ERR, pc->log, 0,
                          "server down %V, fails %d, max_fails %d",
                          &uchpd->server->peer->name,
                          uchpd->server->peer->fails,
                          uchpd->server->peer->max_fails);

            ngx_http_upstream_chash_delete_server(uchpd->server);
        }
    }
}


static char *
ngx_http_upstream_chash(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                           *value;
    ngx_http_script_compile_t            sc;
    ngx_http_upstream_srv_conf_t        *uscf;
    ngx_http_upstream_chash_srv_conf_t  *ucscf;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);
    if (uscf == NULL) {
        return NGX_CONF_ERROR;
    }

    ucscf = ngx_http_conf_upstream_srv_conf(uscf,
                                     ngx_http_upstream_consistent_hash_module);
    if (ucscf == NULL) {
        return NGX_CONF_ERROR;
    }

    if (ucscf->original_init_upstream) {
        return "is duplicate";
    }

    ucscf->original_init_upstream = uscf->peer.init_upstream
                                    ? uscf->peer.init_upstream
                                    : ngx_http_upstream_init_round_robin;

    value = cf->args->elts;
    if (value == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_memzero(&sc, sizeof(ngx_http_script_compile_t));

    sc.cf = cf;
    sc.source = &value[1];
    sc.lengths = &ucscf->lengths;
    sc.values = &ucscf->values;
    sc.complete_lengths = 1;
    sc.complete_values = 1;

    if (ngx_http_script_compile(&sc) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    uscf->peer.init_upstream = ngx_http_upstream_init_chash;

    uscf->flags = NGX_HTTP_UPSTREAM_CREATE
                  |NGX_HTTP_UPSTREAM_ID
                  |NGX_HTTP_UPSTREAM_WEIGHT
                  |NGX_HTTP_UPSTREAM_MAX_FAILS
                  |NGX_HTTP_UPSTREAM_FAIL_TIMEOUT
                  |NGX_HTTP_UPSTREAM_DOWN;

    return NGX_CONF_OK;
}


#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_upstream_chash_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_chash_peer_data_t *uchpd = data;

    return uchpd->original_set_session(pc, uchpd->data);
}


static void
ngx_http_upstream_chash_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_chash_peer_data_t *uchpd = data;

    uchpd->original_save_session(pc, uchpd->data);
    return;
}

#endif
