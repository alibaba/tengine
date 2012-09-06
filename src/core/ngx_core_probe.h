#ifndef _NGX_CORE_PROBE_H_INCLUDED_
#define _NGX_CORE_PROBE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>


#if (NGX_DTRACE)

#include <ngx_http.h>
#include <ngx_dtrace_provider.h>

#define ngx_core_probe_create_pool_done(pool, size)                             \
    NGINX_CREATE_POOL_DONE(pool, size)

#else /* !(NGX_DTRACE) */

#define ngx_core_probe_create_pool_done(pool, size)

#endif


#endif /* _NGX_CORE_PROBE_H_INCLUDED_ */
