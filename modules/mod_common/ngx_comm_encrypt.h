/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef NGX_COMM_ENCRYPT_H
#define NGX_COMM_ENCRYPT_H

#include <ngx_core.h>

#define NGX_COMM_MD5_HEX_LEN         32
#define NGX_COMM_MD5_BIN_LEN         16

/**
 * @brief Calculate the md5 value of ngx_str_t
 * 
 * @param src_data source string
 * @param md5_hex Output md5, size must be NGX_COMM_MD5_HEX_LEN
 */
void
ngx_comm_md5_string(ngx_str_t *src, u_char md5_hex[]);

#endif // NGX_COMM_ENCRYPT_H
