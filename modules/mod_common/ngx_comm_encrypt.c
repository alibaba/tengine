
/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include "ngx_comm_encrypt.h"

#include <ngx_md5.h>

void
ngx_comm_md5_string(ngx_str_t *src, u_char md5_hex[])
{
    u_char          md5_binary[NGX_COMM_MD5_BIN_LEN];
    ngx_md5_t       md5;

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, src->data, src->len);
    ngx_md5_final(md5_binary, &md5);

    ngx_hex_dump(md5_hex, md5_binary, NGX_COMM_MD5_BIN_LEN);
}
