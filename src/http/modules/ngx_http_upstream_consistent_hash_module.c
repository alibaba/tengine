
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include <ngx_md5.h>

#define NGX_CHASH_GREAT                     1
#define NGX_CHASH_EQUAL                     0
#define NGX_CHASH_LESS                      -1
#define NGX_CHASH_VIRTUAL_NODE_NUMBER       160


typedef struct ngx_http_upstream_chash_event_data_s
                        ngx_http_upstream_chash_event_data_t;
#if (NGX_HTTP_UPSTREAM_CHECK)
#include "ngx_http_upstream_check_module.h"
#endif

typedef struct {
    time_t                                  timeout;
    ngx_int_t                               id;
    ngx_queue_t                             queue;
} ngx_http_upstream_chash_down_server_t;

typedef struct {
    uint32_t                     hash;
    ngx_uint_t                   index;
    ngx_uint_t                   rnindex;
    ngx_http_upstream_rr_peer_t *peer;
} ngx_http_upstream_chash_server_t;


typedef struct {
    uint32_t                              step;
    ngx_uint_t                            tries;
    ngx_uint_t                            number;
    ngx_flag_t                            native;
    ngx_array_t                          *values;
    ngx_array_t                          *lengths;
    ngx_segment_tree_t                   *tree;
    ngx_http_upstream_chash_server_t     *servers;
    ngx_http_upstream_chash_event_data_t *events;
} ngx_http_upstream_chash_srv_conf_t;


struct ngx_http_upstream_chash_event_data_s {
    ngx_uint_t                          num;
    ngx_event_t                         ev;
    ngx_http_upstream_chash_server_t  **servers;
    ngx_http_upstream_chash_srv_conf_t *ucscf;
};


typedef struct {
    uint32_t                            hash;

#if (NGX_HTTP_SSL)
    ngx_ssl_session_t                  *ssl_session;
#endif

    ngx_http_upstream_chash_server_t       *server;
    ngx_http_upstream_chash_srv_conf_t     *ucscf;
} ngx_http_upstream_chash_peer_data_t;


static void *ngx_http_upstream_chash_create_srv_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_upstream_init_chash(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static uint32_t ngx_http_upstream_chash_md5(u_char *str, size_t len);
static uint32_t ngx_murmur_hash(u_char *data, size_t len, uint32_t seed);
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
static char *ngx_http_upstream_chash_tries(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static uint32_t ngx_http_upstream_chash_get_server_index(
    ngx_http_upstream_chash_server_t *servers, uint32_t n, uint32_t hash);
static void ngx_http_upstream_chash_recover(ngx_event_t *ev);
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
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE1,
      ngx_http_upstream_chash,
      0,
      0,
      NULL },

    { ngx_string("consistent_mode"),
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE1,
      ngx_http_upstream_chash_mode,
      0,
      0,
      NULL },

    { ngx_string("consistent_tries"),
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE1,
      ngx_http_upstream_chash_tries,
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


static ngx_connection_t empty_connection;


static void *
ngx_http_upstream_chash_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_upstream_chash_srv_conf_t *ucscf;

    ucscf = ngx_pcalloc(cf->pool, sizeof(ngx_http_upstream_chash_srv_conf_t));
    if (ucscf == NULL) {
        return NULL;
    }

    ucscf->native = 1;
    ucscf->tries = NGX_CONF_UNSET_UINT;

    return ucscf;
}


static ngx_int_t
ngx_http_upstream_init_chash(ngx_conf_t *cf, ngx_http_upstream_srv_conf_t *us)
{
    ngx_uint_t                          sid, id;
    u_char                              hash_buf[256];
    ngx_uint_t                          hash_len;
    ngx_int_t                           j, weight;
    ngx_uint_t                          i, n, num;
    ngx_http_upstream_rr_peer_t        *peer;
    ngx_http_upstream_rr_peers_t       *peers;
    ngx_http_upstream_chash_server_t   *server;
    ngx_http_upstream_chash_srv_conf_t *ucscf;

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
    ucscf->events = ngx_pcalloc(cf->pool,
                            n * sizeof(ngx_http_upstream_chash_event_data_t));
    if (ucscf->events == NULL) {
        return NGX_ERROR;
    }

    for (i = 0; i < n; i++) {
        num = peers->peer[i].weight * NGX_CHASH_VIRTUAL_NODE_NUMBER;
        ucscf->number += num;
        ucscf->events[i].servers = ngx_pcalloc(cf->pool, num
                                   * sizeof(ngx_http_upstream_chash_server_t));
        if (ucscf->events[i].servers == NULL) {
            return NGX_ERROR;
        }
        ucscf->events[i].num = 0;
        ucscf->events[i].ev.data = &empty_connection;
        ucscf->events[i].ev.log = &cf->cycle->new_log;
        ucscf->events[i].ev.handler = ngx_http_upstream_chash_recover;
        ucscf->events[i].ucscf = ucscf;
    }

    ucscf->tries = ucscf->tries == NGX_CONF_UNSET_UINT ? n : ucscf->tries;

    ucscf->servers = ngx_pcalloc(cf->pool,
                                 (ucscf->number + 1) *
                                 sizeof(ngx_http_upstream_chash_server_t));
    if (ucscf->servers == NULL) {
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
            sid = ngx_http_upstream_chash_md5(hash_buf, hash_len);
        }

        weight = peer->weight * NGX_CHASH_VIRTUAL_NODE_NUMBER;
        if (weight >= 1<<14) {
            ngx_log_error(NGX_LOG_EMERG, cf->log,
                                        0, "weigth[%d] is too large", weight);
            weight = 1<<14;
        }
        for (j = 0; j < weight; j++) {
            server = &ucscf->servers[++ucscf->number];
            server->peer = peer;
            server->rnindex = i;
            id = sid * 256 * 16 + j;
            server->hash = ngx_murmur_hash((u_char *) (&id),
                                           4,
                                           0x9e3779b9);
            ngx_snprintf(hash_buf, 256, "%V#%i%Z", &peer->name, j);
            hash_len = ngx_strlen(hash_buf);
            server->hash = ngx_http_upstream_chash_md5(hash_buf, hash_len);
        }
    }

    ngx_qsort(ucscf->servers + 1, ucscf->number,
              sizeof(ngx_http_upstream_chash_server_t),
              (const void *)ngx_http_upstream_chash_cmp);

    ucscf->tree = ngx_pcalloc(cf->pool, sizeof(ngx_segment_tree_t));
    if (ucscf->tree == NULL) {
        return NGX_ERROR;
    }

    ngx_segment_tree_init(ucscf->tree, ucscf->number, cf->pool);

    ucscf->tree->build(ucscf->tree, 1, 1, ucscf->number);

    ucscf->step = NGX_MAX_UINT32_VALUE / ucscf->number;

    for (i = 1; i <= ucscf->number; i++) {
        server = &ucscf->servers[i];
        num = ucscf->events[server->rnindex].num++;
        ucscf->events[server->rnindex].servers[num] = server;
        server->index = i;
    }

    return NGX_OK;
}


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
    uchpd->hash = ngx_murmur_hash(hash_value.data, hash_value.len, 0x9e3779b9);

    r->upstream->peer.get = ngx_http_upstream_get_chash_peer;
    r->upstream->peer.free = ngx_http_upstream_free_chash_peer;
    r->upstream->peer.data = uchpd;
    r->upstream->peer.tries = ucscf->tries;

#if (NGX_HTTP_SSL)
    r->upstream->peer.set_session = ngx_http_upstream_chash_set_peer_session;
    r->upstream->peer.save_session = ngx_http_upstream_chash_save_peer_session;
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_get_chash_peer(ngx_peer_connection_t *pc, void *data)
{
    uint32_t                             index, index_1, index_2;
    uint32_t                             diff_1, diff_2;
    ngx_segment_node_t                  *p;
    ngx_http_upstream_rr_peer_t         *peer;
    ngx_http_upstream_chash_server_t    *server;
    ngx_http_upstream_chash_srv_conf_t  *ucscf;
    ngx_http_upstream_chash_peer_data_t *uchpd = data;

    ucscf = uchpd->ucscf;

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

    if (ngx_http_upstream_check_peer_down(server->peer->check_index)
		|| (server->peer->max_fails
			&& server->peer->fails > server->peer->max_fails)
        || server->peer->down)
    {
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
                    ngx_log_error(NGX_LOG_ERR, pc->log, 0,
								 "all servers are down!");
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

            if (ngx_http_upstream_check_peer_down(server->peer->check_index)
				|| (server->peer->max_fails
					&& server->peer->fails > server->peer->max_fails)
				|| server->peer->down)
            {
                ngx_http_upstream_chash_delete_node(ucscf, server);

            } else {
                break;
            }

            index = index_1;
        }
    }

    if (server->peer->down) {
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
ngx_http_upstream_chash_recover(ngx_event_t *ev)
{
    ngx_uint_t                            i;
    ngx_segment_node_t                    node;
    ngx_http_upstream_chash_server_t     *server;
    ngx_http_upstream_chash_srv_conf_t   *ucscf;
    ngx_http_upstream_chash_event_data_t *event;

    event = (ngx_http_upstream_chash_event_data_t *) ((u_char *) ev -
                           offsetof(ngx_http_upstream_chash_event_data_t, ev));
    ucscf = event->ucscf;

    if (ngx_http_upstream_check_peer_down(event->servers[0]->peer->check_index))
    {
        if (ngx_terminate || ngx_exiting || ngx_quit) {
            return;
        }

        ngx_add_timer(&event->ev, 10000);
        return;
    }

    event->servers[0]->peer->down = 0;
    event->servers[0]->peer->fails = 0;

    for (i = 0; i < event->num; i++) {
        server = event->servers[i];
        server->peer->down = 0;
        server->peer->fails = 0;

        node.key = server->index;
        ucscf->tree->insert(ucscf->tree, 1, 1, ucscf->number,
                            server->index, &node);
    }

    ngx_log_error(NGX_LOG_ERR, ev->log, 0, "chash server %V recovers",
                  &event->servers[0]->peer->name);
}


static void
ngx_http_upstream_chash_delete_node(ngx_http_upstream_chash_srv_conf_t *ucscf,
    ngx_http_upstream_chash_server_t *server)
{
    ngx_uint_t                            i;
    ngx_http_upstream_chash_event_data_t *event;

    if (server->peer->down) {
        return;
    }

    event = &ucscf->events[server->rnindex];
    event->servers[0]->peer->down = 1;
    for (i = 0; i < event->num; i++) {
        server = event->servers[i];
        server->peer->down = 1;

        ucscf->tree->del(ucscf->tree, 1, 1, ucscf->number, server->index);
    }

    ngx_add_timer(&event->ev, 10000);
    ngx_log_error(NGX_LOG_ERR, event->ev.log, 0, "chash server %V is down",
                  &server->peer->name);
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
                  | NGX_HTTP_UPSTREAM_ID
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


static char *
ngx_http_upstream_chash_tries(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_int_t                            tries;
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
    tries = ngx_atoi(value[1].data, value[1].len);
    if (tries == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    ucscf->tries = (ngx_uint_t) tries;
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
