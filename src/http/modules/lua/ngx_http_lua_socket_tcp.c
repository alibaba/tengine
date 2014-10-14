
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_socket_tcp.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_output.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_probe.h"


#if 1
#undef ngx_http_lua_probe_info
#define ngx_http_lua_probe_info(msg)
#endif


static int ngx_http_lua_socket_tcp(lua_State *L);
static int ngx_http_lua_socket_tcp_connect(lua_State *L);
static int ngx_http_lua_socket_tcp_receive(lua_State *L);
static int ngx_http_lua_socket_tcp_send(lua_State *L);
static int ngx_http_lua_socket_tcp_close(lua_State *L);
static int ngx_http_lua_socket_tcp_setoption(lua_State *L);
static int ngx_http_lua_socket_tcp_settimeout(lua_State *L);
static void ngx_http_lua_socket_tcp_handler(ngx_event_t *ev);
static ngx_int_t ngx_http_lua_socket_tcp_get_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_lua_socket_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_send_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_connected_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_tcp_cleanup(void *data);
static void ngx_http_lua_req_socket_cleanup(void *data);
static void ngx_http_lua_socket_tcp_finalize(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_send(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_test_connect(ngx_connection_t *c);
static void ngx_http_lua_socket_handle_error(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_uint_t ft_type);
static void ngx_http_lua_socket_handle_success(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static int ngx_http_lua_socket_tcp_send_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static int ngx_http_lua_socket_tcp_connect_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static void ngx_http_lua_socket_dummy_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_tcp_read(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static int ngx_http_lua_socket_tcp_receive_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static ngx_int_t ngx_http_lua_socket_read_line(void *data, ssize_t bytes);
static void ngx_http_lua_socket_resolve_handler(ngx_resolver_ctx_t *ctx);
static int ngx_http_lua_socket_resolve_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static int ngx_http_lua_socket_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static ngx_int_t ngx_http_lua_socket_read_all(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_socket_read_until(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_socket_read_chunk(void *data, ssize_t bytes);
static int ngx_http_lua_socket_tcp_receiveuntil(lua_State *L);
static int ngx_http_lua_socket_receiveuntil_iterator(lua_State *L);
static ngx_int_t ngx_http_lua_socket_compile_pattern(u_char *data, size_t len,
    ngx_http_lua_socket_compiled_pattern_t *cp, ngx_log_t *log);
static int ngx_http_lua_socket_cleanup_compiled_pattern(lua_State *L);
static int ngx_http_lua_req_socket(lua_State *L);
static void ngx_http_lua_req_socket_rev_handler(ngx_http_request_t *r);
static int ngx_http_lua_socket_tcp_getreusedtimes(lua_State *L);
static int ngx_http_lua_socket_tcp_setkeepalive(lua_State *L);
static ngx_int_t ngx_http_lua_get_keepalive_peer(ngx_http_request_t *r,
    lua_State *L, int key_index,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_keepalive_dummy_handler(ngx_event_t *ev);
static ngx_int_t ngx_http_lua_socket_keepalive_close_handler(ngx_event_t *ev);
static void ngx_http_lua_socket_keepalive_rev_handler(ngx_event_t *ev);
static void ngx_http_lua_socket_free_pool(ngx_log_t *log,
    ngx_http_lua_socket_pool_t *spool);
static int ngx_http_lua_socket_tcp_upstream_destroy(lua_State *L);
static int ngx_http_lua_socket_downstream_destroy(lua_State *L);
static ngx_int_t ngx_http_lua_socket_push_input_data(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_http_lua_socket_tcp_upstream_t *u,
    lua_State *L);
static ngx_int_t ngx_http_lua_socket_add_pending_data(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, u_char *pos, size_t len, u_char *pat,
    int prefix, int old_state);
static ngx_int_t ngx_http_lua_socket_add_input_buffer(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_insert_buffer(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, u_char *pat, size_t prefix);
static ngx_int_t ngx_http_lua_socket_tcp_resume(ngx_http_request_t *r);
static void ngx_http_lua_tcp_resolve_cleanup(void *data);
static void ngx_http_lua_tcp_socket_cleanup(void *data);


enum {
    SOCKET_CTX_INDEX = 1,
    SOCKET_TIMEOUT_INDEX = 2,
    SOCKET_KEY_INDEX = 3
};


static char ngx_http_lua_req_socket_metatable_key;
static char ngx_http_lua_tcp_socket_metatable_key;


void
ngx_http_lua_inject_socket_tcp_api(ngx_log_t *log, lua_State *L)
{
    ngx_int_t         rc;

    lua_createtable(L, 0, 3 /* nrec */);    /* ngx.socket */

    lua_pushcfunction(L, ngx_http_lua_socket_tcp);
    lua_setfield(L, -2, "tcp");

    {
        const char  buf[] = "local sock = ngx.socket.tcp()"
                            " local ok, err = sock:connect(...)"
                            " if ok then return sock else return nil, err end";

        rc = luaL_loadbuffer(L, buf, sizeof(buf) - 1, "ngx.socket.connect");
    }

    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_CRIT, log, 0,
                      "failed to load Lua code for ngx.socket.connect(): %i",
                      rc);

    } else {
        lua_setfield(L, -2, "connect");
    }

    lua_setfield(L, -2, "socket");

    /* {{{req socket object metatable */
    lua_pushlightuserdata(L, &ngx_http_lua_req_socket_metatable_key);
    lua_createtable(L, 0 /* narr */, 4 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receive);
    lua_setfield(L, -2, "receive");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receiveuntil);
    lua_setfield(L, -2, "receiveuntil");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_settimeout);
    lua_setfield(L, -2, "settimeout"); /* ngx socket mt */

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* {{{tcp object metatable */
    lua_pushlightuserdata(L, &ngx_http_lua_tcp_socket_metatable_key);
    lua_createtable(L, 0 /* narr */, 10 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_connect);
    lua_setfield(L, -2, "connect");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receive);
    lua_setfield(L, -2, "receive");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receiveuntil);
    lua_setfield(L, -2, "receiveuntil");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_send);
    lua_setfield(L, -2, "send");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_close);
    lua_setfield(L, -2, "close");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_setoption);
    lua_setfield(L, -2, "setoption");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_settimeout);
    lua_setfield(L, -2, "settimeout"); /* ngx socket mt */

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_getreusedtimes);
    lua_setfield(L, -2, "getreusedtimes");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_setkeepalive);
    lua_setfield(L, -2, "setkeepalive");

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */
}


void
ngx_http_lua_inject_req_socket_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_req_socket);
    lua_setfield(L, -2, "socket");
}


static int
ngx_http_lua_socket_tcp(lua_State *L)
{
    ngx_http_request_t      *r;
    ngx_http_lua_ctx_t      *ctx;

    if (lua_gettop(L) != 0) {
        return luaL_error(L, "expecting zero arguments, but got %d",
                          lua_gettop(L));
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    lua_createtable(L, 3 /* narr */, 1 /* nrec */);
    lua_pushlightuserdata(L, &ngx_http_lua_tcp_socket_metatable_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    dd("top: %d", lua_gettop(L));

    return 1;
}


static int
ngx_http_lua_socket_tcp_connect(lua_State *L)
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
    ngx_peer_connection_t       *pc;
    int                          timeout;
    unsigned                     custom_pool;
    int                          key_index;
    const char                  *msg;
    ngx_http_lua_co_ctx_t       *coctx;

    ngx_http_lua_socket_tcp_upstream_t      *u;

    n = lua_gettop(L);
    if (n != 2 && n != 3 && n != 4) {
        return luaL_error(L, "ngx.socket connect: expecting 2, 3, or 4 "
                          "arguments (including the object), but seen %d", n);
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    luaL_checktype(L, 1, LUA_TTABLE);

    p = (u_char *) luaL_checklstring(L, 2, &len);

    host.data = ngx_palloc(r->pool, len + 1);
    if (host.data == NULL) {
        return luaL_error(L, "out of memory");
    }

    host.len = len;

    ngx_memcpy(host.data, p, len);
    host.data[len] = '\0';

    key_index = 2;
    custom_pool = 0;

    if (lua_type(L, n) == LUA_TTABLE) {

        /* found the last optional option table */

        lua_getfield(L, n, "pool");

        switch (lua_type(L, -1)) {
        case LUA_TNUMBER:
            lua_tostring(L, -1);

        case LUA_TSTRING:
            custom_pool = 1;

            lua_pushvalue(L, -1);
            lua_rawseti(L, 1, SOCKET_KEY_INDEX);

            key_index = n + 1;

            break;

        default:
            msg = lua_pushfstring(L, "bad \"pool\" option type: %s",
                                  luaL_typename(L, -1));
            luaL_argerror(L, n, msg);
            break;
        }

        n--;
    }

    if (n == 3) {
        port = luaL_checkinteger(L, 3);

        if (port < 0 || port > 65536) {
            lua_pushnil(L);
            lua_pushfstring(L, "bad port number: %d", port);
            return 2;
        }

        if (!custom_pool) {
            lua_pushliteral(L, ":");
            lua_insert(L, 3);
            lua_concat(L, 3);
        }

        dd("socket key: %s", lua_tostring(L, -1));

    } else { /* n == 2 */
        port = 0;
    }

    if (!custom_pool) {
        /* the key's index is 2 */

        lua_pushvalue(L, 2);
        lua_rawseti(L, 1, SOCKET_KEY_INDEX);
    }

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u) {
        if (u->waiting) {
            lua_pushnil(L);
            lua_pushliteral(L, "socket busy");
            return 2;
        }

        if (u->is_downstream) {
            return luaL_error(L, "attempt to re-connect a request socket");
        }

        if (u->peer.connection) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua tcp socket reconnect without shutting down");

            ngx_http_lua_socket_tcp_finalize(r, u);
        }

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua reuse socket upstream ctx");

    } else {
        u = lua_newuserdata(L, sizeof(ngx_http_lua_socket_tcp_upstream_t));
        if (u == NULL) {
            return luaL_error(L, "out of memory");
        }

#if 1
        lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
        lua_pushcfunction(L, ngx_http_lua_socket_tcp_upstream_destroy);
        lua_setfield(L, -2, "__gc");
        lua_setmetatable(L, -2);
#endif

        lua_rawseti(L, 1, SOCKET_CTX_INDEX);
    }

    ngx_memzero(u, sizeof(ngx_http_lua_socket_tcp_upstream_t));

    coctx = ctx->cur_co_ctx;

    u->request = r; /* set the controlling request */

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    u->conf = llcf;

    pc = &u->peer;

    pc->log = r->connection->log;
    pc->log_error = NGX_ERROR_ERR;

    dd("lua peer connection log: %p", pc->log);

    lua_rawgeti(L, 1, SOCKET_TIMEOUT_INDEX);
    timeout = (ngx_int_t) lua_tointeger(L, -1);
    lua_pop(L, 1);

    if (timeout > 0) {
        u->send_timeout = (ngx_msec_t) timeout;
        u->read_timeout = (ngx_msec_t) timeout;
        u->connect_timeout = (ngx_msec_t) timeout;

    } else {
        u->read_timeout = u->conf->read_timeout;
        u->send_timeout = u->conf->send_timeout;
        u->connect_timeout = u->conf->connect_timeout;
    }

    rc = ngx_http_lua_get_keepalive_peer(r, L, key_index, u);

    if (rc == NGX_OK) {
        lua_pushinteger(L, 1);
        return 1;
    }

    if (rc == NGX_ERROR) {
        lua_pushnil(L);
        lua_pushliteral(L, "error in get keepalive peer");
        return 2;
    }

    /* rc == NGX_DECLINED */

    ngx_memzero(&url, sizeof(ngx_url_t));

    url.url.len = host.len;
    url.url.data = host.data;
    url.default_port = port;
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

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connect timeout: %M", u->connect_timeout);

    u->resolved = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_resolved_t));
    if (u->resolved == NULL) {
        return luaL_error(L, "out of memory");
    }

    if (url.addrs && url.addrs[0].sockaddr) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket network address given directly");

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
    /* TODO remove */
    // rctx->type = NGX_RESOLVE_A;
    /* END */
    rctx->handler = ngx_http_lua_socket_resolve_handler;
    rctx->data = u;
    rctx->timeout = clcf->resolver_timeout;

    u->resolved->ctx = rctx;
    u->co_ctx = ctx->cur_co_ctx;

    coctx->data = u;

    saved_top = lua_gettop(L);

    coctx->cleanup = ngx_http_lua_tcp_resolve_cleanup;

    if (ngx_resolve_name(rctx) != NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket fail to run resolver immediately");

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

    dd("setting data to %p", u);

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
    ngx_http_lua_socket_tcp_upstream_t  *u;
    u_char                              *p;
    size_t                               len;
    struct sockaddr_in                  *sin;
    ngx_uint_t                           i;
    unsigned                             waiting;

    u = ctx->data;
    r = u->request;
    c = r->connection;
    ur = u->resolved;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua tcp socket resolve handler");

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (lctx == NULL) {
        return;
    }

    lctx->cur_co_ctx = u->co_ctx;

    u->co_ctx->cleanup = NULL;

    L = lctx->cur_co_ctx->co;

    waiting = u->waiting;

    if (ctx->state) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua tcp socket resolver error: %s (waiting: %d)",
                       ngx_resolver_strerror(ctx->state), (int) u->waiting);

        lua_pushnil(L);
        lua_pushlstring(L, (char *) ctx->name.data, ctx->name.len);
        lua_pushfstring(L, " could not be resolved (%d: %s)",
                        (int) ctx->state,
                        ngx_resolver_strerror(ctx->state));
        lua_concat(L, 2);

        u->prepare_retvals = ngx_http_lua_socket_error_retval_handler;
        ngx_http_lua_socket_handle_error(r, u,
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
    in_addr_t           addr;
    ngx_uint_t          i;
    struct sockaddr_in *sin;

    for (i = 0; i < ctx->naddrs; i++) {
        dd("addr i: %d %p", (int) i,  &ctx->addrs[i]);

        sin = (struct sockaddr_in *) ctx->addrs[i].sockaddr;
        addr = ntohl(sin->sin_addr.s_addr);

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "name was resolved to %ud.%ud.%ud.%ud",
                       (addr >> 24) & 0xff, (addr >> 16) & 0xff,
                       (addr >> 8) & 0xff, addr & 0xff);
    }
    }
#endif

    if (ur->naddrs == 0) {
        ngx_resolve_name_done(ctx);
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;

        lua_pushnil(L);
        lua_pushliteral(L, "name cannot be resolved to a address");

        if (waiting) {
            ngx_http_run_posted_requests(c);
        }

        return;
    }

    if (ur->naddrs == 1) {
        i = 0;

    } else {
        i = ngx_random() % ur->naddrs;
    }

    dd("selected addr index: %d", (int) i);

    len = NGX_INET_ADDRSTRLEN + sizeof(":65536") - 1;

    p = ngx_pnalloc(r->pool, len + sizeof(struct sockaddr_in));
    if (p == NULL) {
        ngx_resolve_name_done(ctx);
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;

        lua_pushnil(L);
        lua_pushliteral(L, "out of memory");

        if (waiting) {
            ngx_http_run_posted_requests(c);
        }

        return;
    }

    sin = (struct sockaddr_in *) &p[len];
    ngx_memzero(sin, sizeof(struct sockaddr_in));

    len = ngx_inet_ntop(AF_INET, &ur->addrs[i], p, NGX_INET_ADDRSTRLEN);
    len = ngx_sprintf(&p[len], ":%d", ur->port) - p;

    sin->sin_family = AF_INET;
    sin->sin_port = htons(ur->port);
    sin->sin_addr.s_addr = ((struct sockaddr_in *)
                                       ur->addrs[i].sockaddr)->sin_addr.s_addr;

    ur->sockaddr = (struct sockaddr *) sin;
    ur->socklen = sizeof(struct sockaddr_in);

    ur->host.data = p;
    ur->host.len = len;
    ur->naddrs = 1;

    ur->ctx = NULL;

    ngx_resolve_name_done(ctx);

    u->waiting = 0;

    if (waiting) {
        lctx->resume_handler = ngx_http_lua_socket_tcp_resume;
        r->write_event_handler(r);
        ngx_http_run_posted_requests(c);

    } else {
        (void) ngx_http_lua_socket_resolve_retval_handler(r, u, L);
    }
}


static int
ngx_http_lua_socket_resolve_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    ngx_http_lua_ctx_t              *ctx;
    ngx_peer_connection_t           *pc;
    ngx_connection_t                *c;
    ngx_http_cleanup_t              *cln;
    ngx_http_upstream_resolved_t    *ur;
    ngx_int_t                        rc;
    ngx_http_lua_co_ctx_t           *coctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket resolve retval handler");

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_RESOLVER) {
        return 2;
    }

    pc = &u->peer;

    ur = u->resolved;

    if (ur->sockaddr) {
        pc->sockaddr = ur->sockaddr;
        pc->socklen = ur->socklen;
        pc->name = &ur->host;

    } else {
        lua_pushnil(L);
        lua_pushliteral(L, "resolver not working");
        return 2;
    }

    pc->get = ngx_http_lua_socket_tcp_get_peer;

    rc = ngx_event_connect_peer(pc);

    if (rc == NGX_ERROR) {
        u->socket_errno = ngx_socket_errno;
    }

    if (u->cleanup == NULL) {
        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
            lua_pushnil(L);
            lua_pushliteral(L, "out of memory");
            return 2;
        }

        cln->handler = ngx_http_lua_socket_tcp_cleanup;
        cln->data = u;
        u->cleanup = &cln->handler;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connect: %i", rc);

    if (rc == NGX_ERROR) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    if (rc == NGX_BUSY) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
        lua_pushnil(L);
        lua_pushliteral(L, "no live connection");
        return 2;
    }

    if (rc == NGX_DECLINED) {
        dd("socket errno: %d", (int) ngx_socket_errno);
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
        u->socket_errno = ngx_socket_errno;
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    /* rc == NGX_OK || rc == NGX_AGAIN */

    c = pc->connection;

    c->data = u;

    c->write->handler = ngx_http_lua_socket_tcp_handler;
    c->read->handler = ngx_http_lua_socket_tcp_handler;

    u->write_event_handler = ngx_http_lua_socket_connected_handler;
    u->read_event_handler = ngx_http_lua_socket_connected_handler;

    c->sendfile &= r->connection->sendfile;

    c->pool = r->pool;
    c->log = r->connection->log;
    c->read->log = c->log;
    c->write->log = c->log;

    /* init or reinit the ngx_output_chain() and ngx_chain_writer() contexts */

#if 0
    u->writer.out = NULL;
    u->writer.last = &u->writer.out;
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    coctx = ctx->cur_co_ctx;

    dd("setting data to %p", u);

    coctx->data = u;

    if (rc == NGX_OK) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket connected: fd:%d", (int) c->fd);

        /* We should delete the current write/read event
         * here because the socket object may not be used immediately
         * on the Lua land, thus causing hot spin around level triggered
         * event poll and wasting CPU cycles. */

        if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            lua_pushnil(L);
            lua_pushliteral(L, "failed to handle write event");
            return 2;
        }

        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            lua_pushnil(L);
            lua_pushliteral(L, "failed to handle write event");
            return 2;
        }

        u->read_event_handler = ngx_http_lua_socket_dummy_handler;
        u->write_event_handler = ngx_http_lua_socket_dummy_handler;

        lua_pushinteger(L, 1);
        return 1;
    }

    /* rc == NGX_AGAIN */

    coctx->cleanup = ngx_http_lua_tcp_socket_cleanup;

    ngx_add_timer(c->write, u->connect_timeout);

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    u->co_ctx = ctx->cur_co_ctx;
    u->waiting = 1;
    u->prepare_retvals = ngx_http_lua_socket_tcp_connect_retval_handler;

    dd("setting data to %p", u);

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    return NGX_AGAIN;
}


static int
ngx_http_lua_socket_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    u_char           errstr[NGX_MAX_ERROR_STR];
    u_char          *p;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket error retval handler");

    if (u->co_ctx) {
        u->co_ctx->cleanup = NULL;
    }

    ngx_http_lua_socket_tcp_finalize(r, u);

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_RESOLVER) {
        return 2;
    }

    lua_pushnil(L);

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_TIMEOUT) {
        lua_pushliteral(L, "timeout");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_CLOSED) {
        lua_pushliteral(L, "closed");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_BUFTOOSMALL) {
        lua_pushliteral(L, "buffer too small");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_NOMEM) {
        lua_pushliteral(L, "out of memory");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_CLIENTABORT) {
        lua_pushliteral(L, "client aborted");

    } else {

        if (u->socket_errno) {
#if (nginx_version >= 1000000)
            p = ngx_strerror(u->socket_errno, errstr, sizeof(errstr));
#else
            p = ngx_strerror_r(u->socket_errno, errstr, sizeof(errstr));
#endif
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
ngx_http_lua_socket_tcp_connect_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    if (u->ft_type) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    lua_pushinteger(L, 1);
    return 1;
}


static int
ngx_http_lua_socket_tcp_receive(lua_State *L)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_tcp_upstream_t  *u;
    ngx_int_t                            rc;
    ngx_http_lua_ctx_t                  *ctx;
    int                                  n;
    ngx_str_t                            pat;
    lua_Integer                          bytes;
    char                                *p;
    int                                  typ;
    ngx_http_lua_loc_conf_t             *llcf;
    ngx_http_lua_co_ctx_t               *coctx;

    n = lua_gettop(L);
    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 arguments "
                          "(including the object), but got %d", n);
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket calling receive() method");

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {

        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to receive data on a closed socket: u:%p, "
                          "c:%p, ft:%ui eof:%ud",
                          u, u ? u->peer.connection : NULL, u ? u->ft_type : 0,
                          u ? u->eof : 0);
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->waiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "socket busy");
        return 2;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket read timeout: %M", u->read_timeout);

    if (n > 1) {
        if (lua_isnumber(L, 2)) {
            typ = LUA_TNUMBER;

        } else {
            typ = lua_type(L, 2);
        }

        switch (typ) {
        case LUA_TSTRING:
            pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);
            if (pat.len != 2 || pat.data[0] != '*') {
                p = (char *) lua_pushfstring(L, "bad pattern argument: %s",
                                             (char *) pat.data);

                return luaL_argerror(L, 2, p);
            }

            switch (pat.data[1]) {
            case 'l':
                u->input_filter = ngx_http_lua_socket_read_line;
                break;

            case 'a':
                u->input_filter = ngx_http_lua_socket_read_all;
                break;

            default:
                return luaL_argerror(L, 2, "bad pattern argument");
                break;
            }

            u->length = 0;
            u->rest = 0;

            break;

        case LUA_TNUMBER:
            bytes = lua_tointeger(L, 2);
            if (bytes < 0) {
                return luaL_argerror(L, 2, "bad pattern argument");
            }

            u->input_filter = ngx_http_lua_socket_read_chunk;
            u->length = (size_t) bytes;
            u->rest = u->length;

            break;

        default:
            return luaL_argerror(L, 2, "bad pattern argument");
            break;
        }

    } else {
        u->input_filter = ngx_http_lua_socket_read_line;
        u->length = 0;
        u->rest = 0;
    }

    u->input_filter_ctx = u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (u->bufs_in == NULL) {
        u->bufs_in =
            ngx_http_lua_chains_get_free_buf(r->connection->log, r->pool,
                                             &ctx->free_recv_bufs,
                                             u->conf->buffer_size,
                                             (ngx_buf_tag_t)
                                             &ngx_http_lua_module);

        if (u->bufs_in == NULL) {
            return luaL_error(L, "out of memory");
        }

        u->buf_in = u->bufs_in;
        u->buffer = *u->buf_in->buf;
    }

    dd("tcp receive: buf_in: %p, bufs_in: %p", u->buf_in, u->bufs_in);

    if (u->is_downstream) {
        r->read_event_handler = ngx_http_lua_req_socket_rev_handler;
    }

    u->waiting = 0;

    rc = ngx_http_lua_socket_tcp_read(r, u);

    if (rc == NGX_ERROR) {
        dd("read failed: %d", (int) u->ft_type);
        rc = ngx_http_lua_socket_tcp_receive_retval_handler(r, u, L);
        dd("tcp receive retval returned: %d", (int) rc);
        return rc;
    }

    if (rc == NGX_OK) {

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket receive done in a single run");

        return ngx_http_lua_socket_tcp_receive_retval_handler(r, u, L);
    }

    /* rc == NGX_AGAIN */

    u->read_event_handler = ngx_http_lua_socket_read_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    ctx->cur_co_ctx->cleanup = ngx_http_lua_tcp_socket_cleanup;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    u->co_ctx = ctx->cur_co_ctx;
    u->waiting = 1;
    u->prepare_retvals = ngx_http_lua_socket_tcp_receive_retval_handler;

    coctx = ctx->cur_co_ctx;

    dd("setting data to %p, coctx:%p", u, coctx);

    coctx->data = u;

    if (u->is_downstream) {
        ctx->req_body_reader_co_ctx = coctx;
    }

    return lua_yield(L, 0);
}


static ngx_int_t
ngx_http_lua_socket_read_chunk(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_tcp_upstream_t      *u = data;

    ngx_buf_t                   *b;
#if (NGX_DEBUG)
    ngx_http_request_t          *r;

    r = u->request;
#endif

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket read chunk %z", bytes);

    if (bytes == 0) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    b = &u->buffer;

    if (bytes >= (ssize_t) u->rest) {

        u->buf_in->buf->last += u->rest;
        b->pos += u->rest;
        u->rest = 0;

        return NGX_OK;
    }

    /* bytes < u->rest */

    u->buf_in->buf->last += bytes;
    b->pos += bytes;
    u->rest -= bytes;

    return NGX_AGAIN;
}


static ngx_int_t
ngx_http_lua_socket_read_all(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_tcp_upstream_t      *u = data;

    ngx_buf_t                   *b;
#if (NGX_DEBUG)
    ngx_http_request_t          *r;

    r = u->request;
#endif

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket read all");

    if (bytes == 0) {
        return NGX_OK;
    }

    b = &u->buffer;

    u->buf_in->buf->last += bytes;
    b->pos += bytes;

    return NGX_AGAIN;
}


static ngx_int_t
ngx_http_lua_socket_read_line(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_tcp_upstream_t      *u = data;

    ngx_buf_t                   *b;
    u_char                      *dst;
    u_char                       c;
#if (NGX_DEBUG)
    u_char                      *begin;
#endif

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua tcp socket read line");

    if (bytes == 0) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    b = &u->buffer;

#if (NGX_DEBUG)
    begin = b->pos;
#endif

    dd("already read: %p: %.*s", u->buf_in,
            (int) (u->buf_in->buf->last - u->buf_in->buf->pos),
            u->buf_in->buf->pos);

    dd("data read: %.*s", (int) bytes, b->pos);

    dst = u->buf_in->buf->last;

    while (bytes--) {

        c = *b->pos++;

        switch (c) {
        case '\n':
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                           "lua tcp socket read the final line part: \"%*s\"",
                           b->pos - 1 - begin, begin);

            u->buf_in->buf->last = dst;

            dd("read a line: %p: %.*s", u->buf_in,
                    (int) (u->buf_in->buf->last - u->buf_in->buf->pos),
                    u->buf_in->buf->pos);

            return NGX_OK;

        case '\r':
            /* ignore it */
            break;

        default:
            *dst++ = c;
            break;
        }
    }

#if (NGX_DEBUG)
    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua tcp socket read partial line data: %*s",
                   dst - begin, begin);
#endif

    u->buf_in->buf->last = dst;

    return NGX_AGAIN;
}


static ngx_int_t
ngx_http_lua_socket_tcp_read(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_int_t                    rc;
    ngx_connection_t            *c;
    ngx_buf_t                   *b;
    ngx_event_t                 *rev;
    size_t                       size;
    ssize_t                      n;
    unsigned                     read;
    size_t                       preread = 0;
    ngx_http_lua_loc_conf_t     *llcf;

    c = u->peer.connection;
    rev = c->read;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua tcp socket read data: waiting: %d", (int) u->waiting);

    b = &u->buffer;
    read = 0;

    for ( ;; ) {

        size = b->last - b->pos;

        if (size || u->eof) {

            rc = u->input_filter(u->input_filter_ctx, size);

            if (rc == NGX_OK) {

                ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "lua tcp socket receive done: wait:%d, eof:%d, "
                               "uri:\"%V?%V\"", (int) u->waiting, (int) u->eof,
                               &r->uri, &r->args);

                if (u->is_downstream
                    && b->last == b->pos
                    && r->request_body->rest == 0)
                {

                    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

                    if (llcf->check_client_abort) {
                        rc = ngx_http_lua_check_broken_connection(r, rev);

                        if (rc == NGX_OK) {
                            goto success;
                        }

                        if (rc == NGX_HTTP_CLIENT_CLOSED_REQUEST) {
                            ngx_http_lua_socket_handle_error(r, u,
                                         NGX_HTTP_LUA_SOCKET_FT_CLIENTABORT);

                        } else {
                            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
                        }

                        return NGX_ERROR;
                    }
                }

#if 1
                if (ngx_handle_read_event(rev, 0) != NGX_OK) {
                    ngx_http_lua_socket_handle_error(r, u,
                                     NGX_HTTP_LUA_SOCKET_FT_ERROR);
                    return NGX_ERROR;
                }
#endif

success:
                ngx_http_lua_socket_handle_success(r, u);
                return NGX_OK;
            }

            if (rc == NGX_ERROR) {
                dd("input filter error: ft_type:%d waiting:%d",
                   (int) u->ft_type, (int) u->waiting);

                ngx_http_lua_socket_handle_error(r, u,
                                                 NGX_HTTP_LUA_SOCKET_FT_ERROR);
                return NGX_ERROR;
            }

            /* rc == NGX_AGAIN */

            if (u->is_downstream && r->request_body->rest == 0) {
                u->eof = 1;
            }

            continue;
        }

        if (read && !rev->ready) {
            rc = NGX_AGAIN;
            break;
        }

        size = b->end - b->last;

        if (size == 0) {
            rc = ngx_http_lua_socket_add_input_buffer(r, u);
            if (rc == NGX_ERROR) {
                ngx_http_lua_socket_handle_error(r, u,
                                                 NGX_HTTP_LUA_SOCKET_FT_NOMEM);

                return NGX_ERROR;
            }

            b = &u->buffer;
            size = b->end - b->last;
        }

        if (u->is_downstream) {
            if (r->request_body->rest == 0) {

                dd("request body rest is zero");

                u->eof = 1;

                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "lua request body exhausted");

                continue;
            }

            /* try to process the preread body */

            preread = r->header_in->last - r->header_in->pos;

            if (preread) {

                /* there is the pre-read part of the request body */

                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "http client request body preread %uz", preread);

                if ((off_t) preread >= r->request_body->rest) {
                    preread = r->request_body->rest;
                }

                if (size > preread) {
                    size = preread;
                }

                ngx_http_lua_probe_req_socket_consume_preread(r,
                                                              r->header_in->pos,
                                                              size);

                b->last = ngx_copy(b->last, r->header_in->pos, size);

                r->header_in->pos += size;
                r->request_length += size;

                if (r->request_body->rest) {
                    r->request_body->rest -= size;
                }

                continue;
            }

            if (size > (size_t) r->request_body->rest) {
                size = (size_t) r->request_body->rest;
            }
        }

#if 1
        if (rev->active && !rev->ready) {
            rc = NGX_AGAIN;
            break;
        }
#endif

        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket try to recv data %uz: \"%V?%V\"",
                       size, &r->uri, &r->args);

        n = c->recv(c, b->last, size);

        dd("read event ready: %d", (int) c->read->ready);

        read = 1;

        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket recv returned %d: \"%V?%V\"",
                       (int) n, &r->uri, &r->args);

        if (n == NGX_AGAIN) {
            rc = NGX_AGAIN;
            dd("socket recv busy");
            break;
        }

        if (n == 0) {

            if (u->is_downstream) {

                llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

                if (llcf->check_client_abort) {

                    ngx_http_lua_socket_handle_error(r, u,
                                         NGX_HTTP_LUA_SOCKET_FT_CLIENTABORT);
                    return NGX_ERROR;
                }

                /* llcf->check_client_abort == 0 */

                if (r->request_body->rest) {
                    ngx_http_lua_socket_handle_error(r, u,
                                         NGX_HTTP_LUA_SOCKET_FT_CLIENTABORT);
                    return NGX_ERROR;
                }
            }

            u->eof = 1;

            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua tcp socket closed");

            continue;
        }

        if (n == NGX_ERROR) {
            u->socket_errno = ngx_socket_errno;
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            return NGX_ERROR;
        }

        b->last += n;

        if (u->is_downstream) {
            r->request_length += n;
            r->request_body->rest -= n;
        }
    }

#if 1
    if (ngx_handle_read_event(rev, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u,
                                         NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }
#endif

    if (rev->active) {
        ngx_add_timer(rev, u->read_timeout);

    } else if (rev->timer_set) {
        ngx_del_timer(rev);
    }

    return rc;
}


static int
ngx_http_lua_socket_tcp_send(lua_State *L)
{
    ngx_int_t                            rc;
    ngx_http_request_t                  *r;
    u_char                              *p;
    size_t                               len;
    ngx_chain_t                         *cl;
    ngx_http_lua_ctx_t                  *ctx;
    ngx_http_lua_socket_tcp_upstream_t  *u;
    int                                  type;
    const char                          *msg;
    ngx_buf_t                           *b;
    ngx_http_lua_loc_conf_t             *llcf;
    ngx_http_lua_co_ctx_t               *coctx;

    /* TODO: add support for the optional "i" and "j" arguments */

    if (lua_gettop(L) != 2) {
        return luaL_error(L, "expecting 2 arguments (including the object), "
                          "but got %d", lua_gettop(L));
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to send data on a closed socket: u:%p, "
                          "c:%p, ft:%ui eof:%ud",
                          u, u ? u->peer.connection : NULL, u ? u->ft_type : 0,
                          u ? u->eof : 0);
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->waiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "socket busy");
        return 2;
    }

    if (u->is_downstream) {
        return luaL_error(L, "attempt to write to request sockets");
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket send timeout: %M", u->send_timeout);

    type = lua_type(L, 2);
    switch (type) {
        case LUA_TNUMBER:
        case LUA_TSTRING:
            lua_tolstring(L, 2, &len);
            break;

        case LUA_TTABLE:
            len = ngx_http_lua_calc_strlen_in_table(L, 2, 2, 1 /* strict */);
            break;

        default:
            msg = lua_pushfstring(L, "string, number, boolean, nil, "
                                  "or array table expected, got %s",
                                  lua_typename(L, type));

            return luaL_argerror(L, 2, msg);
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    cl = ngx_http_lua_chains_get_free_buf(r->connection->log, r->pool,
                                          &ctx->free_bufs, len,
                                          (ngx_buf_tag_t)
                                          &ngx_http_lua_module);

    if (cl == NULL) {
        return luaL_error(L, "out of memory");
    }

    b = cl->buf;

    switch (type) {
        case LUA_TNUMBER:
        case LUA_TSTRING:
            p = (u_char *) lua_tolstring(L, -1, &len);
            b->last = ngx_copy(b->last, (u_char *) p, len);
            break;

        case LUA_TTABLE:
            b->last = ngx_http_lua_copy_str_in_table(L, -1, b->last);
            break;

        default:
            return luaL_error(L, "impossible to reach here");
    }

    u->request_bufs = cl;

    u->request_len = len;
    u->ft_type = 0;

    /* mimic ngx_http_upstream_init_request here */

#if 1
    u->waiting = 0;
#endif

    ngx_http_lua_probe_socket_tcp_send_start(r, u, b->pos, len);

    rc = ngx_http_lua_socket_send(r, u);

    dd("socket send returned %d", (int) rc);

    if (rc == NGX_ERROR) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    if (rc == NGX_OK) {
        lua_pushinteger(L, len);
        return 1;
    }

    /* rc == NGX_AGAIN */

    ctx->cur_co_ctx->cleanup = ngx_http_lua_tcp_socket_cleanup;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    u->co_ctx = ctx->cur_co_ctx;
    u->waiting = 1;
    u->prepare_retvals = ngx_http_lua_socket_tcp_send_retval_handler;

    dd("setting data to %p", u);

    coctx = ctx->cur_co_ctx;

    coctx->data = u;

    return lua_yield(L, 0);
}


static int
ngx_http_lua_socket_tcp_send_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket send return value handler");

    if (u->ft_type) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    lua_pushinteger(L, u->request_len);
    return 1;
}


static int
ngx_http_lua_socket_tcp_receive_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    int                          n;
    ngx_int_t                    rc;
    ngx_http_lua_ctx_t          *ctx;
    ngx_event_t                 *ev;

    ngx_http_lua_loc_conf_t             *llcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket receive return value handler");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

#if 1
    if (u->is_downstream) {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->check_client_abort) {

            r->read_event_handler = ngx_http_lua_rd_check_broken_connection;

            ev = r->connection->read;

            dd("rev active: %d", ev->active);

            if ((ngx_event_flags & NGX_USE_LEVEL_EVENT) && !ev->active) {
                if (ngx_add_event(ev, NGX_READ_EVENT, 0) != NGX_OK) {
                    lua_pushnil(L);
                    lua_pushliteral(L, "failed to add event");
                    return 2;
                }
            }

        } else {
            /* llcf->check_client_abort == 0 */
            r->read_event_handler = ngx_http_block_reading;
        }
    }
#endif

    if (u->ft_type) {

        dd("u->bufs_in: %p", u->bufs_in);

        if (u->bufs_in) {
            rc = ngx_http_lua_socket_push_input_data(r, ctx, u, L);
            if (rc == NGX_ERROR) {
                lua_pushnil(L);
                lua_pushliteral(L, "out of memory");
                return 2;
            }

            (void) ngx_http_lua_socket_error_retval_handler(r, u, L);

            lua_pushvalue(L, -3);
            lua_remove(L, -4);
            return 3;
        }

        n = ngx_http_lua_socket_error_retval_handler(r, u, L);
        lua_pushliteral(L, "");
        return n + 1;
    }

    rc = ngx_http_lua_socket_push_input_data(r, ctx, u, L);
    if (rc == NGX_ERROR) {
        lua_pushnil(L);
        lua_pushliteral(L, "out of memory");
        return 2;
    }

    return 1;
}


static int
ngx_http_lua_socket_tcp_close(lua_State *L)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_tcp_upstream_t  *u;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting 1 argument "
                          "(including the object) but seen %d", lua_gettop(L));
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->waiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "socket busy");
        return 2;
    }

    if (u->is_downstream) {
        lua_pushnil(L);
        lua_pushliteral(L, "attempt to close a request socket");
        return 2;
    }

    ngx_http_lua_socket_tcp_finalize(r, u);

    lua_pushinteger(L, 1);
    return 1;
}


static int
ngx_http_lua_socket_tcp_setoption(lua_State *L)
{
    /* TODO */
    return 0;
}


static int
ngx_http_lua_socket_tcp_settimeout(lua_State *L)
{
    int                     n;
    ngx_int_t               timeout;

    ngx_http_lua_socket_tcp_upstream_t  *u;

    n = lua_gettop(L);

    if (n != 2) {
        return luaL_error(L, "ngx.socket settimout: expecting at least 2 "
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
            u->send_timeout = (ngx_msec_t) timeout;
            u->connect_timeout = (ngx_msec_t) timeout;

        } else {
            u->read_timeout = u->conf->read_timeout;
            u->send_timeout = u->conf->send_timeout;
            u->connect_timeout = u->conf->connect_timeout;
        }
    }

    return 0;
}


static void
ngx_http_lua_socket_tcp_handler(ngx_event_t *ev)
{
    ngx_connection_t                *c;
    ngx_http_request_t              *r;
    ngx_http_log_ctx_t              *ctx;

    ngx_http_lua_socket_tcp_upstream_t  *u;

    c = ev->data;
    u = c->data;
    r = u->request;
    c = r->connection;

    ctx = c->log->data;
    ctx->current_request = r;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket handler for \"%V?%V\", wev %d", &r->uri,
                   &r->args, (int) ev->write);

    if (ev->write) {
        u->write_event_handler(r, u);

    } else {
        u->read_event_handler(r, u);
    }

    ngx_http_run_posted_requests(c);
}


static ngx_int_t
ngx_http_lua_socket_tcp_get_peer(ngx_peer_connection_t *pc, void *data)
{
    /* empty */
    return NGX_OK;
}


static void
ngx_http_lua_socket_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_connection_t            *c;
    ngx_http_lua_loc_conf_t     *llcf;

    c = u->peer.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket read handler");

    if (c->read->timedout) {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "lua tcp socket read timed out");
        }

        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
        return;
    }

#if 1
    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }
#endif

    if (u->buffer.start != NULL) {
        (void) ngx_http_lua_socket_tcp_read(r, u);
    }
}


static void
ngx_http_lua_socket_send_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_connection_t            *c;
    ngx_http_lua_loc_conf_t     *llcf;

    c = u->peer.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket send handler");

    if (c->write->timedout) {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "lua tcp socket write timed out");
        }

        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
        return;
    }

    if (u->request_bufs) {
        (void) ngx_http_lua_socket_send(r, u);
    }
}


static ngx_int_t
ngx_http_lua_socket_send(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_int_t                    n;
    ngx_connection_t            *c;
    ngx_http_lua_ctx_t          *ctx;
    ngx_buf_t                   *b;

    c = u->peer.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket send data");

    dd("lua connection log: %p", c->log);

    b = u->request_bufs->buf;

    for (;;) {
        n = c->send(c, b->pos, b->last - b->pos);

        if (n >= 0) {
            b->pos += n;

            if (b->pos == b->last) {
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                               "lua tcp socket sent all the data");

                if (c->write->timer_set) {
                    ngx_del_timer(c->write);
                }

                ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
                if (ctx == NULL) {
                    ngx_http_lua_socket_handle_error(r, u,
                                                 NGX_HTTP_LUA_SOCKET_FT_ERROR);
                    return NGX_ERROR;
                }

#if defined(nginx_version) && nginx_version >= 1001004
                ngx_chain_update_chains(r->pool,
#else
                ngx_chain_update_chains(
#endif
                                        &ctx->free_bufs, &ctx->busy_bufs,
                                        &u->request_bufs,
                                        (ngx_buf_tag_t) &ngx_http_lua_module);

                u->write_event_handler = ngx_http_lua_socket_dummy_handler;

                if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
                    ngx_http_lua_socket_handle_error(r, u,
                                                 NGX_HTTP_LUA_SOCKET_FT_ERROR);
                    return NGX_ERROR;
                }

                ngx_http_lua_socket_handle_success(r, u);
                return NGX_OK;
            }

            /* keep sending more data */
            continue;
        }

        /* NGX_ERROR || NGX_AGAIN */
        break;
    }

    if (n == NGX_ERROR) {
        u->socket_errno = ngx_socket_errno;
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    /* n == NGX_AGAIN */

    u->write_event_handler = ngx_http_lua_socket_send_handler;
    u->read_event_handler = ngx_http_lua_socket_dummy_handler;

    ngx_add_timer(c->write, u->send_timeout);

    if (ngx_handle_write_event(c->write, u->conf->send_lowat) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u,
                     NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    return NGX_AGAIN;
}


static void
ngx_http_lua_socket_handle_success(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_http_lua_ctx_t          *ctx;

#if 1
    u->read_event_handler = ngx_http_lua_socket_dummy_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;
#endif

    if (u->co_ctx) {
        u->co_ctx->cleanup = NULL;
    }

#if 0
    if (u->eof) {
        ngx_http_lua_socket_tcp_finalize(r, u);
    }
#endif

    if (u->waiting) {
        u->waiting = 0;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            return;
        }

        ctx->resume_handler = ngx_http_lua_socket_tcp_resume;
        ctx->cur_co_ctx = u->co_ctx;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket waking up the current request");

        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_socket_handle_error(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_uint_t ft_type)
{
    ngx_http_lua_ctx_t          *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket handle error");

    u->ft_type |= ft_type;

#if 0
    ngx_http_lua_socket_tcp_finalize(r, u);
#endif

    if (u->co_ctx) {
        u->co_ctx->cleanup = NULL;
    }

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    if (u->waiting) {
        u->waiting = 0;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            return;
        }

        ctx->resume_handler = ngx_http_lua_socket_tcp_resume;
        ctx->cur_co_ctx = u->co_ctx;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket waking up the current request");

        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_socket_connected_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_int_t                    rc;
    ngx_connection_t            *c;
    ngx_http_lua_loc_conf_t     *llcf;

    c = u->peer.connection;

    if (c->write->timedout) {

        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "lua tcp socket connect timed out");
        }

        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
        return;
    }

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    rc = ngx_http_lua_socket_test_connect(c);
    if (rc != NGX_OK) {
        if (rc > 0) {
            u->socket_errno = (ngx_err_t) rc;
        }

        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connected");

    /* We should delete the current write/read event
     * here because the socket object may not be used immediately
     * on the Lua land, thus causing hot spin around level triggered
     * event poll and wasting CPU cycles. */

    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    ngx_http_lua_socket_handle_success(r, u);
}


static void
ngx_http_lua_socket_tcp_cleanup(void *data)
{
    ngx_http_lua_socket_tcp_upstream_t  *u = data;

    ngx_http_request_t  *r;

    r = u->request;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "cleanup lua tcp socket upstream request: \"%V\"", &r->uri);

    ngx_http_lua_socket_tcp_finalize(r, u);
}


static void
ngx_http_lua_socket_tcp_finalize(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_http_lua_socket_pool_t          *spool;
    ngx_chain_t                         *cl;
    ngx_chain_t                        **ll;
    ngx_http_lua_ctx_t                  *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua finalize socket");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx && u->bufs_in) {

        ll = &u->bufs_in;
        for (cl = u->bufs_in; cl; cl = cl->next) {
            dd("bufs_in chain: %p, next %p", cl, cl->next);
            cl->buf->pos = cl->buf->last;
            ll = &cl->next;
        }

        dd("ctx: %p", ctx);
        dd("free recv bufs: %p", ctx->free_recv_bufs);
        *ll = ctx->free_recv_bufs;
        ctx->free_recv_bufs = u->bufs_in;
        u->bufs_in = NULL;
        u->buf_in = NULL;
        ngx_memzero(&u->buffer, sizeof(ngx_buf_t));
    }

    if (u->cleanup) {
        *u->cleanup = NULL;
        u->cleanup = NULL;
    }

    if (u->is_downstream) {
        if (r->connection->read->timer_set) {
            ngx_del_timer(r->connection->read);
        }

        u->peer.connection = NULL;
        return;
    }

    if (u->resolved && u->resolved->ctx) {
        ngx_resolve_name_done(u->resolved->ctx);
        u->resolved->ctx = NULL;
    }

    if (u->peer.free) {
        u->peer.free(&u->peer, u->peer.data, 0);
    }

    if (u->peer.connection) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua close socket connection");

        ngx_close_connection(u->peer.connection);
        u->peer.connection = NULL;

        if (!u->reused) {
            return;
        }

        spool = u->socket_pool;
        if (spool == NULL) {
            return;
        }

        spool->active_connections--;

        if (spool->active_connections == 0) {
            ngx_http_lua_socket_free_pool(r->connection->log, spool);
        }
    }
}


static ngx_int_t
ngx_http_lua_socket_test_connect(ngx_connection_t *c)
{
    int              err;
    socklen_t        len;

#if (NGX_HAVE_KQUEUE)

    ngx_event_t     *ev;

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT)  {
        dd("pending eof: (%p)%d (%p)%d", c->write, c->write->pending_eof,
            c->read, c->read->pending_eof);

        if (c->write->pending_eof) {
            ev = c->write;

        } else if (c->read->pending_eof) {
            ev = c->read;

        } else {
            ev = NULL;
        }

        if (ev) {
            (void) ngx_connection_error(c, ev->kq_errno,
                                        "kevent() reported that connect() "
                                        "failed");
            return ev->kq_errno;
        }

    } else
#endif
    {
        err = 0;
        len = sizeof(int);

        /*
         * BSDs and Linux return 0 and set a pending error in err
         * Solaris returns -1 and sets errno
         */

        if (getsockopt(c->fd, SOL_SOCKET, SO_ERROR, (void *) &err, &len)
            == -1)
        {
            err = ngx_errno;
        }

        if (err) {
            (void) ngx_connection_error(c, err, "connect() failed");
            return err;
        }
    }

    return NGX_OK;
}


static void
ngx_http_lua_socket_dummy_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket dummy handler");
}


static int
ngx_http_lua_socket_tcp_receiveuntil(lua_State *L)
{
    ngx_http_request_t                  *r;
    int                                  n;
    ngx_str_t                            pat;
    ngx_int_t                            rc;
    size_t                               size;
    unsigned                             inclusive = 0;

    ngx_http_lua_socket_compiled_pattern_t     *cp;

    n = lua_gettop(L);
    if (n != 2 && n != 3) {
        return luaL_error(L, "expecting 2 or 3 arguments "
                          "(including the object), but got %d", n);
    }

    if (n == 3) {
        /* check out the options table */

        luaL_checktype(L, 3, LUA_TTABLE);

        lua_getfield(L, 3, "inclusive");

        switch (lua_type(L, -1)) {
            case LUA_TNIL:
                /* do nothing */
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, -1)) {
                    inclusive = 1;
                }
                break;

            default:
                return luaL_error(L, "bad \"inclusive\" option value type: %s",
                                  luaL_typename(L, -1));

        }

        lua_pop(L, 2);
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket calling receiveuntil() method");

    luaL_checktype(L, 1, LUA_TTABLE);

    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);
    if (pat.len == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "pattern is empty");
        return 2;
    }

    size = sizeof(ngx_http_lua_socket_compiled_pattern_t);

    cp = lua_newuserdata(L, size);
    if (cp == NULL) {
        return luaL_error(L, "out of memory");
    }

    lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
    lua_pushcfunction(L, ngx_http_lua_socket_cleanup_compiled_pattern);
    lua_setfield(L, -2, "__gc");
    lua_setmetatable(L, -2);

    ngx_memzero(cp, size);

    cp->inclusive = inclusive;

    rc = ngx_http_lua_socket_compile_pattern(pat.data, pat.len, cp,
                                             r->connection->log);

    if (rc != NGX_OK) {
        lua_pushnil(L);
        lua_pushliteral(L, "failed to compile pattern");
        return 2;
    }

    lua_pushcclosure(L, ngx_http_lua_socket_receiveuntil_iterator, 3);
    return 1;
}


static int
ngx_http_lua_socket_receiveuntil_iterator(lua_State *L)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_tcp_upstream_t  *u;
    ngx_int_t                            rc;
    ngx_http_lua_ctx_t                  *ctx;
    lua_Integer                          bytes;
    int                                  n;
    ngx_http_lua_co_ctx_t               *coctx;

    ngx_http_lua_socket_compiled_pattern_t     *cp;

    n = lua_gettop(L);
    if (n > 1) {
        return luaL_error(L, "expecting 0 or 1 arguments, "
                          "but seen %d", n);
    }

    if (n >= 1) {
        bytes = luaL_checkinteger(L, 1);
        if (bytes < 0) {
            bytes = 0;
        }

    } else {
        bytes = 0;
    }

    lua_rawgeti(L, lua_upvalueindex(1), SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->waiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "socket busy");
        return 2;
    }

    r = u->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket receiveuntil iterator");

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket read timeout: %M", u->read_timeout);

    u->input_filter = ngx_http_lua_socket_read_until;

    cp = lua_touserdata(L, lua_upvalueindex(3));

    dd("checking existing state: %d", cp->state);

    if (cp->state == -1) {
        cp->state = 0;

        lua_pushnil(L);
        lua_pushnil(L);
        lua_pushnil(L);
        return 3;
    }

    cp->upstream = u;

    cp->pattern.data =
        (u_char *) lua_tolstring(L, lua_upvalueindex(2),
                                 &cp->pattern.len);

    u->input_filter_ctx = cp;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (u->bufs_in == NULL) {
        u->bufs_in =
            ngx_http_lua_chains_get_free_buf(r->connection->log, r->pool,
                                             &ctx->free_recv_bufs,
                                             u->conf->buffer_size,
                                             (ngx_buf_tag_t)
                                             &ngx_http_lua_module);

        if (u->bufs_in == NULL) {
            return luaL_error(L, "out of memory");
        }

        u->buf_in = u->bufs_in;
        u->buffer = *u->buf_in->buf;
    }

    u->length = (size_t) bytes;
    u->rest = u->length;

    if (u->is_downstream) {
        r->read_event_handler = ngx_http_lua_req_socket_rev_handler;
    }

    u->waiting = 0;

    rc = ngx_http_lua_socket_tcp_read(r, u);

    if (rc == NGX_ERROR) {
        dd("read failed: %d", (int) u->ft_type);
        rc = ngx_http_lua_socket_tcp_receive_retval_handler(r, u, L);
        dd("tcp receive retval returned: %d", (int) rc);
        return rc;
    }

    if (rc == NGX_OK) {

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket receive done in a single run");

        return ngx_http_lua_socket_tcp_receive_retval_handler(r, u, L);
    }

    /* rc == NGX_AGAIN */

    u->read_event_handler = ngx_http_lua_socket_read_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    ctx->cur_co_ctx->cleanup = ngx_http_lua_tcp_socket_cleanup;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    u->co_ctx = ctx->cur_co_ctx;
    u->waiting = 1;
    u->prepare_retvals = ngx_http_lua_socket_tcp_receive_retval_handler;

    coctx = ctx->cur_co_ctx;

    dd("setting data to %p", u);

    coctx->data = u;

    if (u->is_downstream) {
        ctx->req_body_reader_co_ctx = coctx;
    }

    return lua_yield(L, 0);
}


static ngx_int_t
ngx_http_lua_socket_compile_pattern(u_char *data, size_t len,
    ngx_http_lua_socket_compiled_pattern_t *cp, ngx_log_t *log)
{
    size_t              i;
    size_t              prefix_len;
    size_t              size;
    unsigned            found;
    int                 cur_state, new_state;

    ngx_http_lua_dfa_edge_t         *edge;
    ngx_http_lua_dfa_edge_t        **last;

    cp->pattern.len = len;

    if (len <= 2) {
        return NGX_OK;
    }

    for (i = 1; i < len; i++) {
        prefix_len = 1;

        while (prefix_len <= len - i - 1) {

            if (ngx_memcmp(data, &data[i], prefix_len) == 0) {
                if (data[prefix_len] == data[i + prefix_len]) {
                    prefix_len++;
                    continue;
                }

                cur_state = i + prefix_len;
                new_state = prefix_len + 1;

                if (cp->recovering == NULL) {
                    size = sizeof(void *) * (len - 2);
                    cp->recovering = ngx_alloc(size, log);
                    if (cp->recovering == NULL) {
                        return NGX_ERROR;
                    }

                    ngx_memzero(cp->recovering, size);
                }

                edge = cp->recovering[cur_state - 2];

                found = 0;

                if (edge == NULL) {
                    last = &cp->recovering[cur_state - 2];

                } else {

                    for (; edge; edge = edge->next) {
                        last = &edge->next;

                        if (edge->chr == data[prefix_len]) {
                            found = 1;

                            if (edge->new_state < new_state) {
                                edge->new_state = new_state;
                            }

                            break;
                        }
                    }
                }

                if (!found) {
                    ngx_log_debug7(NGX_LOG_DEBUG_HTTP, log, 0,
                                   "lua tcp socket read until recovering point:"
                                   " on state %d (%*s), if next is '%c', then "
                                   "recover to state %d (%*s)", cur_state,
                                   (size_t) cur_state, data, data[prefix_len],
                                   new_state, (size_t) new_state, data);

                    edge = ngx_alloc(sizeof(ngx_http_lua_dfa_edge_t), log);
                    edge->chr = data[prefix_len];
                    edge->new_state = new_state;
                    edge->next = NULL;

                    *last = edge;
                }

                break;
            }

            break;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_socket_read_until(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_compiled_pattern_t     *cp = data;

    ngx_http_lua_socket_tcp_upstream_t      *u;
    ngx_http_request_t                      *r;
    ngx_buf_t                               *b;
    u_char                                   c;
    u_char                                  *pat;
    size_t                                   pat_len;
    int                                      i;
    int                                      state;
    int                                      old_state = 0; /* just to make old
                                                               gcc happy */
    ngx_http_lua_dfa_edge_t                 *edge;
    unsigned                                 matched;
    ngx_int_t                                rc;

    u = cp->upstream;
    r = u->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket read until");

    if (bytes == 0) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    b = &u->buffer;

    pat = cp->pattern.data;
    pat_len = cp->pattern.len;
    state = cp->state;

    i = 0;
    while (i < bytes) {
        c = b->pos[i];

        dd("%d: read char %d, state: %d", i, c, state);

        if (c == pat[state]) {
            i++;
            state++;

            if (state == (int) pat_len) {
                /* already matched the whole pattern */
                dd("pat len: %d", (int) pat_len);

                b->pos += i;

                if (u->length) {
                    cp->state = -1;

                } else {
                    cp->state = 0;
                }

                if (cp->inclusive) {
                    rc = ngx_http_lua_socket_add_pending_data(r, u, b->pos, 0,
                                                              pat, state,
                                                              state);

                    if (rc != NGX_OK) {
                        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
                        return NGX_ERROR;
                    }
                }

                return NGX_OK;
            }

            continue;
        }

        if (state == 0) {
            u->buf_in->buf->last++;

            i++;

            if (u->length && --u->rest == 0) {
                cp->state = state;
                b->pos += i;
                return NGX_OK;
            }

            continue;
        }

        matched = 0;

        if (cp->recovering && state >= 2) {
            dd("accessing state: %d, index: %d", state, state - 2);
            for (edge = cp->recovering[state - 2]; edge; edge = edge->next) {

                if (edge->chr == c) {
                    dd("matched '%c' and jumping to state %d", c,
                       edge->new_state);

                    old_state = state;
                    state = edge->new_state;
                    matched = 1;
                    break;
                }
            }
        }

        if (!matched) {
#if 1
            dd("adding pending data: %.*s", state, pat);
            rc = ngx_http_lua_socket_add_pending_data(r, u, b->pos, i, pat,
                                                      state, state);

            if (rc != NGX_OK) {
                u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
                return NGX_ERROR;
            }

#endif

            if (u->length) {
                if (u->rest <= (size_t) state) {
                    u->rest = 0;
                    cp->state = 0;
                    b->pos += i;
                    return NGX_OK;

                } else {
                    u->rest -= state;
                }
            }

            state = 0;
            continue;
        }

        /* matched */

        dd("adding pending data: %.*s", (int) (old_state + 1 - state),
           (char *) pat);

        rc = ngx_http_lua_socket_add_pending_data(r, u, b->pos, i, pat,
                                                  old_state + 1 - state,
                                                  old_state);

        if (rc != NGX_OK) {
            u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
            return NGX_ERROR;
        }

        i++;

        if (u->length) {
            if (u->rest <= (size_t) state) {
                u->rest = 0;
                cp->state = state;
                b->pos += i;
                return NGX_OK;

            } else {
                u->rest -= state;
            }
        }

        continue;
    }

    b->pos += i;
    cp->state = state;

    return NGX_AGAIN;
}


static int
ngx_http_lua_socket_cleanup_compiled_pattern(lua_State *L)
{
    ngx_http_lua_socket_compiled_pattern_t      *cp;

    ngx_http_lua_dfa_edge_t         *edge, *p;
    unsigned                         i;

    dd("cleanup compiled pattern");

    cp = lua_touserdata(L, 1);
    if (cp == NULL || cp->recovering == NULL) {
        return 0;
    }

    dd("pattern len: %d", (int) cp->pattern.len);

    for (i = 0; i < cp->pattern.len - 2; i++) {
        edge = cp->recovering[i];

        while (edge) {
            p = edge;
            edge = edge->next;

            dd("freeing edge %p", p);

            ngx_free(p);

            dd("edge: %p", edge);
        }
    }

#if 1
    ngx_free(cp->recovering);
    cp->recovering = NULL;
#endif

    return 0;
}


static int
ngx_http_lua_req_socket(lua_State *L)
{
    ngx_peer_connection_t           *pc;
    ngx_http_lua_loc_conf_t         *llcf;
    ngx_connection_t                *c;
    ngx_http_request_t              *r;
    ngx_http_lua_ctx_t              *ctx;
    ngx_http_request_body_t         *rb;
    ngx_http_cleanup_t              *cln;
    ngx_http_lua_co_ctx_t           *coctx;

    ngx_http_lua_socket_tcp_upstream_t  *u;

    if (lua_gettop(L) != 0) {
        return luaL_error(L, "expecting zero arguments, but got %d",
                lua_gettop(L));
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r != r->main) {
        return luaL_error(L, "attempt to read the request body in a "
                          "subrequest");
    }

#if nginx_version >= 1003009
    if (r->headers_in.chunked) {
        lua_pushnil(L);
        lua_pushliteral(L, "chunked request bodies not supported yet");
        return 2;
    }
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    if (r->request_body) {
        lua_pushnil(L);
        lua_pushliteral(L, "request body already exists");
        return 2;
    }

    if (r->discard_body) {
        lua_pushnil(L);
        lua_pushliteral(L, "request body discarded");
        return 2;
    }

    dd("req content length: %d", (int) r->headers_in.content_length_n);

    if (r->headers_in.content_length_n <= 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "no body");
        return 2;
    }

    if (ngx_http_lua_test_expect(r) != NGX_OK) {
        lua_pushnil(L);
        lua_pushliteral(L, "test expect failed");
        return 2;
    }

    /* prevent other request body reader from running */

    rb = ngx_pcalloc(r->pool, sizeof(ngx_http_request_body_t));
    if (rb == NULL) {
        return luaL_error(L, "out of memory");
    }

    rb->rest = r->headers_in.content_length_n;

    r->request_body = rb;

    lua_createtable(L, 3 /* narr */, 1 /* nrec */); /* the object */

    lua_pushlightuserdata(L, &ngx_http_lua_req_socket_metatable_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    u = lua_newuserdata(L, sizeof(ngx_http_lua_socket_tcp_upstream_t));
    if (u == NULL) {
        return luaL_error(L, "out of memory");
    }

#if 1
    lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
    lua_pushcfunction(L, ngx_http_lua_socket_downstream_destroy);
    lua_setfield(L, -2, "__gc");
    lua_setmetatable(L, -2);
#endif

    lua_rawseti(L, 1, SOCKET_CTX_INDEX);

    ngx_memzero(u, sizeof(ngx_http_lua_socket_tcp_upstream_t));

    u->is_downstream = 1;

    coctx = ctx->cur_co_ctx;

    u->request = r;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    u->conf = llcf;

    u->read_timeout = u->conf->read_timeout;
    u->connect_timeout = u->conf->connect_timeout;
    u->send_timeout = u->conf->send_timeout;

    cln = ngx_http_cleanup_add(r, 0);
    if (cln == NULL) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
        lua_pushnil(L);
        lua_pushliteral(L, "out of memory");
        return 2;
    }

    cln->handler = ngx_http_lua_req_socket_cleanup;
    cln->data = u;
    u->cleanup = &cln->handler;

    pc = &u->peer;

    pc->log = r->connection->log;
    pc->log_error = NGX_ERROR_ERR;

    c = r->connection;
    pc->connection = c;

    dd("setting data to %p", u);

    coctx->data = u;
    ctx->req_body_reader_co_ctx = coctx;

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    lua_settop(L, 1);
    lua_pushnil(L);
    return 2;
}


static void
ngx_http_lua_req_socket_rev_handler(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t                  *ctx;
    ngx_http_lua_co_ctx_t               *coctx;
    ngx_http_lua_socket_tcp_upstream_t  *u;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua request socket read event handler");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return;
    }

    coctx = ctx->req_body_reader_co_ctx;
    u = coctx->data;

    if (u) {
        u->read_event_handler(r, u);
    }
}


static int
ngx_http_lua_socket_tcp_getreusedtimes(lua_State *L)
{
    ngx_http_lua_socket_tcp_upstream_t    *u;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting 1 argument "
                          "(including the object), but got %d", lua_gettop(L));
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    lua_pushinteger(L, u->reused);
    return 1;
}


static int ngx_http_lua_socket_tcp_setkeepalive(lua_State *L)
{
    ngx_http_lua_main_conf_t            *lmcf;
    ngx_http_lua_loc_conf_t             *llcf;
    ngx_http_lua_socket_tcp_upstream_t  *u;
    ngx_connection_t                    *c;
    ngx_http_lua_socket_pool_t          *spool;
    size_t                               size;
    ngx_str_t                            key;
    ngx_uint_t                           i;
    ngx_queue_t                         *q;
    ngx_peer_connection_t               *pc;
    u_char                              *p;
    ngx_http_request_t                  *r;
    ngx_msec_t                           timeout;
    ngx_uint_t                           pool_size;
    int                                  n;
    ngx_int_t                            rc;
    ngx_buf_t                           *b;

    ngx_http_lua_socket_pool_item_t     *items, *item;

    n = lua_gettop(L);

    if (n < 1 || n > 3) {
        return luaL_error(L, "expecting 1 to 3 arguments "
                          "(including the object), but got %d", n);
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_pushlightuserdata(L, &ngx_http_lua_socket_pool_key);
    lua_rawget(L, LUA_REGISTRYINDEX);

    lua_rawgeti(L, 1, SOCKET_KEY_INDEX);
    key.data = (u_char *) lua_tolstring(L, -1, &key.len);
    if (key.data == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "key not found");
        return 2;
    }

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    /* stack: obj cache key */

    pc = &u->peer;
    c = pc->connection;

    if (u == NULL || c == NULL || u->ft_type || u->eof) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->waiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "socket busy");
        return 2;
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    b = &u->buffer;

    if (b->start && ngx_buf_size(b)) {
        ngx_http_lua_probe_socket_tcp_setkeepalive_buf_unread(r, u, b->pos,
                                                              b->last - b->pos);

        lua_pushnil(L);
        lua_pushliteral(L, "unread data in buffer");
        return 2;
    }

    if (c->read->eof
        || c->read->error
        || c->read->timedout
        || c->write->error
        || c->write->timedout)
    {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid connection");
        return 2;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        lua_pushnil(L);
        lua_pushliteral(L, "failed to handle read event");
        return 2;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua tcp socket set keepalive: saving connection %p", c);

    dd("saving connection to key %s", lua_tostring(L, -1));

    lua_pushvalue(L, -1);
    lua_rawget(L, -3);
    spool = lua_touserdata(L, -1);
    lua_pop(L, 1);

    /* stack: obj timeout? size? cache key */

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (spool == NULL) {
        /* create a new socket pool for the current peer key */

        if (n == 3) {
            pool_size = luaL_checkinteger(L, 3);

        } else {
            pool_size = llcf->pool_size;
        }

        if (pool_size == 0) {
            lua_pushnil(L);
            lua_pushliteral(L, "zero pool size");
            return 2;
        }

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket connection pool size: %ui", pool_size);

        size = sizeof(ngx_http_lua_socket_pool_t) + key.len
               + sizeof(ngx_http_lua_socket_pool_item_t)
               * pool_size;

        spool = lua_newuserdata(L, size);
        if (spool == NULL) {
            return luaL_error(L, "out of memory");
        }

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "lua tcp socket keepalive create connection pool for key"
                       " \"%s\"", lua_tostring(L, -2));

        lua_rawset(L, -3);

        lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

        spool->conf = lmcf;
        spool->active_connections = 0;

        ngx_queue_init(&spool->cache);
        ngx_queue_init(&spool->free);

        p = ngx_copy(spool->key, key.data, key.len);
        *p++ = '\0';

        items = (ngx_http_lua_socket_pool_item_t *) p;

        for (i = 0; i < pool_size; i++) {
            ngx_queue_insert_head(&spool->free, &items[i].queue);
            items[i].socket_pool = spool;
        }
    }

    if (ngx_queue_empty(&spool->free)) {

        q = ngx_queue_last(&spool->cache);
        ngx_queue_remove(q);
        spool->active_connections--;

        item = ngx_queue_data(q, ngx_http_lua_socket_pool_item_t, queue);

        ngx_close_connection(item->connection);

    } else {
        q = ngx_queue_head(&spool->free);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_lua_socket_pool_item_t, queue);
    }

    item->connection = c;
    ngx_queue_insert_head(&spool->cache, q);

    if (!u->reused) {
        spool->active_connections++;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua tcp socket clear current socket connection");

    pc->connection = NULL;

#if 0
    if (u->cleanup) {
        *u->cleanup = NULL;
        u->cleanup = NULL;
    }
#endif

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    if (n >= 2) {
        timeout = (ngx_msec_t) luaL_checkinteger(L, 2);

    } else {
        timeout = llcf->keepalive_timeout;
    }

#if (NGX_DEBUG)
    if (timeout == 0) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket keepalive timeout: unlimited");
    }
#endif

    if (timeout) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket keepalive timeout: %M ms", timeout);

        ngx_add_timer(c->read, timeout);
    }

    c->write->handler = ngx_http_lua_socket_keepalive_dummy_handler;
    c->read->handler = ngx_http_lua_socket_keepalive_rev_handler;

    c->data = item;
    c->idle = 1;
    c->log = ngx_cycle->log;
    c->read->log = ngx_cycle->log;
    c->write->log = ngx_cycle->log;

    item->socklen = pc->socklen;
    ngx_memcpy(&item->sockaddr, pc->sockaddr, pc->socklen);
    item->reused = u->reused;

    if (c->read->ready) {
        rc = ngx_http_lua_socket_keepalive_close_handler(c->read);
        if (rc != NGX_OK) {
            lua_pushnil(L);
            lua_pushliteral(L, "connection in dubious state");
            return 2;
        }
    }

#if 1
    ngx_http_lua_socket_tcp_finalize(r, u);
#endif

    lua_pushinteger(L, 1);
    return 1;
}


static ngx_int_t
ngx_http_lua_get_keepalive_peer(ngx_http_request_t *r, lua_State *L,
    int key_index, ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_http_lua_socket_pool_item_t     *item;
    ngx_http_lua_socket_pool_t          *spool;
    ngx_http_cleanup_t                  *cln;
    ngx_queue_t                         *q;
    int                                  top;
    ngx_peer_connection_t               *pc;
    ngx_connection_t                    *c;

    top = lua_gettop(L);

    if (key_index < 0) {
        key_index = top + key_index + 1;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket pool get keepalive peer");

    pc = &u->peer;

    lua_pushlightuserdata(L, &ngx_http_lua_socket_pool_key);
    lua_rawget(L, LUA_REGISTRYINDEX); /* table */
    lua_pushvalue(L, key_index); /* key */
    lua_rawget(L, -2);

    spool = lua_touserdata(L, -1);
    if (spool == NULL) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "lua tcp socket keepalive connection pool not found");
        lua_settop(L, top);
        return NGX_DECLINED;
    }

    u->socket_pool = spool;

    if (!ngx_queue_empty(&spool->cache)) {
        q = ngx_queue_head(&spool->cache);

        item = ngx_queue_data(q, ngx_http_lua_socket_pool_item_t, queue);
        c = item->connection;

        ngx_queue_remove(q);
        ngx_queue_insert_head(&spool->free, q);

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "lua tcp socket get keepalive peer: using connection %p,"
                       " fd:%d", c, c->fd);

        c->idle = 0;
        c->log = pc->log;
        c->read->log = pc->log;
        c->write->log = pc->log;
        c->data = u;

#if 1
        c->write->handler = ngx_http_lua_socket_tcp_handler;
        c->read->handler = ngx_http_lua_socket_tcp_handler;
#endif

        if (c->read->timer_set) {
            ngx_del_timer(c->read);
        }

        pc->connection = c;
        pc->cached = 1;

        u->reused = item->reused + 1;

#if 1
        u->write_event_handler = ngx_http_lua_socket_dummy_handler;
        u->read_event_handler = ngx_http_lua_socket_dummy_handler;
#endif

        if (u->cleanup == NULL) {
            cln = ngx_http_cleanup_add(r, 0);
            if (cln == NULL) {
                u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
                lua_settop(L, top);
                return NGX_ERROR;
            }

            cln->handler = ngx_http_lua_socket_tcp_cleanup;
            cln->data = u;
            u->cleanup = &cln->handler;
        }

        lua_settop(L, top);

        return NGX_OK;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua tcp socket keepalive: connection pool empty");

    lua_settop(L, top);

    return NGX_DECLINED;
}


static void
ngx_http_lua_socket_keepalive_dummy_handler(ngx_event_t *ev)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "keepalive dummy handler");
}


static void
ngx_http_lua_socket_keepalive_rev_handler(ngx_event_t *ev)
{
    (void) ngx_http_lua_socket_keepalive_close_handler(ev);
}


static ngx_int_t
ngx_http_lua_socket_keepalive_close_handler(ngx_event_t *ev)
{
    ngx_http_lua_socket_pool_item_t     *item;
    ngx_http_lua_socket_pool_t          *spool;

    int                n;
    char               buf[1];
    ngx_connection_t  *c;

    c = ev->data;

    if (c->close) {
        goto close;
    }

    if (c->read->timedout) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                       "lua tcp socket keepalive max idle timeout");

        goto close;
    }

    dd("read event ready: %d", (int) c->read->ready);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "lua tcp socket keepalive close handler check stale events");

    n = recv(c->fd, buf, 1, MSG_PEEK);

    if (n == -1 && ngx_socket_errno == NGX_EAGAIN) {
        /* stale event */

        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            goto close;
        }

        return NGX_OK;
    }

close:

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "lua tcp socket keepalive close handler: fd:%d", c->fd);

    item = c->data;
    spool = item->socket_pool;

    ngx_close_connection(c);

    ngx_queue_remove(&item->queue);
    ngx_queue_insert_head(&spool->free, &item->queue);
    spool->active_connections--;

    dd("keepalive: active connections: %u",
       (unsigned) spool->active_connections);

    if (spool->active_connections == 0) {
        ngx_http_lua_socket_free_pool(ev->log, spool);
    }

    return NGX_DECLINED;
}


static void
ngx_http_lua_socket_free_pool(ngx_log_t *log, ngx_http_lua_socket_pool_t *spool)
{
    lua_State                           *L;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                   "lua tcp socket keepalive: free connection pool for \"%s\"",
                   spool->key);

    L = spool->conf->lua;

    lua_pushlightuserdata(L, &ngx_http_lua_socket_pool_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushstring(L, (char *) spool->key);
    lua_pushnil(L);
    lua_rawset(L, -3);
    lua_pop(L, 1);
}


static int
ngx_http_lua_socket_tcp_upstream_destroy(lua_State *L)
{
    ngx_http_lua_socket_tcp_upstream_t      *u;

    dd("upstream destroy triggered by Lua GC");

    u = lua_touserdata(L, 1);
    if (u == NULL) {
        return 0;
    }

    if (u->cleanup) {
        ngx_http_lua_socket_tcp_cleanup(u); /* it will clear u->cleanup */
    }

    return 0;
}


static int
ngx_http_lua_socket_downstream_destroy(lua_State *L)
{
    ngx_http_lua_socket_tcp_upstream_t     *u;

    dd("upstream destroy triggered by Lua GC");

    u = lua_touserdata(L, 1);
    if (u == NULL) {
        return 0;
    }

    if (u->cleanup) {
        ngx_http_lua_req_socket_cleanup(u); /* it will clear u->cleanup */
    }

    return 0;
}


static void
ngx_http_lua_req_socket_cleanup(void *data)
{
    ngx_http_lua_socket_tcp_upstream_t  *u = data;

#if (NGX_DEBUG)
    ngx_http_request_t  *r;

    r = u->request;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "cleanup lua tcp socket downstream request: \"%V\"",
                   &r->uri);
#endif

    if (u->cleanup) {
        *u->cleanup = NULL;
        u->cleanup = NULL;
    }

    if (u->peer.connection) {
        u->peer.connection = NULL;
    }
}


static ngx_int_t
ngx_http_lua_socket_push_input_data(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_http_lua_socket_tcp_upstream_t *u,
    lua_State *L)
{
    ngx_chain_t             *cl;
    ngx_chain_t            **ll;
    size_t                   size;
    ngx_buf_t               *b;
    size_t                   nbufs;
    u_char                  *p;
    u_char                  *last;

    if (!u->bufs_in) {
        lua_pushliteral(L, "");
        ngx_http_lua_probe_socket_tcp_receive_done(r, u, (u_char *) "", 0);
        return NGX_OK;
    }

    dd("bufs_in: %p, buf_in: %p", u->bufs_in, u->buf_in);

    size = 0;
    nbufs = 0;
    ll = NULL;

    for (cl = u->bufs_in; cl; cl = cl->next) {
        b = cl->buf;
        size += b->last - b->pos;

        if (cl->next) {
            ll = &cl->next;
        }

        nbufs++;
    }

    dd("size: %d, nbufs: %d", (int) size, (int) nbufs);

    if (size == 0) {
        lua_pushliteral(L, "");

        ngx_http_lua_probe_socket_tcp_receive_done(r, u, (u_char *) "", 0);

        goto done;
    }

    if (nbufs == 1) {
        b = u->buf_in->buf;

        lua_pushlstring(L, (char *) b->pos, size);

        dd("copying input data chunk from %p: \"%.*s\"", u->buf_in, (int) size,
                b->pos);

        ngx_http_lua_probe_socket_tcp_receive_done(r, u, b->pos, size);

        goto done;
    }

    /* nbufs > 1 */

    dd("WARN: allocate a big memory: %d", (int) size);

    p = ngx_palloc(r->pool, size);
    if (p == NULL) {
        return NGX_ERROR;
    }

    last = p;
    for (cl = u->bufs_in; cl; cl = cl->next) {
        b = cl->buf;
        last = ngx_copy(last, b->pos, b->last - b->pos);

        dd("copying input data chunk from %p: \"%.*s\"", cl,
           (int) (b->last - b->pos), b->pos);
    }

    lua_pushlstring(L, (char *) p, size);

    ngx_http_lua_probe_socket_tcp_receive_done(r, u, p, size);

    ngx_pfree(r->pool, p);

done:
    if (nbufs > 1 && ll) {
        dd("recycle buffers: %d", (int) (nbufs - 1));

        *ll = ctx->free_recv_bufs;
        ctx->free_recv_bufs = u->bufs_in;
        u->bufs_in = u->buf_in;
    }

    if (u->buffer.pos == u->buffer.last) {
        dd("resetting u->buffer pos & last");
        u->buffer.pos = u->buffer.start;
        u->buffer.last = u->buffer.start;
    }

    u->buf_in->buf->last = u->buffer.pos;
    u->buf_in->buf->pos = u->buffer.pos;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_socket_add_input_buffer(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_chain_t             *cl;
    ngx_http_lua_ctx_t      *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    cl = ngx_http_lua_chains_get_free_buf(r->connection->log, r->pool,
                                          &ctx->free_recv_bufs,
                                          u->conf->buffer_size,
                                          (ngx_buf_tag_t)
                                          &ngx_http_lua_module);

    if (cl == NULL) {
        return NGX_ERROR;
    }

    u->buf_in->next = cl;
    u->buf_in = cl;
    u->buffer = *cl->buf;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_socket_add_pending_data(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, u_char *pos, size_t len, u_char *pat,
    int prefix, int old_state)
{
    u_char          *last;
    ngx_buf_t       *b;

    dd("resuming data: %d: [%.*s]", prefix, prefix, pat);

    last = &pos[len];

    b = u->buf_in->buf;

    if (last - b->last == old_state) {
        b->last += prefix;
        return NGX_OK;
    }

    dd("need more buffers because %d != %d", (int) (last - b->last),
       (int) old_state);

    if (ngx_http_lua_socket_insert_buffer(r, u, pat, prefix) != NGX_OK) {
        return NGX_ERROR;
    }

    b->pos = last;
    b->last = last;

    return NGX_OK;
}


static ngx_int_t ngx_http_lua_socket_insert_buffer(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, u_char *pat, size_t prefix)
{
    ngx_chain_t             *cl, *new_cl, **ll;
    ngx_http_lua_ctx_t      *ctx;
    size_t                   size;
    ngx_buf_t               *b;

    if (prefix <= u->conf->buffer_size) {
        size = u->conf->buffer_size;

    } else {
        size = prefix;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    new_cl = ngx_http_lua_chains_get_free_buf(r->connection->log, r->pool,
                                              &ctx->free_recv_bufs,
                                              size,
                                              (ngx_buf_tag_t)
                                              &ngx_http_lua_module);

    if (new_cl == NULL) {
        return NGX_ERROR;
    }

    b = new_cl->buf;

    b->last = ngx_copy(b->last, pat, prefix);

    dd("copy resumed data to %p: %d: \"%.*s\"",
       new_cl, (int) (b->last - b->pos), (int) (b->last - b->pos), b->pos);

    dd("before resuming data: bufs_in %p, buf_in %p, buf_in next %p",
       u->bufs_in, u->buf_in, u->buf_in->next);

    ll = &u->bufs_in;
    for (cl = u->bufs_in; cl->next; cl = cl->next) {
        ll = &cl->next;
    }

    *ll = new_cl;
    new_cl->next = u->buf_in;

    dd("after resuming data: bufs_in %p, buf_in %p, buf_in next %p",
       u->bufs_in, u->buf_in, u->buf_in->next);

#if (DDEBUG)
    for (cl = u->bufs_in; cl; cl = cl->next) {
        b = cl->buf;

        dd("result buf after resuming data: %p: %.*s", cl,
           (int) ngx_buf_size(b), b->pos);
    }
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_socket_tcp_resume(ngx_http_request_t *r)
{
    int                          nret;
    ngx_int_t                    rc;
    ngx_connection_t            *c;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;
    ngx_http_lua_main_conf_t    *lmcf;

    ngx_http_lua_socket_tcp_upstream_t      *u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp operation done, resuming lua thread");

    coctx = ctx->cur_co_ctx;

#if 0
    ngx_http_lua_probe_info("tcp resume");
#endif

    dd("coctx: %p", coctx);

    u = coctx->data;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket calling prepare retvals handler %p, "
                   "u:%p", u->prepare_retvals, u);

    nret = u->prepare_retvals(r, u, ctx->cur_co_ctx->co);
    if (nret == NGX_AGAIN) {
        return NGX_DONE;
    }

    c = r->connection;

    rc = ngx_http_lua_run_thread(lmcf->lua, r, ctx, nret);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, lmcf->lua, r, ctx);
    }

    if (rc == NGX_DONE) {
        ngx_http_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c,lmcf->lua, r, ctx);
    }

    if (ctx->entered_content_phase) {
        ngx_http_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static void
ngx_http_lua_tcp_resolve_cleanup(void *data)
{
    ngx_resolver_ctx_t                      *rctx;
    ngx_http_lua_socket_tcp_upstream_t      *u;
    ngx_http_lua_co_ctx_t                   *coctx = data;

    u = coctx->data;
    if (u == NULL) {
        return;
    }

    rctx = u->resolved->ctx;
    if (rctx == NULL) {
        return;
    }

    ngx_resolve_name_done(rctx);
}


static void
ngx_http_lua_tcp_socket_cleanup(void *data)
{
    ngx_http_lua_socket_tcp_upstream_t      *u;
    ngx_http_lua_co_ctx_t                   *coctx = data;

    u = coctx->data;
    if (u == NULL) {
        return;
    }

    if (u->request == NULL) {
        return;
    }

    ngx_http_lua_socket_tcp_finalize(u->request, u);
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
