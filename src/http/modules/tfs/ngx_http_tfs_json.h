
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_JSON_H_INCLUDED_
#define _NGX_HTTP_TFS_JSON_H_INCLUDED_


#include <yajl/yajl_parse.h>
#include <yajl/yajl_gen.h>
#include <ngx_http_tfs_protocol.h>


typedef struct {
    yajl_gen          gen;
    ngx_log_t        *log;
    ngx_pool_t       *pool;
} ngx_http_tfs_json_gen_t;


ngx_http_tfs_json_gen_t *ngx_http_tfs_json_init(ngx_log_t *log,
    ngx_pool_t *pool);

void ngx_http_tfs_json_destroy(ngx_http_tfs_json_gen_t *tj_gen);

ngx_chain_t *ngx_http_tfs_json_custom_file_info(ngx_http_tfs_json_gen_t *tj_gen,
    ngx_http_tfs_custom_meta_info_t *info, uint8_t file_type);

ngx_chain_t *ngx_http_tfs_json_file_name(ngx_http_tfs_json_gen_t *tj_gen,
    ngx_str_t *file_name);

ngx_chain_t *ngx_http_tfs_json_raw_file_stat(ngx_http_tfs_json_gen_t *tj_gen,
    u_char *file_name, uint32_t block_id,
    ngx_http_tfs_raw_file_stat_t *file_stat);

ngx_chain_t * ngx_http_tfs_json_appid(ngx_http_tfs_json_gen_t *tj_gen,
    uint64_t app_id);
ngx_chain_t * ngx_http_tfs_json_file_hole_info(ngx_http_tfs_json_gen_t *tj_gen,
    ngx_array_t *file_holes);


#endif  /* _NGX_HTTP_TFS_JSON_H_INCLUDED_ */
