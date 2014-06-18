
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_SERVER_HANDLER_H_INCLUDED_
#define _NGX_HTTP_TFS_SERVER_HANDLER_H_INCLUDED_


#include <ngx_http_tfs.h>


/* root server */
ngx_int_t ngx_http_tfs_create_rs_request(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_rs(ngx_http_tfs_t *t);


/* meta server */
ngx_int_t ngx_http_tfs_create_ms_request(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_ms_input_filter(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_ms(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_ms_ls_dir(ngx_http_tfs_t *t);


/* rc server */
ngx_int_t ngx_http_tfs_create_rcs_request(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_rcs(ngx_http_tfs_t *t);


/* name server */
ngx_int_t ngx_http_tfs_create_ns_request(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_ns(ngx_http_tfs_t *t);


/* data server */
ngx_int_t ngx_http_tfs_create_ds_request(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_ds_input_filter(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_ds(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_process_ds_read(ngx_http_tfs_t *t);

ngx_int_t ngx_http_tfs_retry_ds(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_retry_ns(ngx_http_tfs_t *t);


#endif  /* _NGX_HTTP_TFS_SERVER_HANDLER_H_INCLUDED_ */

