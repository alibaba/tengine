
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


static ngx_int_t ngx_http_stub_status_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_stub_status_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_stub_status_add_variables(ngx_conf_t *cf);
static char *ngx_http_set_stub_status(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
#if (T_NGX_HTTP_STUB_STATUS)
static ngx_int_t ngx_http_stub_status_init(ngx_conf_t *cf);
#endif


static ngx_command_t  ngx_http_status_commands[] = {

    { ngx_string("stub_status"),
      NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS|NGX_CONF_TAKE1,
      ngx_http_set_stub_status,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_stub_status_module_ctx = {
    ngx_http_stub_status_add_variables,    /* preconfiguration */
#if (T_NGX_HTTP_STUB_STATUS)
    ngx_http_stub_status_init,             /* postconfiguration */
#else
    NULL,                                  /* postconfiguration */
#endif

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};


ngx_module_t  ngx_http_stub_status_module = {
    NGX_MODULE_V1,
    &ngx_http_stub_status_module_ctx,      /* module context */
    ngx_http_status_commands,              /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_variable_t  ngx_http_stub_status_vars[] = {

    { ngx_string("connections_active"), NULL, ngx_http_stub_status_variable,
      0, NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("connections_reading"), NULL, ngx_http_stub_status_variable,
      1, NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("connections_writing"), NULL, ngx_http_stub_status_variable,
      2, NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("connections_waiting"), NULL, ngx_http_stub_status_variable,
      3, NGX_HTTP_VAR_NOCACHEABLE, 0 },

      ngx_http_null_variable
};


static ngx_int_t
ngx_http_stub_status_handler(ngx_http_request_t *r)
{
    size_t             size;
    ngx_int_t          rc;
    ngx_buf_t         *b;
    ngx_chain_t        out;
    ngx_atomic_int_t   ap, hn, ac, rq, rd, wr, wa;

#if (T_NGX_HTTP_STUB_STATUS)
    ngx_atomic_int_t   rt;
#endif

    if (!(r->method & (NGX_HTTP_GET|NGX_HTTP_HEAD))) {
        return NGX_HTTP_NOT_ALLOWED;
    }

    rc = ngx_http_discard_request_body(r);

    if (rc != NGX_OK) {
        return rc;
    }

    r->headers_out.content_type_len = sizeof("text/plain") - 1;
    ngx_str_set(&r->headers_out.content_type, "text/plain");
    r->headers_out.content_type_lowcase = NULL;

    if (r->method == NGX_HTTP_HEAD) {
        r->headers_out.status = NGX_HTTP_OK;

        rc = ngx_http_send_header(r);

        if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
            return rc;
        }
    }

    size = sizeof("Active connections:  \n") + NGX_ATOMIC_T_LEN
#if (T_NGX_HTTP_STUB_STATUS)
           + sizeof("server accepts handled requests request_time\n") - 1
           + 6 + 4 * NGX_ATOMIC_T_LEN
#else
           + sizeof("server accepts handled requests\n") - 1
           + 6 + 3 * NGX_ATOMIC_T_LEN
#endif
           + sizeof("Reading:  Writing:  Waiting:  \n") + 3 * NGX_ATOMIC_T_LEN;

    b = ngx_create_temp_buf(r->pool, size);
    if (b == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    out.buf = b;
    out.next = NULL;

    ap = *ngx_stat_accepted;
    hn = *ngx_stat_handled;
    ac = *ngx_stat_active;
    rq = *ngx_stat_requests;
    rd = *ngx_stat_reading;
    wr = *ngx_stat_writing;
    wa = *ngx_stat_waiting;
#if (T_NGX_HTTP_STUB_STATUS)
    rt = *ngx_stat_request_time;
#endif

    b->last = ngx_sprintf(b->last, "Active connections: %uA \n", ac);

#if (T_NGX_HTTP_STUB_STATUS)
    b->last = ngx_cpymem(b->last,
        "server accepts handled requests request_time\n",
        sizeof("server accepts handled requests request_time\n") - 1);

    b->last = ngx_sprintf(b->last, " %uA %uA %uA %uA\n", ap, hn, rq, rt);
#else
    b->last = ngx_cpymem(b->last, "server accepts handled requests\n",
                         sizeof("server accepts handled requests\n") - 1);

    b->last = ngx_sprintf(b->last, " %uA %uA %uA \n", ap, hn, rq);
#endif

    b->last = ngx_sprintf(b->last, "Reading: %uA Writing: %uA Waiting: %uA \n",
                          rd, wr, wa);

    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = b->last - b->pos;

    b->last_buf = (r == r->main) ? 1 : 0;
    b->last_in_chain = 1;

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    return ngx_http_output_filter(r, &out);
}


static ngx_int_t
ngx_http_stub_status_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char            *p;
    ngx_atomic_int_t   value;

    p = ngx_pnalloc(r->pool, NGX_ATOMIC_T_LEN);
    if (p == NULL) {
        return NGX_ERROR;
    }

    switch (data) {
    case 0:
        value = *ngx_stat_active;
        break;

    case 1:
        value = *ngx_stat_reading;
        break;

    case 2:
        value = *ngx_stat_writing;
        break;

    case 3:
        value = *ngx_stat_waiting;
        break;

    /* suppress warning */
    default:
        value = 0;
        break;
    }

    v->len = ngx_sprintf(p, "%uA", value) - p;
    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;
    v->data = p;

    return NGX_OK;
}


static ngx_int_t
ngx_http_stub_status_add_variables(ngx_conf_t *cf)
{
    ngx_http_variable_t  *var, *v;

    for (v = ngx_http_stub_status_vars; v->name.len; v++) {
        var = ngx_http_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }

        var->get_handler = v->get_handler;
        var->data = v->data;
    }

    return NGX_OK;
}


static char *
ngx_http_set_stub_status(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t  *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_stub_status_handler;

    return NGX_CONF_OK;
}


#if (T_NGX_HTTP_STUB_STATUS)
static ngx_int_t
ngx_http_status_log_handler(ngx_http_request_t *r)
{
    ngx_time_t                *tp;
    ngx_msec_int_t             ms;
#if (T_NGX_RET_CACHE)
    struct timeval             tv;
    ngx_http_core_loc_conf_t  *clcf;
#endif

    if (r != r->main) {
        return NGX_OK;
    }

#if (T_NGX_RET_CACHE)
    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    if (clcf->request_time_cache) {
        tp = ngx_timeofday();

        ms = (ngx_msec_int_t)
                 ((tp->sec - r->start_sec) * 1000 + (tp->msec - r->start_msec));
    } else {
        ngx_gettimeofday(&tv);

        ms = (ngx_msec_int_t) ((tv.tv_sec - r->start_sec) * 1000
                 + (tv.tv_usec / 1000 - r->start_msec));
    }

#else 
    tp = ngx_timeofday();
    ms = (ngx_msec_int_t)
             ((tp->sec - r->start_sec) * 1000 + (tp->msec - r->start_msec));    
#endif

    ms = ngx_max(ms, 0);
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http status: request_time %M", ms);

    (void) ngx_atomic_fetch_add(ngx_stat_request_time, ms);

    return NGX_OK;
}


ngx_int_t
ngx_http_stub_status_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_LOG_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_status_log_handler;

    return NGX_OK;
}
#endif

