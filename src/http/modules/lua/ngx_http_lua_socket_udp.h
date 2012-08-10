#ifndef NGX_HTTP_LUA_SOCKET_UDP_H
#define NGX_HTTP_LUA_SOCKET_UDP_H


#include "ngx_http_lua_common.h"


typedef struct ngx_http_lua_socket_udp_upstream_s
        ngx_http_lua_socket_udp_upstream_t;


typedef
    int (*ngx_http_lua_socket_udp_retval_handler)(ngx_http_request_t *r,
        ngx_http_lua_socket_udp_upstream_t *u, lua_State *L);


typedef void (*ngx_http_lua_socket_udp_upstream_handler_pt)(
          ngx_http_request_t *r, ngx_http_lua_socket_udp_upstream_t *u);


struct ngx_http_lua_socket_udp_upstream_s {
    ngx_http_lua_socket_udp_retval_handler          prepare_retvals;
    ngx_http_lua_socket_udp_upstream_handler_pt     read_event_handler;

    ngx_http_lua_loc_conf_t         *conf;
    ngx_http_cleanup_pt             *cleanup;
    ngx_http_request_t              *request;
    ngx_udp_connection_t             udp_connection;

    ngx_msec_t                       read_timeout;

    ngx_http_upstream_resolved_t    *resolved;

    ngx_uint_t                       ft_type;
    ngx_err_t                        socket_errno;
    size_t                           received; /* for receive */
    size_t                           recv_buf_size;

    unsigned                         waiting:1;
};


void ngx_http_lua_inject_socket_udp_api(ngx_log_t *log, lua_State *L);


#endif /* NGX_HTTP_LUA_SOCKET_UDP_H */

