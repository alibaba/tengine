
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_tfs_common.h>
#include <ngx_http_tfs_restful.h>
#include <ngx_http_tfs_protocol.h>


#define NGX_HTTP_TFS_VERSION1 "v1"
#define NGX_HTTP_TFS_VERSION2 "v2"


static ngx_str_t ali_move_source = ngx_string("x-ali-move-source");


static ngx_int_t
ngx_http_restful_parse_raw(ngx_http_request_t *r,
    ngx_http_tfs_restful_ctx_t *ctx, u_char *data)
{
    u_char  *p, ch, *start, *last, *meta_data;

    enum {
        sw_appkey = 0,
        sw_metadata,
        sw_name,
    } state;

    state = sw_appkey;
    last = r->uri.data + r->uri.len;
    start = data;
    meta_data = NULL;

    for (p = data; p < last; p++) {
        ch = *p;

        switch (state) {

        case sw_appkey:
            if (ch == '/') {
                ctx->appkey.data = start;
                ctx->appkey.len = p - start;

                state = sw_metadata;
                if (p + 1 < last) {
                    meta_data = p + 1;
                }
            }

            break;

        case sw_metadata:
            if (ch == '/') {
                if (ngx_memcmp(meta_data, "metadata", 8) == 0) {
                    if (p + 1 < last) {
                        ctx->meta = NGX_HTTP_TFS_YES;
                        ctx->file_path_s.data = p + 1;
                        state = sw_name;

                    } else {
                        return NGX_ERROR;
                    }
                }
            }
        case sw_name:
            break;
        }
    }

    if (r->method == NGX_HTTP_GET || r->method == NGX_HTTP_DELETE
        || r->method == NGX_HTTP_PUT || r->method == NGX_HTTP_HEAD) {
        if (state == sw_appkey) {
            return NGX_ERROR;
        }

        if (state == sw_metadata) {
            ctx->file_path_s.data = meta_data;
        }

        if (state == sw_name) {
            if (r->method == NGX_HTTP_DELETE || r->method == NGX_HTTP_PUT) {
                return NGX_ERROR;
            }
        }
        ctx->file_path_s.len = p - ctx->file_path_s.data;
        if (ctx->file_path_s.len < 1
            || ctx->file_path_s.len > NGX_HTTP_TFS_MAX_FILE_NAME_LEN)
        {
            return NGX_ERROR;
        }

    } else {
        if (state == sw_appkey) {
            ctx->appkey.len = p - start;
            if (ctx->appkey.len == 0) {
                return NGX_ERROR;
            }
            ctx->appkey.data = start;

        } else {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_restful_parse_custom_name(ngx_http_request_t *r,
    ngx_http_tfs_restful_ctx_t *ctx, u_char *data)
{
    u_char    *p, ch, *start, *last, *appid, *meta_data;
    ngx_int_t  rc;

    enum {
        sw_appkey = 0,
        sw_metadata,
        sw_appid,
        sw_uid,
        sw_type,
        sw_name,
    } state;

    state = sw_appkey;
    last = r->uri.data + r->uri.len;
    start = data;
    appid = NULL;
    meta_data = NULL;

    for (p = data; p < last; p++) {
        ch = *p;

        switch (state) {
        case sw_appkey:
            if (ch == '/') {
                ctx->appkey.data = start;
                ctx->appkey.len = p - start;

                start = p + 1;
                /* GET /v2/appkey/appid */
                if (start < last) {
                    if (*start == 'a') {
                        state = sw_name;
                        appid = start;
                    } else if (*start == 'm') {
                        state = sw_metadata;
                        meta_data = start;
                    } else {
                        state = sw_appid;
                    }
                }
            }
            break;
        case sw_metadata:
            if (ch == '/') {
                if (ngx_memcmp(meta_data, "metadata", 8) == 0) {
                    if (p + 1 < last) {
                        ctx->meta = NGX_HTTP_TFS_YES;
                        start = p + 1;
                        state = sw_appid;

                    } else {
                        return NGX_ERROR;
                    }
                }
            }
            break;
        case sw_appid:
            if (ch == '/') {
                rc = ngx_http_tfs_atoull(start, p - start,
                                         (unsigned long long *)&ctx->app_id);
                if (rc == NGX_ERROR || ctx->app_id == 0) {
                    return NGX_ERROR;
                }

                start = p + 1;
                state = sw_uid;
                break;
            }

            if (ch < '0' || ch > '9') {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                              "appid is invalid");
                return NGX_ERROR;
            }

            if ((size_t) (p - start) > (NGX_INT64_LEN - 1)) {
                return NGX_ERROR;
            }

            break;
        case sw_uid:
            if (ch == '/') {
                rc = ngx_http_tfs_atoull(start, p - start,
                                         (unsigned long long *)&ctx->user_id);
                if (rc == NGX_ERROR || ctx->user_id == 0) {
                    return NGX_ERROR;
                }
                start = p + 1;
                state = sw_type;
                break;
            }

            if (ch < '0' || ch > '9') {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                              "userid is invalid");
                return NGX_ERROR;
            }

            if ((size_t) (p - start) > NGX_INT64_LEN - 1) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                              "userid is too big");
                return NGX_ERROR;
            }
            break;
        case sw_type:
            if (ch == '/') {
                if (ngx_strncmp(start, "file", p - start) == 0) {
                    ctx->file_type = NGX_HTTP_TFS_CUSTOM_FT_FILE;

                } else if (ngx_strncmp(start, "dir", p - start) == 0) {
                    ctx->file_type = NGX_HTTP_TFS_CUSTOM_FT_DIR;

                } else {
                    return NGX_ERROR;
                }
                ctx->file_path_s.data = p;
                state = sw_name;
            }
            break;
        case sw_name:
            break;
        }
    }

    if (r->method == NGX_HTTP_GET && appid != NULL) {
        if (ngx_memcmp(appid, "appid", 5) == 0) {
            ctx->get_appid = NGX_HTTP_TFS_YES;
            ctx->file_path_s.data = appid;
            ctx->file_path_s.len = 5;
            return NGX_OK;
        }
        return NGX_ERROR;
    }

    ctx->file_path_s.len = p - ctx->file_path_s.data;
    if (ctx->file_path_s.len < 1
        || ctx->file_path_s.len > NGX_HTTP_TFS_MAX_FILE_NAME_LEN)
    {
        return NGX_ERROR;
    }

    /* forbid file actions on "/" */
    if (ctx->file_type == NGX_HTTP_TFS_CUSTOM_FT_FILE
        && ctx->file_path_s.len == 1)
    {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_restful_parse_uri(ngx_http_request_t *r,
    ngx_http_tfs_restful_ctx_t *ctx)
{
    u_char  *p, ch, *last;

    enum {
        sw_start = 0,
        sw_version_prefix,
        sw_version,
        sw_backslash,
    } state;

    state = sw_start;
    last = r->uri.data + r->uri.len;

    for (p = r->uri.data; p < last; p++) {
        ch = *p;

        switch (state) {
        case sw_start:
            state = sw_version_prefix;
            break;
        case sw_version_prefix:
            if (ch != 'v') {
                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "version invalid %V ", &r->uri);
                return NGX_ERROR;
            }
            state = sw_version;
            break;

        case sw_version:
            if (ch < '1' || ch > '9') {
                return NGX_ERROR;
            }

            ctx->version = ch - '0';
            if (ctx->version > 2) {
                return NGX_ERROR;
            }

            state = sw_backslash;
            break;

        case sw_backslash:
            if (ch != '/') {
                return NGX_ERROR;
            }

            if (ctx->version == 1) {
                return ngx_http_restful_parse_raw(r, ctx, ++p);
            }

            if (ctx->version == 2) {
                return ngx_http_restful_parse_custom_name(r, ctx, ++p);
            }

            return NGX_ERROR;
        }
    }

    return NGX_ERROR;
}


static ngx_int_t
ngx_http_restful_parse_action(ngx_http_request_t *r,
    ngx_http_tfs_restful_ctx_t *ctx)
{
    ngx_int_t  rc;
    ngx_str_t  arg_value, file_path_d, file_temp_path;

    switch(r->method) {
    case NGX_HTTP_GET:
        if (ctx->get_appid) {
            ctx->action.code = NGX_HTTP_TFS_ACTION_GET_APPID;
            ngx_str_set(&ctx->action.msg, "get_appid");
            return NGX_OK;
        }
        if (ctx->file_type == NGX_HTTP_TFS_CUSTOM_FT_FILE) {
            if (ctx->meta) {
                ctx->action.code = NGX_HTTP_TFS_ACTION_LS_FILE;
                ngx_str_set(&ctx->action.msg, "ls_file");
                return NGX_OK;
            }

            ctx->action.code = NGX_HTTP_TFS_ACTION_READ_FILE;
            ngx_str_set(&ctx->action.msg, "read_file");

            if (r->headers_in.range != NULL) {
                return NGX_HTTP_BAD_REQUEST;
            }

            if (ngx_http_arg(r, (u_char *) "check_hole", 10, &arg_value)
                == NGX_OK)
            {
                ctx->chk_file_hole = ngx_atoi(arg_value.data, arg_value.len);
                if (ctx->chk_file_hole == NGX_ERROR
                    || (ctx->chk_file_hole != NGX_HTTP_TFS_NO
                        && ctx->chk_file_hole != NGX_HTTP_TFS_YES))
                {
                    return NGX_HTTP_BAD_REQUEST;
                }
            }

            if (ngx_http_arg(r, (u_char *) "offset", 6, &arg_value) == NGX_OK) {
                ctx->offset = ngx_http_tfs_atoll(arg_value.data, arg_value.len);
                if (ctx->offset == NGX_ERROR) {
                    return NGX_HTTP_BAD_REQUEST;
                }
            }

            if (ngx_http_arg(r, (u_char *) "size", 4, &arg_value) == NGX_OK) {
                rc = ngx_http_tfs_atoull(arg_value.data, arg_value.len,
                                         (unsigned long long *)&ctx->size);
                if (rc == NGX_ERROR) {
                    return NGX_HTTP_BAD_REQUEST;
                }
                if (ctx->size == 0) {
                    return NGX_HTTP_BAD_REQUEST;
                }
                return NGX_OK;
            }

            ctx->size = NGX_HTTP_TFS_MAX_SIZE;

            return NGX_OK;
        }

        ctx->action.code = NGX_HTTP_TFS_ACTION_LS_DIR;
        ngx_str_set(&ctx->action.msg, "ls_dir");
        return NGX_OK;
    case NGX_HTTP_POST:
        if (ngx_http_tfs_parse_headerin(r, &ali_move_source, &file_path_d)
            == NGX_OK)
        {
            ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                          "move from %V to %V",
                          &file_path_d, &ctx->file_path_s);

            if (file_path_d.len < 1
                || file_path_d.len > NGX_HTTP_TFS_MAX_FILE_NAME_LEN
                || ctx->file_path_s.len == 1)
            {
                return NGX_HTTP_BAD_REQUEST;
            }

            if (ctx->file_path_s.len == file_path_d.len
                && ngx_strncmp(ctx->file_path_s.data, file_path_d.data,
                               file_path_d.len) == 0)
            {
                return NGX_HTTP_BAD_REQUEST;
            }

            file_temp_path = ctx->file_path_s;
            ctx->file_path_s = file_path_d;
            ctx->file_path_d = file_temp_path;
            if (ctx->file_type == NGX_HTTP_TFS_CUSTOM_FT_FILE) {
                ctx->action.code = NGX_HTTP_TFS_ACTION_MOVE_FILE;
                ngx_str_set(&ctx->action.msg, "move_file");

            } else {
                ctx->action.code = NGX_HTTP_TFS_ACTION_MOVE_DIR;
                ngx_str_set(&ctx->action.msg, "move_dir");
            }

        } else {
            if (ctx->file_type == NGX_HTTP_TFS_CUSTOM_FT_FILE) {
                ctx->action.code = NGX_HTTP_TFS_ACTION_CREATE_FILE;
                ngx_str_set(&ctx->action.msg, "create_file");

            } else {
                /* forbid create "/" */
                if (ctx->file_path_s.len == 1) {
                    return NGX_HTTP_BAD_REQUEST;
                }

                ctx->action.code = NGX_HTTP_TFS_ACTION_CREATE_DIR;
                ngx_str_set(&ctx->action.msg, "create_dir");
            }
        }
        if (ngx_http_arg(r, (u_char *) "recursive", 9, &arg_value) == NGX_OK) {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->recursive = ngx_atoi(arg_value.data, arg_value.len);
            if (ctx->recursive == NGX_ERROR
                || (ctx->recursive != NGX_HTTP_TFS_NO
                    && ctx->recursive != NGX_HTTP_TFS_YES))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }
        break;
    case NGX_HTTP_PUT:
        if (ctx->file_type == NGX_HTTP_TFS_CUSTOM_FT_FILE) {
            ctx->action.code = NGX_HTTP_TFS_ACTION_WRITE_FILE;
            ngx_str_set(&ctx->action.msg, "write_file");
            if (ngx_http_arg(r, (u_char *) "offset", 6, &arg_value) == NGX_OK) {
                ctx->offset = ngx_http_tfs_atoll(arg_value.data, arg_value.len);
                if (ctx->offset == NGX_ERROR) {
                    return NGX_HTTP_BAD_REQUEST;
                }

            } else {
                /* no specify offset, append by default */
                ctx->offset = NGX_HTTP_TFS_APPEND_OFFSET;
            }
            return NGX_OK;
        }
        /* forbid put aciont on dir */
        return NGX_ERROR;
    case NGX_HTTP_DELETE:
        if (ctx->file_type == NGX_HTTP_TFS_CUSTOM_FT_FILE) {
            ctx->action.code = NGX_HTTP_TFS_ACTION_REMOVE_FILE;
            ngx_str_set(&ctx->action.msg, "remove_file");
            /* for t->file.left_length */
            ctx->size = NGX_HTTP_TFS_MAX_SIZE;

            return NGX_OK;
        }

        /* forbid delete "/" */
        if (ctx->file_path_s.len == 1) {
            return NGX_HTTP_BAD_REQUEST;
        }

        ctx->action.code = NGX_HTTP_TFS_ACTION_REMOVE_DIR;
        ngx_str_set(&ctx->action.msg, "remove_dir");
        break;
    case NGX_HTTP_HEAD:
        if (ctx->file_type == NGX_HTTP_TFS_CUSTOM_FT_FILE) {
            ctx->action.code = NGX_HTTP_TFS_ACTION_LS_FILE;
            ngx_str_set(&ctx->action.msg, "ls_file");

        } else {
            ctx->action.code = NGX_HTTP_TFS_ACTION_LS_DIR;
            ngx_str_set(&ctx->action.msg, "ls_dir");
        }
        ctx->chk_exist = NGX_HTTP_TFS_YES;
        return NGX_OK;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_restful_parse_action_raw(ngx_http_request_t *r,
    ngx_http_tfs_restful_ctx_t *ctx)
{
    ngx_int_t  rc;
    ngx_str_t  arg_value;

    switch(r->method) {
    case NGX_HTTP_GET:
        if (ngx_http_arg(r, (u_char *) "suffix", 6, &arg_value) == NGX_OK) {
            ctx->file_suffix = arg_value;
        }

        rc = ngx_http_tfs_raw_fsname_parse(&ctx->file_path_s, &ctx->file_suffix,
                                           &ctx->fsname);
        if (rc != NGX_OK) {
            return NGX_HTTP_BAD_REQUEST;
        }

        if (ngx_http_arg(r, (u_char *) "type", 4, &arg_value) == NGX_OK) {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->read_stat_type = ngx_atoi(arg_value.data, arg_value.len);
            /* normal_read/stat(0) or force_read/stat(1) */
            if (ctx->read_stat_type == NGX_ERROR
                || (ctx->read_stat_type != NGX_HTTP_TFS_READ_STAT_NORMAL
                    && ctx->read_stat_type != NGX_HTTP_TFS_READ_STAT_FORCE))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }
        if (ctx->meta) {
            ctx->action.code = NGX_HTTP_TFS_ACTION_STAT_FILE;
            ngx_str_set(&ctx->action.msg, "stat_file");

        } else {
            ctx->action.code = NGX_HTTP_TFS_ACTION_READ_FILE;
            ngx_str_set(&ctx->action.msg, "read_file");
            if (ngx_http_arg(r, (u_char *) "offset", 6, &arg_value) == NGX_OK) {
                ctx->offset = ngx_http_tfs_atoll(arg_value.data, arg_value.len);
                if (ctx->offset == NGX_ERROR) {
                    return NGX_HTTP_BAD_REQUEST;
                }
            }

            if (ngx_http_arg(r, (u_char *) "size", 4, &arg_value) == NGX_OK) {
                rc = ngx_http_tfs_atoull(arg_value.data,
                                         arg_value.len,
                                         (unsigned long long *)&ctx->size);
                if (rc == NGX_ERROR) {
                    return NGX_HTTP_BAD_REQUEST;
                }

                if (ctx->size == 0) {
                    return NGX_HTTP_BAD_REQUEST;
                }

                return NGX_OK;
            }

            ctx->size = NGX_HTTP_TFS_MAX_SIZE;
        }
        break;

    case NGX_HTTP_POST:
        ctx->action.code = NGX_HTTP_TFS_ACTION_WRITE_FILE;
        if (ngx_http_arg(r, (u_char *) "suffix", 6, &arg_value) == NGX_OK) {
            ctx->file_suffix = arg_value;
        }

        if (ngx_http_arg(r, (u_char *) "simple_name", 11, &arg_value)
            == NGX_OK)
        {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->simple_name = ngx_atoi(arg_value.data, arg_value.len);
            if (ctx->simple_name == NGX_ERROR
                || (ctx->simple_name != NGX_HTTP_TFS_NO
                    && ctx->simple_name != NGX_HTTP_TFS_YES))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }

        if (ngx_http_arg(r, (u_char *) "large_file", 10, &arg_value)
            == NGX_OK)
        {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->large_file = ngx_atoi(arg_value.data, arg_value.len);
            if (ctx->large_file == NGX_ERROR
                || (ctx->large_file != NGX_HTTP_TFS_NO
                    && ctx->large_file != NGX_HTTP_TFS_YES))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }

        if (ngx_http_arg(r, (u_char *) "meta_segment", 12, &arg_value)
            == NGX_OK)
        {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->write_meta_segment = ngx_atoi(arg_value.data, arg_value.len);
            if (ctx->write_meta_segment == NGX_ERROR
                || (ctx->write_meta_segment != NGX_HTTP_TFS_NO
                    && ctx->write_meta_segment != NGX_HTTP_TFS_YES))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }

        if (ngx_http_arg(r, (u_char *) "no_dedup", 8, &arg_value) == NGX_OK) {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->no_dedup = ngx_atoi(arg_value.data, arg_value.len);
            if (ctx->no_dedup == NGX_ERROR
                || (ctx->no_dedup != NGX_HTTP_TFS_NO
                    && ctx->no_dedup != NGX_HTTP_TFS_YES))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }

        ngx_str_set(&ctx->action.msg, "write_file");
        break;

    case NGX_HTTP_DELETE:
        ctx->action.code = NGX_HTTP_TFS_ACTION_REMOVE_FILE;
        ngx_str_set(&ctx->action.msg, "remove_file");

        /* for outer user use */
        if (ngx_http_arg(r, (u_char *) "hide", 4, &arg_value) == NGX_OK) {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->unlink_type = ngx_atoi(arg_value.data, arg_value.len);
            /* hide(1) or reveal(0)*/
            if (ctx->unlink_type == NGX_ERROR
                || (ctx->unlink_type != 0 && ctx->unlink_type != 1))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
            /* convert to actual type */
            if (ctx->unlink_type == 1) {
                ctx->unlink_type = NGX_HTTP_TFS_UNLINK_CONCEAL;

            } else {
                ctx->unlink_type = NGX_HTTP_TFS_UNLINK_REVEAL;
            }
        }

        if (ngx_http_arg(r, (u_char *) "type", 4, &arg_value) == NGX_OK) {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->unlink_type = ngx_atoi(arg_value.data, arg_value.len);
            /* del(0) or undel(2) or hide(4) or reveal(6)*/
            if (ctx->unlink_type == NGX_ERROR
                || (ctx->unlink_type != NGX_HTTP_TFS_UNLINK_DELETE
                    && ctx->unlink_type != NGX_HTTP_TFS_UNLINK_UNDELETE
                    && ctx->unlink_type != NGX_HTTP_TFS_UNLINK_CONCEAL
                    && ctx->unlink_type != NGX_HTTP_TFS_UNLINK_REVEAL))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }

        if (ngx_http_arg(r, (u_char *) "suffix", 6, &arg_value) == NGX_OK) {
            ctx->file_suffix = arg_value;
        }

        rc = ngx_http_tfs_raw_fsname_parse(&ctx->file_path_s, &ctx->file_suffix,
                                           &ctx->fsname);
        if (rc != NGX_OK) {
            return NGX_HTTP_BAD_REQUEST;
        }

        /* large file not support UNDELETE */
        if ((ctx->fsname.file_type == NGX_HTTP_TFS_LARGE_FILE_TYPE)
            && ctx->unlink_type == NGX_HTTP_TFS_UNLINK_UNDELETE)
        {
            return NGX_HTTP_BAD_REQUEST;
        }
        break;

    case NGX_HTTP_HEAD:
        if (ngx_http_arg(r, (u_char *) "suffix", 6, &arg_value) == NGX_OK) {
            ctx->file_suffix = arg_value;
        }

        rc = ngx_http_tfs_raw_fsname_parse(&ctx->file_path_s, &ctx->file_suffix,
                                           &ctx->fsname);
        if (rc != NGX_OK) {
            return NGX_HTTP_BAD_REQUEST;
        }

        if (ngx_http_arg(r, (u_char *) "type", 4, &arg_value) == NGX_OK) {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->read_stat_type = ngx_atoi(arg_value.data, arg_value.len);
            /* normal_read/stat(0) or force_read/stat(1) */
            if (ctx->read_stat_type == NGX_ERROR
                || (ctx->read_stat_type != NGX_HTTP_TFS_READ_STAT_NORMAL
                    && ctx->read_stat_type != NGX_HTTP_TFS_READ_STAT_FORCE))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }
        ctx->action.code = NGX_HTTP_TFS_ACTION_STAT_FILE;
        ngx_str_set(&ctx->action.msg, "stat_file");
        ctx->chk_exist = NGX_HTTP_TFS_YES;
        break;

    case NGX_HTTP_PUT:
        ctx->action.code = NGX_HTTP_TFS_ACTION_WRITE_FILE;
        if (ngx_http_arg(r, (u_char *) "suffix", 6, &arg_value) == NGX_OK) {
            ctx->file_suffix = arg_value;
        }

        if (ngx_http_arg(r, (u_char *) "simple_name", 11, &arg_value)
            == NGX_OK)
        {
            if (arg_value.len != 1) {
                return NGX_HTTP_BAD_REQUEST;
            }
            ctx->simple_name = ngx_atoi(arg_value.data, arg_value.len);
            if (ctx->simple_name == NGX_ERROR
                || (ctx->simple_name != NGX_HTTP_TFS_NO
                    && ctx->simple_name != NGX_HTTP_TFS_YES))
            {
                return NGX_HTTP_BAD_REQUEST;
            }
        }

        if (ctx->file_path_s.data == NULL) {
            return NGX_HTTP_BAD_REQUEST;
        }

        /* large file not support update */
        if (ngx_http_arg(r, (u_char *) "large_file", 10, &arg_value) == NGX_OK) {
            return NGX_HTTP_BAD_REQUEST;
        }

        rc = ngx_http_tfs_raw_fsname_parse(&ctx->file_path_s, &ctx->file_suffix,
                                           &ctx->fsname);
        /* large file not support update */
        if (rc != NGX_OK
            || (ctx->fsname.file_type == NGX_HTTP_TFS_LARGE_FILE_TYPE))
        {
            return NGX_HTTP_BAD_REQUEST;
        }

        ctx->is_raw_update = NGX_HTTP_TFS_YES;
        ngx_str_set(&ctx->action.msg, "write_file");
        break;

    default:
        return NGX_HTTP_BAD_REQUEST;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_restful_parse(ngx_http_request_t *r, ngx_http_tfs_restful_ctx_t *ctx)
{
    ngx_int_t  rc;

    rc = ngx_http_restful_parse_uri(r, ctx);
    if (rc == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "parse uri failed");
        return NGX_HTTP_BAD_REQUEST;
    }

    if (ctx->version == 1) {
        rc = ngx_http_restful_parse_action_raw(r, ctx);
    }

    if (ctx->version == 2) {
        rc = ngx_http_restful_parse_action(r, ctx);
    }

    return rc;
}
