
/*
 * Copyright (C) by OpenResty Inc.
 */


#ifndef _NGX_HTTP_LUA_PIPE_H_INCLUDED_
#define _NGX_HTTP_LUA_PIPE_H_INCLUDED_


#include "ngx_http_lua_common.h"


typedef ngx_int_t (*ngx_http_lua_pipe_input_filter)(void *data, ssize_t bytes);


typedef struct {
    ngx_connection_t                   *c;
    ngx_http_lua_pipe_input_filter      input_filter;
    void                               *input_filter_ctx;
    size_t                              rest;
    ngx_chain_t                        *buf_in;
    ngx_chain_t                        *bufs_in;
    ngx_buf_t                           buffer;
    ngx_err_t                           pipe_errno;
    unsigned                            err_type:16;
    unsigned                            eof:1;
} ngx_http_lua_pipe_ctx_t;


typedef struct ngx_http_lua_pipe_s  ngx_http_lua_pipe_t;


typedef struct {
    ngx_pid_t               _pid;
    ngx_msec_t              write_timeout;
    ngx_msec_t              stdout_read_timeout;
    ngx_msec_t              stderr_read_timeout;
    ngx_msec_t              wait_timeout;
    /* pipe hides the implementation from the Lua binding */
    ngx_http_lua_pipe_t    *pipe;
} ngx_http_lua_ffi_pipe_proc_t;


typedef int (*ngx_http_lua_pipe_retval_handler)(
    ngx_http_lua_ffi_pipe_proc_t *proc, lua_State *L);


struct ngx_http_lua_pipe_s {
    ngx_pool_t                         *pool;
    ngx_chain_t                        *free_bufs;
    ngx_rbtree_node_t                  *node;
    int                                 stdin_fd;
    int                                 stdout_fd;
    int                                 stderr_fd;
    ngx_http_lua_pipe_ctx_t            *stdin_ctx;
    ngx_http_lua_pipe_ctx_t            *stdout_ctx;
    ngx_http_lua_pipe_ctx_t            *stderr_ctx;
    ngx_http_lua_pipe_retval_handler    retval_handler;
    ngx_http_cleanup_pt                *cleanup;
    ngx_http_request_t                 *r;
    size_t                              buffer_size;
    unsigned                            closed:1;
    unsigned                            dead:1;
    unsigned                            timeout:1;
    unsigned                            merge_stderr:1;
};


typedef struct {
    u_char                           color;
    u_char                           reason_code;
    int                              status;
    ngx_http_lua_co_ctx_t           *wait_co_ctx;
    ngx_http_lua_ffi_pipe_proc_t    *proc;
} ngx_http_lua_pipe_node_t;


typedef struct {
    int     signo;
    char   *signame;
} ngx_http_lua_pipe_signal_t;


#if !(NGX_WIN32) && defined(HAVE_SOCKET_CLOEXEC_PATCH)
#define HAVE_NGX_LUA_PIPE   1


void ngx_http_lua_pipe_init(void);
ngx_int_t ngx_http_lua_pipe_add_signal_handler(ngx_cycle_t *cycle);
#endif


#endif /* _NGX_HTTP_LUA_PIPE_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
