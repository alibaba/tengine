
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_TIMERS_H_INCLUDED_
#define _NGX_HTTP_TFS_TIMERS_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_http_tfs.h>


struct  ngx_http_tfs_timers_lock_s {
    ngx_atomic_t                   *ngx_http_tfs_kp_mutex_ptr;
    ngx_shmtx_t                     ngx_http_tfs_kp_mutex;
};


struct  ngx_http_tfs_timers_data_s {
    ngx_http_tfs_main_conf_t       *main_conf;
    ngx_http_tfs_upstream_t        *upstream;
    ngx_http_tfs_timers_lock_t     *lock;
};

ngx_int_t  ngx_http_tfs_add_rcs_timers(ngx_cycle_t *cycle,
    ngx_http_tfs_timers_data_t *data);
ngx_http_tfs_timers_lock_t *ngx_http_tfs_timers_init(ngx_cycle_t *cycle,
    u_char *lock_file);


#endif  /* _NGX_HTTP_TFS_TIMERS_H_INCLUDED_ */
