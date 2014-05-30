
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_DUPLICATE_H_INCLUDED_
#define _NGX_HTTP_TFS_DUPLICATE_H_INCLUDED_


#include <ngx_tfs_common.h>
#include <ngx_http_tfs_tair_helper.h>


typedef struct {
    u_char                            tair_key[NGX_HTTP_TFS_DUPLICATE_KEY_SIZE];
    int32_t                           dup_version;
    int32_t                           file_ref_count;
    ngx_str_t                         dup_file_name;
    ngx_str_t                         dup_file_suffix;
    ngx_buf_t                         save_body_buffer;
    ngx_http_tfs_t                   *data;
    ngx_http_tfs_tair_instance_t     *tair_instance;
    ngx_chain_t                      *file_data;
    unsigned                          md5_sumed:1;
} ngx_http_tfs_dedup_ctx_t;


ngx_int_t ngx_http_tfs_dedup_get(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log);
ngx_int_t ngx_http_tfs_dedup_set(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log);
ngx_int_t ngx_http_tfs_dedup_remove(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_pool_t *pool, ngx_log_t *log);

ngx_int_t ngx_http_tfs_get_dedup_instance(ngx_http_tfs_dedup_ctx_t *ctx,
    ngx_http_tfs_tair_server_addr_info_t *server_addr_info,
    uint32_t server_addr_hash);


#endif  /* _NGX_HTTP_TFS_DUPLICATE_H_INCLUDED_ */
