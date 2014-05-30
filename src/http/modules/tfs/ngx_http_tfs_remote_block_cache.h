
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_REMOTE_BLOCK_CACHE_H_INCLUDED_
#define _NGX_HTTP_TFS_REMOTE_BLOCK_CACHE_H_INCLUDED_


#include <ngx_http_tfs_block_cache.h>


ngx_int_t ngx_http_tfs_remote_block_cache_lookup(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t* key);

ngx_int_t ngx_http_tfs_remote_block_cache_insert(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key,
    ngx_http_tfs_block_cache_value_t *value);

void ngx_http_tfs_remote_block_cache_remove(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key);

ngx_int_t ngx_http_tfs_remote_block_cache_batch_lookup(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t* keys);

ngx_int_t ngx_http_tfs_remote_block_cache_batch_insert(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t *kvs);

ngx_int_t ngx_http_tfs_get_remote_block_cache_instance(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_str_t *server_addr);


#endif /* _NGX_HTTP_TFS_REMOTE_BLOCK_CACHE_H_INCLUDED_ */
