
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_LOCAL_BLOCK_CACHE_H_INCLUDED_
#define _NGX_HTTP_TFS_LOCAL_BLOCK_CACHE_H_INCLUDED_

#include <ngx_http_tfs_block_cache.h>


typedef struct {
    u_char                                  color;
    u_char                                  dummy;
    ngx_queue_t                             queue;

    ngx_http_tfs_block_cache_key_t          key;

    u_char                                  len;
    u_short                                 count;
    u_char                                  data[1];
} ngx_http_tfs_block_cache_node_t;


ngx_int_t ngx_http_tfs_local_block_cache_init_zone(ngx_shm_zone_t *shm_zone,
    void *data);

ngx_int_t ngx_http_tfs_local_block_cache_lookup(
    ngx_http_tfs_local_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_http_tfs_block_cache_key_t *key,
    ngx_http_tfs_block_cache_value_t *value);

ngx_int_t ngx_http_tfs_local_block_cache_insert(
    ngx_http_tfs_local_block_cache_ctx_t *ctx,
    ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key,
    ngx_http_tfs_block_cache_value_t *value);

void ngx_http_tfs_local_block_cache_remove(
    ngx_http_tfs_local_block_cache_ctx_t *ctx,
    ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key);

void ngx_http_tfs_local_block_cache_discard(
    ngx_http_tfs_local_block_cache_ctx_t *ctx);

ngx_int_t ngx_http_tfs_local_block_cache_batch_lookup(
    ngx_http_tfs_local_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t *keys, ngx_array_t *kvs);



#endif /* _NGX_HTTP_TFS_LOCAL_BLOCK_CACHE_H_INCLUDED_ */
