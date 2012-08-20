#ifndef _NGX_EVENT_PROBE_H_INCLUDED_
#define _NGX_EVENT_PROBE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>


#if (NGX_DTRACE)

#include <ngx_dtrace_provider.h>

#define ngx_event_probe_timer_add(ev, timer)                                 \
    NGINX_TIMER_ADD(ev, timer)

#define ngx_event_probe_timer_del(ev)                                        \
    NGINX_TIMER_DEL(ev)

#define ngx_event_probe_timer_expire(ev)                                     \
    NGINX_TIMER_EXPIRE(ev)

#else /* !(NGX_DTRACE) */

#define ngx_event_probe_timer_add(ev, timer)
#define ngx_event_probe_timer_del(ev)
#define ngx_event_probe_timer_expire(ev)

#endif


#endif /* _NGX_EVENT_PROBE_H_INCLUDED_ */
