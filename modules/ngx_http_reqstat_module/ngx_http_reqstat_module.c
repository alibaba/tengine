/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_reqstat.h>


static ngx_http_input_body_filter_pt  ngx_http_next_input_body_filter;
extern ngx_int_t (*ngx_http_write_filter_stat)(ngx_http_request_t *r);


static variable_index_t REQSTAT_RSRV_VARIABLES[NGX_HTTP_REQSTAT_RSRV] = {
    variable_index("bytes_in", 0),
    variable_index("bytes_out", 1),
    variable_index("conn_total", 2),
    variable_index("req_total", 3),
    variable_index("http_2xx", 4),
    variable_index("http_3xx", 5),
    variable_index("http_4xx", 6),
    variable_index("http_5xx", 7),
    variable_index("http_other_status", 8),
    variable_index("rt", 9),
    variable_index("ups_req", 10),
    variable_index("ups_rt", 11),
    variable_index("ups_tries", 12),
    variable_index("http_200", 13),
    variable_index("http_206", 14),
    variable_index("http_302", 15),
    variable_index("http_304", 16),
    variable_index("http_403", 17),
    variable_index("http_404", 18),
    variable_index("http_416", 19),
    variable_index("http_499", 20),
    variable_index("http_500", 21),
    variable_index("http_502", 22),
    variable_index("http_503", 23),
    variable_index("http_504", 24),
    variable_index("http_508", 25),
    variable_index("http_other_detail_status", 26),
    variable_index("http_ups_4xx", 27),
    variable_index("http_ups_5xx", 28),
};


off_t ngx_http_reqstat_fields[29] = {
    NGX_HTTP_REQSTAT_BYTES_IN,
    NGX_HTTP_REQSTAT_BYTES_OUT,
    NGX_HTTP_REQSTAT_CONN_TOTAL,
    NGX_HTTP_REQSTAT_REQ_TOTAL,
    NGX_HTTP_REQSTAT_2XX,
    NGX_HTTP_REQSTAT_3XX,
    NGX_HTTP_REQSTAT_4XX,
    NGX_HTTP_REQSTAT_5XX,
    NGX_HTTP_REQSTAT_OTHER_STATUS,
    NGX_HTTP_REQSTAT_RT,
    NGX_HTTP_REQSTAT_UPS_REQ,
    NGX_HTTP_REQSTAT_UPS_RT,
    NGX_HTTP_REQSTAT_UPS_TRIES,
    NGX_HTTP_REQSTAT_200,
    NGX_HTTP_REQSTAT_206,
    NGX_HTTP_REQSTAT_302,
    NGX_HTTP_REQSTAT_304,
    NGX_HTTP_REQSTAT_403,
    NGX_HTTP_REQSTAT_404,
    NGX_HTTP_REQSTAT_416,
    NGX_HTTP_REQSTAT_499,
    NGX_HTTP_REQSTAT_500,
    NGX_HTTP_REQSTAT_502,
    NGX_HTTP_REQSTAT_503,
    NGX_HTTP_REQSTAT_504,
    NGX_HTTP_REQSTAT_508,
    NGX_HTTP_REQSTAT_OTHER_DETAIL_STATUS,
    NGX_HTTP_REQSTAT_UPS_4XX,
    NGX_HTTP_REQSTAT_UPS_5XX
};


static void *ngx_http_reqstat_create_main_conf(ngx_conf_t *cf);
static void *ngx_http_reqstat_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_reqstat_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static ngx_int_t ngx_http_reqstat_init(ngx_conf_t *cf);
static ngx_int_t ngx_http_reqstat_add_variable(ngx_conf_t *cf);

static ngx_int_t ngx_http_reqstat_variable_enable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);

static char *ngx_http_reqstat_show(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_reqstat_show_field(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_reqstat_zone(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_reqstat_zone_add_indicator(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_http_reqstat_zone_key_length(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_http_reqstat_zone_recycle(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_http_reqstat(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static void ngx_http_reqstat_count(void *data, off_t offset,
    ngx_int_t incr);
static ngx_int_t ngx_http_reqstat_init_zone(ngx_shm_zone_t *shm_zone,
    void *data);

static ngx_int_t ngx_http_reqstat_log_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_reqstat_init_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_reqstat_show_handler(ngx_http_request_t *r);

static void ngx_http_reqstat_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel);
static ngx_http_reqstat_store_t *
    ngx_http_reqstat_create_store(ngx_http_request_t *r,
    ngx_http_reqstat_conf_t *rlcf);
static ngx_int_t ngx_http_reqstat_check_enable(ngx_http_request_t *r,
    ngx_http_reqstat_conf_t **rlcf, ngx_http_reqstat_store_t **store);

static ngx_int_t ngx_http_reqstat_input_body_filter(ngx_http_request_t *r,
    ngx_buf_t *buf);

ngx_int_t ngx_http_reqstat_log_flow(ngx_http_request_t *r);


static ngx_command_t   ngx_http_reqstat_commands[] = {

    { ngx_string("req_status_zone"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_2MORE,
      ngx_http_reqstat_zone,
      0,
      0,
      NULL },

    { ngx_string("req_status"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_reqstat,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("req_status_bypass"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_set_predicate_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_reqstat_conf_t, bypass),
      NULL },

    { ngx_string("req_status_show"),
      NGX_HTTP_LOC_CONF|NGX_CONF_ANY,
      ngx_http_reqstat_show,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("req_status_show_field"),
      NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_reqstat_show_field,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("req_status_zone_add_indicator"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_2MORE,
      ngx_http_reqstat_zone_add_indicator,
      0,
      0,
      NULL },

    { ngx_string("req_status_zone_key_length"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE2,
      ngx_http_reqstat_zone_key_length,
      0,
      0,
      NULL },

    { ngx_string("req_status_zone_recycle"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE3,
      ngx_http_reqstat_zone_recycle,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_reqstat_module_ctx = {
    ngx_http_reqstat_add_variable,         /* preconfiguration */
    ngx_http_reqstat_init,                 /* postconfiguration */

    ngx_http_reqstat_create_main_conf,     /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_reqstat_create_loc_conf,      /* create location configuration */
    ngx_http_reqstat_merge_loc_conf        /* merge location configuration */
};


ngx_module_t  ngx_http_reqstat_module = {
    NGX_MODULE_V1,
    &ngx_http_reqstat_module_ctx,          /* module context */
    ngx_http_reqstat_commands,             /* module directives */
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


static void *
ngx_http_reqstat_create_main_conf(ngx_conf_t *cf)
{
    return ngx_pcalloc(cf->pool, sizeof(ngx_http_reqstat_conf_t));
}


static void *
ngx_http_reqstat_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_reqstat_conf_t      *conf;

    conf = ngx_palloc(cf->pool, sizeof(ngx_http_reqstat_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    conf->bypass = NGX_CONF_UNSET_PTR;
    conf->monitor = NGX_CONF_UNSET_PTR;
    conf->display = NGX_CONF_UNSET_PTR;
    conf->user_select = NGX_CONF_UNSET_PTR;
    conf->user_defined_str = NGX_CONF_UNSET_PTR;

    return conf;
}


static char *
ngx_http_reqstat_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child)
{
    ngx_http_reqstat_conf_t      *conf = child;
    ngx_http_reqstat_conf_t      *prev = parent;

    ngx_conf_merge_ptr_value(conf->bypass, prev->bypass, NULL);
    ngx_conf_merge_ptr_value(conf->monitor, prev->monitor, NULL);
    ngx_conf_merge_ptr_value(conf->display, prev->display, NULL);
    ngx_conf_merge_ptr_value(conf->user_select, prev->user_select, NULL);
    ngx_conf_merge_ptr_value(conf->user_defined_str, prev->user_defined_str, NULL);

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_reqstat_add_variable(ngx_conf_t *cf)
{
    ngx_str_t                  name = ngx_string("reqstat_enable");
    ngx_http_variable_t       *var;
    ngx_http_reqstat_conf_t   *rmcf;

    rmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_reqstat_module);

    var = ngx_http_add_variable(cf, &name, 0);
    if (var == NULL) {
        return NGX_ERROR;
    }

    var->get_handler = ngx_http_reqstat_variable_enable;
    var->data = 0;

    rmcf->index = ngx_http_get_variable_index(cf, &name);

    if (rmcf->index == NGX_ERROR) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_reqstat_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt          *h;
    ngx_http_core_main_conf_t    *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_LOG_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_reqstat_log_handler;

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_REWRITE_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_reqstat_init_handler;

    ngx_http_next_input_body_filter = ngx_http_top_input_body_filter;
    ngx_http_top_input_body_filter = ngx_http_reqstat_input_body_filter;

    ngx_http_write_filter_stat = ngx_http_reqstat_log_flow;

    return NGX_OK;
}


static char *
ngx_http_reqstat_show_field(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_int_t                  valid, *index;
    ngx_str_t                 *value, *user;
    ngx_uint_t                 i, j;
    ngx_http_reqstat_conf_t   *rmcf, *rlcf;

    rlcf = conf;
    rmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_reqstat_module);

    rlcf->user_select = ngx_array_create(cf->pool, cf->args->nelts - 1,
                                         sizeof(ngx_int_t));
    if (rlcf->user_select == NULL) {
        return NGX_CONF_ERROR;
    }

    index = ngx_array_push_n(rlcf->user_select, cf->args->nelts - 1);
    if (index == NULL) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;
    for (i = 1; i < cf->args->nelts; i++) {
        valid = 0;

        if (value[i].data[0] == '$') {
            value[i].data++;
            value[i].len--;

            if (rmcf->user_defined_str) {

                user = rmcf->user_defined_str->elts;

                for (j = 0; j < rmcf->user_defined_str->nelts; j++) {
                    if (value[i].len != user[j].len
                            || ngx_strncmp(value[i].data, user[j].data, value[i].len)
                            != 0)
                    {
                        continue;
                    }

                    *index++ = NGX_HTTP_REQSTAT_RSRV + j;
                    valid = 1;
                    break;
                }
            }

        } else {
            for (j = 0; j < NGX_HTTP_REQSTAT_RSRV; j++) {
                if (value[i].len != REQSTAT_RSRV_VARIABLES[j].name.len
                    || ngx_strncmp(REQSTAT_RSRV_VARIABLES[j].name.data,
                                   value[i].data, value[i].len) != 0)
                {
                    continue;
                }

                *index++ = REQSTAT_RSRV_VARIABLES[j].index;
                valid = 1;
                break;
            }
        }

        if (!valid) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "field \"%V\" does not exist",
                          &value[i]);

            return NGX_CONF_ERROR;
        }
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_reqstat_show(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                    *value;
    ngx_uint_t                    i;
    ngx_shm_zone_t               *shm_zone, **z;
    ngx_http_core_loc_conf_t     *clcf;

    ngx_http_reqstat_conf_t      *rlcf = conf;

    value = cf->args->elts;

    if (rlcf->display != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    if (cf->args->nelts == 1) {
        rlcf->display = NULL;
        goto reg_handler;
    }

    rlcf->display = ngx_array_create(cf->pool, cf->args->nelts - 1,
                                     sizeof(ngx_shm_zone_t *));
    if (rlcf->display == NULL) {
        return NGX_CONF_ERROR;
    }

    for (i = 1; i < cf->args->nelts; i++) {
        shm_zone = ngx_shared_memory_add(cf, &value[i], 0,
                                         &ngx_http_reqstat_module);
        if (shm_zone == NULL) {
            return NGX_CONF_ERROR;
        }

        z = ngx_array_push(rlcf->display);
        *z = shm_zone;
    }

reg_handler:

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_reqstat_show_handler;

    return NGX_CONF_OK;
}


static char *
ngx_http_reqstat_zone_add_indicator(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_int_t                         *i;
    ngx_str_t                         *value, *name;
    ngx_uint_t                         j;
    ngx_shm_zone_t                    *shm_zone;
    ngx_http_reqstat_ctx_t            *ctx;
    ngx_http_reqstat_conf_t           *rlcf;

    rlcf = conf;
    value = cf->args->elts;

    shm_zone = ngx_shared_memory_add(cf, &value[1], 0,
                                     &ngx_http_reqstat_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (shm_zone->data == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "zone \"%V\" should be defined first",
                           &value[1]);
        return NGX_CONF_ERROR;
    }

    ctx = shm_zone->data;

    if (ctx->user_defined != NULL) {
        return "is duplicate";
    }

    if (cf->args->nelts > NGX_HTTP_REQSTAT_USER + 2) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "too many user defined variables");
        return NGX_CONF_ERROR;
    }

    ctx->user_defined = ngx_array_create(cf->pool, cf->args->nelts - 2,
                                         sizeof(ngx_int_t));
    if (ctx->user_defined == NULL) {
        return NGX_CONF_ERROR;
    }

    rlcf->user_defined_str = ngx_array_create(cf->pool, cf->args->nelts - 2,
                                              sizeof(ngx_str_t));
    if (rlcf->user_defined_str == NULL) {
        return NGX_CONF_ERROR;
    }

    for (j = 2; j < cf->args->nelts; j++) {
        if (value[j].data[0] == '$') {
            value[j].data++;
            value[j].len--;
        }

        name = ngx_array_push(rlcf->user_defined_str);
        name->len = value[j].len;
        name->data = value[j].data;

        i = ngx_array_push(ctx->user_defined);
        *i = ngx_http_get_variable_index(cf, &value[j]);
        if (*i == NGX_ERROR) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "failed to obtain variable \"%V\"",
                               &value[j]);
            return NGX_CONF_ERROR;
        }
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_reqstat_zone_key_length(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_str_t                         *value;
    ngx_shm_zone_t                    *shm_zone;
    ngx_http_reqstat_ctx_t            *ctx;

    value = cf->args->elts;

    shm_zone = ngx_shared_memory_add(cf, &value[1], 0,
                                     &ngx_http_reqstat_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (shm_zone->data == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "zone \"%V\" should be defined first",
                           &value[1]);
        return NGX_CONF_ERROR;
    }

    ctx = shm_zone->data;

    ctx->key_len = ngx_atoi(value[2].data, value[2].len);
    if (ctx->key_len == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid key length");
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_reqstat_zone_recycle(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_int_t                          rate, scale;
    ngx_str_t                         *value;
    ngx_shm_zone_t                    *shm_zone;
    ngx_http_reqstat_ctx_t            *ctx;

    value = cf->args->elts;

    shm_zone = ngx_shared_memory_add(cf, &value[1], 0,
                                     &ngx_http_reqstat_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (shm_zone->data == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "zone \"%V\" should be defined first",
                           &value[1]);
        return NGX_CONF_ERROR;
    }

    ctx = shm_zone->data;

    rate = ngx_atoi(value[2].data, value[2].len);
    if (rate == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid threshold");
        return NGX_CONF_ERROR;
    }

    scale = ngx_atoi(value[3].data, value[3].len);
    if (scale == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid scale");
        return NGX_CONF_ERROR;
    }

    ctx->recycle_rate = rate * 1000 / scale;

    return NGX_CONF_OK;
}


static char *
ngx_http_reqstat_zone(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ssize_t                            size;
    ngx_str_t                         *value;
    ngx_shm_zone_t                    *shm_zone;
    ngx_http_reqstat_ctx_t            *ctx;
    ngx_http_compile_complex_value_t   ccv;

    value = cf->args->elts;

    size = ngx_parse_size(&value[3]);
    if (size == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid zone size \"%V\"", &value[3]);
        return NGX_CONF_ERROR;
    }

    if (size < (ssize_t) (8 * ngx_pagesize)) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "zone \"%V\" is too small", &value[1]);
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_reqstat_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    if (ngx_http_script_variables_count(&value[2]) == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "the value \"%V\" is a constant",
                           &value[2]);
        return NGX_CONF_ERROR;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    ccv.cf = cf;
    ccv.value = &value[2];
    ccv.complex_value = &ctx->value;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    ctx->val = ngx_palloc(cf->pool, sizeof(ngx_str_t));
    if (ctx->val == NULL) {
        return NGX_CONF_ERROR;
    }
    *ctx->val = value[2];

    ctx->key_len = 152;          /* now an item is 640B at length. */
    ctx->recycle_rate = 167;     /* rate threshold is 10r/min */
    ctx->alloc_already_fail = 0;

    shm_zone = ngx_shared_memory_add(cf, &value[1], size,
                                     &ngx_http_reqstat_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (shm_zone->data) {
        ctx = shm_zone->data;

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "%V \"%V\" is already bound to value \"%V\"",
                           &cmd->name, &value[1], ctx->val);
        return NGX_CONF_ERROR;
    }

    shm_zone->init = ngx_http_reqstat_init_zone;
    shm_zone->data = ctx;

    return NGX_CONF_OK;
}


static char *
ngx_http_reqstat(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                    *value;
    ngx_uint_t                    i, j;
    ngx_shm_zone_t               *shm_zone, **z;
    ngx_http_reqstat_conf_t      *smcf;

    ngx_http_reqstat_conf_t      *rlcf = conf;

    value = cf->args->elts;
    smcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_reqstat_module);

    if (rlcf->monitor != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    if (smcf->monitor == NULL) {
        smcf->monitor = ngx_array_create(cf->pool, cf->args->nelts - 1,
                                         sizeof(ngx_shm_zone_t *));
        if (smcf->monitor == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    rlcf->monitor = ngx_array_create(cf->pool, cf->args->nelts - 1,
                                     sizeof(ngx_shm_zone_t *));
    if (rlcf->monitor == NULL) {
        return NGX_CONF_ERROR;
    }

    for (i = 1; i < cf->args->nelts; i++) {
        shm_zone = ngx_shared_memory_add(cf, &value[i], 0,
                                         &ngx_http_reqstat_module);
        if (shm_zone == NULL) {
            return NGX_CONF_ERROR;
        }

        z = ngx_array_push(rlcf->monitor);
        *z = shm_zone;

        z = smcf->monitor->elts;
        for (j = 0; j < smcf->monitor->nelts; j++) {
            if (!ngx_strcmp(value[i].data, z[j]->shm.name.data)) {
                break;
            }
        }

        if (j == smcf->monitor->nelts) {
            z = ngx_array_push(smcf->monitor);
            if (z == NULL) {
                return NGX_CONF_ERROR;
            }
            *z = shm_zone;
        }
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_reqstat_variable_enable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    u_char                       *p;
    ngx_http_reqstat_store_t     *store;

    p = ngx_pnalloc(r->pool, 1 + sizeof(uintptr_t));
    if (p == NULL) {
        return NGX_ERROR;
    }

    v->len = 1;
    v->valid = 1;
    v->not_found = 0;
    v->no_cacheable = 0;
    v->data = p;

    store = ngx_http_get_module_ctx(r, ngx_http_reqstat_module);
    if (store == NULL || store->bypass) {
        *p = '0';

    } else {
        *p++ = '1';
        *((uintptr_t *) p) = (uintptr_t) store;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_reqstat_init_handler(ngx_http_request_t *r)
{
    ngx_http_reqstat_conf_t      *rmcf, *rlcf;
    ngx_http_reqstat_store_t     *store;

    store = ngx_http_get_module_ctx(r, ngx_http_reqstat_module);
    rmcf = ngx_http_get_module_main_conf(r, ngx_http_reqstat_module);
    rlcf = ngx_http_get_module_loc_conf(r, ngx_http_reqstat_module);

    if (store == NULL) {
        if (r->variables[rmcf->index].valid) {
            return NGX_DECLINED;
        }

        store = ngx_http_reqstat_create_store(r, rlcf);
        if (store == NULL) {
            return NGX_ERROR;
        }

        ngx_http_set_ctx(r, store, ngx_http_reqstat_module);
    }

    if (ngx_http_get_indexed_variable(r, rmcf->index) == NULL) {
        return NGX_ERROR;
    }

    return NGX_DECLINED;
}


static ngx_int_t
ngx_http_reqstat_log_handler(ngx_http_request_t *r)
{
    u_char                       *p;
    ngx_int_t                    *indicator, iv;
    ngx_uint_t                    i, j, k, status, utries;
    ngx_time_t                   *tp;
    ngx_msec_int_t                ms, total_ms;
    ngx_shm_zone_t              **shm_zone, *z;
    ngx_http_reqstat_ctx_t       *ctx;
    ngx_http_reqstat_conf_t      *rcf;
    ngx_http_reqstat_store_t     *store;
    ngx_http_reqstat_rbnode_t    *fnode, **fnode_store;
    ngx_http_upstream_state_t    *state;
    ngx_http_variable_value_t    *v;

    switch (ngx_http_reqstat_check_enable(r, &rcf, &store)) {
        case NGX_ERROR:
            return NGX_ERROR;

        case NGX_DECLINED:
        case NGX_AGAIN:
            return NGX_OK;

        default:
            break;
    }

    shm_zone = rcf->monitor->elts;
    fnode_store = store->monitor_index.elts;
    for (i = 0; i < store->monitor_index.nelts; i++) {
        fnode = fnode_store[i];
        if (r->connection->requests == 1) {
            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_CONN_TOTAL, 1);
        }

        ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_REQ_TOTAL, 1);
        ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_BYTES_IN,
                               r->connection->received
                                    - (store ? store->recv : 0));

        if (r->err_status) {
            status = r->err_status;

        } else if (r->headers_out.status) {
            status = r->headers_out.status;

        } else if (r->http_version == NGX_HTTP_VERSION_9) {
            status = 9;

        } else {
            status = 0;
        }

        if (status >= 200 && status < 300) {
            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_2XX, 1);

            switch (status) {
            case 200:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_200, 1);
                break;

            case 206:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_206, 1);
                break;

            default:
                ngx_http_reqstat_count(fnode,
                                       NGX_HTTP_REQSTAT_OTHER_DETAIL_STATUS, 1);
                break;
            }

        } else if (status >= 300 && status < 400) {
            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_3XX, 1);

            switch (status) {
            case 302:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_302, 1);
                break;

            case 304:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_304, 1);
                break;

            default:
                ngx_http_reqstat_count(fnode,
                                       NGX_HTTP_REQSTAT_OTHER_DETAIL_STATUS, 1);
                break;
            }

        } else if (status >= 400 && status < 500) {
            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_4XX, 1);

            switch (status) {
            case 403:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_403, 1);
                break;

            case 404:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_404, 1);
                break;

            case 416:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_416, 1);
                break;

            case 499:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_499, 1);
                break;

            default:
                ngx_http_reqstat_count(fnode,
                                       NGX_HTTP_REQSTAT_OTHER_DETAIL_STATUS, 1);
                break;
            }

        } else if (status >= 500 && status < 600) {
            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_5XX, 1);

            switch (status) {
            case 500:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_500, 1);
                break;

            case 502:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_502, 1);
                break;

            case 503:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_503, 1);
                break;

            case 504:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_504, 1);
                break;

            case 508:
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_508, 1);
                break;

            default:
                ngx_http_reqstat_count(fnode,
                                       NGX_HTTP_REQSTAT_OTHER_DETAIL_STATUS, 1);
                break;
            }

        } else {
            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_OTHER_STATUS, 1);

            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_OTHER_DETAIL_STATUS,
                                   1);
        }

        /* response status of last upstream peer */

        if (r->upstream_states != NULL && r->upstream_states->nelts > 0) {
            ngx_http_upstream_state_t *state = r->upstream_states->elts;
            status = state[r->upstream_states->nelts - 1].status;

            if (status >= 400 && status < 500) {
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_UPS_4XX, 1);

            } else if (status >= 500 && status < 600) {
                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_UPS_5XX, 1);
            }
        }

        tp = ngx_timeofday();

        ms = (ngx_msec_int_t)
             ((tp->sec - r->start_sec) * 1000 + (tp->msec - r->start_msec));
        ms = ngx_max(ms, 0);
        ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_RT, ms);

        if (r->upstream_states != NULL && r->upstream_states->nelts > 0) {
            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_UPS_REQ, 1);

            j = 0;
            total_ms = 0;
            utries = 0;
            state = r->upstream_states->elts;

            for ( ;; ) {

                utries++;

#if nginx_version >= 1009002
                ms = state[j].response_time;
#else
                ms = (ngx_msec_int_t) (state[j].response_sec * 1000
                                               + state[j].response_msec);
#endif
                ms = ngx_max(ms, 0);
                total_ms += ms;

                if (++j == r->upstream_states->nelts) {
                    break;
                }

                if (state[j].peer == NULL) {
                    if (++j == r->upstream_states->nelts) {
                        break;
                    }
                }
            }

            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_UPS_RT,
                                   total_ms);
            ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_UPS_TRIES,
                                   utries);
        }

        z = shm_zone[i];
        ctx = z->data;

        if (ctx->user_defined) {
            indicator = ctx->user_defined->elts;
            for (j = 0; j < ctx->user_defined->nelts; j++) {
                v = ngx_http_get_indexed_variable(r, indicator[j]);
                if (v == NULL || v->not_found || !v->valid) {
                    ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                                  "variable is uninitialized");
                    continue;
                }

                for (k = 0, p = v->data + v->len - 1; p >= v->data; p--) {
                    if (*p == '.') {
                        k = v->data + v->len - 1 - p;
                        continue;
                    }

                    if (*p < '0' || *p > '9') {
                        break;
                    }
                }

                p++;

                if (k) {
                    iv = ngx_atofp(p, v->data + v->len - p, k);

                } else {
                    iv = ngx_atoi(p, v->data + v->len - p);
                }

                if (iv == NGX_ERROR) {
                    continue;
                }

                ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_EXTRA(j), iv);
            }
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_reqstat_show_handler(ngx_http_request_t *r)
{
    ngx_int_t                     rc, *user, index;
    ngx_buf_t                    *b;
    ngx_uint_t                    i, j;
    ngx_array_t                  *display;
    ngx_chain_t                  *tl, out, **cl;
    ngx_queue_t                  *q;
    ngx_shm_zone_t              **shm_zone;
    ngx_http_reqstat_ctx_t       *ctx;
    ngx_http_reqstat_conf_t      *rlcf;
    ngx_http_reqstat_conf_t      *smcf;
    ngx_http_reqstat_rbnode_t    *node;

    rlcf = ngx_http_get_module_loc_conf(r, ngx_http_reqstat_module);
    smcf = ngx_http_get_module_main_conf(r, ngx_http_reqstat_module);

    display = rlcf->display == NULL ? smcf->monitor : rlcf->display;
    if (display == NULL) {
        r->headers_out.status = NGX_HTTP_NO_CONTENT;
        return ngx_http_send_header(r);
    }

    r->headers_out.status = NGX_HTTP_OK;
    ngx_http_clear_content_length(r);

    rc = ngx_http_send_header(r);
    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    shm_zone = display->elts;

    cl = &out.next;

    for (i = 0; i < display->nelts; i++) {

        ctx = shm_zone[i]->data;

        for (q = ngx_queue_head(&ctx->sh->queue);
             q != ngx_queue_sentinel(&ctx->sh->queue);
             q = ngx_queue_next(q))
        {
            node = ngx_queue_data(q, ngx_http_reqstat_rbnode_t, queue);

            if (node->conn_total == 0) {
                continue;
            }

            tl = ngx_alloc_chain_link(r->pool);
            if (tl == NULL) {
                return NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            b = ngx_calloc_buf(r->pool);
            if (b == NULL) {
                return NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            tl->buf = b;
            b->start = ngx_pcalloc(r->pool, 512);
            if (b->start == NULL) {
                return NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            b->end = b->start + 512;
            b->last = b->pos = b->start;
            b->temporary = 1;

            b->last = ngx_slprintf(b->last, b->end, "%*s,",
                                   (size_t) node->len, node->data);
            if (rlcf->user_select) {
                user = rlcf->user_select->elts;
                for (j = 0; j < rlcf->user_select->nelts; j++) {
                    if (user[j] < NGX_HTTP_REQSTAT_RSRV) {
                        index = user[j];
                        b->last = ngx_slprintf(b->last, b->end, "%uA,",
                                        *NGX_HTTP_REQSTAT_REQ_FIELD(node,
                                              ngx_http_reqstat_fields[index]));

                    } else {
                        index = user[j] - NGX_HTTP_REQSTAT_RSRV;
                        b->last = ngx_slprintf(b->last, b->end, "%uA,",
                                        *NGX_HTTP_REQSTAT_REQ_FIELD(node,
                                               NGX_HTTP_REQSTAT_EXTRA(index)));
                    }
                }

            } else {

                for (j = 0; j < NGX_HTTP_REQSTAT_RSRV; j++) {
                    b->last = ngx_slprintf(b->last, b->end, "%uA,",
                                       *NGX_HTTP_REQSTAT_REQ_FIELD(node,
                                                  ngx_http_reqstat_fields[j]));
                }

                if (ctx->user_defined) {
                    for (j = 0; j < ctx->user_defined->nelts; j++) {
                        b->last = ngx_slprintf(b->last, b->end, "%uA,",
                                           *NGX_HTTP_REQSTAT_REQ_FIELD(node,
                                                   NGX_HTTP_REQSTAT_EXTRA(j)));
                    }
                }
            }

            *(b->last - 1) = '\n';

            tl->next = NULL;
            *cl = tl;
            cl = &tl->next;
        }
    }

    tl = ngx_alloc_chain_link(r->pool);
    if (tl == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    tl->buf = ngx_calloc_buf(r->pool);
    if (tl->buf == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    tl->buf->last_buf = 1;
    tl->next = NULL;
    *cl = tl;

    return ngx_http_output_filter(r, out.next);
}


void
ngx_http_reqstat_count(void *data, off_t offset, ngx_int_t incr)
{
    ngx_http_reqstat_rbnode_t    *node = data;

    (void) ngx_atomic_fetch_add(NGX_HTTP_REQSTAT_REQ_FIELD(node, offset), incr);
}


ngx_http_reqstat_rbnode_t *
ngx_http_reqstat_rbtree_lookup(ngx_shm_zone_t *shm_zone, ngx_str_t *val)
{
    size_t                        size, len;
    uint32_t                      hash;
    ngx_int_t                     rc, excess;
    ngx_time_t                   *tp;
    ngx_msec_t                    now;
    ngx_queue_t                  *q;
    ngx_msec_int_t                ms;
    ngx_rbtree_node_t            *node, *sentinel;
    ngx_http_reqstat_ctx_t       *ctx;
    ngx_http_reqstat_rbnode_t    *rs;

    ctx = shm_zone->data;

    hash = ngx_murmur_hash2(val->data, val->len);

    node = ctx->sh->rbtree.root;
    sentinel = ctx->sh->rbtree.sentinel;

    tp = ngx_timeofday();
    now = (ngx_msec_t) (tp->sec * 1000 + tp->msec);

    ngx_shmtx_lock(&ctx->shpool->mutex);

    while (node != sentinel) {

        if (hash < node->key) {
            node = node->left;
            continue;
        }

        if (hash > node->key) {
            node = node->right;
            continue;
        }

        /* hash == node->key */

        rs = (ngx_http_reqstat_rbnode_t *) &node->color;

        /* len < node->len */

        if (val->len < (size_t) rs->len) {
            node = node->left;
            continue;
        }

        rc = ngx_strncmp(val->data, rs->data, (size_t) rs->len);

        if (rc == 0) {

            ms = (ngx_msec_int_t) (now - rs->last_visit);

            rs->excess = rs->excess - ngx_abs(ms) * ctx->recycle_rate / 1000
                       + 1000;
            rs->last_visit = now;

            if (rs->excess > 0) {
                ngx_queue_remove(&rs->visit);
                ngx_queue_insert_head(&ctx->sh->visit, &rs->visit);
            }

            ngx_log_debug2(NGX_LOG_DEBUG_CORE, shm_zone->shm.log, 0,
                           "reqstat lookup exist: %*s", rs->len, rs->data);

            ngx_shmtx_unlock(&ctx->shpool->mutex);

            return rs;
        }

        node = (rc < 0) ? node->left : node->right;
    }

    rc = 0;
    node = NULL;

    size = offsetof(ngx_rbtree_node_t, color)
         + offsetof(ngx_http_reqstat_rbnode_t, data)
         + ctx->key_len;

    if (ctx->alloc_already_fail == 0) {
        node = ngx_slab_alloc_locked(ctx->shpool, size);
        if (node == NULL) {
            ctx->alloc_already_fail = 1;
        }
    }

    if (node == NULL) {

        /* try to free a vacant node */
        q = ngx_queue_last(&ctx->sh->visit);
        rs = ngx_queue_data(q, ngx_http_reqstat_rbnode_t, visit);

        ms = (ngx_msec_int_t) (now - rs->last_visit);

        excess = rs->excess - ngx_abs(ms) * ctx->recycle_rate / 1000;

        ngx_log_debug3(NGX_LOG_DEBUG_CORE, shm_zone->shm.log, 0,
                       "reqstat lookup try recycle: %*s, %d", rs->len, rs->data, excess);

        if (excess < 0) {

            rc = 1;

            node = (ngx_rbtree_node_t *)
                            ((char *) rs - offsetof(ngx_rbtree_node_t, color));
            ngx_rbtree_delete(&ctx->sh->rbtree, node);
            ngx_queue_remove(&rs->visit);

            ngx_log_debug2(NGX_LOG_DEBUG_CORE, shm_zone->shm.log, 0,
                           "reqstat lookup recycle: %*s", rs->len, rs->data);

            rs->conn_total = 0;

            ngx_memzero((void *) &rs->bytes_in, size - offsetof(ngx_rbtree_node_t, color)
                                            - offsetof(ngx_http_reqstat_rbnode_t, bytes_in));

        } else {
            ngx_shmtx_unlock(&ctx->shpool->mutex);
            return NULL;
        }
    }

    node->key = hash;

    rs = (ngx_http_reqstat_rbnode_t *) &node->color;

    len = ngx_min(ctx->key_len, (ssize_t) val->len);
    ngx_memcpy(rs->data, val->data, len);
    rs->len = len;

    ngx_rbtree_insert(&ctx->sh->rbtree, node);
    ngx_queue_insert_head(&ctx->sh->visit, &rs->visit);
    if (!rc) {
        ngx_queue_insert_head(&ctx->sh->queue, &rs->queue);
    }

    rs->last_visit = now;
    rs->excess = 1000;

    ngx_log_debug2(NGX_LOG_DEBUG_CORE, shm_zone->shm.log, 0, "reqstat lookup build: %*s", rs->len, rs->data);

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    return rs;
}


static ngx_int_t
ngx_http_reqstat_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    size_t                        n;
    ngx_http_reqstat_ctx_t       *ctx, *octx;

    octx = data;
    ctx = shm_zone->data;

    if (octx != NULL) {
        if (ngx_strcmp(ctx->val->data, octx->val->data) != 0) {
            ngx_log_error(NGX_LOG_EMERG, shm_zone->shm.log, 0,
                          "reqstat \"%V\" uses the value str \"%V\" "
                          "while previously it used \"%V\"",
                          &shm_zone->shm.name, ctx->val, octx->val);
            return NGX_ERROR;
        }

        ctx->shpool = octx->shpool;
        ctx->sh = octx->sh;

        return NGX_OK;
    }

    ctx->shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;

    ctx->sh = ngx_slab_alloc(ctx->shpool, sizeof(ngx_http_reqstat_shctx_t));
    if (ctx->sh == NULL) {
        return NGX_ERROR;
    }

    ctx->shpool->data = ctx->sh;

    n = sizeof(" in req_status zone \"\"") + shm_zone->shm.name.len;
    ctx->shpool->log_ctx = ngx_slab_alloc(ctx->shpool, n);
    if (ctx->shpool->log_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_sprintf(ctx->shpool->log_ctx,
                " in req_status zone \"%V\"%Z",
                &shm_zone->shm.name);

    ngx_rbtree_init(&ctx->sh->rbtree, &ctx->sh->sentinel,
                    ngx_http_reqstat_rbtree_insert_value);

    ngx_queue_init(&ctx->sh->queue);
    ngx_queue_init(&ctx->sh->visit);

    return NGX_OK;
}


static void
ngx_http_reqstat_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel)
{
    ngx_rbtree_node_t          **p;
    ngx_http_reqstat_rbnode_t   *rsn, *rsnt;

    for ( ;; ) {

        if (node->key < temp->key) {

            p = &temp->left;

        } else if (node->key > temp->key) {

            p = &temp->right;

        } else { /* node->key == temp->key */

            rsn = (ngx_http_reqstat_rbnode_t *) &node->color;
            rsnt = (ngx_http_reqstat_rbnode_t *) &temp->color;

            p = (ngx_memn2cmp(rsn->data, rsnt->data, rsn->len, rsnt->len) < 0)
                ? &temp->left : &temp->right;
        }

        if (*p == sentinel) {
            break;
        }

        temp = *p;
    }

    *p = node;
    node->parent = temp;
    node->left = sentinel;
    node->right = sentinel;
    ngx_rbt_red(node);
}


static ngx_int_t
ngx_http_reqstat_input_body_filter(ngx_http_request_t *r, ngx_buf_t *buf)
{
    ngx_uint_t                    i, diff;
    ngx_http_reqstat_conf_t      *rcf;
    ngx_http_reqstat_store_t     *store;
    ngx_http_reqstat_rbnode_t    *fnode, **fnode_store;

    switch (ngx_http_reqstat_check_enable(r, &rcf, &store)) {
        case NGX_ERROR:
            return NGX_ERROR;

        case NGX_DECLINED:
        case NGX_AGAIN:
            return ngx_http_next_input_body_filter(r, buf);

        default:
            break;
    }

    diff = r->connection->received - store->recv;
    store->recv = r->connection->received;

    fnode_store = store->monitor_index.elts;
    for (i = 0; i < store->monitor_index.nelts; i++) {
        fnode = fnode_store[i];
        ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_BYTES_IN, diff);
    }

    return ngx_http_next_input_body_filter(r, buf);
}


ngx_int_t
ngx_http_reqstat_log_flow(ngx_http_request_t *r)
{
    ngx_uint_t                    i, diff;
    ngx_http_reqstat_conf_t      *rcf;
    ngx_http_reqstat_store_t     *store;
    ngx_http_reqstat_rbnode_t    *fnode, **fnode_store;

    switch (ngx_http_reqstat_check_enable(r, &rcf, &store)) {
        case NGX_ERROR:
            return NGX_ERROR;

        case NGX_DECLINED:
        case NGX_AGAIN:
            return NGX_OK;

        default:
            break;
    }

    diff = r->connection->sent - store->sent;
    store->sent = r->connection->sent;

    fnode_store = store->monitor_index.elts;
    for (i = 0; i < store->monitor_index.nelts; i++) {
        fnode = fnode_store[i];
        ngx_http_reqstat_count(fnode, NGX_HTTP_REQSTAT_BYTES_OUT, diff);
    }

    return NGX_OK;
}


static ngx_http_reqstat_store_t *
ngx_http_reqstat_create_store(ngx_http_request_t *r,
    ngx_http_reqstat_conf_t *rlcf)
{
    ngx_str_t                     val;
    ngx_uint_t                    i;
    ngx_shm_zone_t              **shm_zone, *z;
    ngx_http_reqstat_ctx_t       *ctx;
    ngx_http_reqstat_store_t     *store;
    ngx_http_reqstat_rbnode_t    *fnode, **fnode_store;

    store = ngx_pcalloc(r->pool, sizeof(ngx_http_reqstat_store_t));
    if (store == NULL) {
        return NULL;
    }

    if (rlcf->monitor == NULL) {
        store->bypass = 1;
        return store;
    }

    store->conf = rlcf;

    switch (ngx_http_test_predicates(r, rlcf->bypass)) {

    case NGX_ERROR:
        return NULL;

    case NGX_DECLINED:
        store->bypass = 1;
        return store;

    default: /* NGX_OK */
        break;
    }

    if (ngx_array_init(&store->monitor_index, r->pool, rlcf->monitor->nelts,
                       sizeof(ngx_http_reqstat_rbnode_t *)) == NGX_ERROR)
    {
        return NULL;
    }

    shm_zone = rlcf->monitor->elts;
    for (i = 0; i < rlcf->monitor->nelts; i++) {
        z = shm_zone[i];
        ctx = z->data;

        if (ngx_http_complex_value(r, &ctx->value, &val) != NGX_OK) {
            ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                          "failed to reap the key \"%V\"", ctx->val);
            continue;
        }

        fnode = ngx_http_reqstat_rbtree_lookup(shm_zone[i], &val);

        if (fnode == NULL) {
            ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                          "failed to alloc node in zone \"%V\", "
                          "enlarge it please",
                          &z->shm.name);

        } else {
            fnode_store = ngx_array_push(&store->monitor_index);
            *fnode_store = fnode;
        }
    }

    return store;
}


static ngx_int_t
ngx_http_reqstat_check_enable(ngx_http_request_t *r,
    ngx_http_reqstat_conf_t **rlcf, ngx_http_reqstat_store_t **store)
{
    ngx_http_reqstat_conf_t      *rcf;
    ngx_http_reqstat_store_t     *s;
    ngx_http_variable_value_t    *v;

    rcf = ngx_http_get_module_main_conf(r, ngx_http_reqstat_module);
    if (r->variables[rcf->index].valid) {
        v = ngx_http_get_flushed_variable(r, rcf->index);

        if (v->data[0] == '0') {
            return NGX_DECLINED;
        }

        s = (ngx_http_reqstat_store_t *) (*((uintptr_t *) &v->data[1]));
        rcf = s->conf;

    } else {
        rcf = ngx_http_get_module_loc_conf(r, ngx_http_reqstat_module);

        s = ngx_http_get_module_ctx(r, ngx_http_reqstat_module);

        if (s == NULL) {
            s = ngx_http_reqstat_create_store(r, rcf);
            if (s == NULL) {
                return NGX_ERROR;
            }
        }

        if (s->bypass) {
            return NGX_DECLINED;
        }
    }

    *rlcf = rcf;
    *store = s;

    return NGX_OK;
}
