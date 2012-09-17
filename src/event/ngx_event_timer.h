
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#ifndef _NGX_EVENT_TIMER_H_INCLUDED_
#define _NGX_EVENT_TIMER_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>


#define NGX_TIMER_INFINITE  (ngx_msec_t) -1

#define NGX_TIMER_LAZY_DELAY  300


ngx_int_t ngx_event_timer_init_rbtree(ngx_log_t *log);
ngx_msec_t ngx_event_find_timer_rbtree(void);
void ngx_event_expire_timers_rbtree(void);

ngx_int_t ngx_event_timer_init_minheap(ngx_log_t *log);
ngx_msec_t ngx_event_find_timer_minheap(void);
void ngx_event_expire_timers_minheap(void);

ngx_msec_t ngx_event_find_timer_minheap4(void);
void ngx_event_expire_timers_minheap4(void);

#if (NGX_THREADS)
extern ngx_mutex_t  *ngx_event_timer_mutex;
#endif


extern ngx_thread_volatile ngx_rbtree_t  ngx_event_timer_rbtree;
extern ngx_thread_volatile ngx_minheap_t ngx_event_timer_minheap;


static ngx_inline ngx_int_t
ngx_event_timer_empty_rbtree(void)
{
    if (ngx_event_timer_rbtree.root == ngx_event_timer_rbtree.sentinel) {
        return NGX_OK;
    }

    return NGX_ERROR;
}


static ngx_inline ngx_int_t
ngx_event_timer_empty_minheap(void)
{
    if (ngx_event_timer_minheap.nelts == 0) {
        return NGX_OK;
    }

    return NGX_ERROR;
}


static ngx_inline void
ngx_event_del_timer_rbtree(ngx_event_t *ev)
{
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer del: %d: %M",
                    ngx_event_ident(ev->data), ev->timer.rbtree.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    ngx_rbtree_delete(&ngx_event_timer_rbtree, &ev->timer.rbtree);

    ngx_mutex_unlock(ngx_event_timer_mutex);

#if (NGX_DEBUG)
    ev->timer.rbtree.left = NULL;
    ev->timer.rbtree.right = NULL;
    ev->timer.rbtree.parent = NULL;
#endif

    ev->timer_set = 0;
}


static ngx_inline void
ngx_event_add_timer_rbtree(ngx_event_t *ev, ngx_msec_t timer)
{
    ngx_msec_t      key;
    ngx_msec_int_t  diff;

    key = ngx_current_msec + timer;

    if (ev->timer_set) {

        /*
         * Use a previous timer value if difference between it and a new
         * value is less than NGX_TIMER_LAZY_DELAY milliseconds: this allows
         * to minimize the rbtree operations for fast connections.
         */

        diff = (ngx_msec_int_t) (key - ev->timer.rbtree.key);

        if (ngx_abs(diff) < NGX_TIMER_LAZY_DELAY) {
            ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                           "event timer: %d, old: %M, new: %M",
                            ngx_event_ident(ev->data), ev->timer.rbtree.key, key);
            return;
        }

        ngx_del_timer(ev);
    }

    ev->timer.rbtree.key = key;

    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer add: %d: %M:%M",
                    ngx_event_ident(ev->data), timer, ev->timer.rbtree.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    ngx_rbtree_insert(&ngx_event_timer_rbtree, &ev->timer.rbtree);

    ngx_mutex_unlock(ngx_event_timer_mutex);

    ev->timer_set = 1;
}


static ngx_inline void
ngx_event_del_timer_minheap(ngx_event_t *ev)
{
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer del: %d: %M",
                    ngx_event_ident(ev->data), ev->timer.minheap.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    ngx_minheap_delete(&ngx_event_timer_minheap, ev->timer.minheap.index);

    ngx_mutex_unlock(ngx_event_timer_mutex);

    ev->timer_set = 0;
}


static ngx_inline void
ngx_event_add_timer_minheap(ngx_event_t *ev, ngx_msec_t timer)
{
    ngx_msec_t      key;
    ngx_msec_int_t  diff;

    key = ngx_current_msec + timer;

    if (ev->timer_set) {

        diff = (ngx_msec_int_t) (key - ev->timer.minheap.key);

        if (ngx_abs(diff) < NGX_TIMER_LAZY_DELAY) {
            ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                           "event timer: %d, old: %M, new: %M",
                            ngx_event_ident(ev->data), ev->timer.minheap.key, key);
            return;
        }

        ngx_del_timer(ev);
    }

    ev->timer.minheap.key = key;

    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer add: %d: %M:%M",
                    ngx_event_ident(ev->data), timer, ev->timer.minheap.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    ngx_minheap_insert(&ngx_event_timer_minheap, &ev->timer.minheap);

    ngx_mutex_unlock(ngx_event_timer_mutex);

    ev->timer_set = 1;
}

static ngx_inline void
ngx_event_del_timer_minheap4(ngx_event_t *ev)
{
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer del: %d: %M",
                    ngx_event_ident(ev->data), ev->timer.minheap.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    ngx_minheap4_delete(&ngx_event_timer_minheap, ev->timer.minheap.index);

    ngx_mutex_unlock(ngx_event_timer_mutex);

    ev->timer_set = 0;
}


static ngx_inline void
ngx_event_add_timer_minheap4(ngx_event_t *ev, ngx_msec_t timer)
{
    ngx_msec_t      key;
    ngx_msec_int_t  diff;

    key = ngx_current_msec + timer;

    if (ev->timer_set) {

        diff = (ngx_msec_int_t) (key - ev->timer.minheap.key);

        if (ngx_abs(diff) < NGX_TIMER_LAZY_DELAY) {
            ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                           "event timer: %d, old: %M, new: %M",
                            ngx_event_ident(ev->data), ev->timer.minheap.key, key);
            return;
        }

        ngx_del_timer(ev);
    }

    ev->timer.minheap.key = key;

    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer add: %d: %M:%M",
                    ngx_event_ident(ev->data), timer, ev->timer.minheap.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    ngx_minheap4_insert(&ngx_event_timer_minheap, &ev->timer.minheap);

    ngx_mutex_unlock(ngx_event_timer_mutex);

    ev->timer_set = 1;
}
#endif /* _NGX_EVENT_TIMER_H_INCLUDED_ */
