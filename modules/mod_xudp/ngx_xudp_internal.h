/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _NGX_XUDP_INTERNAL_H_INCLUDED_
#define _NGX_XUDP_INTERNAL_H_INCLUDED_

#include <xudp.h>
#include <ngx_core.h>
#include <ngx_event.h>


extern xudp         *ngx_xudp_engine;
extern xudp_conf    ngx_xudp_conf;

typedef struct ngx_xudp_port_map_node_s ngx_xudp_port_map_node_t;

struct ngx_xudp_port_map_node_s
{
    /* ngx_queue_t of listenr based on IP addr */
    ngx_radix_tree_t    *regular  ;

    /* wildcard listener */
    ngx_queue_t          wildcard ;
};

struct ngx_xudp_cycle_ctx_s
{
    /* mapping based on 16-bit port */
    ngx_radix_tree_t    *ports_map ;
    /* send listener */
    ngx_listening_t     *tx;
    /* group */
    xudp_group          *group;
};

struct ngx_xudp_channel_s
{
    /* read channel */
    xudp_channel    *ch ;
    /* force to flush buffer */
    ngx_event_t     commit;
};

struct ngx_xudp_conf_parser_s
{
#define NGX_XUDP_DEFAULT_XUDP_ADDR_SZ      10
    /* array for ngx_sockaddr_t */
    ngx_array_t        *ngx_xudp_addr_arr;
    /* temporary array for port string  */
    ngx_array_t        *ngx_xudp_temp_port_arr;
    /* */
    ngx_regex_t         *ngx_reg;
};

#if (T_NGX_XQUIC)

#include <xquic_xdp.h>

extern struct kern_xquic ngx_xudp_xquic_kern_cid_route_info;

#endif

#endif