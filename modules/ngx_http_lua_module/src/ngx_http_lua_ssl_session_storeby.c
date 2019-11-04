
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#if (NGX_HTTP_SSL)


#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_ssl_module.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_ssl_session_storeby.h"
#include "ngx_http_lua_ssl.h"
#include "ngx_http_lua_directive.h"


/* Lua SSL new session store routines */
static u_char *ngx_http_lua_log_ssl_sess_store_error(ngx_log_t *log,
    u_char *buf, size_t len);
static ngx_int_t ngx_http_lua_ssl_sess_store_by_chunk(lua_State *L,
    ngx_http_request_t *r);


/* load Lua code from a file for caching new SSL session. */
ngx_int_t
ngx_http_lua_ssl_sess_store_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadfile(r->connection->log, L,
                                     lscf->srv.ssl_sess_store_src.data,
                                     lscf->srv.ssl_sess_store_src_key);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_ssl_sess_store_by_chunk(L, r);
}


/* load lua code from an inline snippet for caching new SSL session */
ngx_int_t
ngx_http_lua_ssl_sess_store_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       lscf->srv.ssl_sess_store_src.data,
                                       lscf->srv.ssl_sess_store_src.len,
                                       lscf->srv.ssl_sess_store_src_key,
                                       "=ssl_session_store_by_lua_block");
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_ssl_sess_store_by_chunk(L, r);
}


char *
ngx_http_lua_ssl_sess_store_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_ssl_sess_store_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


/* conf parser for directive ssl_session_store_by_lua */
char *
ngx_http_lua_ssl_sess_store_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *p;
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_srv_conf_t     *lscf = conf;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lscf->srv.ssl_sess_store_handler) {
        return "is duplicate";
    }

    if (ngx_http_lua_ssl_init(cf->log) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;

    lscf->srv.ssl_sess_store_handler =
        (ngx_http_lua_srv_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_ssl_sess_store_handler_file) {
        /* Lua code in an external file */

        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->srv.ssl_sess_store_src.data = name;
        lscf->srv.ssl_sess_store_src.len = ngx_strlen(name);

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->srv.ssl_sess_store_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

    } else {
        /* inlined Lua code */

        lscf->srv.ssl_sess_store_src = value[1];

        p = ngx_palloc(cf->pool,
                       sizeof("ssl_session_store_by_lua") +
                       NGX_HTTP_LUA_INLINE_KEY_LEN);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->srv.ssl_sess_store_src_key = p;

        p = ngx_copy(p, "ssl_session_store_by_lua",
                     sizeof("ssl_session_store_by_lua") - 1);
        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';
    }

    return NGX_CONF_OK;
}


/* callback for new session caching, to be set with SSL_CTX_sess_set_new_cb */
int
ngx_http_lua_ssl_sess_store_handler(ngx_ssl_conn_t *ssl_conn,
    ngx_ssl_session_t *sess)
{
    const u_char                    *sess_id;
    unsigned int                     sess_id_len;
    lua_State                       *L;
    ngx_int_t                        rc;
    ngx_connection_t                *c, *fc = NULL;
    ngx_http_request_t              *r = NULL;
    ngx_http_connection_t           *hc;
    ngx_http_lua_ssl_ctx_t          *cctx;
    ngx_http_lua_srv_conf_t         *lscf;
    ngx_http_core_loc_conf_t        *clcf;

    c = ngx_ssl_get_connection(ssl_conn);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "ssl session store: connection reusable: %ud", c->reusable);

    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);

    dd("ssl sess_store handler, sess_store-ctx=%p", cctx);

    hc = c->data;

    fc = ngx_http_lua_create_fake_connection(NULL);
    if (fc == NULL) {
        goto failed;
    }

    fc->log->handler = ngx_http_lua_log_ssl_sess_store_error;
    fc->log->data = fc;

    fc->addr_text = c->addr_text;
    fc->listening = c->listening;

    r = ngx_http_lua_create_fake_request(fc);
    if (r == NULL) {
        goto failed;
    }

    r->main_conf = hc->conf_ctx->main_conf;
    r->srv_conf = hc->conf_ctx->srv_conf;
    r->loc_conf = hc->conf_ctx->loc_conf;

    fc->log->file = c->log->file;
    fc->log->log_level = c->log->log_level;
    fc->ssl = c->ssl;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

#if defined(nginx_version) && nginx_version >= 1003014

#   if nginx_version >= 1009000

    ngx_set_connection_log(fc, clcf->error_log);

#   else

    ngx_http_set_connection_log(fc, clcf->error_log);

#   endif

#else

    fc->log->file = clcf->error_log->file;

    if (!(fc->log->log_level & NGX_LOG_DEBUG_CONNECTION)) {
        fc->log->log_level = clcf->error_log->log_level;
    }

#endif

    if (cctx == NULL) {
        cctx = ngx_pcalloc(c->pool, sizeof(ngx_http_lua_ssl_ctx_t));
        if (cctx == NULL) {
            goto failed;  /* error */
        }
    }

#if OPENSSL_VERSION_NUMBER >= 0x1000200fL
    sess_id = SSL_SESSION_get_id(sess, &sess_id_len);
#else
    sess_id = sess->session_id;
    sess_id_len = sess->session_id_length;
#endif

    cctx->connection = c;
    cctx->request = r;
    cctx->session = sess;
    cctx->session_id.data = (u_char *) sess_id;
    cctx->session_id.len = sess_id_len;
    cctx->done = 0;

    dd("setting cctx");

    if (SSL_set_ex_data(c->ssl->connection, ngx_http_lua_ssl_ctx_index, cctx)
        == 0)
    {
        ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "SSL_set_ex_data() failed");
        goto failed;
    }

    lscf = ngx_http_get_module_srv_conf(r, ngx_http_lua_module);

    /* TODO honor lua_code_cache off */
    L = ngx_http_lua_get_lua_vm(r, NULL);

    c->log->action = "storing SSL session by lua";

    rc = lscf->srv.ssl_sess_store_handler(r, lscf, L);

    if (rc >= NGX_OK || rc == NGX_ERROR) {
        cctx->done = 1;

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "ssl_session_store_by_lua*: handler return value: %i, "
                       "sess new cb exit code: %d", rc, cctx->exit_code);

        c->log->action = "SSL handshaking";

        /* Return value is a flag indicating whether the passed-in session
         * has been freed by this callback; always return 0 so OpenSSL will
         * free the session. Nginx's own session caching logic has the same
         * practice. */
        return 0;
    }

    /* impossible to reach here */
    ngx_http_lua_assert(0);

failed:

    if (r && r->pool) {
        ngx_http_lua_free_fake_request(r);
    }

    if (fc) {
        ngx_http_lua_close_fake_connection(fc);
    }

    return 0;
}


static u_char *
ngx_http_lua_log_ssl_sess_store_error(ngx_log_t *log, u_char *buf, size_t len)
{
    u_char              *p;
    ngx_connection_t    *c;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    p = ngx_snprintf(buf, len, ", context: ssl_session_store_by_lua*");
    len -= p - buf;
    buf = p;

    c = log->data;

    if (c->addr_text.len) {
        p = ngx_snprintf(buf, len, ", client: %V", &c->addr_text);
        len -= p - buf;
        buf = p;
    }

    if (c && c->listening && c->listening->addr_text.len) {
        p = ngx_snprintf(buf, len, ", server: %V", &c->listening->addr_text);
        buf = p;
    }

    return buf;
}


/* initialize lua coroutine for caching new SSL session */
static ngx_int_t
ngx_http_lua_ssl_sess_store_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    size_t                   len;
    u_char                  *err_msg;
    ngx_int_t                rc;
    ngx_http_lua_ctx_t      *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            rc = NGX_ERROR;
            ngx_http_lua_finalize_request(r, rc);
            return rc;
        }

    } else {
        dd("reset ctx");
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    ctx->entered_content_phase = 1;
    ctx->context = NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE;

    /* init nginx context in Lua VM */
    ngx_http_lua_set_req(L, r);

#ifndef OPENRESTY_LUAJIT
    ngx_http_lua_create_new_globals_table(L, 0 /* narr */, 1 /* nrec */);

    /*  {{{ make new env inheriting main thread's globals table */
    lua_createtable(L, 0, 1 /* nrec */);   /* the metatable for the new env */
    ngx_http_lua_get_globals_table(L);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
#endif

    lua_pushcfunction(L, ngx_http_lua_traceback);
    lua_insert(L, 1);  /* put it under chunk and args */

    /*  protected call user code */
    rc = lua_pcall(L, 0, 1, 1);

    lua_remove(L, 1);  /* remove traceback function */

    dd("rc == %d", (int) rc);

    if (rc != 0) {
        /*  error occurred when running loaded code */
        err_msg = (u_char *) lua_tolstring(L, -1, &len);

        if (err_msg == NULL) {
            err_msg = (u_char *) "unknown reason";
            len = sizeof("unknown reason") - 1;
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to run session_store_by_lua*: %*s", len, err_msg);

        lua_settop(L, 0); /*  clear remaining elems on stack */
        ngx_http_lua_finalize_request(r, rc);

        return NGX_ERROR;
    }

    lua_settop(L, 0); /*  clear remaining elems on stack */
    ngx_http_lua_finalize_request(r, rc);
    return rc;
}


#ifndef NGX_LUA_NO_FFI_API

/* serialize a session from lua context into buf.
 * the memory allocation of buf should be handled externally. */
int
ngx_http_lua_ffi_ssl_get_serialized_session(ngx_http_request_t *r,
    u_char *buf, char **err)
{
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_connection_t                *c;
    ngx_ssl_session_t               *session;
    ngx_http_lua_ssl_ctx_t          *cctx;

    c = r->connection;

    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("get cctx session");

    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    session = cctx->session;
    if (session == NULL) {
        *err = "bad session in lua context";
        return NGX_ERROR;
    }

    if (i2d_SSL_SESSION(session, &buf) == 0) {
        *err = "i2d_SSL_SESSION() failed";
        return NGX_ERROR;
    }

    return NGX_OK;
}


/* return the size of serialized session. */
int
ngx_http_lua_ffi_ssl_get_serialized_session_size(ngx_http_request_t *r,
    char **err)
{
    int                              len;
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_connection_t                *c;
    ngx_ssl_session_t               *session;
    ngx_http_lua_ssl_ctx_t          *cctx;

    c = r->connection;

    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("get cctx session size");
    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    session = cctx->session;
    if (session == NULL) {
        *err = "bad session in lua context";
        return NGX_ERROR;
    }

    len = i2d_SSL_SESSION(session, NULL);
    if (len == 0) {
        *err = "i2d_SSL_SESSION() failed";
        return NGX_ERROR;
    }

    return len;
}


/* serialize the session id from lua context into buf.
 * the memory allocation of buf should be handled externally. */
int
ngx_http_lua_ffi_ssl_get_session_id(ngx_http_request_t *r,
    u_char *buf, char **err)
{
    int                              id_len;
    u_char                          *id;
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_connection_t                *c;
    ngx_http_lua_ssl_ctx_t          *cctx;

    c = r->connection;

    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("get cctx session");
    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    id = cctx->session_id.data;
    if (id == NULL) {
        *err = "uninitialized session id in lua context";
        return NGX_ERROR;
    }

    id_len = cctx->session_id.len;
    if (id_len == 0) {
        *err = "uninitialized session id len in lua context";
        return NGX_ERROR;
    }

    ngx_hex_dump(buf, id, id_len);

    return NGX_OK;
}


/* return the size of serialized session id. */
int
ngx_http_lua_ffi_ssl_get_session_id_size(ngx_http_request_t *r,
    char **err)
{
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_connection_t                *c;
    ngx_http_lua_ssl_ctx_t          *cctx;

    c = r->connection;

    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("get cctx session");
    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    if (cctx->session_id.len == 0) {
        *err = "uninitialized session id len in lua context";
        return NGX_ERROR;
    }

    /* since the session id will be hex dumped to serialize, the serialized
     * session will be twice the size of the session id: each byte will be a
     * 2-digit hex value. */

    return 2 * cctx->session_id.len;
}

#endif  /* NGX_LUA_NO_FFI_API */


#endif /* NGX_HTTP_SSL */
