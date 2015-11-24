
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_errno.h>
#include <ngx_http_tfs_duplicate.h>
#include <ngx_http_tfs_server_handler.h>
#include <ngx_http_tfs_root_server_message.h>
#include <ngx_http_tfs_meta_server_message.h>
#include <ngx_http_tfs_rc_server_message.h>
#include <ngx_http_tfs_name_server_message.h>
#include <ngx_http_tfs_data_server_message.h>
#include <ngx_http_tfs_remote_block_cache.h>


ngx_int_t
ngx_http_tfs_create_rs_request(ngx_http_tfs_t *t)
{
    ngx_chain_t  *cl;

    cl = ngx_http_tfs_root_server_create_message(t->pool);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    t->request_bufs = cl;

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_process_rs(ngx_http_tfs_t *t)
{
    ngx_int_t                        rc;
    ngx_buf_t                       *b;
    ngx_http_tfs_inet_t             *addr;
    ngx_http_tfs_header_t           *header;
    ngx_http_tfs_peer_connection_t  *tp;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    b = &tp->body_buffer;

    if (ngx_buf_size(b) < header->len) {
        return NGX_AGAIN;
    }

    rc = ngx_http_tfs_root_server_parse_message(t);
    if (rc != NGX_OK) {
        return rc;
    }

    t->state += 1;

    ngx_http_tfs_set_custom_initial_parameters(t);

    addr = ngx_http_tfs_select_meta_server(t);
    ngx_http_tfs_peer_set_addr(t->pool,
                               &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER],
                               addr);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_create_ms_request(ngx_http_tfs_t *t)
{
    ngx_chain_t                              *cl;

    cl = ngx_http_tfs_meta_server_create_message(t);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    t->request_bufs = cl;

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_process_ms(ngx_http_tfs_t *t)
{
    ngx_buf_t                        *b;
    ngx_int_t                         rc, dir_levels, parent_dir_len;
    ngx_chain_t                      *cl, **ll;
    ngx_http_tfs_header_t            *header;
    ngx_http_tfs_peer_connection_t   *tp;
    ngx_http_tfs_logical_cluster_t   *logical_cluster;
    ngx_http_tfs_physical_cluster_t  *physical_cluster;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    b = &tp->body_buffer;

    if (ngx_buf_size(b) < header->len) {
        return NGX_AGAIN;
    }

    rc = ngx_http_tfs_meta_server_parse_message(t);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    b->pos += header->len;

    /* need update meta table */
    if (rc == NGX_HTTP_TFS_EXIT_LEASE_EXPIRED
        || rc == NGX_HTTP_TFS_EXIT_TABLE_VERSION_ERROR)
    {
        t->state = NGX_HTTP_TFS_STATE_ACTION_GET_META_TABLE;
        ngx_http_tfs_clear_buf(b);

        ngx_http_tfs_peer_set_addr(t->pool,
                         &t->tfs_peer_servers[NGX_HTTP_TFS_ROOT_SERVER],
                         (ngx_http_tfs_inet_t *)&t->loc_conf->meta_root_server);

        ngx_log_error(NGX_LOG_DEBUG, t->log, 0,
                      "need update meta table, rc: %i", rc);

        return NGX_OK;
    }

    /* parent dir not exist, recursive create them */
    if (rc == NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR && t->r_ctx.recursive) {
        switch (t->r_ctx.action.code) {
        case NGX_HTTP_TFS_ACTION_CREATE_DIR:
        case NGX_HTTP_TFS_ACTION_CREATE_FILE:
        case NGX_HTTP_TFS_ACTION_MOVE_DIR:
        case NGX_HTTP_TFS_ACTION_MOVE_FILE:
            if (t->dir_lens == NULL) {
                parent_dir_len = ngx_http_tfs_get_parent_dir(&t->last_file_path,
                                                             &dir_levels);
                t->dir_lens = ngx_pcalloc(t->pool,
                                          sizeof(ngx_int_t) * dir_levels);
                if (t->dir_lens == NULL) {
                    return NGX_ERROR;
                }
                t->last_dir_level = 0;
                t->dir_lens[0] = t->last_file_path.len;

            } else {
                parent_dir_len = ngx_http_tfs_get_parent_dir(&t->last_file_path,
                                                             NULL);
            }
            t->last_dir_level++;
            t->dir_lens[t->last_dir_level] = parent_dir_len;
            t->last_file_path.len = t->dir_lens[t->last_dir_level];
            t->orig_action = t->r_ctx.action.code;
            /* temporarily modify */
            t->r_ctx.action.code = NGX_HTTP_TFS_ACTION_CREATE_DIR;
            return NGX_OK;
        }
    }

    /* parent dir may be created by others
     * during the recursive creating process
     */
    if (rc == NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR && t->last_dir_level > 0) {
        rc = NGX_OK;
    }

    if (rc == NGX_OK || rc == NGX_DECLINED) {
        switch (t->r_ctx.action.code) {
        case NGX_HTTP_TFS_ACTION_CREATE_DIR:
        case NGX_HTTP_TFS_ACTION_CREATE_FILE:
        case NGX_HTTP_TFS_ACTION_MOVE_DIR:
        case NGX_HTTP_TFS_ACTION_MOVE_FILE:
            if (t->dir_lens != NULL) {
                if (t->last_dir_level > 0) {
                    if (t->last_dir_level == 1) {
                        t->r_ctx.action.code = t->orig_action;
                    }
                    t->last_file_path.len = t->dir_lens[--(t->last_dir_level)];
                    return NGX_OK;
                }
            }
        case NGX_HTTP_TFS_ACTION_REMOVE_DIR:
            t->state = NGX_HTTP_TFS_STATE_ACTION_DONE;
            return NGX_DONE;

        case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
            switch (t->state) {
            case NGX_HTTP_TFS_STATE_REMOVE_GET_FRAG_INFO:
                if (rc == NGX_DECLINED) {
                    t->state = NGX_HTTP_TFS_STATE_REMOVE_NOTIFY_MS;
                    ngx_http_tfs_clear_buf(b);
                    return NGX_OK;
                }
                t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO;
                break;
            case NGX_HTTP_TFS_STATE_REMOVE_NOTIFY_MS:
                t->state = NGX_HTTP_TFS_STATE_REMOVE_DONE;
                return NGX_DONE;
            }
            break;
        case NGX_HTTP_TFS_ACTION_LS_FILE:
            if (t->r_ctx.chk_exist == NGX_HTTP_TFS_NO && t->meta_info.file_count > 0) {
                /* need json output */
                for (cl = t->out_bufs, ll = &t->out_bufs; cl; cl = cl->next) {
                    ll = &cl->next;
                }

                cl = ngx_http_tfs_json_custom_file_info(t->json_output,
                                                        &t->meta_info,
                                                        t->r_ctx.file_type);
                if (cl == NULL) {
                    return NGX_ERROR;
                }

                *ll = cl;
            }

            t->state = NGX_HTTP_TFS_STATE_ACTION_DONE;
            return NGX_DONE;

        case NGX_HTTP_TFS_ACTION_READ_FILE:
            if (rc == NGX_DECLINED
                || (t->r_ctx.chk_file_hole && !t->file.still_have))
            {
                if (t->r_ctx.chk_file_hole) {
                    /* need json output */
                    if (t->file_holes.nelts > 0) {
                        t->json_output = ngx_http_tfs_json_init(t->log,
                                                                t->pool);
                        if (t->json_output == NULL) {
                            return NGX_ERROR;
                        }

                        for (cl = t->out_bufs, ll = &t->out_bufs;
                             cl;
                             cl = cl->next)
                        {
                            ll = &cl->next;
                        }

                        cl = ngx_http_tfs_json_file_hole_info(t->json_output,
                                                              &t->file_holes);
                        if (cl == NULL) {
                            return NGX_ERROR;
                        }

                        *ll = cl;
                    }

                }
                t->state = NGX_HTTP_TFS_STATE_READ_DONE;
                return NGX_DONE;
            }

            if (t->r_ctx.chk_file_hole) {
                ngx_http_tfs_clear_buf(b);
                return NGX_OK;
            }

            t->state = NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO;
            break;

        case NGX_HTTP_TFS_ACTION_WRITE_FILE:
            switch (t->state) {
            case NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_MS:
                t->state = NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS;
                break;

            case NGX_HTTP_TFS_STATE_WRITE_WRITE_MS:
                if (t->file.left_length == 0) {
                    t->state = NGX_HTTP_TFS_STATE_WRITE_DONE;
                    return NGX_DONE;
                }
                t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
            }
            break;
        default:
            return NGX_ERROR;
        }

        /* NGX_OK */

        /* only select once */
        if (t->name_server_addr_text.len == 0) {
            rc = ngx_http_tfs_select_name_server(t, t->rc_info_node,
                                                 &t->name_server_addr,
                                                 &t->name_server_addr_text);
            if (rc == NGX_ERROR) {
                /* in order to return 404 */
                return NGX_HTTP_TFS_EXIT_SERVER_OBJECT_NOT_FOUND;
            }

            ngx_http_tfs_peer_set_addr(t->pool,
                                 &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER],
                                 &t->name_server_addr);

            /* skip get cluster id from ns */
            if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE
                && t->state == NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS)
            {
                logical_cluster =
                   &t->rc_info_node->logical_clusters[t->logical_cluster_index];
                physical_cluster =
                    &logical_cluster->rw_clusters[t->rw_cluster_index];
                if (physical_cluster->cluster_id > 0) {
                    if (t->file.cluster_id == 0) {
                        t->file.cluster_id = physical_cluster->cluster_id;

                    } else if (t->file.cluster_id
                               != physical_cluster->cluster_id)
                    {
                        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                      "error, cluster id conflict: "
                                      "%uD(ns) <> %uD(ms)",
                                      physical_cluster->cluster_id,
                                      t->file.cluster_id);
                        return NGX_ERROR;
                    }
                    t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
                }
            }
        }

        if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE) {
            /* lookup block cache */
            t->block_cache_ctx.curr_lookup_cache =
                NGX_HTTP_TFS_LOCAL_BLOCK_CACHE;
            t->decline_handler = ngx_http_tfs_batch_lookup_block_cache;
            return NGX_DECLINED;
        }

        return NGX_OK;
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_process_ms_ls_dir(ngx_http_tfs_t *t)
{
    ngx_buf_t                        *b;
    ngx_int_t                         rc;
    ngx_chain_t                      *cl, **ll;
    ngx_http_tfs_ms_ls_response_t    *fake_rsp;
    ngx_http_tfs_peer_connection_t   *tps;
    ngx_http_tfs_peer_connection_t   *tp;
    ngx_http_tfs_custom_meta_info_t  *meta_info;

    tp = t->tfs_peer;
    b = &tp->body_buffer;
    tps = t->tfs_peer_servers;

    if (t->length != ngx_buf_size(b) && b->last != b->end) {
        return NGX_AGAIN;
    }

    rc = ngx_http_tfs_meta_server_parse_message(t);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    /* need update meta table */
    if (rc == NGX_HTTP_TFS_EXIT_LEASE_EXPIRED
        || rc == NGX_HTTP_TFS_EXIT_TABLE_VERSION_ERROR)
    {
        t->state = NGX_HTTP_TFS_STATE_ACTION_GET_META_TABLE;
        ngx_http_tfs_clear_buf(b);

        ngx_http_tfs_peer_set_addr(t->pool,
                                   &tps[NGX_HTTP_TFS_ROOT_SERVER],
                                   (ngx_http_tfs_inet_t *)
                                    &t->loc_conf->meta_root_server);

        ngx_log_error(NGX_LOG_DEBUG, t->log, 0,
                      "need update meta table, rc: %i", rc);

        return NGX_OK;
    }

    if (rc == NGX_OK) {
        if (t->length == 0) {
            if (!t->r_ctx.chk_exist) {
                if (t->file.still_have) {
                    ngx_http_tfs_clear_buf(b);
                    return NGX_OK;
                }

                if (t->meta_info.file_count > 0) {
                    /* need json output */
                    for (cl = t->out_bufs, ll = &t->out_bufs; cl; cl = cl->next)
                    {
                        ll = &cl->next;
                    }

                    cl = ngx_http_tfs_json_custom_file_info(t->json_output,
                                                            &t->meta_info,
                                                            t->r_ctx.file_type);
                    if (cl == NULL) {
                        return NGX_ERROR;
                    }

                    *ll = cl;
                }
            }

            t->state = NGX_HTTP_TFS_STATE_ACTION_DONE;
            return NGX_DONE;
        }

        /* t->length > 0 */
        /* find current meta_info */
        for(meta_info = &t->meta_info;
            meta_info->next;
            meta_info = meta_info->next);

        if (meta_info->rest_file_count > 0) {
            /* fake next ls_dir response head */
            fake_rsp = (ngx_http_tfs_ms_ls_response_t *) b->start;
            fake_rsp->still_have = 1;
            fake_rsp->count = meta_info->rest_file_count;
            b->last =
                ngx_movemem(b->start + sizeof(ngx_http_tfs_ms_ls_response_t),
                            b->pos, ngx_buf_size(b));
            b->pos = b->start;
            /* FIXME: fake len will be minus later, ugly */
            t->length += ngx_buf_size(b);
            return NGX_AGAIN;
        }

    }

    return rc;
}


ngx_int_t
ngx_http_tfs_create_rcs_request(ngx_http_tfs_t *t)
{
    ngx_chain_t  *cl;

    cl = ngx_http_tfs_rc_server_create_message(t);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    t->request_bufs = cl;

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_process_rcs(ngx_http_tfs_t *t)
{
    ngx_buf_t                       *b;
    ngx_int_t                        rc;
    ngx_http_tfs_rc_ctx_t           *rc_ctx;
    ngx_http_tfs_rcs_info_t         *rc_info;
    ngx_http_tfs_peer_connection_t  *tp;

    tp = t->tfs_peer;
    b = &tp->body_buffer;
    rc_ctx = t->loc_conf->upstream->rc_ctx;

    rc = ngx_http_tfs_rc_server_parse_message(t);

    ngx_http_tfs_clear_buf(b);

    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_KEEPALIVE) {
        if (t->curr_ka_queue == ngx_queue_sentinel(&rc_ctx->sh->kp_queue)) {
            rc = NGX_DONE;
        }

        return rc;
    }

    if (rc == NGX_ERROR || rc <= NGX_HTTP_TFS_EXIT_GENERAL_ERROR) {
        return rc;
    }

    rc_info = t->rc_info_node;

    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_GET_APPID) {
        rc = ngx_http_tfs_set_output_appid(t, rc_info->app_id);
        if (rc == NGX_ERROR) {
            return NGX_ERROR;
        }

        return NGX_DONE;
    }

    /* TODO: use fine granularity mutex(per rc_info_node mutex) */
    rc = ngx_http_tfs_misc_ctx_init(t, rc_info);

    return rc;
}


ngx_int_t
ngx_http_tfs_create_ns_request(ngx_http_tfs_t *t)
{
    ngx_chain_t                              *cl;

    cl = ngx_http_tfs_name_server_create_message(t);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    t->request_bufs = cl;

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_process_ns(ngx_http_tfs_t *t)
{
    uint32_t                          cluster_id;
    ngx_buf_t                        *b;
    ngx_int_t                         rc;
    ngx_str_t                        *cluster_id_text;
    ngx_http_tfs_inet_t              *addr;
    ngx_http_tfs_header_t            *header;
    ngx_http_tfs_rcs_info_t          *rc_info;
    ngx_http_tfs_peer_connection_t   *tp;
    ngx_http_tfs_logical_cluster_t   *logical_cluster;
    ngx_http_tfs_physical_cluster_t  *physical_cluster;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    b = &tp->body_buffer;

    if (ngx_buf_size(b) < header->len) {
        return NGX_AGAIN;
    }

    rc = ngx_http_tfs_name_server_parse_message(t);

    ngx_http_tfs_clear_buf(b);
    if (rc == NGX_ERROR) {
        return rc;
    }

    if (rc <= NGX_HTTP_TFS_EXIT_GENERAL_ERROR) {
        return NGX_HTTP_TFS_AGAIN;
    }

    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_STAT_FILE:
        t->state = NGX_HTTP_TFS_STATE_STAT_STAT_FILE;
        break;
    case NGX_HTTP_TFS_ACTION_READ_FILE:
        if (!t->parent
            && (t->r_ctx.version == 2
                || (t->is_large_file && !t->is_process_meta_seg)))
        {
            t->decline_handler = ngx_http_tfs_batch_process_start;
            return NGX_DECLINED;
        }
        t->state = NGX_HTTP_TFS_STATE_READ_READ_DATA;
        break;
    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS:
            /* save cluster id */
            if (t->loc_conf->upstream->enable_rcs) {
                rc_info = t->rc_info_node;
                logical_cluster =
                    &rc_info->logical_clusters[t->logical_cluster_index];
                physical_cluster =
                    &logical_cluster->rw_clusters[t->rw_cluster_index];
                /* check ns cluster id with rc configure */
                cluster_id_text = &physical_cluster->cluster_id_text;
                cluster_id = ngx_http_tfs_get_cluster_id(cluster_id_text->data);
                if (t->file.cluster_id != cluster_id) {
                    ngx_log_error(NGX_LOG_ERR,
                                  t->log, 0,
                                  "error, cluster id conflict: "
                                  "%uD(ns) <> %uD(rcs)",
                                  t->file.cluster_id,
                                  cluster_id);
                    return NGX_ERROR;
                }
                physical_cluster->cluster_id = t->file.cluster_id;

            } else {
                t->main_conf->cluster_id = t->file.cluster_id;
            }
            t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
            return rc;

        case NGX_HTTP_TFS_STATE_WRITE_GET_GROUP_COUNT:
            if (t->group_count != 1) {
                t->state = NGX_HTTP_TFS_STATE_WRITE_GET_GROUP_SEQ;
                return rc;
            }
            /* group_count == 1, maybe able to make choice */
            t->group_seq = 0;
        case NGX_HTTP_TFS_STATE_WRITE_GET_GROUP_SEQ:
            rc_info = t->rc_info_node;
            ngx_http_tfs_rcs_set_group_info_by_addr(rc_info,
                                                    t->group_count,
                                                    t->group_seq,
                                                    t->name_server_addr);
            rc = ngx_http_tfs_select_name_server(t, rc_info,
                                                 &t->name_server_addr,
                                                 &t->name_server_addr_text);
            if (rc == NGX_ERROR) {
                return NGX_HTTP_TFS_EXIT_SERVER_OBJECT_NOT_FOUND;
            }

            tp->peer.free(&tp->peer, tp->peer.data, 0);

            ngx_http_tfs_peer_set_addr(t->pool,
                                       &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER],
                                       &t->name_server_addr);
            return rc;

        case NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO:
            if (t->is_stat_dup_file) {
                t->state = NGX_HTTP_TFS_STATE_WRITE_STAT_DUP_FILE;

            } else if (t->is_rolling_back) {
                t->state = NGX_HTTP_TFS_STATE_WRITE_DELETE_DATA;

            } else {
                if (!t->parent
                    && (t->r_ctx.version == 2
                        || (t->is_large_file && !t->is_process_meta_seg)))
                {
                    t->decline_handler = ngx_http_tfs_batch_process_start;
                    return NGX_DECLINED;
                }
                t->state = NGX_HTTP_TFS_STATE_WRITE_CREATE_FILE_NAME;
            }
            break;
        }
        break;
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_COUNT:
            /* maybe able to make choice */
            if (t->group_count != 1) {
                t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_SEQ;
            }
            /* group_count == 1, maybe able to make choice */
            t->group_seq = 0;
        case NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_SEQ:
            rc_info = t->rc_info_node;
            ngx_http_tfs_rcs_set_group_info_by_addr(rc_info,
                                                    t->group_count,
                                                    t->group_seq,
                                                    t->name_server_addr);
            rc = ngx_http_tfs_select_name_server(t, rc_info,
                                                 &t->name_server_addr,
                                                 &t->name_server_addr_text);
            if (rc == NGX_ERROR) {
                /* in order to return 404 */
                return NGX_HTTP_TFS_EXIT_SERVER_OBJECT_NOT_FOUND;
            }

            tp->peer.free(&tp->peer, tp->peer.data, 0);

            ngx_http_tfs_peer_set_addr(t->pool,
                             &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER],
                             &t->name_server_addr);
            return rc;
        case NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO:
            if (t->is_large_file
                && t->r_ctx.unlink_type == NGX_HTTP_TFS_UNLINK_DELETE
                && t->meta_segment_data == NULL)
            {
                t->state = NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT;

            } else if (t->is_stat_dup_file) {
                t->state = NGX_HTTP_TFS_STATE_REMOVE_STAT_FILE;

            } else {
                t->state = NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA;
            }
        }
        break;
    }

    addr = ngx_http_tfs_select_data_server(t,
                                  &t->file.segment_data[t->file.segment_index]);
    if (addr == NULL) {
        return NGX_ERROR;
    }

    ngx_http_tfs_peer_set_addr(t->pool,
                               &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER],
                               addr);
    return rc;
}


void
ngx_http_tfs_reset_segment_data(ngx_http_tfs_t *t)
{
    uint32_t                      block_count, i;
    ngx_http_tfs_segment_data_t  *segment_data;

    /* reset current lookup cache */
    t->block_cache_ctx.curr_lookup_cache = NGX_HTTP_TFS_LOCAL_BLOCK_CACHE;

    block_count = t->file.segment_count - t->file.segment_index;
    if (block_count > NGX_HTTP_TFS_MAX_BATCH_COUNT) {
        block_count = NGX_HTTP_TFS_MAX_BATCH_COUNT;
    }

    segment_data = &t->file.segment_data[t->file.segment_index];
    for (i = 0; i < block_count; i++, segment_data++) {
        segment_data->cache_hit = NGX_HTTP_TFS_NO_BLOCK_CACHE;
        segment_data->block_info.ds_addrs = NULL;
        segment_data->ds_retry = 0;
        segment_data->ds_index = 0;
    }

    t->file.curr_batch_count = 0;
}


ngx_int_t
ngx_http_tfs_retry_ns(ngx_http_tfs_t *t)
{
    ngx_int_t                        rc;
    ngx_http_tfs_peer_connection_t  *tp;

    tp = t->tfs_peer;
    tp->peer.free(&tp->peer, tp->peer.data, 0);

    if (!t->retry_curr_ns) {
        t->rw_cluster_index++;
        rc = ngx_http_tfs_select_name_server(t, t->rc_info_node,
                                             &t->name_server_addr,
                                             &t->name_server_addr_text);
        if (rc == NGX_ERROR) {
            return NGX_HTTP_TFS_EXIT_SERVER_OBJECT_NOT_FOUND;
        }

        ngx_http_tfs_peer_set_addr(t->pool,
                                 &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER],
                                 &t->name_server_addr);

        ngx_http_tfs_reset_segment_data(t);

    } else {
        t->retry_curr_ns = NGX_HTTP_TFS_NO;
    }

    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_READ_FILE:
    case NGX_HTTP_TFS_ACTION_STAT_FILE:
        /* lookup block cache */
        if (t->block_cache_ctx.curr_lookup_cache
            != NGX_HTTP_TFS_NO_BLOCK_CACHE)
        {
            if (!t->parent
                && (t->r_ctx.version == 2
                    || (t->is_large_file && !t->is_process_meta_seg)))
            {
                t->decline_handler = ngx_http_tfs_batch_lookup_block_cache;

            } else {
                t->decline_handler = ngx_http_tfs_lookup_block_cache;
            }
            return t->decline_handler(t);
        }
        break;
    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        /* update not allow retry */
        if (t->r_ctx.is_raw_update) {
            return NGX_ERROR;
        }

        /* stat failed, do not dedup, save new tfs file and do not save tair */
        if (t->is_stat_dup_file) {
            t->is_stat_dup_file = NGX_HTTP_TFS_NO;
            t->use_dedup = NGX_HTTP_TFS_NO;
            t->state = NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS;
            t->file.segment_data[0].segment_info.block_id = 0;
            t->file.segment_data[0].segment_info.file_id = 0;
        }
    }

    if (ngx_http_tfs_reinit(t->data, t) != NGX_OK) {
        return NGX_ERROR;
    }

    ngx_http_tfs_connect(t);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_create_ds_request(ngx_http_tfs_t *t)
{
    ngx_chain_t  *cl;

    cl = ngx_http_tfs_data_server_create_message(t);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    t->request_bufs = cl;

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_process_ds(ngx_http_tfs_t *t)
{
    size_t                           b_size;
    uint32_t                         body_len, len_to_update;
    ngx_int_t                        rc;
    ngx_buf_t                       *b, *body_buffer;
    ngx_chain_t                     *cl, **ll;
    ngx_http_request_t              *r;
    ngx_http_tfs_header_t           *header;
    ngx_http_tfs_segment_data_t     *segment_data;
    ngx_http_tfs_peer_connection_t  *tp;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    b = &tp->body_buffer;

    body_len = header->len;
    if (ngx_buf_size(b) < body_len) {
        return NGX_AGAIN;
    }

    rc = ngx_http_tfs_data_server_parse_message(t);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    ngx_http_tfs_clear_buf(b);

    segment_data = &t->file.segment_data[t->file.segment_index];

    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_STAT_FILE:
        t->file_name = t->r_ctx.file_path_s;
        if (rc == NGX_OK) {
            t->state = NGX_HTTP_TFS_STATE_STAT_DONE;

            if (t->r_ctx.chk_exist == NGX_HTTP_TFS_NO) {
                /* need json output */
                for (cl = t->out_bufs, ll = &t->out_bufs; cl; cl = cl->next) {
                    ll = &cl->next;
                }

                cl = ngx_http_tfs_json_raw_file_stat(
                                  t->json_output,
                                  ngx_http_tfs_raw_fsname_get_name(&t->r_ctx.fsname,
                                                                   t->is_large_file,
                                                                   0),
                                  t->r_ctx.fsname.file.block_id,
                                  &t->file_stat);
                if (cl == NULL) {
                    return NGX_ERROR;
                }

                *ll = cl;
            }

            return NGX_DONE;
        }

        if (rc == NGX_HTTP_TFS_EXIT_NO_LOGICBLOCK_ERROR) {
            ngx_http_tfs_remove_block_cache(t, segment_data);
        }

        return NGX_HTTP_TFS_AGAIN;

    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_STAT_DUP_FILE:
            if (rc == NGX_OK) {
                if (t->file_stat.flag == NGX_HTTP_TFS_FILE_NORMAL) {
                    rc = ngx_http_tfs_set_output_file_name(t);
                    if (rc == NGX_ERROR) {
                        return NGX_ERROR;
                    }
                    r = t->data;
                    t->dedup_ctx.file_data = r->request_body->bufs;
                    t->dedup_ctx.file_ref_count += 1;
                    t->decline_handler = ngx_http_tfs_set_duplicate_info;
                    return NGX_DECLINED;
                }

            } else {
                /* stat success but file is deleted or concealed */
                /* need save new tfs file, but do not save tair */
                if (rc == NGX_HTTP_TFS_EXIT_FILE_INFO_ERROR
                    || rc == NGX_HTTP_TFS_EXIT_META_NOT_FOUND_ERROR)
                {
                    t->state = NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS;
                    t->is_stat_dup_file = NGX_HTTP_TFS_NO;
                    t->use_dedup = NGX_HTTP_TFS_NO;
                    /* need reset block id and file id */
                    t->file.segment_data[0].segment_info.block_id = 0;
                    t->file.segment_data[0].segment_info.file_id = 0;
                    rc = NGX_OK;

                } else {
                    /* stat failed will goto retry */
                    rc = NGX_HTTP_TFS_AGAIN;
                }
            }
            break;
        case NGX_HTTP_TFS_STATE_WRITE_CREATE_FILE_NAME:
            if (rc == NGX_OK) {
                t->state = NGX_HTTP_TFS_STATE_WRITE_WRITE_DATA;

            } else {
                /* create failed retry */
                return NGX_HTTP_TFS_AGAIN;
            }
            break;
        case NGX_HTTP_TFS_STATE_WRITE_WRITE_DATA:
            /* write failed retry */
            if (rc != NGX_OK) {
                return NGX_HTTP_TFS_AGAIN;
            }

            /* write success, update data buf, offset and crc */
            cl = segment_data->data;
            len_to_update = segment_data->oper_size;
            while (len_to_update > 0) {
                while (cl && ngx_buf_size(cl->buf) == 0) {
                    cl = cl->next;
                }
                if (cl == NULL) {
                    ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                  "update send data offset "
                                  "failed for early end.");
                    return NGX_ERROR;
                }
                b_size = ngx_min(ngx_buf_size(cl->buf), len_to_update);
                if (ngx_buf_in_memory(cl->buf)) {
                    cl->buf->pos += b_size;

                } else {
                    cl->buf->file_pos += b_size;
                }
                len_to_update -= b_size;
            }
            segment_data->data = cl;

            t->file.left_length -= segment_data->oper_size;
            t->stat_info.size += segment_data->oper_size;
            segment_data->oper_offset += segment_data->oper_size;
            segment_data->oper_size = ngx_min(t->file.left_length,
                                              NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);

            if (t->r_ctx.version == 1) {
                if (t->file.left_length > 0 && !t->is_large_file) {
                    t->state = NGX_HTTP_TFS_STATE_WRITE_WRITE_DATA;
                    return NGX_OK;
                }
            }
            t->state = NGX_HTTP_TFS_STATE_WRITE_CLOSE_FILE;
            break;
        case NGX_HTTP_TFS_STATE_WRITE_CLOSE_FILE:
            /* close failed retry */
            if (rc != NGX_OK) {
                return NGX_HTTP_TFS_AGAIN;
            }

            /* sub process return here */
            if (t->parent) {
                return NGX_DONE;
            }

            t->file.segment_index++;

            /* small file or large_file meta segment */
            if (t->r_ctx.version == 1) {
                /* client abort need roll back, remove all segments written */
                if (t->client_abort && t->r_ctx.is_raw_update == NGX_HTTP_TFS_NO) {
                    t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
                    t->is_rolling_back = NGX_HTTP_TFS_YES;
                    t->file.segment_index = 0;
                    return NGX_OK;
                }

                t->state = NGX_HTTP_TFS_STATE_WRITE_DONE;
                rc = ngx_http_tfs_set_output_file_name(t);
                if (rc == NGX_ERROR) {
                    return NGX_ERROR;
                }
                /* when new tfs file is saved,
                 * do not care saving tair is success or not
                 */
                if (t->use_dedup) {
                    r = t->data;
                    t->dedup_ctx.file_data = r->request_body->bufs;
                    t->dedup_ctx.file_ref_count += 1;
                    t->decline_handler = ngx_http_tfs_set_duplicate_info;
                    return NGX_DECLINED;
                }
                return NGX_DONE;
            }
            break;

         /* is rolling back */
         case NGX_HTTP_TFS_STATE_WRITE_DELETE_DATA:
             t->file.segment_index++;
             if (t->file.segment_index >= t->file.segment_count) {
                 if (t->client_abort) {
                     return NGX_HTTP_CLIENT_CLOSED_REQUEST;
                 }

                 if (t->request_timeout) {
                     return NGX_HTTP_REQUEST_TIME_OUT;
                 }

                 return NGX_ERROR;
             }

             t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
             return NGX_OK;
        }
        break;
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_STAT_FILE:
            if (rc == NGX_OK) {
                if (t->file_stat.flag == NGX_HTTP_TFS_FILE_NORMAL
                    || t->file_stat.flag == NGX_HTTP_TFS_FILE_CONCEAL)
                {
                    t->state = NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT;
                    segment_data->oper_size =
                                     ngx_min(t->file_stat.size,
                                             NGX_HTTP_TFS_MAX_READ_FILE_SIZE);
                    return NGX_OK;
                }

                /* file is deleted */
                return NGX_HTTP_TFS_EXIT_FILE_STATUS_ERROR;
            }
            /* stat failed will goto retry */
            return NGX_HTTP_TFS_AGAIN;
       case NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA:
            if (rc != NGX_OK) {
                return rc;
            }

            /* small file */
            if (t->r_ctx.version == 1 && !t->is_large_file) {
                t->state = NGX_HTTP_TFS_STATE_REMOVE_DONE;
                t->file_name = t->r_ctx.file_path_s;
                return NGX_DONE;
            }

            /* large_file && custom file */
            t->file.segment_index++;
            if (t->file.segment_index >= t->file.segment_count) {
                if (t->r_ctx.version == 1) {
                    /* large file */
                    t->state = NGX_HTTP_TFS_STATE_REMOVE_DONE;
                    t->file_name = t->r_ctx.file_path_s;
                    return NGX_DONE;
                }

                if (t->r_ctx.version == 2) {
                    if (!t->file.still_have) {
                        t->state = NGX_HTTP_TFS_STATE_REMOVE_NOTIFY_MS;

                    } else {
                        t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_FRAG_INFO;
                        t->file.file_offset = segment_data->segment_info.offset
                                            + segment_data->segment_info.size;
                        t->file.segment_index = 0;
                    }

                    body_buffer =
                     &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER].body_buffer;
                    ngx_http_tfs_clear_buf(body_buffer);
                }

            } else {
                t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO;
            }
            break;
        }
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_retry_ds(ngx_http_tfs_t *t)
{
    ngx_int_t                       rc;
    ngx_http_tfs_inet_t             *addr;
    ngx_http_tfs_segment_data_t     *segment_data;
    ngx_http_tfs_peer_connection_t  *tp;

    tp = t->tfs_peer;
    tp->peer.free(&tp->peer, tp->peer.data, 0);

    segment_data = &t->file.segment_data[t->file.segment_index];
    addr = ngx_http_tfs_select_data_server(t, segment_data);
    if (addr == NULL) {
        switch(t->r_ctx.action.code) {
        case NGX_HTTP_TFS_ACTION_STAT_FILE:
            t->state = NGX_HTTP_TFS_STATE_STAT_GET_BLK_INFO;
            break;
        case NGX_HTTP_TFS_ACTION_READ_FILE:
            t->state = NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO;
            break;
        case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
            if (t->is_large_file && t->is_process_meta_seg) {
                return NGX_HTTP_TFS_EXIT_SERVER_OBJECT_NOT_FOUND;
            }

            /* TODO: dedup */
            return NGX_ERROR;
        case NGX_HTTP_TFS_ACTION_WRITE_FILE:
            /* update not allow retry */
            if (t->r_ctx.is_raw_update) {
                return NGX_ERROR;
            }

            /* stat retry_ds failed, do not dedup,
             * save new tfs file and do not save tair
             */
            if (t->is_stat_dup_file) {
                t->is_stat_dup_file = NGX_HTTP_TFS_NO;
                t->use_dedup = NGX_HTTP_TFS_NO;
                t->state = NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS;
                t->file.segment_data[0].segment_info.block_id = 0;
                t->file.segment_data[0].segment_info.file_id = 0;
                t->retry_curr_ns = NGX_HTTP_TFS_YES;

            } else {
                /* allow retry other writable clusters */
                if (++t->retry_count <= NGX_HTTP_TFS_MAX_RETRY_COUNT) {
                    t->retry_curr_ns = NGX_HTTP_TFS_YES;
                }
                t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
                segment_data->segment_info.block_id = 0;
                segment_data->segment_info.file_id = 0;
                segment_data->write_file_number = 0;
                segment_data->segment_info.crc = 0;
                /* reset all write data from orig_data */
                segment_data->data = NULL;
                rc = ngx_chain_add_copy_with_buf(t->pool,
                    &segment_data->data, segment_data->orig_data);
                if (rc == NGX_ERROR) {
                    return NGX_ERROR;
                }

                t->file.left_length = segment_data->segment_info.size;
                segment_data->oper_offset = 0;
                segment_data->oper_size = ngx_min(t->file.left_length,
                                                  NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);
            }
            break;
        default:
            return NGX_ERROR;
        }

        t->tfs_peer = ngx_http_tfs_select_peer(t);
        if (t->tfs_peer == NULL) {
            return NGX_ERROR;
        }

        t->recv_chain->buf = &t->header_buffer;
        t->recv_chain->next->buf = &t->tfs_peer->body_buffer;

        /* reset ds retry count */
        segment_data->ds_retry = 0;

        if (t->retry_handler == NULL) {
            return NGX_ERROR;
        }

        return t->retry_handler(t);
    }

    ngx_http_tfs_peer_set_addr(t->pool,
                               &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER],
                               addr);

    if (ngx_http_tfs_reinit(t->data, t) != NGX_OK) {
        return NGX_ERROR;
    }

    ngx_http_tfs_connect(t);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_process_ds_read(ngx_http_tfs_t *t)
{
    size_t                           size;
    ngx_int_t                        rc;
    ngx_buf_t                       *b;
    ngx_http_tfs_segment_data_t     *segment_data;
    ngx_http_tfs_peer_connection_t  *tp;
    ngx_http_tfs_logical_cluster_t  *logical_cluster;

    tp = t->tfs_peer;
    b = &tp->body_buffer;

    size = ngx_buf_size(b);
    if (size == 0) {
        ngx_log_error(NGX_LOG_INFO, t->log, 0, "process ds read is zero");
        return NGX_AGAIN;
    }

    rc = ngx_http_tfs_data_server_parse_message(t);
    if (rc == NGX_ERROR || rc == NGX_HTTP_TFS_AGAIN) {
        ngx_http_tfs_clear_buf(b);
        return NGX_ERROR;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                   "t->length is %O, rc is %i",
                   t->length, rc);

    b->pos += size;

    if (t->length > 0) {
        return NGX_AGAIN;
    }

    segment_data = &t->file.segment_data[t->file.segment_index];

    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_READ_FILE:
        if (t->length == 0) {
            t->file.left_length -= segment_data->oper_size;
            t->file.file_offset += segment_data->oper_size;

            if (t->file.left_length == 0) {
                /* large_file meta segment */
                if (t->is_large_file && t->is_process_meta_seg) {
                    /* ready to read data segments */
                    *(t->meta_segment_data->buf) = *b;
                    /* reset buf pos to get whole file data */
                    t->meta_segment_data->buf->pos = t->meta_segment_data->buf->start;
                    rc = ngx_http_tfs_get_segment_for_read(t);
                    if (rc == NGX_ERROR) {
                        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                      "get segment for read failed");
                        return NGX_ERROR;
                    }

                    if (rc == NGX_DONE) {
                        /* pread and start_offset > file size */
                        t->state = NGX_HTTP_TFS_STATE_READ_DONE;
                        t->file_name = t->r_ctx.file_path_s;

                        return NGX_DONE;
                    }

                    t->is_process_meta_seg = NGX_HTTP_TFS_NO;
                    /* later will be alloc */
                    ngx_memzero(&t->tfs_peer->body_buffer, sizeof(ngx_buf_t));

                    t->state = NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO;

                    t->block_cache_ctx.curr_lookup_cache =
                                                 NGX_HTTP_TFS_LOCAL_BLOCK_CACHE;
                    t->decline_handler = ngx_http_tfs_batch_lookup_block_cache;
                    return NGX_DECLINED;
                }

                /* sub process also return here */
                t->state = NGX_HTTP_TFS_STATE_READ_DONE;
                t->file_name = t->r_ctx.file_path_s;

                return NGX_DONE;
            }

            /* small file */
            if ((t->r_ctx.version == 1 && !t->is_large_file)
                || (t->is_large_file && t->is_process_meta_seg))
            {
                segment_data->oper_size = ngx_min(t->file.left_length,
                                               NGX_HTTP_TFS_MAX_READ_FILE_SIZE);
                segment_data->oper_offset = t->file.file_offset;
                return rc;
            }
        }
        break;

        /* NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT */
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        if (t->length == 0) {
            t->file.left_length -= segment_data->oper_size;

            if (t->file.left_length == 0) {
                if (!t->is_large_file && t->use_dedup) {
                    logical_cluster =
                     &t->rc_info_node->logical_clusters[t->logical_cluster_index];

                    rc = ngx_http_tfs_get_dedup_instance(&t->dedup_ctx,
                                        &logical_cluster->dup_server_info,
                                        logical_cluster->dup_server_addr_hash);

                    if (rc == NGX_ERROR) {
                        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                      "get dedup instance failed.");
                        /* get dedup instance fail, do not unlink file,
                         * return success
                         */
                        t->state = NGX_HTTP_TFS_STATE_REMOVE_DONE;
                        return NGX_DONE;
                    }
                    *(t->meta_segment_data->buf) = t->tfs_peer->body_buffer;
                    /* reset buf pos to get whole file data */
                    t->meta_segment_data->buf->pos =
                                               t->meta_segment_data->buf->start;
                    t->dedup_ctx.file_data = t->meta_segment_data;
                    t->decline_handler = ngx_http_tfs_get_duplicate_info;
                    return NGX_DECLINED;
                }
                if (t->is_large_file) {
                    *(t->meta_segment_data->buf) = t->tfs_peer->body_buffer;
                    /* reset buf pos to get whole file data */
                    t->meta_segment_data->buf->pos = t->meta_segment_data->buf->start;
                    rc = ngx_http_tfs_get_segment_for_delete(t);
                    if (rc == NGX_ERROR) {
                        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                      "get segment for delete failed");
                        return NGX_ERROR;
                    }
                    t->is_process_meta_seg = NGX_HTTP_TFS_NO;
                    /* later will be alloc */
                    ngx_memzero(&t->tfs_peer->body_buffer, sizeof(ngx_buf_t));
                    t->state = NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA;
                }

            } else {
                t->file.file_offset += segment_data->oper_size;
                segment_data->oper_size = ngx_min(t->file.left_length,
                                               NGX_HTTP_TFS_MAX_READ_FILE_SIZE);
                segment_data->oper_offset = t->file.file_offset;
            }
        }
        break;
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_process_ds_input_filter(ngx_http_tfs_t *t)
{
    int16_t                           msg_type;
    uint32_t                          body_len;
    ngx_int_t                         rc;
    ngx_buf_t                        *b;
    ngx_http_tfs_segment_data_t      *segment_data;
    ngx_http_tfs_peer_connection_t   *tp;
    ngx_http_tfs_ds_read_response_t  *resp;

    resp = (ngx_http_tfs_ds_read_response_t *) t->header;
    msg_type = resp->header.type;
    if (msg_type == NGX_HTTP_TFS_STATUS_MESSAGE) {
        t->length = resp->header.len - sizeof(uint32_t);
        return NGX_OK;
    }

    segment_data = &t->file.segment_data[t->file.segment_index];
    tp = t->tfs_peer;
    b = &tp->body_buffer;

    if (resp->data_len < 0) {
        if (resp->data_len == NGX_HTTP_TFS_EXIT_NO_LOGICBLOCK_ERROR) {
            ngx_http_tfs_remove_block_cache(t, segment_data);

        } else if (resp->data_len == -22) {
            /* for compatibility,
             * old dataserver will return this instead of -1007
             */
            resp->data_len = NGX_HTTP_TFS_EXIT_INVALID_ARGU_ERROR;
        }

        /* must be bad request, do not retry */
        if (resp->data_len == NGX_HTTP_TFS_EXIT_READ_OFFSET_ERROR
            || resp->data_len == NGX_HTTP_TFS_EXIT_INVALID_ARGU_ERROR
            || resp->data_len == NGX_HTTP_TFS_EXIT_PHYSIC_BLOCK_OFFSET_ERROR)
        {
            return resp->data_len;
        }
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "read file(block id: %uD, file id: %uL) "
                      "from (%s) fail, error code: %D, will retry",
                      segment_data->segment_info.block_id,
                      segment_data->segment_info.file_id,
                      tp->peer_addr_text, resp->data_len);
        ngx_http_tfs_clear_buf(b);
        return NGX_HTTP_TFS_AGAIN;
    }

    if (resp->data_len == 0) {
        t->state = NGX_HTTP_TFS_STATE_READ_DONE;
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, t->log, 0, "read len is 0");
        return NGX_DONE;
    }

    if (resp->data_len >= NGX_HTTP_TFS_IMAGE_TYPE_SIZE) {
        /* we need to check small file or large file's first data segment */
        /* or custom file's first segment */
        if (((t->parent == NULL && !t->is_process_meta_seg)
             || (t->parent && t->sp_curr == 0))
            && t->headers_in.content_type == NULL)
        {
            if (ngx_buf_size(b) < NGX_HTTP_TFS_IMAGE_TYPE_SIZE) {
                return NGX_AGAIN;
            }

            t->headers_in.content_type = ngx_pcalloc(t->pool, sizeof(ngx_table_elt_t));
            if (t->headers_in.content_type == NULL) {
                return NGX_ERROR;
            }

            rc = ngx_http_tfs_get_content_type(b->pos, &t->headers_in.content_type->value);
            if (rc != NGX_OK) {
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, t->log, 0, "unknown content type");
            }
        }
    }

    body_len = resp->header.len - sizeof(uint32_t);
    t->length = body_len;
    /* in readv2, body_len = resp->data_len + 40 */
    segment_data->oper_size = resp->data_len;
    /* sub process only read once */
    if (t->parent) {
        t->file.left_length = resp->data_len;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                   "read len is %O, data len is %D",
                   t->length, resp->data_len);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_process_ms_input_filter(ngx_http_tfs_t *t)
{
    ngx_http_tfs_header_t  *header;

    header = (ngx_http_tfs_header_t *) t->header;
    t->length = header->len;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, t->log, 0,
                   "ls dir len is %O",
                   t->length);

    return NGX_OK;
}


