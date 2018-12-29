
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_local_block_cache.h>


static void ngx_http_tfs_local_block_cache_rbtree_insert_value(
    ngx_rbtree_node_t *temp, ngx_rbtree_node_t *node,
    ngx_rbtree_node_t *sentinel);


ngx_int_t
ngx_http_tfs_local_block_cache_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    size_t                                 len;
    ngx_http_tfs_local_block_cache_ctx_t  *ctx;
    ngx_http_tfs_local_block_cache_ctx_t  *octx = data;

    ctx = shm_zone->data;

    if (octx) {
        ctx->sh = octx->sh;
        ctx->shpool = octx->shpool;

        return NGX_OK;
    }

    ctx->shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;

    if (shm_zone->shm.exists) {
        ctx->sh = ctx->shpool->data;

        return NGX_OK;
    }

    ctx->sh = ngx_slab_alloc(ctx->shpool,
                             sizeof(ngx_http_tfs_block_cache_shctx_t));
    if (ctx->sh == NULL) {
        return NGX_ERROR;
    }

    ctx->sh->discard_item_count = NGX_HTTP_TFS_BLOCK_CACHE_DISCARD_ITEM_COUNT;
    ctx->sh->hit_count = 0;
    ctx->sh->miss_count = 0;

    ctx->shpool->data = ctx->sh;

    ngx_rbtree_init(&ctx->sh->rbtree, &ctx->sh->sentinel,
                    ngx_http_tfs_local_block_cache_rbtree_insert_value);

    ngx_queue_init(&ctx->sh->queue);

    len = sizeof(" in tfs block cache zone \"\"") + shm_zone->shm.name.len;

    ctx->shpool->log_ctx = ngx_slab_alloc(ctx->shpool, len);
    if (ctx->shpool->log_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_sprintf(ctx->shpool->log_ctx, " in tfs block cache zone \"%V\"%Z",
                &shm_zone->shm.name);

    return NGX_OK;
}


void
ngx_http_tfs_local_block_cache_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel)
{
    ngx_rbtree_node_t                **p;
    ngx_http_tfs_block_cache_node_t  *tbn, *tbnt;

    for ( ;; ) {

        if (node->key < temp->key) {
            p = &temp->left;

        } else if (node->key > temp->key) {
            p = &temp->right;

        } else {
            /* node->key == temp->key */
            tbn = (ngx_http_tfs_block_cache_node_t *) &node->color;
            tbnt = (ngx_http_tfs_block_cache_node_t *) &temp->color;

            p = (ngx_http_tfs_block_cache_cmp(&tbn->key, &tbnt->key) < 0)
                 ? &temp->left : &temp->right;
        }

        if (*p == sentinel) {
            break;
        }

        temp = *p;
    }

    *p = node;
    node->parent = temp;
    node->left = sentinel;
    node->right = sentinel;
    ngx_rbt_red(node);
}


ngx_int_t
ngx_http_tfs_local_block_cache_lookup(ngx_http_tfs_local_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_http_tfs_block_cache_key_t* key,
    ngx_http_tfs_block_cache_value_t *value)
{
    double                            hit_ratio;
    ngx_int_t                         rc;
    ngx_uint_t                        hash;
    ngx_slab_pool_t                  *shpool;
    ngx_rbtree_node_t                *node, *sentinel;
    ngx_http_tfs_block_cache_node_t  *bcn;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "lookup local block cache, ns addr: %uL, block id: %uD",
                   key->ns_addr, key->block_id);

    shpool = ctx->shpool;
    ngx_shmtx_lock(&shpool->mutex);

    node = ctx->sh->rbtree.root;
    sentinel = ctx->sh->rbtree.sentinel;

    hash = ngx_murmur_hash2((u_char*)key, NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE);

    while (node != sentinel) {

        if (hash < node->key) {
            node = node->left;
            continue;
        }

        if (hash > node->key) {
            node = node->right;
            continue;
        }

        /* hash == node->key */
        bcn = (ngx_http_tfs_block_cache_node_t *) &node->color;
        rc = ngx_http_tfs_block_cache_cmp(key, &bcn->key);
        if (rc == 0) {
            value->ds_count = bcn->count;
            value->ds_addrs = ngx_pcalloc(pool,
                                          value->ds_count * sizeof(uint64_t));
            if (value->ds_addrs == NULL) {
                ngx_shmtx_unlock(&shpool->mutex);
                return NGX_ERROR;
            }
            ngx_memcpy(value->ds_addrs, bcn->data,
                       value->ds_count * sizeof(uint64_t));
            ngx_queue_remove(&bcn->queue);
            ngx_queue_insert_head(&ctx->sh->queue, &bcn->queue);
            ctx->sh->hit_count++;
            if (ctx->sh->hit_count >= NGX_HTTP_TFS_BLOCK_CACHE_STAT_COUNT) {
                hit_ratio = 100 * (double)((double)ctx->sh->hit_count
                                           / (double)(ctx->sh->hit_count
                                                      + ctx->sh->miss_count));
                ngx_log_error(NGX_LOG_INFO, log, 0,
                              "local block cache hit_ratio: %.2f%%",
                              hit_ratio);
                ctx->sh->hit_count = 0;
                ctx->sh->miss_count = 0;
            }
            ngx_shmtx_unlock(&shpool->mutex);
            return NGX_OK;
        }
        node = (rc < 0) ? node->left : node->right;
    }
    ctx->sh->miss_count++;
    ngx_shmtx_unlock(&shpool->mutex);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "lookup local block cache, "
                   "ns addr: %uL, block id: %uD not found",
                   key->ns_addr, key->block_id);

    return NGX_DECLINED;
}


ngx_int_t
ngx_http_tfs_local_block_cache_insert(ngx_http_tfs_local_block_cache_ctx_t *ctx,
    ngx_log_t *log, ngx_http_tfs_block_cache_key_t *key,
    ngx_http_tfs_block_cache_value_t *value)
{
    size_t                            n;
    ngx_slab_pool_t                  *shpool;
    ngx_rbtree_node_t                *node;
    ngx_http_tfs_block_cache_node_t  *bcn;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "insert local block cache, ns addr: %uL, block id: %uD",
                   key->ns_addr, key->block_id);

    shpool = ctx->shpool;

    ngx_shmtx_lock(&shpool->mutex);

    n = offsetof(ngx_rbtree_node_t, color)
        + offsetof(ngx_http_tfs_block_cache_node_t, data)
        + value->ds_count * sizeof(uint64_t);

    node = ngx_slab_alloc_locked(shpool, n);
    if (node == NULL) { // full, discard
        ngx_http_tfs_local_block_cache_discard(ctx);
        node = ngx_slab_alloc_locked(shpool, n);
        if (node == NULL) {
            ngx_shmtx_unlock(&shpool->mutex);
            return NGX_ERROR;
        }
    }

    bcn = (ngx_http_tfs_block_cache_node_t *) &node->color;

    node->key = ngx_murmur_hash2((u_char*)key,
                                 NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE);
    ngx_memcpy(&bcn->key, key, NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE);
    bcn->len = (u_char) value->ds_count * sizeof(uint64_t);
    bcn->count = value->ds_count;
    ngx_memcpy(bcn->data, value->ds_addrs, bcn->len);

    ngx_rbtree_insert(&(ctx->sh->rbtree), node);
    ngx_queue_insert_head(&ctx->sh->queue, &bcn->queue);

    ngx_shmtx_unlock(&shpool->mutex);

    return NGX_OK;
}


void
ngx_http_tfs_local_block_cache_remove(ngx_http_tfs_local_block_cache_ctx_t *ctx,
    ngx_log_t *log, ngx_http_tfs_block_cache_key_t* key)
{
    ngx_int_t                         rc;
    ngx_uint_t                        hash;
    ngx_slab_pool_t                  *shpool;
    ngx_rbtree_node_t                *node, *sentinel;
    ngx_http_tfs_block_cache_node_t  *bcn;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "remove local block cache, ns addr: %uL, block id: %uD",
                   key->ns_addr, key->block_id);

    shpool = ctx->shpool;
    ngx_shmtx_lock(&shpool->mutex);

    node = ctx->sh->rbtree.root;
    sentinel = ctx->sh->rbtree.sentinel;

    hash = ngx_murmur_hash2((u_char*)key, NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE);

    while (node != sentinel) {

        if (hash < node->key) {
            node = node->left;
            continue;
        }

        if (hash > node->key) {
            node = node->right;
            continue;
        }

        /* hash == node->key */
        do {
            bcn = (ngx_http_tfs_block_cache_node_t *) &node->color;
            rc = ngx_http_tfs_block_cache_cmp(key, &bcn->key);
            if (rc == 0) {
                ngx_rbtree_delete(&ctx->sh->rbtree, node);
                ngx_slab_free_locked(ctx->shpool, node);
                ngx_queue_remove(&bcn->queue);
                ngx_shmtx_unlock(&shpool->mutex);
                return;
            }
            node = (rc < 0) ? node->left : node->right;
        } while (node != sentinel && hash == node->key);
        break;
    }
    ngx_shmtx_unlock(&shpool->mutex);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "remove local block cache, "
                   "ns addr: %uL, block id: %uD not found",
                   key->ns_addr, key->block_id);

}


void
ngx_http_tfs_local_block_cache_discard(
    ngx_http_tfs_local_block_cache_ctx_t *ctx)
{
    ngx_uint_t                        i;
    ngx_queue_t                      *q, *h, *p;
    ngx_rbtree_node_t                *node;
    ngx_http_tfs_block_cache_node_t  *bcn;

    h = &ctx->sh->queue;
    if (ngx_queue_empty(h)) {
        return;
    }
    q = ngx_queue_last(h);

    for (i = 0; i < ctx->sh->discard_item_count; i++) {
        if (q == ngx_queue_sentinel(h)) {
            ngx_queue_init(h);
            return;
        }

        p = ngx_queue_prev(q);

        bcn = ngx_queue_data(q, ngx_http_tfs_block_cache_node_t, queue);

        node = (ngx_rbtree_node_t *)
            ((u_char *) bcn - offsetof(ngx_rbtree_node_t, color));

        ngx_rbtree_delete(&ctx->sh->rbtree, node);

        ngx_slab_free_locked(ctx->shpool, node);

        q = p;
    }

    q->next = h;
    h->prev = q;
}


ngx_int_t
ngx_http_tfs_local_block_cache_batch_lookup(
    ngx_http_tfs_local_block_cache_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t *keys, ngx_array_t *kvs)
{
    double                           hit_ratio;
    ngx_int_t                        rc;
    ngx_uint_t                       i, hash, hit_count;
    ngx_slab_pool_t                  *shpool;
    ngx_rbtree_node_t                *node, *sentinel;
    ngx_http_tfs_block_cache_kv_t    *kv;
    ngx_http_tfs_block_cache_key_t   *key;
    ngx_http_tfs_block_cache_node_t  *bcn;
    ngx_http_tfs_block_cache_value_t *value;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                   "batch lookup local block cache, block count: %ui",
                   keys->nelts);

    key = keys->elts;
    shpool = ctx->shpool;
    rc = NGX_ERROR;
    ngx_shmtx_lock(&shpool->mutex);

    sentinel = ctx->sh->rbtree.sentinel;
    hit_count = 0;

    for (i = 0; i < keys->nelts; i++, key++) {
        node = ctx->sh->rbtree.root;
        hash = ngx_murmur_hash2((u_char*)key,
                                NGX_HTTP_TFS_BLOCK_CACHE_KEY_SIZE);

        while (node != sentinel) {

            if (hash < node->key) {
                node = node->left;
                continue;
            }

            if (hash > node->key) {
                node = node->right;
                continue;
            }

            /* hash == node->key */
            bcn = (ngx_http_tfs_block_cache_node_t *) &node->color;
            rc = ngx_http_tfs_block_cache_cmp(key, &bcn->key);
            if (rc == 0) {
                value = ngx_pcalloc(pool,
                                    sizeof(ngx_http_tfs_block_cache_value_t));
                if (value == NULL) {
                    ngx_shmtx_unlock(&shpool->mutex);
                    return NGX_ERROR;
                }

                value->ds_count = bcn->count;
                value->ds_addrs = ngx_pcalloc(pool,
                                            value->ds_count * sizeof(uint64_t));
                if (value->ds_addrs == NULL) {
                    ngx_shmtx_unlock(&shpool->mutex);
                    return NGX_ERROR;
                }
                ngx_memcpy(value->ds_addrs, bcn->data,
                           value->ds_count * sizeof(uint64_t));

                kv = (ngx_http_tfs_block_cache_kv_t *)ngx_array_push(kvs);
                kv->key = key;
                kv->value = value;

                ngx_queue_remove(&bcn->queue);
                ngx_queue_insert_head(&ctx->sh->queue, &bcn->queue);
                hit_count++;
                break;
            }
            node = (rc < 0) ? node->left : node->right;
        }

        if (node == sentinel) {
            ctx->sh->miss_count++;
        }
    }

    ctx->sh->hit_count += hit_count;
    if (ctx->sh->hit_count >= NGX_HTTP_TFS_BLOCK_CACHE_STAT_COUNT) {
        hit_ratio = 100 * (double)((double)ctx->sh->hit_count
                                   / (double)(ctx->sh->hit_count
                                              + ctx->sh->miss_count));
        ngx_log_error(NGX_LOG_INFO, log, 0,
                      "local block cache hit_ratio: %.2f%%",
                      hit_ratio);
        ctx->sh->hit_count = 0;
        ctx->sh->miss_count = 0;
    }

    ngx_shmtx_unlock(&shpool->mutex);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                   "batch lookup local block cache, hit_count: %ui",
                   kvs->nelts);

    /* not all hit */
    if (hit_count < keys->nelts) {
        rc = NGX_DECLINED;
    }

    return rc;
}
