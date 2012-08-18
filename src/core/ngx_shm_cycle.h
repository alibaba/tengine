/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#ifndef _NGX_SHM_CYCLE_H_INCLUDED_
#define _NGX_SHM_CYCLE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>


void ngx_increase_shm_cycle_generation(void);
ngx_shm_zone_t * ngx_shared_memory_lc_add(ngx_conf_t *cf, ngx_str_t *name,
    size_t size, void *tag, int slab);
ngx_int_t ngx_shm_cycle_init(ngx_cycle_t *cycle);
void ngx_free_old_shm_cycles(void);


#endif /* _NGX_SHM_CYCLE_H_INCLUDED_ */
