/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


#define NGX_HTTP_PROXY_CONNECT_ESTABLISTHED     \
    "HTTP/1.1 200 Connection Established\r\n"   \
    "Proxy-agent: nginx\r\n\r\n"


typedef struct ngx_http_proxy_connect_upstream_s
    ngx_http_proxy_connect_upstream_t;
typedef struct ngx_http_proxy_connect_address_s
    ngx_http_proxy_connect_address_t;

typedef void (*ngx_http_proxy_connect_upstream_handler_pt)(
    ngx_http_request_t *r, ngx_http_proxy_connect_upstream_t *u);


typedef struct {
    ngx_flag_t                           accept_connect;
    ngx_flag_t                           allow_port_all;
    ngx_array_t                         *allow_ports;

    ngx_msec_t                           data_timeout;
    ngx_msec_t                           send_timeout;
    ngx_msec_t                           connect_timeout;

    size_t                               send_lowat;
    size_t                               buffer_size;

    ngx_http_complex_value_t            *address;
    ngx_http_proxy_connect_address_t    *local;

    ngx_http_complex_value_t            *response;
} ngx_http_proxy_connect_loc_conf_t;


typedef struct {
    ngx_msec_t                       resolve_time;
    ngx_msec_t                       connect_time;
    ngx_msec_t                       first_byte_time;

    /* TODO:
    off_t                            bytes_received;
    off_t                            bytes_sent;
    */
} ngx_http_proxy_connect_upstream_state_t;


struct ngx_http_proxy_connect_upstream_s {
    ngx_http_proxy_connect_loc_conf_t             *conf;

    ngx_http_proxy_connect_upstream_handler_pt     read_event_handler;
    ngx_http_proxy_connect_upstream_handler_pt     write_event_handler;

    ngx_peer_connection_t                          peer;

    ngx_http_request_t                            *request;

    ngx_http_upstream_resolved_t                  *resolved;

    ngx_buf_t                                      from_client;

    ngx_output_chain_ctx_t                         output;

    ngx_buf_t                                      buffer;

    /* 1: DNS resolving succeeded */
    ngx_flag_t                                     _resolved;

    /* 1: connection established */
    ngx_flag_t                                     connected;

    ngx_msec_t                                     start_time;

    ngx_http_proxy_connect_upstream_state_t        state;
};

struct ngx_http_proxy_connect_address_s {
    ngx_addr_t                      *addr;
    ngx_http_complex_value_t        *value;
#if (NGX_HAVE_TRANSPARENT_PROXY)
    ngx_uint_t                       transparent; /* unsigned  transparent:1; */
#endif
};

typedef struct {
    ngx_http_proxy_connect_upstream_t           *u;

    ngx_flag_t                      send_established;
    ngx_flag_t                      send_established_done;

    ngx_buf_t                       buf;    /* CONNECT response */

    ngx_msec_t                      connect_timeout;
    ngx_msec_t                      send_timeout;
    ngx_msec_t                      data_timeout;

} ngx_http_proxy_connect_ctx_t;


static ngx_int_t ngx_http_proxy_connect_init(ngx_conf_t *cf);
static ngx_int_t ngx_http_proxy_connect_add_variables(ngx_conf_t *cf);
static ngx_int_t ngx_http_proxy_connect_connect_addr_variable(
    ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static char *ngx_http_proxy_connect(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_proxy_connect_allow(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static void *ngx_http_proxy_connect_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_proxy_connect_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static void ngx_http_proxy_connect_write_downstream(ngx_http_request_t *r);
static void ngx_http_proxy_connect_read_downstream(ngx_http_request_t *r);
static void ngx_http_proxy_connect_send_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_proxy_connect_allow_handler(ngx_http_request_t *r,
    ngx_http_proxy_connect_loc_conf_t *plcf);
static char* ngx_http_proxy_connect_bind(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_proxy_connect_set_local(ngx_http_request_t *r,
  ngx_http_proxy_connect_upstream_t *u, ngx_http_proxy_connect_address_t *local);
static ngx_int_t ngx_http_proxy_connect_variable_get_time(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static void ngx_http_proxy_connect_variable_set_time(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_proxy_connect_resolve_time_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_proxy_connect_connect_time_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_proxy_connect_first_byte_time_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_proxy_connect_variable_get_response(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static void ngx_http_proxy_connect_variable_set_response(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);

static ngx_int_t ngx_http_proxy_connect_sock_ntop(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u);
static ngx_int_t ngx_http_proxy_connect_create_peer(ngx_http_request_t *r,
    ngx_http_upstream_resolved_t *ur);



static ngx_command_t  ngx_http_proxy_connect_commands[] = {

    { ngx_string("proxy_connect"),
      NGX_HTTP_SRV_CONF|NGX_CONF_NOARGS,
      ngx_http_proxy_connect,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, accept_connect),
      NULL },

    { ngx_string("proxy_connect_allow"),
      NGX_HTTP_SRV_CONF|NGX_CONF_1MORE,
      ngx_http_proxy_connect_allow,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("proxy_connect_data_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, data_timeout),
      NULL },

    { ngx_string("proxy_connect_read_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, data_timeout),
      NULL },

    { ngx_string("proxy_connect_send_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, send_timeout),
      NULL },

    { ngx_string("proxy_connect_connect_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, connect_timeout),
      NULL },

    { ngx_string("proxy_connect_send_lowat"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, send_lowat),
      NULL },

    { ngx_string("proxy_connect_address"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_set_complex_value_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, address),
      NULL },

    { ngx_string("proxy_connect_bind"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE12,
      ngx_http_proxy_connect_bind,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, local),
      NULL },

    { ngx_string("proxy_connect_response"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_set_complex_value_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_proxy_connect_loc_conf_t, response),
      NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_proxy_connect_module_ctx = {
    ngx_http_proxy_connect_add_variables,   /* preconfiguration */
    ngx_http_proxy_connect_init,            /* postconfiguration */

    NULL,                                   /* create main configuration */
    NULL,                                   /* init main configuration */

    NULL,                                   /* create server configuration */
    NULL,                                   /* merge server configuration */

    ngx_http_proxy_connect_create_loc_conf, /* create location configuration */
    ngx_http_proxy_connect_merge_loc_conf   /* merge location configuration */
};


ngx_module_t  ngx_http_proxy_connect_module = {
    NGX_MODULE_V1,
    &ngx_http_proxy_connect_module_ctx,     /* module context */
    ngx_http_proxy_connect_commands,        /* module directives */
    NGX_HTTP_MODULE,                        /* module type */
    NULL,                                   /* init master */
    NULL,                                   /* init module */
    NULL,                                   /* init process */
    NULL,                                   /* init thread */
    NULL,                                   /* exit thread */
    NULL,                                   /* exit process */
    NULL,                                   /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_variable_t  ngx_http_proxy_connect_vars[] = {

    { ngx_string("connect_addr"), NULL,
      ngx_http_proxy_connect_connect_addr_variable,
      0, NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("proxy_connect_connect_timeout"),
      ngx_http_proxy_connect_variable_set_time,
      ngx_http_proxy_connect_variable_get_time,
      offsetof(ngx_http_proxy_connect_ctx_t, connect_timeout),
      NGX_HTTP_VAR_NOCACHEABLE|NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_string("proxy_connect_data_timeout"),
      ngx_http_proxy_connect_variable_set_time,
      ngx_http_proxy_connect_variable_get_time,
      offsetof(ngx_http_proxy_connect_ctx_t, data_timeout),
      NGX_HTTP_VAR_NOCACHEABLE|NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_string("proxy_connect_read_timeout"),
      ngx_http_proxy_connect_variable_set_time,
      ngx_http_proxy_connect_variable_get_time,
      offsetof(ngx_http_proxy_connect_ctx_t, data_timeout),
      NGX_HTTP_VAR_NOCACHEABLE|NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_string("proxy_connect_send_timeout"),
      ngx_http_proxy_connect_variable_set_time,
      ngx_http_proxy_connect_variable_get_time,
      offsetof(ngx_http_proxy_connect_ctx_t, send_timeout),
      NGX_HTTP_VAR_NOCACHEABLE|NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_string("proxy_connect_resolve_time"), NULL,
      ngx_http_proxy_connect_resolve_time_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("proxy_connect_connect_time"), NULL,
      ngx_http_proxy_connect_connect_time_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("proxy_connect_first_byte_time"), NULL,
      ngx_http_proxy_connect_first_byte_time_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("proxy_connect_response"),
      ngx_http_proxy_connect_variable_set_response,
      ngx_http_proxy_connect_variable_get_response,
      offsetof(ngx_http_proxy_connect_ctx_t, buf),
      NGX_HTTP_VAR_NOCACHEABLE|NGX_HTTP_VAR_CHANGEABLE, 0 },

    { ngx_null_string, NULL, NULL, 0, 0, 0 }
};


#if 1

#if defined(nginx_version) && nginx_version >= 1005008
#define __ngx_sock_ntop ngx_sock_ntop
#else
#define __ngx_sock_ntop(sa, slen, p, len, port) ngx_sock_ntop(sa, p, len, port)
#endif

/*
 * #if defined(nginx_version) && nginx_version <= 1009015
 *
 * from src/core/ngx_inet.c: ngx_inet_set_port & ngx_parse_addr_port
 *
 * redefined to __ngx_inet_set_port & __ngx_parse_addr_port to
 * avoid too many `#if nginx_version > ...` macro
 */
static void
__ngx_inet_set_port(struct sockaddr *sa, in_port_t port)
{
    struct sockaddr_in   *sin;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6  *sin6;
#endif

    switch (sa->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:
        sin6 = (struct sockaddr_in6 *) sa;
        sin6->sin6_port = htons(port);
        break;
#endif

#if (NGX_HAVE_UNIX_DOMAIN)
    case AF_UNIX:
        break;
#endif

    default: /* AF_INET */
        sin = (struct sockaddr_in *) sa;
        sin->sin_port = htons(port);
        break;
    }
}


static ngx_int_t
__ngx_parse_addr_port(ngx_pool_t *pool, ngx_addr_t *addr, u_char *text,
    size_t len)
{
    u_char     *p, *last;
    size_t      plen;
    ngx_int_t   rc, port;

    rc = ngx_parse_addr(pool, addr, text, len);

    if (rc != NGX_DECLINED) {
        return rc;
    }

    last = text + len;

#if (NGX_HAVE_INET6)
    if (len && text[0] == '[') {

        p = ngx_strlchr(text, last, ']');

        if (p == NULL || p == last - 1 || *++p != ':') {
            return NGX_DECLINED;
        }

        text++;
        len -= 2;

    } else
#endif

    {
        p = ngx_strlchr(text, last, ':');

        if (p == NULL) {
            return NGX_DECLINED;
        }
    }

    p++;
    plen = last - p;

    port = ngx_atoi(p, plen);

    if (port < 1 || port > 65535) {
        return NGX_DECLINED;
    }

    len -= plen + 1;

    rc = ngx_parse_addr(pool, addr, text, len);

    if (rc != NGX_OK) {
        return rc;
    }

    __ngx_inet_set_port(addr->sockaddr, (in_port_t) port);

    return NGX_OK;
}

#endif


static ngx_int_t
ngx_http_proxy_connect_get_peer(ngx_peer_connection_t *pc, void *data)
{
    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_test_connect(ngx_connection_t *c)
{
    int        err;
    socklen_t  len;

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT)  {
        if (c->write->pending_eof || c->read->pending_eof) {
            if (c->write->pending_eof) {
                err = c->write->kq_errno;

            } else {
                err = c->read->kq_errno;
            }

            c->log->action = "connecting to upstream";
            (void) ngx_connection_error(c, err,
                              "proxy_connet: upstream connect failed (kevent)");
            return NGX_ERROR;
        }

    } else
#endif
    {
        err = 0;
        len = sizeof(int);

        /*
         * BSDs and Linux return 0 and set a pending error in err
         * Solaris returns -1 and sets errno
         */

        if (getsockopt(c->fd, SOL_SOCKET, SO_ERROR, (void *) &err, &len)
            == -1)
        {
            err = ngx_errno;
        }

        if (err) {
            c->log->action = "connecting to upstream";
            (void) ngx_connection_error(c, err,
                                      "proxy_connect: upstream connect failed");
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static void
ngx_http_proxy_connect_finalize_request(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u, ngx_int_t rc)
{
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect: finalize upstream request: %i", rc);

    r->keepalive = 0;

    if (u->resolved && u->resolved->ctx) {
        ngx_resolve_name_done(u->resolved->ctx);
        u->resolved->ctx = NULL;
    }

    if (u->peer.free && u->peer.sockaddr) {
        u->peer.free(&u->peer, u->peer.data, 0);
        u->peer.sockaddr = NULL;
    }

    if (u->peer.connection) {

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "proxy_connect: close upstream connection: %d",
                       u->peer.connection->fd);

        if (u->peer.connection->pool) {
            ngx_destroy_pool(u->peer.connection->pool);
        }

        ngx_close_connection(u->peer.connection);
    }

    u->peer.connection = NULL;

    if (rc == NGX_DECLINED) {
        return;
    }

    r->connection->log->action = "sending to client";

    if (rc == NGX_HTTP_REQUEST_TIME_OUT
        || rc == NGX_HTTP_CLIENT_CLOSED_REQUEST)
    {
        ngx_http_finalize_request(r, rc);
        return;
    }

    if (u->connected && rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        rc = NGX_ERROR;
    }

    ngx_http_finalize_request(r, rc);
}


static void
ngx_http_proxy_connect_send_connection_established(ngx_http_request_t *r)
{
    ngx_int_t                              n;
    ngx_buf_t                             *b;
    ngx_connection_t                      *c;
    ngx_http_core_loc_conf_t              *clcf;
    ngx_http_proxy_connect_upstream_t     *u;
    ngx_http_proxy_connect_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);
    c = r->connection;
    u = ctx->u;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect: send 200 connection established");

    u->connected = 1;

    if (u->state.connect_time == (ngx_msec_t) -1) {
        u->state.connect_time = ngx_current_msec - u->start_time;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    b = &ctx->buf;

    /* modify CONNECT response via proxy_connect_response directive */
    {
    ngx_str_t                               resp;
    ngx_http_proxy_connect_loc_conf_t      *plcf;

    plcf = ngx_http_get_module_loc_conf(r, ngx_http_proxy_connect_module);

    if (plcf->response
        && ngx_http_complex_value(r, plcf->response, &resp) == NGX_OK)
    {
        if (resp.len > 0) {
            b->pos = resp.data;
            b->last = b->pos + resp.len;
        }
    }
    }

    ctx->send_established = 1;

    for (;;) {
        n = c->send(c, b->pos, b->last - b->pos);

        if (n >= 0) {

            r->headers_out.status = 200;    /* fixed that $status is 000 */

            b->pos += n;

            if (b->pos == b->last) {
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                              "proxy_connect: sent 200 connection established");

                if (c->write->timer_set) {
                    ngx_del_timer(c->write);
                }

                ctx->send_established_done = 1;

                r->write_event_handler =
                                        ngx_http_proxy_connect_write_downstream;
                r->read_event_handler = ngx_http_proxy_connect_read_downstream;

                if (ngx_handle_write_event(c->write, clcf->send_lowat)
                    != NGX_OK)
                {
                    ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
                    return;
                }

                if (r->header_in->last > r->header_in->pos || c->read->ready) {
                    r->read_event_handler(r);
                    return;
                }

                return;
            }

            /* keep sending more data */
            continue;
        }

        /* NGX_ERROR || NGX_AGAIN */
        break;
    }

    if (n == NGX_ERROR) {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
        return;
    }

    /* n == NGX_AGAIN */

    r->write_event_handler = ngx_http_proxy_connect_send_handler;

    ngx_add_timer(c->write, ctx->data_timeout);

    if (ngx_handle_write_event(c->write, clcf->send_lowat) != NGX_OK) {
        ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    return;
}


static void
ngx_http_proxy_connect_tunnel(ngx_http_request_t *r,
    ngx_uint_t from_upstream, ngx_uint_t do_write)
{
    char                               *recv_action, *send_action;
    size_t                              size;
    ssize_t                             n;
    ngx_buf_t                          *b;
    ngx_uint_t                          flags;
    ngx_connection_t                   *c, *pc, *dst, *src;
    ngx_http_proxy_connect_ctx_t       *ctx;
    ngx_http_proxy_connect_upstream_t  *u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    c = r->connection;
    u = ctx->u;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "proxy_connect: tunnel fu:%ui write:%ui",
                   from_upstream, do_write);

    pc = u->peer.connection;

    if (from_upstream) {
        src = pc;
        dst = c;
        b = &u->buffer;
        recv_action = "proxying and reading from upstream";
        send_action = "proxying and sending to client";

    } else {
        src = c;
        dst = pc;
        b = &u->from_client;

        if (r->header_in->last > r->header_in->pos) {
            b = r->header_in;
            b->end = b->last;
            do_write = 1;
        }

        if (b->start == NULL) {
            b->start = ngx_palloc(r->pool, u->conf->buffer_size);
            if (b->start == NULL) {
                ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
                return;
            }

            b->pos = b->start;
            b->last = b->start;
            b->end = b->start + u->conf->buffer_size;
            b->temporary = 1;
        }
        recv_action = "proxying and reading from client";
        send_action = "proxying and sending to upstream";
    }

    for ( ;; ) {

        if (do_write) {

            size = b->last - b->pos;

            if (size && dst->write->ready) {
                c->log->action = send_action;

                n = dst->send(dst, b->pos, size);

                if (n == NGX_AGAIN) {
                    break;
                }

                if (n == NGX_ERROR) {
                    ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
                    return;
                }

                if (n > 0) {
                    b->pos += n;

                    if (b->pos == b->last) {
                        b->pos = b->start;
                        b->last = b->start;
                    }
                }
            }
        }

        size = b->end - b->last;

        if (size && src->read->ready) {

            c->log->action = recv_action;

            n = src->recv(src, b->last, size);

            if (n == NGX_AGAIN || n == 0) {
                break;
            }

            if (n > 0) {
                do_write = 1;
                b->last += n;

                if (from_upstream) {
                    if (u->state.first_byte_time == (ngx_msec_t) -1) {
                        u->state.first_byte_time = ngx_current_msec
                            - u->start_time;
                    }
                }

                continue;
            }

            if (n == NGX_ERROR) {
                src->read->eof = 1;
            }
        }

        break;
    }

    c->log->action = "proxying connection";

    /* test finalize */

    if ((pc->read->eof && u->buffer.pos == u->buffer.last)
        || (c->read->eof && u->from_client.pos == u->from_client.last)
        || (c->read->eof && pc->read->eof))
    {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "proxy_connect: tunnel done");
        ngx_http_proxy_connect_finalize_request(r, u, 0);
        return;
    }

    flags = src->read->eof ? NGX_CLOSE_EVENT : 0;

    if (ngx_handle_read_event(src->read, flags) != NGX_OK) {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
        return;
    }

    if (dst) {
        if (ngx_handle_write_event(dst->write, 0) != NGX_OK) {
            ngx_http_proxy_connect_finalize_request(r, u, NGX_ERROR);
            return;
        }

        if (!c->read->delayed && !pc->read->delayed) {
            ngx_add_timer(c->write, ctx->data_timeout);

        } else if (c->write->timer_set) {
            ngx_del_timer(c->write);
        }
    }
}


static void
ngx_http_proxy_connect_read_downstream(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_ctx_t       *ctx;


    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy connect read downstream");

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (r->connection->read->timedout) {
        r->connection->timedout = 1;
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: client read timed out");
        ngx_http_proxy_connect_finalize_request(r, ctx->u,
                                                NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    ngx_http_proxy_connect_tunnel(r, 0, 0);
}


static void
ngx_http_proxy_connect_write_downstream(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_ctx_t       *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy connect write downstream");

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (r->connection->write->timedout) {
        r->connection->timedout = 1;
        ngx_connection_error(r->connection, NGX_ETIMEDOUT,
                             "proxy_connect: connection timed out");
        ngx_http_proxy_connect_finalize_request(r, ctx->u,
                                                NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    ngx_http_proxy_connect_tunnel(r, 1, 1);
}


static void
ngx_http_proxy_connect_read_upstream(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u)
{
    ngx_connection_t                    *c;
    ngx_http_proxy_connect_ctx_t        *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect: upstream read handler");

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    c = u->peer.connection;

    if (c->read->timedout) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "proxy_connect: upstream read timed out (peer:%V)",
                      u->peer.name);
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_GATEWAY_TIME_OUT);
        return;
    }

    if (!ctx->send_established &&
        ngx_http_proxy_connect_test_connect(c) != NGX_OK)
    {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        return;
    }

    if (u->buffer.start == NULL) {
        u->buffer.start = ngx_palloc(r->pool, u->conf->buffer_size);
        if (u->buffer.start == NULL) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        u->buffer.pos = u->buffer.start;
        u->buffer.last = u->buffer.start;
        u->buffer.end = u->buffer.start + u->conf->buffer_size;
        u->buffer.temporary = 1;
    }

    if (!ctx->send_established_done) {
        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        return;
    }

    ngx_http_proxy_connect_tunnel(r, 1, 0);
}


static void
ngx_http_proxy_connect_write_upstream(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u)
{
    ngx_connection_t  *c;
    ngx_http_proxy_connect_ctx_t          *ctx;

    c = u->peer.connection;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect: upstream write handler %s",
                   u->connected ? "" : "(connect)");

    if (c->write->timedout) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "proxy_connect: upstream %s timed out (peer:%V)",
                      u->connected ? "write" : "connect", u->peer.name);
        ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_GATEWAY_TIME_OUT);
        return;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    if (!ctx->send_established &&
        ngx_http_proxy_connect_test_connect(c) != NGX_OK)
    {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        return;
    }

    if (!ctx->send_established) {
        ngx_http_proxy_connect_send_connection_established(r);
        return;
    }

    if (!ctx->send_established_done) {
        if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        return;
    }

    ngx_http_proxy_connect_tunnel(r, 0, 1);
}


static void
ngx_http_proxy_connect_send_handler(ngx_http_request_t *r)
{
    ngx_connection_t                 *c;
    ngx_http_proxy_connect_ctx_t     *ctx;

    c = r->connection;
    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect: send connection established handler");

    if (c->write->timedout) {
        c->timedout = 1;
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "proxy_connect: client write timed out");
        ngx_http_proxy_connect_finalize_request(r, ctx->u,
                                                NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    if (ctx->buf.pos != ctx->buf.last) {
        ngx_http_proxy_connect_send_connection_established(r);
    }
}


static void
ngx_http_proxy_connect_upstream_handler(ngx_event_t *ev)
{
    ngx_connection_t                    *c;
    ngx_http_request_t                  *r;
    ngx_http_log_ctx_t                  *lctx;
    ngx_http_proxy_connect_upstream_t   *u;

    c = ev->data;
    u = c->data;

    r = u->request;
    c = r->connection;

    lctx = c->log->data;
    lctx->current_request = r;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "proxy_connect: upstream handler: \"%V:%V\"",
                   &r->connect_host, &r->connect_port);

    if (ev->write) {
        u->write_event_handler(r, u);

    } else {
        u->read_event_handler(r, u);
    }

    ngx_http_run_posted_requests(c);
}


static void
ngx_http_proxy_connect_process_connect(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u)
{
    ngx_int_t                        rc;
    ngx_connection_t                *c;
    ngx_peer_connection_t           *pc;
    ngx_http_upstream_resolved_t    *ur;
    ngx_http_proxy_connect_ctx_t    *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    r->connection->log->action = "connecting to upstream";

    if (ngx_http_proxy_connect_set_local(r, u, u->conf->local) != NGX_OK) {
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    pc = &u->peer;
    ur = u->resolved;

    pc->sockaddr = ur->sockaddr;
    pc->socklen = ur->socklen;
    pc->name = &ur->host;

    pc->get = ngx_http_proxy_connect_get_peer;

    u->start_time = ngx_current_msec;
    u->state.connect_time = (ngx_msec_t) -1;
    u->state.first_byte_time = (ngx_msec_t) -1;

    rc = ngx_event_connect_peer(&u->peer);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect: ngx_event_connect_peer() returns %i", rc);

    /*
     * We do not retry next upstream if current connecting fails.
     * So there is no ngx_http_proxy_connect_upstream_next() function
     */

    if (rc == NGX_ERROR) {
        ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    if (rc == NGX_BUSY) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: no live connection");
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        return;
    }

    if (rc == NGX_DECLINED) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: connection error");
        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        return;
    }

    /* rc == NGX_OK || rc == NGX_AGAIN || rc == NGX_DONE */

    c = pc->connection;

    c->data = u;

    c->write->handler = ngx_http_proxy_connect_upstream_handler;
    c->read->handler = ngx_http_proxy_connect_upstream_handler;

    u->write_event_handler = ngx_http_proxy_connect_write_upstream;
    u->read_event_handler = ngx_http_proxy_connect_read_upstream;

    c->sendfile &= r->connection->sendfile;
    c->log = r->connection->log;

    if (c->pool == NULL) {

        c->pool = ngx_create_pool(128, r->connection->log);
        if (c->pool == NULL) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }
    }

    c->pool->log = c->log;
    c->read->log = c->log;
    c->write->log = c->log;

    if (rc == NGX_AGAIN) {
        ngx_add_timer(c->write, ctx->connect_timeout);
        return;
    }

    ngx_http_proxy_connect_send_connection_established(r);
}


static void
ngx_http_proxy_connect_resolve_handler(ngx_resolver_ctx_t *ctx)
{
    ngx_connection_t                            *c;
    ngx_http_request_t                          *r;
    ngx_http_upstream_resolved_t                *ur;
    ngx_http_proxy_connect_upstream_t           *u;

#if defined(nginx_version) && nginx_version >= 1013002
    ngx_uint_t run_posted = ctx->async;
#endif

    u = ctx->data;
    r = u->request;
    ur = u->resolved;
    c = r->connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect: resolve handler");

    if (ctx->state) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: %V could not be resolved (%i: %s)",
                      &ctx->name, ctx->state,
                      ngx_resolver_strerror(ctx->state));

        ngx_http_proxy_connect_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
        goto failed;
    }

    ur->naddrs = ctx->naddrs;
    ur->addrs = ctx->addrs;

#if (NGX_DEBUG)
    {
#   if defined(nginx_version) && nginx_version >= 1005008
    ngx_uint_t  i;
    ngx_str_t   addr;
    u_char      text[NGX_SOCKADDR_STRLEN];

    addr.data = text;

    for (i = 0; i < ctx->naddrs; i++) {
        addr.len = ngx_sock_ntop(ur->addrs[i].sockaddr, ur->addrs[i].socklen,
                                 text, NGX_SOCKADDR_STRLEN, 0);

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "proxy_connect: name was resolved to %V", &addr);
    }
#   else
    ngx_uint_t  i;
    in_addr_t   addr;

    for (i = 0; i < ctx->naddrs; i++) {
        addr = ntohl(ctx->addrs[i]);

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "proxy_connect: name was resolved to %ud.%ud.%ud.%ud",
                       (addr >> 24) & 0xff, (addr >> 16) & 0xff,
                       (addr >> 8) & 0xff, addr & 0xff);
    }
#   endif
    }
#endif

    if (ngx_http_proxy_connect_create_peer(r, ur) != NGX_OK) {
        ngx_http_proxy_connect_finalize_request(r, u,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
        goto failed;
    }

    ngx_resolve_name_done(ctx);
    ur->ctx = NULL;

    u->_resolved = 1;

    if (u->state.resolve_time == (ngx_msec_t) -1) {
        u->state.resolve_time = ngx_current_msec - u->start_time;
    }

    ngx_http_proxy_connect_process_connect(r, u);

failed:

#if defined(nginx_version) && nginx_version >= 1013002
    if (run_posted) {
        ngx_http_run_posted_requests(c);
    }
#else
    ngx_http_run_posted_requests(c);
#endif
}


static ngx_int_t
ngx_http_proxy_connect_create_peer(ngx_http_request_t *r,
    ngx_http_upstream_resolved_t *ur)
{
    u_char                                      *p;
    ngx_int_t                                    i, len;
    socklen_t                                    socklen;
    struct sockaddr                             *sockaddr;

    i = ngx_random() % ur->naddrs;  /* i<-0 for ur->naddrs == 1 */

#if defined(nginx_version) && nginx_version >= 1005008

    socklen = ur->addrs[i].socklen;

    sockaddr = ngx_palloc(r->pool, socklen);
    if (sockaddr == NULL) {
        return NGX_ERROR;
    }

    ngx_memcpy(sockaddr, ur->addrs[i].sockaddr, socklen);

    switch (sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
    case AF_INET6:
        ((struct sockaddr_in6 *) sockaddr)->sin6_port = htons(ur->port);
        break;
#endif
    default: /* AF_INET */
        ((struct sockaddr_in *) sockaddr)->sin_port = htons(ur->port);
    }

#else
    /* for nginx older than 1.5.8 */

    socklen = sizeof(struct sockaddr_in);

    sockaddr = ngx_pcalloc(r->pool, socklen);
    if (sockaddr == NULL) {
        return NGX_ERROR;
    }

    ((struct sockaddr_in *) sockaddr)->sin_family = AF_INET;
    ((struct sockaddr_in *) sockaddr)->sin_addr.s_addr = ur->addrs[i];
    ((struct sockaddr_in *) sockaddr)->sin_port = htons(ur->port);

#endif

    p = ngx_pnalloc(r->pool, NGX_SOCKADDR_STRLEN);
    if (p == NULL) {
        return NGX_ERROR;
    }

    len = __ngx_sock_ntop(sockaddr, socklen, p, NGX_SOCKADDR_STRLEN, 1);

    ur->sockaddr = sockaddr;
    ur->socklen = socklen;

    ur->host.data = p;
    ur->host.len = len;
    ur->naddrs = 1;

    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_upstream_create(ngx_http_request_t *r,
    ngx_http_proxy_connect_ctx_t *ctx)
{
    ngx_http_proxy_connect_upstream_t       *u;

    u = ngx_pcalloc(r->pool, sizeof(ngx_http_proxy_connect_upstream_t));
    if (u == NULL) {
        return NGX_ERROR;
    }

    ctx->u = u;

    u->peer.log = r->connection->log;
    u->peer.log_error = NGX_ERROR_ERR;

    u->request = r;

    return NGX_OK;
}


static void
ngx_http_proxy_connect_check_broken_connection(ngx_http_request_t *r,
    ngx_event_t *ev)
{
    int                                 n;
    char                                buf[1];
    ngx_err_t                           err;
    ngx_int_t                           event;
    ngx_connection_t                   *c;
    ngx_http_proxy_connect_ctx_t       *ctx;
    ngx_http_proxy_connect_upstream_t  *u;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "proxy_connect: check client, write event:%d, \"%V:%V\"",
                   ev->write, &r->connect_host, &r->connect_port);

    c = r->connection;
    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);
    u = ctx->u;

    if (c->error) {
        if ((ngx_event_flags & NGX_USE_LEVEL_EVENT) && ev->active) {

            event = ev->write ? NGX_WRITE_EVENT : NGX_READ_EVENT;

            if (ngx_del_event(ev, event, 0) != NGX_OK) {
                ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
                return;
            }
        }

        ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_CLIENT_CLOSED_REQUEST);

        return;
    }

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT) {

        if (!ev->pending_eof) {
            return;
        }

        ev->eof = 1;
        c->error = 1;

        if (ev->kq_errno) {
            ev->error = 1;
        }

        if (u->peer.connection) {
            ngx_log_error(NGX_LOG_INFO, ev->log, ev->kq_errno,
                          "proxy_connect: kevent() reported that client "
                          "prematurely closed connection, so upstream "
                          " connection is closed too");
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_CLIENT_CLOSED_REQUEST);
            return;
        }

        ngx_log_error(NGX_LOG_INFO, ev->log, ev->kq_errno,
                      "proxy_connect: kevent() reported that client "
                      "prematurely closed connection");

        if (u->peer.connection == NULL) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_CLIENT_CLOSED_REQUEST);
        }

        return;
    }

#endif

    n = recv(c->fd, buf, 1, MSG_PEEK);

    err = ngx_socket_errno;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ev->log, err,
                   "proxy_connect: client recv(): %d", n);

    if (ev->write && (n >= 0 || err == NGX_EAGAIN)) {
        return;
    }

    if ((ngx_event_flags & NGX_USE_LEVEL_EVENT) && ev->active) {

        event = ev->write ? NGX_WRITE_EVENT : NGX_READ_EVENT;

        if (ngx_del_event(ev, event, 0) != NGX_OK) {
            ngx_http_proxy_connect_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }
    }

    if (n > 0) {
        return;
    }

    if (n == -1) {
        if (err == NGX_EAGAIN) {
            return;
        }

        ev->error = 1;

    } else { /* n == 0 */
        err = 0;
    }

    ev->eof = 1;
    c->error = 1;

    if (u->peer.connection) {
        ngx_log_error(NGX_LOG_INFO, ev->log, err,
                      "proxy_connect: client prematurely closed connection, "
                      "so upstream connection is closed too");
        ngx_http_proxy_connect_finalize_request(r, u,
                                           NGX_HTTP_CLIENT_CLOSED_REQUEST);
        return;
    }

    ngx_log_error(NGX_LOG_INFO, ev->log, err,
                  "proxy_connect: client prematurely closed connection");

    if (u->peer.connection == NULL) {
        ngx_http_proxy_connect_finalize_request(r, u,
                                           NGX_HTTP_CLIENT_CLOSED_REQUEST);
    }
}


static void
ngx_http_proxy_connect_rd_check_broken_connection(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_check_broken_connection(r, r->connection->read);
}


static void
ngx_http_proxy_connect_wr_check_broken_connection(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_check_broken_connection(r, r->connection->write);
}


static ngx_int_t
ngx_http_proxy_connect_handler(ngx_http_request_t *r)
{
    ngx_url_t                            url;
    ngx_int_t                            rc;
    ngx_resolver_ctx_t                  *rctx, temp;
    ngx_http_core_loc_conf_t            *clcf;
    ngx_http_proxy_connect_ctx_t        *ctx;
    ngx_http_proxy_connect_upstream_t   *u;
    ngx_http_proxy_connect_loc_conf_t   *plcf;

    plcf = ngx_http_get_module_loc_conf(r, ngx_http_proxy_connect_module);

    if (r->method != NGX_HTTP_CONNECT || !plcf->accept_connect) {
        return NGX_DECLINED;
    }

    rc = ngx_http_proxy_connect_allow_handler(r, plcf);

    if (rc != NGX_OK) {
        return rc;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);;

    if (ngx_http_proxy_connect_upstream_create(r, ctx) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    u = ctx->u;

    u->conf = plcf;

    ngx_memzero(&url, sizeof(ngx_url_t));

    if (plcf->address) {
        if (ngx_http_complex_value(r, plcf->address, &url.url) != NGX_OK) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        if (url.url.len == 0 || url.url.data == NULL) {
            url.url.len = r->connect_host.len;
            url.url.data = r->connect_host.data;
        }

    } else {
        url.url.len = r->connect_host.len;
        url.url.data = r->connect_host.data;
    }

    url.default_port = r->connect_port_n;
    url.no_resolve = 1;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "proxy_connect: connect handler: parse url: %V" , &url.url);

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        if (url.err) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "proxy_connect: %s in connect host \"%V\"",
                          url.err, &url.url);
            return NGX_HTTP_FORBIDDEN;
        }

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    r->read_event_handler = ngx_http_proxy_connect_rd_check_broken_connection;
    r->write_event_handler = ngx_http_proxy_connect_wr_check_broken_connection;

    /* NOTE:
     *   We use only one address in u->resolved,
     *   and u->resolved.host is "<address:port>" format.
     */

    u->resolved = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_resolved_t));
    if (u->resolved == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /* rc = NGX_DECLINED */

    if (url.addrs) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "proxy_connect: upstream address given directly");

        u->resolved->sockaddr = url.addrs[0].sockaddr;
        u->resolved->socklen = url.addrs[0].socklen;
#if defined(nginx_version) && nginx_version >= 1011007
        u->resolved->name = url.addrs[0].name;
#endif
        u->resolved->naddrs = 1;
    }

    u->resolved->host = url.host;
    u->resolved->port = (in_port_t) (url.no_port ? r->connect_port_n : url.port);
    u->resolved->no_port = url.no_port;

    if (u->resolved->sockaddr) {

        rc = ngx_http_proxy_connect_sock_ntop(r, u);

        if (rc != NGX_OK) {
            return rc;
        }

        r->main->count++;

        ngx_http_proxy_connect_process_connect(r, u);

        return NGX_DONE;
    }

    ngx_str_t *host = &url.host;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    temp.name = *host;

    u->start_time = ngx_current_msec;
    u->state.resolve_time = (ngx_msec_t) -1;

    rctx = ngx_resolve_start(clcf->resolver, &temp);
    if (rctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: failed to start the resolver");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (rctx == NGX_NO_RESOLVER) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: no resolver defined to resolve %V",
                      &r->connect_host);
        return NGX_HTTP_BAD_GATEWAY;
    }

    rctx->name = *host;
#if !defined(nginx_version) || nginx_version < 1005008
    rctx->type = NGX_RESOLVE_A;
#endif
    rctx->handler = ngx_http_proxy_connect_resolve_handler;
    rctx->data = u;
    rctx->timeout = clcf->resolver_timeout;

    u->resolved->ctx = rctx;

    r->main->count++;

    if (ngx_resolve_name(rctx) != NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "proxy_connect: fail to run resolver immediately");

        u->resolved->ctx = NULL;
        r->main->count--;
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    return NGX_DONE;
}


static ngx_int_t
ngx_http_proxy_connect_sock_ntop(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u)
{
    u_char                          *p;
    ngx_int_t                        len;
    ngx_http_upstream_resolved_t    *ur;

    ur = u->resolved;

    /* fix u->resolved->host to "<address:port>" format */

    p = ngx_pnalloc(r->pool, NGX_SOCKADDR_STRLEN);
    if (p == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    len = __ngx_sock_ntop(ur->sockaddr, ur->socklen, p, NGX_SOCKADDR_STRLEN, 1);

    u->resolved->host.data = p;
    u->resolved->host.len = len;

    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_allow_handler(ngx_http_request_t *r,
    ngx_http_proxy_connect_loc_conf_t *plcf)
{
    ngx_uint_t  i, allow;
    in_port_t   (*ports)[2];

    allow = 0;

    if (plcf->allow_port_all) {
        allow = 1;

    } else if (plcf->allow_ports) {
        ports = plcf->allow_ports->elts;

        for (i = 0; i < plcf->allow_ports->nelts; i++) {
            /*
             * connect_port == port
             * OR
             * port <= connect_port <= eport
             */
            if ((ports[i][1] == 0 && r->connect_port_n == ports[i][0])
                || (ports[i][0] <= r->connect_port_n && r->connect_port_n <= ports[i][1]))
            {
                allow = 1;
                break;
            }
        }

    } else {
        if (r->connect_port_n == 443 || r->connect_port_n == 563) {
            allow = 1;
        }
    }

    if (allow == 0) {
        return NGX_HTTP_FORBIDDEN;
    }

    return NGX_OK;
}


static char *
ngx_http_proxy_connect_allow(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char                              *p;
    in_port_t                           *ports;
    ngx_int_t                            port, eport;
    ngx_uint_t                           i;
    ngx_str_t                           *value;
    ngx_http_proxy_connect_loc_conf_t   *plcf = conf;

    if (plcf->allow_ports != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    plcf->allow_ports = ngx_array_create(cf->pool, 2, sizeof(in_port_t[2]));
    if (plcf->allow_ports == NULL) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {

        if (value[i].len == 3 && ngx_strncmp(value[i].data, "all", 3) == 0) {
            plcf->allow_port_all = 1;
            continue;
        }

        p = ngx_strlchr(value[i].data, value[i].data + value[i].len, '-');

        if (p != NULL) {
            port = ngx_atoi(value[i].data, p - value[i].data);
            p++;
            eport = ngx_atoi(p, value[i].data + value[i].len - p);

            if (port == NGX_ERROR || port < 1 || port > 65535
                || eport == NGX_ERROR || eport < 1 || eport > 65535
                || port > eport)
            {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid port range \"%V\" in \"%V\" directive",
                                   &value[i], &cmd->name);
                return  NGX_CONF_ERROR;
            }

        } else {

            port = ngx_atoi(value[i].data, value[i].len);

            if (port == NGX_ERROR || port < 1 || port > 65535) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid value \"%V\" in \"%V\" directive",
                                   &value[i], &cmd->name);
                return  NGX_CONF_ERROR;
            }

            eport = 0;
        }

        ports = ngx_array_push(plcf->allow_ports);
        if (ports == NULL) {
            return NGX_CONF_ERROR;
        }

        ports[0] = port;
        ports[1] = eport;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_proxy_connect(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t            *clcf;
    ngx_http_proxy_connect_loc_conf_t   *pclcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_proxy_connect_handler;

    pclcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_proxy_connect_module);
    pclcf->accept_connect = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_proxy_connect_bind(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char  *p = conf;

    ngx_int_t                           rc;
    ngx_str_t                          *value;
    ngx_http_complex_value_t            cv;
    ngx_http_proxy_connect_address_t  **plocal, *local;
    ngx_http_compile_complex_value_t    ccv;

    plocal = (ngx_http_proxy_connect_address_t **) (p + cmd->offset);

    if (*plocal != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (cf->args->nelts == 2 && ngx_strcmp(value[1].data, "off") == 0) {
        *plocal = NULL;
        return NGX_CONF_OK;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    ccv.cf = cf;
    ccv.value = &value[1];
    ccv.complex_value = &cv;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    local = ngx_pcalloc(cf->pool, sizeof(ngx_http_proxy_connect_address_t));
    if (local == NULL) {
        return NGX_CONF_ERROR;
    }

    *plocal = local;

    if (cv.lengths) {
        local->value = ngx_palloc(cf->pool, sizeof(ngx_http_complex_value_t));
        if (local->value == NULL) {
            return NGX_CONF_ERROR;
        }

        *local->value = cv;

    } else {
        local->addr = ngx_palloc(cf->pool, sizeof(ngx_addr_t));
        if (local->addr == NULL) {
            return NGX_CONF_ERROR;
        }

        rc = __ngx_parse_addr_port(cf->pool, local->addr, value[1].data,
                                   value[1].len);

        switch (rc) {
        case NGX_OK:
            local->addr->name = value[1];
            break;

        case NGX_DECLINED:
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid address \"%V\"", &value[1]);
            /* fall through */

        default:
            return NGX_CONF_ERROR;
        }
    }

    if (cf->args->nelts > 2) {
        if (ngx_strcmp(value[2].data, "transparent") == 0) {
#if (NGX_HAVE_TRANSPARENT_PROXY)
            local->transparent = 1;
#else
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "transparent proxying is not supported "
                               "on this platform, ignored");
#endif
        } else {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid parameter \"%V\"", &value[2]);
            return NGX_CONF_ERROR;
        }
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_proxy_connect_set_local(ngx_http_request_t *r,
    ngx_http_proxy_connect_upstream_t *u, ngx_http_proxy_connect_address_t *local)
{
    ngx_int_t    rc;
    ngx_str_t    val;
    ngx_addr_t  *addr;

    if (local == NULL) {
        u->peer.local = NULL;
        return NGX_OK;
    }

#if (NGX_HAVE_TRANSPARENT_PROXY)
    u->peer.transparent = local->transparent;
#endif

    if (local->value == NULL) {
        u->peer.local = local->addr;
        return NGX_OK;
    }

    if (ngx_http_complex_value(r, local->value, &val) != NGX_OK) {
        return NGX_ERROR;
    }

    if (val.len == 0) {
        return NGX_OK;
    }

    addr = ngx_palloc(r->pool, sizeof(ngx_addr_t));
    if (addr == NULL) {
        return NGX_ERROR;
    }

    rc = __ngx_parse_addr_port(r->pool, addr, val.data, val.len);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: invalid local address \"%V\"", &val);
        return NGX_OK;
    }

    addr->name = val;
    u->peer.local = addr;

    return NGX_OK;
}


static void *
ngx_http_proxy_connect_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_proxy_connect_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_proxy_connect_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->address = NULL;
     */

    conf->accept_connect = NGX_CONF_UNSET;
    conf->allow_port_all = NGX_CONF_UNSET;
    conf->allow_ports = NGX_CONF_UNSET_PTR;

    conf->connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->send_timeout = NGX_CONF_UNSET_MSEC;
    conf->data_timeout = NGX_CONF_UNSET_MSEC;

    conf->send_lowat = NGX_CONF_UNSET_SIZE;
    conf->buffer_size = NGX_CONF_UNSET_SIZE;

    conf->local = NGX_CONF_UNSET_PTR;

    return conf;
}


static char *
ngx_http_proxy_connect_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_proxy_connect_loc_conf_t    *prev = parent;
    ngx_http_proxy_connect_loc_conf_t    *conf = child;

    ngx_conf_merge_value(conf->accept_connect, prev->accept_connect, 0);
    ngx_conf_merge_value(conf->allow_port_all, prev->allow_port_all, 0);
    ngx_conf_merge_ptr_value(conf->allow_ports, prev->allow_ports, NULL);

    ngx_conf_merge_msec_value(conf->connect_timeout,
                              prev->connect_timeout, 60000);

    ngx_conf_merge_msec_value(conf->send_timeout, prev->send_timeout, 60000);

    ngx_conf_merge_msec_value(conf->data_timeout, prev->data_timeout, 60000);

    ngx_conf_merge_size_value(conf->send_lowat, prev->send_lowat, 0);

    ngx_conf_merge_size_value(conf->buffer_size, prev->buffer_size, 16384);

    if (conf->address == NULL) {
        conf->address = prev->address;
    }

    ngx_conf_merge_ptr_value(conf->local, prev->local, NULL);

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_proxy_connect_connect_addr_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{

    ngx_http_proxy_connect_upstream_t     *u;
    ngx_http_proxy_connect_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (ctx == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    u = ctx->u;

    if (u == NULL || u->peer.name == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    v->len = u->peer.name->len;
    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;
    v->data = u->peer.name->data;

    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_variable_get_time(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char                          *p;
    ngx_msec_t                      *msp, ms;
    ngx_http_proxy_connect_ctx_t    *ctx;

    if (r->method != NGX_HTTP_CONNECT) {
        return NGX_OK;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (ctx == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    msp = (ngx_msec_t *) ((char *) ctx + data);
    ms = *msp;

    p = ngx_pnalloc(r->pool, NGX_TIME_T_LEN);
    if (p == NULL) {
        return NGX_ERROR;
    }

    v->len = ngx_sprintf(p, "%M", ms) - p;
    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;
    v->data = p;

    return NGX_OK;
}


static void
ngx_http_proxy_connect_variable_set_time(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_str_t                        s;
    ngx_msec_t                      *msp, ms;
    ngx_http_proxy_connect_ctx_t    *ctx;

    if (r->method != NGX_HTTP_CONNECT) {
        return;
    }

    s.len = v->len;
    s.data = v->data;

    ms = ngx_parse_time(&s, 0);

    if (ms == (ngx_msec_t) NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: invalid msec \"%V\" (ctx offset=%ui)",
                      &s, data);
        return;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (ctx == NULL) {
#if 0
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "proxy_connect: no ctx found");
#endif
        return;
    }

    msp = (ngx_msec_t *) ((char *) ctx + data);

    *msp = ms;
}


static ngx_int_t
ngx_http_proxy_connect_resolve_time_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char                             *p;
    size_t                              len;
    ngx_msec_int_t                      ms;
    ngx_http_proxy_connect_ctx_t       *ctx;
    ngx_http_proxy_connect_upstream_t  *u;

    if (r->method != NGX_HTTP_CONNECT) {
        return NGX_OK;
    }

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (ctx == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    u = ctx->u;

    if (u == NULL || !u->resolved) {
        v->not_found = 1;
        return NGX_OK;
    }

    len = NGX_TIME_T_LEN + 4;

    p = ngx_pnalloc(r->pool, len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    v->data = p;

    ms = u->state.resolve_time;

    if (ms != -1) {
        ms = ngx_max(ms, 0);
        p = ngx_sprintf(p, "%T.%03M", (time_t) ms / 1000, ms % 1000);

    } else {
        *p++ = '-';
    }

    v->len = p - v->data;

    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_connect_time_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char                             *p;
    size_t                              len;
    ngx_msec_int_t                      ms;
    ngx_http_proxy_connect_ctx_t       *ctx;
    ngx_http_proxy_connect_upstream_t  *u;

    if (r->method != NGX_HTTP_CONNECT) {
        return NGX_OK;
    }

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (ctx == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    u = ctx->u;

    if (u == NULL || !u->connected) {
        v->not_found = 1;
        return NGX_OK;
    }

    len = NGX_TIME_T_LEN + 4;

    p = ngx_pnalloc(r->pool, len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    v->data = p;

    ms = u->state.connect_time;

    if (ms != -1) {
        ms = ngx_max(ms, 0);
        p = ngx_sprintf(p, "%T.%03M", (time_t) ms / 1000, ms % 1000);

    } else {
        *p++ = '-';
    }

    v->len = p - v->data;

    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_first_byte_time_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char                             *p;
    size_t                              len;
    ngx_msec_int_t                      ms;
    ngx_http_proxy_connect_ctx_t       *ctx;
    ngx_http_proxy_connect_upstream_t  *u;

    if (r->method != NGX_HTTP_CONNECT) {
        return NGX_OK;
    }

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (ctx == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    u = ctx->u;

    if (u == NULL || !u->connected) {
        v->not_found = 1;
        return NGX_OK;
    }

    len = NGX_TIME_T_LEN + 4;

    p = ngx_pnalloc(r->pool, len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    v->data = p;

    ms = u->state.first_byte_time;

    if (ms != -1) {
        ms = ngx_max(ms, 0);
        p = ngx_sprintf(p, "%T.%03M", (time_t) ms / 1000, ms % 1000);

    } else {
        *p++ = '-';
    }

    v->len = p - v->data;

    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_variable_get_response(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_http_proxy_connect_ctx_t       *ctx;

    if (r->method != NGX_HTTP_CONNECT) {
        return NGX_OK;
    }

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (ctx == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    v->data = ctx->buf.pos;
    v->len = ctx->buf.last - ctx->buf.pos;

    return NGX_OK;
}


static void
ngx_http_proxy_connect_variable_set_response(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_http_proxy_connect_ctx_t       *ctx;

    if (r->method != NGX_HTTP_CONNECT) {
        return;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_proxy_connect_module);

    if (ctx == NULL) {
        return;
    }

    ctx->buf.pos = (u_char *) v->data;
    ctx->buf.last = ctx->buf.pos + v->len;
}

static ngx_int_t
ngx_http_proxy_connect_add_variables(ngx_conf_t *cf)
{
    ngx_http_variable_t  *var, *v;

    for (v = ngx_http_proxy_connect_vars; v->name.len; v++) {
        var = ngx_http_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }

        *var = *v;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_proxy_connect_post_read_handler(ngx_http_request_t *r)
{
    ngx_http_proxy_connect_ctx_t      *ctx;
    ngx_http_proxy_connect_loc_conf_t *pclcf;

    if (r->method == NGX_HTTP_CONNECT) {

        pclcf = ngx_http_get_module_loc_conf(r, ngx_http_proxy_connect_module);

        if (!pclcf->accept_connect) {
            ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                          "proxy_connect: client sent connect method");
            return NGX_HTTP_NOT_ALLOWED;
        }

        /* init ctx */

        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_proxy_connect_ctx_t));
        if (ctx == NULL) {
            return NGX_ERROR;
        }

        ctx->buf.pos = (u_char *) NGX_HTTP_PROXY_CONNECT_ESTABLISTHED;
        ctx->buf.last = ctx->buf.pos +
                        sizeof(NGX_HTTP_PROXY_CONNECT_ESTABLISTHED) - 1;
        ctx->buf.memory = 1;

        ctx->connect_timeout = pclcf->connect_timeout;
        ctx->send_timeout = pclcf->send_timeout;
        ctx->data_timeout = pclcf->data_timeout;

        ngx_http_set_ctx(r, ctx, ngx_http_proxy_connect_module);
    }

    return NGX_DECLINED;
}


static ngx_int_t
ngx_http_proxy_connect_init(ngx_conf_t *cf)
{
    ngx_http_core_main_conf_t  *cmcf;
    ngx_http_handler_pt        *h;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_POST_READ_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_proxy_connect_post_read_handler;

    return NGX_OK;
}
