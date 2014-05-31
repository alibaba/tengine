
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_PEER_CONNECTION_INCLUDED_
#define _NGX_HTTP_TFS_PEER_CONNECTION_INCLUDED_


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_http_tfs.h>


struct ngx_http_tfs_peer_connection_s {
    ngx_peer_connection_t            peer;
    u_char                           peer_addr_text[24];
    ngx_buf_t                        body_buffer;
    ngx_pool_t                      *pool;
};


ngx_int_t ngx_http_tfs_peer_init(ngx_http_tfs_t *t);
ngx_http_tfs_peer_connection_t *ngx_http_tfs_select_peer(ngx_http_tfs_t *t);


#endif  /* _NGX_HTTP_TFS_PEER_CONNECTION_INCLUDED_ */
