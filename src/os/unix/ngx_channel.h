
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#ifndef _NGX_CHANNEL_H_INCLUDED_
#define _NGX_CHANNEL_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>


typedef struct ngx_channel_s  ngx_channel_t;

typedef ngx_int_t (*ngx_channel_rpc_pt)(ngx_channel_t *ch, void *data,
                                        ngx_log_t *log);

struct ngx_channel_s {
    ngx_uint_t           command;
    ngx_pid_t            pid;
    ngx_int_t            slot;
    ngx_fd_t             fd;
    ngx_channel_rpc_pt   rpc;
    size_t               len;
};


ngx_int_t ngx_write_channel(ngx_socket_t s, ngx_channel_t *ch, size_t size,
    ngx_log_t *log);
ngx_int_t ngx_read_channel(ngx_socket_t s, ngx_channel_t *ch, size_t size,
    ngx_log_t *log);
ngx_int_t ngx_add_channel_event(ngx_cycle_t *cycle, ngx_fd_t fd,
    ngx_int_t event, ngx_event_handler_pt handler);
void ngx_close_channel(ngx_fd_t *fd, ngx_log_t *log);


#endif /* _NGX_CHANNEL_H_INCLUDED_ */
