
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_serialization.h>
#include <ngx_http_tfs_rc_server_message.h>

#define ngx_http_tfs_expire_and_alloc(data, len) do {                   \
        ngx_http_tfs_rc_server_expire(rc_ctx);          \
        data = ngx_slab_alloc_locked(rc_ctx->shpool, len);    \
        if (data == NULL) {                             \
            return NGX_ERROR;                           \
        }                                               \
    } while(0)


static ngx_chain_t *ngx_http_tfs_create_login_message(ngx_http_tfs_t *t);
static ngx_chain_t * ngx_http_tfs_create_keepalive_message(ngx_http_tfs_t *t);

static ngx_int_t ngx_http_tfs_parse_login_message(ngx_http_tfs_t *t);
static ngx_int_t ngx_http_tfs_parse_keepalive_message(ngx_http_tfs_t *t);

static ngx_int_t
ngx_http_tfs_parse_rc_info(ngx_http_tfs_rcs_info_t *rc_info_node,
    ngx_http_tfs_rc_ctx_t *rc_ctx, u_char *data);

static ngx_int_t
ngx_http_tfs_create_info_node(ngx_http_tfs_t *t, ngx_http_tfs_rc_ctx_t *rc_ctx,
    u_char *data, ngx_str_t appkey);

static ngx_int_t
ngx_http_tfs_update_info_node(ngx_http_tfs_t *t, ngx_http_tfs_rc_ctx_t *rc_ctx,
    ngx_http_tfs_rcs_info_t *rc_info_node, u_char *base_info);

static ngx_int_t ngx_http_tfs_parse_session_id(ngx_str_t *session_id,
    uint64_t *app_id);
static void ngx_http_tfs_update_rc_servers(ngx_http_tfs_t *t,
    const ngx_http_tfs_rcs_info_t *rc_info_node);


ngx_chain_t *
ngx_http_tfs_rc_server_create_message(ngx_http_tfs_t *t)
{
    uint16_t  msg_type;

    msg_type = t->r_ctx.action.code;

    switch(msg_type) {
    case NGX_HTTP_TFS_ACTION_KEEPALIVE:
        return ngx_http_tfs_create_keepalive_message(t);
    default:
        return ngx_http_tfs_create_login_message(t);
    }
}


ngx_int_t
ngx_http_tfs_rc_server_parse_message(ngx_http_tfs_t *t)
{
    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_KEEPALIVE) {
        return ngx_http_tfs_parse_keepalive_message(t);
    }

    return ngx_http_tfs_parse_login_message(t);
}


ngx_chain_t *
ngx_http_tfs_create_login_message(ngx_http_tfs_t *t)
{
    ngx_buf_t                            *b;
    ngx_chain_t                          *cl;
    struct sockaddr_in                   *addr;
    ngx_http_tfs_rcs_login_msg_header_t  *req;

    b = ngx_create_temp_buf(t->pool,
                            sizeof(ngx_http_tfs_rcs_login_msg_header_t)
                             + sizeof(uint64_t) + t->r_ctx.appkey.len + 1);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_rcs_login_msg_header_t *) b->pos;
    req->header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.len = sizeof(uint64_t) + t->r_ctx.appkey.len
                       + sizeof(uint32_t) + 1;
    req->header.type = NGX_HTTP_TFS_REQ_RC_LOGIN_MESSAGE;
    req->header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.id = ngx_http_tfs_generate_packet_id();

    req->appkey_len = t->r_ctx.appkey.len + 1;

    b->last += sizeof(ngx_http_tfs_rcs_login_msg_header_t);

    /* app key */
    ngx_memcpy(b->last, t->r_ctx.appkey.data, t->r_ctx.appkey.len);
    b->last += t->r_ctx.appkey.len;
    *(b->last) = '\0';
    b->last += 1;

    /* app ip */
    addr = &(t->loc_conf->upstream->local_addr);
    ngx_memcpy(b->last, &(addr->sin_addr.s_addr), sizeof(uint64_t));
    b->last += sizeof(uint64_t);

    req->header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                       (const char *) (&req->header + 1),
                                       req->header.len);

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }

    cl->buf = b;
    cl->next = NULL;

    return cl;
}


ngx_chain_t *
ngx_http_tfs_create_keepalive_message(ngx_http_tfs_t *t)
{
    u_char                   *p, *tmp_ptr;
    ssize_t                  size, base_size;
    uint32_t                 rc_stat_size;
    ngx_int_t                rc, count;
    ngx_buf_t                *b;
    ngx_queue_t              *q, *queue;
    ngx_chain_t              *cl, **ll;
    ngx_http_tfs_rc_ctx_t    *rc_ctx;
    ngx_http_tfs_header_t    *header;
    ngx_http_tfs_rcs_info_t  *rc_info;

    count = 0;
    rc_ctx = t->loc_conf->upstream->rc_ctx;
    ll = NULL;
    cl = NULL;

    base_size = sizeof(ngx_http_tfs_header_t)
        /* session id and client version len */
        + sizeof(uint32_t) * 2
        /* client version */
        + sizeof(NGX_HTTP_TFS_CLIENT_VERSION)
        /* cache_size cache_time modify_time */
        + sizeof(uint64_t) * 3
        /* is_logout */
        + sizeof(uint8_t)
        /* stat info */
        + sizeof(uint32_t)
        + sizeof(uint64_t)
        /* last_report_time */
        + sizeof(uint64_t);

    queue = &rc_ctx->sh->kp_queue;
    if (ngx_queue_empty(queue)) {
        goto keepalive_create_error;
    }

    q = t->curr_ka_queue;
    if (q == NULL) {
        q = ngx_queue_head(queue);
        t->curr_ka_queue = q;
    }

    rc_info = ngx_queue_data(q, ngx_http_tfs_rcs_info_t, kp_queue);

    ngx_log_error(NGX_LOG_INFO, t->log, 0,
                  "will do keepalive for appkey: %V", &rc_info->appkey);

    /* rc_stat_size = oper_count * (key_size + value_size)
     * key_size = sizeof(oper_type)
     * vlaue_size = sizeof(ngx_http_tfs_stat_rcs_t) - sizeof(oper_app_id) */
    rc_stat_size = NGX_HTTP_TFS_OPER_COUNT * (sizeof(uint32_t) + sizeof(ngx_http_tfs_stat_rcs_t) - sizeof(uint32_t));

    size = base_size + rc_info->session_id.len + 1 + rc_stat_size;
    /*size = base_size + rc_info->session_id.len + 1;*/

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        goto keepalive_create_error;
    }

    header = (ngx_http_tfs_header_t *) b->pos;
    header->flag = NGX_HTTP_TFS_PACKET_FLAG;
    header->len = size - sizeof(ngx_http_tfs_header_t);
    header->type = NGX_HTTP_TFS_REQ_RC_KEEPALIVE_MESSAGE;
    header->version = NGX_HTTP_TFS_PACKET_VERSION;
    header->id = ngx_http_tfs_generate_packet_id();

    p = (u_char *)(header + 1);

    /* include '\0' */
    *((uint32_t *) p) = rc_info->session_id.len + 1;
    p += sizeof(uint32_t);

    p = ngx_cpymem(p, rc_info->session_id.data, rc_info->session_id.len);
    *p = '\0';
    p += sizeof(uint8_t);

    *((uint32_t *) p) = sizeof(NGX_HTTP_TFS_CLIENT_VERSION);
    p += sizeof(uint32_t);

    p = ngx_cpymem(p, NGX_HTTP_TFS_CLIENT_VERSION,
                   sizeof(NGX_HTTP_TFS_CLIENT_VERSION));

    ngx_memzero(p, sizeof(uint64_t) * 3 + sizeof(uint32_t) + sizeof(uint8_t));

    /* cache_size cache_time */
    p += sizeof(uint64_t) * 2;

    *((uint64_t *) p) = rc_info->modify_time;
    /* modify_time and is_logout */
    p += sizeof(uint64_t) + sizeof(uint8_t);

    /* stat size */
    tmp_ptr = p;
    /**((uint32_t *)p) = NGX_HTTP_TFS_OPER_COUNT;*/
    p += sizeof(uint32_t);

    /* set rcs stat */
    rc = ngx_http_tfs_serialize_rcs_stat(&p, rc_info, &count);
    if (rc != NGX_OK) {
        goto keepalive_create_error;
    }
    *((uint32_t *)tmp_ptr) = count;

    /* cache hit_ratio and last_report_time */
    /*p += sizeof(uint64_t) * 2;*/
    p += sizeof(uint64_t);
    (*(uint64_t *)p) = time(NULL);
    p += sizeof(uint64_t);

    /* modify_time is_logout stat_info */
    /*p += sizeof(uint64_t) * 3 + sizeof(uint32_t) + sizeof(uint8_t);*/

    header->crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
        (const char *) (header + 1), header->len);

    b->last += size;

    if (ll == NULL) {
        cl = ngx_alloc_chain_link(t->pool);
        if (cl == NULL) {
            goto keepalive_create_error;
        }

        cl->next = NULL;
        cl->buf = b;

    } else {
        *ll = ngx_alloc_chain_link(t->pool);
        if (*ll == NULL) {
            goto keepalive_create_error;
        }

        (*ll)->next = NULL;
        (*ll)->buf = b;
    }

    return cl;

keepalive_create_error:
    return NULL;
}


ngx_int_t
ngx_http_tfs_parse_login_message(ngx_http_tfs_t *t)
{
    uint16_t                         type;
    ngx_str_t                        err_msg;
    ngx_int_t                        rc;
    ngx_http_tfs_header_t           *header;
    ngx_http_tfs_rc_ctx_t           *rc_ctx;
    ngx_http_tfs_rcs_info_t         *rc_info;
    ngx_http_tfs_peer_connection_t  *tp;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    type = header->type;
    rc_ctx = t->loc_conf->upstream->rc_ctx;

    switch (type) {
    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&err_msg, "login rc");
        return ngx_http_tfs_status_message(&tp->body_buffer, &err_msg, t->log);
    }

    ngx_shmtx_lock(&rc_ctx->shpool->mutex);
    rc_info = ngx_http_tfs_rcs_lookup(rc_ctx, t->r_ctx.appkey);

    rc = NGX_OK;

    if (rc_info == NULL) {
        rc = ngx_http_tfs_create_info_node(t, rc_ctx, tp->body_buffer.pos,
                                           t->r_ctx.appkey);

    } else {
        t->rc_info_node = rc_info;
    }
    ngx_shmtx_unlock(&rc_ctx->shpool->mutex);

#if (NGX_DEBUG)
    ngx_http_tfs_dump_rc_info(t->rc_info_node, t->log);
#endif

    if (rc == NGX_OK) {
        rc = ngx_http_tfs_parse_session_id(&t->rc_info_node->session_id,
                                           &t->rc_info_node->app_id);
        if (rc == NGX_ERROR) {
            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                          "invalid session id: %V",
                          &t->rc_info_node->session_id);
        }
    }
    return rc;
}


ngx_int_t
ngx_http_tfs_parse_keepalive_message(ngx_http_tfs_t *t)
{
    u_char                          *p, update;
    uint16_t                         type;
    ngx_str_t                        err_msg;
    ngx_int_t                        i, rc;
    ngx_queue_t                     *q, *queue;
    ngx_rbtree_node_t               *node;
    ngx_http_tfs_header_t           *header;
    ngx_http_tfs_rc_ctx_t           *rc_ctx;
    ngx_http_tfs_stat_rcs_t         *stat_rcs;
    ngx_http_tfs_rcs_info_t         *rc_info;
    ngx_http_tfs_peer_connection_t  *tp;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    type = header->type;

    switch (type) {
    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&err_msg, "keepalive rc");
        return ngx_http_tfs_status_message(&tp->body_buffer, &err_msg, t->log);
    }

    p = tp->body_buffer.pos;
    update = *p;
    p++;

    if (!update) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, t->log, 0,
                      "rc keepalive, update flag: %d", update);
    } else {
        ngx_log_error(NGX_LOG_WARN, t->log, 0,
                      "rc keepalive, update flag: %d", update);
    }

    rc_ctx = t->loc_conf->upstream->rc_ctx;

    queue = &rc_ctx->sh->kp_queue;
    if (ngx_queue_empty(queue)) {
        return NGX_ERROR;
    }

    q = t->curr_ka_queue;
    if (q == NULL) {
        return NGX_ERROR;
    }
    t->curr_ka_queue = ngx_queue_next(q);

    ngx_shmtx_lock(&rc_ctx->shpool->mutex);
    rc_info = ngx_queue_data(q, ngx_http_tfs_rcs_info_t, kp_queue);

    stat_rcs = rc_info->stat_rcs;
    for (i = 0;i < NGX_HTTP_TFS_OPER_COUNT; i++) {
        ngx_memzero(&stat_rcs[i], sizeof(ngx_http_tfs_stat_rcs_t));
    }

    if (update == NGX_HTTP_TFS_NO) {
        ngx_shmtx_unlock(&rc_ctx->shpool->mutex);
        return NGX_OK;
    }

    /* FIXME: do not consider rc_info_node being expired, it hardly occurs
     * e.g. a single rc_info_node occupys nearly 2KB space,
     * 10MB for tfs_rcs_zone can hold at least 5000 rc_infos.
     */

    /* update info node */
    /* FIXME: sth terrible may happen here
     * if someone has get the rc_info before lock */
    rc = ngx_http_tfs_update_info_node(t, rc_ctx, rc_info, p);
    /* rc_info has been destroyed, remove from queue and rbtree */
    if (rc == NGX_ERROR) {
        ngx_queue_remove(&rc_info->queue);
        ngx_queue_remove(&rc_info->kp_queue);

        node = (ngx_rbtree_node_t *)
            ((u_char *) rc_info - offsetof(ngx_rbtree_node_t, color));
        ngx_rbtree_delete(&rc_ctx->sh->rbtree, node);

        ngx_http_tfs_rc_server_destroy_node(rc_ctx, rc_info);
    }
    ngx_shmtx_unlock(&rc_ctx->shpool->mutex);

#if (NGX_DEBUG)
    ngx_http_tfs_dump_rc_info(rc_info, t->log);
#endif

    return rc;
}


static ngx_int_t
ngx_http_tfs_parse_rc_info(ngx_http_tfs_rcs_info_t *rc_info_node,
    ngx_http_tfs_rc_ctx_t *rc_ctx,  u_char *data)
{
    u_char                                *p;
    uint32_t                               cluster_id, cluster_id_len;
    uint32_t                               len, unlink_cluster_count;
    ngx_int_t                              dup_info_size, rc;
    ngx_uint_t                             i, j;
    ngx_http_tfs_group_info_t             *group_info;
    ngx_http_tfs_logical_cluster_t        *logical_cluster;
    ngx_http_tfs_physical_cluster_t       *physical_cluster;
    ngx_http_tfs_cluster_group_info_t     *cluster_group_info;
    ngx_http_tfs_tair_server_addr_info_t  *dup_server_info;

    p = data;

    /* rc servers count */
    rc_info_node->rc_servers_count = *((uint32_t *) p);
    p += sizeof(uint32_t);

    if (rc_info_node->rc_servers_count > 0) {
        rc_info_node->rc_servers =
            ngx_slab_alloc_locked(rc_ctx->shpool,
                                  rc_info_node->rc_servers_count
                                   * sizeof(uint64_t));
        if (rc_info_node->rc_servers == NULL) {
            ngx_http_tfs_expire_and_alloc(rc_info_node->rc_servers,
                                          rc_info_node->rc_servers_count
                                           * sizeof(uint64_t));
        }

        ngx_memcpy(rc_info_node->rc_servers, p,
                   rc_info_node->rc_servers_count * sizeof(uint64_t));
        p += sizeof(uint64_t) * rc_info_node->rc_servers_count;
    }

    /* logical cluster count */
    rc_info_node->logical_cluster_count = *((uint32_t *) p);
    p += sizeof(uint32_t);

    logical_cluster = rc_info_node->logical_clusters;
    for (i = 0; i < rc_info_node->logical_cluster_count; i++) {
        logical_cluster->need_duplicate = *p;
        p += sizeof(uint8_t);

        if (logical_cluster->need_duplicate) {
            len = *((uint32_t *) p);
            p += sizeof(uint32_t);

            if (len > 0) {
                dup_info_size = len - 1;
                dup_server_info = &logical_cluster->dup_server_info;

                rc = ngx_http_tfs_parse_tair_server_addr_info(dup_server_info,
                                                              p,
                                                              dup_info_size,
                                                              rc_ctx->shpool,
                                                              1);
                if (rc == NGX_ERROR) {
                    return NGX_ERROR;
                }

                logical_cluster->dup_server_addr_hash =
                    ngx_murmur_hash2(p, dup_info_size);
                p += dup_info_size + 1;

                rc_info_node->need_duplicate = 1;
            }
        }

        logical_cluster->rw_cluster_count = *((uint32_t *) p);
        p += sizeof(uint32_t);

        physical_cluster = logical_cluster->rw_clusters;
        for (j = 0; j < logical_cluster->rw_cluster_count; j++) {
            /* cluster stat */
            physical_cluster->cluster_stat = *((uint32_t *) p);
            p += sizeof(uint32_t);

            /* access type */
            physical_cluster->access_type = *((uint32_t *) p);
            p += sizeof(uint32_t);

            /* cluster id */
            len = *((uint32_t *) p);
            if (len <= 0) {
                physical_cluster->cluster_id_text.len = 0;
                return NGX_ERROR;
            }

            physical_cluster->cluster_id_text.len = len - 1;
            p += sizeof(uint32_t);

            physical_cluster->cluster_id_text.data =
                ngx_slab_alloc_locked(rc_ctx->shpool,
                                      physical_cluster->cluster_id_text.len);
            if (physical_cluster->cluster_id_text.data == NULL) {
                ngx_http_tfs_expire_and_alloc(
                                         physical_cluster->cluster_id_text.data,
                                         physical_cluster->cluster_id_text.len);
            }
            ngx_memcpy(physical_cluster->cluster_id_text.data, p,
                       physical_cluster->cluster_id_text.len);
            /* this cluster id need get from ns */
            physical_cluster->cluster_id = 0;
            p += physical_cluster->cluster_id_text.len + 1;

            /* name server vip */
            len = *((uint32_t *) p);
            if (len <= 0) {
                physical_cluster->ns_vip_text.len = 0;
                return NGX_ERROR;
            }

            physical_cluster->ns_vip_text.len = len - 1;
            p += sizeof(uint32_t);

            physical_cluster->ns_vip_text.data =
                ngx_slab_alloc_locked(rc_ctx->shpool,
                                      physical_cluster->ns_vip_text.len);
            if (physical_cluster->ns_vip_text.data == NULL) {
                ngx_http_tfs_expire_and_alloc(physical_cluster->ns_vip_text.data,
                                             physical_cluster->ns_vip_text.len);
            }
            ngx_memcpy(physical_cluster->ns_vip_text.data, p,
                       physical_cluster->ns_vip_text.len);

            p += physical_cluster->ns_vip_text.len + 1;

            ngx_http_tfs_parse_inet(&physical_cluster->ns_vip_text,
                                    &physical_cluster->ns_vip);

            physical_cluster++;
        }

        logical_cluster++;
    }

    /* report interval */
    rc_info_node->report_interval = *((uint32_t *) p);
    p += sizeof(uint32_t);

    /* modify time */
    rc_info_node->modify_time = *((uint64_t *) p);
    p += sizeof(uint64_t);

    /* root server */
    rc_info_node->meta_root_server = *((uint64_t *) p);
    p += sizeof(uint64_t);

    /* remote block cache */
    len = *((uint32_t *) p);
    p += sizeof(uint32_t);
    rc_info_node->remote_block_cache_info.len = 0;

    if (len > 0) {
        rc_info_node->remote_block_cache_info.len = len - 1;

        rc_info_node->remote_block_cache_info.data =
            ngx_slab_alloc_locked(rc_ctx->shpool,
                                  rc_info_node->remote_block_cache_info.len);
        if (rc_info_node->remote_block_cache_info.data == NULL) {
            ngx_http_tfs_expire_and_alloc(
                                     rc_info_node->remote_block_cache_info.data,
                                     rc_info_node->remote_block_cache_info.len);
        }

        ngx_memcpy(rc_info_node->remote_block_cache_info.data, p,
                   len - 1);
        p += len;
    }

    /* unlink & update cluster */
    /* this count is physical cluster count */
    unlink_cluster_count = *((uint32_t *) p);
    p += sizeof(uint32_t);

    rc_info_node->unlink_cluster_group_count = 0;

    for (i = 0; i < unlink_cluster_count; i++) {
        /* skip cluster_stat */
        p += sizeof(uint32_t);
        /* skip access type */
        p += sizeof(uint32_t);

        cluster_id_len = *((uint32_t *) p);
        p += sizeof(uint32_t);

        cluster_id = ngx_http_tfs_get_cluster_id(p);
        p += cluster_id_len;

        for (j = 0; j < rc_info_node->unlink_cluster_group_count; j++) {
            /* find exist cluster_group_info */
            if (rc_info_node->unlink_cluster_groups[j].cluster_id == cluster_id) {
                cluster_group_info = &rc_info_node->unlink_cluster_groups[j];
                break;
            }
        }

        /* new cluster_group_info */
        if (j >= rc_info_node->unlink_cluster_group_count) {
            cluster_group_info = &rc_info_node->unlink_cluster_groups[rc_info_node->unlink_cluster_group_count++];
            cluster_group_info->info_count = 0;
            cluster_group_info->group_count = 0;
            cluster_group_info->cluster_id = cluster_id;
        }

        group_info = &cluster_group_info->group_info[cluster_group_info->info_count++];

        /* name server vip */
        len = *((uint32_t *) p);
        if (len <= 0) {
            group_info->ns_vip_text.len = 0;
            return NGX_ERROR;
        }

        group_info->ns_vip_text.len = len - 1;
        p += sizeof(uint32_t);

        group_info->ns_vip_text.data =
            ngx_slab_alloc_locked(rc_ctx->shpool, group_info->ns_vip_text.len);
        if (group_info->ns_vip_text.data == NULL) {
            ngx_http_tfs_expire_and_alloc(group_info->ns_vip_text.data,
                                          group_info->ns_vip_text.len);
        }

        memcpy(group_info->ns_vip_text.data, p, group_info->ns_vip_text.len);

        group_info->group_seq = -1;
        p += len;

        ngx_http_tfs_parse_inet(&group_info->ns_vip_text, &group_info->ns_vip);
    }

    /* use remote cache flag */
    rc_info_node->use_remote_block_cache = *((uint32_t *) p);
    return NGX_OK;
}


static void
ngx_http_tfs_update_rc_servers(ngx_http_tfs_t *t, const ngx_http_tfs_rcs_info_t *rc_info_node)
{
    ngx_http_tfs_upstream_t       *upstream;

    upstream = t->loc_conf->upstream;
    if (rc_info_node->rc_servers_count > NGX_HTTP_TFS_MAX_RCSERVER_COUNT) {
        upstream->rc_servers_count = NGX_HTTP_TFS_MAX_RCSERVER_COUNT;

    } else {
        upstream->rc_servers_count = rc_info_node->rc_servers_count;
    }

    ngx_memcpy(upstream->rc_servers, rc_info_node->rc_servers, upstream->rc_servers_count * sizeof(uint64_t));
    upstream->rcserver_index = 0;
}


static ngx_int_t
ngx_http_tfs_update_info_node(ngx_http_tfs_t *t, ngx_http_tfs_rc_ctx_t *rc_ctx,
    ngx_http_tfs_rcs_info_t *rc_info_node, u_char *base_info)
{
    u_char                                *p;
    ngx_int_t                              rc;
    ngx_uint_t                             i, j;
    ngx_http_tfs_group_info_t             *group_info;
    ngx_http_tfs_logical_cluster_t        *logical_cluster;
    ngx_http_tfs_physical_cluster_t       *physical_cluster;
    ngx_http_tfs_cluster_group_info_t     *cluster_group_info;
    ngx_http_tfs_tair_server_addr_info_t  *dup_server_info;

    p = base_info;

    /* free old rc servers */
    if (rc_info_node->rc_servers != NULL) {
        ngx_slab_free_locked(rc_ctx->shpool, rc_info_node->rc_servers);
    }
    rc_info_node->rc_servers_count = 0;

    /* free old cluster data */
    logical_cluster = rc_info_node->logical_clusters;
    for (i = 0; i < rc_info_node->logical_cluster_count; i++) {
        /* free old duplicate server info */
        if (logical_cluster->need_duplicate) {
            dup_server_info = &logical_cluster->dup_server_info;

            for (j = 0; j < NGX_HTTP_TFS_TAIR_SERVER_ADDR_PART_COUNT; j++) {
                if (dup_server_info->server[j].data == NULL) {
                    break;
                }
                ngx_slab_free_locked(rc_ctx->shpool,
                                     dup_server_info->server[j].data);
                ngx_str_null(&dup_server_info->server[j]);
            }
            logical_cluster->dup_server_addr_hash = -1;
            logical_cluster->need_duplicate = 0;
        }

        physical_cluster = logical_cluster->rw_clusters;
        for (j = 0; j < logical_cluster->rw_cluster_count; i++) {
            if (physical_cluster->cluster_id_text.len <= 0
                || physical_cluster->cluster_id_text.data == NULL)
            {
                break;
            }
            ngx_slab_free_locked(rc_ctx->shpool,
                                 physical_cluster->cluster_id_text.data);
            ngx_str_null(&physical_cluster->cluster_id_text);
            physical_cluster->cluster_id = 0;

            if (physical_cluster->ns_vip_text.len <= 0
                || physical_cluster->ns_vip_text.data == NULL)
            {
                break;
            }
            ngx_slab_free_locked(rc_ctx->shpool,
                                 physical_cluster->ns_vip_text.data);
            ngx_str_null(&physical_cluster->ns_vip_text);

            physical_cluster++;
        }
        logical_cluster->rw_cluster_count = 0;

        logical_cluster++;
    }
    rc_info_node->logical_cluster_count = 0;

    /* reset need duplicate flag */
    rc_info_node->need_duplicate = 0;

    /* free old remote block cache info */
    if (rc_info_node->remote_block_cache_info.len > 0
        && rc_info_node->remote_block_cache_info.data != NULL)
    {
        ngx_slab_free_locked(rc_ctx->shpool,
                             rc_info_node->remote_block_cache_info.data);
        ngx_str_null(&rc_info_node->remote_block_cache_info);
    }
    rc_info_node->remote_block_cache_info.len = 0;

    /* free old unlink cluster */
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
    rc_info_node->unlink_cluster_group_count = 0;

    /* parse rc info */
    rc = ngx_http_tfs_parse_rc_info(rc_info_node, rc_ctx, p);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    t->rc_info_node = rc_info_node;
    ngx_http_tfs_update_rc_servers(t, rc_info_node);

    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_create_info_node(ngx_http_tfs_t *t,
    ngx_http_tfs_rc_ctx_t *rc_ctx,
    u_char *data, ngx_str_t appkey)
{
    u_char                   *p;
    size_t                    n;
    uint32_t                  len;
    ngx_int_t                 rc;
    ngx_rbtree_node_t        *node;
    ngx_http_tfs_rcs_info_t  *rc_info_node;

    rc_info_node = NULL;

    n = offsetof(ngx_rbtree_node_t, color)
        + sizeof(ngx_http_tfs_rcs_info_t);

    node = ngx_slab_alloc_locked(rc_ctx->shpool, n);
    if (node == NULL) {
        ngx_http_tfs_expire_and_alloc(node, n);
    }

    rc_info_node = (ngx_http_tfs_rcs_info_t *) &node->color;

    node->key = ngx_murmur_hash2(appkey.data, appkey.len);

    rc_info_node->appkey.data = ngx_slab_alloc_locked(rc_ctx->shpool,
                                                      appkey.len);
    if (rc_info_node->appkey.data == NULL) {
        ngx_http_tfs_rc_server_expire(rc_ctx);
        rc_info_node->appkey.data = ngx_slab_alloc_locked(rc_ctx->shpool,
                                                          appkey.len);
        if (rc_info_node->appkey.data == NULL) {
            goto login_error;
        }
    }

    ngx_memcpy(rc_info_node->appkey.data, appkey.data, appkey.len);
    rc_info_node->appkey.len = appkey.len;

    /* parse session id */
    len = *((uint32_t *) data);
    p = data + sizeof(uint32_t);
    if (len <= 0) {
        rc_info_node->session_id.len = 0;
        goto login_error;
    }

    rc_info_node->session_id.len = len - 1;
    rc_info_node->session_id.data = ngx_slab_alloc_locked(rc_ctx->shpool, len);
    if (rc_info_node->session_id.data == NULL) {
        ngx_http_tfs_rc_server_expire(rc_ctx);
        rc_info_node->session_id.data =
            ngx_slab_alloc_locked(rc_ctx->shpool, rc_info_node->session_id.len);
        if (rc_info_node->session_id.data == NULL) {
            goto login_error;
        }
    }

    ngx_memcpy(rc_info_node->session_id.data, p, rc_info_node->session_id.len);

    p += rc_info_node->session_id.len + 1;

    /* parse rc info */
    rc = ngx_http_tfs_parse_rc_info(rc_info_node, rc_ctx, p);
    if (rc == NGX_ERROR) {
        goto login_error;
    }

    ngx_http_tfs_update_rc_servers(t, rc_info_node);

    t->rc_info_node = rc_info_node;
    ngx_rbtree_insert(&rc_ctx->sh->rbtree, node);
    ngx_queue_insert_head(&rc_ctx->sh->queue, &rc_info_node->queue);
    ngx_queue_insert_tail(&rc_ctx->sh->kp_queue, &rc_info_node->kp_queue);

    return NGX_OK;

login_error:

    ngx_http_tfs_rc_server_destroy_node(rc_ctx, rc_info_node);
    t->rc_info_node = NULL;
    return NGX_ERROR;
}


static ngx_int_t
ngx_http_tfs_parse_session_id(ngx_str_t *session_id, uint64_t *app_id)
{
  char        *first_pos;
  const char  separator_key = '-';

  first_pos = ngx_strchr(session_id->data, separator_key);
  if (first_pos == NULL) {
      return NGX_ERROR;
  }

  return ngx_http_tfs_atoull(session_id->data,
                             ((u_char *)first_pos - session_id->data),
                             (unsigned long long *) app_id);
}


void
ngx_http_tfs_select_rc_server(ngx_http_tfs_t *t)
{
    struct sockaddr_in       *addr_in;
    ngx_http_tfs_inet_t      *addr;
    ngx_http_tfs_upstream_t  *upstream;

    upstream = t->loc_conf->upstream;

    if (upstream->rc_servers_count == 0) {
        return;
    }

    if (++upstream->rcserver_index >= upstream->rc_servers_count) {
        upstream->rcserver_index = 0;
    }

    addr_in = (struct sockaddr_in *)upstream->ups_addr->sockaddr;
    addr = (ngx_http_tfs_inet_t*)&upstream->rc_servers[upstream->rcserver_index];
    addr_in->sin_addr.s_addr = addr->ip;
    addr_in->sin_port = htons(addr->port);
}
