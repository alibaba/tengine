
 /*
 * Copyright (C) 2010-2019 Alibaba Group Holding Limited
 */


#ifndef NGX_PROC_STRATEGY_MODULE_H
#define NGX_PROC_STRATEGY_MODULE_H

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>

#include "ngx_comm_shm.h"

/*
* The first way of use.
* call back only when the independent process starts,
* and it is up to the business module to decide whether the timer operation is required
*/
typedef ngx_int_t (*ngx_strategy_init_func)(void * data);


ngx_int_t ngx_strategy_register(ngx_conf_t *cf, ngx_strategy_init_func init, void *data);
ngx_int_t ngx_check_strategy_process(ngx_conf_t *cf);

/*
* The second way to use.
* it is to create shared memory and timer callbacks
*/
typedef struct {
    ngx_strategy_init_func init;
    void * data;
} ngx_strategy_sync_app_t;


typedef struct {
    /* incoming parameters */

    /* App name */
    ngx_str_t    name;
    /* Required shared memory size */
    ngx_int_t    shm_size;
    /* Callback interval
     *     NGX_CONF_UNSET_MSEC means no call
     *     0 means only call once
     *     > 0 callback interval */
    ngx_msec_t   interval;
    /* Callback data, the framework does not analyze, transparent transmission */
    void         *data;

    /* The following internal parameters cannot be modified externally */
    ngx_event_t         tm_event;
    ngx_slab_pool_t     *slab;
} ngx_strategy_frame_ctx_t;


typedef ngx_int_t (*ngx_strategy_frame_init)(ngx_strategy_frame_ctx_t * ctx,
        ngx_cycle_t *cycle, ngx_slab_pool_t * slab);
typedef ngx_int_t (*ngx_strategy_frame_uninit)(ngx_strategy_frame_ctx_t * ctx,
        ngx_cycle_t *cycle);
typedef ngx_int_t (*ngx_strategy_frame_callback)(ngx_strategy_frame_ctx_t * ctx);

typedef struct {
    ngx_strategy_frame_ctx_t                  ctx;
    
    /* Called during initialization,
     * the shared memory has been created and needs to be initialized */
    ngx_strategy_frame_init                   app_init;
    /* Called on exit */
    ngx_strategy_frame_uninit                 app_uninit;
    /* Callback at interval */
    ngx_strategy_frame_callback               app_callback;
} ngx_strategy_frame_app_t;

/**
 * @brief Register APP, registration can be in the init_main_conf stage
 * 
 * @param cf  ngx_conf_t
 * @param app Configuration information, memory will be reallocated inside the module, and temporary variables can be passed in
 * @return ngx_int_t
 *          NGX_OK registration success
 *          NGX_ERROR registration failed
 */
ngx_int_t ngx_strategy_frame_register(ngx_conf_t *cf, ngx_strategy_frame_app_t * app);



typedef struct {
    ngx_array_t apps;           /* ngx_strategy_sync_app_t */

    ngx_array_t frame_apps;     /* ngx_strategy_frame_app_t */

    ngx_int_t   already_init;
} ngx_proc_strategy_main_conf_t;

/*
* The third way of use
* Create two shared memory switches,
* and the module only needs to implement two callbacks, check_update and update
*/
typedef ngx_int_t (*ngx_strategy_slot_update)(ngx_cycle_t *cycle,
    void * context,
    ngx_shm_pool_t * pool,
    void * data,
    ngx_int_t print_detail);


typedef enum {
    STATUS_CHECK_UPDATE_FAILED,
    STATUS_CHECK_NEED_UPDATE,
    STATUS_CHECK_NO_UPDATE,
} check_update_status;

typedef check_update_status (*ngx_strategy_slot_check_update)(void * context, void * data);

typedef struct {
    ngx_shm_pool_t  *pool;
    void            *data;
    ngx_int_t       valid;
} ngx_strategy_slot_ctx_t;

typedef struct {
    ngx_int_t                   current;
    ngx_strategy_slot_ctx_t     slots[2];
} ngx_strategy_slot_shm_ctx_t;

typedef struct {
    /* incoming parameters */
    ngx_strategy_frame_ctx_t frame_ctx;

    /* Incoming parameters, structure size */
    ngx_int_t               slot_size;
    ngx_int_t               pool_size;
    ngx_int_t               print_detail;
    ngx_int_t               shm_warn_mem_rate;

    /* Incoming parameters, additional environment information */
    void                    *data;

    /* Incoming parameters, callback method */
    ngx_strategy_slot_update            update;
    ngx_strategy_slot_check_update      check_update;
    
    /* Internal structure, cannot modify */
    ngx_strategy_slot_shm_ctx_t  *shm_ctx;
} ngx_strategy_slot_app_t;

ngx_strategy_slot_app_t* ngx_strategy_slot_app_register(ngx_conf_t *cf, ngx_strategy_slot_app_t * app);

void * ngx_strategy_get_current_slot(ngx_strategy_slot_app_t *app);

/* According to app_pool_size, calculate the size of the nginx slab_pool that needs to be created */
ngx_int_t ngx_shm_cal_slab_pool_size(ngx_int_t app_pool_size);

#endif // NGX_PROC_STRATEGY_MODULE_H

