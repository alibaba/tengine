
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_control.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_coroutine.h"


static int ngx_http_lua_ngx_exec(lua_State *L);
static int ngx_http_lua_ngx_redirect(lua_State *L);
static int ngx_http_lua_ngx_exit(lua_State *L);
static int ngx_http_lua_on_abort(lua_State *L);


void
ngx_http_lua_inject_control_api(ngx_log_t *log, lua_State *L)
{
    /* ngx.redirect */

    lua_pushcfunction(L, ngx_http_lua_ngx_redirect);
    lua_setfield(L, -2, "redirect");

    /* ngx.exec */

    lua_pushcfunction(L, ngx_http_lua_ngx_exec);
    lua_setfield(L, -2, "exec");

    lua_pushcfunction(L, ngx_http_lua_ngx_exit);
    lua_setfield(L, -2, "throw_error"); /* deprecated */

    /* ngx.exit */

    lua_pushcfunction(L, ngx_http_lua_ngx_exit);
    lua_setfield(L, -2, "exit");

    /* ngx.on_abort */

    lua_pushcfunction(L, ngx_http_lua_on_abort);
    lua_setfield(L, -2, "on_abort");
}


static int
ngx_http_lua_ngx_exec(lua_State *L)
{
    int                          n;
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_str_t                    uri;
    ngx_str_t                    args, user_args;
    ngx_uint_t                   flags;
    u_char                      *p;
    u_char                      *q;
    size_t                       len;
    const char                  *msg;

    n = lua_gettop(L);
    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting one or two arguments, but got %d",
                          n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ngx_str_null(&args);

    /* read the 1st argument (uri) */

    p = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        return luaL_error(L, "The uri argument is empty");
    }

    uri.data = ngx_palloc(r->pool, len);
    if (uri.data == NULL) {
        return luaL_error(L, "no memory");
    }

    ngx_memcpy(uri.data, p, len);

    uri.len = len;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    ngx_http_lua_check_if_abortable(L, ctx);

    flags = NGX_HTTP_LOG_UNSAFE;

    if (ngx_http_parse_unsafe_uri(r, &uri, &args, &flags) != NGX_OK) {
        return luaL_error(L, "unsafe uri");
    }

    if (n == 2) {
        /* read the 2nd argument (args) */
        dd("args type: %s", luaL_typename(L, 2));

        switch (lua_type(L, 2)) {
        case LUA_TNUMBER:
        case LUA_TSTRING:
            p = (u_char *) lua_tolstring(L, 2, &len);

            user_args.data = ngx_palloc(r->pool, len);
            if (user_args.data == NULL) {
                return luaL_error(L, "no memory");
            }

            ngx_memcpy(user_args.data, p, len);

            user_args.len = len;
            break;

        case LUA_TTABLE:
            ngx_http_lua_process_args_option(r, L, 2, &user_args);

            dd("user_args: %.*s", (int) user_args.len, user_args.data);

            break;

        case LUA_TNIL:
            ngx_str_null(&user_args);
            break;

        default:
            msg = lua_pushfstring(L, "string, number, or table expected, "
                                  "but got %s", luaL_typename(L, 2));
            return luaL_argerror(L, 2, msg);
        }

    } else {
        user_args.data = NULL;
        user_args.len = 0;
    }

    if (user_args.len) {
        if (args.len == 0) {
            args = user_args;

        } else {
            p = ngx_palloc(r->pool, args.len + user_args.len + 1);
            if (p == NULL) {
                return luaL_error(L, "no memory");
            }

            q = ngx_copy(p, args.data, args.len);
            *q++ = '&';
            ngx_memcpy(q, user_args.data, user_args.len);

            args.data = p;
            args.len += user_args.len + 1;
        }
    }

    if (r->header_sent || ctx->header_sent) {
        return luaL_error(L, "attempt to call ngx.exec after "
                          "sending out response headers");
    }

    ctx->exec_uri = uri;
    ctx->exec_args = args;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua exec \"%V?%V\"",
                   &ctx->exec_uri, &ctx->exec_args);

    return lua_yield(L, 0);
}


static int
ngx_http_lua_ngx_redirect(lua_State *L)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;
    int                          n;
    u_char                      *p;
    u_char                      *uri;
    size_t                       len;
    ngx_table_elt_t             *h;
    ngx_http_request_t          *r;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting one or two arguments");
    }

    p = (u_char *) luaL_checklstring(L, 1, &len);

    if (n == 2) {
        rc = (ngx_int_t) luaL_checknumber(L, 2);

        if (rc != NGX_HTTP_MOVED_TEMPORARILY
            && rc != NGX_HTTP_MOVED_PERMANENTLY
            && rc != NGX_HTTP_SEE_OTHER
            && rc != NGX_HTTP_PERMANENT_REDIRECT
            && rc != NGX_HTTP_TEMPORARY_REDIRECT)
        {
            return luaL_error(L, "only ngx.HTTP_MOVED_TEMPORARILY, "
                              "ngx.HTTP_MOVED_PERMANENTLY, "
                              "ngx.HTTP_PERMANENT_REDIRECT, "
                              "ngx.HTTP_SEE_OTHER, and "
                              "ngx.HTTP_TEMPORARY_REDIRECT are allowed");
        }

    } else {
        rc = NGX_HTTP_MOVED_TEMPORARILY;
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    ngx_http_lua_check_if_abortable(L, ctx);

    if (r->header_sent || ctx->header_sent) {
        return luaL_error(L, "attempt to call ngx.redirect after sending out "
                          "the headers");
    }

    uri = ngx_palloc(r->pool, len);
    if (uri == NULL) {
        return luaL_error(L, "no memory");
    }

    ngx_memcpy(uri, p, len);

    h = ngx_list_push(&r->headers_out.headers);
    if (h == NULL) {
        return luaL_error(L, "no memory");
    }

    h->hash = ngx_http_lua_location_hash;

#if 0
    dd("location hash: %lu == %lu",
       (unsigned long) h->hash,
       (unsigned long) ngx_hash_key_lc((u_char *) "Location",
                                       sizeof("Location") - 1));
#endif

    h->value.len = len;
    h->value.data = uri;
    ngx_str_set(&h->key, "Location");

    r->headers_out.status = rc;

    ctx->exit_code = rc;
    ctx->exited = 1;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua redirect to \"%V\" with code %i",
                   &h->value, ctx->exit_code);

    if (len && uri[0] != '/') {
        r->headers_out.location = h;
    }

    /*
     * we do not set r->headers_out.location here to avoid the handling
     * the local redirects without a host name by ngx_http_header_filter()
     */

    return lua_yield(L, 0);
}


static int
ngx_http_lua_ngx_exit(lua_State *L)
{
    ngx_int_t                    rc;
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT
                               | NGX_HTTP_LUA_CONTEXT_TIMER
                               | NGX_HTTP_LUA_CONTEXT_HEADER_FILTER
                               | NGX_HTTP_LUA_CONTEXT_BALANCER
                               | NGX_HTTP_LUA_CONTEXT_SSL_CERT
                               | NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE
                               | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH);

    rc = (ngx_int_t) luaL_checkinteger(L, 1);

    if (ctx->context & (NGX_HTTP_LUA_CONTEXT_SSL_CERT
                        | NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE
                        | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH))
    {

#if (NGX_HTTP_SSL)

        ctx->exit_code = rc;
        ctx->exited = 1;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua exit with code %i", rc);

        if (ctx->context == NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE) {
            return 0;
        }

        return lua_yield(L, 0);

#else

        return luaL_error(L, "no SSL support");

#endif
    }

    if (ctx->no_abort
        && rc != NGX_ERROR
        && rc != NGX_HTTP_CLOSE
        && rc != NGX_HTTP_REQUEST_TIME_OUT
        && rc != NGX_HTTP_CLIENT_CLOSED_REQUEST)
    {
        return luaL_error(L, "attempt to abort with pending subrequests");
    }

    if ((r->header_sent || ctx->header_sent)
        && rc >= NGX_HTTP_SPECIAL_RESPONSE
        && rc != NGX_HTTP_REQUEST_TIME_OUT
        && rc != NGX_HTTP_CLIENT_CLOSED_REQUEST
        && rc != NGX_HTTP_CLOSE)
    {
        if (rc != (ngx_int_t) r->headers_out.status) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "attempt to "
                          "set status %i via ngx.exit after sending out the "
                          "response status %ui", rc, r->headers_out.status);
        }

        rc = NGX_HTTP_OK;
    }

    dd("setting exit code: %d", (int) rc);

    ctx->exit_code = rc;
    ctx->exited = 1;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua exit with code %i", ctx->exit_code);

    if (ctx->context & (NGX_HTTP_LUA_CONTEXT_HEADER_FILTER
                        | NGX_HTTP_LUA_CONTEXT_BALANCER))
    {
        return 0;
    }

    dd("calling yield");
    return lua_yield(L, 0);
}


static int
ngx_http_lua_on_abort(lua_State *L)
{
    ngx_http_request_t           *r;
    ngx_http_lua_ctx_t           *ctx;
    ngx_http_lua_co_ctx_t        *coctx = NULL;
    ngx_http_lua_loc_conf_t      *llcf;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_fake_request2(L, r, ctx);

    if (ctx->on_abort_co_ctx) {
        lua_pushnil(L);
        lua_pushliteral(L, "duplicate call");
        return 2;
    }

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
    if (!llcf->check_client_abort) {
        lua_pushnil(L);
        lua_pushliteral(L, "lua_check_client_abort is off");
        return 2;
    }

    ngx_http_lua_coroutine_create_helper(L, r, ctx, &coctx);

    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          coroutines_key));
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushvalue(L, -2);

    dd("on_wait thread 1: %p", lua_tothread(L, -1));

    coctx->co_ref = luaL_ref(L, -2);
    lua_pop(L, 1);

    coctx->is_uthread = 1;
    ctx->on_abort_co_ctx = coctx;

    dd("on_wait thread 2: %p", coctx->co);

    coctx->co_status = NGX_HTTP_LUA_CO_SUSPENDED;
    coctx->parent_co_ctx = ctx->cur_co_ctx;

    lua_pushinteger(L, 1);
    return 1;
}


#ifndef NGX_LUA_NO_FFI_API
int
ngx_http_lua_ffi_exit(ngx_http_request_t *r, int status, u_char *err,
    size_t *errlen)
{
    ngx_http_lua_ctx_t       *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *errlen = ngx_snprintf(err, *errlen, "no request ctx found") - err;
        return NGX_ERROR;
    }

    if (ngx_http_lua_ffi_check_context(ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                                       | NGX_HTTP_LUA_CONTEXT_ACCESS
                                       | NGX_HTTP_LUA_CONTEXT_CONTENT
                                       | NGX_HTTP_LUA_CONTEXT_TIMER
                                       | NGX_HTTP_LUA_CONTEXT_HEADER_FILTER
                                       | NGX_HTTP_LUA_CONTEXT_BALANCER
                                       | NGX_HTTP_LUA_CONTEXT_SSL_CERT
                                       | NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE
                                       | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH,
                                       err, errlen)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (ctx->context & (NGX_HTTP_LUA_CONTEXT_SSL_CERT
                        | NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE
                        | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH))
    {

#if (NGX_HTTP_SSL)

        ctx->exit_code = status;
        ctx->exited = 1;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua exit with code %d", status);

        if (ctx->context == NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE) {
            return NGX_DONE;
        }

        return NGX_OK;

#else

        return NGX_ERROR;

#endif
    }

    if (ctx->no_abort
        && status != NGX_ERROR
        && status != NGX_HTTP_CLOSE
        && status != NGX_HTTP_REQUEST_TIME_OUT
        && status != NGX_HTTP_CLIENT_CLOSED_REQUEST)
    {
        *errlen = ngx_snprintf(err, *errlen,
                               "attempt to abort with pending subrequests")
                  - err;
        return NGX_ERROR;
    }

    if ((r->header_sent || ctx->header_sent)
        && status >= NGX_HTTP_SPECIAL_RESPONSE
        && status != NGX_HTTP_REQUEST_TIME_OUT
        && status != NGX_HTTP_CLIENT_CLOSED_REQUEST
        && status != NGX_HTTP_CLOSE)
    {
        if (status != (ngx_int_t) r->headers_out.status) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "attempt to "
                          "set status %d via ngx.exit after sending out the "
                          "response status %ui", status,
                          r->headers_out.status);
        }

        status = NGX_HTTP_OK;
    }

    ctx->exit_code = status;
    ctx->exited = 1;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua exit with code %i", ctx->exit_code);

    if (ctx->context & (NGX_HTTP_LUA_CONTEXT_HEADER_FILTER
                        | NGX_HTTP_LUA_CONTEXT_BALANCER))
    {
        return NGX_DONE;
    }

    return NGX_OK;
}
#endif  /* NGX_LUA_NO_FFI_API */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
