
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SOCKET_TCP_H_INCLUDED_
#define _NGX_HTTP_LUA_SOCKET_TCP_H_INCLUDED_


#include "ngx_http_lua_common.h"


#define NGX_HTTP_LUA_SOCKET_FT_ERROR         0x0001
#define NGX_HTTP_LUA_SOCKET_FT_TIMEOUT       0x0002
#define NGX_HTTP_LUA_SOCKET_FT_CLOSED        0x0004
#define NGX_HTTP_LUA_SOCKET_FT_RESOLVER      0x0008
#define NGX_HTTP_LUA_SOCKET_FT_BUFTOOSMALL   0x0010
#define NGX_HTTP_LUA_SOCKET_FT_NOMEM         0x0020
#define NGX_HTTP_LUA_SOCKET_FT_PARTIALWRITE  0x0040
#define NGX_HTTP_LUA_SOCKET_FT_CLIENTABORT   0x0080


typedef struct ngx_http_lua_socket_tcp_upstream_s
        ngx_http_lua_socket_tcp_upstream_t;


typedef
    int (*ngx_http_lua_socket_tcp_retval_handler)(ngx_http_request_t *r,
        ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);


typedef void (*ngx_http_lua_socket_tcp_upstream_handler_pt)(
          ngx_http_request_t *r, ngx_http_lua_socket_tcp_upstream_t *u);


typedef struct {
    lua_State                         *lua_vm;

    /* active connections == out-of-pool reused connections
     *                       + in-pool connections */
    ngx_uint_t                         active_connections;

    /* queues of ngx_http_lua_socket_pool_item_t: */
    ngx_queue_t                        cache;
    ngx_queue_t                        free;

    u_char                             key[1];

} ngx_http_lua_socket_pool_t;


struct ngx_http_lua_socket_tcp_upstream_s {
    ngx_http_lua_socket_tcp_retval_handler          prepare_retvals;
    ngx_http_lua_socket_tcp_upstream_handler_pt     read_event_handler;
    ngx_http_lua_socket_tcp_upstream_handler_pt     write_event_handler;

    ngx_http_lua_socket_pool_t      *socket_pool;

    ngx_http_lua_loc_conf_t         *conf;
    ngx_http_cleanup_pt             *cleanup;
    ngx_http_request_t              *request;
    ngx_peer_connection_t            peer;

    ngx_msec_t                       read_timeout;
    ngx_msec_t                       send_timeout;
    ngx_msec_t                       connect_timeout;

    ngx_http_upstream_resolved_t    *resolved;

    ngx_chain_t                     *bufs_in; /* input data buffers */
    ngx_chain_t                     *buf_in; /* last input data buffer */
    ngx_buf_t                        buffer; /* receive buffer */

    size_t                           length;
    size_t                           rest;

    ngx_uint_t                       ft_type;
    ngx_err_t                        socket_errno;

    ngx_int_t                      (*input_filter)(void *data, ssize_t bytes);
    void                            *input_filter_ctx;

    size_t                           request_len;
    ngx_chain_t                     *request_bufs;

    ngx_http_lua_co_ctx_t           *co_ctx;

    ngx_uint_t                       reused;

    unsigned                         no_close:1;
    unsigned                         waiting:1;
    unsigned                         eof:1;
    unsigned                         body_downstream:1;
    unsigned                         raw_downstream:1;
};


typedef struct ngx_http_lua_dfa_edge_s ngx_http_lua_dfa_edge_t;


struct ngx_http_lua_dfa_edge_s {
    u_char                           chr;
    int                              new_state;
    ngx_http_lua_dfa_edge_t         *next;
};


typedef struct {
    ngx_http_lua_socket_tcp_upstream_t  *upstream;

    ngx_str_t                            pattern;
    int                                  state;
    ngx_http_lua_dfa_edge_t            **recovering;

    unsigned                             inclusive:1;
} ngx_http_lua_socket_compiled_pattern_t;


typedef struct {
    ngx_http_lua_socket_pool_t      *socket_pool;

    ngx_queue_t                      queue;
    ngx_connection_t                *connection;

    socklen_t                        socklen;
    struct sockaddr_storage          sockaddr;

    ngx_uint_t                       reused;

} ngx_http_lua_socket_pool_item_t;


void ngx_http_lua_inject_socket_tcp_api(ngx_log_t *log, lua_State *L);
void ngx_http_lua_inject_req_socket_api(lua_State *L);


#endif /* _NGX_HTTP_LUA_SOCKET_TCP_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
