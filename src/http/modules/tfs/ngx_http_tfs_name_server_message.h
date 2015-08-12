
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_NAME_SERVER_MESSAGE_H_INCLUDED_
#define _NGX_HTTP_TFS_NAME_SERVER_MESSAGE_H_INCLUDED_


#include <ngx_http_tfs.h>


ngx_chain_t *ngx_http_tfs_name_server_create_message(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_name_server_parse_message(ngx_http_tfs_t *t);
ngx_int_t ngx_http_tfs_select_name_server(ngx_http_tfs_t *t,
    ngx_http_tfs_rcs_info_t *rc_info, ngx_http_tfs_inet_t *addr,
    ngx_str_t *addr_text);


#endif  /* _NGX_HTTP_TFS_NAME_SERVER_MESSAGE_H_INCLUDED_ */
