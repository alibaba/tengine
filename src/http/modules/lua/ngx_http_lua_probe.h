#ifndef NGX_HTTP_LUA_PROBE_H
#define NGX_HTTP_LUA_PROBE_H


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#if defined(NGX_DTRACE) && NGX_DTRACE

#include <ngx_dtrace_provider.h>

#define ngx_http_lua_probe_register_preload_package(L, pkg)                  \
    NGINX_LUA_HTTP_LUA_REGISTER_PRELOAD_PACKAGE(L, pkg)

#define ngx_http_lua_probe_req_socket_consume_preread(r, data, len)          \
    NGINX_LUA_HTTP_LUA_REQ_SOCKET_CONSUME_PREREAD(r, data, len)

#else /* !(NGX_DTRACE) */

#define ngx_http_lua_probe_register_preload_package(L, pkg)
#define ngx_http_lua_probe_req_socket_consume_preread(r, data, len)

#endif


#endif /* NGX_HTTP_LUA_PROBE_H */
