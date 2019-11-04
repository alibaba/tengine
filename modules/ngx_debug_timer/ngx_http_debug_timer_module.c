
/*
 * Copyright (C) 2018 Alibaba Group Holding Limited
 */


#include <execinfo.h>
#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event_timer.h>
#include <ngx_http.h>


static char *ngx_http_debug_timer(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static void ngx_http_debug_timer_traversal(ngx_array_t *array, ngx_rbtree_node_t *root);
static ngx_int_t ngx_http_debug_timer_buf(ngx_pool_t *pool, ngx_buf_t *b);

static ngx_command_t  ngx_http_debug_timer_commands[] = {

    { ngx_string("debug_timer"),
      NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
      ngx_http_debug_timer,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_debug_timer_module_ctx = {
    NULL,                          /* preconfiguration */
    NULL,                          /* postconfiguration */

    NULL,                          /* create main configuration */
    NULL,                          /* init main configuration */

    NULL,                          /* create server configuration */
    NULL,                          /* merge server configuration */

    NULL,                          /* create location configuration */
    NULL                           /* merge location configuration */
};


ngx_module_t  ngx_http_debug_timer_module = {
    NGX_MODULE_V1,
    &ngx_http_debug_timer_module_ctx,   /* module context */
    ngx_http_debug_timer_commands,      /* module directives */
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
ngx_http_debug_timer_handler(ngx_http_request_t *r)
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

    if (ngx_http_debug_timer_buf(r->pool, b) == NGX_ERROR) {
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


static void
ngx_http_debug_timer_traversal(ngx_array_t *array, ngx_rbtree_node_t *root)
{
    ngx_rbtree_node_t              **node;

    if (array != NULL && root != NULL
        && root != ngx_event_timer_rbtree.sentinel)
    {
        ngx_http_debug_timer_traversal(array, root->left);
        node = ngx_array_push(array);
        if (node == NULL) {
            return;
        }
        *node = (ngx_rbtree_node_t *) root;
        ngx_http_debug_timer_traversal(array, root->right);
    }
}


static ngx_int_t
ngx_http_debug_timer_buf(ngx_pool_t *pool, ngx_buf_t *b)
{
    u_char              *p;
    size_t               size;
    ngx_uint_t           i, n;
    ngx_event_t         *ev;
    ngx_array_t         *array;
    ngx_msec_int_t       timer;
    ngx_rbtree_node_t   *root;
    ngx_rbtree_node_t  **nodes, *node;

#define NGX_TIMER_TITLE_SIZE     (sizeof(NGX_TIMER_TITLE_FORMAT) - 1 + NGX_TIME_T_LEN + NGX_INT_T_LEN)     /* sizeof pid_t equals time_t */
#define NGX_TIMER_TITLE_FORMAT   "pid:%P\n"                  \
                                 "timer:%ui\n"

#define NGX_TIMER_ENTRY_SIZE     (sizeof(NGX_TIMER_ENTRY_FORMAT) - 1 + \
                                  NGX_INT_T_LEN * 2 + NGX_PTR_SIZE * 4 + 256 /* func name */)
#define NGX_TIMER_ENTRY_FORMAT  "--------- [%ui] --------\n"\
                                "timers[i]: %p\n"          \
                                "    timer: %ui\n"          \
                                "       ev: %p\n"           \
                                "     data: %p\n"           \
                                "  handler: %p\n"           \
                                "   action: %s\n"

    root = ngx_event_timer_rbtree.root;

    array = ngx_array_create(pool, 10, sizeof(ngx_rbtree_node_t **));
    if (array == NULL) {
        return NGX_ERROR;
    }

    ngx_http_debug_timer_traversal(array, root);

    n = array->nelts;

    size = NGX_TIMER_TITLE_SIZE + n * NGX_TIMER_ENTRY_SIZE;
    p = ngx_palloc(pool, size);
    if (p == NULL) {
        ngx_array_destroy(array);
        return NGX_ERROR;
    }

    b->pos = p;

    p = ngx_sprintf(p, NGX_TIMER_TITLE_FORMAT, ngx_pid, n);

    nodes = (ngx_rbtree_node_t **) array->elts;

    for (i = 0; i < n; i++) {
        node = nodes[i]; /* node: timer */
        ev = (ngx_event_t *) ((char *) node - (intptr_t)&((ngx_event_t *) 0x0)->timer);

         /* entry format of timer and ev */

        timer = (ngx_msec_int_t) (node->key - ngx_current_msec);

        p = ngx_snprintf(p, NGX_TIMER_ENTRY_SIZE, NGX_TIMER_ENTRY_FORMAT,
                         i, node, timer, ev, ev->data, ev->handler,
                         (ev->log->action != NULL) ? ev->log->action : "");
    }

    ngx_array_destroy(array);

    p[-1] = '\n';  /* make sure last char is newline */

    b->last = p;
    b->memory = 1;
    b->last_buf = 1;

    return NGX_OK;
}


static char *
ngx_http_debug_timer(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_debug_timer_handler;

    return NGX_CONF_OK;
}
