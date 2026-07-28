
/*
 *  Copyright (C) 2010-2019 Alibaba Group Holding Limited
 */



#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


extern ngx_module_t  ngx_http_headers_filter_module;
typedef struct ngx_http_header_val_s  ngx_http_header_val_t;

typedef ngx_int_t (*ngx_http_set_header_pt)(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);


struct ngx_http_header_val_s {
    ngx_http_complex_value_t   value;
    ngx_str_t                  key;
    ngx_http_set_header_pt     handler;
    ngx_uint_t                 offset;
    ngx_uint_t                 always;  /* unsigned  always:1 */
};


typedef enum {
    NGX_HTTP_EXPIRES_OFF,
    NGX_HTTP_EXPIRES_EPOCH,
    NGX_HTTP_EXPIRES_MAX,
    NGX_HTTP_EXPIRES_ACCESS,
    NGX_HTTP_EXPIRES_MODIFIED,
    NGX_HTTP_EXPIRES_DAILY,
    NGX_HTTP_EXPIRES_UNSET
} ngx_http_expires_t;


typedef struct {
    ngx_http_expires_t         expires;
    time_t                     expires_time;
    ngx_http_complex_value_t  *expires_value;
    ngx_array_t               *headers;
    ngx_array_t               *trailers;
} ngx_http_headers_conf_t;


typedef struct {
    ngx_str_t                  separator;
} ngx_http_append_header_conf_t;


static void *ngx_http_append_header_create_conf(ngx_conf_t *cf);
static char *ngx_http_append_header_merge_conf(ngx_conf_t *cf,
    void *parent, void *child);
static char *ngx_http_headers_append(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_append_header(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);


static ngx_command_t  ngx_http_append_header_commands[] = {
    { ngx_string("append_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE2,
      ngx_http_headers_append,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL},

    { ngx_string("append_header_separator"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_append_header_conf_t, separator),
      NULL},

      ngx_null_command
};


static ngx_http_module_t  ngx_http_append_header_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_append_header_create_conf,    /* create location configuration */
    ngx_http_append_header_merge_conf      /* merge location configuration */
};


ngx_module_t  ngx_http_append_header_module = {
    NGX_MODULE_V1,
    &ngx_http_append_header_module_ctx,    /* module context */
    ngx_http_append_header_commands,       /* module directives */
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
ngx_http_append_header_create_conf(ngx_conf_t *cf)
{
    ngx_http_append_header_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_append_header_conf_t));
    if (conf == NULL) {
        return NULL;
    }
    
    return conf;
}


static char *
ngx_http_append_header_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_append_header_conf_t *prev = parent;
    ngx_http_append_header_conf_t *conf = child;

    ngx_conf_merge_str_value(conf->separator, prev->separator, ", ");

    return NGX_CONF_OK;
}


static char *
ngx_http_headers_append(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_headers_conf_t           *hcf;
    ngx_str_t                         *value;
    ngx_http_header_val_t             *hv;
    ngx_http_compile_complex_value_t   ccv;

    value = cf->args->elts;

    hcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_headers_filter_module);
    if (hcf == NULL) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "get ngx_http_headers_filter_module loc conf is NULL.");
        return NGX_CONF_ERROR;
    }

    if (hcf->headers == NULL) {
        hcf->headers = ngx_array_create(cf->pool, 1,
                                        sizeof(ngx_http_header_val_t));
        if (hcf->headers == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    hv = ngx_array_push(hcf->headers);
    if (hv == NULL) {
        return NGX_CONF_ERROR;
    }

    hv->key = value[1];
    hv->handler = ngx_http_append_header;
    hv->offset = 0;

    if (value[2].len == 0) {
        ngx_memzero(&hv->value, sizeof(ngx_http_complex_value_t));
        return NGX_CONF_OK;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    ccv.cf = cf;
    ccv.value = &value[2];
    ccv.complex_value = &hv->value;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_append_header(ngx_http_request_t *r, ngx_http_header_val_t *hv,
    ngx_str_t *value)
{
    u_char                         *p, *data;
    ngx_uint_t                      i, len;
    ngx_table_elt_t                *h, *hf;
    ngx_list_part_t                *part;
    ngx_http_append_header_conf_t  *ahcf;

    if (value->len == 0) {
        return NGX_OK;
    }

    part =  &r->headers_out.headers.part;
    h = (ngx_table_elt_t *) part->elts;
    hf = NULL;
    ahcf = ngx_http_get_module_loc_conf(r, ngx_http_append_header_module);
    if (ahcf == NULL) {
        return NGX_OK;
    }

    for (i = 0; /* void */; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            h = (ngx_table_elt_t *) part->elts;
            i = 0;
        }

        if (h[i].hash == 0) {
            continue;
        }

        if (h[i].key.len == hv->key.len
            && ngx_strncasecmp(h[i].key.data, hv->key.data,
                               h[i].key.len) == 0)
            {
                hf = h + i;
            }

        /* not matched */
        continue;
    }

    if (hf == NULL) {

        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        h->hash = 1;
        h->key = hv->key;
        h->value = *value;

    } else {
        h = hf;
        len = h->value.len + ahcf->separator.len + value->len;

        p = (u_char *) ngx_pcalloc(r->pool, len);
        if (p == NULL) {
            return NGX_ERROR;
        }

        data = p;

        p = ngx_copy(p, h->value.data, h->value.len);
        p = ngx_copy(p, ahcf->separator.data, ahcf->separator.len);
        p = ngx_copy(p, value->data, value->len);

        h->value.data = data;
        h->value.len = len;
    }

    return NGX_OK;
}

