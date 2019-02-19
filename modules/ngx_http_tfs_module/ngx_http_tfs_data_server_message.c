
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_data_server_message.h>
#include <ngx_http_tfs_json.h>
#include <ngx_http_tfs_protocol.h>
#include <ngx_http_tfs_errno.h>
#include <ngx_http_tfs_duplicate.h>


static ngx_chain_t *ngx_http_tfs_create_createfile_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);
static ngx_chain_t *ngx_http_tfs_create_write_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);
static ngx_chain_t *ngx_http_tfs_create_closefile_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);
static ngx_chain_t *ngx_http_tfs_create_read_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data, uint8_t read_ver,
    uint8_t read_flag);
static ngx_chain_t *ngx_http_tfs_create_unlink_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);
static ngx_chain_t * ngx_http_tfs_create_stat_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);

static ngx_int_t ngx_http_tfs_parse_createfile_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);
static ngx_int_t ngx_http_tfs_parse_write_message(ngx_http_tfs_t *t);
static ngx_int_t ngx_http_tfs_parse_closefile_message(ngx_http_tfs_t *t);
static ngx_int_t ngx_http_tfs_parse_read_message(ngx_http_tfs_t *t);
static ngx_int_t ngx_http_tfs_parse_remove_message(ngx_http_tfs_t *t);
static ngx_int_t ngx_http_tfs_parse_statfile_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);

static int32_t ngx_http_tfs_find_segment(uint32_t seg_count,
    ngx_http_tfs_segment_info_t *seg_info, int64_t offset);
static ngx_int_t ngx_http_tfs_copy_body_buffer(ngx_http_tfs_t *t,
    ssize_t bytes, u_char *body);


ngx_http_tfs_inet_t *
ngx_http_tfs_select_data_server(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    ngx_http_tfs_block_info_t  *block_info;

    block_info = &segment_data->block_info;

    switch(t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_STAT_FILE:
    case NGX_HTTP_TFS_ACTION_READ_FILE:
        if (block_info->ds_count > 0) {
            if (segment_data->ds_retry > 0) {
                segment_data->ds_index %= block_info->ds_count;

            } else {
                segment_data->ds_index = ngx_random() % block_info->ds_count;
            }
        }
        break;

    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        if (t->is_stat_dup_file) {
            if (block_info->ds_count > 0) {
                if (segment_data->ds_retry > 0) {
                    segment_data->ds_index %= block_info->ds_count;

                } else {
                    segment_data->ds_index =ngx_random() % block_info->ds_count;
                }
            }

        } else {
            /* write retry ns */
            if (segment_data->ds_retry > 0) {
                return NULL;
            }
            segment_data->ds_index = 0;
        }
        break;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                   "select data server, ds_retry: %ui, ds_index: %ui",
                   segment_data->ds_retry, segment_data->ds_index);

    if (segment_data->ds_retry++ >= block_info->ds_count) {
        return NULL;
    }

    return &block_info->ds_addrs[segment_data->ds_index++];
}


ngx_chain_t *
ngx_http_tfs_data_server_create_message(ngx_http_tfs_t *t)
{
    uint32_t                      meta_segment_size;
    uint16_t                      action;
    ngx_int_t                     rc;
    ngx_chain_t                  *cl;
    ngx_http_tfs_segment_data_t  *segment_data;

    cl = NULL;
    meta_segment_size = 0;
    action = t->r_ctx.action.code;
    segment_data = &t->file.segment_data[t->file.segment_index];

    switch (action) {
    case NGX_HTTP_TFS_ACTION_STAT_FILE:
        if (t->r_ctx.chk_exist == NGX_HTTP_TFS_NO) {
            t->json_output = ngx_http_tfs_json_init(t->log, t->pool);
            if (t->json_output == NULL) {
                return NULL;
            }
        }
        if (t->is_large_file) {
            segment_data->oper_size = sizeof(ngx_http_tfs_segment_head_t);
            return ngx_http_tfs_create_read_message(t, segment_data,
                            NGX_HTTP_TFS_READ_V2, NGX_HTTP_TFS_READ_STAT_FORCE);
        }

        return ngx_http_tfs_create_stat_message(t, segment_data);

    case NGX_HTTP_TFS_ACTION_READ_FILE:
        t->read_ver = NGX_HTTP_TFS_READ;
        t->header_size = sizeof(ngx_http_tfs_ds_read_response_t);
        /* large file need read meta segment first */
        if (t->is_large_file && t->is_process_meta_seg) {
            if (t->meta_segment_data == NULL) {
                /* for files smaller than 140GB, 2MB is fairly enough */
                cl = ngx_http_tfs_chain_get_free_buf(t->pool, &t->free_bufs,
                    NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);
                if (cl == NULL) {
                    return NULL;
                }
                t->tfs_peer->body_buffer = *(cl->buf);
                t->meta_segment_data = cl;
            }
        }

        /* use readv2 if read from start */
        /* unless is large file data segment */
        if (t->r_ctx.version == 1
            && t->file.file_offset == 0
            && !t->parent)
        {
            t->read_ver = NGX_HTTP_TFS_READ_V2;
        }
        /* custom file need fill file hole */
        if (t->r_ctx.version == 2 && t->file.file_hole_size > 0) {
            rc = ngx_http_tfs_fill_file_hole(t, t->file.file_hole_size);
            if (rc == NGX_ERROR) {
                return NULL;
            }
            t->stat_info.size += t->file.file_hole_size;
            t->file.file_hole_size = 0;
        }
        return ngx_http_tfs_create_read_message(t, segment_data,
                                                t->read_ver,
                                                t->r_ctx.read_stat_type);
    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_STAT_DUP_FILE:
            return ngx_http_tfs_create_stat_message(t, segment_data);
        case NGX_HTTP_TFS_STATE_WRITE_CREATE_FILE_NAME:
            return ngx_http_tfs_create_createfile_message(t, segment_data);
        case NGX_HTTP_TFS_STATE_WRITE_WRITE_DATA:
            return ngx_http_tfs_create_write_message(t, segment_data);
        case NGX_HTTP_TFS_STATE_WRITE_CLOSE_FILE:
            return ngx_http_tfs_create_closefile_message(t, segment_data);
        case NGX_HTTP_TFS_STATE_WRITE_DELETE_DATA:
            return ngx_http_tfs_create_unlink_message(t, segment_data);
        default:
            return NULL;
        }

    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_STAT_FILE:
            return ngx_http_tfs_create_stat_message(t, segment_data);

        case NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT:
            t->read_ver = NGX_HTTP_TFS_READ;
            if (t->meta_segment_data == NULL) {
                if (t->use_dedup) {
                    meta_segment_size = t->file_stat.size;
                    t->file.left_length = t->file_stat.size;
                }
                /* if is large file, for files smaller than 140GB,
                 * 2MB is fairly enough
                 */
                if (t->is_large_file) {
                    meta_segment_size = NGX_HTTP_TFS_MAX_FRAGMENT_SIZE;
                    t->file.left_length = NGX_HTTP_TFS_MAX_SIZE;
                }
                cl = ngx_http_tfs_chain_get_free_buf(t->pool, &t->free_bufs,
                    meta_segment_size);
                if (cl == NULL) {
                    return NULL;
                }
                t->meta_segment_data = cl;

                /* avoid alloc body_buffer twice */
                if (!t->is_large_file && t->use_dedup) {
                    t->dedup_ctx.save_body_buffer = t->tfs_peer->body_buffer;
                }

                t->tfs_peer->body_buffer = *(cl->buf);
            }
            t->header_size = sizeof(ngx_http_tfs_ds_read_response_t);

            /* use readv2 to get file size if we do not know that */
            if (t->file.left_length == NGX_HTTP_TFS_MAX_SIZE) {
                t->read_ver = NGX_HTTP_TFS_READ_V2;
            }
            return ngx_http_tfs_create_read_message(t, segment_data,
                                     t->read_ver, NGX_HTTP_TFS_READ_STAT_FORCE);
        case NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA:
            return ngx_http_tfs_create_unlink_message(t, segment_data);

        default:
            return NULL;
        }
    }

    return cl;
}


ngx_int_t
ngx_http_tfs_data_server_parse_message(ngx_http_tfs_t *t)
{
    ngx_http_tfs_segment_data_t  *segment_data;

    segment_data = &t->file.segment_data[t->file.segment_index];

    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_READ_FILE:
        return ngx_http_tfs_parse_read_message(t);

    case NGX_HTTP_TFS_ACTION_STAT_FILE:
        return ngx_http_tfs_parse_statfile_message(t, segment_data);

    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_STAT_DUP_FILE:
            return ngx_http_tfs_parse_statfile_message(t, segment_data);
        case NGX_HTTP_TFS_STATE_WRITE_CREATE_FILE_NAME:
            return ngx_http_tfs_parse_createfile_message(t, segment_data);
        case NGX_HTTP_TFS_STATE_WRITE_WRITE_DATA:
            return ngx_http_tfs_parse_write_message(t);
        case NGX_HTTP_TFS_STATE_WRITE_CLOSE_FILE:
            return ngx_http_tfs_parse_closefile_message(t);
        case NGX_HTTP_TFS_STATE_WRITE_DELETE_DATA:
            return ngx_http_tfs_parse_remove_message(t);
        default:
            return NGX_ERROR;
        }

    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch(t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_STAT_FILE:
            return ngx_http_tfs_parse_statfile_message(t, segment_data);
        case NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT:
            return ngx_http_tfs_parse_read_message(t);
        case NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA:
            return ngx_http_tfs_parse_remove_message(t);
        default:
            return NGX_ERROR;
        }
    }

    return NGX_ERROR;
}


static ngx_chain_t *
ngx_http_tfs_create_createfile_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    size_t                         size;
    ngx_buf_t                     *b;
    ngx_chain_t                   *cl;
    ngx_http_tfs_ds_msg_header_t  *req;

    size = sizeof(ngx_http_tfs_ds_msg_header_t);

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ds_msg_header_t *) b->pos;

    req->base_header.type = NGX_HTTP_TFS_CREATE_FILENAME_MESSAGE;
    req->base_header.len = size - sizeof(ngx_http_tfs_header_t);
    req->base_header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->base_header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->base_header.id = ngx_http_tfs_generate_packet_id();
    req->block_id = segment_data->segment_info.block_id;
    req->file_id = segment_data->segment_info.file_id;

    req->base_header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                         (const char *) (&req->base_header + 1),
                                         req->base_header.len);

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
ngx_http_tfs_create_write_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    u_char                           *p, exit;
    size_t                            size, body_size, b_size;
    uint32_t                          crc;
    ngx_int_t                         rc;
    ngx_buf_t                        *b;
    ngx_uint_t                        i;
    ngx_chain_t                      *cl, *body, *ch;
    ngx_http_tfs_crc_t                t_crc;
    ngx_http_tfs_block_info_t        *block_info;
    ngx_http_tfs_ds_write_request_t  *req;

    exit = 0;

    block_info = &segment_data->block_info;
    size = sizeof(ngx_http_tfs_ds_write_request_t) +
        /* ds count */
        sizeof(uint32_t) +
        /* ds list */
        block_info->ds_count * sizeof(uint64_t) +
        /* flag verion lease_id */
        sizeof(uint64_t) * 3 ;

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ds_write_request_t *) b->pos;

    req->header.base_header.type = NGX_HTTP_TFS_WRITE_DATA_MESSAGE;
    req->header.base_header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.base_header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.base_header.id = ngx_http_tfs_generate_packet_id();
    req->header.block_id = segment_data->segment_info.block_id;
    req->header.file_id = segment_data->segment_info.file_id;
    req->offset = segment_data->oper_offset;
    req->is_server = 0;
    req->file_number = segment_data->write_file_number;

    p = b->pos + sizeof(ngx_http_tfs_ds_write_request_t);

    /* ds count */
    *((uint32_t *) p) = 3 + block_info->ds_count;
    p += sizeof(uint32_t);
    /* ds list */
    for (i = 0; i < block_info->ds_count; i++) {
        *((uint64_t *) p) = *((uint64_t *)&block_info->ds_addrs[i]);
        p += sizeof(uint64_t);
    }

    /* flag, useless */
    *((uint64_t *) p) = -1;
    p += sizeof(uint64_t);
    /* version */
    *((uint64_t *) p) = block_info->version;
    p += sizeof(uint64_t);
    /* lease id */
    *((uint64_t *) p) = block_info->lease_id;
    b->last += size;

    req->length = segment_data->oper_size;

    crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                           (const char *) (&req->header.base_header + 1),
                           (size - sizeof(ngx_http_tfs_header_t)));

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }
    ch = cl;
    cl->buf = b;

    body_size = 0;
    body = segment_data->data;

    t_crc.crc = crc;
    t_crc.data_crc = segment_data->segment_info.crc;

    /* body buf is one or two bufs,
     * please see ngx_http_read_client_request_body
     */
    while (body) {
        b_size = ngx_buf_size(body->buf);
        body_size += b_size;

        b = ngx_alloc_buf(t->pool);
        if (b == NULL) {
            return NULL;
        }

        ngx_memcpy(b, body->buf, sizeof(ngx_buf_t));

        if (body_size > NGX_HTTP_TFS_MAX_FRAGMENT_SIZE) {
            /* need more writes*/
            body_size -= b_size;
            b_size = NGX_HTTP_TFS_MAX_FRAGMENT_SIZE - body_size;
            body_size = NGX_HTTP_TFS_MAX_FRAGMENT_SIZE;
            exit = 1;
        }

        rc = ngx_http_tfs_compute_buf_crc(&t_crc, b, b_size, t->log);
        if (rc == NGX_ERROR) {
            return NULL;
        }

        cl->next = ngx_alloc_chain_link(t->pool);
        if (cl->next == NULL) {
            return NULL;
        }

        cl = cl->next;
        cl->buf = b;

        if (exit) {
            break;
        }

        body = body->next;
    }
    cl->next = NULL;

    ngx_log_error(NGX_LOG_INFO, t->log, 0,
                  "write segment index %uD, block id: %uD, file id: %uL, "
                  "offset: %D, length: %uD, crc: %uD",
                  t->file.segment_index, segment_data->segment_info.block_id,
                  segment_data->segment_info.file_id, req->offset,
                  req->length, t_crc.data_crc);

    segment_data->segment_info.crc = t_crc.data_crc;
    req->header.base_header.len = size - sizeof(ngx_http_tfs_header_t)
                                   + req->length;
    req->header.base_header.crc = t_crc.crc;

    return ch;
}


static ngx_chain_t *
ngx_http_tfs_create_closefile_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    u_char                           *p;
    size_t                            size;
    ngx_buf_t                        *b;
    ngx_uint_t                        i;
    ngx_chain_t                      *cl;
    ngx_http_tfs_block_info_t        *block_info;
    ngx_http_tfs_ds_close_request_t  *req;

    block_info = &segment_data->block_info;
    size = sizeof(ngx_http_tfs_ds_close_request_t) +
        /* ds count */
        sizeof(uint32_t) +
        /* ds list */
        block_info->ds_count * sizeof(uint64_t) +
        /* flag verion lease_id */
        sizeof(uint64_t) * 3 +
        /* size and file size */
        sizeof(uint32_t) * 2 +
        /* option flag */
        sizeof(uint32_t);

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ds_close_request_t *) b->pos;

    req->header.base_header.type = NGX_HTTP_TFS_CLOSE_FILE_MESSAGE;
    req->header.base_header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.base_header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.base_header.id = ngx_http_tfs_generate_packet_id();
    req->header.base_header.len = size - sizeof(ngx_http_tfs_header_t);
    req->header.block_id = segment_data->segment_info.block_id;
    req->header.file_id = segment_data->segment_info.file_id;
    req->mode = NGX_HTTP_TFS_CLOSE_FILE_MASTER;
    req->crc = segment_data->segment_info.crc;
    req->file_number = segment_data->write_file_number;

    p = b->pos + sizeof(ngx_http_tfs_ds_close_request_t);

    /* ds count */
    *((uint32_t *) p) = 3 + block_info->ds_count;
    p += sizeof(uint32_t);
    /* ds list */
    for (i = 0; i < block_info->ds_count; i++) {
        *((uint64_t *) p) = *((uint64_t *)&block_info->ds_addrs[i]);
        p += sizeof(uint64_t);
    }

    /* flag, useless */
    *((uint64_t *) p) = -1;
    p += sizeof(uint64_t);
    /* version */
    *((uint64_t *) p) = block_info->version;
    p += sizeof(uint64_t);
    /* lease id */
    *((uint64_t *) p) = block_info->lease_id;
    p += sizeof(uint64_t);

    /* block size, useless */
    *((uint32_t *) p) = 0;
    p += sizeof(uint32_t);
    /* file size, useless */
    *((uint32_t *) p) = 0;
    p += sizeof(uint32_t);

    *((uint32_t *) p) = NGX_HTTP_TFS_FILE_DEFAULT_OPTION;

    req->header.base_header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                  (const char *) (&req->header.base_header + 1),
                                  (size - sizeof(ngx_http_tfs_header_t)));

    b->last += size;

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }
    cl->next = NULL;
    cl->buf = b;
    return cl;
}


static ngx_chain_t *
ngx_http_tfs_create_read_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data, uint8_t read_ver,
    uint8_t read_flag)
{
    size_t                           size;
    ngx_buf_t                       *b;
    ngx_chain_t                     *cl;
    ngx_http_tfs_ds_read_request_t  *req;

    size = sizeof(ngx_http_tfs_ds_read_request_t);

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ds_read_request_t *) b->pos;

    if (read_ver == NGX_HTTP_TFS_READ) {
        req->header.base_header.type = NGX_HTTP_TFS_READ_DATA_MESSAGE;

    } else if (read_ver == NGX_HTTP_TFS_READ_V2) {
        req->header.base_header.type = NGX_HTTP_TFS_READ_DATA_MESSAGE_V2;
    }
    req->header.base_header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.base_header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.base_header.id = ngx_http_tfs_generate_packet_id();
    req->header.base_header.len = size - sizeof(ngx_http_tfs_header_t);
    req->header.block_id = segment_data->segment_info.block_id;
    req->header.file_id = segment_data->segment_info.file_id;
    req->offset = segment_data->oper_offset;
    req->length = segment_data->oper_size;
    req->flag = read_flag;
    req->header.base_header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                  (const char *) (&req->header.base_header + 1),
                                  (size - sizeof(ngx_http_tfs_header_t)));

    b->last += size;

    ngx_log_error(NGX_LOG_INFO, t->log, 0,
                  "read segment index %uD, block id: %uD, "
                  "file id: %uL, offset: %D, length: %uD",
                  t->file.segment_index,
                  segment_data->segment_info.block_id,
                  segment_data->segment_info.file_id, req->offset,
                  req->length);

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }
    cl->buf = b;
    cl->next = NULL;

    return cl;
}


static ngx_chain_t *
ngx_http_tfs_create_unlink_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    u_char                            *p;
    size_t                             size;
    ngx_buf_t                         *b;
    ngx_uint_t                         i;
    ngx_chain_t                       *cl;
    ngx_http_tfs_block_info_t         *block_info;
    ngx_http_tfs_ds_unlink_request_t  *req;

    block_info = &segment_data->block_info;
    size = sizeof(ngx_http_tfs_ds_unlink_request_t) +
        /* ds count */
        sizeof(uint32_t) +
        /* ds list */
        block_info->ds_count * sizeof(uint64_t) +
        /* flag verion lease_id */
        sizeof(uint64_t) * 3  +
        /* option flag */
        sizeof(uint32_t);

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ds_unlink_request_t *) b->pos;

    req->header.base_header.type = NGX_HTTP_TFS_UNLINK_FILE_MESSAGE;
    req->header.base_header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.base_header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.base_header.id = ngx_http_tfs_generate_packet_id();
    req->header.base_header.len = size - sizeof(ngx_http_tfs_header_t);
    req->header.block_id = segment_data->segment_info.block_id;
    req->header.file_id = segment_data->segment_info.file_id;
    req->server_mode = NGX_HTTP_TFS_REMOVE_FILE_MASTER;
    if (t->r_ctx.version == 1) {
        req->server_mode |= t->r_ctx.unlink_type;

    } else if (t->r_ctx.version == 2) {
        req->server_mode |= NGX_HTTP_TFS_UNLINK_DELETE;
    }

    p = b->pos + sizeof(ngx_http_tfs_ds_unlink_request_t);

    /* ds count */
    *((uint32_t *) p) = 3 + block_info->ds_count;
    p += sizeof(uint32_t);
    /* ds list */
    for (i = 0; i < block_info->ds_count; i++) {
        *((uint64_t *) p) = *((uint64_t *)&block_info->ds_addrs[i]);
        p += sizeof(uint64_t);
    }

    /* flag, useless */
    *((uint64_t *) p) = -1;
    p += sizeof(uint64_t);
    /* version */
    *((uint64_t *) p) = block_info->version;
    p += sizeof(uint64_t);
    /* lease id */
    *((uint64_t *) p) = block_info->lease_id;
    p += sizeof(uint64_t);

    /* option */
    *((uint32_t *) p) = NGX_HTTP_TFS_FILE_DEFAULT_OPTION;

    req->header.base_header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                  (const char *) (&req->header.base_header + 1),
                                  (size - sizeof(ngx_http_tfs_header_t)));

    b->last += size;

    ngx_log_error(NGX_LOG_INFO, t->log, 0,
                  "unlink segment index %uD, block id: %uD, "
                  "file id: %uL, type: %i",
                  t->file.segment_index,
                  segment_data->segment_info.block_id,
                  segment_data->segment_info.file_id, t->r_ctx.unlink_type);

    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NULL;
    }
    cl->next = NULL;
    cl->buf = b;
    return cl;
}


static ngx_chain_t *
ngx_http_tfs_create_stat_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    size_t                           size;
    ngx_buf_t                       *b;
    ngx_chain_t                     *cl;
    ngx_http_tfs_ds_stat_request_t  *req;

    size = sizeof(ngx_http_tfs_ds_stat_request_t);

    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NULL;
    }

    req = (ngx_http_tfs_ds_stat_request_t *) b->pos;

    req->header.base_header.type = NGX_HTTP_TFS_FILE_INFO_MESSAGE;
    req->header.base_header.flag = NGX_HTTP_TFS_PACKET_FLAG;
    req->header.base_header.version = NGX_HTTP_TFS_PACKET_VERSION;
    req->header.base_header.id = ngx_http_tfs_generate_packet_id();
    req->header.base_header.len = size - sizeof(ngx_http_tfs_header_t);
    req->header.block_id = segment_data->segment_info.block_id;
    req->header.file_id = segment_data->segment_info.file_id;
    req->mode = t->r_ctx.read_stat_type;

    req->header.base_header.crc = ngx_http_tfs_crc(NGX_HTTP_TFS_PACKET_FLAG,
                                  (const char *) (&req->header.base_header + 1),
                                  (size - sizeof(ngx_http_tfs_header_t)));

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
ngx_http_tfs_parse_createfile_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    uint16_t                         type;
    ngx_str_t                        action;
    ngx_http_tfs_header_t           *header;
    ngx_http_tfs_ds_cf_reponse_t    *resp;
    ngx_http_tfs_peer_connection_t  *tp;

    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    type = header->type;

    switch (type) {

    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&action, "create file(data server)");
        return ngx_http_tfs_status_message(&tp->body_buffer, &action, t->log);
    }

    resp = (ngx_http_tfs_ds_cf_reponse_t *) tp->body_buffer.pos;

    t->r_ctx.fsname.file.seq_id = resp->file_id;
    ngx_http_tfs_raw_fsname_set_suffix((&t->r_ctx.fsname),
                                       (&t->r_ctx.file_suffix));
    segment_data->segment_info.file_id =
                          ngx_http_tfs_raw_fsname_get_file_id(t->r_ctx.fsname);
    segment_data->write_file_number = resp->file_number;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, t->log, 0,
                   "create file success, seq id: %uD, "
                   "file id: %uL, file number: %uL",
                   t->r_ctx.fsname.file.seq_id,
                   segment_data->segment_info.file_id,
                   segment_data->write_file_number);

    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_parse_write_message(ngx_http_tfs_t *t)
{
    uint16_t                type;
    ngx_str_t               action;
    ngx_http_tfs_header_t  *header;

    header = (ngx_http_tfs_header_t *) t->header;
    type = header->type;

    switch (type) {

    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&action, "write data(data server)");
        return ngx_http_tfs_status_message(&t->tfs_peer->body_buffer, &action,
                                           t->log);
    default:
        ngx_log_error(NGX_LOG_INFO, t->log, 0,
                      "write file(ds) response msg type is invalid %d ", type);
    }

    return NGX_ERROR;
}


static ngx_int_t
ngx_http_tfs_parse_closefile_message(ngx_http_tfs_t *t)
{
    uint16_t                type;
    ngx_str_t               action;
    ngx_http_tfs_header_t  *header;

    header = (ngx_http_tfs_header_t *) t->header;
    type = header->type;

    switch (type) {

    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&action, "close file(data server)");
        return ngx_http_tfs_status_message(&t->tfs_peer->body_buffer, &action,
                                           t->log);

    default:
        ngx_log_error(NGX_LOG_INFO, t->log, 0,
                      "close file response msg type is invalid  %d ", type);
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_parse_read_message(ngx_http_tfs_t *t)
{
    size_t                                   size, left_len, tail_len;
    int32_t                                  code, err_len;
    uint16_t                                 type;
    ngx_int_t                                rc;
    ngx_str_t                                err_msg;
    ngx_buf_t                               *b;
    ngx_http_tfs_peer_connection_t          *tp;
    ngx_http_tfs_ds_read_response_t         *resp;
    ngx_http_tfs_ds_readv2_response_tail_t  *readv2_rsp_tail;

    resp = (ngx_http_tfs_ds_read_response_t *) t->header;
    tp = t->tfs_peer;
    type = resp->header.type;
    b = &tp->body_buffer;

    switch (type) {
    case NGX_HTTP_TFS_STATUS_MESSAGE:
        /* weird status message, err_code is in resp->data_len */
        code = resp->data_len;
        if (code != NGX_HTTP_TFS_STATUS_MESSAGE_OK) {
            err_len = *(uint32_t*) (b->pos);
            if (err_len > 0) {
                err_msg.data = b->pos + sizeof(uint32_t);
                err_msg.len = err_len;
            }

            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                          "read data (data server: %s) failed, "
                          "error code (%d) err_msg(%V)",
                          tp->peer_addr_text, code, &err_msg);
        }

        return NGX_HTTP_TFS_AGAIN;
    }

    size = ngx_buf_size(b);

    /* read v2 */
    if (t->read_ver == NGX_HTTP_TFS_READ_V2) {
        /* recv file_info */
        if (t->length < 0
            || (size_t) t->length <= NGX_HTTP_TFS_READ_V2_TAIL_LEN)
        {
            t->length -= size;
            if (t->length == 0) {
                t->readv2_rsp_tail_buf->last =
                         ngx_cpymem(t->readv2_rsp_tail_buf->last, b->pos, size);
                readv2_rsp_tail = (ngx_http_tfs_ds_readv2_response_tail_t *)
                                   t->readv2_rsp_tail_buf->pos;
                if (readv2_rsp_tail->file_info_len
                    != NGX_HTTP_TFS_RAW_FILE_INFO_SIZE)
                {
                    return NGX_ERROR;
                }
                ngx_http_tfs_wrap_raw_file_info(&readv2_rsp_tail->file_info, &t->file_stat);
                t->file.left_length = ngx_min(t->file.left_length, (uint64_t)t->file_stat.size);
            }
            return NGX_OK;
        }

        /* recv data only or data + file_info */
        left_len = t->length - size;
        if (left_len < NGX_HTTP_TFS_READ_V2_TAIL_LEN) {
            tail_len = NGX_HTTP_TFS_READ_V2_TAIL_LEN - left_len;
            size -= tail_len;
            t->length -= tail_len;
            /* all recvd */
            if (left_len == 0) {
                readv2_rsp_tail = (ngx_http_tfs_ds_readv2_response_tail_t *)
                                   (b->pos + size);
                /* should not happened */
                if (readv2_rsp_tail->file_info_len
                    != NGX_HTTP_TFS_RAW_FILE_INFO_SIZE)
                {
                    return NGX_ERROR;
                }
                ngx_http_tfs_wrap_raw_file_info(&readv2_rsp_tail->file_info, &t->file_stat);
                t->file.left_length = ngx_min(t->file.left_length, (uint64_t)t->file_stat.size);

            /* all data and partial file_info recvd */
            } else if (left_len > 0) {
                t->readv2_rsp_tail_buf = ngx_create_temp_buf(t->pool,
                                                 NGX_HTTP_TFS_READ_V2_TAIL_LEN);
                if (t->readv2_rsp_tail_buf == NULL) {
                    return NGX_ERROR;
                }
                t->readv2_rsp_tail_buf->last =
                                        ngx_cpymem(t->readv2_rsp_tail_buf->last,
                                                   b->pos + size, tail_len);

            } else {
                return NGX_ERROR;
            }

        /* only data recvd */
        } else if (left_len == NGX_HTTP_TFS_READ_V2_TAIL_LEN) {
            t->readv2_rsp_tail_buf = ngx_create_temp_buf(t->pool,
                                                 NGX_HTTP_TFS_READ_V2_TAIL_LEN);
            if (t->readv2_rsp_tail_buf == NULL) {
                return NGX_ERROR;
            }
        }
    }

    if ((!t->is_large_file && !t->is_stat_dup_file )
        || (t->is_large_file && !t->is_process_meta_seg))
    {
        rc = ngx_http_tfs_copy_body_buffer(t, size, b->pos);
        if (rc == NGX_ERROR) {
            return rc;
        }
    }

    t->stat_info.size += size;
    t->length -= size;

    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_parse_remove_message(ngx_http_tfs_t *t)
{
    int32_t                     code, err_len;
    uint16_t                    type;
    uint64_t                    file_size;
    ngx_str_t                   err;
    ngx_int_t                   rc;
    ngx_http_tfs_header_t      *header;
    ngx_http_tfs_status_msg_t  *resp;

    header = (ngx_http_tfs_header_t *) t->header;
    type = header->type;

    switch (type) {
    case NGX_HTTP_TFS_STATUS_MESSAGE:
        resp = (ngx_http_tfs_status_msg_t *) t->tfs_peer->body_buffer.pos;
        err.len = 0;
        code = resp->code;

        if (code != NGX_HTTP_TFS_STATUS_MESSAGE_OK) {
            err_len = resp->error_len;
            if (err_len > 0) {
                err.data = resp->error_str;
                err.len = err_len;
            }

            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                          "remove_file failed, error code (%d) err_msg(%V)",
                          code, &err);
            if (code <= NGX_HTTP_TFS_EXIT_GENERAL_ERROR) {
                return code;
            }

            return NGX_HTTP_TFS_EXIT_GENERAL_ERROR;
        }

        /* on success, return is remove file's size */
        err_len = resp->error_len;
        file_size = 0;
        if (err_len > 1) {
            rc = ngx_http_tfs_atoull(resp->error_str,
                                     err_len - 1,
                                     (unsigned long long *) &file_size);
            if (rc == NGX_ERROR) {
                return NGX_ERROR;
            }
            t->stat_info.size += file_size;
        }

        ngx_log_error(NGX_LOG_INFO, t->log, 0,
                      "remove_file success, file_size: %uL ",
                      file_size);

        return NGX_OK;
    default:
        ngx_log_error(NGX_LOG_INFO, t->log, 0,
                      "remove file(ds) response msg type is invalid %d ", type);
    }

    return NGX_ERROR;
}


static ngx_int_t
ngx_http_tfs_parse_statfile_message(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    uint16_t                               type;
    ngx_int_t                              rc;
    ngx_str_t                              action;
    ngx_http_tfs_header_t                 *header;
    ngx_http_tfs_peer_connection_t        *tp;
    ngx_http_tfs_ds_stat_response_t       *resp;
    ngx_http_tfs_ds_sp_readv2_response_t  *resp2;


    header = (ngx_http_tfs_header_t *) t->header;
    tp = t->tfs_peer;
    type = header->type;

    switch (type) {
    case NGX_HTTP_TFS_STATUS_MESSAGE:
        ngx_str_set(&action, "stat file(data server)");
        rc = ngx_http_tfs_status_message(&tp->body_buffer, &action, t->log);
        return rc;
    }

    if (!t->is_large_file) {
        resp = (ngx_http_tfs_ds_stat_response_t *) tp->body_buffer.pos;
        if (resp->data_len <= 0) {
            return NGX_HTTP_TFS_EXIT_GENERAL_ERROR;
        }
        ngx_http_tfs_wrap_raw_file_info(&resp->file_info, &t->file_stat);

    } else {
        resp2 = (ngx_http_tfs_ds_sp_readv2_response_t *) tp->body_buffer.pos;
        if (resp2->data_len == NGX_HTTP_TFS_EXIT_NO_LOGICBLOCK_ERROR) {
            ngx_http_tfs_remove_block_cache(t, segment_data);
            return NGX_HTTP_TFS_AGAIN;
        }

        /* file deleted */
        if (resp2->data_len == NGX_HTTP_TFS_EXIT_FILE_INFO_ERROR) {
            t->file_stat.id =
                     ngx_http_tfs_raw_fsname_get_file_id(t->r_ctx.fsname);
            t->file_stat.offset = -1;
            t->file_stat.size = -1;
            t->file_stat.u_size = -1;
            t->file_stat.modify_time = -1;
            t->file_stat.create_time = -1;
            t->file_stat.flag = NGX_HTTP_TFS_FILE_DELETED;
            t->file_stat.crc = 0;

        } else {
            if (resp2->data_len != sizeof(ngx_http_tfs_segment_head_t)
                || resp2->file_info_len <= 0)
            {
                return NGX_HTTP_TFS_EXIT_GENERAL_ERROR;
            }
            t->file_stat.size = resp2->seg_head.size;
            t->file_stat.u_size =
                                 resp2->file_info.u_size + resp2->seg_head.size;
        }

    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_get_meta_segment(ngx_http_tfs_t *t)
{
    ngx_http_tfs_segment_info_t  *segment_info;

    t->file.segment_count = 1;

    if (t->file.segment_data == NULL) {
        t->file.segment_data = ngx_pcalloc(t->pool,
                                           sizeof(ngx_http_tfs_segment_data_t));
        if (t->file.segment_data == NULL) {
            return NGX_ERROR;
        }
    }

    segment_info = &t->file.segment_data[0].segment_info;
    segment_info->block_id = t->r_ctx.fsname.file.block_id;
    segment_info->file_id =
                           ngx_http_tfs_raw_fsname_get_file_id(t->r_ctx.fsname);
    segment_info->offset = 0;
    segment_info->size = 0;

    ngx_log_error(NGX_LOG_INFO, t->log, 0,
                  "meta segment: block_id: %uD, fileid: %uL, "
                  "seq_id: %uD, suffix: %uD",
                  segment_info->block_id,
                  segment_info->file_id,
                  t->r_ctx.fsname.file.seq_id,
                  t->r_ctx.fsname.file.suffix);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_set_meta_segment_data(ngx_http_tfs_t *t)
{
    uint32_t                      i, segment_count;
    uint64_t                      size;
    ngx_int_t                     rc;
    ngx_buf_t                    *b;
    ngx_chain_t                  *cl;
    ngx_http_tfs_segment_info_t  *seg_info;
    ngx_http_tfs_segment_data_t  *segment_data;

    segment_count = t->file.segment_count;
    /* prepare meta segment's data */
    size = sizeof(ngx_http_tfs_segment_head_t) +
        segment_count * sizeof(ngx_http_tfs_segment_info_t);
    b = ngx_create_temp_buf(t->pool, size);
    if (b == NULL) {
        return NGX_ERROR;
    }
    t->seg_head = (ngx_http_tfs_segment_head_t*)b->pos;
    t->seg_head->count = segment_count;
    t->seg_head->size = t->r_ctx.size;
    seg_info = (ngx_http_tfs_segment_info_t *)
                (b->pos + sizeof(ngx_http_tfs_segment_head_t));
    for (i = 0; i < segment_count; i++) {
        *seg_info = t->file.segment_data[i].segment_info;
        seg_info++;
    }
    b->last += size;
    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NGX_ERROR;
    }
    cl->buf = b;
    cl->next = NULL;
    /* put meta segment in the last segment
       which we pre-alloc in ngx_http_tfs_get_segment_for_write */
    t->file.segment_count += 1;
    segment_data = &t->file.segment_data[t->file.segment_index];

    segment_data->data = cl;
    /* copy data to orig_data so that we can retry write */
    rc = ngx_chain_add_copy_with_buf(t->pool,
        &segment_data->orig_data, segment_data->data);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    segment_data->oper_size = size;
    segment_data->segment_info.size = size;

    t->file.left_length = size;
    t->is_process_meta_seg = NGX_HTTP_TFS_YES;

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_parse_meta_segment(ngx_http_tfs_t *t, ngx_chain_t *data)
{
    ssize_t                           n;
    uint64_t                          data_size;
    uint32_t                          i, segment_count;
    ngx_buf_t                        *b, *tmp_b;
    ngx_int_t                         rc;
    ngx_str_t                         tfs_name;
    ngx_chain_t                      *body, *cl;
    ngx_http_tfs_raw_fsname_t         fsname;
    ngx_http_tfs_segment_head_t      *seg_head;
    ngx_http_tfs_segment_info_t      *seg_info;
    ngx_http_tfs_tmp_segment_info_t  *tmp_seg_info;

    if (data == NULL || t->meta_segment_data != NULL) {
        return NGX_ERROR;
    }

    /* maybe in two bufs, make it in a continuous buf */
    data_size = ngx_http_tfs_get_chain_buf_size(data);
    tmp_b = ngx_create_temp_buf(t->pool, data_size);
    if (tmp_b == NULL) {
        return NGX_ERROR;
    }
    body = data;
    while (body) {
        data_size = ngx_buf_size(body->buf);
        if (ngx_buf_in_memory(body->buf)) {
            tmp_b->last = ngx_cpymem(tmp_b->last, body->buf->pos, data_size);

        } else {
            /* read data from file */
            n = ngx_read_file(body->buf->file, tmp_b->last, (size_t) data_size,
                              body->buf->file_pos);
            if (n != (ssize_t)data_size) {
                ngx_log_error(NGX_LOG_ERR, t->log, 0,
                              ngx_read_file_n " read only "
                              "%z of %uL from \"%s\"",
                              n, data_size, body->buf->file->name.data);
                return NGX_ERROR;
            }
            tmp_b->last += n;
        }
        body = body->next;
    }

    seg_head = (ngx_http_tfs_segment_head_t*)(tmp_b->start);
    segment_count = seg_head->count;
    tmp_b->pos += sizeof(ngx_http_tfs_segment_head_t);

    b = ngx_create_temp_buf(t->pool, sizeof(ngx_http_tfs_segment_head_t) +
                           segment_count * sizeof(ngx_http_tfs_segment_info_t));
    if (b == NULL) {
        return NGX_ERROR;
    }
    t->seg_head = (ngx_http_tfs_segment_head_t*)b->pos;
    t->seg_head->count = segment_count;
    t->seg_head->size = seg_head->size;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                   "parse meta segment, segment head: "
                   "segment_count: %uD, size: %uL",
                   segment_count, seg_head->size);

    tmp_seg_info = (ngx_http_tfs_tmp_segment_info_t*)(tmp_b->pos);
    seg_info = (ngx_http_tfs_segment_info_t *)
                (b->pos + sizeof(ngx_http_tfs_segment_head_t));
    tfs_name.len = NGX_HTTP_TFS_FILE_NAME_LEN;
    for (i = 0; i < segment_count; i++) {
        tfs_name.data = tmp_seg_info->file_name;
        rc = ngx_http_tfs_raw_fsname_parse(&tfs_name, NULL, &fsname);
        if (rc != NGX_OK) {
            return NGX_ERROR;
        }
        seg_info->block_id = fsname.file.block_id;
        seg_info->file_id = ngx_http_tfs_raw_fsname_get_file_id(fsname);
        seg_info->offset = tmp_seg_info->offset;
        seg_info->size = tmp_seg_info->size;
        seg_info->crc = tmp_seg_info->crc;
        ngx_log_debug6(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "parse meta segment, segment info: file_name: %V,"
                       " block_id: %uD, file_id: %uL, "
                       "offset: %L, size: %D, crc: %uD",
                       &tfs_name, seg_info->block_id, seg_info->file_id,
                       seg_info->offset,
                       seg_info->size, seg_info->crc);
        seg_info++;
        tmp_seg_info++;
    }
    b->last += sizeof(ngx_http_tfs_segment_head_t)
                + segment_count * sizeof(ngx_http_tfs_segment_info_t);
    cl = ngx_alloc_chain_link(t->pool);
    if (cl == NULL) {
        return NGX_ERROR;
    }
    cl->buf = b;
    cl->next = NULL;
    t->meta_segment_data = cl;

    return NGX_OK;
}


/*
 * We use binary search to find the segment we need
 * if found, return index, or return index to insert.
 */

int32_t
ngx_http_tfs_find_segment(uint32_t seg_count,
    ngx_http_tfs_segment_info_t *seg_info, int64_t offset)
{
    int32_t  start, end, middle;

    start = 0;
    end = seg_count - 1;
    middle = (start + end) / 2;
    while (start <= end) {
        if (seg_info[middle].offset == offset) {
            return middle;
        }
        if (seg_info[middle].offset < offset) {
            start = middle + 1;

        } else {
            end = middle - 1;
        }
        middle = (start + end) / 2;
    }
    return -start;
}


ngx_int_t
ngx_http_tfs_get_segment_for_read(ngx_http_tfs_t *t)
{
    uint32_t                      buf_size, seg_count, max_seg_count, i;
    uint64_t                      start_offset, end_offset, data_size;
    int32_t                       start_seg, end_seg;
    ngx_buf_t                    *b;
    ngx_http_tfs_segment_info_t  *seg_info;
    ngx_http_tfs_segment_data_t  *first_segment, *last_segment;

    if (t->meta_segment_data == NULL) {
        return NGX_ERROR;
    }
    b = t->meta_segment_data->buf;
    if (b == NULL) {
        return NGX_ERROR;
    }

    buf_size = ngx_buf_size(b);
    if (buf_size < (sizeof(ngx_http_tfs_segment_head_t) +
                    sizeof(ngx_http_tfs_segment_info_t)))
    {
        return NGX_ERROR;
    }

    t->seg_head = (ngx_http_tfs_segment_head_t *)(b->pos);
    seg_info = (ngx_http_tfs_segment_info_t *)
                (b->pos + sizeof(ngx_http_tfs_segment_head_t));

    if (t->r_ctx.size == NGX_HTTP_TFS_MAX_SIZE) {
        data_size = t->seg_head->size;

    } else {
        data_size = t->r_ctx.size;
    }

    start_offset = t->r_ctx.offset;
    end_offset = start_offset + data_size;
    if (start_offset >= t->seg_head->size) {
        return NGX_DONE;
    }

    /* find out the segment we should start with */
    seg_count = t->seg_head->count;
    max_seg_count = (b->last - (u_char *) seg_info)
                     / sizeof(ngx_http_tfs_segment_info_t);
    if (t->seg_head->count > max_seg_count) {
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "seg_count in seg_head larger than max seg_count, "
                      "%uD > %uD, seg_head may be corrupted.",
                      t->seg_head->count, max_seg_count);
        seg_count = max_seg_count - 1;
    }
    start_seg = ngx_http_tfs_find_segment(seg_count, seg_info, start_offset);
    if (start_seg < 0) {
        start_seg = 0 - start_seg - 1;
        if (((uint64_t) seg_info[start_seg].offset + seg_info[start_seg].size)
            <= start_offset)
        {
            return NGX_ERROR;
        }
    }

    /* find out the last segment */
    end_seg = ngx_http_tfs_find_segment(seg_count, seg_info, end_offset);
    if (end_seg > 0) {
        end_seg -= 1;

    } else if (end_seg < 0) {
        end_seg = 0 - end_seg - 1;

    } else {
        return NGX_ERROR;
    }

    seg_count = end_seg - start_seg + 1;

    /* alloc segment_data */
    t->file.segment_data = ngx_pcalloc(t->pool,
                               sizeof(ngx_http_tfs_segment_data_t) * seg_count);
    if (t->file.segment_data == NULL) {
        return NGX_ERROR;
    }

    t->file.segment_index = 0;
    t->file.segment_count = seg_count;
    t->file.left_length = data_size;

    for (i = 0; start_seg <= end_seg; i++, start_seg++) {
        t->file.segment_data[i].segment_info = seg_info[start_seg];
        t->file.segment_data[i].oper_size =
                                      t->file.segment_data[i].segment_info.size;
    }

    /* first segment's oper_offset and oper_size are special for pread */
    first_segment = &t->file.segment_data[0];
    first_segment->oper_offset = t->r_ctx.offset;
    if (first_segment->segment_info.offset > 0) {
        first_segment->oper_offset -= first_segment->segment_info.offset;
    }
    first_segment->oper_size =
        first_segment->segment_info.size - first_segment->oper_offset;

    /*
     * last segment's oper_size is special,
     * notice that last_segment maybe the same as first_semgnt
     */
    last_segment = &t->file.segment_data[seg_count - 1];
    last_segment->oper_size = ngx_min((end_offset
                                       - (last_segment->segment_info.offset
                                          + last_segment->oper_offset)),
                                      last_segment->segment_info.size);

#if (NGX_DEBUG)
    for (i = 0; i < seg_count; i++) {
        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, t->log, 0,
                      "segment index: %d, oper_offset: %uD, oper_size: %uD",
                      i, t->file.segment_data[i].oper_offset,
                      t->file.segment_data[i].oper_size);
    }
#endif

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_get_segment_for_write(ngx_http_tfs_t *t)
{
    size_t        data_size, buf_size, size;
    int64_t       offset;
    uint32_t      left_size;
    ngx_int_t     seg_count, i, rc;
    ngx_buf_t    *b;
    ngx_chain_t  *body, *cl, **ll;

    if (t->send_body == NULL) {
        return NGX_ERROR;
    }

    body = t->send_body;
    offset = 0;

    /*
     * body buf is one or two bufs ,
     * please see ngx_http_read_client_request_body
     */
    data_size = ngx_http_tfs_get_chain_buf_size(body);
    t->file.left_length = data_size;

    seg_count = (data_size + NGX_HTTP_TFS_MAX_FRAGMENT_SIZE - 1)
                 / NGX_HTTP_TFS_MAX_FRAGMENT_SIZE;
    /* alloc one more so we can put large file's meta segment here */
    size = sizeof(ngx_http_tfs_segment_data_t) * (seg_count + 1);

    if (t->file.segment_data == NULL) {
        t->file.segment_data = ngx_pcalloc(t->pool, size);
        if (t->file.segment_data == NULL) {
            return NGX_ERROR;
        }
    }

    t->file.segment_count = seg_count;
    t->file.segment_index = 0;
    t->file.last_write_segment_index = 0;

    if (t->is_large_file) {
        offset = 0;  /* large file do not support pwrite */

    } else if (t->r_ctx.version == 2) {
        offset = t->r_ctx.offset;
    }

    for (i = 0; i < seg_count; i++) {
        t->file.segment_data[i].segment_info.offset = offset;
        t->file.segment_data[i].segment_info.size =
            ngx_min(data_size, NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);
        t->file.segment_data[i].oper_size =
                                      t->file.segment_data[i].segment_info.size;
        if (t->is_large_file
            || (t->r_ctx.version == 2 && offset != NGX_HTTP_TFS_APPEND_OFFSET))
        {
            offset += NGX_HTTP_TFS_MAX_FRAGMENT_SIZE;
        }
        data_size -= t->file.segment_data[i].segment_info.size;

        /* prepare each segment's data */
        left_size = t->file.segment_data[i].segment_info.size;
        ll = &t->file.segment_data[i].data;
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, t->log, 0,
                      "prepare segment[%i]'s data", i);

        while (left_size > 0) {
            while (body && ngx_buf_size(body->buf) == 0) {
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, t->log, 0,
                              "zero body buf");
                body = body->next;
            }
            if (body == NULL) {
                ngx_log_error(NGX_LOG_ERR, t->log, 0,
                              "prepare segment data[%i] failed for early end.",
                              i);
                return NGX_ERROR;
            }
            buf_size = ngx_min(ngx_buf_size(body->buf), left_size);

            b = ngx_alloc_buf(t->pool);
            if (b == NULL) {
                return NGX_ERROR;
            }
            ngx_memcpy(b, body->buf, sizeof(ngx_buf_t));
            if (ngx_buf_in_memory(b)) {
                b->last = b->pos + buf_size;
                ngx_log_debug3(NGX_LOG_DEBUG_HTTP, t->log, 0,
                               "pos: %uD, last: %uD, size: %z",
                               (b->pos - b->start),
                               (b->last - b->start),
                               buf_size);

            } else {
                b->file_last = b->file_pos + buf_size;
                ngx_log_debug3(NGX_LOG_DEBUG_HTTP, t->log, 0,
                               "pos: %O, last: %O, size: %z",
                               b->file_pos, b->file_last, buf_size);
            }

            cl = ngx_alloc_chain_link(t->pool);
            if (cl == NULL) {
                return NGX_ERROR;
            }
            cl->buf = b;
            cl->next = NULL;
            *ll = cl;
            ll = &cl->next;

            if (ngx_buf_in_memory(body->buf)) {
                body->buf->pos += buf_size;

            } else {
                body->buf->file_pos += buf_size;
            }

            left_size -= buf_size;
        }
        /* copy data to orig_data so that we can retry write */
        rc = ngx_chain_add_copy_with_buf(t->pool,
            &t->file.segment_data[i].orig_data, t->file.segment_data[i].data);
        if (rc == NGX_ERROR) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_get_segment_for_delete(ngx_http_tfs_t *t)
{
    uint32_t                      buf_size, seg_count, max_seg_count, i;
    ngx_buf_t                    *b;
    ngx_http_tfs_segment_info_t  *seg_info;

    if (t->meta_segment_data == NULL) {
        return NGX_ERROR;
    }
    b = t->meta_segment_data->buf;
    if (b == NULL) {
        return NGX_ERROR;
    }

    buf_size = ngx_buf_size(b);
    if (buf_size < (sizeof(ngx_http_tfs_segment_head_t) +
                    sizeof(ngx_http_tfs_segment_info_t)))
    {
        return NGX_ERROR;
    }

    t->seg_head = (ngx_http_tfs_segment_head_t*)(b->pos);
    seg_info = (ngx_http_tfs_segment_info_t*)
        (b->pos + sizeof(ngx_http_tfs_segment_head_t));

    /* all data segments plus meta segment */
    seg_count = t->seg_head->count + 1;
    max_seg_count = (b->last - (u_char *) seg_info)
                    / sizeof(ngx_http_tfs_segment_info_t);
    if (t->seg_head->count > max_seg_count) {
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "seg_count in seg_head larger than max seg_count, "
                      "%uD > %uD, seg_head may be corrupted",
                      t->seg_head->count, max_seg_count);
        seg_count = max_seg_count;
    }

    t->file.segment_data = ngx_http_tfs_prealloc(t->pool, t->file.segment_data,
                              sizeof(ngx_http_tfs_segment_data_t),
                              sizeof(ngx_http_tfs_segment_data_t) * seg_count);
    if (t->file.segment_data == NULL) {
        return NGX_ERROR;
    }

    ngx_memzero(&t->file.segment_data[1],
                sizeof(ngx_http_tfs_segment_data_t) * (seg_count - 1));

    t->file.segment_index = 0;
    t->file.segment_count = seg_count;

    for (i = 1; i < t->file.segment_count; i++) {
        t->file.segment_data[i].segment_info = seg_info[i-1];
    }
    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_copy_body_buffer(ngx_http_tfs_t *t, ssize_t bytes, u_char *body)
{
    ngx_http_request_t  *r = t->data;

    ngx_chain_t  *cl, **ll;

    for (cl = t->out_bufs, ll = &t->out_bufs; cl; cl = cl->next) {
        ll = &cl->next;
    }

    cl = ngx_chain_get_free_buf(r->pool, &t->free_bufs);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    *ll = cl;

    cl->buf->flush = 1;
    cl->buf->memory = 1;

    cl->buf->pos = body;
    cl->buf->last = body + bytes;
    cl->buf->tag = t->output.tag;

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_fill_file_hole(ngx_http_tfs_t *t, size_t file_hole_size)
{
    size_t     size;
    ngx_int_t  rc;
    ngx_buf_t  *b, *zero_buf;

    b = &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER].body_buffer;
    if (b->start == NULL) {
        b->start = ngx_palloc(t->pool, NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);
        if (b->start == NULL) {
            return NGX_ERROR;
        }

        b->pos = b->start;
        b->last = b->start;
        b->end = b->start + NGX_HTTP_TFS_MAX_FRAGMENT_SIZE;
        b->temporary = 1;
    }

    size = b->end - b->last;

    /* file hole can be fill once */
    if (file_hole_size <= size) {
        ngx_memzero(b->last, file_hole_size);
        rc = ngx_http_tfs_copy_body_buffer(t, file_hole_size, b->last);
        if (rc == NGX_ERROR) {
            return rc;
        }

        b->pos += file_hole_size;
        b->last += file_hole_size;

        ngx_log_error(NGX_LOG_DEBUG, t->log, 0,
                      "fill file hole once, size: %uL", file_hole_size);

    } else {
        zero_buf = ngx_create_temp_buf(t->pool, NGX_HTTP_TFS_ZERO_BUF_SIZE);
        if (zero_buf == NULL) {
            return NGX_ERROR;
        }
        ngx_memzero(zero_buf->start, NGX_HTTP_TFS_ZERO_BUF_SIZE);

        while (file_hole_size > 0) {
            size = ngx_min(NGX_HTTP_TFS_ZERO_BUF_SIZE, file_hole_size);
            rc = ngx_http_tfs_copy_body_buffer(t, size, zero_buf->pos);
            if (rc == NGX_ERROR) {
                return rc;
            }

            file_hole_size -= size;

            ngx_log_error(NGX_LOG_DEBUG, t->log, 0,
                          "fill file hole, size: %z, remain hole size: %uL",
                          size, file_hole_size);
        }
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_check_file_hole(ngx_http_tfs_file_t *file, ngx_array_t *file_holes, ngx_log_t *log)
{
    int64_t                         curr_length;
    uint32_t                        segment_count, i;
    ngx_http_tfs_segment_data_t    *segment_data;
    ngx_http_tfs_file_hole_info_t  *file_hole_info;

    if (file == NULL || file_holes == NULL) {
        return NGX_ERROR;
    }

    segment_data = file->segment_data;
    if (segment_data != NULL) {
        segment_count = file->segment_count;
        for (i = 0; i < segment_count; i++, segment_data++) {
            if (file->file_offset < segment_data->segment_info.offset) {
                curr_length = ngx_min(file->left_length,
                    (uint64_t)(segment_data->segment_info.offset - file->file_offset));
                file_hole_info = ngx_array_push(file_holes);
                if (file_hole_info == NULL) {
                    return NGX_ERROR;
                }

                file_hole_info->offset = file->file_offset;
                file_hole_info->length = curr_length;

                ngx_log_error(NGX_LOG_DEBUG, log, 0,
                              "find file hole, offset: %uL, length: %uL",
                              file_hole_info->offset, file_hole_info->length);

                file->file_offset += curr_length;
                file->left_length -= curr_length;
                if (file->left_length == 0) {
                    break;
                }
            }
            file->file_offset += segment_data->oper_size;
            file->left_length -= segment_data->oper_size;
            if (file->left_length == 0) {
                break;
            }
        }
    }

    if (!file->still_have) {
        /* left is all file hole(beyond last segment) */
        if (file->left_length > 0) {
            file_hole_info = ngx_array_push(file_holes);
            if (file_hole_info == NULL) {
                return NGX_ERROR;
            }

            file_hole_info->offset = file->file_offset;
            file_hole_info->length = file->left_length;

            ngx_log_error(NGX_LOG_DEBUG, log, 0,
                          "find file hole, offset: %uL, length: %uL",
                          file_hole_info->offset, file_hole_info->length);
            file->file_offset += file->left_length;
            file->left_length = 0;
        }

        return NGX_DONE;
    }

    return NGX_OK;
}
