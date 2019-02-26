
/*
 * Copyright (C) Nginx, Inc.
 * Copyright (C) Valentin V. Bartenev
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_http_v2_module.h>


static ngx_int_t ngx_http_v2_add_variables(ngx_conf_t *cf);

static ngx_int_t ngx_http_v2_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);

static ngx_int_t ngx_http_v2_module_init(ngx_cycle_t *cycle);

static void *ngx_http_v2_create_main_conf(ngx_conf_t *cf);
static char *ngx_http_v2_init_main_conf(ngx_conf_t *cf, void *conf);
static void *ngx_http_v2_create_srv_conf(ngx_conf_t *cf);
static char *ngx_http_v2_merge_srv_conf(ngx_conf_t *cf, void *parent,
    void *child);
static void *ngx_http_v2_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_v2_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);

static char *ngx_http_v2_push(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

static char *ngx_http_v2_recv_buffer_size(ngx_conf_t *cf, void *post,
    void *data);
static char *ngx_http_v2_pool_size(ngx_conf_t *cf, void *post, void *data);
static char *ngx_http_v2_preread_size(ngx_conf_t *cf, void *post, void *data);
static char *ngx_http_v2_streams_index_mask(ngx_conf_t *cf, void *post,
    void *data);
static char *ngx_http_v2_chunk_size(ngx_conf_t *cf, void *post, void *data);
static char *ngx_http_v2_spdy_deprecated(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


static ngx_conf_post_t  ngx_http_v2_recv_buffer_size_post =
    { ngx_http_v2_recv_buffer_size };
static ngx_conf_post_t  ngx_http_v2_pool_size_post =
    { ngx_http_v2_pool_size };
static ngx_conf_post_t  ngx_http_v2_preread_size_post =
    { ngx_http_v2_preread_size };
static ngx_conf_post_t  ngx_http_v2_streams_index_mask_post =
    { ngx_http_v2_streams_index_mask };
static ngx_conf_post_t  ngx_http_v2_chunk_size_post =
    { ngx_http_v2_chunk_size };


static ngx_command_t  ngx_http_v2_commands[] = {

    { ngx_string("http2_recv_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_v2_main_conf_t, recv_buffer_size),
      &ngx_http_v2_recv_buffer_size_post },

    { ngx_string("http2_pool_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, pool_size),
      &ngx_http_v2_pool_size_post },

    { ngx_string("http2_max_concurrent_streams"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, concurrent_streams),
      NULL },

    { ngx_string("http2_max_concurrent_pushes"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, concurrent_pushes),
      NULL },

    { ngx_string("http2_max_requests"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, max_requests),
      NULL },

    { ngx_string("http2_max_field_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, max_field_size),
      NULL },

    { ngx_string("http2_max_header_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, max_header_size),
      NULL },

    { ngx_string("http2_body_preread_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, preread_size),
      &ngx_http_v2_preread_size_post },

    { ngx_string("http2_streams_index_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, streams_index_mask),
      &ngx_http_v2_streams_index_mask_post },

    { ngx_string("http2_recv_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, recv_timeout),
      NULL },

    { ngx_string("http2_idle_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, idle_timeout),
      NULL },

    { ngx_string("http2_chunk_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_v2_loc_conf_t, chunk_size),
      &ngx_http_v2_chunk_size_post },

    { ngx_string("http2_push_preload"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_v2_loc_conf_t, push_preload),
      NULL },

    { ngx_string("http2_push"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_push,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("spdy_recv_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_spdy_deprecated,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("spdy_pool_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_spdy_deprecated,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("spdy_max_concurrent_streams"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_spdy_deprecated,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("spdy_streams_index_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_spdy_deprecated,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("spdy_recv_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_spdy_deprecated,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("spdy_keepalive_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_spdy_deprecated,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("spdy_headers_comp"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_spdy_deprecated,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("spdy_chunk_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_v2_spdy_deprecated,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

#if (T_NGX_HTTP2_SRV_ENABLE)
    { ngx_string("http2"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_v2_srv_conf_t, enable),
      NULL },
#endif

      ngx_null_command
};


static ngx_http_module_t  ngx_http_v2_module_ctx = {
    ngx_http_v2_add_variables,             /* preconfiguration */
    NULL,                                  /* postconfiguration */

    ngx_http_v2_create_main_conf,          /* create main configuration */
    ngx_http_v2_init_main_conf,            /* init main configuration */

    ngx_http_v2_create_srv_conf,           /* create server configuration */
    ngx_http_v2_merge_srv_conf,            /* merge server configuration */

    ngx_http_v2_create_loc_conf,           /* create location configuration */
    ngx_http_v2_merge_loc_conf             /* merge location configuration */
};


ngx_module_t  ngx_http_v2_module = {
    NGX_MODULE_V1,
    &ngx_http_v2_module_ctx,               /* module context */
    ngx_http_v2_commands,                  /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    ngx_http_v2_module_init,               /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_variable_t  ngx_http_v2_vars[] = {

    { ngx_string("http2"), NULL,
      ngx_http_v2_variable, 0, 0, 0 },

      ngx_http_null_variable
};


static ngx_int_t
ngx_http_v2_add_variables(ngx_conf_t *cf)
{
    ngx_http_variable_t  *var, *v;

    for (v = ngx_http_v2_vars; v->name.len; v++) {
        var = ngx_http_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }

        var->get_handler = v->get_handler;
        var->data = v->data;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_v2_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{

    if (r->stream) {
#if (NGX_HTTP_SSL)

        if (r->connection->ssl) {
            v->len = sizeof("h2") - 1;
            v->valid = 1;
            v->no_cacheable = 0;
            v->not_found = 0;
            v->data = (u_char *) "h2";

            return NGX_OK;
        }

#endif
        v->len = sizeof("h2c") - 1;
        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;
        v->data = (u_char *) "h2c";

        return NGX_OK;
    }

    *v = ngx_http_variable_null_value;

    return NGX_OK;
}


static ngx_int_t
ngx_http_v2_module_init(ngx_cycle_t *cycle)
{
    return NGX_OK;
}


static void *
ngx_http_v2_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_v2_main_conf_t  *h2mcf;

    h2mcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_v2_main_conf_t));
    if (h2mcf == NULL) {
        return NULL;
    }

    h2mcf->recv_buffer_size = NGX_CONF_UNSET_SIZE;

    return h2mcf;
}


static char *
ngx_http_v2_init_main_conf(ngx_conf_t *cf, void *conf)
{
    ngx_http_v2_main_conf_t *h2mcf = conf;

    ngx_conf_init_size_value(h2mcf->recv_buffer_size, 256 * 1024);

    return NGX_CONF_OK;
}


static void *
ngx_http_v2_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_v2_srv_conf_t  *h2scf;

    h2scf = ngx_pcalloc(cf->pool, sizeof(ngx_http_v2_srv_conf_t));
    if (h2scf == NULL) {
        return NULL;
    }

    h2scf->pool_size = NGX_CONF_UNSET_SIZE;

    h2scf->concurrent_streams = NGX_CONF_UNSET_UINT;
    h2scf->concurrent_pushes = NGX_CONF_UNSET_UINT;
    h2scf->max_requests = NGX_CONF_UNSET_UINT;

    h2scf->max_field_size = NGX_CONF_UNSET_SIZE;
    h2scf->max_header_size = NGX_CONF_UNSET_SIZE;

    h2scf->preread_size = NGX_CONF_UNSET_SIZE;

    h2scf->streams_index_mask = NGX_CONF_UNSET_UINT;

    h2scf->recv_timeout = NGX_CONF_UNSET_MSEC;
    h2scf->idle_timeout = NGX_CONF_UNSET_MSEC;

#if (T_NGX_HTTP2_SRV_ENABLE)
    h2scf->enable = NGX_CONF_UNSET;
#endif

    return h2scf;
}


static char *
ngx_http_v2_merge_srv_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_v2_srv_conf_t *prev = parent;
    ngx_http_v2_srv_conf_t *conf = child;

    ngx_conf_merge_size_value(conf->pool_size, prev->pool_size, 4096);

    ngx_conf_merge_uint_value(conf->concurrent_streams,
                              prev->concurrent_streams, 128);
    ngx_conf_merge_uint_value(conf->concurrent_pushes,
                              prev->concurrent_pushes, 10);
    ngx_conf_merge_uint_value(conf->max_requests, prev->max_requests, 1000);

    ngx_conf_merge_size_value(conf->max_field_size, prev->max_field_size,
                              4096);
    ngx_conf_merge_size_value(conf->max_header_size, prev->max_header_size,
                              16384);

    ngx_conf_merge_size_value(conf->preread_size, prev->preread_size, 65536);

    ngx_conf_merge_uint_value(conf->streams_index_mask,
                              prev->streams_index_mask, 32 - 1);

    ngx_conf_merge_msec_value(conf->recv_timeout,
                              prev->recv_timeout, 30000);
    ngx_conf_merge_msec_value(conf->idle_timeout,
                              prev->idle_timeout, 180000);

#if (T_NGX_HTTP2_SRV_ENABLE)
    if (conf->enable == NGX_CONF_UNSET) {
        conf->enable = prev->enable;
    }
#endif

    return NGX_CONF_OK;
}


static void *
ngx_http_v2_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_v2_loc_conf_t  *h2lcf;

    h2lcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_v2_loc_conf_t));
    if (h2lcf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     h2lcf->pushes = NULL;
     */

    h2lcf->chunk_size = NGX_CONF_UNSET_SIZE;

    h2lcf->push_preload = NGX_CONF_UNSET;
    h2lcf->push = NGX_CONF_UNSET;

    return h2lcf;
}


static char *
ngx_http_v2_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_v2_loc_conf_t *prev = parent;
    ngx_http_v2_loc_conf_t *conf = child;

    ngx_conf_merge_size_value(conf->chunk_size, prev->chunk_size, 8 * 1024);

    ngx_conf_merge_value(conf->push, prev->push, 1);

    if (conf->push && conf->pushes == NULL) {
        conf->pushes = prev->pushes;
    }

    ngx_conf_merge_value(conf->push_preload, prev->push_preload, 0);

    return NGX_CONF_OK;
}


static char *
ngx_http_v2_push(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_v2_loc_conf_t *h2lcf = conf;

    ngx_str_t                         *value;
    ngx_http_complex_value_t          *cv;
    ngx_http_compile_complex_value_t   ccv;

    value = cf->args->elts;

    if (ngx_strcmp(value[1].data, "off") == 0) {

        if (h2lcf->pushes) {
            return "\"off\" parameter cannot be used with URI";
        }

        if (h2lcf->push == 0) {
            return "is duplicate";
        }

        h2lcf->push = 0;
        return NGX_CONF_OK;
    }

    if (h2lcf->push == 0) {
        return "URI cannot be used with \"off\" parameter";
    }

    h2lcf->push = 1;

    if (h2lcf->pushes == NULL) {
        h2lcf->pushes = ngx_array_create(cf->pool, 1,
                                         sizeof(ngx_http_complex_value_t));
        if (h2lcf->pushes == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    cv = ngx_array_push(h2lcf->pushes);
    if (cv == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    ccv.cf = cf;
    ccv.value = &value[1];
    ccv.complex_value = cv;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_v2_recv_buffer_size(ngx_conf_t *cf, void *post, void *data)
{
    size_t *sp = data;

    if (*sp <= 2 * NGX_HTTP_V2_STATE_BUFFER_SIZE) {
        return "value is too small";
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_v2_pool_size(ngx_conf_t *cf, void *post, void *data)
{
    size_t *sp = data;

    if (*sp < NGX_MIN_POOL_SIZE) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "the pool size must be no less than %uz",
                           NGX_MIN_POOL_SIZE);

        return NGX_CONF_ERROR;
    }

    if (*sp % NGX_POOL_ALIGNMENT) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "the pool size must be a multiple of %uz",
                           NGX_POOL_ALIGNMENT);

        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_v2_preread_size(ngx_conf_t *cf, void *post, void *data)
{
    size_t *sp = data;

    if (*sp > NGX_HTTP_V2_MAX_WINDOW) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "the maximum body preread buffer size is %uz",
                           NGX_HTTP_V2_MAX_WINDOW);

        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_v2_streams_index_mask(ngx_conf_t *cf, void *post, void *data)
{
    ngx_uint_t *np = data;

    ngx_uint_t  mask;

    mask = *np - 1;

    if (*np == 0 || (*np & mask)) {
        return "must be a power of two";
    }

    *np = mask;

    return NGX_CONF_OK;
}


static char *
ngx_http_v2_chunk_size(ngx_conf_t *cf, void *post, void *data)
{
    size_t *sp = data;

    if (*sp == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "the http2 chunk size cannot be zero");

        return NGX_CONF_ERROR;
    }

    if (*sp > NGX_HTTP_V2_MAX_FRAME_SIZE) {
        *sp = NGX_HTTP_V2_MAX_FRAME_SIZE;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_v2_spdy_deprecated(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                       "invalid directive \"%V\": ngx_http_spdy_module "
                       "was superseded by ngx_http_v2_module", &cmd->name);

    return NGX_CONF_OK;
}
