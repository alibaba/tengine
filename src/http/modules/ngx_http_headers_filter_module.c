
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct ngx_http_header_val_s  ngx_http_header_val_t;

typedef ngx_int_t (*ngx_http_set_header_pt)(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);


typedef struct {
    ngx_str_t                  name;
    ngx_uint_t                 offset;
    ngx_http_set_header_pt     handler;
} ngx_http_set_header_t;


struct ngx_http_header_val_s {
    ngx_http_complex_value_t   value;
    ngx_str_t                  key;
    ngx_http_set_header_pt     handler;
    ngx_uint_t                 offset;
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
    ngx_http_expires_t              expires;
    time_t                          expires_time;
} ngx_http_headers_expires_time_t;


typedef struct {
    ngx_flag_t                      enable_types;

    ngx_hash_t                      types;
    ngx_array_t                    *types_keys;
    ngx_http_headers_expires_time_t default_expires;

    ngx_array_t                    *headers;
} ngx_http_headers_conf_t;


static ngx_int_t ngx_http_set_expires(ngx_http_request_t *r,
    ngx_http_headers_expires_time_t *exp_time);
static ngx_int_t ngx_http_set_expires_type(ngx_http_request_t *r,
    ngx_http_headers_conf_t *conf);
static ngx_int_t ngx_http_add_cache_control(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_add_header(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_last_modified(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_response_header(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);

static void *ngx_http_headers_create_conf(ngx_conf_t *cf);
static char *ngx_http_headers_merge_conf(ngx_conf_t *cf,
    void *parent, void *child);
static ngx_int_t ngx_http_headers_filter_init(ngx_conf_t *cf);
static char *ngx_http_headers_expires(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_headers_expires_by_types(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_http_headers_add(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


static ngx_http_set_header_t  ngx_http_set_headers[] = {

    { ngx_string("Cache-Control"), 0, ngx_http_add_cache_control },

    { ngx_string("Last-Modified"),
                 offsetof(ngx_http_headers_out_t, last_modified),
                 ngx_http_set_last_modified },

    { ngx_string("ETag"),
                 offsetof(ngx_http_headers_out_t, etag),
                 ngx_http_set_response_header },

    { ngx_null_string, 0, NULL }
};


static ngx_str_t ngx_http_headers_default_types[] = {
    ngx_null_string
};


static ngx_command_t  ngx_http_headers_filter_commands[] = {

    { ngx_string("expires"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE12,
      ngx_http_headers_expires,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL},

    { ngx_string("expires_by_types"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_2MORE,
      ngx_http_headers_expires_by_types,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL},

    { ngx_string("add_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE2,
      ngx_http_headers_add,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL},

      ngx_null_command
};


static ngx_http_module_t  ngx_http_headers_filter_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_http_headers_filter_init,          /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_headers_create_conf,          /* create location configuration */
    ngx_http_headers_merge_conf            /* merge location configuration */
};


ngx_module_t  ngx_http_headers_filter_module = {
    NGX_MODULE_V1,
    &ngx_http_headers_filter_module_ctx,   /* module context */
    ngx_http_headers_filter_commands,      /* module directives */
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


static ngx_http_output_header_filter_pt  ngx_http_next_header_filter;


static ngx_int_t
ngx_http_headers_filter(ngx_http_request_t *r)
{
    ngx_str_t                 value;
    ngx_uint_t                i;
    ngx_http_header_val_t    *h;
    ngx_http_headers_conf_t  *conf;

    conf = ngx_http_get_module_loc_conf(r, ngx_http_headers_filter_module);

    if (r != r->main
        || (r->headers_out.status != NGX_HTTP_OK
            && r->headers_out.status != NGX_HTTP_CREATED
            && r->headers_out.status != NGX_HTTP_NO_CONTENT
            && r->headers_out.status != NGX_HTTP_PARTIAL_CONTENT
            && r->headers_out.status != NGX_HTTP_MOVED_PERMANENTLY
            && r->headers_out.status != NGX_HTTP_MOVED_TEMPORARILY
            && r->headers_out.status != NGX_HTTP_SEE_OTHER
            && r->headers_out.status != NGX_HTTP_NOT_MODIFIED
            && r->headers_out.status != NGX_HTTP_TEMPORARY_REDIRECT))
    {
        return ngx_http_next_header_filter(r);
    }

    if (ngx_http_set_expires_type(r, conf) != NGX_OK) {
        return NGX_ERROR;
    }

    if (conf->headers) {
        h = conf->headers->elts;
        for (i = 0; i < conf->headers->nelts; i++) {

            if (ngx_http_complex_value(r, &h[i].value, &value) != NGX_OK) {
                return NGX_ERROR;
            }

            if (h[i].handler(r, &h[i], &value) != NGX_OK) {
                return NGX_ERROR;
            }
        }
    }

    return ngx_http_next_header_filter(r);
}


static ngx_int_t
ngx_http_set_expires(ngx_http_request_t *r,
    ngx_http_headers_expires_time_t *exp_time)
{
    size_t            len;
    time_t            now, expires_time, max_age;
    ngx_uint_t        i;
    ngx_table_elt_t  *expires, *cc, **ccp;

    expires = r->headers_out.expires;

    if (expires == NULL) {

        expires = ngx_list_push(&r->headers_out.headers);
        if (expires == NULL) {
            return NGX_ERROR;
        }

        r->headers_out.expires = expires;

        expires->hash = 1;
        ngx_str_set(&expires->key, "Expires");
    }

    len = sizeof("Mon, 28 Sep 1970 06:00:00 GMT");
    expires->value.len = len - 1;

    ccp = r->headers_out.cache_control.elts;

    if (ccp == NULL) {

        if (ngx_array_init(&r->headers_out.cache_control, r->pool,
                           1, sizeof(ngx_table_elt_t *))
            != NGX_OK)
        {
            return NGX_ERROR;
        }

        ccp = ngx_array_push(&r->headers_out.cache_control);
        if (ccp == NULL) {
            return NGX_ERROR;
        }

        cc = ngx_list_push(&r->headers_out.headers);
        if (cc == NULL) {
            return NGX_ERROR;
        }

        cc->hash = 1;
        ngx_str_set(&cc->key, "Cache-Control");
        *ccp = cc;

    } else {
        for (i = 1; i < r->headers_out.cache_control.nelts; i++) {
            ccp[i]->hash = 0;
        }

        cc = ccp[0];
    }

    if (exp_time->expires == NGX_HTTP_EXPIRES_EPOCH) {
        expires->value.data = (u_char *) "Thu, 01 Jan 1970 00:00:01 GMT";
        ngx_str_set(&cc->value, "no-cache");
        return NGX_OK;
    }

    if (exp_time->expires == NGX_HTTP_EXPIRES_MAX) {
        expires->value.data = (u_char *) "Thu, 31 Dec 2037 23:55:55 GMT";
        /* 10 years */
        ngx_str_set(&cc->value, "max-age=315360000");
        return NGX_OK;
    }

    expires->value.data = ngx_pnalloc(r->pool, len);
    if (expires->value.data == NULL) {
        return NGX_ERROR;
    }

    if (exp_time->expires_time == 0
        && exp_time->expires != NGX_HTTP_EXPIRES_DAILY)
    {
        ngx_memcpy(expires->value.data, ngx_cached_http_time.data,
                   ngx_cached_http_time.len + 1);
        ngx_str_set(&cc->value, "max-age=0");
        return NGX_OK;
    }

    now = ngx_time();

    if (exp_time->expires == NGX_HTTP_EXPIRES_DAILY) {
        expires_time = ngx_next_time(exp_time->expires_time);
        max_age = expires_time - now;

    } else if (exp_time->expires == NGX_HTTP_EXPIRES_ACCESS
               || r->headers_out.last_modified_time == -1)
    {
        expires_time = now + exp_time->expires_time;
        max_age = exp_time->expires_time;

    } else {
        expires_time = r->headers_out.last_modified_time
            + exp_time->expires_time;
        max_age = expires_time - now;
    }

    ngx_http_time(expires->value.data, expires_time);

    if (exp_time->expires_time < 0 || max_age < 0) {
        ngx_str_set(&cc->value, "no-cache");
        return NGX_OK;
    }

    cc->value.data = ngx_pnalloc(r->pool,
                                 sizeof("max-age=") + NGX_TIME_T_LEN + 1);
    if (cc->value.data == NULL) {
        return NGX_ERROR;
    }

    cc->value.len = ngx_sprintf(cc->value.data, "max-age=%T", max_age)
                    - cc->value.data;

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_expires_type(ngx_http_request_t *r, ngx_http_headers_conf_t *conf)
{
    ngx_http_headers_expires_time_t *et;

    if (conf->enable_types) {
        et = ngx_http_test_content_type(r, &conf->types);
        if (et == NULL) {
            et = ngx_http_test_content_type_wildcard(r, &conf->types);
        }
        if (et != NULL) {
            if (et->expires == NGX_HTTP_EXPIRES_OFF) {
                return NGX_OK;
            }
            return ngx_http_set_expires(r, et);
        }
    }

    if (conf->default_expires.expires != NGX_HTTP_EXPIRES_OFF
        && conf->default_expires.expires != NGX_HTTP_EXPIRES_UNSET) {
        return ngx_http_set_expires(r, &conf->default_expires);
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_add_header(ngx_http_request_t *r, ngx_http_header_val_t *hv,
    ngx_str_t *value)
{
    ngx_table_elt_t  *h;

    if (value->len) {
        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        h->hash = 1;
        h->key = hv->key;
        h->value = *value;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_add_cache_control(ngx_http_request_t *r, ngx_http_header_val_t *hv,
    ngx_str_t *value)
{
    ngx_table_elt_t  *cc, **ccp;

    if (value->len == 0) {
        return NGX_OK;
    }

    ccp = r->headers_out.cache_control.elts;

    if (ccp == NULL) {

        if (ngx_array_init(&r->headers_out.cache_control, r->pool,
                           1, sizeof(ngx_table_elt_t *))
            != NGX_OK)
        {
            return NGX_ERROR;
        }
    }

    ccp = ngx_array_push(&r->headers_out.cache_control);
    if (ccp == NULL) {
        return NGX_ERROR;
    }

    cc = ngx_list_push(&r->headers_out.headers);
    if (cc == NULL) {
        return NGX_ERROR;
    }

    cc->hash = 1;
    ngx_str_set(&cc->key, "Cache-Control");
    cc->value = *value;

    *ccp = cc;

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_last_modified(ngx_http_request_t *r, ngx_http_header_val_t *hv,
    ngx_str_t *value)
{
    if (ngx_http_set_response_header(r, hv, value) != NGX_OK) {
        return NGX_ERROR;
    }

    r->headers_out.last_modified_time =
        (value->len) ? ngx_http_parse_time(value->data, value->len) : -1;

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_response_header(ngx_http_request_t *r, ngx_http_header_val_t *hv,
    ngx_str_t *value)
{
    ngx_table_elt_t  *h, **old;

    old = (ngx_table_elt_t **) ((char *) &r->headers_out + hv->offset);

    if (value->len == 0) {
        if (*old) {
            (*old)->hash = 0;
            *old = NULL;
        }

        return NGX_OK;
    }

    if (*old) {
        h = *old;

    } else {
        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        *old = h;
    }

    h->hash = 1;
    h->key = hv->key;
    h->value = *value;

    return NGX_OK;
}


static void *
ngx_http_headers_create_conf(ngx_conf_t *cf)
{
    ngx_http_headers_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_headers_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->headers = NULL;
     *     conf->expire_types = NULL;
     *     conf->expires_time = 0;
     *     conf->enable_types = 0;
     */

    conf->default_expires.expires = NGX_HTTP_EXPIRES_UNSET;

    return conf;
}


static char *
ngx_http_headers_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_headers_conf_t *prev = parent;
    ngx_http_headers_conf_t *conf = child;

    if (ngx_http_merge_types(cf, &conf->types_keys, &conf->types,
                             &prev->types_keys, &prev->types,
                             ngx_http_headers_default_types)
                             != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    /* conf->enable_types default 0 */

    if (conf->default_expires.expires != NGX_HTTP_EXPIRES_OFF) {

        if (conf->default_expires.expires != NGX_HTTP_EXPIRES_UNSET
            || prev->default_expires.expires == NGX_HTTP_EXPIRES_UNSET){
            /* current &prev expires is not set off */
            if (conf->types_keys != NULL
                || conf->types.size > 1
                || conf->types.buckets[0] != NULL)
            {
                /* current or prev set expires_by_types */
                conf->enable_types = 1;
            }
        }

        if (conf->default_expires.expires == NGX_HTTP_EXPIRES_UNSET) {

            conf->default_expires.expires = prev->default_expires.expires;
            conf->default_expires.expires_time =
                prev->default_expires.expires_time;

            if (conf->default_expires.expires == NGX_HTTP_EXPIRES_OFF) {
                /* prev expires set to off */
                /* or prev expires off by inherited but enable types */
                if (conf->types_keys != NULL || prev->enable_types) {
                    /*
                     * current set expires_by_types
                     * ignored prev expires set to off
                     */
                    conf->enable_types = 1;
                }
            } else {
                /* prev expires not set to off */
                if (conf->types_keys != NULL
                    || conf->types.size > 1
                    || conf->types.buckets[0] != NULL)
                {
                    /* current or prev set expires_by_types */
                    conf->enable_types = 1;
                }
            }
        }
    }

    if (conf->headers == NULL) {
        conf->headers = prev->headers;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_headers_filter_init(ngx_conf_t *cf)
{
    ngx_http_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_headers_filter;

    return NGX_OK;
}


static char *
ngx_http_headers_parse_expires(ngx_conf_t *cf, ngx_http_expires_t *expires,
    time_t *expires_time)
{
    ngx_str_t           *value;
    ngx_uint_t           minus, n;

    value = cf->args->elts;

    if (*expires != NGX_HTTP_EXPIRES_MODIFIED) {

        if (ngx_strcmp(value[1].data, "epoch") == 0) {
            *expires = NGX_HTTP_EXPIRES_EPOCH;
            return NGX_CONF_OK;
        }

        if (ngx_strcmp(value[1].data, "max") == 0) {
            *expires = NGX_HTTP_EXPIRES_MAX;
            return NGX_CONF_OK;
        }

        if (ngx_strcmp(value[1].data, "off") == 0) {
            *expires = NGX_HTTP_EXPIRES_OFF;
            return NGX_CONF_OK;
        }

        *expires = NGX_HTTP_EXPIRES_ACCESS;

        n = 1;

    } else {

        n = 2;
    }

    if (value[n].data[0] == '@') {
        value[n].data++;
        value[n].len--;
        minus = 0;

        if (*expires == NGX_HTTP_EXPIRES_MODIFIED) {
            return "daily time cannot be used with \"modified\" parameter";
        }

        *expires = NGX_HTTP_EXPIRES_DAILY;

    } else if (value[n].data[0] == '+') {
        value[n].data++;
        value[n].len--;
        minus = 0;

    } else if (value[n].data[0] == '-') {
        value[n].data++;
        value[n].len--;
        minus = 1;

    } else {
        minus = 0;
    }

    *expires_time = ngx_parse_time(&value[n], 1);

    if (*expires_time == (time_t) NGX_ERROR) {
        return "invalid value";
    }

    if (*expires == NGX_HTTP_EXPIRES_DAILY
        && *expires_time > 24 * 60 * 60)
    {
        return "daily time value must be less than 24 hours";
    }

    if (minus) {
        *expires_time = - *expires_time;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_headers_expires(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_headers_conf_t *hcf = conf;

    char        *rs;
    ngx_str_t   *value;

    if (hcf->default_expires.expires != NGX_HTTP_EXPIRES_UNSET) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (ngx_strcmp(value[1].data, "modified") == 0) {

        hcf->default_expires.expires = NGX_HTTP_EXPIRES_MODIFIED;
        if (cf->args->nelts == 2) {
            return NGX_CONF_ERROR;
        }

    } else {
        hcf->default_expires.expires = NGX_HTTP_EXPIRES_ACCESS;
    }

    rs = ngx_http_headers_parse_expires(cf, &hcf->default_expires.expires,
                                        &hcf->default_expires.expires_time);
    if (rs != NGX_CONF_OK) {
        return rs;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_headers_expires_by_types(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_http_headers_conf_t          *hcf = conf;
    ngx_http_headers_expires_time_t  *et;

    char                *rs;
    ngx_str_t           *value;
    ngx_uint_t           i, hash;
    ngx_uint_t           n;
    ngx_hash_key_t      *type;

    value = cf->args->elts;

    if (hcf->types_keys == NULL) {
        hcf->types_keys = ngx_array_create(cf->pool, 1, sizeof(ngx_hash_key_t));
        if (hcf->types_keys == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    et = ngx_pcalloc(cf->pool, sizeof(ngx_http_headers_expires_time_t));
    if (et == NULL) {
        return NGX_CONF_ERROR;
    }

    if (ngx_strcmp(value[1].data, "modified") == 0) {

        et->expires = NGX_HTTP_EXPIRES_MODIFIED;
        if (cf->args->nelts == 3) {
            return NGX_CONF_ERROR;
        }

        n = 3;

    } else {
        et->expires = NGX_HTTP_EXPIRES_ACCESS;

        if (cf->args->nelts == 2) {
            return NGX_CONF_ERROR;
        }

        n = 2;
    }

    rs = ngx_http_headers_parse_expires(cf, &et->expires, &et->expires_time);
    if (rs != NGX_CONF_OK) {
        return rs;
    }

    for (; n < cf->args->nelts; n++) {

        hash = ngx_hash_strlow(value[n].data, value[n].data, value[n].len);
        value[n].data[value[n].len] = '\0';

        type = hcf->types_keys->elts;
        for (i = 0; i < hcf->types_keys->nelts; i++) {

            if (ngx_strcmp(value[n].data, type[i].key.data) == 0) {
                ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                    "duplicate MIME type \"%V\"", &value[n]);
                continue;
            }
        }

        type = ngx_array_push(hcf->types_keys);
        if (type == NULL) {
            return NGX_CONF_ERROR;
        }

        type->key = value[n];
        type->key_hash = hash;
        type->value = (void *) et;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_headers_add(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_headers_conf_t *hcf = conf;

    ngx_str_t                         *value;
    ngx_uint_t                         i;
    ngx_http_header_val_t             *hv;
    ngx_http_set_header_t             *set;
    ngx_http_compile_complex_value_t   ccv;

    value = cf->args->elts;

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
    hv->handler = ngx_http_add_header;
    hv->offset = 0;

    set = ngx_http_set_headers;
    for (i = 0; set[i].name.len; i++) {
        if (ngx_strcasecmp(value[1].data, set[i].name.data) != 0) {
            continue;
        }

        hv->offset = set[i].offset;
        hv->handler = set[i].handler;

        break;
    }

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
