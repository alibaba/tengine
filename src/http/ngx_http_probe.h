#ifndef _NGX_HTTP_PROBE_H_INCLUDED_
#define _NGX_HTTP_PROBE_H_INCLUDED_

#if (NGX_DTRACE)

#include <ngx_dtrace_provider.h>

#define ngx_http_probe_subrequest_cycle(pr, uri, args)                       \
    NGINX_HTTP_SUBREQUEST_CYCLE(pr, uri, args)

#define ngx_http_probe_subrequest_start(r)                                   \
    NGINX_HTTP_SUBREQUEST_START(r)

#else /* !(NGX_DTRACE) */

#define ngx_http_probe_subrequest_cycle(pr, uri, args)
#define ngx_http_probe_subrequest_start(r)                       \

#endif /* NGX_DTRACE */


#endif /* _NGX_HTTP_PROBE_H_INCLUDED_ */
