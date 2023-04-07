/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _NGX_XUDP_INC_H_INCLUDED_
#define _NGX_XUDP_INC_H_INCLUDED_

#ifndef _NGX_CORE_H_INCLUDED_
#error  "don't include this file directly, include <ngx_core.h> instead "
#endif

struct ngx_xudp_cycle_ctx_s;
typedef struct ngx_xudp_cycle_ctx_s ngx_xudp_cycle_ctx_t;

struct ngx_xudp_channel_s;
typedef struct ngx_xudp_channel_s ngx_xudp_channel_t;

struct ngx_xudp_conf_parser_s;
typedef struct ngx_xudp_conf_parser_s ngx_xudp_conf_parser_t;


/**
 * open xudp listening sockets
 * @return NGX_OK for success , other for error
 * */
ngx_int_t ngx_xudp_open_listening_sockets(ngx_cycle_t *cycle);


/**
 * release relationship between worker and xdp
 * worker will not send and recv traffic via xudp
 * xudp will release all the xdp socket and shm of the worker
 * */
void ngx_xudp_terminate_xudp_binding(ngx_cycle_t *cycle);

#endif