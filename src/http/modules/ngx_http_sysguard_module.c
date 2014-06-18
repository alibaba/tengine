/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_flag_t  enable;
    ngx_int_t   load;
    ngx_str_t   load_action;
    ngx_int_t   swap;
    ngx_str_t   swap_action;
    size_t      free;
    ngx_str_t   free_action;
    time_t      interval;

    ngx_uint_t  log_level;
} ngx_http_sysguard_conf_t;


static void *ngx_http_sysguard_create_conf(ngx_conf_t *cf);
static char *ngx_http_sysguard_merge_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_sysguard_load(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_sysguard_mem(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_sysguard_init(ngx_conf_t *cf);


static ngx_conf_enum_t  ngx_http_sysguard_log_levels[] = {
    { ngx_string("info"), NGX_LOG_INFO },
    { ngx_string("notice"), NGX_LOG_NOTICE },
    { ngx_string("warn"), NGX_LOG_WARN },
    { ngx_string("error"), NGX_LOG_ERR },
    { ngx_null_string, 0 }
};


static ngx_command_t  ngx_http_sysguard_commands[] = {

    { ngx_string("sysguard"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_sysguard_conf_t, enable),
      NULL },

    { ngx_string("sysguard_load"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE12,
      ngx_http_sysguard_load,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("sysguard_mem"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE12,
      ngx_http_sysguard_mem,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("sysguard_interval"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_sec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_sysguard_conf_t, interval),
      NULL },

    { ngx_string("sysguard_log_level"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_enum_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_sysguard_conf_t, log_level),
      &ngx_http_sysguard_log_levels },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_sysguard_module_ctx = {
    NULL,                                   /* preconfiguration */
    ngx_http_sysguard_init,                 /* postconfiguration */

    NULL,                                   /* create main configuration */
    NULL,                                   /* init main configuration */

    NULL,                                   /* create server configuration */
    NULL,                                   /* merge server configuration */

    ngx_http_sysguard_create_conf,          /* create location configuration */
    ngx_http_sysguard_merge_conf            /* merge location configuration */
};


ngx_module_t  ngx_http_sysguard_module = {
    NGX_MODULE_V1,
    &ngx_http_sysguard_module_ctx,          /* module context */
    ngx_http_sysguard_commands,             /* module directives */
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


static time_t    ngx_http_sysguard_cached_load_exptime;
static time_t    ngx_http_sysguard_cached_mem_exptime;
static ngx_int_t ngx_http_sysguard_cached_load;
static ngx_int_t ngx_http_sysguard_cached_swapstat;
static size_t    ngx_http_sysguard_cached_free;


static ngx_int_t
ngx_http_sysguard_update_load(ngx_http_request_t *r, time_t exptime)
{
    ngx_int_t  load, rc;

    ngx_http_sysguard_cached_load_exptime = ngx_time() + exptime;

    rc = ngx_getloadavg(&load, 1, r->connection->log);
    if (rc == NGX_ERROR) {

        ngx_http_sysguard_cached_load = 0;

        return NGX_ERROR;
    }

    ngx_http_sysguard_cached_load = load;

    return NGX_OK;
}


static ngx_int_t
ngx_http_sysguard_update_mem(ngx_http_request_t *r, time_t exptime)
{
    ngx_int_t      rc;
    ngx_meminfo_t  m;

    ngx_http_sysguard_cached_mem_exptime = ngx_time() + exptime;

    rc = ngx_getmeminfo(&m, r->connection->log);
    if (rc == NGX_ERROR) {

        ngx_http_sysguard_cached_swapstat = 0;
        ngx_http_sysguard_cached_free = NGX_CONF_UNSET_SIZE;

        return NGX_ERROR;
    }

    ngx_http_sysguard_cached_swapstat = m.totalswap == 0
        ? 0 : (m.totalswap - m.freeswap) * 100 / m.totalswap;
    ngx_http_sysguard_cached_free = m.freeram + m.cachedram + m.bufferram;

    return NGX_OK;
}


static ngx_int_t
ngx_http_sysguard_do_redirect(ngx_http_request_t *r, ngx_str_t *path)
{
    if (path->len == 0) {
        return NGX_HTTP_SERVICE_UNAVAILABLE;
    } else if (path->data[0] == '@') {
        (void) ngx_http_named_location(r, path);
    } else {
        (void) ngx_http_internal_redirect(r, path, &r->args);
    }

    ngx_http_finalize_request(r, NGX_DONE);

    return NGX_DONE;
}


static ngx_int_t
ngx_http_sysguard_handler(ngx_http_request_t *r)
{
    ngx_http_sysguard_conf_t  *glcf;

    if (r->main->sysguard_set) {
        return NGX_DECLINED;
    }

    glcf = ngx_http_get_module_loc_conf(r, ngx_http_sysguard_module);

    if (!glcf->enable) {
        return NGX_DECLINED;
    }

    r->main->sysguard_set = 1;

    /* load */

    if (glcf->load != NGX_CONF_UNSET) {

        if (ngx_http_sysguard_cached_load_exptime < ngx_time()) {
            ngx_http_sysguard_update_load(r, glcf->interval);
        }

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "http sysguard handler load: %1.3f %1.3f %V %V",
                       ngx_http_sysguard_cached_load * 1.0 / 1000,
                       glcf->load * 1.0 / 1000,
                       &r->uri,
                       &glcf->load_action);

        if (ngx_http_sysguard_cached_load > glcf->load) {

            ngx_log_error(glcf->log_level, r->connection->log, 0,
                          "sysguard load limited, current:%1.3f conf:%1.3f",
                          ngx_http_sysguard_cached_load * 1.0 / 1000,
                          glcf->load * 1.0 / 1000);

            return ngx_http_sysguard_do_redirect(r, &glcf->load_action);
        }
    }

    /* swap */

    if (glcf->swap != NGX_CONF_UNSET) {

        if (ngx_http_sysguard_cached_mem_exptime < ngx_time()) {
            ngx_http_sysguard_update_mem(r, glcf->interval);
        }

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "http sysguard handler swap: %i %i %V %V",
                       ngx_http_sysguard_cached_swapstat,
                       glcf->swap,
                       &r->uri,
                       &glcf->swap_action);

        if (ngx_http_sysguard_cached_swapstat > glcf->swap) {

            ngx_log_error(glcf->log_level, r->connection->log, 0,
                          "sysguard swap limited, current:%i conf:%i",
                          ngx_http_sysguard_cached_swapstat,
                          glcf->swap);

            return ngx_http_sysguard_do_redirect(r, &glcf->swap_action);
        }
    }

    /* mem free */

    if (glcf->free != NGX_CONF_UNSET_SIZE) {

        if (ngx_http_sysguard_cached_mem_exptime < ngx_time()) {
            ngx_http_sysguard_update_mem(r, glcf->interval);
        }

        if (ngx_http_sysguard_cached_free != NGX_CONF_UNSET_SIZE) {

            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "http sysguard handler free: %uz %uz %V %V",
                           ngx_http_sysguard_cached_free,
                           glcf->free,
                           &r->uri,
                           &glcf->free_action);

            if (ngx_http_sysguard_cached_free < glcf->free) {

                ngx_log_error(glcf->log_level, r->connection->log, 0,
                              "sysguard free limited, current:%uzM conf:%uzM",
                              ngx_http_sysguard_cached_free / 1024 / 1024,
                              glcf->free / 1024 / 1024);

                return ngx_http_sysguard_do_redirect(r, &glcf->free_action);
            }
        }

    }

    return NGX_DECLINED;
}


static void *
ngx_http_sysguard_create_conf(ngx_conf_t *cf)
{
    ngx_http_sysguard_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_sysguard_conf_t));
    if (conf == NULL) {
        return NGX_CONF_ERROR;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->load_action = {0, NULL};
     *     conf->swap_action = {0, NULL};
     */

    conf->enable = NGX_CONF_UNSET;
    conf->load = NGX_CONF_UNSET;
    conf->swap = NGX_CONF_UNSET;
    conf->free = NGX_CONF_UNSET_SIZE;
    conf->interval = NGX_CONF_UNSET;
    conf->log_level = NGX_CONF_UNSET_UINT;

    return conf;
}


static char *
ngx_http_sysguard_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_sysguard_conf_t  *prev = parent;
    ngx_http_sysguard_conf_t  *conf = child;

    ngx_conf_merge_value(conf->enable, prev->enable, 0);
    ngx_conf_merge_str_value(conf->load_action, prev->load_action, "");
    ngx_conf_merge_str_value(conf->swap_action, prev->swap_action, "");
    ngx_conf_merge_str_value(conf->free_action, prev->free_action, "");
    ngx_conf_merge_value(conf->load, prev->load, NGX_CONF_UNSET);
    ngx_conf_merge_value(conf->swap, prev->swap, NGX_CONF_UNSET);
    ngx_conf_merge_size_value(conf->free, prev->free, NGX_CONF_UNSET_SIZE);
    ngx_conf_merge_value(conf->interval, prev->interval, 1);
    ngx_conf_merge_uint_value(conf->log_level, prev->log_level, NGX_LOG_ERR);

    return NGX_CONF_OK;
}

static char *
ngx_http_sysguard_load(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_sysguard_conf_t  *glcf = conf;

    ngx_str_t  *value;
    ngx_uint_t  i, scale;

    value = cf->args->elts;
    i = 1;
    scale = 1;

    if (ngx_strncmp(value[i].data, "load=", 5) == 0) {

        if (glcf->load != NGX_CONF_UNSET) {
            return "is duplicate";
        }

        if (value[i].len == 5) {
            goto invalid;
        }

        value[i].data += 5;
        value[i].len -= 5;

        if (ngx_strncmp(value[i].data, "ncpu*", 5) == 0) {
            value[i].data += 5;
            value[i].len -= 5;
            scale = ngx_ncpu;
        }

        glcf->load = ngx_atofp(value[i].data, value[i].len, 3);
        if (glcf->load == NGX_ERROR) {
            goto invalid;
        }

        glcf->load = glcf->load * scale;

        if (cf->args->nelts == 2) {
            return NGX_CONF_OK;
        }

        i++;

        if (ngx_strncmp(value[i].data, "action=", 7) != 0) {
            goto invalid;
        }

        if (value[i].len == 7) {
            goto invalid;
        }

        if (value[i].data[7] != '/' && value[i].data[7] != '@') {
            goto invalid;
        }

        glcf->load_action.data = value[i].data + 7;
        glcf->load_action.len = value[i].len - 7;

        return NGX_CONF_OK;
    }

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static char *
ngx_http_sysguard_mem(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_sysguard_conf_t  *glcf = conf;

    ngx_str_t  *value, ss;
    ngx_uint_t  i;

    value = cf->args->elts;
    i = 1;

    if (ngx_strncmp(value[i].data, "swapratio=", 10) == 0) {

        if (glcf->swap != NGX_CONF_UNSET) {
            return "is duplicate";
        }

        if (value[i].data[value[i].len - 1] != '%') {
            goto invalid;
        }

        glcf->swap = ngx_atofp(value[i].data + 10, value[i].len - 11, 2);
        if (glcf->swap == NGX_ERROR) {
            goto invalid;
        }

        if (cf->args->nelts == 2) {
            return NGX_CONF_OK;
        }

        i++;

        if (ngx_strncmp(value[i].data, "action=", 7) != 0) {
            goto invalid;
        }

        if (value[i].len == 7) {
            goto invalid;
        }

        if (value[i].data[7] != '/' && value[i].data[7] != '@') {
            goto invalid;
        }

        glcf->swap_action.data = value[i].data + 7;
        glcf->swap_action.len = value[i].len - 7;

        return NGX_CONF_OK;

    } else if (ngx_strncmp(value[i].data, "free=", 5) == 0) {

        if (glcf->free != NGX_CONF_UNSET_SIZE) {
            return "is duplicate";
        }

        ss.data = value[i].data + 5;
        ss.len = value[i].len - 5;

        glcf->free = ngx_parse_size(&ss);
        if (glcf->free == (size_t) NGX_ERROR) {
            goto invalid;
        }

        if (cf->args->nelts == 2) {
            return NGX_CONF_OK;
        }

        i++;

        if (ngx_strncmp(value[i].data, "action=", 7) != 0) {
            goto invalid;
        }

        if (value[i].len == 7) {
            goto invalid;
        }

        if (value[i].data[7] != '/' && value[i].data[7] != '@') {
            goto invalid;
        }

        glcf->free_action.data = value[i].data + 7;
        glcf->free_action.len = value[i].len - 7;

        return NGX_CONF_OK;
    }

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static ngx_int_t
ngx_http_sysguard_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_PREACCESS_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_sysguard_handler;

    return NGX_OK;
}
