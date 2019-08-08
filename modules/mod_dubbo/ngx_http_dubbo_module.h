
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_DUBBO_H_
#define _NGX_HTTP_DUBBO_H_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_event_connect.h>

#include "ngx_dubbo.h"

typedef struct {
    ngx_queue_t              queue;

    uint64_t                 reqid;

    ngx_http_request_t      *r;

    ngx_buf_t               *buf;

    void                    *data;
} ngx_http_dubbo_request_t;


typedef struct {
    ngx_pool_t                     *pool;   /* response data */
    void                           *data;
    ngx_buf_t                       backend_buf;

    ngx_queue_t                     send_list;
    ngx_queue_t                     wait_list;
} ngx_http_dubbo_connection_t;

ngx_dubbo_connection_t* ngx_http_get_dubbo_connection(ngx_connection_t *pc);

ngx_int_t ngx_http_dubbo_parse(ngx_connection_t *c, ngx_chain_t *in);

#endif /* _NGX_HTTP_DUBBO_H_ */
