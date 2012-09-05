
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>


#if (NGX_THREADS)
ngx_mutex_t  *ngx_event_timer_mutex;
#endif


#ifdef NGX_USE_MINHEAP
ngx_thread_volatile ngx_minheap_t ngx_event_timer_minheap;
#else
ngx_thread_volatile ngx_rbtree_t  ngx_event_timer_rbtree;
static ngx_rbtree_node_t          ngx_event_timer_sentinel;
#endif

/*
 * the event timer rbtree may contain the duplicate keys, however,
 * it should not be a problem, because we use the rbtree to find
 * a minimum timer value only
 */

ngx_int_t
ngx_event_timer_init(ngx_log_t *log)
{
#ifdef NGX_USE_MINHEAP
    ngx_pool_t      *pool;

    pool = ngx_create_pool(4096, log);
    if (pool == NULL) {
        return NGX_ERROR;
    }
    ngx_event_timer_minheap.elts = ngx_palloc(pool,
                                              1000 * sizeof(ngx_minheap_node_t *));
    if (ngx_event_timer_minheap.elts == NULL) {
        return NGX_ERROR;
    }
    ngx_event_timer_minheap.n = 100;
    ngx_event_timer_minheap.pool = pool;
    ngx_event_timer_minheap.nelts = 0;
#else
    ngx_rbtree_init(&ngx_event_timer_rbtree, &ngx_event_timer_sentinel,
                    ngx_rbtree_insert_timer_value);
#endif

#if (NGX_THREADS)

    if (ngx_event_timer_mutex) {
        ngx_event_timer_mutex->log = log;
        return NGX_OK;
    }

    ngx_event_timer_mutex = ngx_mutex_init(log, 0);
    if (ngx_event_timer_mutex == NULL) {
        return NGX_ERROR;
    }

#endif

    return NGX_OK;
}


ngx_msec_t
ngx_event_find_timer(void)
{
    ngx_msec_int_t      timer;

#ifdef NGX_USE_MINHEAP
    ngx_minheap_node_t *node;

    if (ngx_event_timer_minheap.nelts == 0) {
        return NGX_TIMER_INFINITE;
    }
#else
    ngx_rbtree_node_t  *node, *root, *sentinel;

    if (ngx_event_timer_rbtree.root == &ngx_event_timer_sentinel) {
        return NGX_TIMER_INFINITE;
    }
#endif

    ngx_mutex_lock(ngx_event_timer_mutex);

#ifdef NGX_USE_MINHEAP
    node = ngx_minheap_min(&ngx_event_timer_minheap);
#else
    root = ngx_event_timer_rbtree.root;
    sentinel = ngx_event_timer_rbtree.sentinel;

    node = ngx_rbtree_min(root, sentinel);
#endif

    ngx_mutex_unlock(ngx_event_timer_mutex);

    timer = (ngx_msec_int_t) (node->key - ngx_current_msec);

    return (ngx_msec_t) (timer > 0 ? timer : 0);
}


void
ngx_event_expire_timers(void)
{
    ngx_event_t        *ev;
#ifdef NGX_USE_MINHEAP
    ngx_minheap_node_t *node;
#else
    ngx_rbtree_node_t  *node, *root, *sentinel;

    sentinel = ngx_event_timer_rbtree.sentinel;
#endif

    for ( ;; ) {

        ngx_mutex_lock(ngx_event_timer_mutex);

#ifdef NGX_USE_MINHEAP
        if (ngx_event_timer_minheap.nelts == 0) {
            return;
        }
        node = ngx_minheap_min(&ngx_event_timer_minheap);
#else
        root = ngx_event_timer_rbtree.root;

        if (root == sentinel) {
            return;
        }

        node = ngx_rbtree_min(root, sentinel);
#endif

        /* node->key <= ngx_current_time */

        if ((ngx_msec_int_t) (node->key - ngx_current_msec) <= 0) {
            ev = (ngx_event_t *) ((char *) node - offsetof(ngx_event_t, timer));

#if (NGX_THREADS)

            if (ngx_threaded && ngx_trylock(ev->lock) == 0) {

                /*
                 * We cannot change the timer of the event that is being
                 * handled by another thread.  And we cannot easy walk
                 * the rbtree to find next expired timer so we exit the loop.
                 * However, it should be a rare case when the event that is
                 * being handled has an expired timer.
                 */

                ngx_log_debug1(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                               "event %p is busy in expire timers", ev);
                break;
            }
#endif

            ngx_log_debug2(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                           "event timer del: %d: %M",
                           ngx_event_ident(ev->data), ev->timer.key);

#ifdef NGX_USE_MINHEAP
            ngx_minheap_delete(&ngx_event_timer_minheap, ev->timer.index);
#else
            ngx_rbtree_delete(&ngx_event_timer_rbtree, &ev->timer);
#endif

            ngx_mutex_unlock(ngx_event_timer_mutex);

#ifndef NGX_USE_MINHEAP
#if (NGX_DEBUG)
            ev->timer.left = NULL;
            ev->timer.right = NULL;
            ev->timer.parent = NULL;
#endif
#endif

            ev->timer_set = 0;

#if (NGX_THREADS)
            if (ngx_threaded) {
                ev->posted_timedout = 1;

                ngx_post_event(ev, &ngx_posted_events);

                ngx_unlock(ev->lock);

                continue;
            }
#endif

            ev->timedout = 1;

            ev->handler(ev);

            continue;
        }

        break;
    }

    ngx_mutex_unlock(ngx_event_timer_mutex);
}
