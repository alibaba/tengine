/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef NGX_INGRESS_PROTOBUF_H
#define NGX_INGRESS_PROTOBUF_H

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_buf.h>
#include <ngx_comm_encrypt.h>

#include "ingress.pb-c.h"

typedef enum {
    NGX_INGRESS_SHARED_MEMORY_TYPE_EMPTY        = 0,
    NGX_INGRESS_SHARED_MEMORY_TYPE_SERVICE      = 1,
} ngx_ingress_shared_memory_type_e;

typedef enum {
    NGX_INGRESS_SHARED_MEMORY_TYPE_SUCCESS      = 0,
    NGX_INGRESS_SHARED_MEMORY_TYPE_ERR          = 1,
} ngx_ingress_shared_memory_status_e;

typedef struct {
    ngx_ingress_shared_memory_type_e     type;
    uint64_t                             version;
    u_char                               md5_digit[NGX_COMM_MD5_HEX_LEN];
    Ingress__Config                     *pbconfig;
} ngx_ingress_shared_memory_config_t;

typedef struct {
    ngx_uint_t      shm_size;
    int             shm_fd;
    u_char         *base_address;

    ngx_fd_t        lock_fd;
} ngx_ingress_shared_memory_t;

ngx_ingress_shared_memory_t *ngx_ingress_shared_memory_create(ngx_str_t *shm_name, ngx_uint_t shm_size, ngx_str_t *lock_file);
void ngx_ingress_shared_memory_free(ngx_ingress_shared_memory_t *shared);

ngx_int_t ngx_ingress_shared_memory_write_status(ngx_ingress_shared_memory_t *shared, ngx_ingress_shared_memory_status_e status);

typedef enum {
    ngx_ingress_pb_read_version = 1,
    ngx_ingress_pb_read_body = 2,
} ngx_ingress_pb_read_mode_e;

ngx_int_t ngx_ingress_shared_memory_read_pb(ngx_ingress_shared_memory_t *shared, ngx_ingress_shared_memory_config_t *shm_pb_config, ngx_ingress_pb_read_mode_e mode);
void ngx_ingress_shared_memory_free_pb(ngx_ingress_shared_memory_config_t *shm_pb_config);


#endif // NGX_INGRESS_PROTOBUF_H
