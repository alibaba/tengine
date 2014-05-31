
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_TAIR_HELPER_H_INCLUDED_
#define _NGX_HTTP_TFS_TAIR_HELPER_H_INCLUDED_


#include <ngx_tfs_common.h>
#ifdef NGX_HTTP_TFS_USE_TAIR
#include <ngx_http_etair_type.h>
#endif


typedef struct {
    uint32_t                          server_addr_hash;
    ngx_int_t                         area;

#ifdef NGX_HTTP_TFS_USE_TAIR
    ngx_http_etair_server_conf_t     *server;
#endif
} ngx_http_tfs_tair_instance_t;


typedef struct {
    ngx_str_t  server[NGX_HTTP_TFS_TAIR_SERVER_ADDR_PART_COUNT];
    ngx_int_t  area;
} ngx_http_tfs_tair_server_addr_info_t;


#ifndef NGX_HTTP_TFS_USE_TAIR

#define NGX_HTTP_TAIR_BYTEARRAY       9
#define NGX_HTTP_TAIR_INT             1
#define NGX_HTTP_ETAIR_SUCCESS        0


typedef struct {

    size_t                            len;
    u_char                           *data;

    ngx_uint_t                        type;
} ngx_http_tair_data_t;

typedef struct {
    ngx_http_tair_data_t              key;
    ngx_http_tair_data_t             *value;

    ngx_int_t                         version;
    ngx_int_t                         exptime;

    ngx_int_t                         rc;
} ngx_http_tair_key_value_t;

typedef void (*ngx_http_tair_handler_pt)(ngx_int_t rc, void *data);
typedef void (*ngx_http_tair_get_handler_pt)(ngx_http_tair_key_value_t *kv,
    ngx_int_t rc, void *data);
typedef void (*ngx_http_tair_mget_handler_pt)(ngx_array_t *kvs, ngx_int_t rc,
    void *data);

#endif

ngx_int_t ngx_http_tfs_tair_get_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_http_tair_data_t *key, ngx_http_tair_get_handler_pt callback,
    void *data);

ngx_int_t ngx_http_tfs_tair_mget_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_array_t *kvs, ngx_http_tair_mget_handler_pt callback, void *data);

ngx_int_t
ngx_http_tfs_tair_put_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_http_tair_data_t *key, ngx_http_tair_data_t *value,
    ngx_int_t expire, ngx_int_t version,
    ngx_http_tair_handler_pt callback, void *data);

ngx_int_t
ngx_http_tfs_tair_delete_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_array_t *keys, ngx_http_tair_handler_pt callback, void *data);

ngx_int_t
ngx_http_tfs_parse_tair_server_addr_info(
    ngx_http_tfs_tair_server_addr_info_t *info,
    u_char *addr, uint32_t len, void* pool, uint8_t shared_memory);



#endif  /* _NGX_HTTP_TFS_TAIR_HELPER_H_INCLUDED_ */
