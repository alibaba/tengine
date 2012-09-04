/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#ifndef _NGX_SHM_CYCLE_H_INCLUDED_
#define _NGX_SHM_CYCLE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>


#define ngx_shm_cycle_cleanup_pt       ngx_pool_cleanup_pt


typedef struct {
    ngx_shm_zone_t   *shm_zone;
    ngx_pool_t       *pool;
    unsigned          init:1;
    unsigned          latest:1;
} ngx_shm_cycle_cln_ctx_t;


void ngx_shm_cycle_init(void);
void ngx_shm_cycle_increase_generation(void);
ngx_shm_zone_t *ngx_shm_cycle_add(ngx_conf_t *cf, ngx_str_t *name,
    size_t size, void *tag, int slab);
ngx_int_t ngx_shm_cycle_init_cycle(ngx_cycle_t *cycle);
ngx_array_t *ngx_shm_cycle_get_live_cycles(ngx_pool_t *pool,
    ngx_str_t *name);
void ngx_shm_cycle_free_old_cycles(void);
ngx_int_t ngx_shm_cycle_add_cleanup(ngx_str_t *zn,
    ngx_shm_cycle_cleanup_pt cln);


#endif /* _NGX_SHM_CYCLE_H_INCLUDED_ */
