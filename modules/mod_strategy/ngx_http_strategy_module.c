
 /*
 * Copyright (C) 2010-2019 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>

#include <ngx_proc_strategy_module.h>

static char * ngx_http_strategy_init_main_conf(ngx_conf_t *cf, void *conf);
static char * ngx_http_strategy_zone(ngx_conf_t *cf, void *conf);
static ngx_int_t ngx_http_strategy_module_init(ngx_cycle_t *cycle);

extern ngx_module_t ngx_proc_strategy_module;

static ngx_command_t  ngx_http_strategy_commands[] = {
      ngx_null_command
};

static ngx_http_module_t  ngx_http_strategy_module_ctx = {
    NULL,                                   /* preconfiguration */
    NULL,                                   /* postconfiguration */

    NULL,                                   /* create main configuration */
    ngx_http_strategy_init_main_conf,       /* init main configuration */

    NULL,                                   /* create server configuration */
    NULL,                                   /* merge server configuration */

    NULL,                                   /* create location configration */
    NULL                                    /* merge location configration */
};

ngx_module_t  ngx_http_strategy_module = {
    NGX_MODULE_V1,
    &ngx_http_strategy_module_ctx,          /* module context */
    ngx_http_strategy_commands,             /* module directives */
    NGX_HTTP_MODULE,                        /* module type */
    NULL,                                   /* init master */
    ngx_http_strategy_module_init,          /* init module */
    NULL,                                   /* init process */
    NULL,                                   /* init thread */
    NULL,                                   /* exit thread */
    NULL,                                   /* exit process */
    NULL,                                   /* exit master */
    NGX_MODULE_V1_PADDING
};

static char *
ngx_http_strategy_init_main_conf(ngx_conf_t *cf, void *conf)
{
    return ngx_http_strategy_zone(cf, conf);
}

static ngx_int_t
ngx_http_strategy_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_slab_pool_t                 *shpool;
    ngx_strategy_frame_app_t        *app;

    shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;

    app = shm_zone->data;
    if (app == NULL) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, 0,
                "[strategy] init zone app is null");
        return NGX_ERROR;
    }

    app->ctx.slab = shpool;

    return NGX_OK;
}

static char *
ngx_http_strategy_zone(ngx_conf_t *cf, void *conf)
{
    ngx_str_t               shm_name;
    ngx_shm_zone_t          *shm_zone;

    ngx_proc_strategy_main_conf_t   *smcf;
    ngx_strategy_frame_app_t        *app;
    ngx_uint_t                       i;

    static ngx_int_t ngx_http_strategy_shm_generation = 0;

    smcf = ngx_proc_get_main_conf(cf->cycle->conf_ctx, ngx_proc_strategy_module);
    if (smcf == NULL) {
        return NGX_CONF_OK;
    }

    smcf->already_init = 1;
    
    app = smcf->frame_apps.elts;
    for (i = 0; i < smcf->frame_apps.nelts; i++) {
        /* Shared memory size is 0, skip create */
        if (app[i].ctx.shm_size == 0) {
            continue;
        }

        shm_name.data = ngx_pnalloc(cf->pool, sizeof("strategy_zone_#") + NGX_INT_T_LEN + app[i].ctx.name.len);
        
        if (shm_name.data == NULL) {
            return NGX_CONF_ERROR;
        }

        shm_name.len = ngx_sprintf(shm_name.data, "strategy_zone_%V#%ui",
                                &app[i].ctx.name,
                                ngx_http_strategy_shm_generation)
                    - shm_name.data;

        shm_zone = ngx_shared_memory_add(cf, &shm_name, app[i].ctx.shm_size,
                                        &ngx_http_strategy_module);
        if (shm_zone == NULL) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                            "[strategy] ngx_shared_memory_add failed: %V", &shm_name);
            return NGX_CONF_ERROR;
        }

        if (shm_zone->data) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                            "[strategy] duplicate zone \"%V\"", &shm_name);
            return NGX_CONF_ERROR;
        }

        shm_zone->init = ngx_http_strategy_init_zone;
        shm_zone->data = &app[i];
    }

    ngx_http_strategy_shm_generation ++;

    return NGX_CONF_OK;
}

static ngx_int_t ngx_http_strategy_module_init(ngx_cycle_t *cycle)
{
    ngx_proc_strategy_main_conf_t   *smcf;
    ngx_strategy_frame_app_t        *app;
    ngx_uint_t                       i;
    ngx_int_t                        rc;

    smcf = ngx_proc_get_main_conf(cycle->conf_ctx, ngx_proc_strategy_module);
    if (smcf == NULL) {
        return NGX_OK;
    }

    app = smcf->frame_apps.elts;
    for (i = 0; i < smcf->frame_apps.nelts; i++) {
        if (app[i].app_init == NULL) {
            continue;
        }

        rc = app[i].app_init(&app[i].ctx, cycle, app[i].ctx.slab);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                    "[strategy] init app:%V failed", &app[i].ctx.name);
            
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}
