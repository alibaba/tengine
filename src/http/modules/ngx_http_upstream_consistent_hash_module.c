
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include <ngx_md5.h>

#define NGX_CHASH_GREAT                     1
#define NGX_CHASH_EQUAL                     0
#define NGX_CHASH_LESS                      -1
#define NGX_CHASH_VIRTUAL_NODE_NUMBER       160

typedef struct {
    time_t                                  timeout;
    ngx_int_t                               id;
    ngx_queue_t                             queue;
} ngx_http_upstream_chash_down_server_t;

typedef struct {
    u_char                                  down;
    uint32_t                                hash;
    ngx_uint_t                              index;
    ngx_uint_t                              rnindex;
    ngx_http_upstream_rr_peer_t            *peer;
} ngx_http_upstream_chash_server_t;

typedef struct {
    ngx_uint_t                              number;
    ngx_queue_t                             down_servers;
    ngx_array_t                            *values;
    ngx_array_t                            *lengths;
    ngx_segment_tree_t                     *tree;
    ngx_http_upstream_chash_server_t     ***real_node;
    ngx_http_upstream_chash_server_t       *servers;
    ngx_http_upstream_chash_down_server_t  *d_servers;
} ngx_http_upstream_chash_srv_conf_t;

typedef struct {
    uint32_t                                hash;

#if (NGX_HTTP_SSL)
    ngx_ssl_session_t                  *ssl_session;
#endif

    ngx_http_upstream_chash_server_t       *server;
    ngx_http_upstream_chash_srv_conf_t     *ucscf;
} ngx_http_upstream_chash_peer_data_t;


static void *ngx_http_upstream_chash_create_srv_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_upstream_init_chash(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_chash_cmp(const void *one, const void *two);
static ngx_int_t ngx_http_upstream_init_chash_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_chash_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_free_chash_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static char *ngx_http_upstream_chash(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static uint32_t ngx_http_upstream_chash_get_server_index(
    ngx_http_upstream_chash_server_t *servers, uint32_t n, uint32_t hash);
static void ngx_http_upstream_chash_delete_node(
    ngx_http_upstream_chash_srv_conf_t *ucscf,
    ngx_http_upstream_chash_server_t *server);

#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_upstream_chash_set_peer_session(
    ngx_peer_connection_t *pc, void *data);
static void ngx_http_upstream_chash_save_peer_session(ngx_peer_connection_t *pc,
    void *data);
#endif


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


static ngx_int_t
ngx_http_upstream_init_chash(ngx_conf_t *cf, ngx_http_upstream_srv_conf_t *us)
{
    u_char                               hash_buf[256];
    ngx_int_t                            j, weight;
    ngx_uint_t                           sid, id, hash_len;
    ngx_uint_t                           i, n, *number, rnindex;
    ngx_http_upstream_rr_peer_t         *peer;
    ngx_http_upstream_rr_peers_t        *peers;
    ngx_http_upstream_chash_server_t    *server;
    ngx_http_upstream_chash_srv_conf_t  *ucscf;

    if (ngx_http_upstream_init_round_robin(cf, us) == NGX_ERROR) {
        return NGX_ERROR;
    }

    ucscf = ngx_http_conf_upstream_srv_conf(us,
                                     ngx_http_upstream_consistent_hash_module);
    if (ucscf == NULL) {
        return NGX_ERROR;
    }

    us->peer.init = ngx_http_upstream_init_chash_peer;

    peers = (ngx_http_upstream_rr_peers_t *) us->peer.data;
    if (peers == NULL) {
        return NGX_ERROR;
    }

    n = peers->number;
    ucscf->number = 0;
    ucscf->real_node = ngx_pcalloc(cf->pool, n *
                                   sizeof(ngx_http_upstream_chash_server_t**));
    if (ucscf->real_node == NULL) {
        return NGX_ERROR;
    }
    for (i = 0; i < n; i++) {
        ucscf->number += peers->peer[i].weight * NGX_CHASH_VIRTUAL_NODE_NUMBER;
        ucscf->real_node[i] = ngx_pcalloc(cf->pool,
                                    (peers->peer[i].weight
                                     * NGX_CHASH_VIRTUAL_NODE_NUMBER + 1) *
                                     sizeof(ngx_http_upstream_chash_server_t*));
        if (ucscf->real_node[i] == NULL) {
            return NGX_ERROR;
        }
    }

    ucscf->servers = ngx_pcalloc(cf->pool,
                                 (ucscf->number + 1) *
                                  sizeof(ngx_http_upstream_chash_server_t));

    if (ucscf->servers == NULL) {
        return NGX_ERROR;
    }

    ucscf->d_servers = ngx_pcalloc(cf->pool,
                                (ucscf->number + 1) *
                                sizeof(ngx_http_upstream_chash_down_server_t));

    if (ucscf->d_servers == NULL) {
        return NGX_ERROR;
    }

    ucscf->number = 0;
    for (i = 0; i < n; i++) {

        peer = &peers->peer[i];
        sid = (ngx_uint_t) ngx_atoi(peer->id.data, peer->id.len);

        if (sid == (ngx_uint_t) NGX_ERROR || sid > 65535) {

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, cf->log, 0, "server id %d", sid);

            ngx_snprintf(hash_buf, 256, "%V%Z", &peer->name);
            hash_len = ngx_strlen(hash_buf);
            sid = ngx_murmur_hash2(hash_buf, hash_len);
        }

        weight = peer->weight * NGX_CHASH_VIRTUAL_NODE_NUMBER;

        if (weight >= 1 << 14) {
            ngx_log_error(NGX_LOG_WARN, cf->log, 0,
                          "weigth[%d] is too large, is must be less than %d",
                          weight / NGX_CHASH_VIRTUAL_NODE_NUMBER,
                          (1 << 14) / NGX_CHASH_VIRTUAL_NODE_NUMBER);
            weight = 1 << 14;
        }

        for (j = 0; j < weight; j++) {
            server = &ucscf->servers[++ucscf->number];
            server->peer = peer;
            server->rnindex = i;

            id = sid * 256 * 16 + j;
            server->hash = ngx_murmur_hash2((u_char *) (&id), 4);
        }
    }

    ngx_qsort(ucscf->servers + 1, ucscf->number,
              sizeof(ngx_http_upstream_chash_server_t),
              (const void *)ngx_http_upstream_chash_cmp);

    number = ngx_calloc(n * sizeof(ngx_uint_t), cf->log);
    if (number == NULL) {
        return NGX_ERROR;
    }

    for (i = 1; i <= ucscf->number; i++) {
        ucscf->servers[i].index = i;
        ucscf->d_servers[i].id = i;
        rnindex = ucscf->servers[i].rnindex;
        ucscf->real_node[rnindex][number[rnindex]] = &ucscf->servers[i];
        number[rnindex]++;
    }

    ngx_free(number);

    ucscf->tree = ngx_pcalloc(cf->pool, sizeof(ngx_segment_tree_t));
    if (ucscf->tree == NULL) {
        return NGX_ERROR;
    }

    ngx_segment_tree_init(ucscf->tree, ucscf->number, cf->pool);
    ucscf->tree->build(ucscf->tree, 1, 1, ucscf->number);

    ngx_queue_init(&ucscf->down_servers);

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_chash_cmp(const void *one, const void *two)
{
    ngx_http_upstream_chash_server_t *frist, *second;

    frist = (ngx_http_upstream_chash_server_t *)one;
    second = (ngx_http_upstream_chash_server_t *) two;

    if (frist->hash > second->hash) {
        return NGX_CHASH_GREAT;

    } else if (frist->hash == second->hash) {
        return NGX_CHASH_EQUAL;

    } else {
        return NGX_CHASH_LESS;
    }
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
    if (ucscf == NULL) {
        return NGX_ERROR;
    }

    uchpd = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_chash_peer_data_t));
    if (uchpd == NULL) {
        return NGX_ERROR;
    }

    uchpd->ucscf = ucscf;
    if (ngx_http_script_run(r, &hash_value,
                ucscf->lengths->elts, 0, ucscf->values->elts) == NULL) {
        return NGX_ERROR;
    }

    uchpd->hash = ngx_murmur_hash2(hash_value.data, hash_value.len);

    r->upstream->peer.get = ngx_http_upstream_get_chash_peer;
    r->upstream->peer.free = ngx_http_upstream_free_chash_peer;
    r->upstream->peer.data = uchpd;

#if (NGX_HTTP_SSL)
    r->upstream->peer.set_session = ngx_http_upstream_chash_set_peer_session;
    r->upstream->peer.save_session = ngx_http_upstream_chash_save_peer_session;
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_get_chash_peer(ngx_peer_connection_t *pc, void *data)
{

    time_t                                  now;
    uint32_t                                index, index1, index2;
    uint32_t                                diff1, diff2;
    ngx_queue_t                            *q, *temp;
    ngx_segment_node_t                      node, *p;
    ngx_http_upstream_rr_peer_t            *peer;
    ngx_http_upstream_chash_server_t       *server;
    ngx_http_upstream_chash_srv_conf_t     *ucscf;
    ngx_http_upstream_chash_peer_data_t    *uchpd = data;
    ngx_http_upstream_chash_down_server_t  *down_server;

    ucscf = uchpd->ucscf;

    if (!ngx_queue_empty(&ucscf->down_servers)) {
        q = ngx_queue_head(&ucscf->down_servers);
        while(q != ngx_queue_sentinel(&ucscf->down_servers)) {
            temp = ngx_queue_next(q);
            down_server = ngx_queue_data(q,
                                         ngx_http_upstream_chash_down_server_t,
                                         queue);
            now = ngx_time();
            if (now >= down_server->timeout) {
                peer = ucscf->servers[down_server->id].peer;
#if (NGX_HTTP_UPSTREAM_CHECK)
                if (!ngx_http_upstream_check_peer_down(peer->check_index)) {
#endif
                    peer->fails = 0;
                    peer->down = 0;
                    ucscf->servers[down_server->id].down = 0;

                    ngx_queue_remove(&down_server->queue);
                    node.key = down_server->id;
                    ucscf->tree->insert(ucscf->tree, 1, 1, ucscf->number,
                                        down_server->id, &node);
#if (NGX_HTTP_UPSTREAM_CHECK)
                }
#endif
            }
            q = temp;
        }
    }

    pc->cached = 0;
    pc->connection = NULL;

    index = ngx_http_upstream_chash_get_server_index(ucscf->servers,
                                                     ucscf->number,
                                                     uchpd->hash);
    server = &ucscf->servers[index];

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "consistent hash [peer name]:%V %ud",
                   &server->peer->name, server->hash);

    if (
#if (NGX_HTTP_UPSTREAM_CHECK)
            ngx_http_upstream_check_peer_down(server->peer->check_index) ||
#endif
            server->peer->fails > server->peer->max_fails
            || server->peer->down
        ) {

        ngx_http_upstream_chash_delete_node(ucscf, server);

        while (1) {

            p = ucscf->tree->query(ucscf->tree, 1, 1, ucscf->number,
                                   1, index - 1);
            index1 = p->key;

            p = ucscf->tree->query(ucscf->tree, 1, 1, ucscf->number,
                                   index + 1, ucscf->number);
            index2 = p->key;

            if (index1 == ucscf->tree->extreme) {

                if (index2 == ucscf->tree->extreme) {
                    ngx_log_error(NGX_LOG_ERR, pc->log, 0,
                                  "all servers are down!");
                    return NGX_BUSY;

                } else {
                    index1 = index2;
                    server = &ucscf->servers[index2];
                }

            } else if (index2 == ucscf->tree->extreme) {
                server = &ucscf->servers[index1];

            } else {

                if (ucscf->servers[index1].hash > uchpd->hash) {
                    diff1 = ucscf->servers[index1].hash - uchpd->hash;

                } else {
                    diff1 = uchpd->hash - ucscf->servers[index1].hash;
                }

                if (uchpd->hash > ucscf->servers[index2].hash) {
                    diff2 = uchpd->hash - ucscf->servers[index2].hash;

                } else {
                    diff2 = ucscf->servers[index2].hash - uchpd->hash;
                }

                index1 = diff1 > diff2 ? index2 : index1;

                server = &ucscf->servers[index1];
            }

            if (
#if (NGX_HTTP_UPSTREAM_CHECK)
            ngx_http_upstream_check_peer_down(server->peer->check_index) ||
#endif
                server->peer->fails > server->peer->max_fails
                || server->peer->down)
            {
                ngx_http_upstream_chash_delete_node(ucscf, server);

            } else {
                break;
            }

            index = index1;
        }
    }

    if (server->down) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0, "all servers are down");
        return NGX_BUSY;
    }

    uchpd->server = server;
    peer = server->peer;

    pc->name = &peer->name;
    pc->sockaddr = peer->sockaddr;
    pc->socklen = peer->socklen;

    return NGX_OK;
}


static void
ngx_http_upstream_chash_delete_node(ngx_http_upstream_chash_srv_conf_t *ucscf,
    ngx_http_upstream_chash_server_t *server)
{
    ngx_http_upstream_chash_server_t **servers, *p;
    servers = ucscf->real_node[server->rnindex];

    for (; *servers; servers++) {
        p = *servers;
        if (!p->down) {
            ucscf->tree->del(ucscf->tree, 1, 1, ucscf->number, p->index);
            p->down = 1;
            ucscf->d_servers[p->index].timeout = ngx_time()
                                               + p->peer->fail_timeout;
            ngx_queue_insert_head(&ucscf->down_servers,
                                  &ucscf->d_servers[p->index].queue);
        }
    }
}


static uint32_t
ngx_http_upstream_chash_get_server_index(
    ngx_http_upstream_chash_server_t *servers, uint32_t n, uint32_t hash)
{
    uint32_t  low, hight, mid;

    low = 1;
    hight = n;

    while (low < hight) {
        mid = (low + hight) >> 1;
        if (servers[mid].hash == hash) {
            return mid;

        } else if (servers[mid].hash < hash) {
            low = mid + 1;

        } else {
            hight = mid;
        }
    }

    if (low == n && servers[low].hash < hash) {
      return 1;
    }

    return low;
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
    if(ucscf == NULL) {
        return NGX_CONF_ERROR;
    }

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
ngx_http_upstream_chash_set_peer_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_chash_peer_data_t *uchpd = data;

    ngx_int_t            rc;
    ngx_ssl_session_t   *ssl_session;

    ssl_session = uchpd->ssl_session;
    rc = ngx_ssl_set_session(pc->connection, ssl_session);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "set session: %p:%d",
                   ssl_session, ssl_session ? ssl_session->references : 0);

    return rc;
}


static void
ngx_http_upstream_chash_save_peer_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_chash_peer_data_t *uchpd = data;

    ngx_ssl_session_t   *old_ssl_session, *ssl_session;

    ssl_session = ngx_ssl_get_session(pc->connection);

    if (ssl_session == NULL) {
        return;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "save session: %p:%d", ssl_session, ssl_session->references);

    old_ssl_session = uchpd->ssl_session;
    uchpd->ssl_session = ssl_session;

    if (old_ssl_session) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "old session: %p:%d",
                       old_ssl_session, old_ssl_session->references);

        ngx_ssl_free_session(old_ssl_session);
    }
}

#endif
