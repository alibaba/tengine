#ifndef NGX_HTTP_LUA_SOCKET_H
#define NGX_HTTP_LUA_SOCKET_H


#include "ngx_http_lua_common.h"

typedef struct ngx_http_lua_socket_upstream_s  ngx_http_lua_socket_upstream_t;


typedef
    int (*ngx_http_lua_socket_retval_handler)(ngx_http_request_t *r,
        ngx_http_lua_socket_upstream_t *u, lua_State *L);


typedef void (*ngx_http_lua_socket_upstream_handler_pt)(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);


typedef struct {
    ngx_http_lua_main_conf_t          *conf;
    ngx_uint_t                         active_connections;

    /* queues of ngx_http_lua_socket_pool_item_t: */
    ngx_queue_t                        cache;
    ngx_queue_t                        free;

    u_char                             key[1];

} ngx_http_lua_socket_pool_t;


struct ngx_http_lua_socket_upstream_s {
    ngx_http_lua_socket_retval_handler          prepare_retvals;
    ngx_http_lua_socket_upstream_handler_pt     read_event_handler;
    ngx_http_lua_socket_upstream_handler_pt     write_event_handler;

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

    ngx_output_chain_ctx_t           output;
    ngx_chain_writer_ctx_t           writer;

    ngx_int_t                      (*input_filter)(void *data, ssize_t bytes);
    void                            *input_filter_ctx;

    ssize_t                          recv_bytes;
    size_t                           request_len;
    ngx_chain_t                     *request_bufs;

    ngx_uint_t                       reused;

    unsigned                         request_sent:1;

    unsigned                         waiting:1;
    unsigned                         eof:1;
    unsigned                         is_downstream:1;
};


typedef struct ngx_http_lua_dfa_edge_s ngx_http_lua_dfa_edge_t;


struct ngx_http_lua_dfa_edge_s {
    u_char                           chr;
    int                              new_state;
    ngx_http_lua_dfa_edge_t         *next;
};


typedef struct {
    ngx_http_lua_socket_upstream_t      *upstream;

    ngx_str_t                            pattern;
    int                                  state;
    ngx_http_lua_dfa_edge_t            **recovering;
} ngx_http_lua_socket_compiled_pattern_t;


typedef struct {
    ngx_http_lua_socket_pool_t      *socket_pool;

    ngx_queue_t                      queue;
    ngx_connection_t                *connection;

    socklen_t                        socklen;
    struct sockaddr_storage          sockaddr;

    ngx_uint_t                       reused;

} ngx_http_lua_socket_pool_item_t;


void ngx_http_lua_inject_socket_api(ngx_log_t *log, lua_State *L);

void ngx_http_lua_inject_req_socket_api(lua_State *L);


#endif /* NGX_HTTP_LUA_SOCKET_H */

