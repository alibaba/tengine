/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _NGX_XUDP_MODULE_H_INCLUDED_
#define _NGX_XUDP_MODULE_H_INCLUDED_

#include <ngx_config.h>
#include <ngx_core.h>

struct ngx_xudp_conf_s;
typedef struct ngx_xudp_conf_s ngx_xudp_conf_t;

struct ngx_xudp_conf_s
{
    /* xudp configure address */
    ngx_array_t      xudp_address;
    /* xudp core path */
    ngx_str_t        dispatcher_path;
    /* xudp is on */
    ngx_int_t        on;
    /* sndbuf */
    ngx_uint_t       sndnum;
    /* rcvbuf */
    ngx_uint_t       rcvnum;
    /* allow degrade ,default true */
    ngx_flag_t       allow_degrade;
    /* force xudp off */
    ngx_flag_t       no_xudp;
    /* force xudp tx off */
    ngx_flag_t       no_xudp_tx;
    /* interval waiting xudp load */
    ngx_msec_t       retries_interval;
    /* max count for retry xudp load */
    ngx_uint_t       max_retries;
};

#endif //_NGX_XUDP_MODULE_H_INCLUDED_