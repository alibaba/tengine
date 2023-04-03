#ifndef _NGX_XUDP_H_INCLUDED_
#define _NGX_XUDP_H_INCLUDED_

#include <ngx_core.h>


/**
 * 获取当前进程的发送通道。
 * 自xudp2.0起，任意xudp监听的ls都可以被用作tx，该接口后续可以废弃。
 * */
ngx_listening_t *ngx_xudp_get_tx(void);


/**
 *  发送数据。
 *  @param push 是否需要立刻写入网卡
 *  @ls tx from `ngx_xudp_get_tx`
 * */
ssize_t ngx_xudp_sendmmsg(ngx_connection_t *c , struct iovec *msg_iov, unsigned int vlen,
                          const struct sockaddr *peer_addr, socklen_t peer_addrlen, int push);


/**
 * @param c
 * @return  whether the connection should use xudp for tx or not
 * */
static ngx_inline ngx_int_t
ngx_xudp_is_tx_enable(ngx_connection_t *c)
{
return !!c->xudp_tx;
}


/**
 * @param c
 * @return  disable connection for xudp tx
 * */
static ngx_inline void
ngx_xudp_disable_tx(ngx_connection_t *c)
{
    c->xudp_tx = 0 ;
    ngx_memory_barrier();
}


/**
 * @param c
 * @return  enable connection for xudp tx
 * */
void ngx_xudp_enable_tx(ngx_connection_t *c);

/**
 * @param
 * @return whether the error is fatal
 * */
ngx_int_t ngx_xudp_error_is_fatal(int error);

#endif