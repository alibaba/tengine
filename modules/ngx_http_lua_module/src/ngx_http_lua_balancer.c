
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_balancer.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_directive.h"

#define NGX_BALANCER_DEF_HOST_LEN  32
typedef struct {
    ngx_queue_t                    queue;
    ngx_queue_t                    hnode;
    ngx_uint_t                     hash;
    ngx_http_lua_srv_conf_t       *lscf;
    ngx_connection_t              *connection;
    socklen_t                      socklen;
    ngx_sockaddr_t                 sockaddr;
    ngx_sockaddr_t                 local_sockaddr;
    ngx_str_t                      host;
    /* try to avoid allocating memory from the connection pool */
    u_char                         host_data[NGX_BALANCER_DEF_HOST_LEN];
} ngx_http_lua_balancer_ka_item_t; /*balancer keepalive item*/


struct ngx_http_lua_balancer_peer_data_s {
    ngx_uint_t                          keepalive_requests;
    ngx_msec_t                          keepalive_timeout;

    void                               *data;

    ngx_event_get_peer_pt               original_get_peer;
    ngx_event_free_peer_pt              original_free_peer;

#if (NGX_HTTP_SSL)
    ngx_event_set_peer_session_pt       original_set_session;
    ngx_event_save_peer_session_pt      original_save_session;
#endif

    ngx_http_lua_srv_conf_t            *conf;
    ngx_http_request_t                 *request;

    ngx_uint_t                          more_tries;
    ngx_uint_t                          total_tries;

    struct sockaddr                    *sockaddr;
    socklen_t                           socklen;
    ngx_addr_t                         *local;

    ngx_str_t                           host;
    ngx_str_t                          *addr_text;

    int                                 last_peer_state;

#if !(HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
    unsigned                            cloned_upstream_conf:1;
#endif

    unsigned                            keepalive:1;
};


#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_lua_balancer_set_session(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_lua_balancer_save_session(ngx_peer_connection_t *pc,
    void *data);
static ngx_int_t
ngx_http_lua_upstream_get_ssl_name(ngx_http_request_t *r,
    ngx_http_upstream_t *u);
#endif
static ngx_int_t ngx_http_lua_balancer_init(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_lua_balancer_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_lua_balancer_get_peer(ngx_peer_connection_t *pc,
    void *data);
static ngx_int_t ngx_http_lua_balancer_by_chunk(lua_State *L,
    ngx_http_request_t *r);
static void ngx_http_lua_balancer_free_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static void ngx_http_lua_balancer_notify_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t type);
static void ngx_http_lua_balancer_close(ngx_connection_t *c);
static void ngx_http_lua_balancer_dummy_handler(ngx_event_t *ev);
static void ngx_http_lua_balancer_close_handler(ngx_event_t *ev);
static ngx_connection_t *ngx_http_lua_balancer_get_cached_item(
    ngx_http_lua_srv_conf_t *lscf, ngx_peer_connection_t *pc, ngx_str_t *name);
static ngx_uint_t ngx_http_lua_balancer_calc_hash(ngx_str_t *name,
    struct sockaddr *sockaddr, socklen_t socklen, ngx_addr_t *local);


static struct sockaddr  *ngx_http_lua_balancer_default_server_sockaddr;


ngx_int_t
ngx_http_lua_balancer_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadfile(r->connection->log, L,
                                     lscf->balancer.src.data,
                                     &lscf->balancer.src_ref,
                                     lscf->balancer.src_key);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_balancer_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_balancer_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       lscf->balancer.src.data,
                                       lscf->balancer.src.len,
                                       &lscf->balancer.src_ref,
                                       lscf->balancer.src_key,
                                       (const char *) lscf->balancer.chunkname);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_balancer_by_chunk(L, r);
}


char *
ngx_http_lua_balancer_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_balancer_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_balancer_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    size_t                       chunkname_len;
    u_char                      *chunkname;
    u_char                      *cache_key = NULL;
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_srv_conf_t     *lscf = conf;
    ngx_url_t                    url;

    ngx_http_upstream_srv_conf_t      *uscf;
    ngx_http_upstream_server_t        *us;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lscf->balancer.handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    lscf->balancer.handler = (ngx_http_lua_srv_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_balancer_handler_file) {
        /* Lua code in an external file */
        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                    value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->balancer.src.data = name;
        lscf->balancer.src.len = ngx_strlen(name);

    } else {
        cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "balancer_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        chunkname = ngx_http_lua_gen_chunk_name(cf, "balancer_by_lua",
                                                sizeof("balancer_by_lua") - 1,
                                                &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        lscf->balancer.src = value[1];
        lscf->balancer.chunkname = chunkname;
    }

    lscf->balancer.src_key = cache_key;

    /* balancer setup */

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    if (uscf->servers->nelts == 0) {
        us = ngx_array_push(uscf->servers);
        if (us == NULL) {
            return NGX_CONF_ERROR;
        }

        ngx_memzero(us, sizeof(ngx_http_upstream_server_t));
        ngx_memzero(&url, sizeof(ngx_url_t));

        ngx_str_set(&url.url, "0.0.0.1");
        url.default_port = 80;

        if (ngx_parse_url(cf->pool, &url) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        us->name = url.url;
        us->addrs = url.addrs;
        us->naddrs = url.naddrs;

        ngx_http_lua_balancer_default_server_sockaddr = us->addrs[0].sockaddr;
    }

    if (uscf->peer.init_upstream) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "load balancing method redefined");

        lscf->balancer.original_init_upstream = uscf->peer.init_upstream;

    } else {
        lscf->balancer.original_init_upstream =
            ngx_http_upstream_init_round_robin;
    }

    uscf->peer.init_upstream = ngx_http_lua_balancer_init;

    uscf->flags = NGX_HTTP_UPSTREAM_CREATE
                  |NGX_HTTP_UPSTREAM_WEIGHT
                  |NGX_HTTP_UPSTREAM_MAX_FAILS
                  |NGX_HTTP_UPSTREAM_FAIL_TIMEOUT
                  |NGX_HTTP_UPSTREAM_DOWN;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_lua_balancer_init(ngx_conf_t *cf, ngx_http_upstream_srv_conf_t *us)
{
    ngx_uint_t                            i;
    ngx_uint_t                            bucket_cnt;
    ngx_queue_t                          *buckets;
    ngx_http_lua_srv_conf_t              *lscf;
    ngx_http_lua_balancer_ka_item_t      *cached;

    lscf = ngx_http_conf_upstream_srv_conf(us, ngx_http_lua_module);

    ngx_conf_init_uint_value(lscf->balancer.max_cached, 32);

    if (lscf->balancer.original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    lscf->balancer.original_init_peer = us->peer.init;

    us->peer.init = ngx_http_lua_balancer_init_peer;

    /* allocate cache items and add to free queue */

    cached = ngx_pcalloc(cf->pool,
                         sizeof(ngx_http_lua_balancer_ka_item_t)
                         * lscf->balancer.max_cached);
    if (cached == NULL) {
        return NGX_ERROR;
    }

    ngx_queue_init(&lscf->balancer.cache);
    ngx_queue_init(&lscf->balancer.free);

    for (i = 0; i < lscf->balancer.max_cached; i++) {
        ngx_queue_insert_head(&lscf->balancer.free, &cached[i].queue);
        cached[i].lscf = lscf;
    }

    bucket_cnt = lscf->balancer.max_cached / 2;
    bucket_cnt = bucket_cnt > 0 ? bucket_cnt : 1;
    buckets = ngx_pcalloc(cf->pool, sizeof(ngx_queue_t) * bucket_cnt);

    if (buckets == NULL) {
        return NGX_ERROR;
    }

    for (i = 0; i < bucket_cnt; i++) {
        ngx_queue_init(&buckets[i]);
    }

    lscf->balancer.buckets = buckets;
    lscf->balancer.bucket_cnt = bucket_cnt;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_balancer_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_lua_srv_conf_t            *lscf;
    ngx_http_lua_balancer_peer_data_t  *bp;

    lscf = ngx_http_conf_upstream_srv_conf(us, ngx_http_lua_module);

    if (lscf->balancer.original_init_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    bp = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_balancer_peer_data_t));
    if (bp == NULL) {
        return NGX_ERROR;
    }

    bp->conf = lscf;
    bp->request = r;
    bp->data = r->upstream->peer.data;
    bp->original_get_peer = r->upstream->peer.get;
    bp->original_free_peer = r->upstream->peer.free;

    r->upstream->peer.data = bp;
    r->upstream->peer.get = ngx_http_lua_balancer_get_peer;
    r->upstream->peer.free = ngx_http_lua_balancer_free_peer;
    r->upstream->peer.notify = ngx_http_lua_balancer_notify_peer;

#if (NGX_HTTP_SSL)
    bp->original_set_session = r->upstream->peer.set_session;
    bp->original_save_session = r->upstream->peer.save_session;

    r->upstream->peer.set_session = ngx_http_lua_balancer_set_session;
    r->upstream->peer.save_session = ngx_http_lua_balancer_save_session;
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_balancer_get_peer(ngx_peer_connection_t *pc, void *data)
{
    void                               *pdata;
    lua_State                          *L;
    ngx_int_t                           rc;
    ngx_connection_t                   *c;
    ngx_http_request_t                 *r;
#if (NGX_HTTP_SSL)
    ngx_http_upstream_t                *u;
#endif
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_lua_srv_conf_t            *lscf;
    ngx_http_lua_balancer_peer_data_t  *bp = data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua balancer: get peer, tries: %ui", pc->tries);

    r = bp->request;
#if (NGX_HTTP_SSL)
    u = r->upstream;
#endif
    lscf = bp->conf;

    ngx_http_lua_assert(lscf->balancer.handler && r);

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_ERROR;
        }

        L = ngx_http_lua_get_lua_vm(r, ctx);

    } else {
        L = ngx_http_lua_get_lua_vm(r, ctx);

        dd("reset ctx");
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_BALANCER;

    bp->sockaddr = NULL;
    bp->socklen = 0;
    bp->more_tries = 0;
    bp->keepalive_requests = 0;
    bp->keepalive_timeout = 0;
    bp->keepalive = 0;
    bp->total_tries++;

    pdata = r->upstream->peer.data;
    r->upstream->peer.data = bp;

    rc = lscf->balancer.handler(r, lscf, L);

    r->upstream->peer.data = pdata;

    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    if (ctx->exited && ctx->exit_code != NGX_OK) {
        rc = ctx->exit_code;
        if (rc == NGX_ERROR
            || rc == NGX_BUSY
            || rc == NGX_DECLINED
#ifdef HAVE_BALANCER_STATUS_CODE_PATCH
            || rc >= NGX_HTTP_SPECIAL_RESPONSE
#endif
        ) {
            return rc;
        }

        if (rc > NGX_OK) {
            return NGX_ERROR;
        }
    }

    if (bp->local != NULL) {
        pc->local = bp->local;
    }

    if (bp->sockaddr && bp->socklen) {
        pc->sockaddr = bp->sockaddr;
        pc->socklen = bp->socklen;
        pc->name = bp->addr_text;
        pc->cached = 0;
        pc->connection = NULL;

        if (bp->more_tries) {
            r->upstream->peer.tries += bp->more_tries;
        }

        if (bp->keepalive) {
#if (NGX_HTTP_SSL)
            if (bp->host.len == 0 && u->ssl) {
                ngx_http_lua_upstream_get_ssl_name(r, u);
                bp->host = u->ssl_name;
            }
#endif

            c = ngx_http_lua_balancer_get_cached_item(lscf, pc, &bp->host);

            if (c) {
                ngx_log_debug3(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                               "lua balancer: keepalive reusing connection %p,"
                               " host: %V, name: %V",
                               c, bp->addr_text, &bp->host);
                return NGX_DONE;
            }

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "lua balancer: keepalive no free connection, "
                           "host: %V, name: %v",  bp->addr_text, &bp->host);
        }

        return NGX_OK;
    }

    rc = bp->original_get_peer(pc, bp->data);
    if (rc == NGX_ERROR) {
        return rc;
    }

    if (pc->sockaddr == ngx_http_lua_balancer_default_server_sockaddr) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0,
                      "lua balancer: no peer set");

        return NGX_ERROR;
    }

    return rc;
}


static ngx_int_t
ngx_http_lua_balancer_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    u_char                  *err_msg;
    size_t                   len;
    ngx_int_t                rc;

    /* init nginx context in Lua VM */
    ngx_http_lua_set_req(L, r);

#ifndef OPENRESTY_LUAJIT
    ngx_http_lua_create_new_globals_table(L, 0 /* narr */, 1 /* nrec */);

    /*  {{{ make new env inheriting main thread's globals table */
    lua_createtable(L, 0, 1 /* nrec */);   /* the metatable for the new env */
    ngx_http_lua_get_globals_table(L);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
#endif /* OPENRESTY_LUAJIT */

    lua_pushcfunction(L, ngx_http_lua_traceback);
    lua_insert(L, 1);  /* put it under chunk and args */

    /*  protected call user code */
    rc = lua_pcall(L, 0, 1, 1);

    lua_remove(L, 1);  /* remove traceback function */

    dd("rc == %d", (int) rc);

    if (rc != 0) {
        /*  error occurred when running loaded code */
        err_msg = (u_char *) lua_tolstring(L, -1, &len);

        if (err_msg == NULL) {
            err_msg = (u_char *) "unknown reason";
            len = sizeof("unknown reason") - 1;
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to run balancer_by_lua*: %*s", len, err_msg);

        lua_settop(L, 0); /*  clear remaining elems on stack */

        return NGX_ERROR;
    }

    lua_settop(L, 0); /*  clear remaining elems on stack */
    return rc;
}


static void
ngx_http_lua_balancer_free_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_uint_t                                  hash;
    ngx_str_t                                  *host;
    ngx_queue_t                                *q;
    ngx_connection_t                           *c;
    ngx_http_upstream_t                        *u;
    ngx_http_lua_balancer_ka_item_t            *item;
    ngx_http_lua_balancer_peer_data_t          *bp = data;
    ngx_http_lua_srv_conf_t                    *lscf = bp->conf;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua balancer: free peer, tries: %ui", pc->tries);

    u = bp->request->upstream;
    c = pc->connection;

    if (bp->sockaddr && bp->socklen) {
        bp->last_peer_state = (int) state;

        if (pc->tries) {
            pc->tries--;
        }

        if (bp->keepalive) {
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

            if (bp->keepalive_requests
                && c->requests >= bp->keepalive_requests)
            {
                goto invalid;
            }

            if (!u->keepalive) {
                goto invalid;
            }

            if (!u->request_body_sent) {
                goto invalid;
            }

            if (ngx_terminate || ngx_exiting) {
                goto invalid;
            }

            if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
                goto invalid;
            }

            if (ngx_queue_empty(&lscf->balancer.free)) {
                q = ngx_queue_last(&lscf->balancer.cache);

                item = ngx_queue_data(q, ngx_http_lua_balancer_ka_item_t,
                                      queue);
                ngx_queue_remove(q);
                ngx_queue_remove(&item->hnode);

                ngx_http_lua_balancer_close(item->connection);

            } else {
                q = ngx_queue_head(&lscf->balancer.free);
                ngx_queue_remove(q);

                item = ngx_queue_data(q, ngx_http_lua_balancer_ka_item_t,
                                      queue);
            }

            host = &bp->host;
            ngx_log_debug3(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "lua balancer: keepalive saving connection %p, "
                           "host: %V, name: %V",
                           c, bp->addr_text, host);

            ngx_queue_insert_head(&lscf->balancer.cache, q);
            hash = ngx_http_lua_balancer_calc_hash(host,
                                                   bp->sockaddr, bp->socklen,
                                                   bp->local);
            item->hash = hash;
            hash %= lscf->balancer.bucket_cnt;
            ngx_queue_insert_head(&lscf->balancer.buckets[hash], &item->hnode);
            item->connection = c;
            pc->connection = NULL;

            c->read->delayed = 0;
            ngx_add_timer(c->read, bp->keepalive_timeout);

            if (c->write->timer_set) {
                ngx_del_timer(c->write);
            }

            c->write->handler = ngx_http_lua_balancer_dummy_handler;
            c->read->handler = ngx_http_lua_balancer_close_handler;

            c->data = item;
            c->idle = 1;
            c->log = ngx_cycle->log;
            c->read->log = ngx_cycle->log;
            c->write->log = ngx_cycle->log;
            c->pool->log = ngx_cycle->log;

            item->socklen = pc->socklen;
            ngx_memcpy(&item->sockaddr, pc->sockaddr, pc->socklen);
            if (pc->local) {
                ngx_memcpy(&item->local_sockaddr,
                           pc->local->sockaddr, pc->local->socklen);

            } else {
                ngx_memzero(&item->local_sockaddr,
                            sizeof(item->local_sockaddr));
            }

            if (host->data && host->len) {
                if (host->len <= sizeof(item->host_data)) {
                    ngx_memcpy(item->host_data, host->data, host->len);
                    item->host.data = item->host_data;
                    item->host.len = host->len;

                } else {
                    item->host.data = ngx_pstrdup(c->pool, host);
                    if (item->host.data == NULL) {
                        ngx_http_lua_balancer_close(c);

                        ngx_queue_remove(&item->queue);
                        ngx_queue_remove(&item->hnode);
                        ngx_queue_insert_head(&item->lscf->balancer.free,
                                              &item->queue);
                        return;
                    }

                    item->host.len = host->len;
                }

            } else {
                ngx_str_null(&item->host);
            }

            if (c->read->ready) {
                ngx_http_lua_balancer_close_handler(c->read);
            }

            return;

invalid:

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "lua balancer: keepalive not saving connection %p",
                           c);
        }

        return;
    }

    bp->original_free_peer(pc, bp->data, state);
}


static void
ngx_http_lua_balancer_notify_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t type)
{
#ifdef NGX_HTTP_UPSTREAM_NOTIFY_CACHED_CONNECTION_ERROR
    if (type == NGX_HTTP_UPSTREAM_NOTIFY_CACHED_CONNECTION_ERROR) {
        pc->tries--;
    }
#endif
}


static void
ngx_http_lua_balancer_close(ngx_connection_t *c)
{
#if (NGX_HTTP_SSL)
    if (c->ssl) {
        c->ssl->no_wait_shutdown = 1;
        c->ssl->no_send_shutdown = 1;

        if (ngx_ssl_shutdown(c) == NGX_AGAIN) {
            c->ssl->handler = ngx_http_lua_balancer_close;
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "lua balancer: keepalive shutdown "
                           "connection %p failed", c);
            return;
        }
    }
#endif

    ngx_destroy_pool(c->pool);
    ngx_close_connection(c);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua balancer: keepalive closing connection %p", c);
}


static void
ngx_http_lua_balancer_dummy_handler(ngx_event_t *ev)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "lua balancer: dummy handler");
}


static void
ngx_http_lua_balancer_close_handler(ngx_event_t *ev)
{
    ngx_http_lua_balancer_ka_item_t     *item;

    int                n;
    char               buf[1];
    ngx_connection_t  *c;

    c = ev->data;
    if (c->close || c->read->timedout) {
        goto close;
    }

    n = recv(c->fd, buf, 1, MSG_PEEK);

    if (n == -1 && ngx_socket_errno == NGX_EAGAIN) {
        ev->ready = 0;

        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            goto close;
        }

        return;
    }

close:

    item = c->data;
    c->log = ev->log;

    ngx_http_lua_balancer_close(c);

    ngx_queue_remove(&item->queue);
    ngx_queue_remove(&item->hnode);
    ngx_queue_insert_head(&item->lscf->balancer.free, &item->queue);
}


#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_lua_balancer_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_lua_balancer_peer_data_t  *bp = data;

    if (bp->sockaddr && bp->socklen) {
        /* TODO */
        return NGX_OK;
    }

    return bp->original_set_session(pc, bp->data);
}


static void
ngx_http_lua_balancer_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_lua_balancer_peer_data_t  *bp = data;

    if (bp->sockaddr && bp->socklen) {
        /* TODO */
        return;
    }

    bp->original_save_session(pc, bp->data);
}

#endif


int
ngx_http_lua_ffi_balancer_set_current_peer(ngx_http_request_t *r,
    const u_char *addr, size_t addr_len, int port,
    const u_char *host, size_t host_len,
    char **err)
{
    ngx_url_t              url;
    ngx_http_lua_ctx_t    *ctx;
    ngx_http_upstream_t   *u;

    ngx_http_lua_balancer_peer_data_t  *bp;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    ngx_memzero(&url, sizeof(ngx_url_t));

    url.url.data = ngx_palloc(r->pool, addr_len);
    if (url.url.data == NULL) {
        *err = "no memory";
        return NGX_ERROR;
    }

    ngx_memcpy(url.url.data, addr, addr_len);

    url.url.len = addr_len;
    url.default_port = (in_port_t) port;
    url.uri_part = 0;
    url.no_resolve = 1;

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        if (url.err) {
            *err = url.err;
        }

        return NGX_ERROR;
    }

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (url.addrs && url.addrs[0].sockaddr) {
        bp->sockaddr = url.addrs[0].sockaddr;
        bp->socklen = url.addrs[0].socklen;
        bp->addr_text = &url.addrs[0].name;

    } else {
        *err = "no host allowed";
        return NGX_ERROR;
    }

    if (host && host_len) {
        bp->host.data = ngx_palloc(r->pool, host_len);
        if (bp->host.data == NULL) {
            *err = "no memory";
            return NGX_ERROR;
        }

        ngx_memcpy(bp->host.data, host, host_len);
        bp->host.len = host_len;

#if (NGX_HTTP_SSL)
        if (u->ssl) {
            u->ssl_name = bp->host;
        }
#endif

    } else {
        ngx_str_null(&bp->host);
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_bind_to_local_addr(ngx_http_request_t *r,
    const u_char *addr, size_t addr_len,
    u_char *errbuf, size_t *errbuf_size)
{
    u_char                *p;
    ngx_http_lua_ctx_t    *ctx;
    ngx_http_upstream_t   *u;
    ngx_int_t              rc;

    ngx_http_lua_balancer_peer_data_t  *bp;

    if (r == NULL) {
        p = ngx_snprintf(errbuf, *errbuf_size, "no request found");
        *errbuf_size = p - errbuf;
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        p = ngx_snprintf(errbuf, *errbuf_size, "no upstream found");
        *errbuf_size = p - errbuf;
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        p = ngx_snprintf(errbuf, *errbuf_size, "no ctx found");
        *errbuf_size = p - errbuf;
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        p = ngx_snprintf(errbuf, *errbuf_size,
                         "API disabled in the current context");
        *errbuf_size = p - errbuf;
        return NGX_ERROR;
    }

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (bp->local == NULL) {
        bp->local = ngx_palloc(r->pool, sizeof(ngx_addr_t) + addr_len);
        if (bp->local == NULL) {
            p = ngx_snprintf(errbuf, *errbuf_size, "no memory");
            *errbuf_size = p - errbuf;
            return NGX_ERROR;
        }
    }

    rc = ngx_parse_addr_port(r->pool, bp->local, (u_char *) addr, addr_len);
    if (rc == NGX_ERROR) {
        p = ngx_snprintf(errbuf, *errbuf_size, "invalid addr %s", addr);
        *errbuf_size = p - errbuf;
        return NGX_ERROR;
    }

    bp->local->name.len = addr_len;
    bp->local->name.data = (u_char *) (bp->local + 1);
    ngx_memcpy(bp->local->name.data, addr, addr_len);

    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_enable_keepalive(ngx_http_request_t *r,
    unsigned long timeout, unsigned int max_requests, char **err)
{
    ngx_http_upstream_t                     *u;
    ngx_http_lua_ctx_t                      *ctx;
    ngx_http_lua_balancer_peer_data_t       *bp;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (!(bp->sockaddr && bp->socklen)) {
        *err = "no current peer set";
        return NGX_ERROR;
    }

    bp->keepalive_timeout = (ngx_msec_t) timeout;
    bp->keepalive_requests = (ngx_uint_t) max_requests;
    bp->keepalive = 1;

    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_set_timeouts(ngx_http_request_t *r,
    long connect_timeout, long send_timeout, long read_timeout,
    char **err)
{
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_upstream_t                *u;

#if !(HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
    ngx_http_upstream_conf_t           *ucf;
    ngx_http_lua_balancer_peer_data_t  *bp;
#endif

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

#if !(HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (!bp->cloned_upstream_conf) {
        /* we clone the upstream conf for the current request so that
         * we do not affect other requests at all. */

        ucf = ngx_palloc(r->pool, sizeof(ngx_http_upstream_conf_t));

        if (ucf == NULL) {
            *err = "no memory";
            return NGX_ERROR;
        }

        ngx_memcpy(ucf, u->conf, sizeof(ngx_http_upstream_conf_t));

        u->conf = ucf;
        bp->cloned_upstream_conf = 1;

    } else {
        ucf = u->conf;
    }
#endif

    if (connect_timeout > 0) {
#if (HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
        u->connect_timeout = (ngx_msec_t) connect_timeout;
#else
        ucf->connect_timeout = (ngx_msec_t) connect_timeout;
#endif
    }

    if (send_timeout > 0) {
#if (HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
        u->send_timeout = (ngx_msec_t) send_timeout;
#else
        ucf->send_timeout = (ngx_msec_t) send_timeout;
#endif
    }

    if (read_timeout > 0) {
#if (HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
        u->read_timeout = (ngx_msec_t) read_timeout;
#else
        ucf->read_timeout = (ngx_msec_t) read_timeout;
#endif
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_set_more_tries(ngx_http_request_t *r,
    int count, char **err)
{
#if (nginx_version >= 1007005)
    ngx_uint_t                          max_tries, total;
#endif
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_upstream_t                *u;
    ngx_http_lua_balancer_peer_data_t  *bp;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

#if (nginx_version >= 1007005)
    max_tries = r->upstream->conf->next_upstream_tries;
    total = bp->total_tries + r->upstream->peer.tries - 1;

    if (max_tries && total + count > max_tries) {
        count = max_tries - total;
        *err = "reduced tries due to limit";

    } else {
        *err = NULL;
    }
#else
    *err = NULL;
#endif

    bp->more_tries = count;
    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_get_last_failure(ngx_http_request_t *r,
    int *status, char **err)
{
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_upstream_t                *u;
    ngx_http_upstream_state_t          *state;
    ngx_http_lua_balancer_peer_data_t  *bp;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (r->upstream_states && r->upstream_states->nelts > 1) {
        state = r->upstream_states->elts;
        *status = (int) state[r->upstream_states->nelts - 2].status;

    } else {
        *status = 0;
    }

    return bp->last_peer_state;
}


int
ngx_http_lua_ffi_balancer_recreate_request(ngx_http_request_t *r,
    char **err)
{
    ngx_http_lua_ctx_t    *ctx;
    ngx_http_upstream_t   *u;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    /* u->create_request can not be NULL since we are in balancer phase */
    ngx_http_lua_assert(u->create_request != NULL);

    *err = NULL;

    if (u->request_bufs != NULL && u->request_bufs != r->request_body->bufs) {
        /* u->request_bufs already contains a valid request buffer
         * remove it from chain first
         */
        u->request_bufs = r->request_body->bufs;
    }

    return u->create_request(r);
}


int
ngx_http_lua_ffi_balancer_set_upstream_tls(ngx_http_request_t *r, int on,
    char **err)
{
    ngx_http_lua_ctx_t    *ctx;
    ngx_http_upstream_t   *u;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    if (on == 0) {
        u->ssl = 0;
        u->schema.len = sizeof("http://") - 1;

    } else {
        u->ssl = 1;
        u->schema.len = sizeof("https://") - 1;
    }

    return NGX_OK;
}


char *
ngx_http_lua_balancer_keepalive(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_int_t    n;
    ngx_str_t   *value;

#if 0
    ngx_http_upstream_srv_conf_t            *uscf;
#endif
    ngx_http_lua_srv_conf_t                 *lscf = conf;

    if (lscf->balancer.max_cached != NGX_CONF_UNSET_UINT) {
        return "is duplicate";
    }

    /* read options */

    value = cf->args->elts;

    n = ngx_atoi(value[1].data, value[1].len);

    if (n == NGX_ERROR || n == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid value \"%V\" in \"%V\" directive",
                           &value[1], &cmd->name);
        return NGX_CONF_ERROR;
    }

    lscf->balancer.max_cached = n;

    return NGX_CONF_OK;
}


#if (NGX_HTTP_SSL)
static ngx_int_t
ngx_http_lua_upstream_get_ssl_name(ngx_http_request_t *r,
    ngx_http_upstream_t *u)
{
    u_char     *p, *last;
    ngx_str_t   name;

    if (u->conf->ssl_name) {
        if (ngx_http_complex_value(r, u->conf->ssl_name, &name) != NGX_OK) {
            return NGX_ERROR;
        }

    } else {
        name = u->ssl_name;
    }

    if (name.len == 0) {
        goto done;
    }

    /*
     * ssl name here may contain port, notably if derived from $proxy_host
     * or $http_host; we have to strip it. eg: www.example.com:443
     */

    p = name.data;
    last = name.data + name.len;

    if (*p == '[') {
        p = ngx_strlchr(p, last, ']');

        if (p == NULL) {
            p = name.data;
        }
    }

    p = ngx_strlchr(p, last, ':');

    if (p != NULL) {
        name.len = p - name.data;
    }

done:

    u->ssl_name = name;

    return NGX_OK;
}
#endif


static ngx_uint_t
ngx_http_lua_balancer_calc_hash(ngx_str_t *name,
    struct sockaddr *sockaddr, socklen_t socklen, ngx_addr_t *local)
{
    ngx_uint_t hash;

    hash = ngx_hash_key_lc(name->data, name->len);
    hash ^= ngx_hash_key((u_char *) sockaddr, socklen);
    if (local != NULL) {
        hash ^= ngx_hash_key((u_char *) local->sockaddr, local->socklen);
    }

    return hash;
}


static ngx_connection_t *
ngx_http_lua_balancer_get_cached_item(ngx_http_lua_srv_conf_t *lscf,
    ngx_peer_connection_t *pc, ngx_str_t *name)
{
    ngx_uint_t                         hash;
    ngx_queue_t                       *q;
    ngx_queue_t                       *head;
    ngx_connection_t                  *c;
    struct sockaddr                   *sockaddr;
    socklen_t                          socklen;
    ngx_addr_t                        *local;
    ngx_http_lua_balancer_ka_item_t   *item;

    sockaddr = pc->sockaddr;
    socklen = pc->socklen;
    local = pc->local;

    hash = ngx_http_lua_balancer_calc_hash(name, sockaddr, socklen, pc->local);
    head = &lscf->balancer.buckets[hash % lscf->balancer.bucket_cnt];

    c = NULL;
    for (q = ngx_queue_head(head);
        q != ngx_queue_sentinel(head);
        q = ngx_queue_next(q))
    {
        item = ngx_queue_data(q, ngx_http_lua_balancer_ka_item_t, hnode);
        if (item->hash != hash) {
            continue;
        }

        if (name->len == item->host.len
            && ngx_memn2cmp((u_char *) &item->sockaddr,
                            (u_char *) sockaddr,
                            item->socklen, socklen) == 0
            && ngx_strncasecmp(name->data,
                               item->host.data, name->len) == 0
            && (local == NULL
                || ngx_memn2cmp((u_char *) &item->local_sockaddr,
                                (u_char *) local->sockaddr,
                                socklen, local->socklen) == 0))
        {
            c = item->connection;
            ngx_queue_remove(q);
            ngx_queue_remove(&item->queue);
            ngx_queue_insert_head(&lscf->balancer.free, &item->queue);
            c->idle = 0;
            c->sent = 0;
            c->log = pc->log;
            c->read->log = pc->log;
            c->write->log = pc->log;
            c->pool->log = pc->log;

            if (c->read->timer_set) {
                ngx_del_timer(c->read);
            }

            pc->cached = 1;
            pc->connection = c;
            return c;
        }
    }

    return NULL;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
