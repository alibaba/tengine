
 /*
 * Copyright (C) 2010-2019 Alibaba Group Holding Limited
 */


#include "ngx_proc_strategy_module.h"

static ngx_int_t ngx_proc_strategy_prepare(ngx_cycle_t *cycle);
static void ngx_proc_strategy_exit_worker(ngx_cycle_t *cycle);
static ngx_int_t ngx_proc_strategy_init_worker(ngx_cycle_t *cycle);
static void * ngx_proc_strategy_create_main_conf(ngx_conf_t *cf);

static ngx_command_t ngx_proc_strategy_commands[] = {
    ngx_null_command
};


static ngx_proc_module_t ngx_proc_strategy_module_ctx = {
    ngx_string("strategy"),
    ngx_proc_strategy_create_main_conf,
    NULL,
    NULL,
    NULL,
    ngx_proc_strategy_prepare,
    ngx_proc_strategy_init_worker,
    NULL,
    ngx_proc_strategy_exit_worker
};


ngx_module_t ngx_proc_strategy_module = {
    NGX_MODULE_V1,
    &ngx_proc_strategy_module_ctx,
    ngx_proc_strategy_commands,
    NGX_PROC_MODULE,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NGX_MODULE_V1_PADDING
};


extern ngx_module_t ngx_http_strategy_module;


static ngx_int_t
ngx_proc_strategy_prepare(ngx_cycle_t *cycle)
{
    return NGX_OK;
}

static void
ngx_strategy_timer_handler(ngx_event_t *ev)
{
    ngx_strategy_frame_app_t    *frame_app = ev->data;
    ngx_int_t                   rc;

    if (ngx_exiting || ngx_quit) {
        return;
    }

    if (frame_app->ctx.interval == NGX_CONF_UNSET_MSEC) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "[strategy] callback interval not set:%V", &frame_app->ctx.name);
        return;
    }

    if (frame_app->app_callback == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "[strategy] app_callback not set:%V", &frame_app->ctx.name);
        return;
    }

    rc = frame_app->app_callback(&frame_app->ctx);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "[strategy] app_callback error:%V", &frame_app->ctx.name);
    } else if (frame_app->ctx.interval > 0) {
        ngx_memzero(&frame_app->ctx.tm_event, sizeof(ngx_event_t));
        frame_app->ctx.tm_event.handler = ngx_strategy_timer_handler;
        frame_app->ctx.tm_event.log = ngx_cycle->log;
        frame_app->ctx.tm_event.data = frame_app;
        ngx_add_timer(&frame_app->ctx.tm_event, frame_app->ctx.interval);
    }
}

static ngx_int_t
ngx_proc_strategy_init_worker(ngx_cycle_t *cycle)
{
    ngx_uint_t                     i;
    
    ngx_proc_strategy_main_conf_t  *dmcf;
    ngx_strategy_sync_app_t     *app;
    ngx_strategy_frame_app_t    *frame_app;

    dmcf = ngx_proc_get_main_conf(cycle->conf_ctx, ngx_proc_strategy_module);

    ngx_log_error(NGX_LOG_WARN, cycle->log, 0, "[strategy] init app : normal_app num=%d", dmcf->apps.nelts);

    /* normal app */
    app = dmcf->apps.elts;
    for (i = 0; i < dmcf->apps.nelts; i++) {
        app[i].init(app[i].data);
    }

    /* frame app */
    ngx_log_error(NGX_LOG_WARN, cycle->log, 0, "[strategy] init app : frame_app num=%d", dmcf->frame_apps.nelts);

    frame_app = dmcf->frame_apps.elts;
    for (i = 0; i < dmcf->frame_apps.nelts; i++) {
        if (frame_app[i].app_callback == NULL) {
            continue;
        }
        
        frame_app[i].ctx.tm_event.data = &frame_app[i];

        ngx_strategy_timer_handler(&frame_app[i].ctx.tm_event);
    }

    return NGX_OK;
}


static void
ngx_proc_strategy_exit_worker(ngx_cycle_t *cycle)
{
    ngx_proc_strategy_main_conf_t  *dmcf;
    ngx_strategy_frame_app_t *app;
    ngx_uint_t                   i;
    ngx_int_t                    rc;

    dmcf = ngx_proc_get_main_conf(cycle->conf_ctx, ngx_proc_strategy_module);

    app = dmcf->frame_apps.elts;
    for (i = 0; i < dmcf->frame_apps.nelts; i++) {
        if (app[i].app_uninit == NULL) {
            continue;
        }

        rc = app[i].app_uninit(&app[i].ctx, cycle);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                    "[strategy] app=%V uninit failed", &app[i].ctx.name);
        }
    }
}

ngx_int_t
ngx_strategy_register(ngx_conf_t *cf, ngx_strategy_init_func init, void *data)
{
    ngx_strategy_sync_app_t * app;
    ngx_proc_strategy_main_conf_t * umcf;
   
    umcf = ngx_proc_get_main_conf(cf->cycle->conf_ctx, ngx_proc_strategy_module);
    if (umcf == NULL) {
        return NGX_ERROR;
    }

    app = ngx_array_push(&umcf->apps);
    if (app == NULL) {
        return NGX_ERROR;
    }

    app->init = init;
    app->data = data;

    return NGX_OK;
}


static void *
ngx_proc_strategy_create_main_conf(ngx_conf_t *cf)
{
    ngx_proc_strategy_main_conf_t  *conf;
    ngx_int_t rc = NGX_OK;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_proc_strategy_main_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    rc = ngx_array_init(&conf->apps, cf->pool, 37, sizeof(ngx_strategy_sync_app_t));
    if (rc != NGX_OK) {
        return NULL;
    }

    rc = ngx_array_init(&conf->frame_apps, cf->pool, 37, sizeof(ngx_strategy_frame_app_t));
    if (rc != NGX_OK) {
        return NULL;
    }

    conf->already_init = 0;

    return conf;
}


ngx_int_t ngx_check_strategy_process(ngx_conf_t *cf)
{
    ngx_proc_main_conf_t           *cmcf;
    ngx_proc_conf_t                **cpcfp;
    ngx_uint_t                       i;

    cmcf = ngx_proc_get_main_conf(cf->cycle->conf_ctx, ngx_proc_core_module);
    if (cmcf == NULL) {
        return NGX_ERROR;
    }

    cpcfp = cmcf->processes.elts;
    for (i = 0; i < cmcf->processes.nelts; i++) {
        if (ngx_strcmp(cpcfp[i]->name.data, "strategy") == 0) {
            break;
        }
    }

    if (i == cmcf->processes.nelts) {
        return NGX_ERROR;
    }

    return NGX_OK;
}

ngx_int_t
ngx_strategy_frame_register(ngx_conf_t *cf, ngx_strategy_frame_app_t * inapp)
{
    ngx_strategy_frame_app_t        *app;
    ngx_proc_strategy_main_conf_t   *umcf;
    ngx_int_t                       rc;
   
    umcf = ngx_proc_get_main_conf(cf->cycle->conf_ctx, ngx_proc_strategy_module);
    if (umcf == NULL) {
        return NGX_ERROR;
    }

    rc = ngx_check_strategy_process(cf);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                "[strategy] no \"process strategy {}\" in proc configuration");
        return NGX_ERROR;
    }

    /* The registration behavior must be created before the shared memory */
    if (umcf->already_init) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                "[strategy] already init when call register, pls adjust module build order");
        return NGX_ERROR;
    }

    app = ngx_array_push(&umcf->frame_apps);
    if (app == NULL) {
        return NGX_ERROR;
    }

    app->ctx.name.data = ngx_palloc(cf->pool, inapp->ctx.name.len);
    if (app->ctx.name.data == NULL) {
        ngx_log_error(NGX_LOG_WARN, cf->log, 0,
                "[strategy] alloc name memory failed: %V", &inapp->ctx.name);

        return NGX_ERROR;
    }

    memcpy(app->ctx.name.data, inapp->ctx.name.data, inapp->ctx.name.len);

    app->ctx.name.len = inapp->ctx.name.len;

    app->ctx.shm_size = inapp->ctx.shm_size;
    app->ctx.interval = inapp->ctx.interval;
    app->ctx.data     = inapp->ctx.data;

    app->app_init = inapp->app_init;
    app->app_uninit = inapp->app_uninit;
    app->app_callback = inapp->app_callback;

    return NGX_OK;
}


static ngx_int_t
ngx_strategy_slot_init_elem(ngx_strategy_slot_app_t * slot_app,
        ngx_strategy_slot_ctx_t *ctx,
        ngx_cycle_t *cycle,
        ngx_slab_pool_t * slab)
{
    u_char * addr;

    ngx_int_t   max_pool_size = slot_app->pool_size + sizeof(ngx_shm_pool_t);

    ctx->data = ngx_slab_alloc(slab, slot_app->slot_size);
    if (ctx->data == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "[strategy] slab alloc ctx failed");
        return NGX_ERROR;
    }

    addr = ngx_slab_alloc(slab, max_pool_size);
    if (addr == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "[strategy] slab alloc failed: max_pool_size=%d", max_pool_size);
        return NGX_ERROR;
    }

    ctx->pool = ngx_shm_create_pool(addr, max_pool_size);
    if (ctx->pool == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "[strategy] pool create failed: max_pool_size=%d", max_pool_size);
        return NGX_ERROR;
    }

    if (slot_app->update == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "[strategy] slot update not set");
        return NGX_ERROR;
    }

    ctx->valid = 0;

    return NGX_OK;
}

static ngx_int_t
ngx_strategy_slot_init(ngx_strategy_frame_ctx_t * ctx,
        ngx_cycle_t *cycle, ngx_slab_pool_t * slab)
{
    ngx_strategy_slot_app_t *slot_app;
    ngx_int_t               rc, i;

    slot_app = ctx->data;
    if (slot_app == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                "[strategy] slot_init: slot_app is null");
        return NGX_ERROR;
    }

    slot_app->shm_ctx = ngx_slab_alloc(slab, sizeof(ngx_strategy_slot_shm_ctx_t));
    if (slot_app->shm_ctx == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                "[strategy] slot_init: shm_ctx alloc failed: appname=%V", &ctx->name);
        return NGX_ERROR;
    }

    slot_app->shm_ctx->current = 0;

    for (i = 0; i < 2; i++) {
        ngx_strategy_slot_ctx_t *current;

        current = &slot_app->shm_ctx->slots[i];

        rc = ngx_strategy_slot_init_elem(slot_app, current, cycle, slab);
        if (rc == NGX_ERROR) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                    "[strategy] init slot %d failed: %V", i, &ctx->name);
            return rc;
        }

        rc = slot_app->update(cycle, slot_app->data, current->pool, current->data, 0);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_WARN, cycle->log, 0,
                    "[strategy] update slot %d failed: %V", i, &ctx->name);
        } else {
            current->valid = 1;
        }
    }
    
    return NGX_OK;
}

static ngx_int_t
ngx_strategy_slot_callback(ngx_strategy_frame_ctx_t * ctx)
{
    ngx_strategy_slot_app_t     *slot_app;
    ngx_int_t                   rc;
    ngx_strategy_slot_ctx_t     *reserved;
    ngx_int_t                   need_update = 0;

    slot_app = ctx->data;
    if (slot_app == NULL || slot_app->shm_ctx == NULL) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, 0,
                "[strategy] slot_callback failed: slot_app or shm_ctx is null: slot_app=%p", slot_app);
        return NGX_ERROR;
    }
    
    /* 1. Check for updates and rebuild if there are updates */
    reserved = &slot_app->shm_ctx->slots[(slot_app->shm_ctx->current + 1) % 2];

    if (slot_app->check_update == NULL) {
        need_update = 1;
    }
    else {
        check_update_status status = slot_app->check_update(slot_app->data, reserved->data);
        if (status == STATUS_CHECK_UPDATE_FAILED) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, 0,
                    "[strategy][monitor] update config failed: appname=%V", &ctx->name);
        }
        else if (status == STATUS_CHECK_NEED_UPDATE) {
            need_update = 1;
        }
    }

    if (need_update) {
        rc = slot_app->update((ngx_cycle_t *)ngx_cycle,
            slot_app->data, reserved->pool,
            reserved->data, slot_app->print_detail);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, 0,
                 "[strategy] update failed: appname=%V", &ctx->name);
            return NGX_OK;
        }

        if (ngx_shm_pool_used_rate(reserved->pool) >= slot_app->shm_warn_mem_rate) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, 0,
                "[strategy][monitor] space: appname=%V, shm_size=%d, free=%d, used_rate=%d",
                &ctx->name,
                ngx_shm_pool_size(reserved->pool),
                ngx_shm_pool_free_size(reserved->pool),
                ngx_shm_pool_used_rate(reserved->pool)
                );
        }
       
        reserved->valid = 1;
    }

    /* 2. If there is an update switch the memory block */
    if (need_update) {
        slot_app->shm_ctx->current = (slot_app->shm_ctx->current + 1) % 2;
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, 0,
                 "[strategy] update area rule: appname=%V, current=%d",
                 &ctx->name, slot_app->shm_ctx->current);
    }

    return NGX_OK;
}

ngx_strategy_slot_app_t*
ngx_strategy_slot_app_register(ngx_conf_t *cf, ngx_strategy_slot_app_t * app)
{
    ngx_strategy_frame_app_t frame_app;
    ngx_strategy_slot_app_t * slot_app;
    ngx_int_t               rc;
    
    slot_app = ngx_pcalloc(cf->pool, sizeof(ngx_strategy_slot_app_t));
    if (slot_app == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                "[strategy] slot_app alloc mem failed");
        return NULL;
    }

    slot_app->slot_size = app->slot_size;
    slot_app->pool_size = app->pool_size;
    slot_app->print_detail = app->print_detail;
    slot_app->shm_warn_mem_rate = app->shm_warn_mem_rate;

    slot_app->update = app->update;
    slot_app->check_update = app->check_update;
    slot_app->data = app->data;

    memset(&frame_app, 0, sizeof(frame_app));
    frame_app.ctx = app->frame_ctx;
    frame_app.ctx.data = slot_app;
    frame_app.app_init = ngx_strategy_slot_init;
    frame_app.app_callback = ngx_strategy_slot_callback;
    
    if (frame_app.ctx.shm_size == 0) {
        frame_app.ctx.shm_size = ngx_shm_cal_slab_pool_size(slot_app->pool_size);
        if (frame_app.ctx.shm_size ==  NGX_ERROR) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0, 
                    "[strategy] shm_size cal error, slot_app->pool_size: %d", 
                    slot_app->pool_size);
            return NULL;
        }
        ngx_log_error(NGX_LOG_DEBUG, cf->log, 0,
                "[strategy] shm_size:%d, pool_size:%d", frame_app.ctx.shm_size,
                slot_app->pool_size);
    }

    rc = ngx_strategy_frame_register(cf, &frame_app);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                "[strategy] frame_register failed: %V", &frame_app.ctx.name);
        return NULL;
    }
    
    return slot_app;
}

void * ngx_strategy_get_current_slot(ngx_strategy_slot_app_t *app)
{
    ngx_strategy_slot_ctx_t     *current;

    if (app == NULL || app->shm_ctx == NULL) {
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                "[strategy] get slot: app or shm_ctx is null: app=%p", app);
        return NULL;
    }
    
    current = &app->shm_ctx->slots[(app->shm_ctx->current) % 2];

    if (current->valid == 0) {
        return NULL;
    }

    return current->data;
}

/* Shared memory needs to allocate 2 pools of the same size */
#define NGX_STRATEGY_SHM_POOL_NUM           2
/* The value of M divided by N is rounded up，must M >= 1 and N > 0 */
#define NGX_CEIL_INT(M,N)                   (((M) - 1) / (N) + 1)

ngx_int_t
ngx_shm_cal_slab_pool_size(ngx_int_t app_pool_size)
{
    if ((app_pool_size < 0)  
        || (app_pool_size > (NGX_MAX_INT_T_VALUE / NGX_STRATEGY_SHM_POOL_NUM)))
    {
        /* Make sure app_pool_size is within the valid range */
        return NGX_ERROR;
    }
    /* The assignment of ngx_pagesize and ngx_pagesize_shift is in ngx_os_init,
        which is called earlier than ngx_init_cycle */

    /* Get ngx_pagesize size from global variable */
    ngx_uint_t pagesize = ngx_pagesize;
    /* Get ngx_pagesize_shift */
    ngx_uint_t pagesize_shift = ngx_pagesize_shift;

    ngx_uint_t extra_size = 0;

    extra_size += sizeof(ngx_slab_pool_t);
   
    /* slab classification array size */
    ngx_uint_t grade_array_size = pagesize_shift * sizeof(ngx_slab_page_t);
    
    extra_size += ngx_max(pagesize, grade_array_size + grade_array_size); 

    ngx_uint_t page_num = NGX_CEIL_INT(app_pool_size + sizeof(ngx_shm_pool_t), pagesize)
                          * NGX_STRATEGY_SHM_POOL_NUM; 
    
    ngx_uint_t page_array_size = page_num * sizeof(ngx_slab_page_t) + pagesize; 
    extra_size += page_array_size;

    
    extra_size = (pagesize_shift + NGX_CEIL_INT(extra_size, pagesize)) * pagesize;

    
    ngx_int_t total_size = page_num * pagesize + extra_size;

    if (total_size < 0) { 
        return NGX_ERROR;
    }

    return total_size;
}
