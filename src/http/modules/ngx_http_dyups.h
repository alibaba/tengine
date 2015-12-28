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


typedef ngx_int_t (*ngx_dyups_add_upstream_filter_pt)
    (ngx_http_upstream_main_conf_t *umcf, ngx_http_upstream_srv_conf_t *uscf);
typedef ngx_int_t (*ngx_dyups_del_upstream_filter_pt)
    (ngx_http_upstream_main_conf_t *umcf, ngx_http_upstream_srv_conf_t *uscf);


extern ngx_flag_t ngx_http_dyups_api_enable;
extern ngx_dyups_add_upstream_filter_pt ngx_dyups_add_upstream_top_filter;
extern ngx_dyups_del_upstream_filter_pt ngx_dyups_del_upstream_top_filter;

#endif
