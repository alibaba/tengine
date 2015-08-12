
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_timers.h>
#include <nginx.h>


static void ngx_http_tfs_timeout_handler(ngx_event_t *event);


ngx_http_tfs_timers_lock_t *
ngx_http_tfs_timers_init(ngx_cycle_t *cycle,
    u_char *lock_file)
{
    u_char                     *shared;
    size_t                      size;
    ngx_shm_t                   shm;
    ngx_http_tfs_timers_lock_t *lock;

    /* cl should be equal or bigger than cache line size */

    size = 128; /* ngx_http_tfs_kp_mutex */

    shm.size = size;
    shm.name.len = sizeof("nginx_tfs_keepalive_zone");
    shm.name.data = (u_char *) "nginx_tfs_keepalive_zone";
    shm.log = cycle->log;

    if (ngx_shm_alloc(&shm) != NGX_OK) {
        return NULL;
    }

    shared = shm.addr;

    lock = ngx_palloc(cycle->pool, sizeof(ngx_http_tfs_timers_lock_t));
    if (lock == NULL) {
        return NULL;
    }

    lock->ngx_http_tfs_kp_mutex_ptr = (ngx_atomic_t *) shared;
    lock->ngx_http_tfs_kp_mutex.spin = (ngx_uint_t) -1;

#if defined(nginx_version) && (nginx_version > 1001008)

    if (ngx_shmtx_create(&lock->ngx_http_tfs_kp_mutex,
                         (ngx_shmtx_sh_t *) shared, lock_file)
        != NGX_OK)
    {
        return NULL;
    }

#else

    if (ngx_shmtx_create(&lock->ngx_http_tfs_kp_mutex, shared, lock_file)
        != NGX_OK)
    {
        return NULL;
    }
#endif

    return lock;
}


ngx_int_t
ngx_http_tfs_add_rcs_timers(ngx_cycle_t *cycle,
    ngx_http_tfs_timers_data_t *data)
{
    ngx_event_t         *ev;
    ngx_connection_t    *dummy;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cycle->log, 0,
                   "http check tfs rc servers");

    ev = ngx_pcalloc(cycle->pool, sizeof(ngx_event_t));
    if (ev == NULL) {
        return NGX_ERROR;
    }

    dummy = ngx_pcalloc(cycle->pool, sizeof(ngx_connection_t));
    if (dummy == NULL) {
        return NGX_ERROR;
    }

    dummy->data = data;
    ev->handler = ngx_http_tfs_timeout_handler;
    ev->log = cycle->log;
    ev->data = dummy;
    ev->timer_set = 0;

    ngx_add_timer(ev, data->upstream->rcs_interval);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_timers_finalize_request_handler(ngx_http_tfs_t *t)
{
    ngx_event_t                 *event;
    ngx_connection_t            *dummy;
    ngx_http_tfs_timers_data_t  *data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, t->log, 0, "http tfs timers finalize");

    event = t->finalize_data;
    dummy = event->data;
    data = dummy->data;

    ngx_destroy_pool(t->pool);
    ngx_shmtx_unlock(&data->lock->ngx_http_tfs_kp_mutex);
    ngx_add_timer(event, data->upstream->rcs_interval);
    return NGX_OK;
}


static void
ngx_http_tfs_timeout_handler(ngx_event_t *event)
{
    ngx_int_t                   rc;
    ngx_pool_t                  *pool;
    ngx_http_tfs_t              *t;
    ngx_connection_t            *dummy;
    ngx_http_request_t          *r;
    ngx_http_tfs_timers_data_t  *data;

    dummy = event->data;
    data = dummy->data;
    if (ngx_shmtx_trylock(&data->lock->ngx_http_tfs_kp_mutex)) {

        if (ngx_queue_empty(&data->upstream->rc_ctx->sh->kp_queue)) {
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, event->log, 0,
                           "empty rc keepalive queue");
            ngx_shmtx_unlock(&data->lock->ngx_http_tfs_kp_mutex);
            ngx_add_timer(event, data->upstream->rcs_interval);
            return;
        }

        pool = ngx_create_pool(8192, event->log);
        if (pool == NULL) {
            ngx_shmtx_unlock(&data->lock->ngx_http_tfs_kp_mutex);
            return;
        }

        /* fake ngx_http_request_t */
        r = ngx_pcalloc(pool, sizeof(ngx_http_request_t));
        if (r == NULL) {
            ngx_shmtx_unlock(&data->lock->ngx_http_tfs_kp_mutex);
            return;
        }

        r->pool = pool;
        r->connection = ngx_pcalloc(pool, sizeof(ngx_connection_t));
        if (r->connection == NULL) {
            ngx_destroy_pool(pool);
            ngx_shmtx_unlock(&data->lock->ngx_http_tfs_kp_mutex);
            return;
        }
        r->connection->log = event->log;
        /* in order to return from ngx_http_run_posted_requests()  */
        r->connection->destroyed = 1;

        t = ngx_pcalloc(pool, sizeof(ngx_http_tfs_t));
        if (t == NULL) {
            ngx_destroy_pool(pool);
            ngx_shmtx_unlock(&data->lock->ngx_http_tfs_kp_mutex);
            return;
        }

        t->pool = pool;
        t->data = r;
        t->log = event->log;
        t->finalize_request = ngx_http_tfs_timers_finalize_request_handler;
        t->finalize_data = event;

        t->r_ctx.action.code = NGX_HTTP_TFS_ACTION_KEEPALIVE;
        t->r_ctx.version = 1;
        t->loc_conf = ngx_pcalloc(pool, sizeof(ngx_http_tfs_loc_conf_t));
        if (t->loc_conf == NULL) {
            ngx_destroy_pool(pool);
            ngx_shmtx_unlock(&data->lock->ngx_http_tfs_kp_mutex);
            return;
        }
        t->loc_conf->upstream = data->upstream;
        t->main_conf = data->main_conf;

        rc = ngx_http_tfs_init(t);
        if (rc == NGX_ERROR) {
            ngx_destroy_pool(pool);
            ngx_shmtx_unlock(&data->lock->ngx_http_tfs_kp_mutex);
            return;
        }

    } else {
        ngx_log_debug0(NGX_LOG_DEBUG_EVENT, event->log, 0,
                       "tfs kp mutex lock failed");
    }
}
