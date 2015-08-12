
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_SERIALIZATION_H_INCLUDED_
#define _NGX_HTTP_TFS_SERIALIZATION_H_INCLUDED_


#include <ngx_tfs_common.h>
#include <ngx_http_tfs_rc_server_info.h>

ngx_int_t ngx_http_tfs_serialize_string(u_char **p, ngx_str_t *string);

ngx_int_t ngx_http_tfs_deserialize_string(u_char **p, ngx_pool_t *pool,
    ngx_str_t *string);

//ngx_int_t ngx_http_tfs_serialize_vstring(u_char **p, ngx_str_t *string);

ngx_int_t ngx_http_tfs_deserialize_vstring(u_char **p, ngx_pool_t *pool,
    uint32_t *count, ngx_str_t **string);

// TODO:
//ngx_int_t ngx_http_tfs_serialize_bucket_meta_info(u_char **p,
//    ngx_http_tfs_bucket_meta_info_t *bucket_meta_info);
//
//ngx_int_t ngx_http_tfs_deserialize_bucket_meta_info(u_char **p,
//    ngx_http_tfs_bucket_meta_info_t *bucket_meta_info);
//
//ngx_int_t ngx_http_tfs_serialize_object_meta_info(u_char **p,
//    ngx_http_tfs_object_meta_info_t *object_meta_info);
//
//ngx_int_t ngx_http_tfs_deserialize_object_meta_info(u_char **p,
//    ngx_http_tfs_object_meta_info_t *object_meta_info);
//
//ngx_int_t ngx_http_tfs_serialize_tfs_file_info(u_char **p,
//    ngx_http_tfs_file_info_t *tfs_file_info);
//
//ngx_int_t ngx_http_tfs_deserialize_tfs_file_info(u_char **p,
//    ngx_http_tfs_file_info_t *tfs_file_info);
//
//ngx_int_t ngx_http_tfs_serialize_customize_info(u_char **p,
//    ngx_http_tfs_customize_info_t *customize_info);
//
//ngx_int_t ngx_http_tfs_deserialize_customize_info(u_char **p, ngx_pool_t *pool,
//    ngx_http_tfs_customize_info_t *customize_info);
//
//ngx_int_t ngx_http_tfs_serialize_object_info(u_char **p,
//    ngx_http_tfs_object_info_t *object_info);
//
//ngx_int_t ngx_http_tfs_deserialize_object_info(u_char **p, ngx_pool_t *pool,
//    ngx_http_tfs_object_info_t *object_info);
//
//ngx_int_t ngx_http_tfs_serialize_user_info(u_char **p,
//    ngx_http_tfs_user_info_t *user_info);
//
//ngx_int_t ngx_http_tfs_deserialize_kv_meta_table(u_char **p,
//    ngx_http_tfs_kv_meta_table_t *kv_meta_table);

ngx_int_t ngx_http_tfs_serialize_rcs_stat(u_char **p,
    ngx_http_tfs_rcs_info_t  *rc_info, ngx_int_t *count);

#endif   /* _NGX_HTTP_TFS_SERIALIZATION_H_INCLUDED_ */
