/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_DYUPS_H_INCLUDE_
#define _NGX_HTTP_DYUPS_H_INCLUDE_


#include <ngx_config.h>
#include <ngx_core.h>


ngx_int_t ngx_dyups_update_upstream(ngx_str_t *name, ngx_buf_t *buf,
    ngx_str_t *rv);

ngx_int_t ngx_dyups_delete_upstream(ngx_str_t *name, ngx_str_t *rv);


extern ngx_flag_t ngx_http_dyups_api_enable;


#endif
