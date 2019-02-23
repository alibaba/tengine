/*
 * automatically generated from the file dtrace/ngx_lua_provider.d by the
 *  gen-dtrace-probe-header tool in the nginx-devel-utils project:
 *  https://github.com/agentzh/nginx-devel-utils
 */

#ifndef _NGX_HTTP_LUA_PROBE_H_INCLUDED_
#define _NGX_HTTP_LUA_PROBE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#if defined(NGX_DTRACE) && NGX_DTRACE

#include <ngx_dtrace_provider.h>

#define ngx_http_lua_probe_info(s)                                           \
    NGINX_LUA_HTTP_LUA_INFO(s)

#define ngx_http_lua_probe_register_preload_package(L, pkg)                  \
    NGINX_LUA_HTTP_LUA_REGISTER_PRELOAD_PACKAGE(L, pkg)

#define ngx_http_lua_probe_req_socket_consume_preread(r, data, len)          \
    NGINX_LUA_HTTP_LUA_REQ_SOCKET_CONSUME_PREREAD(r, data, len)

#define ngx_http_lua_probe_user_coroutine_create(r, parent, child)           \
    NGINX_LUA_HTTP_LUA_USER_COROUTINE_CREATE(r, parent, child)

#define ngx_http_lua_probe_user_coroutine_resume(r, parent, child)           \
    NGINX_LUA_HTTP_LUA_USER_COROUTINE_RESUME(r, parent, child)

#define ngx_http_lua_probe_user_coroutine_yield(r, parent, child)            \
    NGINX_LUA_HTTP_LUA_USER_COROUTINE_YIELD(r, parent, child)

#define ngx_http_lua_probe_thread_yield(r, L)                                \
    NGINX_LUA_HTTP_LUA_THREAD_YIELD(r, L)

#define ngx_http_lua_probe_socket_tcp_send_start(r, u, data, len)            \
    NGINX_LUA_HTTP_LUA_SOCKET_TCP_SEND_START(r, u, data, len)

#define ngx_http_lua_probe_socket_tcp_receive_done(r, u, data, len)          \
    NGINX_LUA_HTTP_LUA_SOCKET_TCP_RECEIVE_DONE(r, u, data, len)

#define ngx_http_lua_probe_socket_tcp_setkeepalive_buf_unread(r, u, data,    \
                                                              len)           \
    NGINX_LUA_HTTP_LUA_SOCKET_TCP_SETKEEPALIVE_BUF_UNREAD(r, u, data, len)

#define ngx_http_lua_probe_user_thread_spawn(r, creator, newthread)          \
    NGINX_LUA_HTTP_LUA_USER_THREAD_SPAWN(r, creator, newthread)

#define ngx_http_lua_probe_thread_delete(r, thread, ctx)                     \
    NGINX_LUA_HTTP_LUA_THREAD_DELETE(r, thread, ctx)

#define ngx_http_lua_probe_run_posted_thread(r, thread, status)              \
    NGINX_LUA_HTTP_LUA_RUN_POSTED_THREAD(r, thread, status)

#define ngx_http_lua_probe_coroutine_done(r, co, success)                    \
    NGINX_LUA_HTTP_LUA_COROUTINE_DONE(r, co, success)

#define ngx_http_lua_probe_user_thread_wait(parent, child)                   \
    NGINX_LUA_HTTP_LUA_USER_THREAD_WAIT(parent, child)

#else /* !(NGX_DTRACE) */

#define ngx_http_lua_probe_info(s)
#define ngx_http_lua_probe_register_preload_package(L, pkg)
#define ngx_http_lua_probe_req_socket_consume_preread(r, data, len)
#define ngx_http_lua_probe_user_coroutine_create(r, parent, child)
#define ngx_http_lua_probe_user_coroutine_resume(r, parent, child)
#define ngx_http_lua_probe_user_coroutine_yield(r, parent, child)
#define ngx_http_lua_probe_thread_yield(r, L)
#define ngx_http_lua_probe_socket_tcp_send_start(r, u, data, len)
#define ngx_http_lua_probe_socket_tcp_receive_done(r, u, data, len)
#define ngx_http_lua_probe_socket_tcp_setkeepalive_buf_unread(r, u, data, len)
#define ngx_http_lua_probe_user_thread_spawn(r, creator, newthread)
#define ngx_http_lua_probe_thread_delete(r, thread, ctx)
#define ngx_http_lua_probe_run_posted_thread(r, thread, status)
#define ngx_http_lua_probe_coroutine_done(r, co, success)
#define ngx_http_lua_probe_user_thread_wait(parent, child)

#endif

#endif /* _NGX_HTTP_LUA_PROBE_H_INCLUDED_ */
