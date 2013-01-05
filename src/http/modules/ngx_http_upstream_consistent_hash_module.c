
/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include <ngx_md5.h>


typedef struct {
    time_t                                  timeout;
    ngx_int_t                               id;
    ngx_queue_t                             queue;
} ngx_http_upstream_chash_down_server_t;

typedef struct {
    u_char                                  down;
    uint32_t                                hash;
    ngx_uint_t                              index;
    ngx_uint_t                              rnindex; // real node index
#ifdef NGX_HTTP_UPSTREAM_ID
    ngx_int_t                               sid;
#endif
    ngx_http_upstream_rr_peer_t            *peer;
} ngx_http_upstream_chash_server_t;

typedef struct {
    uint32_t                                step;
    ngx_uint_t                              tries;
    ngx_uint_t                              number;
    ngx_flag_t                              native;
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
    ngx_http_upstream_chash_server_t       *server;
    ngx_http_upstream_chash_srv_conf_t     *ucscf;
} ngx_http_upstream_chash_peer_data_t;


static void *ngx_http_upstream_chash_create_srv_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_upstream_init_chash(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
#ifndef NGX_HTTP_UPSTREAM_ID
static uint32_t ngx_http_upstream_chash_md5(u_char *str, size_t len);
#else
static uint32_t ngx_murmur_hash(u_char *data, size_t len, uint32_t seed);
#endif
static ngx_int_t ngx_http_upstream_chash_cmp(const void *one, const void *two);
static ngx_int_t ngx_http_upstream_init_chash_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_chash_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_free_chash_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static char *ngx_http_upstream_chash(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_upstream_chash_mode(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static uint32_t ngx_http_upstream_chash_get_server_index(
    ngx_http_upstream_chash_server_t *servers, uint32_t n, uint32_t hash);
static void ngx_http_upstream_chash_delete_node(
    ngx_http_upstream_chash_srv_conf_t *ucscf,
    ngx_http_upstream_chash_server_t *server);


static ngx_command_t ngx_http_upstream_chash_commands[] = {

    { ngx_string("consistent_hash"),
      NGX_HTTP_UPS_CONF | NGX_CONF_TAKE1,
      ngx_http_upstream_chash,
      0,
      0,
      NULL },

    { ngx_string("consistent_mode"),
      NGX_HTTP_UPS_CONF | NGX_CONF_TAKE1,
      ngx_http_upstream_chash_mode,
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

    ucscf->native = 0;

    return ucscf;
}


static ngx_int_t
ngx_http_upstream_init_chash(ngx_conf_t *cf, ngx_http_upstream_srv_conf_t *us)
{
#ifdef NGX_HTTP_UPSTREAM_ID
    ngx_uint_t                               sid, id;
#else
    u_char                                   hash_buf[256];
    ngx_uint_t                               hash_len;
#endif
    ngx_int_t                                j, weight;
    ngx_uint_t                               i, n;
    ngx_http_upstream_rr_peer_t             *peer;
    ngx_http_upstream_rr_peers_t            *peers;
    ngx_http_upstream_chash_server_t        *server;
    ngx_http_upstream_chash_srv_conf_t      *ucscf;

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
    ucscf->tries = n;
    ucscf->number = 0;
    ucscf->real_node = ngx_pcalloc(cf->pool, n *
                                   sizeof(ngx_http_upstream_chash_server_t**));
    if (ucscf->real_node == NULL) {
        return NGX_ERROR;
    }
    for (i = 0; i < n; i++) {
        ucscf->number += peers->peer[i].weight * 16;
        ucscf->real_node[i] = ngx_pcalloc(cf->pool,
                                          (peers->peer[i].weight * 16 + 1) *
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
    for (i = 0; i < n ; i++) {
        peer = &peers->peer[i];
#ifdef NGX_HTTP_UPSTREAM_ID
        sid = (ngx_uint_t) ngx_atoi(peer->id.data, peer->id.len);
        if (sid == (ngx_uint_t) NGX_ERROR || sid > 65535) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, cf->log, 0, "server id %d", sid);
            sid = i;
        }

#endif
        weight = peer->weight * 16;
        for (j = 0; j < weight; j++) {
            server = &ucscf->servers[++ucscf->number];
            server->peer = peer;
            server->rnindex = i;
            ucscf->real_node[i][j] = server;
#ifdef NGX_HTTP_UPSTREAM_ID
            id = sid * 256 * 16 + j;
            server->hash = ngx_murmur_hash((u_char *) (&id),
                                           4,
                                           0x9e3779b9);
#else
            ngx_snprintf(hash_buf, 256, "%V#%i%Z", &peer->name, j);
            hash_len = ngx_strlen(hash_buf);
            server->hash = ngx_http_upstream_chash_md5(hash_buf, hash_len);
#endif
        }
    }

    ngx_qsort(ucscf->servers + 1, ucscf->number,
              sizeof(ngx_http_upstream_chash_server_t),
              (const void *)ngx_http_upstream_chash_cmp);

    for (i = 1; i <= ucscf->number; i++) {
        ucscf->servers[i].index = i;
        ucscf->d_servers[i].id = i;
    }

    ucscf->tree = ngx_pcalloc(cf->pool, sizeof(ngx_segment_tree_t));
    if (ucscf->tree == NULL) {
        return NGX_ERROR;
    }

    ngx_segment_tree_init(ucscf->tree, ucscf->number, cf->pool);

    ucscf->tree->build(ucscf->tree, 1, 1, ucscf->number);

    ucscf->step = NGX_MAX_UINT32_VALUE / ucscf->number;

    ngx_queue_init(&ucscf->down_servers);

    return NGX_OK;
}


#ifndef NGX_HTTP_UPSTREAM_ID
static uint32_t
ngx_http_upstream_chash_md5(u_char *str, size_t len)
{
    u_char      md5_buf[16];
    ngx_md5_t   md5;

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, str, len);
    ngx_md5_final(md5_buf, &md5);

    return ngx_crc32_long(md5_buf, 16);
}

#else
static uint32_t
ngx_murmur_hash(u_char *data, size_t len, uint32_t seed)
{
    uint32_t  h, k;

    h = seed ^ len;

    while (len >= 4) {
        k  = data[0];
        k |= data[1] << 8;
        k |= data[2] << 16;
        k |= data[3] << 24;

        k *= 0x5bd1e995;
        k ^= k >> 24;
        k *= 0x5bd1e995;

        h *= 0x5bd1e995;
        h ^= k;

        data += 4;
        len -= 4;
    }

    switch (len) {
    case 3:
        h ^= data[2] << 16;
    case 2:
        h ^= data[1] << 8;
    case 1:
        h ^= data[0];
        h *= 0x5bd1e995;
    }

    h ^= h >> 13;
    h *= 0x5bd1e995;
    h ^= h >> 15;

    return h;
}
#endif


static ngx_int_t
ngx_http_upstream_chash_cmp(const void *one, const void *two)
{
    ngx_http_upstream_chash_server_t *frist, *second;

    frist = (ngx_http_upstream_chash_server_t *)one;
    second = (ngx_http_upstream_chash_server_t *) two;

    if (frist->hash > second->hash) {
        return 1;
    } else if (frist->hash == second->hash) {
        return 0;
    } else {
        return -1;
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
#ifdef NGX_HTTP_UPSTREAM_ID
    uchpd->hash = ngx_murmur_hash(hash_value.data, hash_value.len, 0x9e3779b9);
#else
    uchpd->hash = ngx_crc32_long(hash_value.data, hash_value.len);
#endif

    r->upstream->peer.get = ngx_http_upstream_get_chash_peer;
    r->upstream->peer.free = ngx_http_upstream_free_chash_peer;
    r->upstream->peer.data = uchpd;
    r->upstream->peer.tries = ucscf->tries;

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_get_chash_peer(ngx_peer_connection_t *pc, void *data)
{

    time_t                                   now;
    uint32_t                                 index, index_1, index_2;
    uint32_t                                 diff_1, diff_2;
    ngx_queue_t                             *q, *temp;
    ngx_segment_node_t                       node, *p;
    ngx_http_upstream_rr_peer_t             *peer;
    ngx_http_upstream_chash_server_t        *server;
    ngx_http_upstream_chash_srv_conf_t      *ucscf;
    ngx_http_upstream_chash_peer_data_t     *uchpd = data;
    ngx_http_upstream_chash_down_server_t   *down_server;

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

    if (ucscf->native) {
        index = ngx_http_upstream_chash_get_server_index(ucscf->servers,
                                                         ucscf->number,
                                                         uchpd->hash);
    } else {
        index = uchpd->hash / ucscf->step;
    }

    if (index < 1) {
        index = 1;

    } else if (index > ucscf->number) {
        index = ucscf->number;
    }

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
            index_1 = p->key;
            p = ucscf->tree->query(ucscf->tree, 1, 1, ucscf->number,
                                   index + 1, ucscf->number);
            index_2 = p->key;

            if (index_1 == ucscf->tree->extreme) {

                if (index_2 == ucscf->tree->extreme) {
                    ngx_log_error(NGX_LOG_ERR, pc->log, 0, "all servers are down!");
                    return NGX_BUSY;

                } else {
                    index_1 = index_2;
                    server = &ucscf->servers[index_2];
                }

            } else if (index_2 == ucscf->tree->extreme) {
                server = &ucscf->servers[index_1];

            } else {
                if (ucscf->servers[index_1].hash > uchpd->hash) {
                    diff_1 = ucscf->servers[index_1].hash - uchpd->hash;

                } else {
                    diff_1 = uchpd->hash - ucscf->servers[index_1].hash;
                }

                if (uchpd->hash > ucscf->servers[index_2].hash) {
                    diff_2 = uchpd->hash - ucscf->servers[index_2].hash;

                } else {
                    diff_2 = ucscf->servers[index_2].hash - uchpd->hash;
                }

                index_1 = diff_1 > diff_2 ? index_2 : index_1;

                server = &ucscf->servers[index_1];
            }

            if (
#if (NGX_HTTP_UPSTREAM_CHECK)
            ngx_http_upstream_check_peer_down(server->peer->check_index) ||
#endif
                server->peer->fails > server->peer->max_fails
                || server->peer->down
                )
            {
                ngx_http_upstream_chash_delete_node(ucscf, server);

            } else {
                break;
            }

            index = index_1;
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
    uint32_t    low, hight, mid;

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
    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "consistent hash free  peer %ui %ui", pc->tries, state);

    if (uchpd->server == NULL) {
        return;
    }

    if (state & NGX_PEER_FAILED) {
        uchpd->server->peer->fails++;
    }

    if (pc->tries) {
        pc->tries--;
    }

    return;
}


static char *
ngx_http_upstream_chash(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                                       *value;
    ngx_http_script_compile_t                        sc;
    ngx_http_upstream_srv_conf_t                    *uscf;
    ngx_http_upstream_chash_srv_conf_t              *ucscf;

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
#ifdef NGX_HTTP_UPSTREAM_ID
                  | NGX_HTTP_UPSTREAM_ID
#endif
                  | NGX_HTTP_UPSTREAM_WEIGHT
                  | NGX_HTTP_UPSTREAM_MAX_FAILS
                  | NGX_HTTP_UPSTREAM_FAIL_TIMEOUT
                  | NGX_HTTP_UPSTREAM_DOWN;

    return NGX_CONF_OK;
}


static char *
ngx_http_upstream_chash_mode(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                           *value;
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

    value = cf->args->elts;
    if (ngx_strncmp(value[1].data,"quick", 5) == 0) {
        ucscf->native = 0;

    } else if (ngx_strncmp(value[1].data, "native", 6) == 0) {
        ucscf->native = 1;

    }

    return NGX_CONF_OK;
}
