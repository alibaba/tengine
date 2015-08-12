
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_rc_server_info.h>
#include <ngx_http_tfs.h>


static void ngx_http_tfs_rcs_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel);


ngx_http_tfs_rcs_info_t *
ngx_http_tfs_rcs_lookup(ngx_http_tfs_rc_ctx_t *ctx,
    ngx_str_t appkey)
{
    ngx_int_t                 rc;
    ngx_uint_t                hash;
    ngx_rbtree_node_t        *node, *sentinel;
    ngx_http_tfs_rcs_info_t  *tr;

    node = ctx->sh->rbtree.root;
    sentinel = ctx->sh->rbtree.sentinel;

    hash = ngx_murmur_hash2(appkey.data, appkey.len);

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

        tr = (ngx_http_tfs_rcs_info_t *) &node->color;
        rc = ngx_memn2cmp(appkey.data, tr->appkey.data, appkey.len,
                          tr->appkey.len);

        if (rc == 0) {
            ngx_queue_remove(&tr->queue);
            ngx_queue_insert_head(&ctx->sh->queue, &tr->queue);

            return tr;
        }

        node = (rc < 0) ? node->left : node->right;
     }

    return NULL;
}


void
ngx_http_tfs_rc_server_destroy_node(ngx_http_tfs_rc_ctx_t *rc_ctx,
    ngx_http_tfs_rcs_info_t *rc_info_node)
{
    ngx_str_t                            *block_cache_info;
    ngx_uint_t                            i, j;
    ngx_rbtree_node_t                    *node;
    ngx_http_tfs_group_info_t            *group_info;
    ngx_http_tfs_logical_cluster_t       *logical_cluster;
    ngx_http_tfs_physical_cluster_t      *physical_cluster;
    ngx_http_tfs_cluster_group_info_t    *cluster_group_info;
    ngx_http_tfs_tair_server_addr_info_t *dup_server_info;

    if (rc_info_node == NULL) {
        return;
    }

    if (rc_info_node->session_id.len <= 0
        || rc_info_node->session_id.data == NULL)
    {
        goto last_free;
    }

    ngx_slab_free_locked(rc_ctx->shpool, rc_info_node->session_id.data);
    ngx_str_null(&rc_info_node->session_id);

    if (rc_info_node->rc_servers_count <= 0
        || rc_info_node->rc_servers == NULL)
    {
        goto last_free;
    }

    ngx_slab_free_locked(rc_ctx->shpool, rc_info_node->rc_servers);
    block_cache_info = &rc_info_node->remote_block_cache_info;
    rc_info_node->rc_servers = NULL;

    logical_cluster = rc_info_node->logical_clusters;
    for (i = 0; i < rc_info_node->logical_cluster_count; i++) {
        if (logical_cluster->need_duplicate) {
            dup_server_info = &logical_cluster->dup_server_info;

            for (i = 0; i < NGX_HTTP_TFS_TAIR_SERVER_ADDR_PART_COUNT; i++) {
                if (dup_server_info->server[i].data == NULL) {
                    goto last_free;
                }
                ngx_slab_free_locked(rc_ctx->shpool,
                                     dup_server_info->server[i].data);
                ngx_str_null(&dup_server_info->server[i]);
            }
        }

        physical_cluster = logical_cluster->rw_clusters;
        for (j = 0; j < logical_cluster->rw_cluster_count; j++) {
            if (physical_cluster[j].cluster_id_text.len <= 0
                || physical_cluster[j].cluster_id_text.data == NULL)
            {
                goto last_free;
            }
            ngx_slab_free_locked(rc_ctx->shpool,
                                 physical_cluster[j].cluster_id_text.data);
            ngx_str_null(&physical_cluster[j].cluster_id_text);
            physical_cluster[j].cluster_id = 0;

            if (physical_cluster[j].ns_vip_text.len <= 0
                || physical_cluster[j].ns_vip_text.data == NULL)
            {
                goto last_free;
            }
            ngx_slab_free_locked(rc_ctx->shpool,
                                 physical_cluster[j].ns_vip_text.data);
            ngx_str_null(&physical_cluster[j].ns_vip_text);
            physical_cluster++;
        }
        logical_cluster++;
    }

    if (block_cache_info->len <= 0 || block_cache_info->data == NULL)
    {
        goto last_free;
    }

    ngx_slab_free_locked(rc_ctx->shpool, block_cache_info->data);
    ngx_str_null(&rc_info_node->remote_block_cache_info);

    cluster_group_info = rc_info_node->unlink_cluster_groups;
    for (i = 0; i < rc_info_node->unlink_cluster_group_count; i++) {
        for (j = 0; j < cluster_group_info[i].info_count; j++) {
            group_info = &cluster_group_info[i].group_info[j];
            if (group_info->ns_vip_text.len <= 0
                || group_info->ns_vip_text.data == NULL)
            {
                break;
            }
            ngx_slab_free_locked(rc_ctx->shpool, group_info->ns_vip_text.data);
            ngx_str_null(&group_info->ns_vip_text);
        }
    }

last_free:
    node = (ngx_rbtree_node_t *)
        ((u_char *) rc_info_node - offsetof(ngx_rbtree_node_t, color));
    ngx_slab_free_locked(rc_ctx->shpool, node);
}


void
ngx_http_tfs_rc_server_expire(ngx_http_tfs_rc_ctx_t *ctx)
{
    ngx_queue_t             *q, *kp_q;
    ngx_rbtree_node_t       *node;
    ngx_http_tfs_rcs_info_t *rc_info_node;

    if (ngx_queue_empty(&ctx->sh->queue)) {
        return;
    }

    q = ngx_queue_last(&ctx->sh->queue);

    rc_info_node = ngx_queue_data(q, ngx_http_tfs_rcs_info_t, queue);
    kp_q = &rc_info_node->kp_queue;

    ngx_queue_remove(q);
    ngx_queue_remove(kp_q);

    node = (ngx_rbtree_node_t *)
        ((u_char *) rc_info_node - offsetof(ngx_rbtree_node_t, color));

    ngx_rbtree_delete(&ctx->sh->rbtree, node);

    ngx_http_tfs_rc_server_destroy_node(ctx, rc_info_node);
}


ngx_int_t
ngx_http_tfs_rc_server_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_http_tfs_rc_ctx_t  *octx = data;

    size_t                 len;
    ngx_http_tfs_rc_ctx_t *ctx;

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

    ctx->sh = ngx_slab_alloc(ctx->shpool, sizeof(ngx_http_tfs_rc_shctx_t));
    if (ctx->sh == NULL) {
        return NGX_ERROR;
    }

    ctx->shpool->data = ctx->sh;

    ngx_rbtree_init(&ctx->sh->rbtree, &ctx->sh->sentinel,
                    ngx_http_tfs_rcs_rbtree_insert_value);
    ngx_queue_init(&ctx->sh->queue);
    ngx_queue_init(&ctx->sh->kp_queue);

    len = sizeof(" in tfs rc servers zone \"\"") + shm_zone->shm.name.len;

    ctx->shpool->log_ctx = ngx_slab_alloc(ctx->shpool, len);
    if (ctx->shpool->log_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_sprintf(ctx->shpool->log_ctx, " in tfs rc servers zone \"%V\"%Z",
                &shm_zone->shm.name);

    return NGX_OK;
}


static void
ngx_http_tfs_rcs_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel)
{
    ngx_int_t                 rc;
    ngx_rbtree_node_t       **p;
    ngx_http_tfs_rcs_info_t  *trn, *trnt;

    for ( ;; ) {

        if (node->key < temp->key) {

            p = &temp->left;

        } else if (node->key > temp->key) {

            p = &temp->right;

        } else { /* node->key == temp->key */

            trn = (ngx_http_tfs_rcs_info_t *) &node->color;
            trnt = (ngx_http_tfs_rcs_info_t *) &temp->color;

            rc = ngx_memn2cmp(trn->appkey.data, trnt->appkey.data,
                              trn->appkey.len, trn->appkey.len);
            if (rc < 0) {
                p = &temp->left;

            } else if (rc > 0) {
                p = &temp->right;

            } else {
                return;
            }
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


void
ngx_http_tfs_rcs_set_group_info_by_addr(ngx_http_tfs_rcs_info_t *rc_info,
    ngx_int_t group_count, ngx_int_t group_seq, ngx_http_tfs_inet_t addr)
{
    ngx_uint_t                          i, j;
    ngx_http_tfs_group_info_t          *group_info;
    ngx_http_tfs_cluster_group_info_t  *cluster_group_info;

    cluster_group_info = rc_info->unlink_cluster_groups;

    for (i = 0; i < rc_info->unlink_cluster_group_count; i++) {
        group_info = cluster_group_info[i].group_info;

        for (j = 0; j < cluster_group_info[i].info_count; j++) {

            if (ngx_memcmp(&group_info[j].ns_vip, &addr,
                           sizeof(ngx_http_tfs_inet_t)) == 0)
            {
                group_info[j].group_seq = group_seq;
                cluster_group_info[i].group_count = group_count;
                return;
            }
        }
    }
}


void
ngx_http_tfs_dump_rc_info(ngx_http_tfs_rcs_info_t *rc_info, ngx_log_t *log)
{
    uint32_t                            i, j, k;
    ngx_http_tfs_group_info_t          *group_info;
    ngx_http_tfs_logical_cluster_t     *logical_clusters;
    ngx_http_tfs_physical_cluster_t    *physical_clusters;
    ngx_http_tfs_cluster_group_info_t  *unlink_cluster_groups;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0, "=========dump rc info for appkey: %V =========",
                   &rc_info->appkey);
    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0, "appid: %uL, logical_cluster_count: %uD",
                   rc_info->app_id, rc_info->logical_cluster_count);
    logical_clusters = rc_info->logical_clusters;
    for (i = 0; i < rc_info->logical_cluster_count; i++) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0, "need_duplicate: %ud",
                       logical_clusters[i].need_duplicate);
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0, "rw_cluster_count: %uD",
                       logical_clusters[i].rw_cluster_count);
        physical_clusters = logical_clusters[i].rw_clusters;
        for (j = 0; j < logical_clusters[i].rw_cluster_count; j++) {
            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, log, 0,
                           "cluster_stat: %uD, access_type: %uD, cluster_id: %V, ns_vip: %V",
                           physical_clusters[j].cluster_stat,
                           physical_clusters[j].access_type,
                           &physical_clusters[j].cluster_id_text,
                           &physical_clusters[j].ns_vip_text);
        }
    }
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0, "unlink_cluster_group_count: %ud",
                   rc_info->unlink_cluster_group_count);
    unlink_cluster_groups = rc_info->unlink_cluster_groups;
    for (j = 0; j < rc_info->unlink_cluster_group_count; j++) {
        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, log, 0, "cluster_id: %ud, info_count: %uD, group_count: %D",
                       unlink_cluster_groups[j].cluster_id,
                       unlink_cluster_groups[j].info_count,
                       unlink_cluster_groups[j].group_count);
        group_info = unlink_cluster_groups[j].group_info;
        for (k = 0; k < unlink_cluster_groups[j].info_count; k++) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0, "group_seq: %D, ns_vip: %V",
                           group_info[k].group_seq,
                           &group_info[k].ns_vip_text);
        }
    }
}


ngx_int_t
ngx_http_tfs_rcs_stat_update(ngx_http_tfs_t *t,
    ngx_http_tfs_rcs_info_t *rc_info, ngx_http_tfs_oper_type_e oper_type)
{
    if (t == NULL || rc_info ==  NULL || oper_type >= NGX_HTTP_TFS_OPER_COUNT) {
        return NGX_ERROR;
    }

    int32_t index = oper_type;

    if (rc_info->stat_rcs[index].oper_app_id == 0 ) {
        rc_info->stat_rcs[index].oper_app_id = rc_info->app_id;
        rc_info->stat_rcs[index].oper_type = oper_type;
    }

    ++rc_info->stat_rcs[index].oper_times;
    rc_info->stat_rcs[index].oper_size += t->stat_info.size;
    ++rc_info->stat_rcs[index].oper_succ;
    rc_info->stat_rcs[index].oper_rt += ngx_http_tfs_get_request_time(t);

    return NGX_OK;
}
