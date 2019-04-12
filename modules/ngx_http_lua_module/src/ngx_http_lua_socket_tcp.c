
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_socket_tcp.h"
#include "ngx_http_lua_input_filters.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_uthread.h"
#include "ngx_http_lua_output.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_probe.h"


static int ngx_http_lua_socket_tcp(lua_State *L);
static int ngx_http_lua_socket_tcp_connect(lua_State *L);
#if (NGX_HTTP_SSL)
static int ngx_http_lua_socket_tcp_sslhandshake(lua_State *L);
#endif
static int ngx_http_lua_socket_tcp_receive(lua_State *L);
static int ngx_http_lua_socket_tcp_receiveany(lua_State *L);
static int ngx_http_lua_socket_tcp_send(lua_State *L);
static int ngx_http_lua_socket_tcp_close(lua_State *L);
static int ngx_http_lua_socket_tcp_setoption(lua_State *L);
static int ngx_http_lua_socket_tcp_settimeout(lua_State *L);
static int ngx_http_lua_socket_tcp_settimeouts(lua_State *L);
static void ngx_http_lua_socket_tcp_handler(ngx_event_t *ev);
static ngx_int_t ngx_http_lua_socket_tcp_get_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_lua_socket_init_peer_connection_addr_text(
    ngx_peer_connection_t *pc);
static void ngx_http_lua_socket_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_send_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_connected_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_tcp_cleanup(void *data);
static void ngx_http_lua_socket_tcp_finalize(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_tcp_finalize_read_part(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_tcp_finalize_write_part(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_send(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_test_connect(ngx_http_request_t *r,
    ngx_connection_t *c);
static void ngx_http_lua_socket_handle_conn_error(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_uint_t ft_type);
static void ngx_http_lua_socket_handle_read_error(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_uint_t ft_type);
static void ngx_http_lua_socket_handle_write_error(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_uint_t ft_type);
static void ngx_http_lua_socket_handle_conn_success(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_handle_read_success(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_handle_write_success(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static int ngx_http_lua_socket_tcp_send_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static int ngx_http_lua_socket_tcp_conn_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static void ngx_http_lua_socket_dummy_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static int ngx_http_lua_socket_tcp_receive_helper(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static ngx_int_t ngx_http_lua_socket_tcp_read(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static int ngx_http_lua_socket_tcp_receive_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static ngx_int_t ngx_http_lua_socket_read_line(void *data, ssize_t bytes);
static void ngx_http_lua_socket_resolve_handler(ngx_resolver_ctx_t *ctx);
static int ngx_http_lua_socket_resolve_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static int ngx_http_lua_socket_conn_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static int ngx_http_lua_socket_read_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static int ngx_http_lua_socket_write_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static ngx_int_t ngx_http_lua_socket_read_all(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_socket_read_until(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_socket_read_chunk(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_socket_read_any(void *data, ssize_t bytes);
static int ngx_http_lua_socket_tcp_receiveuntil(lua_State *L);
static int ngx_http_lua_socket_receiveuntil_iterator(lua_State *L);
static ngx_int_t ngx_http_lua_socket_compile_pattern(u_char *data, size_t len,
    ngx_http_lua_socket_compiled_pattern_t *cp, ngx_log_t *log);
static int ngx_http_lua_socket_cleanup_compiled_pattern(lua_State *L);
static int ngx_http_lua_req_socket(lua_State *L);
static void ngx_http_lua_req_socket_rev_handler(ngx_http_request_t *r);
static int ngx_http_lua_socket_tcp_getreusedtimes(lua_State *L);
static int ngx_http_lua_socket_tcp_setkeepalive(lua_State *L);
static void ngx_http_lua_socket_tcp_create_socket_pool(lua_State *L,
    ngx_http_request_t *r, ngx_str_t key, ngx_int_t pool_size,
    ngx_int_t backlog, ngx_http_lua_socket_pool_t **spool);
static ngx_int_t ngx_http_lua_get_keepalive_peer(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u);
static void ngx_http_lua_socket_keepalive_dummy_handler(ngx_event_t *ev);
static int ngx_http_lua_socket_tcp_connect_helper(lua_State *L,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, u_char *host_ref, size_t host_len, in_port_t port,
    unsigned resuming);
static void ngx_http_lua_socket_tcp_conn_op_timeout_handler(
    ngx_event_t *ev);
static int ngx_http_lua_socket_tcp_conn_op_timeout_retval_handler(
    ngx_http_request_t *r, ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static void ngx_http_lua_socket_tcp_resume_conn_op(
    ngx_http_lua_socket_pool_t *spool);
static void ngx_http_lua_socket_tcp_conn_op_ctx_cleanup(void *data);
static void ngx_http_lua_socket_tcp_conn_op_resume_handler(ngx_event_t *ev);
static ngx_int_t ngx_http_lua_socket_keepalive_close_handler(ngx_event_t *ev);
static void ngx_http_lua_socket_keepalive_rev_handler(ngx_event_t *ev);
static int ngx_http_lua_socket_tcp_conn_op_resume_retval_handler(
    ngx_http_request_t *r, ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
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
static ngx_int_t ngx_http_lua_socket_tcp_conn_op_resume(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_socket_tcp_conn_resume(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_socket_tcp_read_resume(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_socket_tcp_write_resume(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_socket_tcp_resume_helper(ngx_http_request_t *r,
    int socket_op);
static void ngx_http_lua_tcp_queue_conn_op_cleanup(void *data);
static void ngx_http_lua_tcp_resolve_cleanup(void *data);
static void ngx_http_lua_coctx_cleanup(void *data);
static void ngx_http_lua_socket_free_pool(ngx_log_t *log,
    ngx_http_lua_socket_pool_t *spool);
static int ngx_http_lua_socket_shutdown_pool(lua_State *L);
static void ngx_http_lua_socket_shutdown_pool_helper(
    ngx_http_lua_socket_pool_t *spool);
static void
    ngx_http_lua_socket_empty_resolve_handler(ngx_resolver_ctx_t *ctx);
static int ngx_http_lua_socket_prepare_error_retvals(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L, ngx_uint_t ft_type);
#if (NGX_HTTP_SSL)
static int ngx_http_lua_ssl_handshake_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L);
static void ngx_http_lua_ssl_handshake_handler(ngx_connection_t *c);
static int ngx_http_lua_ssl_free_session(lua_State *L);
#endif
static void ngx_http_lua_socket_tcp_close_connection(ngx_connection_t *c);


enum {
    SOCKET_CTX_INDEX = 1,
    SOCKET_KEY_INDEX = 3,
    SOCKET_CONNECT_TIMEOUT_INDEX = 2,
    SOCKET_SEND_TIMEOUT_INDEX = 4,
    SOCKET_READ_TIMEOUT_INDEX = 5,
};


enum {
    SOCKET_OP_CONNECT,
    SOCKET_OP_READ,
    SOCKET_OP_WRITE,
    SOCKET_OP_RESUME_CONN
};


#define ngx_http_lua_socket_check_busy_connecting(r, u, L)                   \
    if ((u)->conn_waiting) {                                                 \
        lua_pushnil(L);                                                      \
        lua_pushliteral(L, "socket busy connecting");                        \
        return 2;                                                            \
    }


#define ngx_http_lua_socket_check_busy_reading(r, u, L)                      \
    if ((u)->read_waiting) {                                                 \
        lua_pushnil(L);                                                      \
        lua_pushliteral(L, "socket busy reading");                           \
        return 2;                                                            \
    }


#define ngx_http_lua_socket_check_busy_writing(r, u, L)                      \
    if ((u)->write_waiting) {                                                \
        lua_pushnil(L);                                                      \
        lua_pushliteral(L, "socket busy writing");                           \
        return 2;                                                            \
    }                                                                        \
    if ((u)->raw_downstream                                                  \
        && ((r)->connection->buffered & NGX_HTTP_LOWLEVEL_BUFFERED))         \
    {                                                                        \
        lua_pushnil(L);                                                      \
        lua_pushliteral(L, "socket busy writing");                           \
        return 2;                                                            \
    }


static char ngx_http_lua_req_socket_metatable_key;
static char ngx_http_lua_raw_req_socket_metatable_key;
static char ngx_http_lua_tcp_socket_metatable_key;
static char ngx_http_lua_upstream_udata_metatable_key;
static char ngx_http_lua_downstream_udata_metatable_key;
static char ngx_http_lua_pool_udata_metatable_key;
static char ngx_http_lua_pattern_udata_metatable_key;
#if (NGX_HTTP_SSL)
static char ngx_http_lua_ssl_session_metatable_key;
#endif


void
ngx_http_lua_inject_socket_tcp_api(ngx_log_t *log, lua_State *L)
{
    ngx_int_t         rc;

    lua_createtable(L, 0, 4 /* nrec */);    /* ngx.socket */

    lua_pushcfunction(L, ngx_http_lua_socket_tcp);
    lua_pushvalue(L, -1);
    lua_setfield(L, -3, "tcp");
    lua_setfield(L, -2, "stream");

    {
        const char  buf[] = "local sock = ngx.socket.tcp()"
                            " local ok, err = sock:connect(...)"
                            " if ok then return sock else return nil, err end";

        rc = luaL_loadbuffer(L, buf, sizeof(buf) - 1, "=ngx.socket.connect");
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
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          req_socket_metatable_key));
    lua_createtable(L, 0 /* narr */, 5 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receive);
    lua_setfield(L, -2, "receive");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receiveuntil);
    lua_setfield(L, -2, "receiveuntil");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_settimeout);
    lua_setfield(L, -2, "settimeout"); /* ngx socket mt */

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_settimeouts);
    lua_setfield(L, -2, "settimeouts"); /* ngx socket mt */

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* {{{raw req socket object metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          raw_req_socket_metatable_key));
    lua_createtable(L, 0 /* narr */, 6 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receive);
    lua_setfield(L, -2, "receive");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receiveuntil);
    lua_setfield(L, -2, "receiveuntil");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_send);
    lua_setfield(L, -2, "send");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_settimeout);
    lua_setfield(L, -2, "settimeout"); /* ngx socket mt */

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_settimeouts);
    lua_setfield(L, -2, "settimeouts"); /* ngx socket mt */

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* {{{tcp object metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          tcp_socket_metatable_key));
    lua_createtable(L, 0 /* narr */, 12 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_connect);
    lua_setfield(L, -2, "connect");

#if (NGX_HTTP_SSL)

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_sslhandshake);
    lua_setfield(L, -2, "sslhandshake");

#endif

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receive);
    lua_setfield(L, -2, "receive");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receiveany);
    lua_setfield(L, -2, "receiveany");

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

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_settimeouts);
    lua_setfield(L, -2, "settimeouts"); /* ngx socket mt */

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_getreusedtimes);
    lua_setfield(L, -2, "getreusedtimes");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_setkeepalive);
    lua_setfield(L, -2, "setkeepalive");

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* {{{upstream userdata metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          upstream_udata_metatable_key));
    lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
    lua_pushcfunction(L, ngx_http_lua_socket_tcp_upstream_destroy);
    lua_setfield(L, -2, "__gc");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* {{{downstream userdata metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          downstream_udata_metatable_key));
    lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
    lua_pushcfunction(L, ngx_http_lua_socket_downstream_destroy);
    lua_setfield(L, -2, "__gc");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* {{{socket pool userdata metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          pool_udata_metatable_key));
    lua_createtable(L, 0, 1); /* metatable */
    lua_pushcfunction(L, ngx_http_lua_socket_shutdown_pool);
    lua_setfield(L, -2, "__gc");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* {{{socket compiled pattern userdata metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          pattern_udata_metatable_key));
    lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
    lua_pushcfunction(L, ngx_http_lua_socket_cleanup_compiled_pattern);
    lua_setfield(L, -2, "__gc");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

#if (NGX_HTTP_SSL)

    /* {{{ssl session userdata metatable */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          ssl_session_metatable_key));
    lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
    lua_pushcfunction(L, ngx_http_lua_ssl_free_session);
    lua_setfield(L, -2, "__gc");
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

#endif
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

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT
                               | NGX_HTTP_LUA_CONTEXT_TIMER
                               | NGX_HTTP_LUA_CONTEXT_SSL_CERT
                               | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH);

    lua_createtable(L, 5 /* narr */, 1 /* nrec */);
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          tcp_socket_metatable_key));
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    dd("top: %d", lua_gettop(L));

    return 1;
}


static void
ngx_http_lua_socket_tcp_create_socket_pool(lua_State *L, ngx_http_request_t *r,
    ngx_str_t key, ngx_int_t pool_size, ngx_int_t backlog,
    ngx_http_lua_socket_pool_t **spool)
{
    u_char                              *p;
    size_t                               size, key_len;
    ngx_int_t                            i;
    ngx_http_lua_socket_pool_t          *sp;
    ngx_http_lua_socket_pool_item_t     *items;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connection pool size: %i, backlog: %i",
                   pool_size, backlog);

    key_len = ngx_align(key.len + 1, sizeof(void *));

    size = sizeof(ngx_http_lua_socket_pool_t) - 1 + key_len
           + sizeof(ngx_http_lua_socket_pool_item_t) * pool_size;

    /* before calling this function, the Lua stack is:
     * -1 key
     * -2 pools
     */
    sp = lua_newuserdata(L, size);
    if (sp == NULL) {
        luaL_error(L, "no memory");
        return;
    }

    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          pool_udata_metatable_key));
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket keepalive create connection pool for key"
                   " \"%V\"", &key);

    /* a new socket pool with metatable is push to the stack, so now we have:
     * -1 sp
     * -2 key
     * -3 pools
     *
     * it is time to set pools[key] to sp.
     */
    lua_rawset(L, -3);

    /* clean up the stack for consistency's sake */
    lua_pop(L, 1);

    sp->backlog = backlog;
    sp->size = pool_size;
    sp->connections = 0;
    sp->lua_vm = ngx_http_lua_get_lua_vm(r, NULL);

    ngx_queue_init(&sp->cache_connect_op);
    ngx_queue_init(&sp->wait_connect_op);
    ngx_queue_init(&sp->cache);
    ngx_queue_init(&sp->free);

    p = ngx_copy(sp->key, key.data, key.len);
    *p++ = '\0';

    items = (ngx_http_lua_socket_pool_item_t *) (sp->key + key_len);

    dd("items: %p", items);

    ngx_http_lua_assert((void *) items == ngx_align_ptr(items, sizeof(void *)));

    for (i = 0; i < pool_size; i++) {
        ngx_queue_insert_head(&sp->free, &items[i].queue);
        items[i].socket_pool = sp;
    }

    *spool = sp;
}


static int
ngx_http_lua_socket_tcp_connect_helper(lua_State *L,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, u_char *host_ref, size_t host_len, in_port_t port,
    unsigned resuming)
{
    int                                    n;
    int                                    host_size;
    int                                    saved_top;
    ngx_int_t                              rc;
    ngx_str_t                              host;
    ngx_str_t                             *conn_op_host;
    ngx_url_t                              url;
    ngx_queue_t                           *q;
    ngx_resolver_ctx_t                    *rctx, temp;
    ngx_http_lua_co_ctx_t                 *coctx;
    ngx_http_core_loc_conf_t              *clcf;
    ngx_http_lua_socket_pool_t            *spool;
    ngx_http_lua_socket_tcp_conn_op_ctx_t *conn_op_ctx;

    spool = u->socket_pool;
    if (spool != NULL) {
        rc = ngx_http_lua_get_keepalive_peer(r, u);

        if (rc == NGX_OK) {
            lua_pushinteger(L, 1);
            return 1;
        }

        /* rc == NGX_DECLINED */

        spool->connections++;

        /* check if backlog is enabled and
         * don't queue resuming connection operation */
        if (spool->backlog >= 0 && !resuming) {

            dd("lua tcp socket %s connections %ld",
               spool->key, spool->connections);

            if (spool->connections > spool->size + spool->backlog) {
                spool->connections--;
                lua_pushnil(L);
                lua_pushliteral(L, "too many waiting connect operations");
                return 2;
            }

            if (spool->connections > spool->size) {
                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, u->peer.log, 0,
                               "lua tcp socket queue connect operation for "
                               "connection pool \"%s\", connections: %i",
                               spool->key, spool->connections);

                host_size = sizeof(u_char) *
                    (ngx_max(host_len, NGX_INET_ADDRSTRLEN) + 1);

                if (!ngx_queue_empty(&spool->cache_connect_op)) {
                    q = ngx_queue_last(&spool->cache_connect_op);
                    ngx_queue_remove(q);
                    conn_op_ctx = ngx_queue_data(
                        q, ngx_http_lua_socket_tcp_conn_op_ctx_t, queue);

                    conn_op_host = &conn_op_ctx->host;
                    if (host_len > conn_op_host->len
                        && host_len > NGX_INET_ADDRSTRLEN)
                    {
                        ngx_free(conn_op_host->data);
                        conn_op_host->data = ngx_alloc(host_size,
                                                       ngx_cycle->log);
                        if (conn_op_host->data == NULL) {
                            ngx_free(conn_op_ctx);
                            goto no_memory_and_not_resuming;
                        }
                    }

                } else {
                    conn_op_ctx = ngx_alloc(
                        sizeof(ngx_http_lua_socket_tcp_conn_op_ctx_t),
                        ngx_cycle->log);
                    if (conn_op_ctx == NULL) {
                        goto no_memory_and_not_resuming;
                    }

                    conn_op_host = &conn_op_ctx->host;
                    conn_op_host->data = ngx_alloc(host_size, ngx_cycle->log);
                    if (conn_op_host->data == NULL) {
                        ngx_free(conn_op_ctx);
                        goto no_memory_and_not_resuming;
                    }
                }

                conn_op_ctx->cleanup = NULL;

                ngx_memcpy(conn_op_host->data, host_ref, host_len);
                conn_op_host->data[host_len] = '\0';
                conn_op_host->len = host_len;

                conn_op_ctx->port = port;

                u->write_co_ctx = ctx->cur_co_ctx;

                conn_op_ctx->u = u;
                ctx->cur_co_ctx->cleanup =
                    ngx_http_lua_tcp_queue_conn_op_cleanup;
                ctx->cur_co_ctx->data = conn_op_ctx;

                ngx_memzero(&conn_op_ctx->event, sizeof(ngx_event_t));
                conn_op_ctx->event.handler =
                    ngx_http_lua_socket_tcp_conn_op_timeout_handler;
                conn_op_ctx->event.data = conn_op_ctx;
                conn_op_ctx->event.log = ngx_cycle->log;

                ngx_add_timer(&conn_op_ctx->event, u->connect_timeout);

                ngx_queue_insert_tail(&spool->wait_connect_op,
                                      &conn_op_ctx->queue);

                ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                               "lua tcp socket queued connect operation for "
                               "%d(ms), u: %p, ctx: %p",
                               u->connect_timeout, conn_op_ctx->u, conn_op_ctx);

                return lua_yield(L, 0);
            }
        }

    } /* end spool != NULL */

    host.data = ngx_palloc(r->pool, host_len + 1);
    if (host.data == NULL) {
        return luaL_error(L, "no memory");
    }

    host.len = host_len;

    ngx_memcpy(host.data, host_ref, host_len);
    host.data[host_len] = '\0';

    ngx_memzero(&url, sizeof(ngx_url_t));
    url.url = host;
    url.default_port = port;
    url.no_resolve = 1;

    coctx = ctx->cur_co_ctx;

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        lua_pushnil(L);

        if (url.err) {
            lua_pushfstring(L, "failed to parse host name \"%s\": %s",
                            url.url.data, url.err);

        } else {
            lua_pushfstring(L, "failed to parse host name \"%s\"",
                            url.url.data);
        }

        goto failed;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connect timeout: %M", u->connect_timeout);

    u->resolved = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_resolved_t));
    if (u->resolved == NULL) {
        if (resuming) {
            lua_pushnil(L);
            lua_pushliteral(L, "no memory");
            goto failed;
        }

        goto no_memory_and_not_resuming;
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
        u->resolved->port = url.default_port;
    }

    if (u->resolved->sockaddr) {
        rc = ngx_http_lua_socket_resolve_retval_handler(r, u, L);
        if (rc == NGX_AGAIN && !resuming) {
            return lua_yield(L, 0);
        }

        if (rc > 1) {
            goto failed;
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
        goto failed;
    }

    if (rctx == NGX_NO_RESOLVER) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;
        lua_pushnil(L);
        lua_pushfstring(L, "no resolver defined to resolve \"%s\"", host.data);
        goto failed;
    }

    rctx->name = host;
#if !defined(nginx_version) || nginx_version < 1005008
    rctx->type = NGX_RESOLVE_A;
#endif
    rctx->handler = ngx_http_lua_socket_resolve_handler;
    rctx->data = u;
    rctx->timeout = clcf->resolver_timeout;

    u->resolved->ctx = rctx;
    u->write_co_ctx = ctx->cur_co_ctx;

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_tcp_resolve_cleanup;
    coctx->data = u;

    saved_top = lua_gettop(L);

    if (ngx_resolve_name(rctx) != NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket fail to run resolver immediately");

        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;

        coctx->cleanup = NULL;
        coctx->data = NULL;

        u->resolved->ctx = NULL;
        lua_pushnil(L);
        lua_pushfstring(L, "%s could not be resolved", host.data);
        goto failed;
    }

    if (u->conn_waiting) {
        dd("resolved and already connecting");

        if (resuming) {
            return NGX_AGAIN;
        }

        return lua_yield(L, 0);
    }

    n = lua_gettop(L) - saved_top;
    if (n) {
        dd("errors occurred during resolving or connecting"
           "or already connected");

        if (n > 1) {
            goto failed;
        }

        return n;
    }

    /* still resolving */

    u->conn_waiting = 1;
    u->write_prepare_retvals = ngx_http_lua_socket_resolve_retval_handler;

    dd("setting data to %p", u);

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    if (resuming) {
        return NGX_AGAIN;
    }

    return lua_yield(L, 0);

failed:

    if (spool != NULL) {
        spool->connections--;
        ngx_http_lua_socket_tcp_resume_conn_op(spool);
    }

    return 2;

no_memory_and_not_resuming:

    if (spool != NULL) {
        spool->connections--;
        ngx_http_lua_socket_tcp_resume_conn_op(spool);
    }

    return luaL_error(L, "no memory");
}


static int
ngx_http_lua_socket_tcp_connect(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    int                          port;
    int                          n;
    u_char                      *p;
    size_t                       len;
    ngx_http_lua_loc_conf_t     *llcf;
    ngx_peer_connection_t       *pc;
    int                          connect_timeout, send_timeout, read_timeout;
    unsigned                     custom_pool;
    int                          key_index;
    ngx_int_t                    backlog;
    ngx_int_t                    pool_size;
    ngx_str_t                    key;
    const char                  *msg;

    ngx_http_lua_socket_tcp_upstream_t      *u;

    ngx_http_lua_socket_pool_t              *spool;

    n = lua_gettop(L);
    if (n != 2 && n != 3 && n != 4) {
        return luaL_error(L, "ngx.socket connect: expecting 2, 3, or 4 "
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

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT
                               | NGX_HTTP_LUA_CONTEXT_TIMER
                               | NGX_HTTP_LUA_CONTEXT_SSL_CERT
                               | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH);

    luaL_checktype(L, 1, LUA_TTABLE);

    p = (u_char *) luaL_checklstring(L, 2, &len);

    backlog = -1;
    key_index = 2;
    pool_size = 0;
    custom_pool = 0;
    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (lua_type(L, n) == LUA_TTABLE) {

        /* found the last optional option table */

        lua_getfield(L, n, "pool_size");

        if (lua_isnumber(L, -1)) {
            pool_size = (ngx_int_t) lua_tointeger(L, -1);

            if (pool_size <= 0) {
                msg = lua_pushfstring(L, "bad \"pool_size\" option value: %i",
                                      pool_size);
                return luaL_argerror(L, n, msg);
            }

        } else if (!lua_isnil(L, -1)) {
            msg = lua_pushfstring(L, "bad \"pool_size\" option type: %s",
                                  lua_typename(L, lua_type(L, -1)));
            return luaL_argerror(L, n, msg);
        }

        lua_pop(L, 1);

        lua_getfield(L, n, "backlog");

        if (lua_isnumber(L, -1)) {
            backlog = (ngx_int_t) lua_tointeger(L, -1);

            if (backlog < 0) {
                msg = lua_pushfstring(L, "bad \"backlog\" option value: %i",
                                      backlog);
                return luaL_argerror(L, n, msg);
            }

            /* use default value for pool size if only backlog specified */
            if (pool_size == 0) {
                pool_size = llcf->pool_size;
            }
        }

        lua_pop(L, 1);

        lua_getfield(L, n, "pool");

        switch (lua_type(L, -1)) {
        case LUA_TNUMBER:
            lua_tostring(L, -1);
            /* FALLTHROUGH */

        case LUA_TSTRING:
            custom_pool = 1;

            lua_pushvalue(L, -1);
            lua_rawseti(L, 1, SOCKET_KEY_INDEX);

            key_index = n + 1;

            break;

        case LUA_TNIL:
            lua_pop(L, 2);
            break;

        default:
            msg = lua_pushfstring(L, "bad \"pool\" option type: %s",
                                  luaL_typename(L, -1));
            luaL_argerror(L, n, msg);
            break;
        }

        n--;
    }

    /* the fourth argument is not a table */
    if (n == 4) {
        lua_pop(L, 1);
        n--;
    }

    if (n == 3) {
        port = luaL_checkinteger(L, 3);

        if (port < 0 || port > 65535) {
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
        if (u->request && u->request != r) {
            return luaL_error(L, "bad request");
        }

        ngx_http_lua_socket_check_busy_connecting(r, u, L);
        ngx_http_lua_socket_check_busy_reading(r, u, L);
        ngx_http_lua_socket_check_busy_writing(r, u, L);

        if (u->body_downstream || u->raw_downstream) {
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
            return luaL_error(L, "no memory");
        }

#if 1
        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              upstream_udata_metatable_key));
        lua_rawget(L, LUA_REGISTRYINDEX);
        lua_setmetatable(L, -2);
#endif

        lua_rawseti(L, 1, SOCKET_CTX_INDEX);
    }

    ngx_memzero(u, sizeof(ngx_http_lua_socket_tcp_upstream_t));

    u->request = r; /* set the controlling request */

    u->conf = llcf;

    pc = &u->peer;

    pc->log = r->connection->log;
    pc->log_error = NGX_ERROR_ERR;

    dd("lua peer connection log: %p", pc->log);

    lua_rawgeti(L, 1, SOCKET_CONNECT_TIMEOUT_INDEX);
    lua_rawgeti(L, 1, SOCKET_SEND_TIMEOUT_INDEX);
    lua_rawgeti(L, 1, SOCKET_READ_TIMEOUT_INDEX);

    read_timeout = (ngx_int_t) lua_tointeger(L, -1);
    send_timeout = (ngx_int_t) lua_tointeger(L, -2);
    connect_timeout = (ngx_int_t) lua_tointeger(L, -3);

    lua_pop(L, 3);

    if (connect_timeout > 0) {
        u->connect_timeout = (ngx_msec_t) connect_timeout;

    } else {
        u->connect_timeout = u->conf->connect_timeout;
    }

    if (send_timeout > 0) {
        u->send_timeout = (ngx_msec_t) send_timeout;

    } else {
        u->send_timeout = u->conf->send_timeout;
    }

    if (read_timeout > 0) {
        u->read_timeout = (ngx_msec_t) read_timeout;

    } else {
        u->read_timeout = u->conf->read_timeout;
    }

    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(socket_pool_key));
    lua_rawget(L, LUA_REGISTRYINDEX); /* table */
    lua_pushvalue(L, key_index); /* key */

    lua_rawget(L, -2);
    spool = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (spool != NULL) {
        u->socket_pool = spool;

    } else if (pool_size > 0) {
        lua_pushvalue(L, key_index);
        key.data = (u_char *) lua_tolstring(L, -1, &key.len);

        ngx_http_lua_socket_tcp_create_socket_pool(L, r, key, pool_size,
                                                   backlog, &spool);
        u->socket_pool = spool;
    }

    return ngx_http_lua_socket_tcp_connect_helper(L, u, r, ctx, p,
                                                  len, port, 0);
}


static void
ngx_http_lua_socket_empty_resolve_handler(ngx_resolver_ctx_t *ctx)
{
    /* do nothing */
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
#if defined(nginx_version) && nginx_version >= 1005008
    socklen_t                            socklen;
    struct sockaddr                     *sockaddr;
#else
    struct sockaddr_in                  *sin;
#endif
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

    lctx->cur_co_ctx = u->write_co_ctx;

    u->write_co_ctx->cleanup = NULL;

    L = lctx->cur_co_ctx->co;

    waiting = u->conn_waiting;

    if (ctx->state) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua tcp socket resolver error: %s "
                       "(connect waiting: %d)",
                       ngx_resolver_strerror(ctx->state), (int) waiting);

        lua_pushnil(L);
        lua_pushlstring(L, (char *) ctx->name.data, ctx->name.len);
        lua_pushfstring(L, " could not be resolved (%d: %s)",
                        (int) ctx->state,
                        ngx_resolver_strerror(ctx->state));
        lua_concat(L, 2);

        u->write_prepare_retvals =
                                ngx_http_lua_socket_conn_error_retval_handler;
        ngx_http_lua_socket_handle_conn_error(r, u,
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
#   if defined(nginx_version) && nginx_version >= 1005008
    u_char      text[NGX_SOCKADDR_STRLEN];
    ngx_str_t   addr;
#   else
    in_addr_t   addr;
#   endif
    ngx_uint_t  i;

#   if defined(nginx_version) && nginx_version >= 1005008
    addr.data = text;

    for (i = 0; i < ctx->naddrs; i++) {
        addr.len = ngx_sock_ntop(ur->addrs[i].sockaddr, ur->addrs[i].socklen,
                                 text, NGX_SOCKADDR_STRLEN, 0);

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "name was resolved to %V", &addr);
    }
#   else
    for (i = 0; i < ctx->naddrs; i++) {
        dd("addr i: %d %p", (int) i,  &ctx->addrs[i]);

        addr = ntohl(ctx->addrs[i]);

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "name was resolved to %ud.%ud.%ud.%ud",
                       (addr >> 24) & 0xff, (addr >> 16) & 0xff,
                       (addr >> 8) & 0xff, addr & 0xff);
    }
#   endif
    }
#endif

    ngx_http_lua_assert(ur->naddrs > 0);

    if (ur->naddrs == 1) {
        i = 0;

    } else {
        i = ngx_random() % ur->naddrs;
    }

    dd("selected addr index: %d", (int) i);

#if defined(nginx_version) && nginx_version >= 1005008
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

#else
    /* for nginx older than 1.5.8 */

    len = NGX_INET_ADDRSTRLEN + sizeof(":65535") - 1;

    p = ngx_pnalloc(r->pool, len + sizeof(struct sockaddr_in));
    if (p == NULL) {
        goto nomem;
    }

    sin = (struct sockaddr_in *) &p[len];
    ngx_memzero(sin, sizeof(struct sockaddr_in));

    len = ngx_inet_ntop(AF_INET, &ur->addrs[i], p, NGX_INET_ADDRSTRLEN);
    len = ngx_sprintf(&p[len], ":%d", ur->port) - p;

    sin->sin_family = AF_INET;
    sin->sin_port = htons(ur->port);
    sin->sin_addr.s_addr = ur->addrs[i];

    ur->sockaddr = (struct sockaddr *) sin;
    ur->socklen = sizeof(struct sockaddr_in);
#endif

    ur->host.data = p;
    ur->host.len = len;
    ur->naddrs = 1;

    ngx_resolve_name_done(ctx);
    ur->ctx = NULL;

    u->conn_waiting = 0;
    u->write_co_ctx = NULL;

    if (waiting) {
        lctx->resume_handler = ngx_http_lua_socket_tcp_conn_resume;
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

    u->write_prepare_retvals = ngx_http_lua_socket_conn_error_retval_handler;
    ngx_http_lua_socket_handle_conn_error(r, u,
                                          NGX_HTTP_LUA_SOCKET_FT_NOMEM);

    if (waiting) {
        dd("run posted requests");
        ngx_http_run_posted_requests(c);

    } else {
        lua_pushnil(L);
        lua_pushliteral(L, "no memory");
    }
}


static void
ngx_http_lua_socket_init_peer_connection_addr_text(ngx_peer_connection_t *pc)
{
    ngx_connection_t            *c;
    size_t                       addr_text_max_len;

    c = pc->connection;

    switch (pc->sockaddr->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:
        addr_text_max_len = NGX_INET6_ADDRSTRLEN;
        break;
#endif

#if (NGX_HAVE_UNIX_DOMAIN)
    case AF_UNIX:
        addr_text_max_len = NGX_UNIX_ADDRSTRLEN;
        break;
#endif

    case AF_INET:
        addr_text_max_len = NGX_INET_ADDRSTRLEN;
        break;

    default:
        addr_text_max_len = NGX_SOCKADDR_STRLEN;
        break;
    }

    c->addr_text.data = ngx_pnalloc(c->pool, addr_text_max_len);
    if (c->addr_text.data == NULL) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0,
                      "init peer connection addr_text failed: no memory");
        return;
    }

    c->addr_text.len = ngx_sock_ntop(pc->sockaddr, pc->socklen,
                                     c->addr_text.data,
                                     addr_text_max_len, 0);
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
        cln = ngx_http_lua_cleanup_add(r, 0);
        if (cln == NULL) {
            u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
            lua_pushnil(L);
            lua_pushliteral(L, "no memory");
            return 2;
        }

        cln->handler = ngx_http_lua_socket_tcp_cleanup;
        cln->data = u;
        u->cleanup = &cln->handler;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connect: %i", rc);

    if (rc == NGX_ERROR) {
        return ngx_http_lua_socket_conn_error_retval_handler(r, u, L);
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
        return ngx_http_lua_socket_conn_error_retval_handler(r, u, L);
    }

    /* rc == NGX_OK || rc == NGX_AGAIN */

    c = pc->connection;

    c->data = u;

    c->write->handler = ngx_http_lua_socket_tcp_handler;
    c->read->handler = ngx_http_lua_socket_tcp_handler;

    u->write_event_handler = ngx_http_lua_socket_connected_handler;
    u->read_event_handler = ngx_http_lua_socket_connected_handler;

    c->sendfile &= r->connection->sendfile;

    if (c->pool == NULL) {

        /* we need separate pool here to be able to cache SSL connections */

        c->pool = ngx_create_pool(128, r->connection->log);
        if (c->pool == NULL) {
            return ngx_http_lua_socket_prepare_error_retvals(r, u, L,
                                                NGX_HTTP_LUA_SOCKET_FT_NOMEM);
        }
    }

    c->log = r->connection->log;
    c->pool->log = c->log;
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

    if (rc == NGX_OK) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket connected: fd:%d", (int) c->fd);

        /* We should delete the current write/read event
         * here because the socket object may not be used immediately
         * on the Lua land, thus causing hot spin around level triggered
         * event poll and wasting CPU cycles. */

        if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
            ngx_http_lua_socket_handle_conn_error(r, u,
                                                  NGX_HTTP_LUA_SOCKET_FT_ERROR);
            lua_pushnil(L);
            lua_pushliteral(L, "failed to handle write event");
            return 2;
        }

        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            ngx_http_lua_socket_handle_conn_error(r, u,
                                                  NGX_HTTP_LUA_SOCKET_FT_ERROR);
            lua_pushnil(L);
            lua_pushliteral(L, "failed to handle read event");
            return 2;
        }

        u->read_event_handler = ngx_http_lua_socket_dummy_handler;
        u->write_event_handler = ngx_http_lua_socket_dummy_handler;

        lua_pushinteger(L, 1);
        return 1;
    }

    /* rc == NGX_AGAIN */

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_coctx_cleanup;
    coctx->data = u;

    ngx_add_timer(c->write, u->connect_timeout);

    u->write_co_ctx = ctx->cur_co_ctx;
    u->conn_waiting = 1;
    u->write_prepare_retvals = ngx_http_lua_socket_tcp_conn_retval_handler;

    dd("setting data to %p", u);

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    return NGX_AGAIN;
}


static int
ngx_http_lua_socket_conn_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    ngx_uint_t      ft_type;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket error retval handler");

    if (u->write_co_ctx) {
        u->write_co_ctx->cleanup = NULL;
    }

    ngx_http_lua_socket_tcp_finalize(r, u);

    ft_type = u->ft_type;
    u->ft_type = 0;
    return ngx_http_lua_socket_prepare_error_retvals(r, u, L, ft_type);
}


#if (NGX_HTTP_SSL)

static int
ngx_http_lua_socket_tcp_sslhandshake(lua_State *L)
{
    int                      n, top;
    ngx_int_t                rc;
    ngx_str_t                name = ngx_null_string;
    ngx_connection_t        *c;
    ngx_ssl_session_t      **psession;
    ngx_http_request_t      *r;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_lua_co_ctx_t   *coctx;

    ngx_http_lua_socket_tcp_upstream_t  *u;

    /* Lua function arguments: self [,session] [,host] [,verify]
       [,send_status_req] */

    n = lua_gettop(L);
    if (n < 1 || n > 5) {
        return luaL_error(L, "ngx.socket sslhandshake: expecting 1 ~ 5 "
                          "arguments (including the object), but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket ssl handshake");

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);

    if (u == NULL
        || u->peer.connection == NULL
        || u->read_closed
        || u->write_closed)
    {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_socket_check_busy_connecting(r, u, L);
    ngx_http_lua_socket_check_busy_reading(r, u, L);
    ngx_http_lua_socket_check_busy_writing(r, u, L);

    if (u->raw_downstream || u->body_downstream) {
        lua_pushnil(L);
        lua_pushliteral(L, "not supported for downstream");
        return 2;
    }

    c = u->peer.connection;

    u->ssl_session_reuse = 1;

    if (c->ssl && c->ssl->handshaked) {
        switch (lua_type(L, 2)) {
        case LUA_TUSERDATA:
            lua_pushvalue(L, 2);
            break;

        case LUA_TBOOLEAN:
            if (!lua_toboolean(L, 2)) {
                /* avoid generating the ssl session */
                lua_pushboolean(L, 1);
                break;
            }
            /* fall through */

        default:
            ngx_http_lua_ssl_handshake_retval_handler(r, u, L);
            break;
        }

        return 1;
    }

    if (ngx_ssl_create_connection(u->conf->ssl, c,
                                  NGX_SSL_BUFFER|NGX_SSL_CLIENT)
        != NGX_OK)
    {
        lua_pushnil(L);
        lua_pushliteral(L, "failed to create ssl connection");
        return 2;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    coctx = ctx->cur_co_ctx;

    c->sendfile = 0;

    if (n >= 2) {
        if (lua_type(L, 2) == LUA_TBOOLEAN) {
            u->ssl_session_reuse = lua_toboolean(L, 2);

        } else {
            psession = lua_touserdata(L, 2);

            if (psession != NULL && *psession != NULL) {
                if (ngx_ssl_set_session(c, *psession) != NGX_OK) {
                    lua_pushnil(L);
                    lua_pushliteral(L, "lua ssl set session failed");
                    return 2;
                }

                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                               "lua ssl set session: %p", *psession);
            }
        }

        if (n >= 3) {
            name.data = (u_char *) lua_tolstring(L, 3, &name.len);

            if (name.data) {
                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "lua ssl server name: \"%*s\"", name.len,
                               name.data);

#ifdef SSL_CTRL_SET_TLSEXT_HOSTNAME

                if (SSL_set_tlsext_host_name(c->ssl->connection,
                                             (char *) name.data)
                    == 0)
                {
                    lua_pushnil(L);
                    lua_pushliteral(L, "SSL_set_tlsext_host_name failed");
                    return 2;
                }

#else

               ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                              "lua socket SNI disabled because the current "
                              "version of OpenSSL lacks the support");

#endif
            }

            if (n >= 4) {
                u->ssl_verify = lua_toboolean(L, 4);

                if (n >= 5) {
                    if (lua_toboolean(L, 5)) {
#ifdef NGX_HTTP_LUA_USE_OCSP
                        SSL_set_tlsext_status_type(c->ssl->connection,
                                                   TLSEXT_STATUSTYPE_ocsp);
#else
                        return luaL_error(L, "no OCSP support");
#endif
                    }
                }
            }
        }
    }

    dd("found sni name: %.*s %p", (int) name.len, name.data, name.data);

    if (name.len == 0) {
        u->ssl_name.len = 0;

    } else {
        if (u->ssl_name.data) {
            /* buffer already allocated */

            if (u->ssl_name.len >= name.len) {
                /* reuse it */
                ngx_memcpy(u->ssl_name.data, name.data, name.len);
                u->ssl_name.len = name.len;

            } else {
                ngx_free(u->ssl_name.data);
                goto new_ssl_name;
            }

        } else {

new_ssl_name:

            u->ssl_name.data = ngx_alloc(name.len, ngx_cycle->log);
            if (u->ssl_name.data == NULL) {
                u->ssl_name.len = 0;

                lua_pushnil(L);
                lua_pushliteral(L, "no memory");
                return 2;
            }

            ngx_memcpy(u->ssl_name.data, name.data, name.len);
            u->ssl_name.len = name.len;
        }
    }

    u->write_co_ctx = coctx;

#if 0
#ifdef NGX_HTTP_LUA_USE_OCSP
    SSL_set_tlsext_status_type(c->ssl->connection, TLSEXT_STATUSTYPE_ocsp);
#endif
#endif

    rc = ngx_ssl_handshake(c);

    dd("ngx_ssl_handshake returned %d", (int) rc);

    if (rc == NGX_AGAIN) {
        if (c->write->timer_set) {
            ngx_del_timer(c->write);
        }

        ngx_add_timer(c->read, u->connect_timeout);

        u->conn_waiting = 1;
        u->write_prepare_retvals = ngx_http_lua_ssl_handshake_retval_handler;

        ngx_http_lua_cleanup_pending_operation(coctx);
        coctx->cleanup = ngx_http_lua_coctx_cleanup;
        coctx->data = u;

        c->ssl->handler = ngx_http_lua_ssl_handshake_handler;

        if (ctx->entered_content_phase) {
            r->write_event_handler = ngx_http_lua_content_wev_handler;

        } else {
            r->write_event_handler = ngx_http_core_run_phases;
        }

        return lua_yield(L, 0);
    }

    top = lua_gettop(L);
    ngx_http_lua_ssl_handshake_handler(c);
    return lua_gettop(L) - top;
}


static void
ngx_http_lua_ssl_handshake_handler(ngx_connection_t *c)
{
    const char                  *err;
    int                          waiting;
    lua_State                   *L;
    ngx_int_t                    rc;
    ngx_connection_t            *dc;  /* downstream connection */
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_loc_conf_t     *llcf;

    ngx_http_lua_socket_tcp_upstream_t  *u;

    u = c->data;
    r = u->request;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return;
    }

    c->write->handler = ngx_http_lua_socket_tcp_handler;
    c->read->handler = ngx_http_lua_socket_tcp_handler;

    waiting = u->conn_waiting;

    dc = r->connection;
    L = u->write_co_ctx->co;

    if (c->read->timedout) {
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        goto failed;
    }

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    if (c->ssl->handshaked) {

        if (u->ssl_verify) {
            rc = SSL_get_verify_result(c->ssl->connection);

            if (rc != X509_V_OK) {
                lua_pushnil(L);
                err = lua_pushfstring(L, "%d: %s", (int) rc,
                                      X509_verify_cert_error_string(rc));

                llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
                if (llcf->log_socket_errors) {
                    ngx_log_error(NGX_LOG_ERR, dc->log, 0, "lua ssl "
                                  "certificate verify error: (%s)", err);
                }

                goto failed;
            }

#if defined(nginx_version) && nginx_version >= 1007000

            if (u->ssl_name.len
                && ngx_ssl_check_host(c, &u->ssl_name) != NGX_OK)
            {
                lua_pushnil(L);
                lua_pushliteral(L, "certificate host mismatch");

                llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
                if (llcf->log_socket_errors) {
                    ngx_log_error(NGX_LOG_ERR, dc->log, 0, "lua ssl "
                                  "certificate does not match host \"%V\"",
                                  &u->ssl_name);
                }

                goto failed;
            }

#endif
        }

        if (waiting) {
            ngx_http_lua_socket_handle_conn_success(r, u);

        } else {
            (void) ngx_http_lua_ssl_handshake_retval_handler(r, u, L);
        }

        if (waiting) {
            ngx_http_run_posted_requests(dc);
        }

        return;
    }

    lua_pushnil(L);
    lua_pushliteral(L, "handshake failed");

failed:

    if (waiting) {
        u->write_prepare_retvals =
                                ngx_http_lua_socket_conn_error_retval_handler;
        ngx_http_lua_socket_handle_conn_error(r, u,
                                              NGX_HTTP_LUA_SOCKET_FT_SSL);
        ngx_http_run_posted_requests(dc);

    } else {
        (void) ngx_http_lua_socket_conn_error_retval_handler(r, u, L);
    }
}


static int
ngx_http_lua_ssl_handshake_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    ngx_connection_t            *c;
    ngx_ssl_session_t           *ssl_session, **ud;

    if (!u->ssl_session_reuse) {
        lua_pushboolean(L, 1);
        return 1;
    }

    ud = lua_newuserdata(L, sizeof(ngx_ssl_session_t *));

    c = u->peer.connection;

    ssl_session = ngx_ssl_get_session(c);
    if (ssl_session == NULL) {
        *ud = NULL;

    } else {
        *ud = ssl_session;

       ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                      "lua ssl save session: %p", ssl_session);

        /* set up the __gc metamethod */
        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              ssl_session_metatable_key));
        lua_rawget(L, LUA_REGISTRYINDEX);
        lua_setmetatable(L, -2);
    }

    return 1;
}

#endif  /* NGX_HTTP_SSL */


static int
ngx_http_lua_socket_read_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    ngx_uint_t          ft_type;

    if (u->read_co_ctx) {
        u->read_co_ctx->cleanup = NULL;
    }

    ft_type = u->ft_type;
    u->ft_type = 0;

    if (u->no_close) {
        u->no_close = 0;

    } else {
        ngx_http_lua_socket_tcp_finalize_read_part(r, u);
    }

    return ngx_http_lua_socket_prepare_error_retvals(r, u, L, ft_type);
}


static int
ngx_http_lua_socket_write_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    ngx_uint_t          ft_type;

    if (u->write_co_ctx) {
        u->write_co_ctx->cleanup = NULL;
    }

    ngx_http_lua_socket_tcp_finalize_write_part(r, u);

    ft_type = u->ft_type;
    u->ft_type = 0;
    return ngx_http_lua_socket_prepare_error_retvals(r, u, L, ft_type);
}


static int
ngx_http_lua_socket_prepare_error_retvals(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L, ngx_uint_t ft_type)
{
    u_char           errstr[NGX_MAX_ERROR_STR];
    u_char          *p;

    if (ft_type & (NGX_HTTP_LUA_SOCKET_FT_RESOLVER
                   | NGX_HTTP_LUA_SOCKET_FT_SSL))
    {
        return 2;
    }

    lua_pushnil(L);

    if (ft_type & NGX_HTTP_LUA_SOCKET_FT_TIMEOUT) {
        lua_pushliteral(L, "timeout");

    } else if (ft_type & NGX_HTTP_LUA_SOCKET_FT_CLOSED) {
        lua_pushliteral(L, "closed");

    } else if (ft_type & NGX_HTTP_LUA_SOCKET_FT_BUFTOOSMALL) {
        lua_pushliteral(L, "buffer too small");

    } else if (ft_type & NGX_HTTP_LUA_SOCKET_FT_NOMEM) {
        lua_pushliteral(L, "no memory");

    } else if (ft_type & NGX_HTTP_LUA_SOCKET_FT_CLIENTABORT) {
        lua_pushliteral(L, "client aborted");

    } else {

        if (u->socket_errno) {
#if defined(nginx_version) && nginx_version >= 9000
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
ngx_http_lua_socket_tcp_conn_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    if (u->ft_type) {
        return ngx_http_lua_socket_conn_error_retval_handler(r, u, L);
    }

    lua_pushinteger(L, 1);
    return 1;
}


static int
ngx_http_lua_socket_tcp_receive_helper(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    ngx_int_t                            rc;
    ngx_http_lua_ctx_t                  *ctx;
    ngx_http_lua_co_ctx_t               *coctx;

    u->input_filter_ctx = u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (u->bufs_in == NULL) {
        u->bufs_in =
            ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                            &ctx->free_recv_bufs,
                                            u->conf->buffer_size);

        if (u->bufs_in == NULL) {
            return luaL_error(L, "no memory");
        }

        u->buf_in = u->bufs_in;
        u->buffer = *u->buf_in->buf;
    }

    dd("tcp receive: buf_in: %p, bufs_in: %p", u->buf_in, u->bufs_in);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket read timeout: %M", u->read_timeout);

    if (u->raw_downstream || u->body_downstream) {
        r->read_event_handler = ngx_http_lua_req_socket_rev_handler;
    }

    u->read_waiting = 0;
    u->read_co_ctx = NULL;

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

    coctx = ctx->cur_co_ctx;

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_coctx_cleanup;
    coctx->data = u;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    u->read_co_ctx = coctx;
    u->read_waiting = 1;
    u->read_prepare_retvals = ngx_http_lua_socket_tcp_receive_retval_handler;

    dd("setting data to %p, coctx:%p", u, coctx);

    if (u->raw_downstream || u->body_downstream) {
        ctx->downstream = u;
    }

    return lua_yield(L, 0);
}


static int
ngx_http_lua_socket_tcp_receiveany(lua_State *L)
{
    int                                  n;
    lua_Integer                          bytes;
    ngx_http_request_t                  *r;
    ngx_http_lua_loc_conf_t             *llcf;
    ngx_http_lua_socket_tcp_upstream_t  *u;

    n = lua_gettop(L);
    if (n != 2) {
        return luaL_error(L, "expecting 2 arguments "
                          "(including the object), but got %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);

    if (u == NULL || u->peer.connection == NULL || u->read_closed) {

        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to receive data on a closed socket: u:%p, "
                          "c:%p, ft:%d eof:%d",
                          u, u ? u->peer.connection : NULL,
                          u ? (int) u->ft_type : 0, u ? (int) u->eof : 0);
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_socket_check_busy_connecting(r, u, L);
    ngx_http_lua_socket_check_busy_reading(r, u, L);

    if (!lua_isnumber(L, 2)) {
        return luaL_argerror(L, 2, "bad max argument");
    }

    bytes = lua_tointeger(L, 2);
    if (bytes <= 0) {
        return luaL_argerror(L, 2, "bad max argument");
    }

    u->input_filter = ngx_http_lua_socket_read_any;
    u->rest = (size_t) bytes;
    u->length = u->rest;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket calling receiveany() method to read at "
                   "most %uz bytes", u->rest);

    return ngx_http_lua_socket_tcp_receive_helper(r, u, L);
}


static int
ngx_http_lua_socket_tcp_receive(lua_State *L)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_tcp_upstream_t  *u;
    int                                  n;
    ngx_str_t                            pat;
    lua_Integer                          bytes;
    char                                *p;
    int                                  typ;
    ngx_http_lua_loc_conf_t             *llcf;

    n = lua_gettop(L);
    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 arguments "
                          "(including the object), but got %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket calling receive() method");

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);

    if (u == NULL || u->peer.connection == NULL || u->read_closed) {

        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to receive data on a closed socket: u:%p, "
                          "c:%p, ft:%d eof:%d",
                          u, u ? u->peer.connection : NULL,
                          u ? (int) u->ft_type : 0, u ? (int) u->eof : 0);
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_socket_check_busy_connecting(r, u, L);
    ngx_http_lua_socket_check_busy_reading(r, u, L);

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

#if 1
            if (bytes == 0) {
                lua_pushliteral(L, "");
                return 1;
            }
#endif

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

    return ngx_http_lua_socket_tcp_receive_helper(r, u, L);
}


static ngx_int_t
ngx_http_lua_socket_read_chunk(void *data, ssize_t bytes)
{
    ngx_int_t                                rc;
    ngx_http_lua_socket_tcp_upstream_t      *u = data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua tcp socket read chunk %z", bytes);

    rc = ngx_http_lua_read_bytes(&u->buffer, u->buf_in, &u->rest,
                                 bytes, u->request->connection->log);
    if (rc == NGX_ERROR) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    return rc;
}


static ngx_int_t
ngx_http_lua_socket_read_all(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_tcp_upstream_t      *u = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua tcp socket read all");
    return ngx_http_lua_read_all(&u->buffer, u->buf_in, bytes,
                                 u->request->connection->log);
}


static ngx_int_t
ngx_http_lua_socket_read_line(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_tcp_upstream_t      *u = data;

    ngx_int_t                    rc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua tcp socket read line");

    rc = ngx_http_lua_read_line(&u->buffer, u->buf_in, bytes,
                                u->request->connection->log);
    if (rc == NGX_ERROR) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    return rc;
}


static ngx_int_t
ngx_http_lua_socket_read_any(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_tcp_upstream_t      *u = data;

    ngx_int_t                    rc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua tcp socket read any");

    rc = ngx_http_lua_read_any(&u->buffer, u->buf_in, &u->rest, bytes,
                               u->request->connection->log);
    if (rc == NGX_ERROR) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    return rc;
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
    off_t                        preread = 0;
    ngx_http_lua_loc_conf_t     *llcf;

    c = u->peer.connection;
    rev = c->read;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua tcp socket read data: wait:%d",
                   (int) u->read_waiting);

    b = &u->buffer;
    read = 0;

    for ( ;; ) {

        size = b->last - b->pos;

        if (size || u->eof) {

            rc = u->input_filter(u->input_filter_ctx, size);

            if (rc == NGX_OK) {

                ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "lua tcp socket receive done: wait:%d, eof:%d, "
                               "uri:\"%V?%V\"", (int) u->read_waiting,
                               (int) u->eof, &r->uri, &r->args);

                if (u->body_downstream
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
                            ngx_http_lua_socket_handle_read_error(r, u,
                                          NGX_HTTP_LUA_SOCKET_FT_CLIENTABORT);

                        } else {
                            ngx_http_lua_socket_handle_read_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
                        }

                        return NGX_ERROR;
                    }
                }

#if 1
                if (ngx_handle_read_event(rev, 0) != NGX_OK) {
                    ngx_http_lua_socket_handle_read_error(r, u,
                                     NGX_HTTP_LUA_SOCKET_FT_ERROR);
                    return NGX_ERROR;
                }
#endif

success:

                ngx_http_lua_socket_handle_read_success(r, u);
                return NGX_OK;
            }

            if (rc == NGX_ERROR) {
                dd("input filter error: ft_type:%d wait:%d",
                   (int) u->ft_type, (int) u->read_waiting);

                ngx_http_lua_socket_handle_read_error(r, u,
                                                NGX_HTTP_LUA_SOCKET_FT_ERROR);
                return NGX_ERROR;
            }

            /* rc == NGX_AGAIN */

            if (u->body_downstream && r->request_body->rest == 0) {
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
                ngx_http_lua_socket_handle_read_error(r, u,
                                                NGX_HTTP_LUA_SOCKET_FT_NOMEM);

                return NGX_ERROR;
            }

            b = &u->buffer;
            size = (size_t) (b->end - b->last);
        }

        if (u->raw_downstream) {
            preread = r->header_in->last - r->header_in->pos;

            if (preread) {

                if ((off_t) size > preread) {
                    size = (size_t) preread;
                }

                ngx_http_lua_probe_req_socket_consume_preread(r,
                                                              r->header_in->pos,
                                                              size);

                b->last = ngx_copy(b->last, r->header_in->pos, size);
                r->header_in->pos += size;
                continue;
            }

        } else if (u->body_downstream) {

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
                               "http client request body preread %O", preread);

                if (preread >= r->request_body->rest) {
                    preread = r->request_body->rest;
                }

                if ((off_t) size > preread) {
                    size = (size_t) preread;
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

            if (u->raw_downstream || u->body_downstream) {

                llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

                if (llcf->check_client_abort) {

                    ngx_http_lua_socket_handle_read_error(r, u,
                                          NGX_HTTP_LUA_SOCKET_FT_CLIENTABORT);
                    return NGX_ERROR;
                }

                /* llcf->check_client_abort == 0 */

                if (u->body_downstream && r->request_body->rest) {
                    ngx_http_lua_socket_handle_read_error(r, u,
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
            ngx_http_lua_socket_handle_read_error(r, u,
                                                  NGX_HTTP_LUA_SOCKET_FT_ERROR);
            return NGX_ERROR;
        }

        b->last += n;

        if (u->body_downstream) {
            r->request_length += n;
            r->request_body->rest -= n;
        }
    }

#if 1
    if (ngx_handle_read_event(rev, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_read_error(r, u,
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
    int                                  tcp_nodelay;
    const char                          *msg;
    ngx_buf_t                           *b;
    ngx_connection_t                    *c;
    ngx_http_lua_loc_conf_t             *llcf;
    ngx_http_core_loc_conf_t            *clcf;
    ngx_http_lua_co_ctx_t               *coctx;

    /* TODO: add support for the optional "i" and "j" arguments */

    if (lua_gettop(L) != 2) {
        return luaL_error(L, "expecting 2 arguments (including the object), "
                          "but got %d", lua_gettop(L));
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    dd("tcp send: u=%p, u->write_closed=%d", u, (unsigned) u->write_closed);

    if (u == NULL || u->peer.connection == NULL || u->write_closed) {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to send data on a closed socket: u:%p, "
                          "c:%p, ft:%d eof:%d",
                          u, u ? u->peer.connection : NULL,
                          u ? (int) u->ft_type : 0, u ? (int) u->eof : 0);
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_socket_check_busy_connecting(r, u, L);
    ngx_http_lua_socket_check_busy_writing(r, u, L);

    if (u->body_downstream) {
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

    if (len == 0) {
        lua_pushinteger(L, 0);
        return 1;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    cl = ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                         &ctx->free_bufs, len);

    if (cl == NULL) {
        return luaL_error(L, "no memory");
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

        case LUA_TNIL:
            *b->last++ = 'n';
            *b->last++ = 'i';
            *b->last++ = 'l';
            break;

        case LUA_TBOOLEAN:
            if (lua_toboolean(L, 2)) {
                *b->last++ = 't';
                *b->last++ = 'r';
                *b->last++ = 'u';
                *b->last++ = 'e';

            } else {
                *b->last++ = 'f';
                *b->last++ = 'a';
                *b->last++ = 'l';
                *b->last++ = 's';
                *b->last++ = 'e';
            }

            break;

        default:
            return luaL_error(L, "impossible to reach here");
    }

    u->request_bufs = cl;

    u->request_len = len;

    /* mimic ngx_http_upstream_init_request here */

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    c = u->peer.connection;

    if (clcf->tcp_nodelay && c->tcp_nodelay == NGX_TCP_NODELAY_UNSET) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua socket tcp_nodelay");

        tcp_nodelay = 1;

        if (setsockopt(c->fd, IPPROTO_TCP, TCP_NODELAY,
                       (const void *) &tcp_nodelay, sizeof(int))
            == -1)
        {
            llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
            if (llcf->log_socket_errors) {
                ngx_connection_error(c, ngx_socket_errno,
                                     "setsockopt(TCP_NODELAY) "
                                     "failed");
            }

            lua_pushnil(L);
            lua_pushliteral(L, "setsocketopt tcp_nodelay failed");
            return 2;
        }

        c->tcp_nodelay = NGX_TCP_NODELAY_SET;
    }

#if 1
    u->write_waiting = 0;
    u->write_co_ctx = NULL;
#endif

    ngx_http_lua_probe_socket_tcp_send_start(r, u, b->pos, len);

    rc = ngx_http_lua_socket_send(r, u);

    dd("socket send returned %d", (int) rc);

    if (rc == NGX_ERROR) {
        return ngx_http_lua_socket_write_error_retval_handler(r, u, L);
    }

    if (rc == NGX_OK) {
        lua_pushinteger(L, len);
        return 1;
    }

    /* rc == NGX_AGAIN */

    coctx = ctx->cur_co_ctx;

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_coctx_cleanup;
    coctx->data = u;

    if (u->raw_downstream) {
        ctx->writing_raw_req_socket = 1;
    }

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    u->write_co_ctx = coctx;
    u->write_waiting = 1;
    u->write_prepare_retvals = ngx_http_lua_socket_tcp_send_retval_handler;

    dd("setting data to %p", u);

    return lua_yield(L, 0);
}


static int
ngx_http_lua_socket_tcp_send_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket send return value handler");

    if (u->ft_type) {
        return ngx_http_lua_socket_write_error_retval_handler(r, u, L);
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
    if (u->raw_downstream || u->body_downstream) {
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

        if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_TIMEOUT) {
            u->no_close = 1;
        }

        dd("u->bufs_in: %p", u->bufs_in);

        if (u->bufs_in) {
            rc = ngx_http_lua_socket_push_input_data(r, ctx, u, L);
            if (rc == NGX_ERROR) {
                lua_pushnil(L);
                lua_pushliteral(L, "no memory");
                return 2;
            }

            (void) ngx_http_lua_socket_read_error_retval_handler(r, u, L);

            lua_pushvalue(L, -3);
            lua_remove(L, -4);
            return 3;
        }

        n = ngx_http_lua_socket_read_error_retval_handler(r, u, L);
        lua_pushliteral(L, "");
        return n + 1;
    }

    rc = ngx_http_lua_socket_push_input_data(r, ctx, u, L);
    if (rc == NGX_ERROR) {
        lua_pushnil(L);
        lua_pushliteral(L, "no memory");
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

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL
        || u->peer.connection == NULL
        || (u->read_closed && u->write_closed))
    {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_socket_check_busy_connecting(r, u, L);
    ngx_http_lua_socket_check_busy_reading(r, u, L);
    ngx_http_lua_socket_check_busy_writing(r, u, L);

    if (u->raw_downstream || u->body_downstream) {
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
        return luaL_error(L, "ngx.socket settimout: expecting 2 arguments "
                          "(including the object) but seen %d", lua_gettop(L));
    }

    timeout = (ngx_int_t) lua_tonumber(L, 2);
    if (timeout >> 31) {
        return luaL_error(L, "bad timeout value");
    }

    lua_pushinteger(L, timeout);
    lua_pushinteger(L, timeout);

    lua_rawseti(L, 1, SOCKET_CONNECT_TIMEOUT_INDEX);
    lua_rawseti(L, 1, SOCKET_SEND_TIMEOUT_INDEX);
    lua_rawseti(L, 1, SOCKET_READ_TIMEOUT_INDEX);

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


static int
ngx_http_lua_socket_tcp_settimeouts(lua_State *L)
{
    int                     n;
    ngx_int_t               connect_timeout, send_timeout, read_timeout;

    ngx_http_lua_socket_tcp_upstream_t  *u;

    n = lua_gettop(L);

    if (n != 4) {
        return luaL_error(L, "ngx.socket settimout: expecting 4 arguments "
                          "(including the object) but seen %d", lua_gettop(L));
    }

    connect_timeout = (ngx_int_t) lua_tonumber(L, 2);
    if (connect_timeout >> 31) {
        return luaL_error(L, "bad timeout value");
    }

    send_timeout = (ngx_int_t) lua_tonumber(L, 3);
    if (send_timeout >> 31) {
        return luaL_error(L, "bad timeout value");
    }

    read_timeout = (ngx_int_t) lua_tonumber(L, 4);
    if (read_timeout >> 31) {
        return luaL_error(L, "bad timeout value");
    }

    lua_rawseti(L, 1, SOCKET_READ_TIMEOUT_INDEX);
    lua_rawseti(L, 1, SOCKET_SEND_TIMEOUT_INDEX);
    lua_rawseti(L, 1, SOCKET_CONNECT_TIMEOUT_INDEX);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);

    if (u) {
        if (connect_timeout > 0) {
            u->connect_timeout = (ngx_msec_t) connect_timeout;

        } else {
            u->connect_timeout = u->conf->connect_timeout;
        }

        if (send_timeout > 0) {
            u->send_timeout = (ngx_msec_t) send_timeout;

        } else {
            u->send_timeout = u->conf->send_timeout;
        }

        if (read_timeout > 0) {
            u->read_timeout = (ngx_msec_t) read_timeout;

        } else {
            u->read_timeout = u->conf->read_timeout;
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

    if (c->fd != (ngx_socket_t) -1) {  /* not a fake connection */
        ctx = c->log->data;
        ctx->current_request = r;
    }

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, c->log, 0,
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
        c->read->timedout = 0;

        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_socket_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "lua tcp socket read timed out");
        }

        ngx_http_lua_socket_handle_read_error(r, u,
                                              NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
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

        ngx_http_lua_socket_handle_write_error(r, u,
                                               NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
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

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        ngx_http_lua_socket_handle_write_error(r, u,
                                               NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

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
                    ngx_http_lua_socket_handle_write_error(r, u,
                                                NGX_HTTP_LUA_SOCKET_FT_ERROR);
                    return NGX_ERROR;
                }

                ngx_http_lua_socket_handle_write_success(r, u);
                return NGX_OK;
            }

            /* keep sending more data */
            continue;
        }

        /* NGX_ERROR || NGX_AGAIN */
        break;
    }

    if (n == NGX_ERROR) {
        c->error = 1;
        u->socket_errno = ngx_socket_errno;
        ngx_http_lua_socket_handle_write_error(r, u,
                                               NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    /* n == NGX_AGAIN */

    if (u->raw_downstream) {
        ctx->writing_raw_req_socket = 1;
    }

    u->write_event_handler = ngx_http_lua_socket_send_handler;

    ngx_add_timer(c->write, u->send_timeout);

    if (ngx_handle_write_event(c->write, u->conf->send_lowat) != NGX_OK) {
        ngx_http_lua_socket_handle_write_error(r, u,
                                               NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    return NGX_AGAIN;
}


static void
ngx_http_lua_socket_handle_conn_success(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

#if 1
    u->read_event_handler = ngx_http_lua_socket_dummy_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;
#endif

    if (u->conn_waiting) {
        u->conn_waiting = 0;

        coctx = u->write_co_ctx;
        coctx->cleanup = NULL;
        u->write_co_ctx = NULL;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            return;
        }

        ctx->resume_handler = ngx_http_lua_socket_tcp_conn_resume;
        ctx->cur_co_ctx = coctx;

        ngx_http_lua_assert(coctx && (!ngx_http_lua_is_thread(ctx)
                            || coctx->co_ref >= 0));

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket waking up the current request (conn)");

        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_socket_handle_read_success(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

#if 1
    u->read_event_handler = ngx_http_lua_socket_dummy_handler;
#endif

    if (u->read_waiting) {
        u->read_waiting = 0;

        coctx = u->read_co_ctx;
        coctx->cleanup = NULL;
        u->read_co_ctx = NULL;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            return;
        }

        ctx->resume_handler = ngx_http_lua_socket_tcp_read_resume;
        ctx->cur_co_ctx = coctx;

        ngx_http_lua_assert(coctx && (!ngx_http_lua_is_thread(ctx)
                            || coctx->co_ref >= 0));

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket waking up the current request (read)");

        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_socket_handle_write_success(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

#if 1
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;
#endif

    if (u->write_waiting) {
        u->write_waiting = 0;

        coctx = u->write_co_ctx;
        coctx->cleanup = NULL;
        u->write_co_ctx = NULL;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            return;
        }

        ctx->resume_handler = ngx_http_lua_socket_tcp_write_resume;
        ctx->cur_co_ctx = coctx;

        ngx_http_lua_assert(coctx && (!ngx_http_lua_is_thread(ctx)
                            || coctx->co_ref >= 0));

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket waking up the current request (read)");

        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_socket_handle_conn_error(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_uint_t ft_type)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket handle connect error");

    u->ft_type |= ft_type;

#if 1
    ngx_http_lua_socket_tcp_finalize(r, u);
#endif

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    dd("connection waiting: %d", (int) u->conn_waiting);

    coctx = u->write_co_ctx;

    if (u->conn_waiting) {
        u->conn_waiting = 0;

        coctx->cleanup = NULL;
        u->write_co_ctx = NULL;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        ctx->resume_handler = ngx_http_lua_socket_tcp_conn_resume;
        ctx->cur_co_ctx = coctx;

        ngx_http_lua_assert(coctx && (!ngx_http_lua_is_thread(ctx)
                            || coctx->co_ref >= 0));

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket waking up the current request");

        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_socket_handle_read_error(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_uint_t ft_type)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket handle read error");

    u->ft_type |= ft_type;

#if 0
    ngx_http_lua_socket_tcp_finalize(r, u);
#endif

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;

    if (u->read_waiting) {
        u->read_waiting = 0;

        coctx = u->read_co_ctx;
        coctx->cleanup = NULL;
        u->read_co_ctx = NULL;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        ctx->resume_handler = ngx_http_lua_socket_tcp_read_resume;
        ctx->cur_co_ctx = coctx;

        ngx_http_lua_assert(coctx && (!ngx_http_lua_is_thread(ctx)
                            || coctx->co_ref >= 0));

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket waking up the current request");

        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_socket_handle_write_error(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, ngx_uint_t ft_type)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket handle write error");

    u->ft_type |= ft_type;

#if 0
    ngx_http_lua_socket_tcp_finalize(r, u);
#endif

    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    if (u->write_waiting) {
        u->write_waiting = 0;

        coctx = u->write_co_ctx;
        coctx->cleanup = NULL;
        u->write_co_ctx = NULL;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        ctx->resume_handler = ngx_http_lua_socket_tcp_write_resume;
        ctx->cur_co_ctx = coctx;

        ngx_http_lua_assert(coctx && (!ngx_http_lua_is_thread(ctx)
                            || coctx->co_ref >= 0));

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
            ngx_http_lua_socket_init_peer_connection_addr_text(&u->peer);
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "lua tcp socket connect timed out,"
                          " when connecting to %V:%ud",
                          &c->addr_text, ngx_inet_get_port(u->peer.sockaddr));
        }

        ngx_http_lua_socket_handle_conn_error(r, u,
                                              NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
        return;
    }

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    rc = ngx_http_lua_socket_test_connect(r, c);
    if (rc != NGX_OK) {
        if (rc > 0) {
            u->socket_errno = (ngx_err_t) rc;
        }

        ngx_http_lua_socket_handle_conn_error(r, u,
                                              NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connected");

    /* We should delete the current write/read event
     * here because the socket object may not be used immediately
     * on the Lua land, thus causing hot spin around level triggered
     * event poll and wasting CPU cycles. */

    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_conn_error(r, u,
                                              NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_conn_error(r, u,
                                              NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    ngx_http_lua_socket_handle_conn_success(r, u);
}


static void
ngx_http_lua_socket_tcp_cleanup(void *data)
{
    ngx_http_lua_socket_tcp_upstream_t  *u = data;

    ngx_http_request_t  *r;

    r = u->request;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "cleanup lua tcp socket request: \"%V\"", &r->uri);

    ngx_http_lua_socket_tcp_finalize(r, u);
}


static void
ngx_http_lua_socket_tcp_finalize_read_part(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_chain_t                         *cl;
    ngx_chain_t                        **ll;
    ngx_connection_t                    *c;
    ngx_http_lua_ctx_t                  *ctx;

    if (u->read_closed) {
        return;
    }

    u->read_closed = 1;

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

    if (u->raw_downstream || u->body_downstream) {
        if (r->connection->read->timer_set) {
            ngx_del_timer(r->connection->read);
        }
        return;
    }

    c = u->peer.connection;

    if (c) {
        if (c->read->timer_set) {
            ngx_del_timer(c->read);
        }

        if (c->read->active || c->read->disabled) {
            ngx_del_event(c->read, NGX_READ_EVENT, NGX_CLOSE_EVENT);
        }

#if defined(nginx_version) && nginx_version >= 1007005
        if (c->read->posted) {
#else
        if (c->read->prev) {
#endif
            ngx_delete_posted_event(c->read);
        }

        c->read->closed = 1;

        /* TODO: shutdown the reading part of the connection */
    }
}


static void
ngx_http_lua_socket_tcp_finalize_write_part(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_connection_t                    *c;
    ngx_http_lua_ctx_t                  *ctx;

    if (u->write_closed) {
        return;
    }

    u->write_closed = 1;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (u->raw_downstream || u->body_downstream) {
        if (ctx && ctx->writing_raw_req_socket) {
            ctx->writing_raw_req_socket = 0;
            if (r->connection->write->timer_set) {
                ngx_del_timer(r->connection->write);
            }

            r->connection->write->error = 1;
        }
        return;
    }

    c = u->peer.connection;

    if (c) {
        if (c->write->timer_set) {
            ngx_del_timer(c->write);
        }

        if (c->write->active || c->write->disabled) {
            ngx_del_event(c->write, NGX_WRITE_EVENT, NGX_CLOSE_EVENT);
        }

#if defined(nginx_version) && nginx_version >= 1007005
        if (c->write->posted) {
#else
        if (c->write->prev) {
#endif
            ngx_delete_posted_event(c->write);
        }

        c->write->closed = 1;

        /* TODO: shutdown the writing part of the connection */
    }
}


static void
ngx_http_lua_socket_tcp_conn_op_timeout_handler(ngx_event_t *ev)
{
    ngx_http_lua_socket_tcp_upstream_t      *u;
    ngx_http_lua_ctx_t                      *ctx;
    ngx_connection_t                        *c;
    ngx_http_request_t                      *r;
    ngx_http_lua_co_ctx_t                   *coctx;
    ngx_http_lua_loc_conf_t                 *llcf;
    ngx_http_lua_socket_tcp_conn_op_ctx_t   *conn_op_ctx;

    conn_op_ctx = ev->data;
    ngx_queue_remove(&conn_op_ctx->queue);

    u = conn_op_ctx->u;
    r = u->request;

    coctx = u->write_co_ctx;
    coctx->cleanup = NULL;
    /* note that we store conn_op_ctx in coctx->data instead of u */
    coctx->data = conn_op_ctx;
    u->write_co_ctx = NULL;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->log_socket_errors) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "lua tcp socket queued connect timed out,"
                      " when trying to connect to %V:%ud",
                      &conn_op_ctx->host, conn_op_ctx->port);
    }

    ngx_queue_insert_head(&u->socket_pool->cache_connect_op,
                          &conn_op_ctx->queue);
    u->socket_pool->connections--;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return;
    }

    ctx->cur_co_ctx = coctx;

    ngx_http_lua_assert(coctx && (!ngx_http_lua_is_thread(ctx)
                        || coctx->co_ref >= 0));

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket waking up the current request");

    u->write_prepare_retvals =
        ngx_http_lua_socket_tcp_conn_op_timeout_retval_handler;

    c = r->connection;

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_socket_tcp_conn_op_resume(r);

    } else {
        ctx->resume_handler = ngx_http_lua_socket_tcp_conn_op_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
}


static int
ngx_http_lua_socket_tcp_conn_op_timeout_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    lua_pushnil(L);
    lua_pushliteral(L, "timeout");
    return 2;
}


static void
ngx_http_lua_socket_tcp_resume_conn_op(ngx_http_lua_socket_pool_t *spool)
{
    ngx_queue_t                             *q;
    ngx_http_lua_socket_tcp_conn_op_ctx_t   *conn_op_ctx;

#if (NGX_DEBUG)
    ngx_http_lua_assert(spool->connections >= 0);

#else
    if (spool->connections < 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "lua tcp socket connections count mismatched for "
                      "connection pool \"%s\", connections: %i, size: %i",
                      spool->key, spool->connections, spool->size);
        spool->connections = 0;
    }
#endif

    /* we manually destroy wait_connect_op before triggering connect
     * operation resumption, so that there is no resumption happens when Nginx
     * is exiting.
     */
    if (ngx_queue_empty(&spool->wait_connect_op)) {
        return;
    }

    q = ngx_queue_head(&spool->wait_connect_op);
    conn_op_ctx = ngx_queue_data(q, ngx_http_lua_socket_tcp_conn_op_ctx_t,
                                 queue);
    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua tcp socket post connect operation resumption "
                   "u: %p, ctx: %p for connection pool \"%s\", "
                   "connections: %i",
                   conn_op_ctx->u, conn_op_ctx, spool->key, spool->connections);

    if (conn_op_ctx->event.timer_set) {
        ngx_del_timer(&conn_op_ctx->event);
    }

    conn_op_ctx->event.handler =
        ngx_http_lua_socket_tcp_conn_op_resume_handler;

    ngx_post_event((&conn_op_ctx->event), &ngx_posted_events);
}


static void
ngx_http_lua_socket_tcp_conn_op_ctx_cleanup(void *data)
{
    ngx_http_lua_socket_tcp_upstream_t     *u;
    ngx_http_lua_socket_tcp_conn_op_ctx_t  *conn_op_ctx = data;

    u = conn_op_ctx->u;
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "cleanup lua tcp socket conn_op_ctx: \"%V\"",
                   &u->request->uri);

    ngx_queue_insert_head(&u->socket_pool->cache_connect_op,
                          &conn_op_ctx->queue);
}


static void
ngx_http_lua_socket_tcp_conn_op_resume_handler(ngx_event_t *ev)
{
    ngx_queue_t                             *q;
    ngx_connection_t                        *c;
    ngx_http_lua_ctx_t                      *ctx;
    ngx_http_request_t                      *r;
    ngx_http_cleanup_t                      *cln;
    ngx_http_lua_co_ctx_t                   *coctx;
    ngx_http_lua_socket_pool_t              *spool;
    ngx_http_lua_socket_tcp_upstream_t      *u;
    ngx_http_lua_socket_tcp_conn_op_ctx_t   *conn_op_ctx;

    conn_op_ctx = ev->data;
    u = conn_op_ctx->u;
    r = u->request;
    spool = u->socket_pool;

    if (ngx_queue_empty(&spool->wait_connect_op)) {
#if (NGX_DEBUG)
        ngx_http_lua_assert(!(spool->backlog >= 0
                              && spool->connections > spool->size));

#else
        if (spool->backlog >= 0 && spool->connections > spool->size) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "lua tcp socket connections count mismatched for "
                          "connection pool \"%s\", connections: %i, size: %i",
                          spool->key, spool->connections, spool->size);
            spool->connections = spool->size;
        }
#endif

        return;
    }

    q = ngx_queue_head(&spool->wait_connect_op);
    ngx_queue_remove(q);

    coctx = u->write_co_ctx;
    coctx->cleanup = NULL;
    /* note that we store conn_op_ctx in coctx->data instead of u */
    coctx->data = conn_op_ctx;
    /* clear ngx_http_lua_tcp_queue_conn_op_cleanup */
    u->write_co_ctx = NULL;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        ngx_queue_insert_head(&spool->cache_connect_op,
                              &conn_op_ctx->queue);
        return;
    }

    ctx->cur_co_ctx = coctx;

    ngx_http_lua_assert(coctx && (!ngx_http_lua_is_thread(ctx)
                        || coctx->co_ref >= 0));

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket waking up the current request");

    u->write_prepare_retvals =
        ngx_http_lua_socket_tcp_conn_op_resume_retval_handler;

    c = r->connection;

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_socket_tcp_conn_op_resume(r);

    } else {
        cln = ngx_http_lua_cleanup_add(r, 0);
        if (cln != NULL) {
            cln->handler = ngx_http_lua_socket_tcp_conn_op_ctx_cleanup;
            cln->data = conn_op_ctx;
            conn_op_ctx->cleanup = &cln->handler;
        }

        ctx->resume_handler = ngx_http_lua_socket_tcp_conn_op_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
}


static int
ngx_http_lua_socket_tcp_conn_op_resume_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u, lua_State *L)
{
    int                                      nret;
    ngx_http_lua_ctx_t                      *ctx;
    ngx_http_lua_co_ctx_t                   *coctx;
    ngx_http_lua_socket_tcp_conn_op_ctx_t   *conn_op_ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    coctx = ctx->cur_co_ctx;
    dd("coctx: %p", coctx);
    conn_op_ctx = coctx->data;
    if (conn_op_ctx->cleanup != NULL) {
        *conn_op_ctx->cleanup = NULL;
        ngx_http_lua_cleanup_free(r, conn_op_ctx->cleanup);
        conn_op_ctx->cleanup = NULL;
    }

    /* decrease pending connect operation counter */
    u->socket_pool->connections--;

    nret = ngx_http_lua_socket_tcp_connect_helper(L, u, r, ctx,
                                                  conn_op_ctx->host.data,
                                                  conn_op_ctx->host.len,
                                                  conn_op_ctx->port, 1);
    ngx_queue_insert_head(&u->socket_pool->cache_connect_op,
                          &conn_op_ctx->queue);

    return nret;
}


static void
ngx_http_lua_socket_tcp_finalize(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_connection_t               *c;
    ngx_http_lua_socket_pool_t     *spool;

    dd("request: %p, u: %p, u->cleanup: %p", r, u, u->cleanup);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua finalize socket");

    if (u->cleanup) {
        *u->cleanup = NULL;
        ngx_http_lua_cleanup_free(r, u->cleanup);
        u->cleanup = NULL;
    }

    ngx_http_lua_socket_tcp_finalize_read_part(r, u);
    ngx_http_lua_socket_tcp_finalize_write_part(r, u);

    if (u->raw_downstream || u->body_downstream) {
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

#if (NGX_HTTP_SSL)
    if (u->ssl_name.data) {
        ngx_free(u->ssl_name.data);
        u->ssl_name.data = NULL;
        u->ssl_name.len = 0;
    }
#endif

    c = u->peer.connection;
    if (c) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua close socket connection");

        ngx_http_lua_socket_tcp_close_connection(c);
        u->peer.connection = NULL;
        u->conn_closed = 1;

        spool = u->socket_pool;
        if (spool == NULL) {
            return;
        }

        spool->connections--;

        if (spool->connections == 0) {
            ngx_http_lua_socket_free_pool(r->connection->log, spool);
            return;
        }

        ngx_http_lua_socket_tcp_resume_conn_op(spool);
    }
}


static void
ngx_http_lua_socket_tcp_close_connection(ngx_connection_t *c)
{
#if (NGX_HTTP_SSL)

    if (c->ssl) {
        c->ssl->no_wait_shutdown = 1;
        c->ssl->no_send_shutdown = 1;

        (void) ngx_ssl_shutdown(c);
    }

#endif

    if (c->pool) {
        ngx_destroy_pool(c->pool);
        c->pool = NULL;
    }

    ngx_close_connection(c);
}


static ngx_int_t
ngx_http_lua_socket_test_connect(ngx_http_request_t *r, ngx_connection_t *c)
{
    int              err;
    socklen_t        len;

    ngx_http_lua_loc_conf_t     *llcf;

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
            llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
            if (llcf->log_socket_errors) {
                (void) ngx_connection_error(c, ev->kq_errno,
                                            "kevent() reported that "
                                            "connect() failed");
            }
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
            llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
            if (llcf->log_socket_errors) {
                (void) ngx_connection_error(c, err, "connect() failed");
            }
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

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

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
        return luaL_error(L, "no memory");
    }

    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          pattern_udata_metatable_key));
    lua_rawget(L, LUA_REGISTRYINDEX);
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

    if (u == NULL || u->peer.connection == NULL || u->read_closed) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_socket_check_busy_connecting(r, u, L);
    ngx_http_lua_socket_check_busy_reading(r, u, L);

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
            ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                            &ctx->free_recv_bufs,
                                            u->conf->buffer_size);

        if (u->bufs_in == NULL) {
            return luaL_error(L, "no memory");
        }

        u->buf_in = u->bufs_in;
        u->buffer = *u->buf_in->buf;
    }

    u->length = (size_t) bytes;
    u->rest = u->length;

    if (u->raw_downstream || u->body_downstream) {
        r->read_event_handler = ngx_http_lua_req_socket_rev_handler;
    }

    u->read_waiting = 0;
    u->read_co_ctx = NULL;

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

    coctx = ctx->cur_co_ctx;

    u->read_event_handler = ngx_http_lua_socket_read_handler;

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_coctx_cleanup;
    coctx->data = u;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    u->read_co_ctx = coctx;
    u->read_waiting = 1;
    u->read_prepare_retvals = ngx_http_lua_socket_tcp_receive_retval_handler;

    dd("setting data to %p", u);

    if (u->raw_downstream || u->body_downstream) {
        ctx->downstream = u;
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
    ngx_http_lua_dfa_edge_t        **last = NULL;

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
                    if (edge == NULL) {
                        return NGX_ERROR;
                    }

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
    int                              n, raw;
    ngx_peer_connection_t           *pc;
    ngx_http_lua_loc_conf_t         *llcf;
    ngx_connection_t                *c;
    ngx_http_request_t              *r;
    ngx_http_lua_ctx_t              *ctx;
    ngx_http_request_body_t         *rb;
    ngx_http_cleanup_t              *cln;
    ngx_http_lua_co_ctx_t           *coctx;

    ngx_http_lua_socket_tcp_upstream_t  *u;

    n = lua_gettop(L);
    if (n == 0) {
        raw = 0;

    } else if (n == 1) {
        raw = lua_toboolean(L, 1);
        lua_pop(L, 1);

    } else {
        return luaL_error(L, "expecting zero arguments, but got %d",
                          lua_gettop(L));
    }

    r = ngx_http_lua_get_req(L);

    if (r != r->main) {
        return luaL_error(L, "attempt to read the request body in a "
                          "subrequest");
    }

#if (NGX_HTTP_SPDY)
    if (r->spdy_stream) {
        return luaL_error(L, "spdy not supported yet");
    }
#endif

#if (NGX_HTTP_V2)
    if (r->stream) {
        return luaL_error(L, "http v2 not supported yet");
    }
#endif

#if nginx_version >= 1003009
    if (!raw && r->headers_in.chunked) {
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

    c = r->connection;

    if (raw) {
#if !defined(nginx_version) || nginx_version < 1003013
        lua_pushnil(L);
        lua_pushliteral(L, "nginx version too old");
        return 2;
#else
        if (r->request_body) {
            if (r->request_body->rest > 0) {
                lua_pushnil(L);
                lua_pushliteral(L, "pending request body reading in some "
                                "other thread");
                return 2;
            }

        } else {
            rb = ngx_pcalloc(r->pool, sizeof(ngx_http_request_body_t));
            if (rb == NULL) {
                return luaL_error(L, "no memory");
            }
            r->request_body = rb;
        }

        if (c->buffered & NGX_HTTP_LOWLEVEL_BUFFERED) {
            lua_pushnil(L);
            lua_pushliteral(L, "pending data to write");
            return 2;
        }

        if (ctx->buffering) {
            lua_pushnil(L);
            lua_pushliteral(L, "http 1.0 buffering");
            return 2;
        }

        if (!r->header_sent) {
            /* prevent other parts of nginx from sending out
             * the response header */
            r->header_sent = 1;
        }

        ctx->header_sent = 1;

        dd("ctx acquired raw req socket: %d", ctx->acquired_raw_req_socket);

        if (ctx->acquired_raw_req_socket) {
            lua_pushnil(L);
            lua_pushliteral(L, "duplicate call");
            return 2;
        }

        ctx->acquired_raw_req_socket = 1;
        r->keepalive = 0;
        r->lingering_close = 1;
#endif

    } else {
        /* request body reader */

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
            return luaL_error(L, "no memory");
        }

        rb->rest = r->headers_in.content_length_n;

        r->request_body = rb;
    }

    lua_createtable(L, 2 /* narr */, 3 /* nrec */); /* the object */

    if (raw) {
        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              raw_req_socket_metatable_key));

    } else {
        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              req_socket_metatable_key));
    }

    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    u = lua_newuserdata(L, sizeof(ngx_http_lua_socket_tcp_upstream_t));
    if (u == NULL) {
        return luaL_error(L, "no memory");
    }

#if 1
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          downstream_udata_metatable_key));
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);
#endif

    lua_rawseti(L, 1, SOCKET_CTX_INDEX);

    ngx_memzero(u, sizeof(ngx_http_lua_socket_tcp_upstream_t));

    if (raw) {
        u->raw_downstream = 1;

    } else {
        u->body_downstream = 1;
    }

    coctx = ctx->cur_co_ctx;

    u->request = r;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    u->conf = llcf;

    u->read_timeout = u->conf->read_timeout;
    u->connect_timeout = u->conf->connect_timeout;
    u->send_timeout = u->conf->send_timeout;

    cln = ngx_http_lua_cleanup_add(r, 0);
    if (cln == NULL) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
        lua_pushnil(L);
        lua_pushliteral(L, "no memory");
        return 2;
    }

    cln->handler = ngx_http_lua_socket_tcp_cleanup;
    cln->data = u;
    u->cleanup = &cln->handler;

    pc = &u->peer;

    pc->log = c->log;
    pc->log_error = NGX_ERROR_ERR;

    pc->connection = c;

    dd("setting data to %p", u);

    coctx->data = u;
    ctx->downstream = u;

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    if (raw) {
        if (c->write->timer_set) {
            ngx_del_timer(c->write);
        }
    }

    lua_settop(L, 1);
    return 1;
}


static void
ngx_http_lua_req_socket_rev_handler(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t                  *ctx;
    ngx_http_lua_socket_tcp_upstream_t  *u;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua request socket read event handler");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        r->read_event_handler = ngx_http_block_reading;
        return;
    }

    u = ctx->downstream;
    if (u == NULL || u->peer.connection == NULL) {
        r->read_event_handler = ngx_http_block_reading;
        return;
    }

    u->read_event_handler(r, u);
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

    if (u == NULL
        || u->peer.connection == NULL
        || (u->read_closed && u->write_closed))
    {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    lua_pushinteger(L, u->reused);
    return 1;
}


static int
ngx_http_lua_socket_tcp_setkeepalive(lua_State *L)
{
    ngx_http_lua_loc_conf_t             *llcf;
    ngx_http_lua_socket_tcp_upstream_t  *u;
    ngx_connection_t                    *c;
    ngx_http_lua_socket_pool_t          *spool;
    ngx_str_t                            key;
    ngx_queue_t                         *q;
    ngx_peer_connection_t               *pc;
    ngx_http_request_t                  *r;
    ngx_msec_t                           timeout;
    ngx_int_t                            pool_size;
    int                                  n;
    ngx_int_t                            rc;
    ngx_buf_t                           *b;
    const char                          *msg;

    ngx_http_lua_socket_pool_item_t     *item;

    n = lua_gettop(L);

    if (n < 1 || n > 3) {
        return luaL_error(L, "expecting 1 to 3 arguments "
                          "(including the object), but got %d", n);
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, SOCKET_CTX_INDEX);
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    /* stack: obj timeout? size? */

    pc = &u->peer;
    c = pc->connection;

    if (c == NULL || u->read_closed || u->write_closed) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    if (u->request != r) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_socket_check_busy_connecting(r, u, L);
    ngx_http_lua_socket_check_busy_reading(r, u, L);
    ngx_http_lua_socket_check_busy_writing(r, u, L);

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

    if (ngx_terminate || ngx_exiting) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "lua tcp socket set keepalive while process exiting, "
                       "closing connection %p", c);

        ngx_http_lua_socket_tcp_finalize(r, u);
        lua_pushinteger(L, 1);
        return 1;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua tcp socket set keepalive: saving connection %p", c);

    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(socket_pool_key));
    lua_rawget(L, LUA_REGISTRYINDEX);

    /* stack: obj timeout? size? pools */

    lua_rawgeti(L, 1, SOCKET_KEY_INDEX);
    key.data = (u_char *) lua_tolstring(L, -1, &key.len);
    if (key.data == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "key not found");
        return 2;
    }

    dd("saving connection to key %s", lua_tostring(L, -1));

    lua_pushvalue(L, -1);
    lua_rawget(L, -3);
    spool = lua_touserdata(L, -1);
    lua_pop(L, 1);

    /* stack: obj timeout? size? pools cache_key */

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (spool == NULL) {
        /* create a new socket pool for the current peer key */

        if (n >= 3 && !lua_isnil(L, 3)) {
            pool_size = luaL_checkinteger(L, 3);

        } else {
            pool_size = llcf->pool_size;
        }

        if (pool_size <= 0) {
            msg = lua_pushfstring(L, "bad \"pool_size\" option value: %i",
                                  pool_size);
            return luaL_argerror(L, n, msg);
        }

        ngx_http_lua_socket_tcp_create_socket_pool(L, r, key, pool_size, -1,
                                                   &spool);
    }

    if (ngx_queue_empty(&spool->free)) {

        q = ngx_queue_last(&spool->cache);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_lua_socket_pool_item_t, queue);

        ngx_http_lua_socket_tcp_close_connection(item->connection);

        /* only decrease the counter for connections which were counted */
        if (u->socket_pool != NULL) {
            u->socket_pool->connections--;
        }

    } else {
        q = ngx_queue_head(&spool->free);
        ngx_queue_remove(q);

        item = ngx_queue_data(q, ngx_http_lua_socket_pool_item_t, queue);

        /* we should always increase connections after getting connected,
         * and decrease connections after getting closed.
         * however, we don't create connection pool in previous connect method.
         * so we increase connections here for backward compatibility.
         */
        if (u->socket_pool == NULL) {
            spool->connections++;
        }
    }

    item->connection = c;
    ngx_queue_insert_head(&spool->cache, q);

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

    if (n >= 2 && !lua_isnil(L, 2)) {
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
    c->pool->log = ngx_cycle->log;
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

    /* since we set u->peer->connection to NULL previously, the connect
     * operation won't be resumed in the ngx_http_lua_socket_tcp_finalize.
     * Therefore we need to resume it here.
     */
    ngx_http_lua_socket_tcp_resume_conn_op(spool);

    lua_pushinteger(L, 1);
    return 1;
}


static ngx_int_t
ngx_http_lua_get_keepalive_peer(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_http_lua_socket_pool_item_t     *item;
    ngx_http_lua_socket_pool_t          *spool;
    ngx_http_cleanup_t                  *cln;
    ngx_queue_t                         *q;
    ngx_peer_connection_t               *pc;
    ngx_connection_t                    *c;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket pool get keepalive peer");

    pc = &u->peer;
    spool = u->socket_pool;

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
        c->pool->log = pc->log;
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
            cln = ngx_http_lua_cleanup_add(r, 0);
            if (cln == NULL) {
                u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
                return NGX_ERROR;
            }

            cln->handler = ngx_http_lua_socket_tcp_cleanup;
            cln->data = u;
            u->cleanup = &cln->handler;
        }

        return NGX_OK;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua tcp socket keepalive: connection pool empty");

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

    ngx_http_lua_socket_tcp_close_connection(c);

    ngx_queue_remove(&item->queue);
    ngx_queue_insert_head(&spool->free, &item->queue);
    spool->connections--;

    dd("keepalive: connections: %u", (unsigned) spool->connections);

    if (spool->connections == 0) {
        ngx_http_lua_socket_free_pool(ev->log, spool);

    } else {
        ngx_http_lua_socket_tcp_resume_conn_op(spool);
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

    L = spool->lua_vm;

    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(socket_pool_key));
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushstring(L, (char *) spool->key);
    lua_pushnil(L);
    lua_rawset(L, -3);
    lua_pop(L, 1);
}


static void
ngx_http_lua_socket_shutdown_pool_helper(ngx_http_lua_socket_pool_t *spool)
{
    ngx_queue_t                             *q;
    ngx_connection_t                        *c;
    ngx_http_lua_socket_pool_item_t         *item;
    ngx_http_lua_socket_tcp_conn_op_ctx_t   *conn_op_ctx;

    while (!ngx_queue_empty(&spool->cache)) {
        q = ngx_queue_head(&spool->cache);

        item = ngx_queue_data(q, ngx_http_lua_socket_pool_item_t, queue);
        c = item->connection;

        ngx_http_lua_socket_tcp_close_connection(c);

        ngx_queue_remove(q);
        ngx_queue_insert_head(&spool->free, q);
    }

    while (!ngx_queue_empty(&spool->cache_connect_op)) {
        q = ngx_queue_head(&spool->cache_connect_op);
        ngx_queue_remove(q);
        conn_op_ctx = ngx_queue_data(q, ngx_http_lua_socket_tcp_conn_op_ctx_t,
                                     queue);
        ngx_http_lua_socket_tcp_free_conn_op_ctx(conn_op_ctx);
    }

    while (!ngx_queue_empty(&spool->wait_connect_op)) {
        q = ngx_queue_head(&spool->wait_connect_op);
        ngx_queue_remove(q);
        conn_op_ctx = ngx_queue_data(q, ngx_http_lua_socket_tcp_conn_op_ctx_t,
                                     queue);

        if (conn_op_ctx->event.timer_set) {
            ngx_del_timer(&conn_op_ctx->event);
        }

        ngx_http_lua_socket_tcp_free_conn_op_ctx(conn_op_ctx);
    }

    /* spool->connections will be decreased down to zero in
     * ngx_http_lua_socket_tcp_finalize */
}


static int
ngx_http_lua_socket_shutdown_pool(lua_State *L)
{
    ngx_http_lua_socket_pool_t          *spool;

    spool = lua_touserdata(L, 1);

    if (spool != NULL) {
        ngx_http_lua_socket_shutdown_pool_helper(spool);
    }

    return 0;
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

    dd("downstream destroy");

    u = lua_touserdata(L, 1);
    if (u == NULL) {
        dd("u is NULL");
        return 0;
    }

    if (u->cleanup) {
        ngx_http_lua_socket_tcp_cleanup(u); /* it will clear u->cleanup */
    }

    return 0;
}


static ngx_int_t
ngx_http_lua_socket_push_input_data(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_http_lua_socket_tcp_upstream_t *u,
    lua_State *L)
{
    ngx_chain_t             *cl;
    ngx_chain_t            **ll;
#if (DDEBUG) || (NGX_DTRACE)
    size_t                   size = 0;
#endif
    size_t                   chunk_size;
    ngx_buf_t               *b;
    size_t                   nbufs;
    luaL_Buffer              luabuf;

    dd("bufs_in: %p, buf_in: %p", u->bufs_in, u->buf_in);

    nbufs = 0;
    ll = NULL;

    luaL_buffinit(L, &luabuf);

    for (cl = u->bufs_in; cl; cl = cl->next) {
        b = cl->buf;
        chunk_size = b->last - b->pos;

        dd("copying input data chunk from %p: \"%.*s\"", cl,
           (int) chunk_size, b->pos);

        luaL_addlstring(&luabuf, (char *) b->pos, chunk_size);

        if (cl->next) {
            ll = &cl->next;
        }

#if (DDEBUG) || (NGX_DTRACE)
        size += chunk_size;
#endif

        nbufs++;
    }

    luaL_pushresult(&luabuf);

#if (DDEBUG)
    dd("size: %d, nbufs: %d", (int) size, (int) nbufs);
#endif

#if (NGX_DTRACE)
    ngx_http_lua_probe_socket_tcp_receive_done(r, u,
                                               (u_char *) lua_tostring(L, -1),
                                               size);
#endif

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

    if (u->bufs_in) {
        u->buf_in->buf->last = u->buffer.pos;
        u->buf_in->buf->pos = u->buffer.pos;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_socket_add_input_buffer(ngx_http_request_t *r,
    ngx_http_lua_socket_tcp_upstream_t *u)
{
    ngx_chain_t             *cl;
    ngx_http_lua_ctx_t      *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    cl = ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                         &ctx->free_recv_bufs,
                                         u->conf->buffer_size);

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

    new_cl = ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                             &ctx->free_recv_bufs,
                                             size);

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
ngx_http_lua_socket_tcp_conn_op_resume(ngx_http_request_t *r)
{
    return ngx_http_lua_socket_tcp_resume_helper(r, SOCKET_OP_RESUME_CONN);
}


static ngx_int_t
ngx_http_lua_socket_tcp_conn_resume(ngx_http_request_t *r)
{
    return ngx_http_lua_socket_tcp_resume_helper(r, SOCKET_OP_CONNECT);
}


static ngx_int_t
ngx_http_lua_socket_tcp_read_resume(ngx_http_request_t *r)
{
    return ngx_http_lua_socket_tcp_resume_helper(r, SOCKET_OP_READ);
}


static ngx_int_t
ngx_http_lua_socket_tcp_write_resume(ngx_http_request_t *r)
{
    return ngx_http_lua_socket_tcp_resume_helper(r, SOCKET_OP_WRITE);
}


static ngx_int_t
ngx_http_lua_socket_tcp_resume_helper(ngx_http_request_t *r, int socket_op)
{
    int                                    nret;
    lua_State                             *vm;
    ngx_int_t                              rc;
    ngx_uint_t                             nreqs;
    ngx_connection_t                      *c;
    ngx_http_lua_ctx_t                    *ctx;
    ngx_http_lua_co_ctx_t                 *coctx;
    ngx_http_lua_socket_tcp_conn_op_ctx_t *conn_op_ctx;

    ngx_http_lua_socket_tcp_retval_handler  prepare_retvals;

    ngx_http_lua_socket_tcp_upstream_t      *u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp operation done, resuming lua thread");

    coctx = ctx->cur_co_ctx;

    dd("coctx: %p", coctx);

    switch (socket_op) {

    case SOCKET_OP_RESUME_CONN:
        conn_op_ctx = coctx->data;
        u = conn_op_ctx->u;
        prepare_retvals = u->write_prepare_retvals;
        break;

    case SOCKET_OP_CONNECT:
    case SOCKET_OP_WRITE:
        u = coctx->data;
        prepare_retvals = u->write_prepare_retvals;
        break;

    case SOCKET_OP_READ:
        u = coctx->data;
        prepare_retvals = u->read_prepare_retvals;
        break;

    default:
        /* impossible to reach here */
        return NGX_ERROR;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket calling prepare retvals handler %p, "
                   "u:%p", prepare_retvals, u);

    nret = prepare_retvals(r, u, ctx->cur_co_ctx->co);
    if (socket_op == SOCKET_OP_CONNECT
        && nret > 1
        && !u->conn_closed
        && u->socket_pool != NULL)
    {
        u->socket_pool->connections--;
        ngx_http_lua_socket_tcp_resume_conn_op(u->socket_pool);
    }

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
ngx_http_lua_tcp_queue_conn_op_cleanup(void *data)
{
    ngx_http_lua_co_ctx_t                  *coctx = data;
    ngx_http_lua_socket_tcp_upstream_t     *u;
    ngx_http_lua_socket_tcp_conn_op_ctx_t  *conn_op_ctx;

    conn_op_ctx = coctx->data;
    u = conn_op_ctx->u;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua tcp socket abort queueing, conn_op_ctx: %p, u: %p",
                   conn_op_ctx, u);

    if (conn_op_ctx->event.posted) {
        ngx_delete_posted_event(&conn_op_ctx->event);

    } else if (conn_op_ctx->event.timer_set) {
        ngx_del_timer(&conn_op_ctx->event);
    }

    ngx_queue_remove(&conn_op_ctx->queue);
    ngx_queue_insert_head(&u->socket_pool->cache_connect_op,
                          &conn_op_ctx->queue);

    u->socket_pool->connections--;
    ngx_http_lua_socket_tcp_resume_conn_op(u->socket_pool);
}


static void
ngx_http_lua_tcp_resolve_cleanup(void *data)
{
    ngx_resolver_ctx_t                      *rctx;
    ngx_http_lua_socket_tcp_upstream_t      *u;
    ngx_http_lua_co_ctx_t                   *coctx = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua tcp socket abort resolver");

    u = coctx->data;
    if (u == NULL) {
        return;
    }

    if (u->socket_pool != NULL) {
        u->socket_pool->connections--;
        ngx_http_lua_socket_tcp_resume_conn_op(u->socket_pool);
    }

    rctx = u->resolved->ctx;
    if (rctx == NULL) {
        return;
    }

    /* just to be safer */
    rctx->handler = ngx_http_lua_socket_empty_resolve_handler;

    ngx_resolve_name_done(rctx);
}


static void
ngx_http_lua_coctx_cleanup(void *data)
{
    ngx_http_lua_socket_tcp_upstream_t      *u;
    ngx_http_lua_co_ctx_t                   *coctx = data;

    dd("running coctx cleanup");

    u = coctx->data;
    if (u == NULL) {
        return;
    }

    if (u->request == NULL) {
        return;
    }

    ngx_http_lua_socket_tcp_finalize(u->request, u);
}


#if (NGX_HTTP_SSL)

static int
ngx_http_lua_ssl_free_session(lua_State *L)
{
    ngx_ssl_session_t      **psession;

    psession = lua_touserdata(L, 1);
    if (psession && *psession != NULL) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua ssl free session: %p", *psession);

        ngx_ssl_free_session(*psession);
    }

    return 0;
}

#endif  /* NGX_HTTP_SSL */


void
ngx_http_lua_cleanup_conn_pools(lua_State *L)
{
    ngx_http_lua_socket_pool_t          *spool;

    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          socket_pool_key));
    lua_rawget(L, LUA_REGISTRYINDEX); /* table */

    lua_pushnil(L);  /* first key */
    while (lua_next(L, -2) != 0) {
        /* tb key val */
        spool = lua_touserdata(L, -1);

        if (spool != NULL) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "lua tcp socket keepalive: free connection pool %p "
                           "for \"%s\"", spool, spool->key);

            ngx_http_lua_socket_shutdown_pool_helper(spool);
        }

        lua_pop(L, 1);
    }

    lua_pop(L, 1);
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
