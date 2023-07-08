
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_is_internal(lua_State *L);


void
ngx_http_lua_inject_req_misc_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_is_internal);
    lua_setfield(L, -2, "is_internal");
}


static int
ngx_http_lua_ngx_req_is_internal(lua_State *L)
{
    ngx_http_request_t  *r;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    lua_pushboolean(L, r->internal == 1);
    return 1;
}


int
ngx_http_lua_ffi_get_resp_status(ngx_http_request_t *r)
{
    if (r->connection->fd == (ngx_socket_t) -1) {
        return NGX_HTTP_LUA_FFI_BAD_CONTEXT;
    }

    if (r->err_status) {
        return r->err_status;

    } else if (r->headers_out.status) {
        return r->headers_out.status;

    } else if (r->http_version == NGX_HTTP_VERSION_9) {
        return 9;

    } else {
        return 0;
    }
}


int
ngx_http_lua_ffi_set_resp_status(ngx_http_request_t *r, int status)
{
    if (r->connection->fd == (ngx_socket_t) -1) {
        return NGX_HTTP_LUA_FFI_BAD_CONTEXT;
    }

    if (r->header_sent) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "attempt to set ngx.status after sending out "
                      "response headers");
        return NGX_DECLINED;
    }

    r->headers_out.status = status;

    if (r->err_status) {
        r->err_status = 0;
    }

    if (status == 101) {
        /*
         * XXX work-around a bug in the Nginx core older than 1.5.5
         * that 101 does not have a default status line
         */

        ngx_str_set(&r->headers_out.status_line, "101 Switching Protocols");

    } else {
        r->headers_out.status_line.len = 0;
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_req_is_internal(ngx_http_request_t *r)
{
    if (r->connection->fd == (ngx_socket_t) -1) {
        return NGX_HTTP_LUA_FFI_BAD_CONTEXT;
    }

    return r->internal;
}


int
ngx_http_lua_ffi_is_subrequest(ngx_http_request_t *r)
{
    if (r->connection->fd == (ngx_socket_t) -1) {
        return NGX_HTTP_LUA_FFI_BAD_CONTEXT;
    }

    return r != r->main;
}


int
ngx_http_lua_ffi_headers_sent(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_HTTP_LUA_FFI_NO_REQ_CTX;
    }

    if (r->connection->fd == (ngx_socket_t) -1) {
        return NGX_HTTP_LUA_FFI_BAD_CONTEXT;
    }

    return r->header_sent ? 1 : 0;
}


int
ngx_http_lua_ffi_get_conf_env(u_char *name, u_char **env_buf, size_t *name_len)
{
    ngx_uint_t            i;
    ngx_str_t            *var;
    ngx_core_conf_t      *ccf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx,
                                           ngx_core_module);

    var = ccf->env.elts;

    for (i = 0; i < ccf->env.nelts; i++) {
        if (var[i].data[var[i].len] == '='
            && ngx_strncmp(name, var[i].data, var[i].len) == 0)
        {
            *env_buf = var[i].data;
            *name_len = var[i].len;

            return NGX_OK;
        }
    }

    return NGX_DECLINED;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
