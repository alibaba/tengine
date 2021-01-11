
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#include "ngx_dubbo.h"
#include "ngx_http_dubbo_module.h"
#include "ngx_multi_upstream_module.h"

typedef struct {
    ngx_http_upstream_conf_t    upstream;

    ngx_http_complex_value_t    service_name;
    ngx_http_complex_value_t    service_version;
    ngx_http_complex_value_t    method;

    ngx_array_t                *args_in;

    ngx_flag_t                  pass_all_headers;
    ngx_flag_t                  pass_body;
    ngx_flag_t                  ups_info;

    ngx_msec_t                  heartbeat_interval;
} ngx_http_dubbo_loc_conf_t;

typedef struct {
    ngx_str_t                    key;
    ngx_str_t                    value;
    ngx_int_t                    key_var_index;
    ngx_int_t                    value_var_index;
} ngx_http_dubbo_arg_t;

typedef enum {
    ngx_http_dubbo_parse_st_start = 0,

    ngx_http_dubbo_parse_st_payload = 1,
    ngx_http_dubbo_parse_st_props_len = 2,

    ngx_http_dubbo_parse_end
} ngx_http_dubbo_parse_state_e;

typedef struct {
    ngx_chain_t                          *in;
    ngx_chain_t                          *out;
    ngx_chain_t                          *free;
    ngx_chain_t                          *busy;

    ngx_http_request_t                   *request;
    ngx_dubbo_resp_t                      dubbo_resp;
    ngx_http_dubbo_parse_state_e          state;
    ngx_dubbo_connection_t               *connection;

    ngx_array_t                          *result;
    ngx_str_t                            *response_body;
} ngx_http_dubbo_ctx_t;

typedef ngx_int_t (*ngx_http_dubbo_response_handler_pt)(ngx_http_request_t *r);

static ngx_int_t ngx_http_dubbo_create_request(ngx_http_request_t *r);
static ngx_int_t ngx_http_dubbo_reinit_request(ngx_http_request_t *r);
static ngx_int_t ngx_http_dubbo_create_dubbo_request(ngx_http_request_t *r, ngx_connection_t *pc
        , ngx_multi_request_t **multi_rptr, ngx_chain_t *in);

static ngx_int_t ngx_http_dubbo_body_output_filter(void *data, ngx_chain_t *in);
static ngx_int_t ngx_http_dubbo_parse_filter(ngx_http_request_t *r);

static ngx_http_dubbo_ctx_t* ngx_http_dubbo_get_ctx(ngx_http_request_t *r);

static ngx_int_t ngx_http_dubbo_filter_init(void *data);
static ngx_int_t ngx_http_dubbo_filter(void *data, ssize_t bytes);
static void ngx_http_dubbo_abort_request(ngx_http_request_t *r);
static void ngx_http_dubbo_finalize_request(ngx_http_request_t *r,
    ngx_int_t rc);

static void *ngx_http_dubbo_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_dubbo_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);

static char *ngx_http_dubbo_pass(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static char *ngx_http_dubbo_pass_set(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

static ngx_int_t ngx_http_dubbo_add_response_header(ngx_http_request_t *r, ngx_str_t *name, ngx_str_t *value);

static ngx_conf_bitmask_t  ngx_http_dubbo_next_upstream_masks[] = {
    { ngx_string("error"), NGX_HTTP_UPSTREAM_FT_ERROR },
    { ngx_string("timeout"), NGX_HTTP_UPSTREAM_FT_TIMEOUT },
    { ngx_string("invalid_header"), NGX_HTTP_UPSTREAM_FT_INVALID_HEADER },
    { ngx_string("non_idempotent"), NGX_HTTP_UPSTREAM_FT_NON_IDEMPOTENT },
    { ngx_string("http_500"), NGX_HTTP_UPSTREAM_FT_HTTP_500 },
    { ngx_string("http_502"), NGX_HTTP_UPSTREAM_FT_HTTP_502 },
    { ngx_string("http_503"), NGX_HTTP_UPSTREAM_FT_HTTP_503 },
    { ngx_string("http_504"), NGX_HTTP_UPSTREAM_FT_HTTP_504 },
    { ngx_string("http_403"), NGX_HTTP_UPSTREAM_FT_HTTP_403 },
    { ngx_string("http_404"), NGX_HTTP_UPSTREAM_FT_HTTP_404 },
    { ngx_string("http_429"), NGX_HTTP_UPSTREAM_FT_HTTP_429 },
    { ngx_string("off"), NGX_HTTP_UPSTREAM_FT_OFF },
    { ngx_null_string, 0 }
};

static ngx_str_t  ngx_http_dubbo_hide_headers[] = {
    ngx_string("Date"),
    ngx_string("Server"),
    ngx_string("X-Pad"),
    ngx_string("X-Accel-Expires"),
    ngx_string("X-Accel-Redirect"),
    ngx_string("X-Accel-Limit-Rate"),
    ngx_string("X-Accel-Buffering"),
    ngx_string("X-Accel-Charset"),
    ngx_null_string
};

static ngx_command_t  ngx_http_dubbo_commands[] = {

    { ngx_string("dubbo_pass"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE4,
      ngx_http_dubbo_pass,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("dubbo_bind"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE12,
      ngx_http_upstream_bind_set_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.local),
      NULL },

    { ngx_string("dubbo_socket_keepalive"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.socket_keepalive),
      NULL },

    { ngx_string("dubbo_connect_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.connect_timeout),
      NULL },

    { ngx_string("dubbo_send_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.send_timeout),
      NULL },

    { ngx_string("dubbo_intercept_errors"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.intercept_errors),
      NULL },

    { ngx_string("dubbo_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.buffer_size),
      NULL },

    { ngx_string("dubbo_read_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.read_timeout),
      NULL },

    { ngx_string("dubbo_next_upstream"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.next_upstream),
      &ngx_http_dubbo_next_upstream_masks },

    { ngx_string("dubbo_next_upstream_tries"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.next_upstream_tries),
      NULL },

    { ngx_string("dubbo_next_upstream_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.next_upstream_timeout),
      NULL },

    { ngx_string("dubbo_pass_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_array_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.pass_headers),
      NULL },

    { ngx_string("dubbo_hide_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_array_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.hide_headers),
      NULL },

    { ngx_string("dubbo_ignore_headers"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, upstream.ignore_headers),
      &ngx_http_upstream_ignore_headers_masks },


    { ngx_string("dubbo_pass_set"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE2,
      ngx_http_dubbo_pass_set,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("dubbo_pass_all_headers"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, pass_all_headers),
      NULL },

    { ngx_string("dubbo_pass_body"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, pass_body),
      NULL },

    { ngx_string("dubbo_heartbeat_interval"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, heartbeat_interval),
      NULL },

    { ngx_string("dubbo_upstream_error_info"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_dubbo_loc_conf_t, ups_info),
      NULL },


      ngx_null_command
};


static ngx_http_module_t  ngx_http_dubbo_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_dubbo_create_loc_conf,        /* create location configuration */
    ngx_http_dubbo_merge_loc_conf          /* merge location configuration */
};


ngx_module_t  ngx_http_dubbo_module = {
    NGX_MODULE_V1,
    &ngx_http_dubbo_module_ctx,            /* module context */
    ngx_http_dubbo_commands,               /* module directives */
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

const ngx_str_t ngx_http_dubbo_str_body = ngx_string("body");
const ngx_str_t ngx_http_dubbo_str_status = ngx_string("status");
const ngx_str_t ngx_http_dubbo_content_type = ngx_string("Content-Type");
const ngx_str_t ngx_http_dubbo_content_type_text = ngx_string("text/html");

static ngx_int_t
ngx_http_dubbo_handler(ngx_http_request_t *r)
{
    ngx_int_t                    rc;
    ngx_http_upstream_t         *u;
    ngx_http_dubbo_ctx_t        *ctx;
    ngx_http_dubbo_loc_conf_t   *dlcf;

    if (ngx_http_upstream_create(r) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_dubbo_ctx_t));
    if (ctx == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ctx->request = r;

    ngx_http_set_ctx(r, ctx, ngx_http_dubbo_module);

    u = r->upstream;

    ngx_str_set(&u->schema, "dubbo://");
    u->output.tag = (ngx_buf_tag_t) &ngx_http_dubbo_module;

    dlcf = ngx_http_get_module_loc_conf(r, ngx_http_dubbo_module);

    u->conf = &dlcf->upstream;

    if (ngx_http_set_content_type(r) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }
 
    u->create_request = ngx_http_dubbo_create_request;
    u->reinit_request = ngx_http_dubbo_reinit_request;
    u->process_header = ngx_http_dubbo_parse_filter;
    u->abort_request = ngx_http_dubbo_abort_request;
    u->finalize_request = ngx_http_dubbo_finalize_request;

    r->state = 0;

#if 0 //just support no buffering upstream for the moment
    u->buffering = dlcf->upstream.buffering;

    u->pipe = ngx_pcalloc(r->pool, sizeof(ngx_event_pipe_t));
    if (u->pipe == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }
#else
    u->buffering = 0;
#endif

    u->input_filter_init = ngx_http_dubbo_filter_init;
    u->input_filter = ngx_http_dubbo_filter;
    u->input_filter_ctx = ctx;

    //only support buffering mode
    r->request_body_no_buffering = 0;

    u->multi_mode = NGX_MULTI_UPS_NEED_MULTI;

    rc = ngx_http_read_client_request_body(r, ngx_http_upstream_init);

    if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return rc;
    }

    return NGX_DONE;
}

ngx_int_t
ngx_http_dubbo_response_handler(ngx_connection_t *pc, ngx_http_request_t *r, ngx_array_t *result)
{
    ngx_http_upstream_t             *u;
    ngx_keyval_t                    *kv;
    ngx_uint_t                       i;
    ngx_chain_t                     *cl;
    ngx_buf_t                       *buf;
    ngx_uint_t                       status;

    u = r->upstream;

    if (u->out_bufs != NULL) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0, "dubbo [%V]: out_bufs is not NULL, %p", r);
        return NGX_ERROR;
    }

    u->headers_in.status_n = NGX_HTTP_BAD_GATEWAY;
    u->state->status = NGX_HTTP_BAD_GATEWAY;

    kv = result->elts;
    for (i=0; i < result->nelts; i++) {
        if (kv[i].key.len == 4 && 0 == ngx_strncasecmp(kv[i].key.data,
                    ngx_http_dubbo_str_body.data, ngx_http_dubbo_str_body.len)) {
            if (kv[i].value.len > 0 && kv[i].value.data != NULL) {
                cl = ngx_chain_get_free_buf(r->pool, &u->free_bufs);
                if (cl == NULL) {
                    return NGX_ERROR;
                }

                u->out_bufs = cl;
                buf = u->out_bufs->buf;

                buf->flush = 1;
                buf->memory = 1;

                buf->pos = kv[i].value.data;
                buf->last = kv[i].value.data + kv[i].value.len;
            }

            u->headers_in.content_length_n = kv[i].value.len;
        } else if (kv[i].key.len == 6 && 0 == ngx_strncasecmp(kv[i].key.data, ngx_http_dubbo_str_status.data, ngx_http_dubbo_str_status.len)) {
            status = ngx_atoi(kv[i].value.data, kv[i].value.len);
            u->headers_in.status_n = status;
            u->state->status = status;
        } else {
            if (NGX_OK != ngx_http_dubbo_add_response_header(r, &kv[i].key, &kv[i].value)) {
                return NGX_ERROR;
            }
        }
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_dubbo_create_request(ngx_http_request_t *r)
{
    ngx_http_upstream_t     *u;

    u = r->upstream;

    u->output.output_filter = ngx_http_dubbo_body_output_filter;
    u->output.filter_ctx = r;

    return NGX_OK;
}

static ngx_int_t
ngx_http_dubbo_body_output_filter(void *data, ngx_chain_t *in)
{
    ngx_http_request_t      *r = data;
    ngx_connection_t        *pc = r->upstream->peer.connection;
    ngx_http_request_t      *fake_r = pc->data;
    ngx_chain_t             *out, *cl, **ll, *tmp;
    ngx_multi_request_t     *multi_r;
    ngx_buf_t               *b;
    u_char                  *start;
    ngx_int_t                rc;
    ngx_multi_connection_t  *multi_c;
    ngx_dubbo_connection_t  *dubbo_c;
    ngx_http_dubbo_loc_conf_t *dlcf;

    ngx_http_dubbo_ctx_t    *ctx = ngx_http_dubbo_get_ctx(fake_r);

    if (!r->upstream->multi) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0, "dubbo: only support upstream multi module");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    multi_c = ngx_get_multi_connection(pc);
    dubbo_c = ctx->connection;

    dlcf = ngx_http_get_module_loc_conf(r, ngx_http_dubbo_module);

    if (r == fake_r && in != NULL) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0, "dubbo: body output failed %p, %p", pc, r);

        return NGX_ERROR;
    }

    out = NULL;
    ll = &out;

    if (ctx->out) {

        *ll = ctx->out;

        for (cl = ctx->out, ll = &cl->next; cl; cl = cl->next) {
            ll = &cl->next;
        }

        ctx->out = NULL;
    }

    if (r != fake_r) { //no need send dubbo request when fake_r

        if (NGX_OK != ngx_http_dubbo_create_dubbo_request(r, pc, &multi_r, in)) {
            ngx_log_error(NGX_LOG_ERR, pc->log, 0, "dubbo: http create request failed %p, %p", pc, r);
            return NGX_ERROR;
        }

        for (cl = multi_r->out; cl; cl = cl->next) {
            tmp = ngx_chain_get_free_buf(fake_r->pool, &ctx->free);
            if (tmp == NULL) {
                return NGX_ERROR;
            }

            b = tmp->buf;
            start = b->start;

            ngx_memcpy(b, cl->buf, sizeof(ngx_buf_t));

            /*
             * restore b->start to preserve memory allocated in the buffer,
             * to reuse it later for headers and control frames
             */

            b->start = start;

            b->tag = (ngx_buf_tag_t) &ngx_http_dubbo_body_output_filter;
            b->shadow = cl->buf;
            b->last_shadow = 1;

            b->last_buf = 0;
            b->last_in_chain = 0;

            *ll = tmp;
            ll = &tmp->next;
        }

        ngx_queue_insert_head(&multi_c->send_list, &multi_r->backend_queue);

        //init front list
        if (r->backend_r == NULL) {
            r->backend_r = ngx_pcalloc(r->connection->pool, sizeof(ngx_queue_t));
            if (r->backend_r == NULL) {
                return NGX_ERROR;
            }

            ngx_queue_init(r->backend_r);
        }

        //add to front list to remove on front close early
        ngx_queue_insert_tail(r->backend_r, &multi_r->front_queue);
    }

    rc = ngx_chain_writer(&fake_r->upstream->writer, out);

    ngx_chain_update_chains(fake_r->pool, &ctx->free, &ctx->busy, &out,
            (ngx_buf_tag_t) &ngx_http_dubbo_body_output_filter);

    for (cl = ctx->free; cl; cl = cl->next) {

        /* mark original buffers as sent */
        if (cl->buf->shadow) {
            if (cl->buf->last_shadow) {
                b = cl->buf->shadow;
                b->pos = b->last;
            }

            cl->buf->shadow = NULL;
        }
    }

    ngx_add_timer(&dubbo_c->ping_event, dlcf->heartbeat_interval);

    return rc;
}

ngx_int_t
ngx_http_dubbo_get_variable(ngx_http_request_t *r, ngx_str_t *name, ngx_str_t *value)
{
    u_char                      *low;
    ngx_str_t                    var;
    ngx_uint_t                   hash;
    ngx_http_variable_value_t   *vv;

    if (0 >= name->len || NULL == name->data) {
        return NGX_ERROR;
    }

    low = ngx_pnalloc(r->pool, name->len);
    if (low == NULL) {
        return NGX_ERROR;
    }

    hash = ngx_hash_strlow(low, name->data, name->len);
    var.data = low;
    var.len = name->len;

    vv = ngx_http_get_variable(r, &var, hash);

    if (vv == NULL || vv->not_found || vv->valid == 0) {
        return NGX_ERROR;
    }

    value->data = vv->data;
    value->len = vv->len;

    return NGX_OK;
}

static ngx_int_t
ngx_http_dubbo_create_dubbo_request(ngx_http_request_t *r, ngx_connection_t *pc, ngx_multi_request_t **multi_rptr, ngx_chain_t *in)
{
    ngx_http_dubbo_ctx_t        *ctx;
    ngx_multi_request_t         *multi_r;
    ngx_dubbo_connection_t      *dubbo_c;
    ngx_http_dubbo_loc_conf_t   *dlcf;

    ngx_str_t                   *service_name;
    ngx_str_t                   *service_version;
    ngx_str_t                   *method;

    ngx_array_t                 *args;
    ngx_dubbo_arg_t             *arg;
    ngx_keyval_t                *kv;
    ngx_uint_t                   n;

    size_t                       len = 0;
    ngx_int_t                    size;
    ngx_buf_t                   *body = NULL;
    ngx_chain_t                 *cl;

    ngx_http_variable_value_t   *vv;
    size_t                       i;

    ctx = ngx_http_dubbo_get_ctx(r);
    dubbo_c = ctx->connection;

    //read body
    for (cl = in; cl; cl = cl->next) {
        len += ngx_buf_size(cl->buf);
    }

    if (len > 0) {
        body = ngx_create_temp_buf(r->pool, len);
        if (body == NULL) {
            return NGX_ERROR;
        }
        for (cl = in; cl; cl = cl->next) {
            if (cl->buf->in_file) {
                size = ngx_read_file(cl->buf->file, body->last,
                        cl->buf->file_last - cl->buf->file_pos, cl->buf->file_pos);

                if (size == NGX_ERROR) {
                    return NGX_ERROR;
                }

                body->last += size;
            } else {
                body->last = ngx_cpymem(body->last, cl->buf->pos, cl->buf->last - cl->buf->pos);
            }
        }
    }

    if (dubbo_c == NULL) {
        return NGX_ERROR;
    }

    multi_r = ngx_create_multi_request(pc, r);
    if (multi_r == NULL) {
        return NGX_ERROR;
    }

    *multi_rptr = multi_r;
    
    dlcf = ngx_http_get_module_loc_conf(r, ngx_http_dubbo_module);

    service_name = ngx_palloc(r->pool, sizeof(ngx_str_t));
    if (service_name == NULL) {
        return NGX_ERROR;
    }

    if (ngx_http_complex_value(r, &dlcf->service_name, service_name)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    service_version = ngx_palloc(r->pool, sizeof(ngx_str_t));
    if (service_version == NULL) {
        return NGX_ERROR;
    }

    if (ngx_http_complex_value(r, &dlcf->service_version, service_version)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    method = ngx_palloc(r->pool, sizeof(ngx_str_t));
    if (method == NULL) {
        return NGX_ERROR;
    }

    if (ngx_http_complex_value(r, &dlcf->method, method)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    args = ngx_array_create(dubbo_c->temp_pool, 1, sizeof(ngx_dubbo_arg_t));
    if (args == NULL) {
        return NGX_ERROR;
    }

    arg = (ngx_dubbo_arg_t*)ngx_array_push(args);
    if (arg == NULL) {
        return NGX_ERROR;
    }

    if (dlcf->args_in == NULL) {
        n = 1;
    } else {
        n = dlcf->args_in->nelts;
    }

    arg->type = DUBBO_ARG_MAP;
    arg->value.m = ngx_array_create(dubbo_c->temp_pool, n, sizeof(ngx_keyval_t));

    if (body && dlcf->pass_body) {
        kv = (ngx_keyval_t*)ngx_array_push(arg->value.m);
        if (kv == NULL) {
            return NGX_ERROR;
        }

        kv->key.data = ngx_http_dubbo_str_body.data;
        kv->key.len = ngx_http_dubbo_str_body.len;
        kv->value.data = body->pos;
        kv->value.len = body->last - body->pos;
    }

    if (dlcf->pass_all_headers) {
        //pass all
        ngx_uint_t                              i;
        ngx_list_part_t                        *part;
        ngx_table_elt_t                        *header;

        part = &r->headers_in.headers.part;
        header = part->elts;

        for (i = 0; /* void */ ; i++) {
            if (i >= part->nelts) {
                if (part->next == NULL) {
                    break;
                }

                part = part->next;
                header = part->elts;
                i = 0;
            }

            kv = (ngx_keyval_t*)ngx_array_push(arg->value.m);
            if (kv == NULL) {
                return NGX_ERROR;
            }

            kv->key.data = header[i].lowcase_key;
            kv->key.len = header[i].key.len;
            kv->value.data = header[i].value.data;
            kv->value.len = header[i].value.len;
        }
    }

    if (dlcf->args_in != NULL) {
        //pass set
        ngx_http_dubbo_arg_t *args_in = dlcf->args_in->elts;
        for (i = 0; i < dlcf->args_in->nelts; i++) {
            kv = (ngx_keyval_t*)ngx_array_push(arg->value.m);
            if (kv == NULL) {
                return NGX_ERROR;
            }

            //get key value
            if (args_in[i].key_var_index != NGX_CONF_UNSET) {
                vv = ngx_http_get_indexed_variable(r, args_in[i].key_var_index);
                if (vv == NULL || vv->not_found) {
                    ngx_log_error(NGX_LOG_WARN, r->connection->log, 0
                            , "dubbo: cannot found pass set key from variable index %ui, %V"
                            , args_in[i].key_var_index, &args_in[i].key);
                    ngx_str_null(&kv->key);
                } else {
                    kv->key.data = vv->data;
                    kv->key.len = vv->len;
                }
            } else {
                kv->key = args_in[i].key;
            }

            if (args_in[i].value_var_index != NGX_CONF_UNSET) {
                vv = ngx_http_get_indexed_variable(r, args_in[i].value_var_index);
                if (vv == NULL || vv->not_found) {
                    ngx_log_error(NGX_LOG_WARN, r->connection->log, 0
                            , "dubbo: cannot found pass set key from variable index %ui, %V"
                            , args_in[i].value_var_index, &args_in[i].value);
                    ngx_str_null(&kv->value);
                } else {
                    kv->value.data = vv->data;
                    kv->value.len = vv->len;
                }
            } else {
                kv->value = args_in[i].value;
            }
        }
    }

    if (NGX_ERROR == ngx_dubbo_encode_request(dubbo_c, service_name,
                                              service_version, method,
                                              args, multi_r))
    {
        ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0,
                      "dubbo: encode request failed");
        return NGX_ERROR;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_dubbo_reinit_request(ngx_http_request_t *r)
{
    return NGX_OK;
}

static ngx_int_t
ngx_http_dubbo_filter_init(void *data)
{
    ngx_http_dubbo_ctx_t  *ctx = data;

    ngx_http_upstream_t  *u;

    u = ctx->request->upstream;

    u->length = 1;

    return NGX_OK;
}

static ngx_int_t
ngx_http_dubbo_filter(void *data, ssize_t bytes)
{
    ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "dubbo: dubbo filter not used");

    return NGX_ERROR;
}

static void
ngx_http_dubbo_abort_request(ngx_http_request_t *r)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "abort http dubbo request");
    return;
}


static void
ngx_http_dubbo_finalize_request(ngx_http_request_t *r, ngx_int_t rc)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "finalize http dubbo request");
    return;
}

static void *
ngx_http_dubbo_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_dubbo_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_dubbo_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->upstream.ignore_headers = 0;
     *     conf->upstream.next_upstream = 0;
     *     conf->upstream.hide_headers_hash = { NULL, 0 };
     *     conf->upstream.ssl_name = NULL;
     *
     */

    conf->upstream.local = NGX_CONF_UNSET_PTR;
    conf->upstream.next_upstream_tries = NGX_CONF_UNSET_UINT;
    conf->upstream.connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->upstream.send_timeout = NGX_CONF_UNSET_MSEC;
    conf->upstream.read_timeout = NGX_CONF_UNSET_MSEC;
    conf->upstream.next_upstream_timeout = NGX_CONF_UNSET_MSEC;

    conf->upstream.buffer_size = NGX_CONF_UNSET_SIZE;

    conf->upstream.hide_headers = NGX_CONF_UNSET_PTR;
    conf->upstream.pass_headers = NGX_CONF_UNSET_PTR;

    conf->upstream.intercept_errors = NGX_CONF_UNSET;

#if (NGX_HTTP_SSL)
    conf->upstream.ssl_session_reuse = NGX_CONF_UNSET;
    conf->upstream.ssl_server_name = NGX_CONF_UNSET;
    conf->upstream.ssl_verify = NGX_CONF_UNSET;
#endif

    /* the hardcoded values */
    conf->upstream.cyclic_temp_file = 0;
    conf->upstream.buffering = 0;
    conf->upstream.ignore_client_abort = 0;
    conf->upstream.send_lowat = 0;
    conf->upstream.bufs.num = 0;
    conf->upstream.busy_buffers_size = 0;
    conf->upstream.max_temp_file_size = 0;
    conf->upstream.temp_file_write_size = 0;
    conf->upstream.pass_request_headers = 1;
    conf->upstream.pass_request_body = 1;
    conf->upstream.force_ranges = 0;
    conf->upstream.pass_trailers = 1;
    conf->upstream.preserve_output = 1;

    ngx_str_set(&conf->upstream.module, "dubbo");

    conf->pass_all_headers = NGX_CONF_UNSET;
    conf->pass_body = NGX_CONF_UNSET;
    conf->ups_info = NGX_CONF_UNSET;
    conf->args_in = NULL;
    conf->heartbeat_interval = NGX_CONF_UNSET_MSEC;

    return conf;
}


static char *
ngx_http_dubbo_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_hash_init_t            hash;
    ngx_http_core_loc_conf_t  *clcf;

    ngx_http_dubbo_loc_conf_t *prev = parent;
    ngx_http_dubbo_loc_conf_t *conf = child;

    ngx_conf_merge_ptr_value(conf->upstream.local,
            prev->upstream.local, NULL);

    ngx_conf_merge_value(conf->upstream.socket_keepalive,
            prev->upstream.socket_keepalive, 0);

    ngx_conf_merge_uint_value(conf->upstream.next_upstream_tries,
            prev->upstream.next_upstream_tries, 0);

    ngx_conf_merge_msec_value(conf->upstream.connect_timeout,
            prev->upstream.connect_timeout, 60000);

    ngx_conf_merge_msec_value(conf->upstream.send_timeout,
            prev->upstream.send_timeout, 60000);

    ngx_conf_merge_msec_value(conf->upstream.read_timeout,
            prev->upstream.read_timeout, 60000);

    ngx_conf_merge_msec_value(conf->upstream.next_upstream_timeout,
            prev->upstream.next_upstream_timeout, 0);

    ngx_conf_merge_size_value(conf->upstream.buffer_size,
            prev->upstream.buffer_size,
            (size_t) ngx_pagesize);

    ngx_conf_merge_bitmask_value(conf->upstream.ignore_headers,
            prev->upstream.ignore_headers,
            NGX_CONF_BITMASK_SET);

    ngx_conf_merge_bitmask_value(conf->upstream.next_upstream,
            prev->upstream.next_upstream,
            (NGX_CONF_BITMASK_SET
             |NGX_HTTP_UPSTREAM_FT_ERROR
             |NGX_HTTP_UPSTREAM_FT_TIMEOUT));

    if (conf->upstream.next_upstream & NGX_HTTP_UPSTREAM_FT_OFF) {
        conf->upstream.next_upstream = NGX_CONF_BITMASK_SET
            |NGX_HTTP_UPSTREAM_FT_OFF;
    }

    ngx_conf_merge_value(conf->upstream.intercept_errors,
            prev->upstream.intercept_errors, 0);

#if (NGX_HTTP_SSL)

    ngx_conf_merge_value(conf->upstream.ssl_session_reuse,
            prev->upstream.ssl_session_reuse, 1);

    if (conf->upstream.ssl_name == NULL) {
        conf->upstream.ssl_name = prev->upstream.ssl_name;
    }

    ngx_conf_merge_value(conf->upstream.ssl_server_name,
            prev->upstream.ssl_server_name, 0);
    ngx_conf_merge_value(conf->upstream.ssl_verify,
            prev->upstream.ssl_verify, 0);

#endif

    hash.max_size = 512;
    hash.bucket_size = ngx_align(64, ngx_cacheline_size);
    hash.name = "dubbo_headers_hash";

    if (ngx_http_upstream_hide_headers_hash(cf, &conf->upstream,
                &prev->upstream, ngx_http_dubbo_hide_headers, &hash)
            != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);

    if (clcf->noname && conf->upstream.upstream == NULL) {
        conf->upstream.upstream = prev->upstream.upstream;
#if (NGX_HTTP_SSL)
        conf->upstream.ssl = prev->upstream.ssl;
#endif
    }

    if (clcf->lmt_excpt && clcf->handler == NULL && conf->upstream.upstream) {
        clcf->handler = ngx_http_dubbo_handler;
    }

    if (conf->service_name.value.data == NULL) {
        conf->service_name = prev->service_name;
    }

    if (conf->service_version.value.data == NULL) {
        conf->service_version = prev->service_version;
    }

    if (conf->method.value.data == NULL) {
        conf->method = prev->method;
    }

    ngx_conf_merge_ptr_value(conf->args_in, prev->args_in, NULL);
    ngx_conf_merge_value(conf->pass_all_headers, prev->pass_all_headers, 1);
    ngx_conf_merge_value(conf->pass_body, prev->pass_body, 1);
    ngx_conf_merge_value(conf->ups_info, prev->ups_info, 0);

    ngx_conf_merge_msec_value(conf->heartbeat_interval,
                              prev->heartbeat_interval, 60000);

    return NGX_CONF_OK;
}

static char *
ngx_http_dubbo_compile_complex_value(ngx_conf_t *cf, ngx_str_t *value,
                                     ngx_http_complex_value_t *cv)
{
    ngx_http_compile_complex_value_t   ccv;

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    ccv.cf = cf;
    ccv.value = value;
    ccv.complex_value = cv;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}

static char *
ngx_http_dubbo_pass(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_dubbo_loc_conf_t *dlcf = conf;

    ngx_str_t                 *value;
    ngx_url_t                  u;
    ngx_http_core_loc_conf_t  *clcf;
    char                      *msg;

    if (dlcf->upstream.upstream) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if ((msg = ngx_http_dubbo_compile_complex_value(cf, &value[1],
                                                    &dlcf->service_name))
        != NGX_CONF_OK)
    {
        return msg;
    }

    if ((msg = ngx_http_dubbo_compile_complex_value(cf, &value[2],
                                                    &dlcf->service_version))
        != NGX_CONF_OK)
    {
        return msg;
    }

    if ((msg = ngx_http_dubbo_compile_complex_value(cf, &value[3],
                                                    &dlcf->method))
        != NGX_CONF_OK)
    {
        return msg;
    }

    ngx_memzero(&u, sizeof(ngx_url_t));

    u.url = value[4];
    u.no_resolve = 1;

    dlcf->upstream.upstream = ngx_http_upstream_add(cf, &u, 0);
    if (dlcf->upstream.upstream == NULL) {
        return NGX_CONF_ERROR;
    }

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);

    clcf->handler = ngx_http_dubbo_handler;

    if (clcf->name.data[clcf->name.len - 1] == '/') {
        clcf->auto_redirect = 1;
    }

    return NGX_CONF_OK;
}

static char *
ngx_http_dubbo_pass_set(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_dubbo_loc_conf_t *dlcf = conf;

    ngx_str_t                 *value;
    ngx_http_dubbo_arg_t        *arg;

    if (dlcf->upstream.upstream) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (dlcf->args_in == NULL) {
        dlcf->args_in = ngx_array_create(cf->pool, 4, sizeof(ngx_http_dubbo_arg_t));
        if (NULL == dlcf->args_in) {
            return NGX_CONF_ERROR;
        }
    }

    arg = (ngx_http_dubbo_arg_t*)ngx_array_push(dlcf->args_in);
    if (arg == NULL) {
        return NGX_CONF_ERROR;
    }

    arg->key = value[1];
    arg->value = value[2];
    arg->key_var_index = NGX_CONF_UNSET;
    arg->value_var_index = NGX_CONF_UNSET;
    if (*value[1].data == '$') {
        arg->key.data += 1;
        arg->key.len -= 1;

        arg->key_var_index = ngx_http_get_variable_index(cf, &arg->key);
    }

    if (*value[2].data == '$') {
        arg->value.data += 1;
        arg->value.len -= 1;

        arg->value_var_index = ngx_http_get_variable_index(cf, &arg->value);
        if (arg->value_var_index == NGX_ERROR) {
            return NGX_CONF_ERROR;
        }
    }

    return NGX_CONF_OK;
}

static void
ngx_http_dubbo_ping_handler(ngx_event_t *ev)
{
    ngx_connection_t        *pc;
    ngx_http_request_t      *fake_r;
    ngx_http_upstream_t     *fake_u;
    ngx_multi_request_t     *multi_r;
    ngx_dubbo_connection_t  *dubbo_c;
    ngx_http_dubbo_ctx_t    *ctx;
    u_char                  *start;
    ngx_chain_t             *cl, *tmp, **ll;
    ngx_buf_t               *b;

    pc = ev->data;
    fake_r = pc->data;
    fake_u = fake_r->upstream;

    ctx = ngx_http_dubbo_get_ctx(fake_r);
    dubbo_c = ctx->connection;

    multi_r = ngx_create_multi_request(pc, fake_r);
    if (multi_r == NULL) {
        return;
    }

    if (NGX_ERROR == ngx_dubbo_encode_ping_request(dubbo_c, multi_r)) {
        ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0,
                      "dubbo: encode ping request failed");
        return;
    }

    for (cl = ctx->out, ll = &ctx->out; cl; cl = cl->next) {
        ll = &cl->next;
    }

    for (cl = multi_r->out; cl; cl = cl->next) {
        tmp = ngx_chain_get_free_buf(fake_r->pool, &ctx->free);
        if (tmp == NULL) {
            return;
        }

        b = tmp->buf;
        start = b->start;

        ngx_memcpy(b, cl->buf, sizeof(ngx_buf_t));

        /*
         * restore b->start to preserve memory allocated in the buffer,
         * to reuse it later for headers and control frames
         */

        b->start = start;

        b->tag = (ngx_buf_tag_t) &ngx_http_dubbo_body_output_filter;
        b->shadow = cl->buf;
        b->last_shadow = 1;

        b->last_buf = 0;
        b->last_in_chain = 0;

        *ll = tmp;
        ll = &tmp->next;
    }

    ngx_post_event(fake_u->peer.connection->write, &ngx_posted_events);
    ngx_log_error(NGX_LOG_INFO, dubbo_c->log, 0,
                  "dubbo: send ping request [%ul] frame to backend", multi_r->id);
    return;
}

static ngx_int_t
ngx_http_dubbo_add_response_header(ngx_http_request_t *r, ngx_str_t *name, ngx_str_t *value)
{
    ngx_table_elt_t                 *h;
    ngx_http_upstream_header_t      *hh;
    ngx_http_upstream_main_conf_t   *umcf;
    ngx_http_upstream_t             *u;

    umcf = ngx_http_get_module_main_conf(r, ngx_http_upstream_module);
    u = r->upstream;

    h = ngx_list_push(&u->headers_in.headers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    h->key = *name;
    h->value = *value;
    h->lowcase_key = ngx_pcalloc(r->pool, h->key.len);
    if (h->lowcase_key == NULL) {
        return NGX_ERROR;
    }
    ngx_strlow(h->lowcase_key, h->key.data, h->key.len);
    h->hash = ngx_hash_key(h->lowcase_key, h->key.len);

    hh = ngx_hash_find(&umcf->headers_in_hash, h->hash,
            h->lowcase_key, h->key.len);

    if (hh && hh->handler(r, h, hh->offset) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_dubbo_parse_filter(ngx_http_request_t *r)
{
    ngx_http_request_t              *fake_r;
    ngx_http_upstream_t             *fake_u;
    ngx_chain_t                      in;
    ngx_http_dubbo_ctx_t            *ctx, *fake_ctx;
    ngx_int_t                        ret;
    ngx_http_request_t              *real_r;

    ngx_queue_t                     *q, *n;
    ngx_multi_request_t             *multi_r, *tmp;
    ngx_dubbo_resp_t                *resp;
    ngx_str_t                        body;
    ngx_flag_t                       find;
    ngx_dubbo_connection_t          *dubbo_c;
    ngx_multi_connection_t          *multi_c;
    ngx_connection_t                *pc;

    ngx_http_dubbo_loc_conf_t       *dlcf;
    ngx_keyval_t                    *kv;

    fake_r = r;
    fake_u = r->upstream;

    in.buf = &fake_u->buffer;
    in.next = NULL;

    if (!fake_u->multi) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "dubbo: only support upstream multi module");
        return NGX_ERROR;
    }

    fake_ctx = ngx_http_dubbo_get_ctx(fake_r);
    ctx = fake_ctx;

    dubbo_c = ctx->connection;

    pc = fake_u->peer.connection;

    multi_c = ngx_get_multi_connection(pc);

    switch (ctx->state) {
        case ngx_http_dubbo_parse_st_start:
            multi_c->cur = NULL;
            for ( ; ; ) {
                ret = ngx_dubbo_decode_response(dubbo_c, &in);

                if (ret == NGX_ERROR) {
                    ngx_log_error(NGX_LOG_WARN, dubbo_c->log, 0, "dubbo: response parse error");
                    return NGX_ERROR;
                } else if (ret == NGX_DONE) {
                    resp = &dubbo_c->resp;

                    if (resp->header.type & DUBBO_FLAG_PING) {
                        //ping frame
                        if (resp->header.type & DUBBO_FLAG_REQ) {
                            ngx_log_error(NGX_LOG_INFO, dubbo_c->log, 0,
                                          "dubbo: get a ping request frame [%ul] from backend", resp->header.reqid);
#if 0
                            //no need send response just moment
                            ngx_post_event(fake_u->peer.connection->write, &ngx_posted_events);
#endif
                        } else {
                            ngx_log_error(NGX_LOG_INFO, dubbo_c->log, 0,
                                          "dubbo: get a ping response frame [%ul] from backend", resp->header.reqid);
                        }
                        continue;
                    }

                    find = 0;
                    for (q = ngx_queue_head(&multi_c->send_list);
                            q != ngx_queue_sentinel(&multi_c->send_list);
                            q = ngx_queue_next(q))
                    {
                        multi_r = ngx_queue_data(q, ngx_multi_request_t, backend_queue);
                        if (multi_r->id == resp->header.reqid) { //find
                            find = 1;
                            ngx_queue_remove(q);

                            //clean front list for multi_r 
                            real_r = multi_r->data;
                            if (real_r->backend_r) {
                                for (n = ngx_queue_head(real_r->backend_r);
                                        n != ngx_queue_sentinel(real_r->backend_r);
                                        n = ngx_queue_next(n))
                                {
                                    tmp = ngx_queue_data(n, ngx_multi_request_t, front_queue); 
                                    if (tmp == multi_r) {
                                        ngx_queue_remove(n);
                                        break;
                                    }
                                }
                            } else {
                                ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: find dubbo_r but front list null");
                                //free dubbo_r and pool
                                ngx_destroy_pool(multi_r->pool);
                                return NGX_ERROR;
                            }

                            body.data = resp->payload;
                            body.len = resp->header.payloadlen;

                            multi_c->cur = multi_r->data;

                            if (NGX_OK != ngx_dubbo_hessian2_decode_payload_map(real_r->pool,
                                        &body, &ctx->result, dubbo_c->log)) {

                                ngx_log_error(NGX_LOG_WARN, dubbo_c->log,
                                              0, "dubbo: response decode result failed %V", &body);

                                dlcf = ngx_http_get_module_loc_conf(real_r, ngx_http_dubbo_module);
                                if (dlcf->ups_info) {
                                    ctx->result = ngx_array_create(real_r->pool, 2, sizeof(ngx_keyval_t));
                                    if (ctx->result == NULL) {
                                        return NGX_ERROR;
                                    };
                                    kv = (ngx_keyval_t*)ngx_array_push(ctx->result);
                                    kv->key = ngx_http_dubbo_str_body;
                                    kv->value = body;

                                    kv = (ngx_keyval_t*)ngx_array_push(ctx->result);
                                    kv->key = ngx_http_dubbo_content_type;
                                    kv->value = ngx_http_dubbo_content_type_text;
                                } else {
                                    real_r->upstream->headers_in.status_n = NGX_HTTP_BAD_GATEWAY;
                                    real_r->upstream->state->status = NGX_HTTP_BAD_GATEWAY;
                                    ngx_destroy_pool(multi_r->pool);
                                    return NGX_HTTP_UPSTREAM_PARSE_ERROR;
                                }
                            }

                            if (NGX_OK != ngx_http_dubbo_response_handler(pc, real_r, ctx->result)) {
                                ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: response handler failed %V", &body);
                                real_r->upstream->headers_in.status_n = NGX_HTTP_INTERNAL_SERVER_ERROR;
                                real_r->upstream->state->status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                                ngx_destroy_pool(multi_r->pool);
                                return NGX_ERROR;
                            }

                            ctx->state = ngx_http_dubbo_parse_st_payload;
                            ngx_destroy_pool(multi_r->pool);
                            return NGX_HTTP_UPSTREAM_HEADER_END;
                        }
                    }

                    if (!find) {
                        ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0,
                                      "dubbo: response cannot find request %ui", resp->header.reqid);
                    }

                    continue;
                } else {
                    ngx_log_error(NGX_LOG_INFO, dubbo_c->log, 0, "dubbo: response parse again");
                    break;
                }
            }

            return NGX_AGAIN;
        case ngx_http_dubbo_parse_st_payload:
            if (multi_c->cur == NULL) {
                ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo [%V]: parse body not found real_r");
                break;
            }
            real_r = multi_c->cur;
            real_r->upstream->length = 0;
            ctx->state = ngx_http_dubbo_parse_st_start;
            return NGX_HTTP_UPSTREAM_GET_BODY_DATA;
            //return NGX_ERROR;
        default:
            ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: parse state error");
            break;
    }

    return NGX_ERROR;
}

static void
ngx_http_dubbo_cleanup(void *data)
{
#if 0
    ngx_dubbo_connection_t  *dubbo_c = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, dubbo_c->log, 0,
                   "dubbo cleanup");
#endif
    return;
}

static ngx_int_t
ngx_http_dubbo_get_connection_data(ngx_http_request_t *r,
        ngx_http_dubbo_ctx_t *ctx, ngx_peer_connection_t *pc)
{
    ngx_connection_t        *c;
    ngx_pool_cleanup_t      *cln;

    c = pc->connection;

    for (cln = c->pool->cleanup; cln; cln = cln->next) {
        if (cln->handler == ngx_http_dubbo_cleanup) {
            ctx->connection = cln->data;
            break;
        }
    }

    if (ctx->connection == NULL) {
        cln = ngx_pool_cleanup_add(c->pool, sizeof(ngx_dubbo_connection_t));
        if (cln == NULL) {
            return NGX_ERROR;
        }

        cln->handler = ngx_http_dubbo_cleanup;
        ctx->connection = cln->data;

        if(NGX_OK != ngx_dubbo_init_connection(ctx->connection, c, ngx_http_dubbo_ping_handler)) {
            return NGX_ERROR;
        }

        ngx_log_error(NGX_LOG_INFO, c->log, 0,
                      "dubbo: pc %p create dubbo connection %p", c, ctx->connection);
    }

    return NGX_OK;
}


static ngx_http_dubbo_ctx_t*
ngx_http_dubbo_get_ctx(ngx_http_request_t *r)
{
    ngx_http_dubbo_ctx_t    *ctx;
    ngx_http_upstream_t     *u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_dubbo_module);

    if (ctx == NULL) {
        //need create ctx when fake_r
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_dubbo_ctx_t));
        if (ctx == NULL) {
            return NULL;
        }

        ctx->request = r;

        ngx_http_set_ctx(r, ctx, ngx_http_dubbo_module);

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "create dubbo ctx on create request, maybe fake_r");
    }

    if (ctx->connection == NULL) {
        u = r->upstream;

        if (ngx_http_dubbo_get_connection_data(r, ctx, &u->peer) != NGX_OK) {
            return NULL;
        }
    }

    return ctx;
}
