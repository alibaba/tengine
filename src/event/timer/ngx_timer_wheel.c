


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>

typedef ngx_msec_t   ngx_timer_wheel_key_t;

typedef struct ngx_timer_wheel_node_s ngx_timer_wheel_node_t;
struct ngx_timer_wheel_node_s {
    ngx_timer_wheel_key_t     key;
    ngx_timer_wheel_node_t   *next;
    ngx_timer_wheel_node_t  **prev;

    u_char                    data;
};


static ngx_int_t ngx_timer_wheel_init(ngx_cycle_t *cycle);
static void ngx_timer_wheel_expire_timers(void);
static void ngx_timer_wheel_add(ngx_event_t *ev, ngx_msec_t timer);
static void ngx_timer_wheel_del(ngx_event_t *ev);
static ngx_int_t ngx_timer_wheel_empty(void);


ngx_timer_actions_t  ngx_timer_wheel_actions = {
    ngx_string("wheel"),
    ngx_timer_wheel_add,
    ngx_timer_wheel_del,
    ngx_timer_wheel_empty,

    NULL,                           /* find min timer */
    ngx_timer_wheel_expire_timers,

    ngx_timer_wheel_init,
};


static ngx_thread_volatile ngx_timer_wheel_node_t **ngx_timer_wheel;
static ngx_thread_volatile ngx_uint_t               ngx_timer_wheel_size;

static ngx_msec_t               ngx_timer_wheel_resolution;
static ngx_uint_t               ngx_timer_wheel_current;
static ngx_uint_t               ngx_timer_wheel_max_slot;


#define ngx_timer_wheel_slot(key) \
    (((key + ngx_timer_wheel_resolution - 1) / ngx_timer_wheel_resolution) % ngx_timer_wheel_max_slot)

#define ngx_timer_wheel_unlink(node) \
                                                                              \
    *(node->prev) = node->next;                                               \
                                                                              \
    if (node->next) {                                                         \
        node->next->prev = node->prev;                                        \
    }                                                                         \
                                                                              \
    node->prev = NULL;                                                        \
 

#define ngx_timer_wheel_link(queue, node)                                 \
                                                                          \
    if (node->prev != NULL) {                                             \
        ngx_timer_wheel_unlink(node);                                     \
    }                                                                     \
    node->next = (ngx_timer_wheel_node_t *) *queue;                       \
    node->prev = (ngx_timer_wheel_node_t **) queue;                       \
    *queue = node;                                                        \
                                                                          \
    if (node->next) {                                                     \
        node->next->prev = &node->next;                                   \
    }

static ngx_int_t
ngx_timer_wheel_init(ngx_cycle_t *cycle)
{
    ngx_core_conf_t        *ccf;
    ngx_timer_conf_t       *tcf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);
    tcf = (ngx_timer_conf_t*) ngx_get_conf(cycle->conf_ctx, ngx_timer_module);

    if (ccf->timer_resolution == 0) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "when use \"wheel\" timer type, timer resolution must be specified");

        return NGX_ERROR;
    }


    ngx_timer_wheel_resolution =  ccf->timer_resolution;
    ngx_timer_wheel_max_slot = ngx_max(tcf->wheel_max / ngx_timer_wheel_resolution, 1024);
    ngx_timer_wheel_current = ngx_timer_wheel_slot(ngx_current_msec);
    ngx_timer_wheel_size = 0;
#if (NGX_THREADS)
    ngx_timer_wheel_pending = NULL;
#endif
    ngx_timer_wheel = ngx_pcalloc(cycle->pool,
                                  ngx_timer_wheel_max_slot * sizeof(ngx_timer_wheel_node_t *));

    if (ngx_timer_wheel == NULL) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static void
ngx_timer_wheel_expire_timers(void)
{
    ngx_event_t            *ev;
    ngx_timer_wheel_node_t *node, *head;
    ngx_uint_t              slot;

    slot = ngx_timer_wheel_slot(ngx_current_msec + ngx_timer_wheel_resolution);

    ngx_mutex_lock(ngx_event_timer_mutex);

    while (ngx_timer_wheel_current != slot) {

        head = ngx_timer_wheel[ngx_timer_wheel_current];
        while (head) {

            node = head;
            head = node->next;

            ev = (ngx_event_t *) ((char *) node - offsetof(ngx_event_t, timer));

            if (ngx_timer_before(ngx_current_msec + ngx_timer_wheel_resolution, node->key) ) {
                continue;
            }

#if (NGX_THREADS)
            if (ngx_threaded && ngx_trylock(ev->lock) == 0) {

                ngx_timer_wheel_unlink(node);

                ngx_log_debug1(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                               "event %p is busy in expire timers", ev);

                ngx_timer_wheel_link(&ngx_timer_wheel[(ngx_timer_wheel_current + 1) % ngx_timer_wheel_max_slot], node);
                continue;
            }
#endif

            ngx_log_debug2(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                           "event timer del: %d: %M",
                           ngx_event_ident(ev->data), ev->timer.key);

            ngx_timer_wheel_unlink(node);
            ngx_timer_wheel_size --;

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
        }

        ngx_timer_wheel_current ++;
        ngx_timer_wheel_current %= ngx_timer_wheel_max_slot;
    }

    ngx_mutex_unlock(ngx_event_timer_mutex);
}


static void
ngx_timer_wheel_add(ngx_event_t *ev, ngx_msec_t timer)
{
    ngx_msec_t      key;
    ngx_timer_wheel_node_t **queue, *node;

    if (ev->timer_set) {
        ngx_timer_wheel_del(ev);
    }

    timer = ngx_max(timer, ngx_timer_wheel_resolution);
    key = ngx_current_msec + timer;
    ev->timer.key = key;
    node = (void *)&ev->timer;

    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer add: %d: %M:%M",
                   ngx_event_ident(ev->data), timer, ev->timer.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    queue = &ngx_timer_wheel[ngx_timer_wheel_slot(key)];

    ngx_timer_wheel_link(queue, node);

    ngx_timer_wheel_size ++;

    ngx_mutex_unlock(ngx_event_timer_mutex);

    ev->timer_set = 1;
}


static void
ngx_timer_wheel_del(ngx_event_t *ev)
{
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, ev->log, 0,
                   "event timer del: %d: %M",
                   ngx_event_ident(ev->data), ev->timer.key);

    ngx_mutex_lock(ngx_event_timer_mutex);

    ngx_timer_wheel_unlink(((ngx_timer_wheel_node_t *)&ev->timer) );

    ngx_timer_wheel_size --;

    ngx_mutex_unlock(ngx_event_timer_mutex);

#if (NGX_DEBUG)
    ngx_memzero(((u_char *)&ev->timer) + sizeof(ev->timer.key),
                sizeof(ev->timer) - sizeof(ev->timer.key));
#endif

    ev->timer_set = 0;
}


static ngx_int_t
ngx_timer_wheel_empty(void)
{
    return ngx_timer_wheel_size == 0;
}

