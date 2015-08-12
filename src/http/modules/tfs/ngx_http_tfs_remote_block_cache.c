
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs.h>
#include <ngx_http_tfs_data_server_message.h>
#include <ngx_http_tfs_local_block_cache.h>
#include <ngx_http_tfs_remote_block_cache.h>


static void ngx_http_tfs_remote_block_cache_get_handler(
    ngx_http_tair_key_value_t *kv, ngx_int_t rc, void *data);
static void ngx_http_tfs_remote_block_cache_dummy_handler(ngx_int_t rc,
    void *data);

static void ngx_http_tfs_remote_block_cache_mget_handler(ngx_array_t *kvs,
    ngx_int_t rc, void *data);

ngx_int_t
ngx_http_tfs_remote_block_cache_lookup(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t* key)
{
    ngx_int_t             rc;
    ngx_http_tair_data_t  tair_key;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "lookup remote block cache, ns addr: %uL, block id: %uD",
                   key->ns_addr, key->block_id);

    tair_key.type = NGX_HTTP_TAIR_INT;
    tair_key.data = (u_char *)key;
    tair_key.len = NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE;

    rc = ngx_http_tfs_tair_get_helper(
                                    ctx->tair_instance,
                                    pool, log,
                                    &tair_key,
                                    ngx_http_tfs_remote_block_cache_get_handler,
                                    (void *)ctx);

    return rc;
}


static void
ngx_http_tfs_remote_block_cache_get_handler(ngx_http_tair_key_value_t *kv,
    ngx_int_t rc, void *data)
{
    u_char                                 *p, *q;
    uint32_t                                ds_count;
    ngx_http_tfs_t                         *t;
    ngx_http_tfs_inet_t                    *addr;
    ngx_http_tfs_segment_data_t            *segment_data;
    ngx_http_tfs_block_cache_key_t          key;
    ngx_http_tfs_block_cache_value_t        value;
    ngx_http_tfs_remote_block_cache_ctx_t  *ctx = data;

    t = ctx->data;
    segment_data = &t->file.segment_data[t->file.segment_index];
    if (rc == NGX_HTTP_ETAIR_SUCCESS) {
        q = kv->key.data;
        p = kv->value->data;
        if (p != NULL
            && (kv->value->len
                > NGX_HTTP_TFS_REMOTE_BLOCK_CACHE_VALUE_BASE_SIZE))
        {
            key.ns_addr = *(uint64_t *)q;
            q += sizeof(uint64_t);
            key.block_id = *(uint32_t *)q;

            ds_count = *(uint32_t *)p;
            p += sizeof(uint32_t);

            if (ds_count > 0) {
                segment_data->block_info.ds_count = ds_count;
                segment_data->block_info.ds_addrs = ngx_pcalloc(t->pool,
                                       sizeof(ngx_http_tfs_inet_t) * ds_count);
                if (segment_data->block_info.ds_addrs == NULL) {
                    ngx_http_tfs_finalize_request(t->data, t,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
                    return;
                }
                ngx_memcpy(segment_data->block_info.ds_addrs, p,
                           ds_count * sizeof(ngx_http_tfs_inet_t));

                /* insert local block cache */
                if (t->block_cache_ctx.use_cache
                    & NGX_HTTP_TFS_LOCAL_BLOCK_CACHE)
                {
                    value.ds_count = ds_count;
                    value.ds_addrs =
                        (uint64_t *)segment_data->block_info.ds_addrs;
                    ngx_http_tfs_local_block_cache_insert(
                                                   t->block_cache_ctx.local_ctx,
                                                   t->log, &key, &value);
                }

                /* skip GET_BLK_INFO state */
                t->state += 1;

                segment_data->cache_hit = NGX_HTTP_TFS_REMOTE_BLOCK_CACHE;

                /* select data server */
                addr = ngx_http_tfs_select_data_server(t, segment_data);

                ngx_http_tfs_peer_set_addr(t->pool,
                                           &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER],
                                           addr);

            } else {
                /* remote block cache invalid, need remove it */
                ngx_http_tfs_remote_block_cache_remove(ctx, t->pool, t->log,
                                                       &key);
            }
        }

    } else {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "lookup remote block cache, "
                       "ns addr: %V, block id: %uD not found",
                       &t->name_server_addr_text,
                       segment_data->segment_info.block_id);
    }

    ngx_http_tfs_finalize_state(t, NGX_OK);
}


ngx_int_t
ngx_http_tfs_remote_block_cache_insert(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_http_tfs_block_cache_key_t *key,
    ngx_http_tfs_block_cache_value_t *value)
{
    ngx_int_t             rc;
    ngx_pool_t           *tmp_pool;
    ngx_http_tair_data_t  tair_key, tair_value;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "insert remote block cache, "
                   "ns addr: %uL, block id: %uD",
                   key->ns_addr, key->block_id);

    tair_key.type = NGX_HTTP_TAIR_INT;
    tair_key.data = (u_char *)key;
    tair_key.len = NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE;

    tair_value.len = NGX_HTTP_TFS_REMOTE_BLOCK_CACHE_VALUE_BASE_SIZE
                      + value->ds_count * sizeof(uint64_t);
    tair_value.data = ngx_pcalloc(pool, tair_value.len);
    if (tair_value.data == NULL) {
        return NGX_ERROR;
    }
    *(uint32_t*)tair_value.data = value->ds_count;
    ngx_memcpy(tair_value.data+ NGX_HTTP_TFS_REMOTE_BLOCK_CACHE_VALUE_BASE_SIZE,
               value->ds_addrs, value->ds_count * sizeof(uint64_t));
    tair_value.type = NGX_HTTP_TAIR_INT;

    /* since we do not care returns,
     * we make a tmp pool and destroy it in callback
     */
    tmp_pool = ngx_create_pool(4096, log);
    if (tmp_pool == NULL) {
        return NGX_ERROR;
    }

    rc = ngx_http_tfs_tair_put_helper(
                                  ctx->tair_instance,
                                  tmp_pool, log,
                                  &tair_key, &tair_value,
                                  0/*expire*/, 0/* do not care version */,
                                  ngx_http_tfs_remote_block_cache_dummy_handler,
                                  (void *)tmp_pool);

    return rc;
}


static void
ngx_http_tfs_remote_block_cache_dummy_handler(ngx_int_t rc, void *data)
{
    ngx_destroy_pool((ngx_pool_t *)data);
}


void
ngx_http_tfs_remote_block_cache_remove(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t* key)
{
    ngx_int_t              rc;
    ngx_pool_t            *tmp_pool;
    ngx_array_t            tair_keys;
    ngx_http_tair_data_t  *tair_key;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "remove remote block cache, ns addr: %uL, block id: %uD",
                   key->ns_addr, key->block_id);

    rc = ngx_array_init(&tair_keys, pool, 1, sizeof(ngx_http_tair_data_t));
    if (rc == NGX_ERROR) {
        return;
    }
    tair_key = (ngx_http_tair_data_t*) ngx_array_push(&tair_keys);

    tair_key->type = NGX_HTTP_TAIR_INT;
    tair_key->data = (u_char *)key;
    tair_key->len = NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE;

    /* since we do not care returns,
     * we make a tmp pool and destroy it in callback
     */
    tmp_pool = ngx_create_pool(4096, log);
    if (tmp_pool == NULL) {
        return;
    }

    (void) ngx_http_tfs_tair_delete_helper(
                                  ctx->tair_instance,
                                  tmp_pool, log,
                                  &tair_keys,
                                  ngx_http_tfs_remote_block_cache_dummy_handler,
                                  (void *)tmp_pool);

}


ngx_int_t
ngx_http_tfs_remote_block_cache_batch_lookup(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t* keys)
{
    ngx_int_t                        rc;
    ngx_uint_t                       i;
    ngx_array_t                     *tair_kvs;
    ngx_http_tair_key_value_t       *tair_kv;
    ngx_http_tfs_block_cache_key_t  *key;

    tair_kvs = ngx_array_create(pool, keys->nelts,
                                sizeof(ngx_http_tair_key_value_t));
    if (tair_kvs == NULL) {
        return NGX_ERROR;
    }

    key = keys->elts;
    for (i = 0; i < keys->nelts; i++, key++) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                       "batch lookup remote block cache, "
                       "ns addr: %uL, block id: %uD",
                       key->ns_addr, key->block_id);

        tair_kv = (ngx_http_tair_key_value_t *)ngx_array_push(tair_kvs);
        if (tair_kv == NULL) {
            return NGX_ERROR;
        }

        tair_kv->key.type = NGX_HTTP_TAIR_INT;
        tair_kv->key.data = (u_char *)key;
        tair_kv->key.len = NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE;
    }

    rc = ngx_http_tfs_tair_mget_helper(
                                   ctx->tair_instance,
                                   pool, log,
                                   tair_kvs,
                                   ngx_http_tfs_remote_block_cache_mget_handler,
                                   (void *)ctx);
    return rc;
}


static void
ngx_http_tfs_remote_block_cache_mget_handler(ngx_array_t *kvs, ngx_int_t rc,
    void *data)
{
    u_char                                 *p, *q;
    uint32_t                                ds_count, block_count;
    ngx_uint_t                              i, j, hit_count;
    ngx_http_tfs_t                         *t;
    ngx_http_tair_key_value_t              *kv;
    ngx_http_tfs_segment_data_t            *segment_data;
    ngx_http_tfs_block_cache_key_t          key;
    ngx_http_tfs_block_cache_value_t        value;
    ngx_http_tfs_remote_block_cache_ctx_t  *ctx = data;

    t = ctx->data;

    segment_data = &t->file.segment_data[t->file.segment_index];
    block_count = t->file.segment_count - t->file.segment_index;
    if (block_count > NGX_HTTP_TFS_MAX_BATCH_COUNT) {
        block_count = NGX_HTTP_TFS_MAX_BATCH_COUNT;
    }

    if (rc == NGX_OK) {
        kv = kvs->elts;
        hit_count = 0;
        for (i = 0; i < kvs->nelts; i++, kv++) {
            if (kv->rc != NGX_HTTP_ETAIR_SUCCESS) {
                continue;
            }
            q = kv->key.data;
            p = kv->value->data;
            if (p != NULL
                && (kv->value->len
                    > NGX_HTTP_TFS_REMOTE_BLOCK_CACHE_VALUE_BASE_SIZE))
            {
                key.ns_addr = *(uint64_t *)q;
                q += sizeof(uint64_t);
                key.block_id = *(uint32_t *)q;

                ds_count = *(uint32_t *)p;
                p += sizeof(uint32_t);

                if (ds_count > 0) {
                    /* find out segment */
                    for (j = 0; j < block_count; j++) {
                        if(segment_data[j].segment_info.block_id == key.block_id
                           && segment_data[j].block_info.ds_addrs == NULL)
                        {
                            break;
                        }
                    }
                    /* not found, some error happen */
                    if (j == block_count) {
                        continue;
                    }

                    segment_data[j].block_info.ds_count = ds_count;
                    segment_data[j].block_info.ds_addrs = ngx_pcalloc(t->pool,
                                        ds_count * sizeof(ngx_http_tfs_inet_t));
                    if (segment_data[j].block_info.ds_addrs == NULL) {
                        ngx_http_tfs_finalize_request(t->data, t,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
                        return;
                    }
                    ngx_memcpy(segment_data[j].block_info.ds_addrs, p,
                               ds_count * sizeof(ngx_http_tfs_inet_t));

                    if (t->block_cache_ctx.use_cache
                        & NGX_HTTP_TFS_LOCAL_BLOCK_CACHE)
                    {
                        value.ds_count = ds_count;
                        value.ds_addrs =
                            (uint64_t *)segment_data[j].block_info.ds_addrs;
                        ngx_http_tfs_local_block_cache_insert(
                            t->block_cache_ctx.local_ctx, t->log, &key, &value);
                    }

                    hit_count++;
                    segment_data[j].cache_hit = NGX_HTTP_TFS_REMOTE_BLOCK_CACHE;

                    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                                   "remote block cache hit, "
                                   "ns addr: %V, block id: %uD",
                                   &t->name_server_addr_text,
                                   segment_data[j].segment_info.block_id);

                } else {
                    /* remote block cache invalid, need remove it */
                    ngx_http_tfs_remote_block_cache_remove(ctx, t->pool, t->log,
                                                           &key);
                }
            }
        }

        if (hit_count > 0) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, t->log, 0,
                           "batch lookup remote block cache, hit_count: %ui",
                           hit_count);

            /* remote block cache hit count */
            t->file.curr_batch_count += hit_count;

            if (hit_count == kvs->nelts) {
                /* all cache hit, start batch process */
                t->decline_handler = ngx_http_tfs_batch_process_start;
                rc = NGX_DECLINED;
            }
        }

    } else {
        rc = NGX_OK;
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "remote block cache miss");
    }

    ngx_http_tfs_finalize_state(t, rc);
}


#ifdef NGX_HTTP_TFS_USE_TAIR
ngx_int_t
ngx_http_tfs_get_remote_block_cache_instance(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_str_t *server_addr)
{
    size_t                                server_addr_len;
    uint32_t                              server_addr_hash;
    ngx_int_t                             rc, i;
    ngx_str_t                            *st, *group_name;
    ngx_array_t                           config_server;
    ngx_http_tfs_t                       *t;
    ngx_http_tfs_tair_instance_t         *instance;
    ngx_http_tfs_tair_server_addr_info_t  server_addr_info;

    if (server_addr->len == 0
        || server_addr->data == NULL)
    {
        return NGX_ERROR;
    }

    t = ctx->data;
    server_addr_len = server_addr->len;
    server_addr_hash = ngx_murmur_hash2(server_addr->data, server_addr_len);

    instance = ctx->tair_instance;
    if (instance->server != NULL) {
        if (instance->server_addr_hash == server_addr_hash) {
            return NGX_OK;
        }

        ngx_http_etair_destory_server(instance->server,
                                      (ngx_cycle_t *) ngx_cycle);
        instance->server = NULL;
    }

    rc = ngx_http_tfs_parse_tair_server_addr_info(&server_addr_info,
                                                  server_addr->data,
                                                  server_addr_len,
                                                  t->pool, 0);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    rc = ngx_array_init(&config_server, t->pool,
                        NGX_HTTP_TFS_TAIR_CONFIG_SERVER_COUNT,
                        sizeof(ngx_str_t));
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    for (i = 0; i < NGX_HTTP_TFS_TAIR_CONFIG_SERVER_COUNT; i++) {
        if (server_addr_info.server[i].len > 0 ) {
            st = (ngx_str_t *) ngx_array_push(&config_server);
            *st = server_addr_info.server[i];
        }
    }

    group_name = &server_addr_info.server[NGX_HTTP_TFS_TAIR_CONFIG_SERVER_COUNT];
    instance->server = ngx_http_etair_create_server(group_name,
                                                    &config_server,
                                                    t->main_conf->tair_timeout,
                                                    (ngx_cycle_t *) ngx_cycle);
    if (instance->server == NULL) {
        return NGX_ERROR;
    }
    instance->server_addr_hash = server_addr_hash;
    instance->area = server_addr_info.area;

    return NGX_OK;
}

#else

ngx_int_t
ngx_http_tfs_get_remote_block_cache_instance(
    ngx_http_tfs_remote_block_cache_ctx_t *ctx,
    ngx_str_t *server_addr)
{
    return NGX_ERROR;
}

#endif

