
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_CONNECTION_POOL_H_INCLUDED_
#define _NGX_HTTP_CONNECTION_POOL_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct ngx_http_connection_pool_s ngx_http_connection_pool_t;


typedef struct {
    ngx_queue_t              queue;
    ngx_connection_t        *connection;
    socklen_t                socklen;
    u_char                   sockaddr[NGX_SOCKADDRLEN];
    ngx_queue_t             *free;
} ngx_http_connection_pool_elt_t;


struct ngx_http_connection_pool_s {
    ngx_queue_t             *cache;
    ngx_queue_t             *free;
    ngx_uint_t               max_cached;
    ngx_uint_t               bucket_count;

    ngx_uint_t               failed;       /* unsigned:1 */
    ngx_pool_t              *pool;

#if (NGX_DEBUG)
    ngx_int_t                count;        /* check get&free op pairs */
#endif

    ngx_event_get_peer_pt    get_peer;
    ngx_event_free_peer_pt   free_peer;
};


ngx_http_connection_pool_t *ngx_http_connection_pool_init(ngx_pool_t *pool,
    ngx_uint_t max_count, ngx_uint_t bucket_count);

#if (NGX_DEBUG)
void ngx_http_connection_pool_check(ngx_http_connection_pool_t *coon_pool,
    ngx_log_t *log);
#endif


#endif  /* _NGX_HTTP_CONNECTION_POOL_H_INCLUDED_ */
