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
#include "ngx_http_lua_ssl_client_helloby.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_ssl.h"


static void ngx_http_lua_ssl_client_hello_done(void *data);
static void ngx_http_lua_ssl_client_hello_aborted(void *data);
static u_char *ngx_http_lua_log_ssl_client_hello_error(ngx_log_t *log,
    u_char *buf, size_t len);
static ngx_int_t ngx_http_lua_ssl_client_hello_by_chunk(lua_State *L,
    ngx_http_request_t *r);


ngx_int_t
ngx_http_lua_ssl_client_hello_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadfile(r->connection->log, L,
                                     lscf->srv.ssl_client_hello_src.data,
                                     &lscf->srv.ssl_client_hello_src_ref,
                                     lscf->srv.ssl_client_hello_src_key);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_ssl_client_hello_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_ssl_client_hello_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       lscf->srv.ssl_client_hello_src.data,
                                       lscf->srv.ssl_client_hello_src.len,
                                       &lscf->srv.ssl_client_hello_src_ref,
                                       lscf->srv.ssl_client_hello_src_key,
                           (const char *) lscf->srv.ssl_client_hello_chunkname);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_ssl_client_hello_by_chunk(L, r);
}


char *
ngx_http_lua_ssl_client_hello_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_ssl_client_hello_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_ssl_client_hello_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
#ifndef SSL_ERROR_WANT_CLIENT_HELLO_CB

    ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                  "at least OpenSSL 1.1.1 required but found "
                  OPENSSL_VERSION_TEXT);

    return NGX_CONF_ERROR;

#else

    size_t                       chunkname_len;
    u_char                      *chunkname;
    u_char                      *cache_key = NULL;
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_srv_conf_t     *lscf = conf;

    /*  must specify a concrete handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lscf->srv.ssl_client_hello_handler) {
        return "is duplicate";
    }

    if (ngx_http_lua_ssl_init(cf->log) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;

    lscf->srv.ssl_client_hello_handler =
        (ngx_http_lua_srv_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_ssl_client_hello_handler_file) {
        /* Lua code in an external file */

        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                    value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->srv.ssl_client_hello_src.data = name;
        lscf->srv.ssl_client_hello_src.len = ngx_strlen(name);

    } else {
        cache_key = ngx_http_lua_gen_chunk_cache_key(cf,
                                                     "ssl_client_hello_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        chunkname = ngx_http_lua_gen_chunk_name(cf, "ssl_client_hello_by_lua",
                                          sizeof("ssl_client_hello_by_lua")- 1,
                                          &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        lscf->srv.ssl_client_hello_src = value[1];
        lscf->srv.ssl_client_hello_chunkname = chunkname;
    }

    lscf->srv.ssl_client_hello_src_key = cache_key;

    return NGX_CONF_OK;

#endif  /* NO SSL_ERROR_WANT_CLIENT_HELLO_CB */
}


int
ngx_http_lua_ssl_client_hello_handler(ngx_ssl_conn_t *ssl_conn,
    int *al, void *arg)
{
    lua_State                       *L;
    ngx_int_t                        rc;
    ngx_connection_t                *c, *fc;
    ngx_http_request_t              *r = NULL;
    ngx_pool_cleanup_t              *cln;
    ngx_http_connection_t           *hc;
    ngx_http_lua_srv_conf_t         *lscf;
    ngx_http_core_loc_conf_t        *clcf;
    ngx_http_lua_ssl_ctx_t          *cctx;
    ngx_http_core_srv_conf_t        *cscf;

    c = ngx_ssl_get_connection(ssl_conn);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "ssl client hello: connection reusable: %ud", c->reusable);

    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);

    dd("ssl client hello handler, client-hello-ctx=%p", cctx);

    if (cctx && cctx->entered_client_hello_handler) {
        /* not the first time */

        if (cctx->done) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "lua_client_hello_by_lua: "
                           "client hello cb exit code: %d",
                           cctx->exit_code);

            dd("lua ssl client hello done, finally");
            return cctx->exit_code;
        }

        return -1;
    }

    dd("first time");

#if (nginx_version < 1017009)
    ngx_reusable_connection(c, 0);
#endif

    hc = c->data;

    fc = ngx_http_lua_create_fake_connection(NULL);
    if (fc == NULL) {
        goto failed;
    }

    fc->log->handler = ngx_http_lua_log_ssl_client_hello_error;
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


#if nginx_version >= 1009000
    ngx_set_connection_log(fc, clcf->error_log);
#else
    ngx_http_set_connection_log(fc, clcf->error_log);
#endif

    if (cctx == NULL) {
        cctx = ngx_pcalloc(c->pool, sizeof(ngx_http_lua_ssl_ctx_t));
        if (cctx == NULL) {
            goto failed;  /* error */
        }

        cctx->ctx_ref = LUA_NOREF;
    }

    cctx->exit_code = 1;  /* successful by default */
    cctx->connection = c;
    cctx->request = r;
    cctx->entered_client_hello_handler = 1;
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

    c->log->action = "loading SSL client hello by lua";

    if (lscf->srv.ssl_client_hello_handler == NULL) {
        cscf = ngx_http_get_module_srv_conf(r, ngx_http_core_module);

        ngx_log_error(NGX_LOG_ALERT, c->log, 0,
                      "no ssl_client_hello_by_lua* defined in "
                      "server %V", &cscf->server_name);

        goto failed;
    }

    rc = lscf->srv.ssl_client_hello_handler(r, lscf, L);

    if (rc >= NGX_OK || rc == NGX_ERROR) {
        cctx->done = 1;

        if (cctx->cleanup) {
            *cctx->cleanup = NULL;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua_client_hello_by_lua: handler return value: %i, "
                       "client hello cb exit code: %d", rc, cctx->exit_code);

        c->log->action = "SSL handshaking";
        return cctx->exit_code;
    }

    /* rc == NGX_DONE */

    cln = ngx_pool_cleanup_add(fc->pool, 0);
    if (cln == NULL) {
        goto failed;
    }

    cln->handler = ngx_http_lua_ssl_client_hello_done;
    cln->data = cctx;

    if (cctx->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(c->pool, 0);
        if (cln == NULL) {
            goto failed;
        }

        cln->data = cctx;
        cctx->cleanup = &cln->handler;
    }

    *cctx->cleanup = ngx_http_lua_ssl_client_hello_aborted;

    return -1;

#if 1
failed:

    if (r && r->pool) {
        ngx_http_lua_free_fake_request(r);
    }

    if (fc) {
        ngx_http_lua_close_fake_connection(fc);
    }

    return 0;
#endif
}


static void
ngx_http_lua_ssl_client_hello_done(void *data)
{
    ngx_connection_t                *c;
    ngx_http_lua_ssl_ctx_t          *cctx = data;

    dd("lua ssl client hello done");

    if (cctx->aborted) {
        return;
    }

    ngx_http_lua_assert(cctx->done == 0);

    cctx->done = 1;

    if (cctx->cleanup) {
        *cctx->cleanup = NULL;
    }

    c = cctx->connection;

    c->log->action = "SSL handshaking";

    ngx_post_event(c->write, &ngx_posted_events);
}


static void
ngx_http_lua_ssl_client_hello_aborted(void *data)
{
    ngx_http_lua_ssl_ctx_t      *cctx = data;

    dd("lua ssl client hello done");

    if (cctx->done) {
        /* completed successfully already */
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cctx->connection->log, 0,
                   "lua_client_hello_by_lua: client hello cb aborted");

    cctx->aborted = 1;
    cctx->request->connection->ssl = NULL;

    ngx_http_lua_finalize_fake_request(cctx->request, NGX_ERROR);
}


static u_char *
ngx_http_lua_log_ssl_client_hello_error(ngx_log_t *log,
    u_char *buf, size_t len)
{
    u_char              *p;
    ngx_connection_t    *c;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    p = ngx_snprintf(buf, len, ", context: ssl_client_hello_by_lua*");
    len -= p - buf;
    buf = p;

    c = log->data;

    if (c && c->addr_text.len) {
        p = ngx_snprintf(buf, len, ", client: %V", &c->addr_text);
        len -= p - buf;
        buf = p;
    }

    if (c && c->listening && c->listening->addr_text.len) {
        p = ngx_snprintf(buf, len, ", server: %V", &c->listening->addr_text);
        /* len -= p - buf; */
        buf = p;
    }

    return buf;
}


static ngx_int_t
ngx_http_lua_ssl_client_hello_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    int                      co_ref;
    ngx_int_t                rc;
    lua_State               *co;
    ngx_http_lua_ctx_t      *ctx;
    ngx_pool_cleanup_t      *cln;

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

    /*  {{{ new coroutine to handle request */
    co = ngx_http_lua_new_thread(r, L, &co_ref);

    if (co == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "lua: failed to create new coroutine to handle request");

        rc = NGX_ERROR;
        ngx_http_lua_finalize_request(r, rc);
        return rc;
    }

    /*  move code closure to new coroutine */
    lua_xmove(L, co, 1);

#ifndef OPENRESTY_LUAJIT
    /*  set closure's env table to new coroutine's globals table */
    ngx_http_lua_get_globals_table(co);
    lua_setfenv(co, -2);
#endif

    /* save nginx request in coroutine globals table */
    ngx_http_lua_set_req(co, r);

    ctx->cur_co_ctx = &ctx->entry_co_ctx;
    ctx->cur_co_ctx->co = co;
    ctx->cur_co_ctx->co_ref = co_ref;
#ifdef NGX_LUA_USE_ASSERT
    ctx->cur_co_ctx->co_top = 1;
#endif

    ngx_http_lua_attach_co_ctx_to_L(co, ctx->cur_co_ctx);

    /* register request cleanup hooks */
    if (ctx->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(r->pool, 0);
        if (cln == NULL) {
            rc = NGX_ERROR;
            ngx_http_lua_finalize_request(r, rc);
            return rc;
        }

        cln->handler = ngx_http_lua_request_cleanup_handler;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_SSL_CLIENT_HELLO;

    rc = ngx_http_lua_run_thread(L, r, ctx, 0);

    if (rc == NGX_ERROR || rc >= NGX_OK) {
        /* do nothing */

    } else if (rc == NGX_AGAIN) {
        rc = ngx_http_lua_content_run_posted_threads(L, r, ctx, 0);

    } else if (rc == NGX_DONE) {
        rc = ngx_http_lua_content_run_posted_threads(L, r, ctx, 1);

    } else {
        rc = NGX_OK;
    }

    ngx_http_lua_finalize_request(r, rc);
    return rc;
}


int
ngx_http_lua_ffi_ssl_get_client_hello_server_name(ngx_http_request_t *r,
    const char **name, size_t *namelen, char **err)
{
    ngx_ssl_conn_t          *ssl_conn;
#ifdef SSL_ERROR_WANT_CLIENT_HELLO_CB
    const unsigned char     *p;
    size_t                   remaining, len;
#endif

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

#ifdef SSL_CTRL_SET_TLSEXT_HOSTNAME

#ifdef SSL_ERROR_WANT_CLIENT_HELLO_CB
    remaining = 0;

    /* This code block is taken from OpenSSL's client_hello_select_server_ctx()
     * */
    if (!SSL_client_hello_get0_ext(ssl_conn, TLSEXT_TYPE_server_name, &p,
                                   &remaining))
    {
        return NGX_DECLINED;
    }

    if (remaining <= 2) {
        *err = "Bad SSL Client Hello Extension";
        return NGX_ERROR;
    }

    len = (*(p++) << 8);
    len += *(p++);
    if (len + 2 != remaining) {
        *err = "Bad SSL Client Hello Extension";
        return NGX_ERROR;
    }

    remaining = len;
    if (remaining == 0 || *p++ != TLSEXT_NAMETYPE_host_name) {
        *err = "Bad SSL Client Hello Extension";
        return NGX_ERROR;
    }

    remaining--;
    if (remaining <= 2) {
        *err = "Bad SSL Client Hello Extension";
        return NGX_ERROR;
    }

    len = (*(p++) << 8);
    len += *(p++);
    if (len + 2 > remaining) {
        *err = "Bad SSL Client Hello Extension";
        return NGX_ERROR;
    }

    remaining = len;
    *name = (const char *) p;
    *namelen = len;

    return NGX_OK;

#else
    *err = "OpenSSL too old to support this function";
    return NGX_ERROR;

#endif

#else

    *err = "no TLS extension support";
    return NGX_ERROR;
#endif
}


int
ngx_http_lua_ffi_ssl_get_client_hello_ext(ngx_http_request_t *r,
    unsigned int type, const unsigned char **out, size_t *outlen, char **err)
{
    ngx_ssl_conn_t          *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

#ifdef SSL_ERROR_WANT_CLIENT_HELLO_CB
    if (SSL_client_hello_get0_ext(ssl_conn, type, out, outlen) == 0) {
        return NGX_DECLINED;
    }

    return NGX_OK;
#else
    *err = "OpenSSL too old to support this function";
    return NGX_ERROR;
#endif

}


int
ngx_http_lua_ffi_ssl_set_protocols(ngx_http_request_t *r,
    int protocols, char **err)
{

    ngx_ssl_conn_t    *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

#if OPENSSL_VERSION_NUMBER >= 0x009080dfL
    /* only in 0.9.8m+ */
    SSL_clear_options(ssl_conn,
                      SSL_OP_NO_SSLv2|SSL_OP_NO_SSLv3|SSL_OP_NO_TLSv1);
#endif

    if (!(protocols & NGX_SSL_SSLv2)) {
        SSL_set_options(ssl_conn, SSL_OP_NO_SSLv2);
    }

    if (!(protocols & NGX_SSL_SSLv3)) {
        SSL_set_options(ssl_conn, SSL_OP_NO_SSLv3);
    }

    if (!(protocols & NGX_SSL_TLSv1)) {
        SSL_set_options(ssl_conn, SSL_OP_NO_TLSv1);
    }

#ifdef SSL_OP_NO_TLSv1_1
    SSL_clear_options(ssl_conn, SSL_OP_NO_TLSv1_1);
    if (!(protocols & NGX_SSL_TLSv1_1)) {
        SSL_set_options(ssl_conn, SSL_OP_NO_TLSv1_1);
    }
#endif

#ifdef SSL_OP_NO_TLSv1_2
    SSL_clear_options(ssl_conn, SSL_OP_NO_TLSv1_2);
    if (!(protocols & NGX_SSL_TLSv1_2)) {
        SSL_set_options(ssl_conn, SSL_OP_NO_TLSv1_2);
    }
#endif

#ifdef SSL_OP_NO_TLSv1_3
    SSL_clear_options(ssl_conn, SSL_OP_NO_TLSv1_3);
    if (!(protocols & NGX_SSL_TLSv1_3)) {
        SSL_set_options(ssl_conn, SSL_OP_NO_TLSv1_3);
    }
#endif

    return NGX_OK;
}

#endif /* NGX_HTTP_SSL */
