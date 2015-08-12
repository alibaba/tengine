
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_md5.h>
#include <ngx_http_tfs_duplicate.h>
#include <ngx_http_tfs_data_server_message.h>
#include <ngx_http_tfs_remote_block_cache.h>


static void ngx_http_tfs_dedup_get_handler(ngx_http_tair_key_value_t *kv,
    ngx_int_t rc, void *data);
static void ngx_http_tfs_dedup_set_handler(ngx_int_t rc, void *data);
static void ngx_http_tfs_dedup_remove_handler(ngx_int_t rc, void *data);
static void ngx_http_tfs_dedup_callback(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_int_t rc);

ngx_int_t ngx_http_tfs_dedup_check_suffix(ngx_str_t *tfs_name,
    ngx_str_t *suffix);
ngx_int_t ngx_http_tfs_dedup_check_filename(ngx_str_t *dup_name,
    ngx_http_tfs_raw_fsname_t* fsname);


ngx_int_t
ngx_http_tfs_dedup_get(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t * log)
{
    u_char               *p;
    ssize_t               data_len;
    ngx_int_t             rc;
    ngx_http_tair_data_t  tair_key;

    data_len = 0;

    rc = ngx_http_tfs_sum_md5(ctx->file_data, ctx->tair_key, &data_len, log);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    p = ctx->tair_key;
    p += NGX_HTTP_TFS_MD5_RESULT_LEN;

    *(uint32_t *) p = htonl(data_len);

    tair_key.type = NGX_HTTP_TAIR_BYTEARRAY;
    tair_key.data = ctx->tair_key;
    tair_key.len = NGX_HTTP_TFS_DUPLICATE_KEY_SIZE;

    ctx->md5_sumed = 1;

    rc = ngx_http_tfs_tair_get_helper(ctx->tair_instance, pool, log,
                                      &tair_key,
                                      ngx_http_tfs_dedup_get_handler,
                                      ctx);

    return rc;
}


static void
ngx_http_tfs_dedup_get_handler(ngx_http_tair_key_value_t *kv, ngx_int_t rc,
    void *data)
{
    u_char                    *p;
    ngx_http_tfs_t            *t;
    ngx_http_tfs_dedup_ctx_t  *ctx;

    ctx = data;
    t = ctx->data;

    if (rc == NGX_HTTP_ETAIR_SUCCESS) {
        p = kv->value->data;
        if (p != NULL
            && (kv->value->len > NGX_HTTP_TFS_DUPLICATE_VALUE_BASE_SIZE))
        {
            ctx->file_ref_count = *(int32_t *)p;
            p += sizeof(int32_t);
            ctx->dup_file_name.len = kv->value->len - sizeof(int32_t);
            ctx->dup_file_name.data = ngx_pcalloc(t->pool,
                                                  ctx->dup_file_name.len);
            if (ctx->dup_file_name.data == NULL) {
                rc = NGX_ERROR;

            } else {
                ngx_memcpy(ctx->dup_file_name.data, p, ctx->dup_file_name.len);
                rc = NGX_OK;
            }
            ctx->dup_version = kv->version;

        } else {
            rc = NGX_ERROR;
        }
        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "get duplicate info: "
                       "file name: %V, file ref count: %d, dup_version: %d",
                       &ctx->dup_file_name,
                       ctx->file_ref_count,
                       ctx->dup_version);

    } else {
        rc = NGX_ERROR;
        ctx->dup_version = NGX_HTTP_TFS_DUPLICATE_INITIAL_MAGIC_VERSION;
    }
    ngx_http_tfs_dedup_callback(ctx, rc);
}


ngx_int_t
ngx_http_tfs_dedup_set(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t * log)
{
    u_char               *p;
    ssize_t               data_len;
    ngx_int_t             rc;
    ngx_http_tair_data_t  tair_key, tair_value;

    data_len = 0;

    if (!ctx->md5_sumed) {
        rc = ngx_http_tfs_sum_md5(ctx->file_data, ctx->tair_key, &data_len,
                                  log);
        if (rc == NGX_ERROR) {
            return NGX_ERROR;
        }

        p = ctx->tair_key;
        p += NGX_HTTP_TFS_MD5_RESULT_LEN;

        *(uint32_t *) p = htonl(data_len);
        ctx->md5_sumed = 1;
    }

    tair_key.len = NGX_HTTP_TFS_DUPLICATE_KEY_SIZE;
    tair_key.data = ctx->tair_key;
    tair_key.type = NGX_HTTP_TAIR_BYTEARRAY;

    tair_value.len =
        NGX_HTTP_TFS_DUPLICATE_VALUE_BASE_SIZE + ctx->dup_file_name.len;
    tair_value.data = ngx_pcalloc(pool, tair_value.len);
    if (tair_value.data == NULL) {
        return NGX_ERROR;
    }
    ngx_memcpy(tair_value.data, &ctx->file_ref_count,
               NGX_HTTP_TFS_DUPLICATE_VALUE_BASE_SIZE);
    ngx_memcpy(tair_value.data + NGX_HTTP_TFS_DUPLICATE_VALUE_BASE_SIZE,
               ctx->dup_file_name.data, ctx->dup_file_name.len);
    tair_value.type = NGX_HTTP_TAIR_BYTEARRAY;
    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, log, 0,
                   "set duplicate info: "
                   "file name: %V, file ref count: %d, dup_version: %d",
                   &ctx->dup_file_name,
                   ctx->file_ref_count,
                   ctx->dup_version);

    rc = ngx_http_tfs_tair_put_helper(ctx->tair_instance, pool, log,
                                      &tair_key, &tair_value, 0/*expire*/,
                                      ctx->dup_version,
                                      ngx_http_tfs_dedup_set_handler, ctx);

    return rc;
}


static void
ngx_http_tfs_dedup_set_handler(ngx_int_t rc, void *data)
{
    ngx_http_tfs_dedup_ctx_t  *ctx;

    ctx = data;

    if (rc == NGX_HTTP_ETAIR_SUCCESS) {
        rc = NGX_OK;

    } else {
        rc = NGX_ERROR;
    }
    ngx_http_tfs_dedup_callback(ctx, rc);
}


ngx_int_t
ngx_http_tfs_dedup_remove(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t * log)
{
    u_char                *p;
    ssize_t                data_len;
    ngx_int_t              rc;
    ngx_array_t            tair_keys;
    ngx_http_tair_data_t  *tair_key;

    data_len = 0;

    if (!ctx->md5_sumed) {
        rc = ngx_http_tfs_sum_md5(ctx->file_data, ctx->tair_key, &data_len,
                                  log);
        if (rc == NGX_ERROR) {
            return NGX_ERROR;
        }

        p = ctx->tair_key;
        p += NGX_HTTP_TFS_MD5_RESULT_LEN;

        *(uint32_t *) p = htonl(data_len);
        ctx->md5_sumed = 1;
    }

    rc = ngx_array_init(&tair_keys, pool, 1, sizeof(ngx_http_tair_data_t));
    if (rc == NGX_ERROR) {
        return rc;
    }
    tair_key = (ngx_http_tair_data_t*) ngx_array_push(&tair_keys);

    tair_key->type = NGX_HTTP_TAIR_BYTEARRAY;
    tair_key->data = ctx->tair_key;
    tair_key->len = NGX_HTTP_TFS_DUPLICATE_KEY_SIZE;

    rc = ngx_http_tfs_tair_delete_helper(ctx->tair_instance, pool, log,
                                         &tair_keys,
                                         ngx_http_tfs_dedup_remove_handler,
                                         ctx);

    return rc;
}


static void
ngx_http_tfs_dedup_remove_handler(ngx_int_t rc, void *data)
{
    ngx_http_tfs_dedup_ctx_t  *ctx;

    ctx = data;

    if (rc == NGX_HTTP_ETAIR_SUCCESS) {
        rc = NGX_OK;

    } else {
        rc = NGX_ERROR;
    }

    ngx_http_tfs_dedup_callback(ctx, rc);
}


ngx_int_t
ngx_http_tfs_dedup_check_suffix(ngx_str_t *tfs_name, ngx_str_t *suffix)
{
    ngx_int_t  rc;

    rc = NGX_ERROR;
    if ((tfs_name->len == NGX_HTTP_TFS_FILE_NAME_LEN && suffix->len == 0)
        || (tfs_name->len > NGX_HTTP_TFS_FILE_NAME_LEN && suffix->len > 0
            && ((tfs_name->len - NGX_HTTP_TFS_FILE_NAME_LEN) == suffix->len)
            && (ngx_strncmp(suffix->data,
                            tfs_name->data + NGX_HTTP_TFS_FILE_NAME_LEN,
                            suffix->len) == 0)))
    {
        rc = NGX_OK;
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_dedup_check_filename(ngx_str_t *dup_file_name,
    ngx_http_tfs_raw_fsname_t* fsname)
{
    ngx_int_t                  rc;
    ngx_str_t                  dup_file_suffix = ngx_null_string;
    ngx_http_tfs_raw_fsname_t  dup_fsname;

    rc = ngx_http_tfs_raw_fsname_parse(dup_file_name, &dup_file_suffix,
                                       &dup_fsname);
    if (rc == NGX_OK) {
        if (fsname->cluster_id == dup_fsname.cluster_id
            && fsname->file.block_id == dup_fsname.file.block_id
            && fsname->file.seq_id == dup_fsname.file.seq_id
            && fsname->file.suffix == dup_fsname.file.suffix)
        {
            return NGX_OK;
        }
    }

    return NGX_ERROR;
}


static void
ngx_http_tfs_dedup_callback(ngx_http_tfs_dedup_ctx_t *ctx, ngx_int_t rc)
{
    ngx_http_tfs_t           *t;
    ngx_http_tfs_rcs_info_t  *rc_info;

    t = ctx->data;
    rc_info = t->rc_info_node;

    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT:
            /* exist in tair */
            if (rc == NGX_OK) {
                /* check file name */
                rc = ngx_http_tfs_dedup_check_filename(&ctx->dup_file_name,
                                                       &t->r_ctx.fsname);
                if (rc == NGX_OK) {
                    /* file name match, modify ref count and save tair */
                    if (t->r_ctx.unlink_type == NGX_HTTP_TFS_UNLINK_DELETE) {
                        if (--ctx->file_ref_count <= 0) {
                            /* if ref count is 0,
                             * remove key from tair then unlink file
                             */
                            t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO;
                            t->is_stat_dup_file = NGX_HTTP_TFS_NO;
                            t->tfs_peer->body_buffer = ctx->save_body_buffer;
                            ctx->file_data = t->meta_segment_data;
                            rc = ngx_http_tfs_dedup_remove(ctx, t->pool,
                                                           t->log);
                            /* do not care delete tair fail,
                             * go on unlinking file
                             */
                            if (rc == NGX_ERROR) {
                                ngx_http_tfs_finalize_state(t, NGX_OK);
                            }

                            return;
                        }

                        /* file_ref_count > 0, just save tair */
                        t->state = NGX_HTTP_TFS_STATE_REMOVE_DONE;
                        ctx->file_data = t->meta_segment_data;
                        rc = ngx_http_tfs_dedup_set(ctx, t->pool, t->log);
                        /* do not care save tair fail, return success */
                        if (rc == NGX_ERROR) {
                            ngx_http_tfs_finalize_state(t, NGX_DONE);
                        }

                        return;
                    }
                }

                /* file name not match, unlink file */
                t->tfs_peer->body_buffer = ctx->save_body_buffer;
                t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO;
                t->is_stat_dup_file = NGX_HTTP_TFS_NO;
                ngx_http_tfs_finalize_state(t, NGX_OK);

                return;
            }

            /* not exist in tair, unlink file */
            t->tfs_peer->body_buffer = ctx->save_body_buffer;
            t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO;
            t->is_stat_dup_file = NGX_HTTP_TFS_NO;
            ngx_http_tfs_finalize_state(t, NGX_OK);
            return;
        case NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO:
        case NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA:
            ngx_http_tfs_finalize_state(t, NGX_OK);
            return;
        case NGX_HTTP_TFS_STATE_REMOVE_DONE:
            ngx_http_tfs_finalize_state(t, NGX_DONE);
            return;
        }
        break;
    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS:
        case NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO:
            /* exist in tair */
            if (rc == NGX_OK) {
                /* check suffix */
                rc = ngx_http_tfs_dedup_check_suffix(&ctx->dup_file_name,
                                                     &t->r_ctx.file_suffix);
                if (rc == NGX_OK) {
                    /* suffix match, need to stat file */
                    rc = ngx_http_tfs_raw_fsname_parse(&ctx->dup_file_name,
                                                       &ctx->dup_file_suffix,
                                                       &t->r_ctx.fsname);
                    if (rc == NGX_OK) {
                        t->file.cluster_id = t->r_ctx.fsname.cluster_id;
                        t->is_stat_dup_file = NGX_HTTP_TFS_YES;
                        t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
                    }

                } else {
                    /* suffix not match, need save new tfs file,
                     * do not save tair
                     */
                    t->use_dedup = NGX_HTTP_TFS_NO;
                }
            } /* not exist in tair need save new tfs file and tair */

            /* need reset meta segment */
            rc = ngx_http_tfs_get_meta_segment(t);
            if (rc != NGX_OK) {
                ngx_log_error(NGX_LOG_ERR, t->log, 0,
                              "tfs get meta segment failed");
                ngx_http_tfs_finalize_request(t->data, t,
                                              NGX_HTTP_INTERNAL_SERVER_ERROR);
                return;
            }

            /* lookup block cache */
            if (t->is_stat_dup_file) {
                /* dedup write may need to stat file */
                if (rc_info->use_remote_block_cache) {
                    rc = ngx_http_tfs_get_remote_block_cache_instance(
                              &t->block_cache_ctx.remote_ctx,
                              &rc_info->remote_block_cache_info);
                    if (rc == NGX_ERROR) {
                        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                     "get remote block cache instance failed.");

                    } else {
                        t->block_cache_ctx.use_cache |=
                            NGX_HTTP_TFS_REMOTE_BLOCK_CACHE;
                    }
                }

                ngx_http_tfs_lookup_block_cache(t);

                return;
            }

            ngx_http_tfs_finalize_state(t, NGX_OK);
            break;
        case NGX_HTTP_TFS_STATE_WRITE_STAT_DUP_FILE:
            if (rc == NGX_OK) {
                t->state = NGX_HTTP_TFS_STATE_WRITE_DONE;
                ngx_http_tfs_finalize_state(t, NGX_DONE);

            } else {
                /* save tair(add ref count) failed,
                 * need save new tfs file, do not save tair
                 */
                t->state = NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS;
                t->is_stat_dup_file = NGX_HTTP_TFS_NO;
                t->use_dedup = NGX_HTTP_TFS_NO;
                /* need reset output buf */
                t->out_bufs = NULL;
                /* need reset block id and file id */
                t->file.segment_data[0].segment_info.block_id = 0;
                t->file.segment_data[0].segment_info.file_id = 0;
                ngx_http_tfs_finalize_state(t, NGX_OK);
            }
            break;
        case NGX_HTTP_TFS_STATE_WRITE_DONE:
            ngx_http_tfs_finalize_state(t, NGX_DONE);
            break;
        }
    }
    return;
}


#ifdef NGX_HTTP_TFS_USE_TAIR

ngx_int_t
ngx_http_tfs_get_dedup_instance(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_http_tfs_tair_server_addr_info_t *server_addr_info,
    uint32_t server_addr_hash)
{
    ngx_str_t                     *st;
    ngx_int_t                      rc, i;
    ngx_array_t                    config_server;
    ngx_http_tfs_t                *t;
    ngx_http_etair_server_conf_t  *server;
    ngx_http_tfs_tair_instance_t  *instance;

    t = ctx->data;

    for (i = 0; i < NGX_HTTP_TFS_MAX_CLUSTER_COUNT; i++) {
        instance = &t->main_conf->dup_instances[i];

        if (instance->server == NULL) {
            break;
        }

        if (instance->server_addr_hash == server_addr_hash) {
            ctx->tair_instance = instance;
            return NGX_OK;
        }
    }

    /* not found && full, clear */
    if (i > NGX_HTTP_TFS_MAX_CLUSTER_COUNT) {
        for (i = 0; i < NGX_HTTP_TFS_MAX_CLUSTER_COUNT; i++) {
            instance = &t->main_conf->dup_instances[i];
            if (instance->server != NULL) {
                ngx_http_etair_destory_server(instance->server,
                                              (ngx_cycle_t *) ngx_cycle);
                instance->server = NULL;
            }
        }
        instance = &t->main_conf->dup_instances[0];
    }

    rc = ngx_array_init(&config_server, t->pool,
                        NGX_HTTP_TFS_TAIR_CONFIG_SERVER_COUNT,
                        sizeof(ngx_str_t));
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    for (i = 0; i < NGX_HTTP_TFS_TAIR_CONFIG_SERVER_COUNT; i++) {
        if (server_addr_info->server[i].len > 0 ) {
            st = (ngx_str_t *) ngx_array_push(&config_server);
            *st = server_addr_info->server[i];
        }
    }

    server = &server_addr_info->server[NGX_HTTP_TFS_TAIR_CONFIG_SERVER_COUNT];
    server = ngx_http_etair_create_server(server,
                                          &config_server,
                                          t->main_conf->tair_timeout,
                                          (ngx_cycle_t *) ngx_cycle);
    if (server == NULL) {
        return NGX_ERROR;
    }

    instance->server = server;
    instance->server_addr_hash = server_addr_hash;
    instance->area = server_addr_info->area;
    ctx->tair_instance = instance;

    return NGX_OK;
}

#else

ngx_int_t
ngx_http_tfs_get_dedup_instance(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_http_tfs_tair_server_addr_info_t *server_addr_info,
    uint32_t server_addr_hash)
{
    return NGX_ERROR;
}

#endif
