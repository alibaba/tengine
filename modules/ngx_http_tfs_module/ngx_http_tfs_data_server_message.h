
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_DATA_SERVER_MESSAGE_H_INCLUDED_
#define _NGX_HTTP_TFS_DATA_SERVER_MESSAGE_H_INCLUDED_


#include <ngx_http_tfs.h>


ngx_chain_t *ngx_http_tfs_data_server_create_message(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_data_server_parse_message(ngx_http_tfs_t *t);
ngx_http_tfs_inet_t *ngx_http_tfs_select_data_server(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data);

ngx_int_t ngx_http_tfs_get_meta_segment(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_set_meta_segment_data(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_parse_meta_segment(ngx_http_tfs_t *t, ngx_chain_t *data);
ngx_int_t ngx_http_tfs_get_segment_for_write(ngx_http_tfs_t *t);

ngx_int_t ngx_http_tfs_get_segment_for_read(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_get_segment_for_delete(ngx_http_tfs_t *t);

ngx_int_t ngx_http_tfs_fill_file_hole(ngx_http_tfs_t *t, size_t file_hole_size);
ngx_int_t ngx_http_tfs_check_file_hole(ngx_http_tfs_file_t *file,
    ngx_array_t *file_holes, ngx_log_t *log);


#endif  /* _NGX_HTTP_TFS_DATA_SERVER_MESSAGE_H_INCLUDED_ */
