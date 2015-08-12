
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs.h>
#include <ngx_http_tfs_block_cache.h>
#include <ngx_http_tfs_local_block_cache.h>
#include <ngx_http_tfs_remote_block_cache.h>


ngx_int_t
ngx_http_tfs_block_cache_lookup(ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key,
    ngx_http_tfs_block_cache_value_t *value)
{
    ngx_int_t  rc = NGX_DECLINED;

    if (ctx->curr_lookup_cache == NGX_HTTP_TFS_LOCAL_BLOCK_CACHE) {

        ctx->curr_lookup_cache = NGX_HTTP_TFS_REMOTE_BLOCK_CACHE;

        if (ctx->use_cache & NGX_HTTP_TFS_LOCAL_BLOCK_CACHE) {
            rc = ngx_http_tfs_local_block_cache_lookup(ctx->local_ctx,
                                                       pool, log, key, value);

            if (rc == NGX_OK) {
                return rc;
            }
        }
    }

    if (ctx->curr_lookup_cache == NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {

        ctx->curr_lookup_cache = NGX_HTTP_TFS_NO_BLOCK_CACHE;

        if (ctx->use_cache & NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {
            rc = ngx_http_tfs_remote_block_cache_lookup(&ctx->remote_ctx,
                                                        pool, log, key);
        }
    }

    return rc;
}


void
ngx_http_tfs_block_cache_insert(ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key,
    ngx_http_tfs_block_cache_value_t *value)
{
    if (ctx->use_cache & NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {
        ngx_http_tfs_remote_block_cache_insert(&ctx->remote_ctx,
                                               pool, log, key, value);
    }

    if (ctx->use_cache & NGX_HTTP_TFS_LOCAL_BLOCK_CACHE) {
        ngx_http_tfs_local_block_cache_insert(ctx->local_ctx, log, key, value);
    }
}


void
ngx_http_tfs_block_cache_remove(ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t* key,
    uint8_t hit_status)
{
    if (hit_status != NGX_HTTP_TFS_NO_BLOCK_CACHE
        && (ctx->use_cache & NGX_HTTP_TFS_LOCAL_BLOCK_CACHE))
    {
        ngx_http_tfs_local_block_cache_remove(ctx->local_ctx, log, key);
    }

    if (hit_status == NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {
        ngx_http_tfs_remote_block_cache_remove(&ctx->remote_ctx,
                                               pool, log, key);
    }
}


ngx_int_t
ngx_http_tfs_block_cache_batch_lookup(ngx_http_tfs_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t *keys,
    ngx_array_t *kvs)
{
    uint32_t                        i;
    ngx_int_t                       rc;
    ngx_uint_t                      local_miss_count;
    ngx_array_t                     local_miss_keys;
    ngx_http_tfs_t                 *t;
    ngx_http_tfs_segment_data_t    *segment_data;
    ngx_http_tfs_block_cache_key_t *key;

    rc = NGX_DECLINED;

    if (ctx->curr_lookup_cache == NGX_HTTP_TFS_LOCAL_BLOCK_CACHE) {

        ctx->curr_lookup_cache = NGX_HTTP_TFS_REMOTE_BLOCK_CACHE;

        if (ctx->use_cache & NGX_HTTP_TFS_LOCAL_BLOCK_CACHE) {
            rc = ngx_http_tfs_local_block_cache_batch_lookup(ctx->local_ctx,
                                                             pool, log, keys,
                                                             kvs);

            if (rc == NGX_OK || rc == NGX_ERROR) {
                return rc;
            }
        }
    }

    /* rc == NGX_DECLIEND */
    if (ctx->curr_lookup_cache == NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {

        ctx->curr_lookup_cache = NGX_HTTP_TFS_NO_BLOCK_CACHE;

        if (ctx->use_cache & NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {
            t = ctx->remote_ctx.data;
            local_miss_count = keys->nelts - kvs->nelts;

            rc = ngx_array_init(&local_miss_keys, t->pool, local_miss_count,
                                sizeof(ngx_http_tfs_block_cache_key_t));
            if (rc == NGX_ERROR) {
                return rc;
            }

            segment_data = &t->file.segment_data[t->file.segment_index];
            for (i = 0; i < keys->nelts; i++, segment_data++) {
                if (segment_data->cache_hit == NGX_HTTP_TFS_NO_BLOCK_CACHE) {
                    key = (ngx_http_tfs_block_cache_key_t *)
                           ngx_array_push(&local_miss_keys);
                    key->ns_addr = *((uint64_t*)(&t->name_server_addr));
                    key->block_id = segment_data->segment_info.block_id;
                }
            }

            rc = ngx_http_tfs_remote_block_cache_batch_lookup(&ctx->remote_ctx,
                                                              pool, log,
                                                              &local_miss_keys);
        }
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_block_cache_cmp(ngx_http_tfs_block_cache_key_t *left,
    ngx_http_tfs_block_cache_key_t *right)
{
    if (left->ns_addr == right->ns_addr) {

        if (left->block_id == right->block_id) {
            return 0;
        }

        if (left->block_id < right->block_id) {
            return -1;
        }

        return 1;
    }

    if (left->ns_addr < right->ns_addr) {
        return -1;
    }

    return 1;
}
