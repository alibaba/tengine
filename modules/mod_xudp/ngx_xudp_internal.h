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
    // 基于IP地址的常规匹配的存放listenr的 ngx_queue_t
    ngx_radix_tree_t    *regular  ;

    // 存放通配的listener
    ngx_queue_t          wildcard ;
};

struct ngx_xudp_cycle_ctx_s
{
    // 基于16位端口的映射
    ngx_radix_tree_t    *ports_map ;
    // 发送监听器
    ngx_listening_t     *tx;
    // group
    xudp_group          *group;
};

struct ngx_xudp_channel_s
{
    //读取通道
    xudp_channel    *ch ;
    //强制刷新发送缓冲区。
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