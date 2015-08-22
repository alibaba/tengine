
/*
 * Copyright (C) 2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


static char *ngx_http_debug_pool(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_debug_pool_buf(ngx_pool_t *pool, ngx_buf_t *b);

static ngx_command_t  ngx_http_debug_pool_commands[] = {

    { ngx_string("debug_pool"),
      NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
      ngx_http_debug_pool,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_debug_pool_module_ctx = {
    NULL,                          /* preconfiguration */
    NULL,                          /* postconfiguration */

    NULL,                          /* create main configuration */
    NULL,                          /* init main configuration */

    NULL,                          /* create server configuration */
    NULL,                          /* merge server configuration */

    NULL,                          /* create location configuration */
    NULL                           /* merge location configuration */
};


ngx_module_t  ngx_http_debug_pool_module = {
    NGX_MODULE_V1,
    &ngx_http_debug_pool_module_ctx,    /* module context */
    ngx_http_debug_pool_commands,       /* module directives */
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
ngx_http_debug_pool_handler(ngx_http_request_t *r)
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

    if (ngx_http_debug_pool_buf(r->pool, b) == NGX_ERROR) {
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
ngx_http_debug_pool_buf(ngx_pool_t *pool, ngx_buf_t *b)
{
    u_char              *p, *unit;
    size_t               size, s, n, cn, ln;
    ngx_uint_t           i;
    ngx_pool_stat_t     *stat;

#define NGX_POOL_PID_SIZE       (NGX_TIME_T_LEN + sizeof("pid:\n") - 1)     /* sizeof pid_t equals time_t */
#define NGX_POOL_PID_FORMAT     "pid:%P\n"
#define NGX_POOL_ENTRY_SIZE     (48 /* func */ + 12 * 4 + sizeof("size: num: cnum: lnum: \n") - 1)
#define NGX_POOL_ENTRY_FORMAT   "size:%12z num:%12z cnum:%12z lnum:%12z %s\n"
#define NGX_POOL_SUMMARY_SIZE   (12 * 4 + sizeof("size: num: cnum: lnum: [SUMMARY]\n") - 1)
#define NGX_POOL_SUMMARY_FORMAT "size:%10z%2s num:%12z cnum:%12z lnum:%12z [SUMMARY]\n"

    size = NGX_POOL_PID_SIZE + ngx_pool_stats_num * NGX_POOL_ENTRY_SIZE
           + NGX_POOL_SUMMARY_SIZE;
    p = ngx_palloc(pool, size);
    if (p == NULL) {
        return NGX_ERROR;
    }

    b->pos = p;

    p = ngx_sprintf(p, NGX_POOL_PID_FORMAT, ngx_pid);

    /* lines of entry */

    s = n = cn = ln = 0;

    for (i = 0; i < NGX_POOL_STATS_MAX; i++) {
        for (stat = ngx_pool_stats[i]; stat != NULL; stat = stat->next) {
            p = ngx_snprintf(p, NGX_POOL_ENTRY_SIZE, NGX_POOL_ENTRY_FORMAT,
                             stat->size, stat->num, stat->cnum, stat->lnum,
                             stat->func);
            s += stat->size;
            n += stat->num;
            cn += stat->cnum;
            ln += stat->lnum;
        }
    }

    /* summary line */

    unit = (u_char *) " B";

    if (s > 1024 * 1024) {
        s = s / (1024 * 1024);
        unit = (u_char *) "MB";
    } else if (s > 1024) {
        s = s / 1024;
        unit = (u_char *) "KB";
    }

    p = ngx_snprintf(p, NGX_POOL_SUMMARY_SIZE, NGX_POOL_SUMMARY_FORMAT,
                     s, unit, n, cn, ln);

    b->last = p;
    b->memory = 1;
    b->last_buf = 1;

    return NGX_OK;
}


static char *
ngx_http_debug_pool(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_debug_pool_handler;

    return NGX_CONF_OK;
}
