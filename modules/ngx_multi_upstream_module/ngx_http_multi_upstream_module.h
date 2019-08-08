
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_MULTI_UPSTREAM_MODULE_H_
#define _NGX_HTTP_MULTI_UPSTREAM_MODULE_H_

#include "ngx_multi_upstream_module.h"

typedef ngx_int_t (*ngx_http_multi_upstream_handler_pt)(ngx_connection_t *pc, ngx_http_request_t *r);

ngx_int_t ngx_http_multi_upstream_connection_detach(ngx_connection_t *c);
ngx_int_t ngx_http_multi_upstream_connection_close(ngx_connection_t *c);

ngx_flag_t ngx_http_multi_connection_fake(ngx_http_request_t *r);

#endif /* _NGX_HTTP_MULTI_UPSTREAM_MODULE_H_ */
