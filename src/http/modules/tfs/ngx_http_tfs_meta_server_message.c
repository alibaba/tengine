
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_meta_server_message.h>
#include <ngx_http_tfs_json.h>
#include <ngx_http_tfs_protocol.h>
#include <ngx_http_tfs_errno.h>
#include <ngx_http_tfs_duplicate.h>


static ngx_chain_t *ngx_http_tfs_create_write_meta_message(ngx_http_tfs_t *t);
static ngx_chain_t *ngx_http_tfs_create_read_meta_message(ngx_http_tfs_t *t,
    int64_t req_offset, uint64_t req_size);
static ngx_chain_t *ngx_http_tfs_create_action_message(ngx_http_tfs_t *t,
    ngx_str_t *file_path_s, ngx_str_t *file_path_d);
static ngx_chain_t *ngx_http_tfs_create_ls_message(ngx_http_tfs_t *t);

static ngx_int_t ngx_http_tfs_parse_write_meta_message(ngx_http_tfs_t *t);
static ngx_int_t ngx_http_tfs_parse_read_meta_message(ngx_http_tfs_t *t);
static ngx_int_t ngx_http_tfs_parse_action_message(ngx_http_tfs_t *t);
static ngx_int_t ngx_http_tfs_parse_ls_message(ngx_http_tfs_t *t);


ngx_http_tfs_inet_t *
ngx_http_tfs_select_meta_server(ngx_http_tfs_t *t)
{
    uint32_t                hash, index;
    ngx_http_tfs_meta_hh_t  h;

    h.app_id = ngx_hton64(t->r_ctx.app_id);
    h.user_id = ngx_hton64(t->r_ctx.user_id);

    hash = ngx_http_tfs_murmur_hash((u_char *) &h,
                                    sizeof(ngx_http_tfs_meta_hh_t));

    index = hash % NGX_HTTP_TFS_METASERVER_COUNT;

    return &(t->loc_conf->meta_server_table.table[index]);
}


ngx_chain_t *
ngx_http_tfs_meta_server_create_message(ngx_http_tfs_t *t)
{
    uint16_t      msg_type;
    ngx_chain_t  *cl;

    cl = NULL;
    msg_type = t->r_ctx.action.code;

    switch (msg_type) {

    case NGX_HTTP_TFS_ACTION_CREATE_DIR:
    case NGX_HTTP_TFS_ACTION_CREATE_FILE:
        ngx_log_error(NGX_LOG_DEBUG, t->log, 0,
                      "will create path: "
                      "last_dir_level: %i, dir_len: %i, last_file_path: %V",
                      t->last_dir_level,
                      t->last_file_path.len,
                      &t->last_file_path);
        cl = ngx_http_tfs_create_action_message(t, &t->last_file_path, NULL);
        break;

    case NGX_HTTP_TFS_ACTION_MOVE_DIR:
    case NGX_HTTP_TFS_ACTION_MOVE_FILE:
        cl = ngx_http_tfs_create_action_message(t, &t->r_ctx.file_path_s,
                                                &t->last_file_path);
        break;

    case NGX_HTTP_TFS_ACTION_REMOVE_DIR:
        cl = ngx_http_tfs_create_action_message(t, &t->r_ctx.file_path_s, NULL);
        break;

    case NGX_HTTP_TFS_ACTION_READ_FILE:
        cl = ngx_http_tfs_create_read_meta_message(t, t->file.file_offset,
                                                   t->file.left_length);
        break;

    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_MS:
            cl = ngx_http_tfs_create_read_meta_message(t, 0, 0);
            break;
        case NGX_HTTP_TFS_STATE_WRITE_WRITE_MS:
            cl = ngx_http_tfs_create_write_meta_message(t);
            break;
        }
        break;

    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_GET_FRAG_INFO:
            cl = ngx_http_tfs_create_read_meta_message(t, t->file.file_offset,
                                                       t->file.left_length);
            break;
        case NGX_HTTP_TFS_STATE_REMOVE_NOTIFY_MS:
            cl = ngx_http_tfs_create_action_message(t, &t->r_ctx.file_path_s,
                                                    NULL);
            break;
        }
        break;

    case NGX_HTTP_TFS_ACTION_LS_DIR:
    case NGX_HTTP_TFS_ACTION_LS_FILE:
        t->json_output = ngx_http_tfs_json_init(t->log, t->pool);
        if (t->json_output == NULL) {
            return NULL;
        }
        cl = ngx_http_tfs_create_ls_message(t);
        break;
    }

    return cl;
}


ngx_int_t
ngx_http_tfs_meta_server_parse_message(ngx_http_tfs_t *t)
{
    uint16_t  action;

    action = t->r_ctx.action.code;

    switch (action) {

    case NGX_HTTP_TFS_ACTION_CREATE_DIR:
    case NGX_HTTP_TFS_ACTION_CREATE_FILE:
    case NGX_HTTP_TFS_ACTION_REMOVE_DIR:
    case NGX_HTTP_TFS_ACTION_MOVE_DIR:
    case NGX_HTTP_TFS_ACTION_MOVE_FILE:
        return ngx_http_tfs_parse_action_message(t);

    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_GET_FRAG_INFO:
            return ngx_http_tfs_parse_read_meta_message(t);
        case NGX_HTTP_TFS_STATE_REMOVE_NOTIFY_MS:
            return ngx_http_tfs_parse_action_message(t);
        default:
            return NGX_ERROR;
        }

    case NGX_HTTP_TFS_ACTION_LS_DIR:
    case NGX_HTTP_TFS_ACTION_LS_FILE:
        return ngx_http_tfs_parse_ls_message(t);

    case NGX_HTTP_TFS_ACTION_READ_FILE:
        return ngx_http_tfs_parse_read_meta_message(t);

    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_MS:
            return ngx_http_tfs_parse_read_meta_message(t);

        case NGX_HTTP_TFS_STATE_WRITE_WRITE_MS:
            return ngx_http_tfs_parse_write_meta_message(t);

        default:
            return NGX_ERROR;
        }
    default:
        return NGX_ERROR;
    }

    return NGX_ERROR;
}


static ngx_chain_t *
ngx_http_tfs_create_write_meta_message(ngx_http_tfs_t *t)
{
    u_char                             *p;
    size_t                              size, frag_size;
    ngx_buf_t                          *b;
    ngx_int_t                           need_write_frag_count, i;
    ngx_chain_t                        *cl;
    ngx_http_tfs_restful_ctx_t         *r_ctx;
    ngx_http_tfs_segment_data_t        *segment_data;
    ngx_http_tfs_meta_frag_info_t      *wfi;
    ngx_http_tfs_ms_base_msg_header_t  *req;

    r_ctx = &t->r_ctx;
    need_write_frag_count =
        t->file.segment_index - t->file.last_write_segment_index;
    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0 ,
                   "last_write_segment_index: %uD, segment_index: %uD",
                   t->file.last_write_segment_index, t->file.segment_index);

    frag_size = sizeof(ngx_http_tfs_meta_frag_info_t) +
        sizeof(ngx_http_tfs_meta_frag_meta_info_t) * need_write_frag_count;

    size = sizeof(ngx_http_tfs_ms_base_msg_header_t) +
        r_ctx->file_path_s.len + 1 +
        /* version */
        sizeof(uint64_t) +
        frag_size;

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ms_base_msg_header_t *) b->pos;
    req->header.type = NGX_HTTP_TFS_WRITE_FILEPATH_MESSAGE;
    req->header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.id = ngx_http_tfs_generate_packet_id();
    req->app_id = r_ctx->app_id;
    req->user_id = r_ctx->user_id;
    req->file_len = r_ctx->file_path_s.len + 1;
    p = ngx_cpymem(req->file_path_s, r_ctx->file_path_s.data,
                   r_ctx->file_path_s.len + 1);

    *((uint64_t *)p) = t->loc_conf->meta_server_table.version;

    wfi = (ngx_http_tfs_meta_frag_info_t*)(p + sizeof(uint64_t));
    wfi->cluster_id = t->file.cluster_id;
    wfi->frag_count = need_write_frag_count;
    segment_data = &t->file.segment_data[t->file.last_write_segment_index];
    for (i = 0; i < need_write_frag_count; i++) {
#if (NGX_DEBUG)
        ngx_http_tfs_dump_segment_data(segment_data, t->log);
#endif
        wfi->frag_meta[i].block_id = segment_data->segment_info.block_id;
        wfi->frag_meta[i].file_id = segment_data->segment_info.file_id;
        wfi->frag_meta[i].offset = segment_data->segment_info.offset;
        wfi->frag_meta[i].size = segment_data->segment_info.size;
        segment_data++;
    }
    t->file.last_write_segment_index += need_write_frag_count;

    b->last += size;

    req->header.len = size - sizeof(ngx_http_tfs_header_t);
    req->header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                       (const char *) (&req->header + 1),
                                       size - sizeof(ngx_http_tfs_header_t));

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }

    cl->buf = b;
    cl->next = NULL;

    return cl;
}


static ngx_chain_t *
ngx_http_tfs_create_read_meta_message(ngx_http_tfs_t *t, int64_t req_offset,
    uint64_t req_size)
{
    u_char                             *p;
    size_t                              size, max_frag_count, req_frag_count;
    ngx_buf_t                          *b;
    ngx_chain_t                        *cl;
    ngx_http_tfs_restful_ctx_t         *r_ctx;
    ngx_http_tfs_ms_base_msg_header_t  *req;

    r_ctx = &t->r_ctx;

    size = sizeof(ngx_http_tfs_ms_base_msg_header_t) +
        /* file */
        r_ctx->file_path_s.len +
        /* \0 */
        1 +
        /* version */
        sizeof(uint64_t) +
        /* offset */
        sizeof(uint64_t) +
        /* size */
        sizeof(uint64_t);

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ms_base_msg_header_t *) b->pos;
    req->header.type = NGX_HTTP_TFS_READ_FILEPATH_MESSAGE;
    req->header.len = size - sizeof(ngx_http_tfs_header_t);
    req->header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.id = ngx_http_tfs_generate_packet_id();
    req->app_id = r_ctx->app_id;
    req->user_id = r_ctx->user_id;
    req->file_len = r_ctx->file_path_s.len + 1;
    p = ngx_cpymem(req->file_path_s, r_ctx->file_path_s.data,
                   r_ctx->file_path_s.len + 1);

    *((uint64_t *)p) = t->loc_conf->meta_server_table.version;
    p += sizeof(uint64_t);

    *((uint64_t *) p) = req_offset;
    p += sizeof(uint64_t);

    max_frag_count = (t->main_conf->body_buffer_size
                      - sizeof(ngx_http_tfs_ms_read_response_t))
        / sizeof(ngx_http_tfs_meta_frag_meta_info_t);
    req_frag_count = req_size / (NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);

    ngx_log_error(NGX_LOG_INFO, t->log, 0 ,
                  "max_frag_count: %uz, req_frag_count: %uz, data size: %uz",
                  max_frag_count, req_frag_count, req_size);

    if (req_frag_count > max_frag_count) {
        *((uint64_t *) p) =
            (max_frag_count - 1) * NGX_HTTP_TFS_MAX_FRAGMENT_SIZE;
        t->has_split_frag = NGX_HTTP_TFS_YES;

    } else {
        *((uint64_t *) p) = req_size;
        t->has_split_frag = NGX_HTTP_TFS_NO;
    }

    req->header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                       (const char *) (&req->header + 1),
                                       req->header.len);

    b->last += size;

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }

    cl->buf = b;
    cl->next = NULL;

    return cl;
}


static ngx_chain_t *
ngx_http_tfs_create_action_message(ngx_http_tfs_t *t, ngx_str_t *file_path_s,
    ngx_str_t *file_path_d)
{
    size_t                              size;
    u_char                             *p;
    ngx_buf_t                          *b;
    ngx_chain_t                        *cl;
    ngx_http_tfs_restful_ctx_t         *r_ctx;
    ngx_http_tfs_ms_base_msg_header_t  *req;

    r_ctx = &t->r_ctx;

    size = sizeof(ngx_http_tfs_ms_base_msg_header_t) +
        /* file path */
        file_path_s->len +
        /* version */
        sizeof(uint64_t) +
        /* new file path len */
        sizeof(uint32_t) +
        /* '/0' */
        1 +
        /* action */
        sizeof(uint8_t);

    if (file_path_d != NULL && file_path_d->data != NULL) {
        size += file_path_d->len + 1;
    }

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ms_base_msg_header_t *) b->pos;
    req->header.type = NGX_HTTP_TFS_FILEPATH_ACTION_MESSAGE;
    req->header.len = size - sizeof(ngx_http_tfs_header_t);
    req->header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.id = ngx_http_tfs_generate_packet_id();
    req->app_id = r_ctx->app_id;
    req->user_id = r_ctx->user_id;
    req->file_len = file_path_s->len + 1;
    p = ngx_cpymem(req->file_path_s, file_path_s->data, file_path_s->len + 1);

    *((uint64_t *)p) = t->loc_conf->meta_server_table.version;
    p += sizeof(uint64_t);

    if (file_path_d != NULL && file_path_d->data != NULL) {
        /* new file path */
        *((uint32_t *)p) = file_path_d->len + 1;
        p += sizeof(uint32_t);
        p = ngx_cpymem(p, file_path_d->data, file_path_d->len + 1);

    } else {
        *((uint32_t *)p) = 0;
        p += sizeof(uint32_t);
    }

    /* start body */
    *p = r_ctx->action.code;

    req->header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                       (const char *) (&req->header + 1),
                                       req->header.len);
    b->last += size;

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }

    cl->buf = b;
    cl->next = NULL;

    return cl;
}


static ngx_chain_t *
ngx_http_tfs_create_ls_message(ngx_http_tfs_t *t)
{
    size_t                            size;
    u_char                           *p;
    ngx_buf_t                        *b;
    ngx_chain_t                      *cl;
    ngx_http_tfs_restful_ctx_t       *r_ctx;
    ngx_http_tfs_ms_ls_msg_header_t  *req;

    r_ctx = &t->r_ctx;

    size = sizeof(ngx_http_tfs_ms_ls_msg_header_t) +
        /* file path */
        t->last_file_path.len +
        /* '/0' */
        1 +
        /* file type */
        sizeof(uint8_t) +
        /* version */
        sizeof(uint64_t);

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ms_ls_msg_header_t *) b->pos;
    req->header.type = NGX_HTTP_TFS_LS_FILEPATH_MESSAGE;
    req->header.len = size - sizeof(ngx_http_tfs_header_t);
    req->header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.id = ngx_http_tfs_generate_packet_id();
    req->app_id = r_ctx->app_id;
    req->user_id = r_ctx->user_id;
    req->file_len = t->last_file_path.len + 1;
    req->pid = t->last_file_pid;
    p = ngx_cpymem(req->file_path, t->last_file_path.data,
                   t->last_file_path.len + 1);

    *p = t->last_file_type;
    p += sizeof(uint8_t);

    *((uint64_t *)p) = t->loc_conf->meta_server_table.version;

    req->header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                       (const char *) (&req->header + 1),
                                       req->header.len);
    b->last += size;

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }

    cl->buf = b;
    cl->next = NULL;

    return cl;
}


static ngx_int_t
ngx_http_tfs_parse_write_meta_message(ngx_http_tfs_t *t)
{
    uint16_t                        type;
    ngx_str_t                       action;
    ngx_http_tfs_header_t           *header;
    ngx_http_tfs_peer_connection_t  *tp;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    type = header->type;

    switch (type) {

    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&action, "write message (meta server)");
        return ngx_http_tfs_status_message(&tp->body_buffer, &action, t->log);
    default:
        ngx_log_error(NGX_LOG_WARN, t->log, 0,
                      " file type is %d ", type);
        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_parse_read_meta_message(ngx_http_tfs_t *t)
{
    u_char                              *p;
    int64_t                              curr_length;
    uint16_t                             type;
    uint32_t                             count;
    uint64_t                             end_offset;
    ngx_int_t                            rc;
    ngx_str_t                            action;
    ngx_uint_t                           i;
    ngx_http_tfs_header_t               *header;
    ngx_http_tfs_segment_data_t         *first_segment, *last_segment,
                                        *segment_data;
    ngx_http_tfs_file_hole_info_t       *file_hole_info;
    ngx_http_tfs_peer_connection_t      *tp;
    ngx_http_tfs_ms_read_response_t     *resp;
    ngx_http_tfs_meta_frag_meta_info_t  *fmi;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    type = header->type;

    switch (type) {
    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&action, "read file(meta server)");
        return ngx_http_tfs_status_message(&tp->body_buffer, &action, t->log);
    }

    resp = (ngx_http_tfs_ms_read_response_t *) tp->body_buffer.pos;

    count = resp->frag_info.frag_count & ~(1 << (sizeof(uint32_t) * 8 - 1));

    t->file.cluster_id = resp->frag_info.cluster_id;

    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
        return NGX_OK;
    }

    if (count == 0) {
        return NGX_DECLINED;
    }

    if (t->file.segment_data == NULL) {
        t->file.segment_data =
            ngx_pcalloc(t->pool, sizeof(ngx_http_tfs_segment_data_t) * count);
        if (t->file.segment_data == NULL) {
            return NGX_ERROR;
        }
        /* the first semgent offset is special for pread */
        t->is_first_segment = NGX_HTTP_TFS_YES;

    } else {
        /* need realloc */
        if (count > t->file.segment_count) {
            t->file.segment_data = ngx_http_tfs_prealloc(t->pool,
                          t->file.segment_data,
                          sizeof(ngx_http_tfs_segment_data_t)
                           * t->file.segment_count,
                          sizeof(ngx_http_tfs_segment_data_t) * count);
            if (t->file.segment_data == NULL) {
                return NGX_ERROR;
            }
        }
        /* reuse */
        ngx_memzero(t->file.segment_data,
                    sizeof(ngx_http_tfs_segment_data_t) * count);
    }

    t->file.segment_count = count;
    t->file.still_have = resp->still_have ? :t->has_split_frag;
    t->file.segment_index = 0;

    p = tp->body_buffer.pos + sizeof(ngx_http_tfs_ms_read_response_t);
    fmi = (ngx_http_tfs_meta_frag_meta_info_t *) p;

    for (i = 0; i < count; i++, fmi++) {
        t->file.segment_data[i].segment_info.block_id = fmi->block_id;
        t->file.segment_data[i].segment_info.file_id = fmi->file_id;
        t->file.segment_data[i].segment_info.offset = fmi->offset;
        t->file.segment_data[i].segment_info.size = fmi->size;
        t->file.segment_data[i].oper_size = fmi->size;
    }

    /* the first semgent's oper_offset and oper_size are special for pread */
    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE) {
        first_segment = &t->file.segment_data[0];
        if (t->is_first_segment) {
            /* skip file hole */
            first_segment->oper_offset =
                ngx_max(t->r_ctx.offset, first_segment->segment_info.offset);
            if (first_segment->segment_info.offset > 0) {
                first_segment->oper_offset %=first_segment->segment_info.offset;
            }
            first_segment->oper_size =
                first_segment->segment_info.size - first_segment->oper_offset;
            t->is_first_segment = NGX_HTTP_TFS_NO;
            if (t->r_ctx.chk_file_hole) {
                rc = ngx_array_init(&t->file_holes, t->pool,
                                    NGX_HTTP_TFS_INIT_FILE_HOLE_COUNT,
                                    sizeof(ngx_http_tfs_file_hole_info_t));
                if (rc == NGX_ERROR) {
                    return NGX_ERROR;
                }
            }
        }

        /* last segment(also special) has been readed, set its oper_size*/
        /* notice that it maybe the same as first_segment */
        if (!t->file.still_have) {
            last_segment = &t->file.segment_data[count - 1];
            end_offset = t->file.file_offset + t->file.left_length;
            if (end_offset
                > ((uint64_t)last_segment->segment_info.offset
                   + last_segment->oper_offset))
            {
                last_segment->oper_size =
                    ngx_min((end_offset - (last_segment->segment_info.offset
                                           + last_segment->oper_offset)),
                            last_segment->segment_info.size);

            } else { /* end_offset in file hole */
                last_segment->oper_size = 0;
            }
        }

        /* check file hole */
        if (t->r_ctx.chk_file_hole) {
            segment_data = t->file.segment_data;
            for (i = 0; i < count; i++, segment_data++) {
                /* must be file hole, add to array */
                if (t->file.file_offset < segment_data->segment_info.offset) {
                    curr_length =
                        ngx_min(t->file.left_length,
                                (uint64_t)(segment_data->segment_info.offset
                                           - t->file.file_offset));
                    file_hole_info = ngx_array_push(&t->file_holes);
                    if (file_hole_info == NULL) {
                        return NGX_ERROR;
                    }

                    file_hole_info->offset = t->file.file_offset;
                    file_hole_info->length = curr_length;

                    ngx_log_error(NGX_LOG_DEBUG, t->log, 0,
                                  "find file hole, offset: %uL, length: %uL",
                                  file_hole_info->offset,
                                  file_hole_info->length);

                    t->file.file_offset += curr_length;
                    t->file.left_length -= curr_length;
                    if (t->file.left_length == 0) {
                        return NGX_DECLINED;
                    }
                }
                t->file.file_offset += segment_data->oper_size;
                t->file.left_length -= segment_data->oper_size;
                if (t->file.left_length == 0) {
                    return NGX_DECLINED;
                }
            }
            return NGX_OK;
        }
    }

#if (NGX_DEBUG)
    for (i = 0; i < count; i++) {
        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "segment index: %d, oper_offset: %uD, oper_size: %uD",
                       i, t->file.segment_data[i].oper_offset,
                       t->file.segment_data[i].oper_size);
    }
#endif

    ngx_log_error(NGX_LOG_DEBUG, t->log, 0,
                  "still_have is %d, frag count is %d",
                  t->file.still_have, count);

    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_parse_action_message(ngx_http_tfs_t *t)
{
    uint16_t                         type;
    ngx_str_t                        action;
    ngx_http_tfs_header_t           *header;
    ngx_http_tfs_peer_connection_t  *tp;

    tp = t->tfs_peer;
    header = (ngx_http_tfs_header_t *) t->header;
    type = header->type;

    switch (type) {

    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&action, "action (meta server)");
        return ngx_http_tfs_status_message(&tp->body_buffer, &action, t->log);
    default:
        break;
    }

    return NGX_ERROR;
}


static ngx_int_t
ngx_http_tfs_parse_ls_message(ngx_http_tfs_t *t)
{
    u_char                           *p;
    uint16_t                          type;
    uint32_t                          count, i;
    ngx_buf_t                        *b;
    ngx_str_t                         action;
    ngx_http_tfs_header_t            *header;
    ngx_http_tfs_custom_file_t       *file;
    ngx_http_tfs_ms_ls_response_t    *resp;
    ngx_http_tfs_peer_connection_t   *tp;
    ngx_http_tfs_custom_meta_info_t  *meta_info, **new_meta_info;

    tp = t->tfs_peer;
    header = (ngx_http_tfs_header_t *) t->header;

    type = header->type;

    switch (type) {
    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&action, "ls file(meta server)");
        return ngx_http_tfs_status_message(&tp->body_buffer, &action, t->log);
    }

    b = &tp->body_buffer;
    resp = (ngx_http_tfs_ms_ls_response_t *) b->pos;
    count = resp->count;

    t->file.still_have = resp->still_have;
    t->length -= ngx_buf_size(b);

    if (count == 0) {
        if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_LS_FILE) {
            ngx_log_error(NGX_LOG_DEBUG, t->log, 0, "file(%V) not exist",
                          &t->r_ctx.file_path_s);
            return NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR;
        } else {
            return NGX_OK;
        }
    }

    meta_info = &t->meta_info;
    if (meta_info->files == NULL) {
        meta_info->files = ngx_pcalloc(t->pool,
                                    sizeof(ngx_http_tfs_custom_file_t) * count);
        if (meta_info->files == NULL) {
            return NGX_ERROR;
        }
        meta_info->file_count = count;
        meta_info->file_index = 0;

    } else {
        for(; meta_info->next; meta_info = meta_info->next);

        if (meta_info->file_index == meta_info->file_count) {
            new_meta_info = &meta_info->next;
            meta_info = ngx_pcalloc(t->pool,
                                    sizeof(ngx_http_tfs_custom_meta_info_t));
            if (meta_info == NULL) {
                return NGX_ERROR;
            }
            meta_info->files =
                ngx_pcalloc(t->pool,sizeof(ngx_http_tfs_custom_file_t) * count);
            if (meta_info->files == NULL) {
                return NGX_ERROR;
            }
            meta_info->file_count = count;

            *new_meta_info = meta_info;
        }
    }

    file = meta_info->files;

    p = b->pos + sizeof(ngx_http_tfs_ms_ls_response_t);

    for (i = meta_info->file_index;
         i < meta_info->file_count && p < (b->last - sizeof(uint32_t));
         i++)
    {
        file[i].file_name.len = *((uint32_t *) p); /* include '\0'*/
        p += sizeof(uint32_t);
        if (p + file[i].file_name.len >= b->last) {
            p -= sizeof(uint32_t);
            break;
        }
        if (file[i].file_name.len > 0) {
            file[i].file_name.data = ngx_pcalloc(t->pool,
                                                 file[i].file_name.len - 1);
            ngx_memcpy(file[i].file_name.data, p, file[i].file_name.len - 1);
            p += file[i].file_name.len;

            file[i].file_name.len -= 1; /* exclude '\0'*/
        }
        if (p + sizeof(ngx_http_tfs_custom_file_info_t) >= b->last) {
            p -= file[i].file_name.len + 1 + sizeof(uint32_t);
            break;
        }
        ngx_memcpy(&file[i].file_info, p,
                   sizeof(ngx_http_tfs_custom_file_info_t));
        p += sizeof(ngx_http_tfs_custom_file_info_t);
    }

    b->pos = p;
    meta_info->file_index = i;
    meta_info->rest_file_count = meta_info->file_count - meta_info->file_index;

    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_LS_FILE) {
        file[0].file_name = t->r_ctx.file_path_s;

    } else if (resp->still_have && t->length == 0) {
        t->last_file_path = file[meta_info->file_count - 1].file_name;
        t->last_file_pid = file[meta_info->file_count - 1].file_info.pid;
        t->last_file_type = (((t->last_file_pid >> 63) & 0x01) == 0x01) ?
            NGX_HTTP_TFS_CUSTOM_FT_FILE : NGX_HTTP_TFS_CUSTOM_FT_DIR;
        ngx_log_error(NGX_LOG_DEBUG, t->log, 0, "ls last file path: %V",
                      &t->last_file_path);
    }

    return NGX_OK;
}
