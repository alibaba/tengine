
#ifndef NGX_TIMER_TREE_PREFIX
#error "this file should only be used in ngx_timer_heap.c/ngx_timer_rbtree.c/ngx_timer_heap4.c"
#endif
#include <ngx_config.h>

#define NGX_TIMER_CAT(A, B)           NGX_TIMER_CAT_I(A, B)
#define NGX_TIMER_CAT_I(A, B)         A ## B

#define NGX_TIMER_TREE_INIT     NGX_TIMER_CAT(NGX_TIMER_TREE_PREFIX, _init)
#define NGX_TIMER_TREE_DEL      NGX_TIMER_CAT(NGX_TIMER_TREE_PREFIX, _del)
#define NGX_TIMER_TREE_ADD      NGX_TIMER_CAT(NGX_TIMER_TREE_PREFIX, _add)
#define NGX_TIMER_TREE_FIND_MIN NGX_TIMER_CAT(NGX_TIMER_TREE_PREFIX, _find_min)
#define NGX_TIMER_TREE_EMPTY    NGX_TIMER_CAT(NGX_TIMER_TREE_PREFIX, _empty)
#define NGX_TIMER_TREE_EXPIRE_TIMERS \
                            NGX_TIMER_CAT(NGX_TIMER_TREE_PREFIX, _expire_timers)

static ngx_int_t
NGX_TIMER_TREE_INIT(ngx_cycle_t *cycle)
{
    ngx_int_t        rc;

    rc = NGX_TREE_INIT(cycle);

    if (rc != NGX_OK) {
        return rc;
    }

    /* ngx_event_timer_mutex init in ngx_timer_module.init_conf */
    return NGX_OK;
}

static void
NGX_TIMER_TREE_DEL(ngx_event_t *ev)
{
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer del: %d: %M",
                   ngx_event_ident(ev->data), ev->timer.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    NGX_TREE_DELETE(&ev->timer);

    ngx_mutex_unlock(ngx_event_timer_mutex);

#if (NGX_DEBUG)
    ngx_memzero(((u_char *)&ev->timer) + sizeof(ev->timer.key),
                sizeof(ev->timer) - sizeof(ev->timer.key));
#endif

    ev->timer_set = 0;
}


static void
NGX_TIMER_TREE_ADD(ngx_event_t *ev, ngx_msec_t timer)
{
    ngx_msec_t      key;

#ifndef NGX_TREE_ADJUST
    ngx_msec_int_t  diff;
#endif

    key = ngx_current_msec + timer;

    if (ev->timer_set) {

#ifdef NGX_TREE_ADJUST
        ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                       "event timer mod: %d: %M:%M",
                       ngx_event_ident(ev->data), timer, ev->timer.key);

        ngx_mutex_lock(ngx_event_timer_mutex);

        NGX_TREE_ADJUST(&ev->timer);

        ngx_mutex_unlock(ngx_event_timer_mutex);

        return;
#else
        /*
         * Use a previous timer value if difference between it and a new
         * value is less than NGX_TIMER_LAZY_DELAY milliseconds: this allows
         * to minimize the rbtree operations for fast connections.
         */

        diff = (ngx_msec_int_t) (key - ev->timer.key);

        if (ngx_abs(diff) < NGX_TIMER_LAZY_DELAY) {
            ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                           "event timer: %d, old: %M, new: %M",
                           ngx_event_ident(ev->data), ev->timer.key, key);
            return;
        }

        ngx_del_timer(ev);
#endif
    }

    ev->timer.key = key;

    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer add: %d: %M:%M",
                   ngx_event_ident(ev->data), timer, ev->timer.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    NGX_TREE_INSERT(&ev->timer);

    ngx_mutex_unlock(ngx_event_timer_mutex);

    ev->timer_set = 1;
}


static ngx_msec_t
NGX_TIMER_TREE_FIND_MIN(void)
{
    ngx_msec_int_t      timer;
    ngx_rbtree_node_t  *node;

    if (NGX_TREE_EMPTY()) {
        return NGX_TIMER_INFINITE;
    }

    ngx_mutex_lock(ngx_event_timer_mutex);

    node = NGX_TREE_MIN();

    ngx_mutex_unlock(ngx_event_timer_mutex);

    timer = (ngx_msec_int_t) (node->key - ngx_current_msec);

    return (ngx_msec_t) (timer > 0 ? timer : 0);
}


static void
NGX_TIMER_TREE_EXPIRE_TIMERS(void)
{
    ngx_event_t        *ev;
    ngx_rbtree_node_t  *node;

    for ( ;; ) {

        ngx_mutex_lock(ngx_event_timer_mutex);

        if (NGX_TREE_EMPTY()) {
            return;
        }

        node = NGX_TREE_MIN();

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

            NGX_TREE_DELETE(&ev->timer);

            ngx_mutex_unlock(ngx_event_timer_mutex);

#if (NGX_DEBUG)
            ngx_memzero(((u_char *)&ev->timer) + sizeof(ev->timer.key),
                        sizeof(ev->timer) - sizeof(ev->timer.key));
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

static ngx_int_t
NGX_TIMER_TREE_EMPTY()
{
    return NGX_TREE_EMPTY();
}

