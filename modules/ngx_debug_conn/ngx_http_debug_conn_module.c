
/*
 * Copyright (C) 2016 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#if (NGX_DEBUG_POOL)
extern size_t ngx_pool_size(ngx_pool_t *);
#else
#define ngx_pool_size(p) ((size_t) 0)
#endif

#if (NGX_HTTP_SSL)
#define ngx_request_scheme(r) ((r)->connection->ssl ? "https" : "http")
#else
#define ngx_request_scheme(r) "http"
#endif


static char *ngx_http_debug_conn(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_debug_conn_buf(ngx_pool_t *pool, ngx_buf_t *b);

static ngx_command_t  ngx_http_debug_conn_commands[] = {

    { ngx_string("debug_conn"),
      NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
      ngx_http_debug_conn,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_debug_conn_module_ctx = {
    NULL,                          /* preconfiguration */
    NULL,                          /* postconfiguration */

    NULL,                          /* create main configuration */
    NULL,                          /* init main configuration */

    NULL,                          /* create server configuration */
    NULL,                          /* merge server configuration */

    NULL,                          /* create location configuration */
    NULL                           /* merge location configuration */
};


ngx_module_t  ngx_http_debug_conn_module = {
    NGX_MODULE_V1,
    &ngx_http_debug_conn_module_ctx,    /* module context */
    ngx_http_debug_conn_commands,       /* module directives */
    NGX_HTTP_MODULE,                    /* module type */
    NULL,                               /* init master */
    NULL,                               /* init module */
    NULL,                               /* init process */
    NULL,                               /* init thread */
    NULL,                               /* exit thread */
    NULL,                               /* exit process */
    NULL,                               /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_debug_conn_handler(ngx_http_request_t *r)
{
    ngx_int_t    rc;
    ngx_buf_t   *b;
    ngx_chain_t  out;

    if (r->method != NGX_HTTP_GET) {
        return NGX_HTTP_NOT_ALLOWED;
    }

    rc = ngx_http_discard_request_body(r);
    if (rc != NGX_OK) {
        return rc;
    }

    b = ngx_pcalloc(r->pool, sizeof(ngx_buf_t));
    if (b == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (ngx_http_debug_conn_buf(r->pool, b) == NGX_ERROR) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = b->last - b->pos;

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    out.buf = b;
    out.next = NULL;

    return ngx_http_output_filter(r, &out);
}


static ngx_int_t
ngx_http_debug_conn_buf(ngx_pool_t *pool, ngx_buf_t *b)
{
    u_char              *p;
    size_t               size;
    ngx_uint_t           i, k, n;
    ngx_str_t            addr, action, host, uri;
    ngx_connection_t    *c;
    ngx_http_request_t  *r;

#define NGX_CONN_TITLE_SIZE     (sizeof(NGX_CONN_TITLE_FORMAT) - 1 + NGX_TIME_T_LEN + NGX_INT_T_LEN)     /* sizeof pid_t equals time_t */
#define NGX_CONN_TITLE_FORMAT   "pid:%P\n"                  \
                                "connections:%ui\n"

#define NGX_CONN_ENTRY_SIZE     (sizeof(NGX_CONN_ENTRY_FORMAT) - 1 + \
                                 NGX_SIZE_T_LEN * 2 + NGX_SOCKADDR_STRLEN + 32 /* action */ + \
                                 NGX_OFF_T_LEN +  NGX_INT_T_LEN * 3 + NGX_PTR_SIZE * 2 * 2)
#define NGX_CONN_ENTRY_FORMAT   "--------- [%ui] --------\n"\
                                "conns[i]: %ui\n"         \
                                "      fd: %z\n"          \
                                "    addr: %V\n"          \
                                "    sent: %O\n"          \
                                "  action: %V\n"          \
                                " handler: r:%p w:%p\n"   \
                                "requests: %ui\n"         \
                                "poolsize: %z\n"

#define NGX_REQ_ENTRY_SIZE      (sizeof(NGX_REQ_ENTRY_FORMAT) - 1 + \
                                 sizeof("https") - 1 + 32 /* host */ + 64 /* uri */ + \
                                 NGX_TIME_T_LEN + NGX_PTR_SIZE * 2 * 2 + NGX_SIZE_T_LEN)
#define NGX_REQ_ENTRY_FORMAT    "********* request ******\n"\
                                "     uri: %s://%V%V\n"   \
                                " handler: r:%p w:%p\n"   \
                                "startsec: %T\n"          \
                                "poolsize: %z\n"

    n = ngx_cycle->connection_n - ngx_cycle->free_connection_n;

    size = NGX_CONN_TITLE_SIZE + n * (NGX_CONN_ENTRY_SIZE + NGX_REQ_ENTRY_SIZE);
    p = ngx_palloc(pool, size);
    if (p == NULL) {
        return NGX_ERROR;
    }

    b->pos = p;

    p = ngx_sprintf(p, NGX_CONN_TITLE_FORMAT, ngx_pid, n);

    /* lines of entry */

    k = 0;

    for (i = 0; i < ngx_cycle->connection_n; i++) {
        c = &ngx_cycle->connections[i];

        if (c->fd <= 0) {
            continue;
        }

        k++;

        if (n == 0) {
            break;
        }
        n--;

        /* addr_text */

        if (c->addr_text.data != NULL) {
            addr.data = c->addr_text.data;
            addr.len = ngx_min(c->addr_text.len, NGX_SOCKADDR_STRLEN);

        } else if (c->listening && c->listening->addr_text.data != NULL) {
            addr.data = c->listening->addr_text.data;
            addr.len = ngx_min(c->listening->addr_text.len, NGX_SOCKADDR_STRLEN);

        } else {
            ngx_str_set(&addr, "(null)");
        }

        /* action */

        if (c->log->action != NULL) {
            action.data = (u_char *) c->log->action;
            action.len = ngx_min(ngx_strlen(c->log->action), 32);

#if (NGX_SSL)
        } else if (c->ssl) {

            ngx_str_set(&action, "(null: ssl)");
#endif

        } else if (c->listening && c->listening->connection == c) {
            ngx_str_set(&action, "(null: listening)");

        } else if (c->data == NULL) {
            ngx_str_set(&action, "(null: channel)");

        } else {
            ngx_str_set(&action, "(null)");
        }

        /* entry format of connection */

        p = ngx_snprintf(p, NGX_CONN_ENTRY_SIZE, NGX_CONN_ENTRY_FORMAT,
                         k, i,
                         c->fd,
                         &addr,
                         c->sent,
                         &action,
                         c->read->handler, c->write->handler,
                         c->requests,
                         c->pool ? ngx_pool_size(c->pool) : (size_t) 0);

        /* c->data: http request */

        if (c->data != NULL) {
            r = (ngx_http_request_t *) c->data;
            if (r->signature == NGX_HTTP_MODULE && r->connection == c) {

                /* request host */

                if (r->headers_in.server.len) {
                    host.data = r->headers_in.server.data;
                    host.len = ngx_min(r->headers_in.server.len, 32);
                } else {
                    ngx_str_set(&host, "");
                }

                /* request uri */

                uri.data = r->unparsed_uri.data;
                uri.len = ngx_min(r->unparsed_uri.len, 64);

                /* entry format of request */

                p = ngx_snprintf(p, NGX_REQ_ENTRY_SIZE, NGX_REQ_ENTRY_FORMAT,
                                 ngx_request_scheme(r), &host, &uri,
                                 r->read_event_handler, r->write_event_handler,
                                 r->start_sec,
                                 r->pool ? ngx_pool_size(r->pool) : (size_t) 0);
            }
        }

        p[-1] = '\n';  /* make sure last char is newline */
    }

    b->last = p;
    b->memory = 1;
    b->last_buf = 1;

    return NGX_OK;
}


static char *
ngx_http_debug_conn(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_debug_conn_handler;

    return NGX_CONF_OK;
}
