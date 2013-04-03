

#ifndef _NGX_TIMER_MODULE_INCLUDE_
#define _NGX_TIMER_MODULE_INCLUDE_

#include <ngx_event.h>

#define ngx_timer_before(x, y)  ((ngx_msec_int_t) (x - y) <= 0)

typedef struct {
    ngx_str_t    name;
    void       (*add)(ngx_event_t *ev, ngx_msec_t timer);
    void       (*del)(ngx_event_t *ev);
    ngx_int_t  (*empty)(void);
    ngx_msec_t (*find_min)(void);
    void       (*expire_timers)(void);

    ngx_int_t  (*init)(ngx_cycle_t *cycle);
} ngx_timer_actions_t;

extern ngx_timer_actions_t   ngx_timer_actions;

#define ngx_add_timer               ngx_timer_actions.add
#define ngx_del_timer               ngx_timer_actions.del
#define ngx_timer_empty             ngx_timer_actions.empty
#define ngx_timer_find_min          ngx_timer_actions.find_min
#define ngx_timer_expire_timers     ngx_timer_actions.expire_timers

typedef struct {
    ngx_timer_actions_t  *use;
    ngx_msec_t            wheel_max;
} ngx_timer_conf_t;

extern ngx_module_t ngx_timer_module;
#include <ngx_event_timer.h>

#endif /* _NGX_TIMER_MODULE_INCLUDE_ */

