
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_http_connection_pool.h>


static void ngx_http_connection_pool_close(ngx_connection_t *c);
static void ngx_http_connection_pool_close_handler(ngx_event_t *ev);
static void ngx_http_connection_pool_dummy_handler(ngx_event_t *ev);

static ngx_int_t ngx_http_connection_pool_get(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_connection_pool_free(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);


ngx_http_connection_pool_t *
ngx_http_connection_pool_init(ngx_pool_t *pool, ngx_uint_t max_cached,
    ngx_uint_t bucket_count)
{
    ngx_uint_t                      j, k;
    ngx_http_connection_pool_t     *conn_pool;
    ngx_http_connection_pool_elt_t *cached;

    conn_pool = ngx_pcalloc(pool, sizeof(ngx_http_connection_pool_t));
    if (conn_pool == NULL) {
        return NULL;
    }

    conn_pool->bucket_count = bucket_count;
    conn_pool->max_cached = max_cached;

    conn_pool->cache = ngx_pcalloc(pool, sizeof(ngx_queue_t) * bucket_count);
    if (conn_pool->cache == NULL) {
        return NULL;
    }

    conn_pool->free = ngx_pcalloc(pool, sizeof(ngx_queue_t) * bucket_count);
    if (conn_pool->free == NULL) {
        return NULL;
    }

    for (j = 0; j < bucket_count; j++) {
        ngx_queue_init(&conn_pool->cache[j]);
        ngx_queue_init(&conn_pool->free[j]);
        cached = ngx_pcalloc(pool,
                           sizeof(ngx_http_connection_pool_elt_t) * max_cached);
        if (cached == NULL) {
            return NULL;
        }

        for (k = 0; k < max_cached; k++) {
            ngx_queue_insert_head(&conn_pool->free[j], &cached[k].queue);
        }
    }

    conn_pool->get_peer = ngx_http_connection_pool_get;
    conn_pool->free_peer = ngx_http_connection_pool_free;
    return conn_pool;
}


ngx_int_t
ngx_http_connection_pool_get(ngx_peer_connection_t *pc, void *data)
{
    u_char                         pc_addr[32] = {'\0'};
    ngx_uint_t                     bucket_id, hash;
    ngx_queue_t                    *q, *cache, *free;
    ngx_connection_t               *c;
    ngx_http_connection_pool_t     *p;
    ngx_http_connection_pool_elt_t *item;

    p = data;

#if (NGX_DEBUG)
    p->count--;
#endif

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0, "get keepalive peer");

    p->failed = 0;

    hash = ngx_murmur_hash2((u_char *) pc->sockaddr, pc->socklen);
    bucket_id = hash % p->bucket_count;

    cache = &p->cache[bucket_id];
    free = &p->free[bucket_id];

    ngx_sprintf(pc_addr, "%s:%d",
                inet_ntoa(((struct sockaddr_in*)(pc->sockaddr))->sin_addr),
                ntohs(((struct sockaddr_in*)(pc->sockaddr))->sin_port));

    for (q = ngx_queue_head(cache);
         q != ngx_queue_sentinel(cache);
         q = ngx_queue_next(q))
    {
        item = ngx_queue_data(q, ngx_http_connection_pool_elt_t, queue);
        c = item->connection;

        if (ngx_memn2cmp((u_char *) &item->sockaddr, (u_char *) pc->sockaddr,
                         item->socklen, pc->socklen)
            == 0)
        {
            ngx_queue_remove(q);
            ngx_queue_insert_head(free, q);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "get keepalive peer: using connection %p", c);

            c->idle = 0;
            c->log = pc->log;
            c->read->log = pc->log;
            c->write->log = pc->log;
            c->pool->log = pc->log;

            pc->connection = c;
            pc->cached = 1;

            item->free = free;
            return NGX_DONE;
        }
    }

    return NGX_OK;
}


void
ngx_http_connection_pool_free(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state)
{
    ngx_http_connection_pool_t     *p = data;
    ngx_http_connection_pool_elt_t *item;

    ngx_uint_t         hash, bucket_id;
    ngx_queue_t       *q, *cache, *free;
    ngx_connection_t  *c;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0, "free keepalive peer");

    /* remember failed state - peer.free() may be called more than once */

    if (state & NGX_PEER_FAILED) {
        p->failed = 1;
    }

    /* cache valid connections */

    c = pc->connection;

    if (p->failed
        || c == NULL
        || c->read->eof
        || c->read->error
        || c->read->timedout
        || c->write->error
        || c->write->timedout)
    {
        return;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        return;
    }

#if (NGX_DEBUG)
    p->count++;
#endif

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "free keepalive peer: saving connection %p", c);

    hash = ngx_murmur_hash2((u_char *) pc->sockaddr, pc->socklen);
    bucket_id = hash % p->bucket_count;

    cache = &p->cache[bucket_id];
    free = &p->free[bucket_id];

    if (ngx_queue_empty(free)) {
        q = ngx_queue_last(cache);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_connection_pool_elt_t, queue);

        ngx_http_connection_pool_close(item->connection);

    } else {
        q = ngx_queue_head(free);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_connection_pool_elt_t, queue);
    }

    item->connection = c;
    item->free = free;
    ngx_queue_insert_head(cache, q);

    pc->connection = NULL;

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    c->write->handler = ngx_http_connection_pool_dummy_handler;
    c->read->handler = ngx_http_connection_pool_close_handler;

    c->data = item;
    c->idle = 1;
    c->log = ngx_cycle->log;
    c->read->log = ngx_cycle->log;
    c->write->log = ngx_cycle->log;
    c->pool->log = ngx_cycle->log;

    item->socklen = pc->socklen;
    ngx_memcpy(&item->sockaddr, pc->sockaddr, pc->socklen);

    if (c->read->ready) {
        ngx_http_connection_pool_close_handler(c->read);
    }
}


static void
ngx_http_connection_pool_close_handler(ngx_event_t *ev)
{
    ngx_http_connection_pool_elt_t  *item;

    int                n;
    char               buf[1];
    ngx_connection_t  *c;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0, "keepalive close handler");

    c = ev->data;

    if (c->close) {
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


    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "connection pool close connection");

    ngx_http_connection_pool_close(c);

    ngx_queue_remove(&item->queue);
    ngx_queue_insert_head(item->free, &item->queue);
}


static void
ngx_http_connection_pool_close(ngx_connection_t *c)
{
#if (NGX_HTTP_SSL)

    if (c->ssl) {
        c->ssl->no_wait_shutdown = 1;
        c->ssl->no_send_shutdown = 1;

        if (ngx_ssl_shutdown(c) == NGX_AGAIN) {
            c->ssl->handler = ngx_http_connection_pool_close;
            return;
        }
    }

#endif

    ngx_destroy_pool(c->pool);
    ngx_close_connection(c);
}


static void
ngx_http_connection_pool_dummy_handler(ngx_event_t *ev)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0, "keepalive dummy handler");
}

#if (NGX_DEBUG)
void
ngx_http_connection_pool_check(ngx_http_connection_pool_t *conn_pool,
    ngx_log_t *log)
{
    if (conn_pool->count != 0) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "<== conn pool check ==> "
                      "some keepalive peer do not free!,  conn_pool count: %i",
                      conn_pool->count);

    } else {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, log, 0,
                       "<== conn pool check ==> all keepalive peers are free");
    }
}
#endif
