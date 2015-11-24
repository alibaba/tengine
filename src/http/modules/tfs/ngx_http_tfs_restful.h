
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_RESTFUL_H_INCLUDED_
#define _NGX_HTTP_TFS_RESTFUL_H_INCLUDED_


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_http_tfs_raw_fsname.h>


typedef struct {
    ngx_str_t                    file_path_s;
    ngx_str_t                    file_path_d;

    ngx_str_t                    file_suffix;
    ngx_http_tfs_raw_fsname_t    fsname;

    ngx_str_t                    appkey;
    uint64_t                     app_id;
    uint64_t                     user_id;

    /* action */
    ngx_http_tfs_action_t        action;
    int64_t                      offset;
    uint64_t                     size;

    ngx_int_t                    unlink_type;
    ngx_int_t                    simple_name;
    uint8_t                      version;
    uint8_t                      file_type;
    ngx_int_t                    large_file;

    ngx_int_t                    read_stat_type;
    ngx_int_t                    write_meta_segment;
    ngx_int_t                    no_dedup;
    ngx_int_t                    chk_file_hole;
    ngx_int_t                    recursive;

    unsigned                     meta:1;
    unsigned                     get_appid:1;
    unsigned                     chk_exist:1;
    unsigned                     is_raw_update:1;
} ngx_http_tfs_restful_ctx_t;


ngx_int_t ngx_http_restful_parse(ngx_http_request_t *r,
    ngx_http_tfs_restful_ctx_t *ctx);


#endif  /* _NGX_HTTP_TFS_RESTFUL_H_INCLUDED_ */
