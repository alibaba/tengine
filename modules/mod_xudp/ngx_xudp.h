/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _NGX_XUDP_H_INCLUDED_
#define _NGX_XUDP_H_INCLUDED_

#include <ngx_core.h>


/**
 * get send channel of the worker
 * from xudp2.0, xudp listener can be use as tx
 * */
ngx_listening_t *ngx_xudp_get_tx(void);


/**
 *  send data
 *  @param push send data to NIC immediately
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