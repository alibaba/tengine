
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_socket_udp.h"
#include "ngx_http_lua_socket_tcp.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_output.h"
#include "ngx_http_lua_probe.h"


#if 1
#undef ngx_http_lua_probe_info
#define ngx_http_lua_probe_info(msg)
#endif


#define UDP_MAX_DATAGRAM_SIZE 65536


static int ngx_http_lua_socket_udp(lua_State *L);
static int ngx_http_lua_socket_udp_setpeername(lua_State *L);
static int ngx_http_lua_socket_udp_send(lua_State *L);
static int ngx_http_lua_socket_udp_receive(lua_State *L);
static int ngx_http_lua_socket_udp_settimeout(lua_State *L);
static void ngx_http_lua_socket_udp_finalize(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u);
static int ngx_http_lua_socket_udp_upstream_destroy(lua_State *L);
static int ngx_http_lua_socket_resolve_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u, lua_State *L);
static void ngx_http_lua_socket_resolve_handler(ngx_resolver_ctx_t *ctx);
static int ngx_http_lua_socket_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u, lua_State *L);
static void ngx_http_lua_socket_udp_handle_error(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u, ngx_uint_t ft_type);
static void ngx_http_lua_socket_udp_cleanup(void *data);
static void ngx_http_lua_socket_udp_handler(ngx_event_t *ev);
static void ngx_http_lua_socket_dummy_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u);
static int ngx_http_lua_socket_udp_receive_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u, lua_State *L);
static ngx_int_t ngx_http_lua_socket_udp_read(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u);
static void ngx_http_lua_socket_udp_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u);
static void ngx_http_lua_socket_udp_handle_success(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u);
static ngx_int_t ngx_http_lua_udp_connect(ngx_http_lua_udp_connection_t *uc);
static int ngx_http_lua_socket_udp_close(lua_State *L);
static ngx_int_t ngx_http_lua_socket_udp_resume(ngx_http_request_t *r);
static void ngx_http_lua_udp_resolve_cleanup(void *data);
static void ngx_http_lua_udp_socket_cleanup(void *data);


enum {
    SOCKET_CTX_INDEX = 1,
    SOCKET_TIMEOUT_INDEX = 2,
};


static char ngx_http_lua_socket_udp_metatable_key;
static char ngx_http_lua_udp_udata_metatable_key;
static u_char ngx_http_lua_socket_udp_buffer[UDP_MAX_DATAGRAM_SIZE];


void
ngx_http_lua_inject_socket_udp_api(ngx_log_t *log, lua_State *L)
{
    lua_getfield(L, -1, "socket"); /* ngx socket */

    lua_pushcfunction(L, ngx_http_lua_socket_udp);
    lua_setfield(L, -2, "udp"); /* ngx socket */

    /* udp socket object metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          socket_udp_metatable_key));
    lua_createtable(L, 0 /* narr */, 6 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_socket_udp_setpeername);
    lua_setfield(L, -2, "setpeername"); /* ngx socket mt */

    lua_pushcfunction(L, ngx_http_lua_socket_udp_send);
    lua_setfield(L, -2, "send");

    lua_pushcfunction(L, ngx_http_lua_socket_udp_receive);
    lua_setfield(L, -2, "receive");

    lua_pushcfunction(L, ngx_http_lua_socket_udp_settimeout);
    lua_setfield(L, -2, "settimeout"); /* ngx socket mt */

    lua_pushcfunction(L, ngx_http_lua_socket_udp_close);
    lua_setfield(L, -2, "close"); /* ngx socket mt */

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* udp socket object metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          udp_udata_metatable_key));
    lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
    lua_pushcfunction(L, ngx_http_lua_socket_udp_upstream_destroy);
    lua_setfield(L, -2, "__gc");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    lua_pop(L, 1);
}


static int
ngx_http_lua_socket_udp(lua_State *L)
{
    ngx_http_request_t      *r;
    ngx_http_lua_ctx_t      *ctx;

    if (lua_gettop(L) != 0) {
        return luaL_error(L, "expecting zero arguments, but got %d",
                          lua_gettop(L));
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_YIELDABLE);

    lua_createtable(L, 3 /* narr */, 1 /* nrec */);
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          socket_udp_metatable_key));
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    dd("top: %d", lua_gettop(L));

    return 1;
}


static int
ngx_http_lua_socket_udp_setpeername(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_str_t                    host;
    int                          port;
    ngx_resolver_ctx_t          *rctx, temp;
    ngx_http_core_loc_conf_t    *clcf;
    int                          saved_top;
    int                          n;
    u_char                      *p;
    size_t                       len;
    ngx_url_t                    url;
    ngx_int_t                    rc;
    ngx_http_lua_loc_conf_t     *llcf;
    int                          timeout;
    ngx_http_lua_co_ctx_t       *coctx;

    ngx_http_lua_udp_connection_t           *uc;
    ngx_http_lua_socket_udp_upstream_t      *u;

    /*
     * TODO: we should probably accept an extra argument to setpeername()
     * to allow the user bind the datagram unix domain socket himself,
     * which is necessary for systems without autobind support.
     */

    n = lua_gettop(L);
    if (n != 2 && n != 3) {
        return luaL_error(L, "ngx.socket.udp setpeername: expecting 2 or 3 "
                          "arguments (including the object), but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_YIELDABLE);

    luaL_checktype(L, 1, LUA_TTABLE);

    p = (u_char *) luaL_checklstring(L, 2, &len);

    host.data = ngx_palloc(r->pool, len + 1);
    if (host.data == NULL) {
        return luaL_error(L, "no memory");
    }

    host.len = len;

    ngx_memcpy(host.data, p, len);
    host.data[len] = '\0';

    if (n == 3) {
        port = luaL_checkinteger(L, 3);

        if (port < 0 || port > 65535) {
            lua_pushnil(L);
            lua_pushfstring(L, "bad port number: %d", port);
            return 2;
        }

    } else { /* n == 2 */
        port = 0;
    }

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u) {
        if (u->request && u->request != r) {
            return luaL_error(L, "bad request");
        }

        if (u->waiting) {
            lua_pushnil(L);
            lua_pushliteral(L, "socket busy");
            return 2;
        }

        if (u->udp_connection.connection) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua udp socket reconnect without shutting down");

            ngx_http_lua_socket_udp_finalize(r, u);
        }

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua reuse socket upstream ctx");

    } else {
        u = lua_newuserdata(L, sizeof(ngx_http_lua_socket_udp_upstream_t));
        if (u == NULL) {
            return luaL_error(L, "no memory");
        }

#if 1
        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              udp_udata_metatable_key));
        lua_rawget(L, LUA_REGISTRYINDEX);
        lua_setmetatable(L, -2);
#endif

        lua_rawseti(L, 1, SOCKET_CTX_INDEX);
    }

    ngx_memzero(u, sizeof(ngx_http_lua_socket_udp_upstream_t));

    u->request = r; /* set the controlling request */
    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    u->conf = llcf;

    uc = &u->udp_connection;

    uc->log = *r->connection->log;

    dd("lua peer connection log: %p", &uc->log);

    lua_rawgeti(L, 1, SOCKET_TIMEOUT_INDEX);
    timeout = (ngx_int_t) lua_tointeger(L, -1);
    lua_pop(L, 1);

    if (timeout > 0) {
        u->read_timeout = (ngx_msec_t) timeout;

    } else {
        u->read_timeout = u->conf->read_timeout;
    }

    ngx_memzero(&url, sizeof(ngx_url_t));

    url.url.len = host.len;
    url.url.data = host.data;
    url.default_port = (in_port_t) port;
    url.no_resolve = 1;

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        lua_pushnil(L);

        if (url.err) {
            lua_pushfstring(L, "failed to parse host name \"%s\": %s",
                            host.data, url.err);

        } else {
            lua_pushfstring(L, "failed to parse host name \"%s\"", host.data);
        }

        return 2;
    }

    u->resolved = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_resolved_t));
    if (u->resolved == NULL) {
        return luaL_error(L, "no memory");
    }

    if (url.addrs && url.addrs[0].sockaddr) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua udp socket network address given directly");

        u->resolved->sockaddr = url.addrs[0].sockaddr;
        u->resolved->socklen = url.addrs[0].socklen;
        u->resolved->naddrs = 1;
        u->resolved->host = url.addrs[0].name;

    } else {
        u->resolved->host = host;
        u->resolved->port = (in_port_t) port;
    }

    if (u->resolved->sockaddr) {
        rc = ngx_http_lua_socket_resolve_retval_handler(r, u, L);
        if (rc == NGX_AGAIN) {
            return lua_yield(L, 0);
        }

        return rc;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    temp.name = host;
    rctx = ngx_resolve_start(clcf->resolver, &temp);
    if (rctx == NULL) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;
        lua_pushnil(L);
        lua_pushliteral(L, "failed to start the resolver");
        return 2;
    }

    if (rctx == NGX_NO_RESOLVER) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;
        lua_pushnil(L);
        lua_pushfstring(L, "no resolver defined to resolve \"%s\"", host.data);
        return 2;
    }

    rctx->name = host;
    rctx->handler = ngx_http_lua_socket_resolve_handler;
    rctx->data = u;
    rctx->timeout = clcf->resolver_timeout;

    u->co_ctx = ctx->cur_co_ctx;
    u->resolved->ctx = rctx;

    saved_top = lua_gettop(L);

    coctx = ctx->cur_co_ctx;
    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_udp_resolve_cleanup;

    if (ngx_resolve_name(rctx) != NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua udp socket fail to run resolver immediately");

        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;

        u->resolved->ctx = NULL;
        lua_pushnil(L);
        lua_pushfstring(L, "%s could not be resolved", host.data);

        return 2;
    }

    if (u->waiting == 1) {
        /* resolved and already connecting */
        return lua_yield(L, 0);
    }

    n = lua_gettop(L) - saved_top;
    if (n) {
        /* errors occurred during resolving or connecting
         * or already connected */
        return n;
    }

    /* still resolving */

    u->waiting = 1;
    u->prepare_retvals = ngx_http_lua_socket_resolve_retval_handler;

    coctx->data = u;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    return lua_yield(L, 0);
}


static void
ngx_http_lua_socket_resolve_handler(ngx_resolver_ctx_t *ctx)
{
    ngx_http_request_t                  *r;
    ngx_connection_t                    *c;
    ngx_http_upstream_resolved_t        *ur;
    ngx_http_lua_ctx_t                  *lctx;
    lua_State                           *L;
    ngx_http_lua_socket_udp_upstream_t  *u;
    u_char                              *p;
    size_t                               len;
    socklen_t                            socklen;
    struct sockaddr                     *sockaddr;
    ngx_uint_t                           i;
    unsigned                             waiting;

    u = ctx->data;
    r = u->request;
    c = r->connection;
    ur = u->resolved;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua udp socket resolve handler");

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (lctx == NULL) {
        return;
    }

    lctx->cur_co_ctx = u->co_ctx;

    u->co_ctx->cleanup = NULL;

    L = lctx->cur_co_ctx->co;

    dd("setting socket_ready to 1");

    waiting = u->waiting;

    if (ctx->state) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua udp socket resolver error: %s (waiting: %d)",
                       ngx_resolver_strerror(ctx->state), (int) u->waiting);

        lua_pushnil(L);
        lua_pushlstring(L, (char *) ctx->name.data, ctx->name.len);
        lua_pushfstring(L, " could not be resolved (%d: %s)",
                        (int) ctx->state,
                        ngx_resolver_strerror(ctx->state));
        lua_concat(L, 2);

#if 1
        ngx_resolve_name_done(ctx);
        ur->ctx = NULL;
#endif

        u->prepare_retvals = ngx_http_lua_socket_error_retval_handler;
        ngx_http_lua_socket_udp_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_RESOLVER);

        if (waiting) {
            ngx_http_run_posted_requests(c);
        }

        return;
    }

    ur->naddrs = ctx->naddrs;
    ur->addrs = ctx->addrs;

#if (NGX_DEBUG)
    {
        u_char      text[NGX_SOCKADDR_STRLEN];
        ngx_str_t   addr;
        ngx_uint_t  i;

        addr.data = text;

        for (i = 0; i < ctx->naddrs; i++) {
            addr.len = ngx_sock_ntop(ur->addrs[i].sockaddr,
                                     ur->addrs[i].socklen, text,
                                     NGX_SOCKADDR_STRLEN, 0);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "name was resolved to %V", &addr);
        }
    }
#endif

    ngx_http_lua_assert(ur->naddrs > 0);

    if (ur->naddrs == 1) {
        i = 0;

    } else {
        i = ngx_random() % ur->naddrs;
    }

    dd("selected addr index: %d", (int) i);

    socklen = ur->addrs[i].socklen;

    sockaddr = ngx_palloc(r->pool, socklen);
    if (sockaddr == NULL) {
        goto nomem;
    }

    ngx_memcpy(sockaddr, ur->addrs[i].sockaddr, socklen);

    switch (sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
    case AF_INET6:
        ((struct sockaddr_in6 *) sockaddr)->sin6_port = htons(ur->port);
        break;
#endif
    default: /* AF_INET */
        ((struct sockaddr_in *) sockaddr)->sin_port = htons(ur->port);
    }

    p = ngx_pnalloc(r->pool, NGX_SOCKADDR_STRLEN);
    if (p == NULL) {
        goto nomem;
    }

    len = ngx_sock_ntop(sockaddr, socklen, p, NGX_SOCKADDR_STRLEN, 1);
    ur->sockaddr = sockaddr;
    ur->socklen = socklen;

    ur->host.data = p;
    ur->host.len = len;
    ur->naddrs = 1;

    ngx_resolve_name_done(ctx);
    ur->ctx = NULL;

    u->waiting = 0;

    if (waiting) {
        lctx->resume_handler = ngx_http_lua_socket_udp_resume;
        r->write_event_handler(r);
        ngx_http_run_posted_requests(c);

    } else {
        (void) ngx_http_lua_socket_resolve_retval_handler(r, u, L);
    }

    return;

nomem:

    if (ur->ctx) {
        ngx_resolve_name_done(ctx);
        ur->ctx = NULL;
    }

    u->prepare_retvals = ngx_http_lua_socket_error_retval_handler;
    ngx_http_lua_socket_udp_handle_error(r, u,
                                         NGX_HTTP_LUA_SOCKET_FT_NOMEM);

    if (waiting) {
        ngx_http_run_posted_requests(c);

    } else {
        lua_pushnil(L);
        lua_pushliteral(L, "no memory");
    }
}


static int
ngx_http_lua_socket_resolve_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u, lua_State *L)
{
    ngx_http_lua_ctx_t              *ctx;
    ngx_http_lua_co_ctx_t           *coctx;
    ngx_connection_t                *c;
    ngx_pool_cleanup_t              *cln;
    ngx_http_upstream_resolved_t    *ur;
    ngx_int_t                        rc;
    ngx_http_lua_udp_connection_t   *uc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket resolve retval handler");

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_RESOLVER) {
        return 2;
    }

    uc = &u->udp_connection;

    ur = u->resolved;

    if (ur->sockaddr) {
        uc->sockaddr = ur->sockaddr;
        uc->socklen = ur->socklen;
        uc->server = ur->host;

    } else {
        lua_pushnil(L);
        lua_pushliteral(L, "resolver not working");
        return 2;
    }

    rc = ngx_http_lua_udp_connect(uc);

    if (rc != NGX_OK) {
        u->socket_errno = ngx_socket_errno;
    }

    if (u->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(r->pool, 0);
        if (cln == NULL) {
            u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
            lua_pushnil(L);
            lua_pushliteral(L, "no memory");
            return 2;
        }

        cln->handler = ngx_http_lua_socket_udp_cleanup;
        cln->data = u;
        u->cleanup = &cln->handler;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket connect: %i", rc);

    if (rc != NGX_OK) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    /* rc == NGX_OK */

    c = uc->connection;

    c->data = u;

    c->write->handler = NULL;
    c->read->handler = ngx_http_lua_socket_udp_handler;
    c->read->resolver = 0;

    c->pool = r->pool;
    c->log = r->connection->log;
    c->read->log = c->log;
    c->write->log = c->log;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    coctx = ctx->cur_co_ctx;

    coctx->data = u;

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;

    lua_pushinteger(L, 1);
    return 1;
}


static int
ngx_http_lua_socket_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u, lua_State *L)
{
    u_char           errstr[NGX_MAX_ERROR_STR];
    u_char          *p;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket error retval handler");

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_RESOLVER) {
        return 2;
    }

    lua_pushnil(L);

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_PARTIALWRITE) {
        lua_pushliteral(L, "partial write");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_TIMEOUT) {
        lua_pushliteral(L, "timeout");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_CLOSED) {
        lua_pushliteral(L, "closed");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_BUFTOOSMALL) {
        lua_pushliteral(L, "buffer too small");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_NOMEM) {
        lua_pushliteral(L, "no memory");

    } else {

        if (u->socket_errno) {
            p = ngx_strerror(u->socket_errno, errstr, sizeof(errstr));
            /* for compatibility with LuaSocket */
            ngx_strlow(errstr, errstr, p - errstr);
            lua_pushlstring(L, (char *) errstr, p - errstr);

        } else {
            lua_pushliteral(L, "error");
        }
    }

    return 2;
}


static int
ngx_http_lua_socket_udp_send(lua_State *L)
{
    ssize_t                              n;
    ngx_http_request_t                  *r;
    u_char                              *p;
    u_char                              *str;
    size_t                               len;
    ngx_http_lua_socket_udp_upstream_t  *u;
    int                                  type;
    const char                          *msg;
    ngx_str_t                            query;
    ngx_http_lua_loc_conf_t             *llcf;

    if (lua_gettop(L) != 2) {
        return luaL_error(L, "expecting 2 arguments (including the object), "
                          "but got %d", lua_gettop(L));
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->udp_connection.connection == NULL) {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to send data on a closed socket: u:%p, c:%p",
                          u, u ? u->udp_connection.connection : NULL);
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    if (u->ft_type) {
        u->ft_type = 0;
    }

    if (u->waiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "socket busy");
        return 2;
    }

    type = lua_type(L, 2);
    switch (type) {
        case LUA_TNUMBER:
            len = ngx_http_lua_get_num_len(L, 2);
            break;

        case LUA_TSTRING:
            lua_tolstring(L, 2, &len);
            break;

        case LUA_TTABLE:
            /* The maximum possible length, not the actual length */
            len = ngx_http_lua_calc_strlen_in_table(L, 2, 2, 1 /* strict */);
            break;

        case LUA_TNIL:
            len = sizeof("nil") - 1;
            break;

        case LUA_TBOOLEAN:
            if (lua_toboolean(L, 2)) {
                len = sizeof("true") - 1;

            } else {
                len = sizeof("false") - 1;
            }

            break;

        default:
            msg = lua_pushfstring(L, "string, number, boolean, nil, "
                                  "or array table expected, got %s",
                                  lua_typename(L, type));

            return luaL_argerror(L, 2, msg);
    }

    query.data = lua_newuserdata(L, len);
    p = query.data;

    switch (type) {
        case LUA_TNUMBER:
            p = ngx_http_lua_write_num(L, 2, p);
            break;

        case LUA_TSTRING:
            str = (u_char *) lua_tolstring(L, 2, &len);
            p = ngx_cpymem(p, (u_char *) str, len);
            break;

        case LUA_TTABLE:
            p = ngx_http_lua_copy_str_in_table(L, 2, p);
            break;

        case LUA_TNIL:
            *p++ = 'n';
            *p++ = 'i';
            *p++ = 'l';
            break;

        case LUA_TBOOLEAN:
            if (lua_toboolean(L, 2)) {
                *p++ = 't';
                *p++ = 'r';
                *p++ = 'u';
                *p++ = 'e';

            } else {
                *p++ = 'f';
                *p++ = 'a';
                *p++ = 'l';
                *p++ = 's';
                *p++ = 'e';
            }

            break;

        default:
            return luaL_error(L, "impossible to reach here");
    }

    query.len = p - query.data;
    ngx_http_lua_assert(query.len <= len);

    u->ft_type = 0;

    /* mimic ngx_http_upstream_init_request here */

#if 1
    u->waiting = 0;
#endif

    dd("sending query %.*s", (int) query.len, query.data);

    n = ngx_send(u->udp_connection.connection, query.data, query.len);

    dd("ngx_send returns %d (query len %d)", (int) n, (int) query.len);

    if (n == NGX_ERROR || n == NGX_AGAIN) {
        u->socket_errno = ngx_socket_errno;

        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    if (n != (ssize_t) query.len) {
        dd("not the while query was sent");

        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_PARTIALWRITE;
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    dd("n == len");

    lua_pushinteger(L, 1);
    return 1;
}


static int
ngx_http_lua_socket_udp_receive(lua_State *L)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_udp_upstream_t  *u;
    ngx_int_t                            rc;
    ngx_http_lua_ctx_t                  *ctx;
    ngx_http_lua_co_ctx_t               *coctx;
    size_t                               size;
    int                                  nargs;
    ngx_http_lua_loc_conf_t             *llcf;

    nargs = lua_gettop(L);
    if (nargs != 1 && nargs != 2) {
        return luaL_error(L, "expecting 1 or 2 arguments "
                          "(including the object), but got %d", nargs);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket calling receive() method");

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->udp_connection.connection == NULL) {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to receive data on a closed socket: u:%p, "
                          "c:%p", u, u ? u->udp_connection.connection : NULL);
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    if (u->ft_type) {
        u->ft_type = 0;
    }

#if 1
    if (u->waiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "socket busy");
        return 2;
    }
#endif

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket read timeout: %M", u->read_timeout);

    size = (size_t) luaL_optnumber(L, 2, UDP_MAX_DATAGRAM_SIZE);
    size = ngx_min(size, UDP_MAX_DATAGRAM_SIZE);

    u->recv_buf_size = size;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket receive buffer size: %uz", u->recv_buf_size);

    rc = ngx_http_lua_socket_udp_read(r, u);

    if (rc == NGX_ERROR) {
        dd("read failed: %d", (int) u->ft_type);
        rc = ngx_http_lua_socket_udp_receive_retval_handler(r, u, L);
        dd("udp receive retval returned: %d", (int) rc);
        return rc;
    }

    if (rc == NGX_OK) {

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua udp socket receive done in a single run");

        return ngx_http_lua_socket_udp_receive_retval_handler(r, u, L);
    }

    /* n == NGX_AGAIN */

    u->read_event_handler = ngx_http_lua_socket_udp_read_handler;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    coctx = ctx->cur_co_ctx;

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_udp_socket_cleanup;
    coctx->data = u;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    u->co_ctx = coctx;
    u->waiting = 1;
    u->prepare_retvals = ngx_http_lua_socket_udp_receive_retval_handler;

    return lua_yield(L, 0);
}


static int
ngx_http_lua_socket_udp_receive_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u, lua_State *L)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket receive return value handler");

    if (u->ft_type) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    lua_pushlstring(L, (char *) ngx_http_lua_socket_udp_buffer, u->received);
    return 1;
}


static int
ngx_http_lua_socket_udp_settimeout(lua_State *L)
{
    int                     n;
    ngx_int_t               timeout;

    ngx_http_lua_socket_udp_upstream_t  *u;

    n = lua_gettop(L);

    if (n != 2) {
        return luaL_error(L, "ngx.socket settimeout: expecting at least 2 "
                          "arguments (including the object) but seen %d",
                          lua_gettop(L));
    }

    timeout = (ngx_int_t) lua_tonumber(L, 2);

    lua_rawseti(L, 1, SOCKET_TIMEOUT_INDEX);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);

    if (u) {
        if (timeout > 0) {
            u->read_timeout = (ngx_msec_t) timeout;

        } else {
            u->read_timeout = u->conf->read_timeout;
        }
    }

    return 0;
}


static void
ngx_http_lua_socket_udp_finalize(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua finalize socket");

    if (u->cleanup) {
        *u->cleanup = NULL;
        u->cleanup = NULL;
    }

    if (u->resolved && u->resolved->ctx) {
        ngx_resolve_name_done(u->resolved->ctx);
        u->resolved->ctx = NULL;
    }

    if (u->udp_connection.connection) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua close socket connection");

        ngx_close_connection(u->udp_connection.connection);
        u->udp_connection.connection = NULL;
    }

    if (u->waiting) {
        u->waiting = 0;
    }
}


static int
ngx_http_lua_socket_udp_upstream_destroy(lua_State *L)
{
    ngx_http_lua_socket_udp_upstream_t      *u;

    dd("upstream destroy triggered by Lua GC");

    u = lua_touserdata(L, 1);
    if (u == NULL) {
        return 0;
    }

    if (u->cleanup) {
        ngx_http_lua_socket_udp_cleanup(u); /* it will clear u->cleanup */
    }

    return 0;
}


static void
ngx_http_lua_socket_dummy_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket dummy handler");
}


static ngx_int_t
ngx_http_lua_socket_udp_read(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u)
{
    ngx_connection_t            *c;
    ngx_event_t                 *rev;
    ssize_t                      n;

    c = u->udp_connection.connection;
    rev = c->read;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua udp socket read data: waiting: %d", (int) u->waiting);

    n = ngx_udp_recv(u->udp_connection.connection,
                     ngx_http_lua_socket_udp_buffer, u->recv_buf_size);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua udp recv returned %z", n);

    if (n >= 0) {
        u->received = n;
        ngx_http_lua_socket_udp_handle_success(r, u);
        return NGX_OK;
    }

    if (n == NGX_ERROR) {
        u->socket_errno = ngx_socket_errno;
        ngx_http_lua_socket_udp_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    /* n == NGX_AGAIN */

#if 1
    if (ngx_handle_read_event(rev, 0) != NGX_OK) {
        ngx_http_lua_socket_udp_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }
#endif

    if (rev->active) {
        ngx_add_timer(rev, u->read_timeout);

    } else if (rev->timer_set) {
        ngx_del_timer(rev);
    }

    return NGX_AGAIN;
}


static void
ngx_http_lua_socket_udp_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u)
{
    ngx_connection_t            *c;
    ngx_http_lua_loc_conf_t     *llcf;

    c = u->udp_connection.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket read handler");

    if (c->read->timedout) {
        c->read->timedout = 0;

        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "lua udp socket read timed out");
        }

        ngx_http_lua_socket_udp_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
        return;
    }

#if 1
    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }
#endif

    (void) ngx_http_lua_socket_udp_read(r, u);
}


static void
ngx_http_lua_socket_udp_handle_error(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u, ngx_uint_t ft_type)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket handle error");

    u->ft_type |= ft_type;

#if 0
    ngx_http_lua_socket_udp_finalize(r, u);
#endif

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;

    coctx = u->co_ctx;

    if (coctx) {
        coctx->cleanup = NULL;
    }

    if (u->waiting) {
        u->waiting = 0;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            return;
        }

        ctx->resume_handler = ngx_http_lua_socket_udp_resume;
        ctx->cur_co_ctx = coctx;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua udp socket waking up the current request");

        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_socket_udp_cleanup(void *data)
{
    ngx_http_lua_socket_udp_upstream_t  *u = data;

    ngx_http_request_t  *r;

    r = u->request;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "cleanup lua udp socket upstream request: \"%V\"", &r->uri);

    ngx_http_lua_socket_udp_finalize(r, u);
}


static void
ngx_http_lua_socket_udp_handler(ngx_event_t *ev)
{
    ngx_connection_t                *c;
    ngx_http_request_t              *r;
    ngx_http_log_ctx_t              *ctx;

    ngx_http_lua_socket_udp_upstream_t  *u;

    c = ev->data;
    u = c->data;
    r = u->request;
    c = r->connection;

    if (c->fd != (ngx_socket_t) -1) {  /* not a fake connection */
        ctx = c->log->data;
        ctx->current_request = r;
    }

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua udp socket handler for \"%V?%V\", wev %d", &r->uri,
                   &r->args, (int) ev->write);

    u->read_event_handler(r, u);

    ngx_http_run_posted_requests(c);
}


static void
ngx_http_lua_socket_udp_handle_success(ngx_http_request_t *r,
    ngx_http_lua_socket_udp_upstream_t *u)
{
    ngx_http_lua_ctx_t          *ctx;

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;

    if (u->co_ctx) {
        u->co_ctx->cleanup = NULL;
    }

    if (u->waiting) {
        u->waiting = 0;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            return;
        }

        ctx->resume_handler = ngx_http_lua_socket_udp_resume;
        ctx->cur_co_ctx = u->co_ctx;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua udp socket waking up the current request");

        r->write_event_handler(r);
    }
}


static ngx_int_t
ngx_http_lua_udp_connect(ngx_http_lua_udp_connection_t *uc)
{
    int                rc;
    ngx_int_t          event;
    ngx_event_t       *rev, *wev;
    ngx_socket_t       s;
    ngx_connection_t  *c;

    s = ngx_socket(uc->sockaddr->sa_family, SOCK_DGRAM, 0);

    ngx_log_debug1(NGX_LOG_DEBUG_EVENT, &uc->log, 0, "UDP socket %d", s);

    if (s == (ngx_socket_t) -1) {
        ngx_log_error(NGX_LOG_ALERT, &uc->log, ngx_socket_errno,
                      ngx_socket_n " failed");

        return NGX_ERROR;
    }

    c = ngx_get_connection(s, &uc->log);

    if (c == NULL) {
        if (ngx_close_socket(s) == -1) {
            ngx_log_error(NGX_LOG_ALERT, &uc->log, ngx_socket_errno,
                          ngx_close_socket_n "failed");
        }

        return NGX_ERROR;
    }

    if (ngx_nonblocking(s) == -1) {
        ngx_log_error(NGX_LOG_ALERT, &uc->log, ngx_socket_errno,
                      ngx_nonblocking_n " failed");

        ngx_free_connection(c);

        if (ngx_close_socket(s) == -1) {
            ngx_log_error(NGX_LOG_ALERT, &uc->log, ngx_socket_errno,
                          ngx_close_socket_n " failed");
        }

        return NGX_ERROR;
    }

    rev = c->read;
    wev = c->write;

    rev->log = &uc->log;
    wev->log = &uc->log;

    uc->connection = c;

    c->number = ngx_atomic_fetch_add(ngx_connection_counter, 1);

#if (NGX_HTTP_LUA_HAVE_SO_PASSCRED)
    if (uc->sockaddr->sa_family == AF_UNIX) {
        struct sockaddr         addr;

        addr.sa_family = AF_UNIX;

        /* just to make valgrind happy */
        ngx_memzero(addr.sa_data, sizeof(addr.sa_data));

        ngx_log_debug0(NGX_LOG_DEBUG_EVENT, &uc->log, 0, "datagram unix "
                       "domain socket autobind");

        if (bind(uc->connection->fd, &addr, sizeof(sa_family_t)) != 0) {
            ngx_log_error(NGX_LOG_CRIT, &uc->log, ngx_socket_errno,
                          "bind() failed");

            return NGX_ERROR;
        }
    }
#endif

    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, &uc->log, 0,
                   "connect to %V, fd:%d #%d", &uc->server, s, c->number);

    rc = connect(s, uc->sockaddr, uc->socklen);

    /* TODO: aio, iocp */

    if (rc == -1) {
        ngx_log_error(NGX_LOG_CRIT, &uc->log, ngx_socket_errno,
                      "connect() failed");

        return NGX_ERROR;
    }

    /* UDP sockets are always ready to write */
    wev->ready = 1;

    if (ngx_add_event) {

        event = (ngx_event_flags & NGX_USE_CLEAR_EVENT) ?
                    /* kqueue, epoll */                 NGX_CLEAR_EVENT:
                    /* select, poll, /dev/poll */       NGX_LEVEL_EVENT;
                    /* eventport event type has no meaning: oneshot only */

        if (ngx_add_event(rev, NGX_READ_EVENT, event) != NGX_OK) {
            return NGX_ERROR;
        }

    } else {
        /* rtsig */

        if (ngx_add_conn(c) == NGX_ERROR) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static int
ngx_http_lua_socket_udp_close(lua_State *L)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_udp_upstream_t  *u;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting 1 argument "
                          "(including the object) but seen %d", lua_gettop(L));
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->udp_connection.connection == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    if (u->waiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "socket busy");
        return 2;
    }

    ngx_http_lua_socket_udp_finalize(r, u);

    lua_pushinteger(L, 1);
    return 1;
}


static ngx_int_t
ngx_http_lua_socket_udp_resume(ngx_http_request_t *r)
{
    int                          nret;
    lua_State                   *vm;
    ngx_int_t                    rc;
    ngx_uint_t                   nreqs;
    ngx_connection_t            *c;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    ngx_http_lua_socket_udp_upstream_t      *u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp operation done, resuming lua thread");

    coctx = ctx->cur_co_ctx;

#if 0
    ngx_http_lua_probe_info("udp resume");
#endif

    u = coctx->data;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua udp socket calling prepare retvals handler %p, "
                   "u:%p", u->prepare_retvals, u);

    nret = u->prepare_retvals(r, u, ctx->cur_co_ctx->co);
    if (nret == NGX_AGAIN) {
        return NGX_DONE;
    }

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(vm, r, ctx, nret);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static void
ngx_http_lua_udp_resolve_cleanup(void *data)
{
    ngx_resolver_ctx_t                      *rctx;
    ngx_http_lua_socket_udp_upstream_t      *u;
    ngx_http_lua_co_ctx_t                   *coctx = data;

    u = coctx->data;
    if (u == NULL) {
        return;
    }

    rctx = u->resolved->ctx;
    if (rctx == NULL) {
        return;
    }

    /* postpone free the rctx in the handler */
    rctx->handler = ngx_resolve_name_done;
}


static void
ngx_http_lua_udp_socket_cleanup(void *data)
{
    ngx_http_lua_socket_udp_upstream_t      *u;
    ngx_http_lua_co_ctx_t                   *coctx = data;

    u = coctx->data;
    if (u == NULL) {
        return;
    }

    if (u->request == NULL) {
        return;
    }

    ngx_http_lua_socket_udp_finalize(u->request, u);
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
