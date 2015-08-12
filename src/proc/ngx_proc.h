
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */

#ifndef _NGX_PROC_H_INCLUDED_
#define _NGX_PROC_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>


#define NGX_PROC_MODULE            0x434f5250  /* "PROC" */
#define NGX_PROC_MAIN_CONF         0x02000000
#define NGX_PROC_CONF              0x04000000


#define NGX_PROC_MAIN_CONF_OFFSET  offsetof(ngx_proc_conf_ctx_t, main_conf)
#define NGX_PROC_CONF_OFFSET       offsetof(ngx_proc_conf_ctx_t, proc_conf)


typedef struct {
    void                         **main_conf;
    void                         **proc_conf;
} ngx_proc_conf_ctx_t;


typedef struct {
    ngx_str_t                      name;

    ngx_int_t                      priority;
    ngx_msec_t                     delay_start;
    ngx_uint_t                     count;
    ngx_flag_t                     respawn;

    ngx_proc_conf_ctx_t           *ctx;
} ngx_proc_conf_t;


typedef struct {
    ngx_array_t                    processes; /* ngx_proc_conf_t */
} ngx_proc_main_conf_t;


typedef struct ngx_proc_args_s {
    ngx_module_t                  *module;
    ngx_proc_conf_t               *proc_conf;
} ngx_proc_args_t;


typedef struct {
    ngx_str_t                      name;
    void                        *(*create_main_conf)(ngx_conf_t *cf);
    char                        *(*init_main_conf)(ngx_conf_t *cf, void *conf);
    void                        *(*create_proc_conf)(ngx_conf_t *cf);
    char                        *(*merge_proc_conf)(ngx_conf_t *cf,
                                                    void *parent, void *child);

    ngx_int_t                    (*prepare)(ngx_cycle_t *cycle);
    ngx_int_t                    (*init)(ngx_cycle_t *cycle);
    ngx_int_t                    (*loop)(ngx_cycle_t *cycle);
    void                         (*exit)(ngx_cycle_t *cycle);
} ngx_proc_module_t;


#define ngx_proc_get_main_conf(conf_ctx, module)           \
    ((ngx_get_conf(conf_ctx, ngx_procs_module)) ?          \
        ((ngx_proc_conf_ctx_t *) (ngx_get_conf(conf_ctx,   \
              ngx_procs_module)))->main_conf[module.ctx_index] : NULL)


#define ngx_proc_get_conf(conf_ctx, module)                \
    ((ngx_get_conf(conf_ctx, ngx_procs_module)) ?          \
        ((ngx_proc_conf_ctx_t *) (ngx_get_conf(conf_ctx,   \
              ngx_procs_module)))->proc_conf[module.ctx_index] : NULL)


ngx_int_t ngx_procs_start(ngx_cycle_t *cycle, ngx_int_t type);


extern ngx_module_t  ngx_procs_module;
extern ngx_module_t  ngx_proc_core_module;


#endif /* _NGX_PROC_H_INCLUDED_ */
