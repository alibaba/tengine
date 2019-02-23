
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_BLOCK_CACHE_H_INCLUDED_
#define _NGX_HTTP_TFS_BLOCK_CACHE_H_INCLUDED_


#include <ngx_tfs_common.h>
#include <ngx_http_tfs_tair_helper.h>


#define NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE sizeof(ngx_http_tfs_block_cache_key_t)

#define NGX_HTTP_TFS_REMOTE_BLOCK_CACHE_VALUE_BASE_SIZE sizeof(uint32_t)

#define NGX_HTTP_TFS_BLOCK_CACHE_DISCARD_ITEM_COUNT 10000

#define NGX_HTTP_TFS_BLOCK_CACHE_STAT_COUNT  (3000 * 60 * 60)

#define NGX_HTTP_TFS_NO_BLOCK_CACHE      0x0
#define NGX_HTTP_TFS_LOCAL_BLOCK_CACHE   0x1
#define NGX_HTTP_TFS_REMOTE_BLOCK_CACHE  0x2


typedef struct {
    uint64_t                             ns_addr;
    uint32_t                             block_id;
} __attribute__ ((__packed__)) ngx_http_tfs_block_cache_key_t;


typedef struct {
    uint32_t                             ds_count;
    uint64_t                            *ds_addrs;
} ngx_http_tfs_block_cache_value_t;


typedef struct {
    ngx_http_tfs_block_cache_key_t      *key;
    ngx_http_tfs_block_cache_value_t    *value;
} ngx_http_tfs_block_cache_kv_t;


typedef struct {
    ngx_rbtree_t                         rbtree;
    ngx_rbtree_node_t                    sentinel;
    ngx_queue_t                          queue;
    uint64_t                             discard_item_count;
    uint64_t                             hit_count;
    uint64_t                             miss_count;
} ngx_http_tfs_block_cache_shctx_t;


typedef struct {
    ngx_http_tfs_block_cache_shctx_t    *sh;
    ngx_slab_pool_t                     *shpool;
} ngx_http_tfs_local_block_cache_ctx_t;


typedef struct {
    void                                *data;
    ngx_http_tfs_tair_instance_t        *tair_instance;
} ngx_http_tfs_remote_block_cache_ctx_t;


typedef struct {
    ngx_http_tfs_local_block_cache_ctx_t *local_ctx;
    ngx_http_tfs_remote_block_cache_ctx_t remote_ctx;
    uint8_t                               use_cache;
    uint8_t                               curr_lookup_cache;
} ngx_http_tfs_block_cache_ctx_t;


ngx_int_t ngx_http_tfs_block_cache_lookup(ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t* key,
    ngx_http_tfs_block_cache_value_t *value);
void ngx_http_tfs_block_cache_insert(ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key,
    ngx_http_tfs_block_cache_value_t *value);
void ngx_http_tfs_block_cache_remove(ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key,
    uint8_t hit_status);
ngx_int_t ngx_http_tfs_block_cache_batch_lookup(
    ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t* keys, ngx_array_t *kvs);
void ngx_http_tfs_block_cache_batch_insert(ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t* kvs);
ngx_int_t ngx_http_tfs_block_cache_cmp(ngx_http_tfs_block_cache_key_t *left,
    ngx_http_tfs_block_cache_key_t *right);


#endif /* _NGX_HTTP_TFS_BLOCK_CACHE_H_INCLUDED_ */
