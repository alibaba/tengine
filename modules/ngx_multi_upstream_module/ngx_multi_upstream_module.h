
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */


#ifndef _NGX_MULTI_UPSTREAM_MODULE_H_
#define _NGX_MULTI_UPSTREAM_MODULE_H_

#define NGX_HTTP_UPSTREAM_HEADER_END         41
#define NGX_HTTP_UPSTREAM_GET_BODY_DATA      42
#define NGX_HTTP_UPSTREAM_PARSE_ERROR        43

#define NGX_MULTI_UPS_SUPPORT_MULTI     0x01
#define NGX_MULTI_UPS_NEED_MULTI        0x03

typedef ngx_int_t (*ngx_multi_upstream_handler_pt)(ngx_connection_t *pc);
typedef ngx_int_t (*ngx_multi_upstream_free_pt)(ngx_connection_t *pc, void *data);

typedef struct {
    ngx_connection_t    *connection;

    ngx_queue_t          data;          //front session or request list
    ngx_queue_t          send_list;     //backend request list sending
    ngx_queue_t          leak_list;     //backend request list sending but front close
    ngx_queue_t          waiting_list;  //waiting backend send block

    void                *data_c;

    ngx_flag_t           connected:1;

    void                *cur;
} ngx_multi_connection_t;

typedef struct {
    ngx_queue_t          queue;
    void                *data;
} ngx_multi_data_t;

typedef struct {
    ngx_queue_t          backend_queue;
    ngx_queue_t          front_queue;

    void                *data;

    ngx_uint_t           id;                    //id for multi

    ngx_pool_t          *pool;

    ngx_chain_t         *out;

    void                *ctx;
} ngx_multi_request_t;

typedef enum {
    NGX_FRONT_OK = 0,
    NGX_FRONT_PARSE_ERR = 1,
    NGX_FRONT_SEND_ERR = 2,
    NGX_BACKEND_PARSE_ERR = 3,
    NGX_BACKEND_SEND_ERR = 4
} ngx_multi_code_t; 

ngx_multi_connection_t* ngx_get_multi_connection(ngx_connection_t *c);
ngx_flag_t ngx_multi_connected(ngx_connection_t *c);

ngx_multi_connection_t* ngx_create_multi_connection(ngx_connection_t *c);

ngx_multi_request_t* ngx_create_multi_request(ngx_connection_t *c, void *data);

void ngx_multi_clean_leak(ngx_connection_t *c);

#endif /* _NGX_MULTI_UPSTREAM_MODULE_H_ */
