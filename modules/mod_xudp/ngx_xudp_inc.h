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
 * 解除当前进程和xdp的绑定关系，当调用后，该进程将无法通过xudp收到和发送任何数据。
 * xudp会自动释放和该进程关联的所有XDP socket和共享内存。
 * */
void ngx_xudp_terminate_xudp_binding(ngx_cycle_t *cycle);

#endif //