/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef _T_NGX_XQUIC_SEND_H_INCLUDED_
#define _T_NGX_XQUIC_SEND_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_event.h>
#include <ngx_http.h>
#if defined(__linux__)
#include <linux/version.h>
#endif

#if defined(LINUX_VERSION_CODE)
    #if LINUX_VERSION_CODE > KERNEL_VERSION(3,0,0)
        //The sendmmsg() system call was added in Linux 3.0.
        #define T_NGX_XQUIC_SUPPORT_SENDMMSG
    #endif
#endif

ssize_t ngx_xquic_server_send(const unsigned char *buf, size_t size,
    const struct sockaddr *peer_addr, socklen_t peer_addrlen, void *user_data);

#if defined(T_NGX_XQUIC_SUPPORT_SENDMMSG)
ssize_t ngx_xquic_server_send_mmsg(const struct iovec *msg_iov, unsigned int vlen,
    const struct sockaddr *peer_addr, socklen_t peer_addrlen, void *user_data);
#endif

void ngx_http_xquic_write_handler(ngx_event_t *wev);

#endif /* _T_NGX_XQUIC_SEND_H_INCLUDED_ */

