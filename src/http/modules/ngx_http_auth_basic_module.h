/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#ifndef _NGX_HTTP_AUTH_BASIC_H_INCLUDED_
#define _NGX_HTTP_AUTH_BASIC_H_INCLUDED_

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_http_complex_value_t  *realm;
    ngx_http_complex_value_t  *user_file;
} ngx_http_auth_basic_loc_conf_t;


ngx_int_t ngx_http_auth_basic_get_realm(ngx_http_request_t *r, ngx_str_t *realm);


#endif /* _NGX_HTTP_AUTH_BASIC_H_INCLUDED_ */