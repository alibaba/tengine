#ifndef _NGX_HTTP_PROBE_H_INCLUDED_
#define _NGX_HTTP_PROBE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#if (NGX_DTRACE)

#include <ngx_dtrace_provider.h>

#define ngx_http_probe_subrequest_cycle(pr, uri, args)                       \
    NGINX_HTTP_SUBREQUEST_CYCLE(pr, uri, args)

#define ngx_http_probe_subrequest_start(r)                                   \
    NGINX_HTTP_SUBREQUEST_START(r)

#define ngx_http_probe_subrequest_finalize_writing(r)                        \
    NGINX_HTTP_SUBREQUEST_FINALIZE_WRITING(r)

#define ngx_http_probe_subrequest_finalize_nonactive(r)                      \
    NGINX_HTTP_SUBREQUEST_FINALIZE_NONACTIVE(r)

#define ngx_http_probe_subrequest_finalize_nonactive(r)                      \
    NGINX_HTTP_SUBREQUEST_FINALIZE_NONACTIVE(r)

#define ngx_http_probe_subrequest_wake_parent(r)                             \
    NGINX_HTTP_SUBREQUEST_WAKE_PARENT(r)

#define ngx_http_probe_subrequest_done(r)                                    \
    NGINX_HTTP_SUBREQUEST_DONE(r)

#define ngx_http_probe_subrequest_post_start(r, rc)                          \
    NGINX_HTTP_SUBREQUEST_POST_START(r, rc)

#define ngx_http_probe_subrequest_post_done(r, rc)                           \
    NGINX_HTTP_SUBREQUEST_POST_DONE(r, rc)

#define ngx_http_probe_module_post_config(m)                                 \
    NGINX_HTTP_MODULE_POST_CONFIG(m)

#define ngx_http_probe_read_body_abort(r, reason)                            \
    NGINX_HTTP_READ_BODY_ABORT(r, reason)

#define ngx_http_probe_read_body_done(r)                                     \
    NGINX_HTTP_READ_BODY_DONE(r)

#define ngx_http_probe_read_req_line_done(r)                                 \
    NGINX_HTTP_READ_REQ_LINE_DONE(r)

#define ngx_http_probe_read_req_header_done(r, h)                               \
    NGINX_HTTP_READ_REQ_HEADER_DONE(r, h)

#else /* !(NGX_DTRACE) */

#define ngx_http_probe_subrequest_cycle(pr, uri, args)
#define ngx_http_probe_subrequest_start(r)
#define ngx_http_probe_subrequest_finalize_writing(r)
#define ngx_http_probe_subrequest_finalize_nonactive(r)
#define ngx_http_probe_subrequest_wake_parent(r)
#define ngx_http_probe_subrequest_done(r)
#define ngx_http_probe_subrequest_post_start(r, rc)
#define ngx_http_probe_subrequest_post_done(r, rc)
#define ngx_http_probe_module_post_config(m)
#define ngx_http_probe_read_body_abort(r, reason)
#define ngx_http_probe_read_body_done(r)
#define ngx_http_probe_read_req_line_done(r)
#define ngx_http_probe_read_req_header_done(r, h)

#endif /* NGX_DTRACE */


#endif /* _NGX_HTTP_PROBE_H_INCLUDED_ */
