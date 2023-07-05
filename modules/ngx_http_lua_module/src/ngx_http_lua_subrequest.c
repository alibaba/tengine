
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_subrequest.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_ctx.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_headers_in.h"
#if defined(NGX_DTRACE) && NGX_DTRACE
#include "ngx_http_probe.h"
#endif


#define NGX_HTTP_LUA_SHARE_ALL_VARS     0x01
#define NGX_HTTP_LUA_COPY_ALL_VARS      0x02


#define ngx_http_lua_method_name(m) { sizeof(m) - 1, (u_char *) m " " }


ngx_str_t  ngx_http_lua_get_method = ngx_http_lua_method_name("GET");
ngx_str_t  ngx_http_lua_put_method = ngx_http_lua_method_name("PUT");
ngx_str_t  ngx_http_lua_post_method = ngx_http_lua_method_name("POST");
ngx_str_t  ngx_http_lua_head_method = ngx_http_lua_method_name("HEAD");
ngx_str_t  ngx_http_lua_delete_method =
        ngx_http_lua_method_name("DELETE");
ngx_str_t  ngx_http_lua_options_method =
        ngx_http_lua_method_name("OPTIONS");
ngx_str_t  ngx_http_lua_copy_method = ngx_http_lua_method_name("COPY");
ngx_str_t  ngx_http_lua_move_method = ngx_http_lua_method_name("MOVE");
ngx_str_t  ngx_http_lua_lock_method = ngx_http_lua_method_name("LOCK");
ngx_str_t  ngx_http_lua_mkcol_method =
        ngx_http_lua_method_name("MKCOL");
ngx_str_t  ngx_http_lua_propfind_method =
        ngx_http_lua_method_name("PROPFIND");
ngx_str_t  ngx_http_lua_proppatch_method =
        ngx_http_lua_method_name("PROPPATCH");
ngx_str_t  ngx_http_lua_unlock_method =
        ngx_http_lua_method_name("UNLOCK");
ngx_str_t  ngx_http_lua_patch_method =
        ngx_http_lua_method_name("PATCH");
ngx_str_t  ngx_http_lua_trace_method =
        ngx_http_lua_method_name("TRACE");


static ngx_str_t  ngx_http_lua_content_length_header_key =
    ngx_string("Content-Length");


static ngx_int_t ngx_http_lua_adjust_subrequest(ngx_http_request_t *sr,
    ngx_uint_t method, int forward_body,
    ngx_http_request_body_t *body, unsigned vars_action,
    ngx_array_t *extra_vars);
static int ngx_http_lua_ngx_location_capture(lua_State *L);
static int ngx_http_lua_ngx_location_capture_multi(lua_State *L);
static void ngx_http_lua_process_vars_option(ngx_http_request_t *r,
    lua_State *L, int table, ngx_array_t **varsp);
static ngx_int_t ngx_http_lua_subrequest_add_extra_vars(ngx_http_request_t *r,
    ngx_array_t *extra_vars);
static ngx_int_t ngx_http_lua_subrequest(ngx_http_request_t *r,
    ngx_str_t *uri, ngx_str_t *args, ngx_http_request_t **psr,
    ngx_http_post_subrequest_t *ps, ngx_uint_t flags);
static ngx_int_t ngx_http_lua_subrequest_resume(ngx_http_request_t *r);
static void ngx_http_lua_handle_subreq_responses(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx);
static void ngx_http_lua_cancel_subreq(ngx_http_request_t *r);
static ngx_int_t ngx_http_post_request_to_head(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_copy_in_file_request_body(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_copy_request_headers(ngx_http_request_t *sr,
    ngx_http_request_t *pr, int pr_not_chunked);


enum {
    NGX_HTTP_LUA_SUBREQ_TRUNCATED = 1,
};


/* ngx.location.capture is just a thin wrapper around
 * ngx.location.capture_multi */
static int
ngx_http_lua_ngx_location_capture(lua_State *L)
{
    int                 n;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting one or two arguments");
    }

    lua_createtable(L, n, 0); /* uri opts? table  */
    lua_insert(L, 1); /* table uri opts? */
    if (n == 1) { /* table uri */
        lua_rawseti(L, 1, 1); /* table */

    } else { /* table uri opts */
        lua_rawseti(L, 1, 2); /* table uri */
        lua_rawseti(L, 1, 1); /* table */
    }

    lua_createtable(L, 1, 0); /* table table' */
    lua_insert(L, 1);   /* table' table */
    lua_rawseti(L, 1, 1); /* table' */

    return ngx_http_lua_ngx_location_capture_multi(L);
}


static int
ngx_http_lua_ngx_location_capture_multi(lua_State *L)
{
    ngx_http_request_t              *r;
    ngx_http_request_t              *sr = NULL; /* subrequest object */
    ngx_http_post_subrequest_t      *psr;
    ngx_http_lua_ctx_t              *sr_ctx;
    ngx_http_lua_ctx_t              *ctx;
    ngx_array_t                     *extra_vars;
    ngx_str_t                        uri;
    ngx_str_t                        args;
    ngx_str_t                        extra_args;
    ngx_uint_t                       flags;
    u_char                          *p;
    u_char                          *q;
    size_t                           len;
    size_t                           nargs;
    int                              rc;
    int                              n;
    int                              always_forward_body = 0;
    ngx_uint_t                       method;
    ngx_http_request_body_t         *body;
    int                              type;
    ngx_buf_t                       *b;
    unsigned                         vars_action;
    ngx_uint_t                       nsubreqs;
    ngx_uint_t                       index;
    size_t                           sr_statuses_len;
    size_t                           sr_headers_len;
    size_t                           sr_bodies_len;
    size_t                           sr_flags_len;
    size_t                           ofs1, ofs2;
    unsigned                         custom_ctx;
    ngx_http_lua_co_ctx_t           *coctx;

    ngx_http_lua_post_subrequest_data_t      *psr_data;

    n = lua_gettop(L);
    if (n != 1) {
        return luaL_error(L, "only one argument is expected, but got %d", n);
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    nsubreqs = lua_objlen(L, 1);
    if (nsubreqs == 0) {
        return luaL_error(L, "at least one subrequest should be specified");
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

#if (NGX_HTTP_V2)
    if (r->main->stream) {
        return luaL_error(L, "http2 requests not supported yet");
    }
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    coctx = ctx->cur_co_ctx;
    if (coctx == NULL) {
        return luaL_error(L, "no co ctx found");
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua location capture, uri:\"%V\" c:%ud", &r->uri,
                   r->main->count);

    sr_statuses_len = nsubreqs * sizeof(ngx_int_t);
    sr_headers_len  = nsubreqs * sizeof(ngx_http_headers_out_t *);
    sr_bodies_len   = nsubreqs * sizeof(ngx_str_t);
    sr_flags_len    = nsubreqs * sizeof(uint8_t);

    p = ngx_pcalloc(r->pool, sr_statuses_len + sr_headers_len +
                    sr_bodies_len + sr_flags_len);

    if (p == NULL) {
        return luaL_error(L, "no memory");
    }

    coctx->sr_statuses = (void *) p;
    p += sr_statuses_len;

    coctx->sr_headers = (void *) p;
    p += sr_headers_len;

    coctx->sr_bodies = (void *) p;
    p += sr_bodies_len;

    coctx->sr_flags = (void *) p;

    coctx->nsubreqs = nsubreqs;

    coctx->pending_subreqs = 0;

    extra_vars = NULL;

    for (index = 0; index < nsubreqs; index++) {
        coctx->pending_subreqs++;

        lua_rawgeti(L, 1, index + 1);
        if (lua_isnil(L, -1)) {
            return luaL_error(L, "only array-like tables are allowed");
        }

        dd("queries query: top %d", lua_gettop(L));

        if (lua_type(L, -1) != LUA_TTABLE) {
            return luaL_error(L, "the query argument %d is not a table, "
                              "but a %s",
                              index, lua_typename(L, lua_type(L, -1)));
        }

        nargs = lua_objlen(L, -1);

        if (nargs != 1 && nargs != 2) {
            return luaL_error(L, "query argument %d expecting one or "
                              "two arguments", index);
        }

        lua_rawgeti(L, 2, 1); /* queries query uri */

        dd("queries query uri: %d", lua_gettop(L));

        dd("first arg in first query: %s", lua_typename(L, lua_type(L, -1)));

        body = NULL;

        ngx_str_null(&extra_args);

        if (extra_vars != NULL) {
            /* flush out existing elements in the array */
            extra_vars->nelts = 0;
        }

        vars_action = 0;

        custom_ctx = 0;

        if (nargs == 2) {
            /* check out the options table */

            lua_rawgeti(L, 2, 2); /* queries query uri opts */

            dd("queries query uri opts: %d", lua_gettop(L));

            if (lua_type(L, 4) != LUA_TTABLE) {
                return luaL_error(L, "expecting table as the 2nd argument for "
                                  "subrequest %d, but got %s", index,
                                  luaL_typename(L, 4));
            }

            dd("queries query uri opts: %d", lua_gettop(L));

            /* check the args option */

            lua_getfield(L, 4, "args");

            type = lua_type(L, -1);

            switch (type) {
            case LUA_TTABLE:
                ngx_http_lua_process_args_option(r, L, -1, &extra_args);
                break;

            case LUA_TNIL:
                /* do nothing */
                break;

            case LUA_TNUMBER:
            case LUA_TSTRING:
                extra_args.data = (u_char *) lua_tolstring(L, -1, &len);
                extra_args.len = len;

                break;

            default:
                return luaL_error(L, "Bad args option value");
            }

            lua_pop(L, 1);

            dd("queries query uri opts: %d", lua_gettop(L));

            /* check the vars option */

            lua_getfield(L, 4, "vars");

            switch (lua_type(L, -1)) {
            case LUA_TTABLE:
                ngx_http_lua_process_vars_option(r, L, -1, &extra_vars);

                dd("post process vars top: %d", lua_gettop(L));
                break;

            case LUA_TNIL:
                /* do nothing */
                break;

            default:
                return luaL_error(L, "Bad vars option value");
            }

            lua_pop(L, 1);

            dd("queries query uri opts: %d", lua_gettop(L));

            /* check the share_all_vars option */

            lua_getfield(L, 4, "share_all_vars");

            switch (lua_type(L, -1)) {
            case LUA_TNIL:
                /* do nothing */
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, -1)) {
                    vars_action |= NGX_HTTP_LUA_SHARE_ALL_VARS;
                }
                break;

            default:
                return luaL_error(L, "Bad share_all_vars option value");
            }

            lua_pop(L, 1);

            dd("queries query uri opts: %d", lua_gettop(L));

            /* check the copy_all_vars option */

            lua_getfield(L, 4, "copy_all_vars");

            switch (lua_type(L, -1)) {
            case LUA_TNIL:
                /* do nothing */
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, -1)) {
                    vars_action |= NGX_HTTP_LUA_COPY_ALL_VARS;
                }
                break;

            default:
                return luaL_error(L, "Bad copy_all_vars option value");
            }

            lua_pop(L, 1);

            dd("queries query uri opts: %d", lua_gettop(L));

            /* check the "forward_body" option */

            lua_getfield(L, 4, "always_forward_body");
            always_forward_body = lua_toboolean(L, -1);
            lua_pop(L, 1);

            dd("always forward body: %d", always_forward_body);

            /* check the "method" option */

            lua_getfield(L, 4, "method");

            type = lua_type(L, -1);

            if (type == LUA_TNIL) {
                method = NGX_HTTP_GET;

            } else {
                if (type != LUA_TNUMBER) {
                    return luaL_error(L, "Bad http request method");
                }

                method = (ngx_uint_t) lua_tonumber(L, -1);
            }

            lua_pop(L, 1);

            dd("queries query uri opts: %d", lua_gettop(L));

            /* check the "ctx" option */

            lua_getfield(L, 4, "ctx");

            type = lua_type(L, -1);

            if (type != LUA_TNIL) {
                if (type != LUA_TTABLE) {
                    return luaL_error(L, "Bad ctx option value type %s, "
                                      "expected a Lua table",
                                      lua_typename(L, type));
                }

                custom_ctx = 1;

            } else {
                lua_pop(L, 1);
            }

            dd("queries query uri opts ctx?: %d", lua_gettop(L));

            /* check the "body" option */

            lua_getfield(L, 4, "body");

            type = lua_type(L, -1);

            if (type != LUA_TNIL) {
                if (type != LUA_TSTRING && type != LUA_TNUMBER) {
                    return luaL_error(L, "Bad http request body");
                }

                body = ngx_pcalloc(r->pool, sizeof(ngx_http_request_body_t));

                if (body == NULL) {
                    return luaL_error(L, "no memory");
                }

                q = (u_char *) lua_tolstring(L, -1, &len);

                dd("request body: [%.*s]", (int) len, q);

                if (len) {
                    b = ngx_create_temp_buf(r->pool, len);
                    if (b == NULL) {
                        return luaL_error(L, "no memory");
                    }

                    b->last = ngx_copy(b->last, q, len);

                    body->bufs = ngx_alloc_chain_link(r->pool);
                    if (body->bufs == NULL) {
                        return luaL_error(L, "no memory");
                    }

                    body->bufs->buf = b;
                    body->bufs->next = NULL;

                    body->buf = b;
                }
            }

            lua_pop(L, 1); /* pop the body */

            /* stack: queries query uri opts ctx? */

            lua_remove(L, 4);

            /* stack: queries query uri ctx? */

            dd("queries query uri ctx?: %d", lua_gettop(L));

        } else {
            method = NGX_HTTP_GET;
        }

        /* stack: queries query uri ctx? */

        p = (u_char *) luaL_checklstring(L, 3, &len);

        uri.data = ngx_palloc(r->pool, len);
        if (uri.data == NULL) {
            return luaL_error(L, "memory allocation error");
        }

        ngx_memcpy(uri.data, p, len);

        uri.len = len;

        ngx_str_null(&args);

        flags = 0;

        rc = ngx_http_parse_unsafe_uri(r, &uri, &args, &flags);
        if (rc != NGX_OK) {
            dd("rc = %d", (int) rc);

            return luaL_error(L, "unsafe uri in argument #1: %s", p);
        }

        if (args.len == 0) {
            if (extra_args.len) {
                p = ngx_palloc(r->pool, extra_args.len);
                if (p == NULL) {
                    return luaL_error(L, "no memory");
                }

                ngx_memcpy(p, extra_args.data, extra_args.len);

                args.data = p;
                args.len = extra_args.len;
            }

        } else if (extra_args.len) {
            /* concatenate the two parts of args together */
            len = args.len + (sizeof("&") - 1) + extra_args.len;

            p = ngx_palloc(r->pool, len);
            if (p == NULL) {
                return luaL_error(L, "no memory");
            }

            q = ngx_copy(p, args.data, args.len);
            *q++ = '&';
            ngx_memcpy(q, extra_args.data, extra_args.len);

            args.data = p;
            args.len = len;
        }

        ofs1 = ngx_align(sizeof(ngx_http_post_subrequest_t), sizeof(void *));
        ofs2 = ngx_align(sizeof(ngx_http_lua_ctx_t), sizeof(void *));

        p = ngx_palloc(r->pool, ofs1 + ofs2
                       + sizeof(ngx_http_lua_post_subrequest_data_t));
        if (p == NULL) {
            return luaL_error(L, "no memory");
        }

        psr = (ngx_http_post_subrequest_t *) p;

        p += ofs1;

        sr_ctx = (ngx_http_lua_ctx_t *) p;

        ngx_http_lua_assert((void *) sr_ctx == ngx_align_ptr(sr_ctx,
                                                             sizeof(void *)));

        p += ofs2;

        psr_data = (ngx_http_lua_post_subrequest_data_t *) p;

        ngx_http_lua_assert((void *) psr_data == ngx_align_ptr(psr_data,
                                                               sizeof(void *)));

        ngx_memzero(sr_ctx, sizeof(ngx_http_lua_ctx_t));

        /* set by ngx_memzero:
         *      sr_ctx->run_post_subrequest = 0
         *      sr_ctx->free = NULL
         *      sr_ctx->body = NULL
         */

        psr_data->ctx = sr_ctx;
        psr_data->pr_co_ctx = coctx;

        psr->handler = ngx_http_lua_post_subrequest;
        psr->data = psr_data;

        rc = ngx_http_lua_subrequest(r, &uri, &args, &sr, psr, 0);

        if (rc != NGX_OK) {
            return luaL_error(L, "failed to issue subrequest: %d", (int) rc);
        }

        ngx_http_lua_init_ctx(sr, sr_ctx);

        sr_ctx->capture = 1;
        sr_ctx->index = index;
        sr_ctx->last_body = &sr_ctx->body;
        sr_ctx->vm_state = ctx->vm_state;

        ngx_http_set_ctx(sr, sr_ctx, ngx_http_lua_module);

        rc = ngx_http_lua_adjust_subrequest(sr, method, always_forward_body,
                                            body, vars_action, extra_vars);

        if (rc != NGX_OK) {
            ngx_http_lua_cancel_subreq(sr);
            return luaL_error(L, "failed to adjust the subrequest: %d",
                              (int) rc);
        }

        dd("queries query uri opts ctx? %d", lua_gettop(L));

        /* stack: queries query uri ctx? */

        if (custom_ctx) {
            ngx_http_lua_ngx_set_ctx_helper(L, sr, sr_ctx, -1);
            lua_pop(L, 3);

        } else {
            lua_pop(L, 2);
        }

        /* stack: queries */
    }

    if (extra_vars) {
        ngx_array_destroy(extra_vars);
    }

    ctx->no_abort = 1;

    return lua_yield(L, 0);
}


static ngx_int_t
ngx_http_lua_adjust_subrequest(ngx_http_request_t *sr, ngx_uint_t method,
    int always_forward_body, ngx_http_request_body_t *body,
    unsigned vars_action, ngx_array_t *extra_vars)
{
    ngx_http_request_t          *r;
    ngx_http_core_main_conf_t   *cmcf;
    int                          pr_not_chunked = 0;
    size_t                       size;

    r = sr->parent;

    sr->header_in = r->header_in;

    if (body) {
        sr->request_body = body;

    } else if (!always_forward_body
               && method != NGX_HTTP_PUT
               && method != NGX_HTTP_POST
               && r->headers_in.content_length_n > 0)
    {
        sr->request_body = NULL;

    } else {
        if (!r->headers_in.chunked) {
            pr_not_chunked = 1;
        }

        if (sr->request_body && sr->request_body->temp_file) {

            /* deep-copy the request body */

            if (ngx_http_lua_copy_in_file_request_body(sr) != NGX_OK) {
                return NGX_ERROR;
            }
        }
    }

    if (ngx_http_lua_copy_request_headers(sr, r, pr_not_chunked) != NGX_OK) {
        return NGX_ERROR;
    }

    sr->method = method;

    switch (method) {
        case NGX_HTTP_GET:
            sr->method_name = ngx_http_lua_get_method;
            break;

        case NGX_HTTP_POST:
            sr->method_name = ngx_http_lua_post_method;
            break;

        case NGX_HTTP_PUT:
            sr->method_name = ngx_http_lua_put_method;
            break;

        case NGX_HTTP_HEAD:
            sr->method_name = ngx_http_lua_head_method;
            break;

        case NGX_HTTP_DELETE:
            sr->method_name = ngx_http_lua_delete_method;
            break;

        case NGX_HTTP_OPTIONS:
            sr->method_name = ngx_http_lua_options_method;
            break;

        case NGX_HTTP_MKCOL:
            sr->method_name = ngx_http_lua_mkcol_method;
            break;

        case NGX_HTTP_COPY:
            sr->method_name = ngx_http_lua_copy_method;
            break;

        case NGX_HTTP_MOVE:
            sr->method_name = ngx_http_lua_move_method;
            break;

        case NGX_HTTP_PROPFIND:
            sr->method_name = ngx_http_lua_propfind_method;
            break;

        case NGX_HTTP_PROPPATCH:
            sr->method_name = ngx_http_lua_proppatch_method;
            break;

        case NGX_HTTP_LOCK:
            sr->method_name = ngx_http_lua_lock_method;
            break;

        case NGX_HTTP_UNLOCK:
            sr->method_name = ngx_http_lua_unlock_method;
            break;

        case NGX_HTTP_PATCH:
            sr->method_name = ngx_http_lua_patch_method;
            break;

        case NGX_HTTP_TRACE:
            sr->method_name = ngx_http_lua_trace_method;
            break;

        default:
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "unsupported HTTP method: %ui", method);

            return NGX_ERROR;
    }

    if (!(vars_action & NGX_HTTP_LUA_SHARE_ALL_VARS)) {
        /* we do not inherit the parent request's variables */
        cmcf = ngx_http_get_module_main_conf(sr, ngx_http_core_module);

        size = cmcf->variables.nelts * sizeof(ngx_http_variable_value_t);

        if (vars_action & NGX_HTTP_LUA_COPY_ALL_VARS) {

            sr->variables = ngx_palloc(sr->pool, size);
            if (sr->variables == NULL) {
                return NGX_ERROR;
            }

            ngx_memcpy(sr->variables, r->variables, size);

        } else {

            /* we do not inherit the parent request's variables */

            sr->variables = ngx_pcalloc(sr->pool, size);
            if (sr->variables == NULL) {
                return NGX_ERROR;
            }
        }
    }

    return ngx_http_lua_subrequest_add_extra_vars(sr, extra_vars);
}


static ngx_int_t
ngx_http_lua_subrequest_add_extra_vars(ngx_http_request_t *sr,
    ngx_array_t *extra_vars)
{
    ngx_http_core_main_conf_t   *cmcf;
    ngx_http_variable_t         *v;
    ngx_http_variable_value_t   *vv;
    u_char                      *val;
    u_char                      *p;
    ngx_uint_t                   i, hash;
    ngx_str_t                    name;
    size_t                       len;
    ngx_hash_t                  *variables_hash;
    ngx_keyval_t                *var;

    /* set any extra variables that were passed to the subrequest */

    if (extra_vars == NULL || extra_vars->nelts == 0) {
        return NGX_OK;
    }

    cmcf = ngx_http_get_module_main_conf(sr, ngx_http_core_module);

    variables_hash = &cmcf->variables_hash;

    var = extra_vars->elts;

    for (i = 0; i < extra_vars->nelts; i++, var++) {
        /* copy the variable's name and value because they are allocated
         * by the lua VM */

        len = var->key.len + var->value.len;

        p = ngx_pnalloc(sr->pool, len);
        if (p == NULL) {
            return NGX_ERROR;
        }

        name.data = p;
        name.len = var->key.len;

        p = ngx_copy(p, var->key.data, var->key.len);

        hash = ngx_hash_strlow(name.data, name.data, name.len);

        val = p;
        len = var->value.len;

        ngx_memcpy(p, var->value.data, len);

        v = ngx_hash_find(variables_hash, hash, name.data, name.len);

        if (v) {
            if (!(v->flags & NGX_HTTP_VAR_CHANGEABLE)) {
                ngx_log_error(NGX_LOG_ERR, sr->connection->log, 0,
                              "variable \"%V\" not changeable", &name);
                return NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            if (v->set_handler) {
                vv = ngx_palloc(sr->pool, sizeof(ngx_http_variable_value_t));
                if (vv == NULL) {
                    return NGX_ERROR;
                }

                vv->valid = 1;
                vv->not_found = 0;
                vv->no_cacheable = 0;

                vv->data = val;
                vv->len = len;

                v->set_handler(sr, vv, v->data);

                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, sr->connection->log, 0,
                               "variable \"%V\" set to value \"%v\"", &name,
                               vv);

                continue;
            }

            if (v->flags & NGX_HTTP_VAR_INDEXED) {
                vv = &sr->variables[v->index];

                vv->valid = 1;
                vv->not_found = 0;
                vv->no_cacheable = 0;

                vv->data = val;
                vv->len = len;

                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, sr->connection->log, 0,
                               "variable \"%V\" set to value \"%v\"",
                               &name, vv);

                continue;
            }
        }

        ngx_log_error(NGX_LOG_ERR, sr->connection->log, 0,
                      "variable \"%V\" cannot be assigned a value (maybe you "
                      "forgot to define it first?) ", &name);

        return NGX_ERROR;
    }

    return NGX_OK;
}


static void
ngx_http_lua_process_vars_option(ngx_http_request_t *r, lua_State *L,
    int table, ngx_array_t **varsp)
{
    ngx_array_t         *vars;
    ngx_keyval_t        *var;

    if (table < 0) {
        table = lua_gettop(L) + table + 1;
    }

    vars = *varsp;

    if (vars == NULL) {

        vars = ngx_array_create(r->pool, 4, sizeof(ngx_keyval_t));
        if (vars == NULL) {
            dd("here");
            luaL_error(L, "no memory");
            return;
        }

        *varsp = vars;
    }

    lua_pushnil(L);
    while (lua_next(L, table) != 0) {

        if (lua_type(L, -2) != LUA_TSTRING) {
            luaL_error(L, "attempt to use a non-string key in the "
                       "\"vars\" option table");
            return;
        }

        if (!lua_isstring(L, -1)) {
            luaL_error(L, "attempt to use bad variable value type %s",
                       luaL_typename(L, -1));
            return;
        }

        var = ngx_array_push(vars);
        if (var == NULL) {
            dd("here");
            luaL_error(L, "no memory");
            return;
        }

        var->key.data = (u_char *) lua_tolstring(L, -2, &var->key.len);
        var->value.data = (u_char *) lua_tolstring(L, -1, &var->value.len);

        lua_pop(L, 1);
    }
}


ngx_int_t
ngx_http_lua_post_subrequest(ngx_http_request_t *r, void *data, ngx_int_t rc)
{
    ngx_http_request_t            *pr;
    ngx_http_lua_ctx_t            *pr_ctx;
    ngx_http_lua_ctx_t            *ctx; /* subrequest ctx */
    ngx_http_lua_co_ctx_t         *pr_coctx;
    size_t                         len;
    ngx_str_t                     *body_str;
    u_char                        *p;
    ngx_chain_t                   *cl;

    ngx_http_lua_post_subrequest_data_t    *psr_data = data;

    ctx = psr_data->ctx;

    if (ctx->run_post_subrequest) {
        if (r != r->connection->data) {
            r->connection->data = r;
        }

        return NGX_OK;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run post subrequest handler, rc:%i c:%ud", rc,
                   r->main->count);

    ctx->run_post_subrequest = 1;

    pr = r->parent;

    pr_ctx = ngx_http_get_module_ctx(pr, ngx_http_lua_module);
    if (pr_ctx == NULL) {
        return NGX_ERROR;
    }

    pr_coctx = psr_data->pr_co_ctx;
    pr_coctx->pending_subreqs--;

    if (pr_coctx->pending_subreqs == 0) {
        dd("all subrequests are done");

        pr_ctx->no_abort = 0;
        pr_ctx->resume_handler = ngx_http_lua_subrequest_resume;
        pr_ctx->cur_co_ctx = pr_coctx;
    }

    if (pr_ctx->entered_content_phase) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua restoring write event handler");

        pr->write_event_handler = ngx_http_lua_content_wev_handler;

    } else {
        pr->write_event_handler = ngx_http_core_run_phases;
    }

    dd("status rc = %d", (int) rc);
    dd("status headers_out.status = %d", (int) r->headers_out.status);
    dd("uri: %.*s", (int) r->uri.len, r->uri.data);

    /*  capture subrequest response status */

    pr_coctx->sr_statuses[ctx->index] = r->headers_out.status;

    if (pr_coctx->sr_statuses[ctx->index] == 0) {
        if (rc == NGX_OK) {
            rc = NGX_HTTP_OK;
        }

        if (rc == NGX_ERROR) {
            rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        if (rc >= 100) {
            pr_coctx->sr_statuses[ctx->index] = rc;
        }
    }

    if (!ctx->seen_last_for_subreq) {
        pr_coctx->sr_flags[ctx->index] |= NGX_HTTP_LUA_SUBREQ_TRUNCATED;
    }

    dd("pr_coctx status: %d", (int) pr_coctx->sr_statuses[ctx->index]);

    /* copy subrequest response headers */
    if (ctx->headers_set) {
        rc = ngx_http_lua_set_content_type(r, ctx);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "failed to set default content type: %i", rc);
            return NGX_ERROR;
        }
    }

    pr_coctx->sr_headers[ctx->index] = &r->headers_out;

    /* copy subrequest response body */

    body_str = &pr_coctx->sr_bodies[ctx->index];

    len = 0;
    for (cl = ctx->body; cl; cl = cl->next) {
        /*  ignore all non-memory buffers */
        len += cl->buf->last - cl->buf->pos;
    }

    body_str->len = len;

    if (len == 0) {
        body_str->data = NULL;

    } else {
        p = ngx_palloc(r->pool, len);
        if (p == NULL) {
            return NGX_ERROR;
        }

        body_str->data = p;

        /* copy from and then free the data buffers */

        for (cl = ctx->body; cl; cl = cl->next) {
            p = ngx_copy(p, cl->buf->pos, cl->buf->last - cl->buf->pos);

            cl->buf->last = cl->buf->pos;

#if 0
            dd("free body chain link buf ASAP");
            ngx_pfree(r->pool, cl->buf->start);
#endif
        }
    }

    if (ctx->body) {

        ngx_chain_update_chains(r->pool,
                                &pr_ctx->free_bufs, &pr_ctx->busy_bufs,
                                &ctx->body,
                                (ngx_buf_tag_t) &ngx_http_lua_module);

        dd("free bufs: %p", pr_ctx->free_bufs);
    }

    ngx_http_post_request_to_head(pr);

    if (r != r->connection->data) {
        r->connection->data = r;
    }

    if (rc == NGX_ERROR
        || rc == NGX_HTTP_CREATED
        || rc == NGX_HTTP_NO_CONTENT
        || (rc >= NGX_HTTP_SPECIAL_RESPONSE
            && rc != NGX_HTTP_CLOSE
            && rc != NGX_HTTP_REQUEST_TIME_OUT
            && rc != NGX_HTTP_CLIENT_CLOSED_REQUEST))
    {
        /* emulate ngx_http_special_response_handler */

        if (rc > NGX_OK) {
            r->err_status = rc;

            r->expect_tested = 1;
            r->headers_out.content_type.len = 0;
            r->headers_out.content_length_n = 0;

            ngx_http_clear_accept_ranges(r);
            ngx_http_clear_last_modified(r);

            rc = ngx_http_lua_send_header_if_needed(r, ctx);
            if (rc == NGX_ERROR) {
                return NGX_ERROR;
            }
        }

        return NGX_OK;
    }

    return rc;
}


static void
ngx_http_lua_handle_subreq_responses(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx)
{
    ngx_uint_t                   i, count;
    ngx_uint_t                   index;
    lua_State                   *co;
    ngx_str_t                   *body_str;
    ngx_table_elt_t             *header;
    ngx_list_part_t             *part;
    ngx_http_headers_out_t      *sr_headers;
    ngx_http_lua_co_ctx_t       *coctx;

    u_char                  buf[sizeof("Mon, 28 Sep 1970 06:00:00 GMT") - 1];

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua handle subrequest responses");

    coctx = ctx->cur_co_ctx;
    co = coctx->co;

    for (index = 0; index < coctx->nsubreqs; index++) {
        dd("summary: reqs %d, subquery %d, pending %d, req %.*s",
           (int) coctx->nsubreqs,
           (int) index,
           (int) coctx->pending_subreqs,
           (int) r->uri.len, r->uri.data);

        /*  {{{ construct ret value */
        lua_createtable(co, 0 /* narr */, 4 /* nrec */);

        /*  copy captured status */
        lua_pushinteger(co, coctx->sr_statuses[index]);
        lua_setfield(co, -2, "status");

        dd("captured subrequest flags: %d", (int) coctx->sr_flags[index]);

        /* set truncated flag if truncation happens */
        if (coctx->sr_flags[index] & NGX_HTTP_LUA_SUBREQ_TRUNCATED) {
            lua_pushboolean(co, 1);
            lua_setfield(co, -2, "truncated");

        } else {
            lua_pushboolean(co, 0);
            lua_setfield(co, -2, "truncated");
        }

        /*  copy captured body */

        body_str = &coctx->sr_bodies[index];

        lua_pushlstring(co, (char *) body_str->data, body_str->len);
        lua_setfield(co, -2, "body");

        if (body_str->data) {
            dd("free body buffer ASAP");
            ngx_pfree(r->pool, body_str->data);
        }

        /* copy captured headers */

        sr_headers = coctx->sr_headers[index];

        part = &sr_headers->headers.part;
        count = part->nelts;
        while (part->next) {
            part = part->next;
            count += part->nelts;
        }

        lua_createtable(co, 0, count + 5); /* res.header */

        dd("saving subrequest response headers");

        part = &sr_headers->headers.part;
        header = part->elts;

        for (i = 0; /* void */; i++) {

            if (i >= part->nelts) {
                if (part->next == NULL) {
                    break;
                }

                part = part->next;
                header = part->elts;
                i = 0;
            }

            dd("checking sr header %.*s", (int) header[i].key.len,
               header[i].key.data);

#if 1
            if (header[i].hash == 0) {
                continue;
            }
#endif

            header[i].hash = 0;

            dd("pushing sr header %.*s", (int) header[i].key.len,
               header[i].key.data);

            lua_pushlstring(co, (char *) header[i].key.data,
                            header[i].key.len); /* header key */
            lua_pushvalue(co, -1); /* stack: table key key */

            /* check if header already exists */
            lua_rawget(co, -3); /* stack: table key value */

            if (lua_isnil(co, -1)) {
                lua_pop(co, 1); /* stack: table key */

                lua_pushlstring(co, (char *) header[i].value.data,
                                header[i].value.len);
                    /* stack: table key value */

                lua_rawset(co, -3); /* stack: table */

            } else {

                if (!lua_istable(co, -1)) { /* already inserted one value */
                    lua_createtable(co, 4, 0);
                        /* stack: table key value table */

                    lua_insert(co, -2); /* stack: table key table value */
                    lua_rawseti(co, -2, 1); /* stack: table key table */

                    lua_pushlstring(co, (char *) header[i].value.data,
                                    header[i].value.len);
                        /* stack: table key table value */

                    lua_rawseti(co, -2, lua_objlen(co, -2) + 1);
                        /* stack: table key table */

                    lua_rawset(co, -3); /* stack: table */

                } else {
                    lua_pushlstring(co, (char *) header[i].value.data,
                                    header[i].value.len);
                        /* stack: table key table value */

                    lua_rawseti(co, -2, lua_objlen(co, -2) + 1);
                        /* stack: table key table */

                    lua_pop(co, 2); /* stack: table */
                }
            }
        }

        if (sr_headers->content_type.len) {
            lua_pushliteral(co, "Content-Type"); /* header key */
            lua_pushlstring(co, (char *) sr_headers->content_type.data,
                            sr_headers->content_type.len); /* head key value */
            lua_rawset(co, -3); /* head */
        }

        if (sr_headers->content_length == NULL
            && sr_headers->content_length_n >= 0)
        {
            lua_pushliteral(co, "Content-Length"); /* header key */

            lua_pushnumber(co, (lua_Number) sr_headers->content_length_n);
                /* head key value */

            lua_rawset(co, -3); /* head */
        }

        /* to work-around an issue in ngx_http_static_module
         * (github issue #41) */
        if (sr_headers->location && sr_headers->location->value.len) {
            lua_pushliteral(co, "Location"); /* header key */
            lua_pushlstring(co, (char *) sr_headers->location->value.data,
                            sr_headers->location->value.len);
            /* head key value */
            lua_rawset(co, -3); /* head */
        }

        if (sr_headers->last_modified_time != -1) {
            if (sr_headers->status != NGX_HTTP_OK
                && sr_headers->status != NGX_HTTP_PARTIAL_CONTENT
                && sr_headers->status != NGX_HTTP_NOT_MODIFIED
                && sr_headers->status != NGX_HTTP_NO_CONTENT)
            {
                sr_headers->last_modified_time = -1;
                sr_headers->last_modified = NULL;
            }
        }

        if (sr_headers->last_modified == NULL
            && sr_headers->last_modified_time != -1)
        {
            (void) ngx_http_time(buf, sr_headers->last_modified_time);

            lua_pushliteral(co, "Last-Modified"); /* header key */
            lua_pushlstring(co, (char *) buf, sizeof(buf)); /* head key value */
            lua_rawset(co, -3); /* head */
        }

        lua_setfield(co, -2, "header");

        /*  }}} */
    }
}


void
ngx_http_lua_inject_subrequest_api(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 2 /* nrec */); /* .location */

    lua_pushcfunction(L, ngx_http_lua_ngx_location_capture);
    lua_setfield(L, -2, "capture");

    lua_pushcfunction(L, ngx_http_lua_ngx_location_capture_multi);
    lua_setfield(L, -2, "capture_multi");

    lua_setfield(L, -2, "location");
}


static ngx_int_t
ngx_http_lua_subrequest(ngx_http_request_t *r,
    ngx_str_t *uri, ngx_str_t *args, ngx_http_request_t **psr,
    ngx_http_post_subrequest_t *ps, ngx_uint_t flags)
{
    ngx_time_t                    *tp;
    ngx_connection_t              *c;
    ngx_http_request_t            *sr;
    ngx_http_core_srv_conf_t      *cscf;

#if (nginx_version >= 1009005)

    if (r->subrequests == 0) {
#if defined(NGX_DTRACE) && NGX_DTRACE
        ngx_http_probe_subrequest_cycle(r, uri, args);
#endif

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "lua subrequests cycle while processing \"%V\"", uri);
        return NGX_ERROR;
    }

#else  /* nginx_version <= 1009004 */

    r->main->subrequests--;

    if (r->main->subrequests == 0) {
#if defined(NGX_DTRACE) && NGX_DTRACE
        ngx_http_probe_subrequest_cycle(r, uri, args);
#endif

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "lua subrequests cycle while processing \"%V\"", uri);
        r->main->subrequests = 1;
        return NGX_ERROR;
    }

#endif

    sr = ngx_pcalloc(r->pool, sizeof(ngx_http_request_t));
    if (sr == NULL) {
        return NGX_ERROR;
    }

    sr->signature = NGX_HTTP_MODULE;

    c = r->connection;
    sr->connection = c;

    sr->ctx = ngx_pcalloc(r->pool, sizeof(void *) * ngx_http_max_module);
    if (sr->ctx == NULL) {
        return NGX_ERROR;
    }

    if (ngx_list_init(&sr->headers_out.headers, r->pool, 20,
                      sizeof(ngx_table_elt_t))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    cscf = ngx_http_get_module_srv_conf(r, ngx_http_core_module);
    sr->main_conf = cscf->ctx->main_conf;
    sr->srv_conf = cscf->ctx->srv_conf;
    sr->loc_conf = cscf->ctx->loc_conf;

    sr->pool = r->pool;

    sr->headers_in.content_length_n = -1;
    sr->headers_in.keep_alive_n = -1;

    ngx_http_clear_content_length(sr);
    ngx_http_clear_accept_ranges(sr);
    ngx_http_clear_last_modified(sr);

    sr->request_body = r->request_body;

#if (NGX_HTTP_SPDY)
    sr->spdy_stream = r->spdy_stream;
#endif

#if (NGX_HTTP_V2)
    sr->stream = r->stream;
#endif

#ifdef HAVE_ALLOW_REQUEST_BODY_UPDATING_PATCH
    sr->content_length_n = -1;
#endif

    sr->method = NGX_HTTP_GET;
    sr->http_version = r->http_version;

    sr->request_line = r->request_line;
    sr->uri = *uri;

    if (args) {
        sr->args = *args;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua http subrequest \"%V?%V\"", uri, &sr->args);

    sr->subrequest_in_memory = (flags & NGX_HTTP_SUBREQUEST_IN_MEMORY) != 0;
    sr->waited = (flags & NGX_HTTP_SUBREQUEST_WAITED) != 0;

    sr->unparsed_uri = r->unparsed_uri;
    sr->method_name = ngx_http_core_get_method;
    sr->http_protocol = r->http_protocol;

    ngx_http_set_exten(sr);

    sr->main = r->main;
    sr->parent = r;
    sr->post_subrequest = ps;
    sr->read_event_handler = ngx_http_request_empty_handler;
    sr->write_event_handler = ngx_http_handler;

    sr->variables = r->variables;

    sr->log_handler = r->log_handler;

    sr->internal = 1;

    sr->discard_body = r->discard_body;
    sr->expect_tested = 1;
    sr->main_filter_need_in_memory = r->main_filter_need_in_memory;

    sr->uri_changes = NGX_HTTP_MAX_URI_CHANGES + 1;

#if (nginx_version >= 1009005)
    sr->subrequests = r->subrequests - 1;
#endif

    tp = ngx_timeofday();
    sr->start_sec = tp->sec;
    sr->start_msec = tp->msec;

    r->main->count++;

    *psr = sr;

#if defined(NGX_DTRACE) && NGX_DTRACE
    ngx_http_probe_subrequest_start(sr);
#endif

    return ngx_http_post_request(sr, NULL);
}


static ngx_int_t
ngx_http_lua_subrequest_resume(ngx_http_request_t *r)
{
    lua_State                   *vm;
    ngx_int_t                    rc;
    ngx_uint_t                   nreqs;
    ngx_connection_t            *c;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run subrequests done, resuming lua thread");

    coctx = ctx->cur_co_ctx;

    dd("nsubreqs: %d", (int) coctx->nsubreqs);

    ngx_http_lua_handle_subreq_responses(r, ctx);

    dd("free sr_statues/headers/bodies memory ASAP");

#if 1
    ngx_pfree(r->pool, coctx->sr_statuses);

    coctx->sr_statuses = NULL;
    coctx->sr_headers = NULL;
    coctx->sr_bodies = NULL;
    coctx->sr_flags = NULL;
#endif

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(vm, r, ctx, coctx->nsubreqs);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    /* rc == NGX_ERROR || rc >= NGX_OK */

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static void
ngx_http_lua_cancel_subreq(ngx_http_request_t *r)
{
    ngx_http_posted_request_t   *pr;
    ngx_http_posted_request_t  **p;

#if 1
    r->main->count--;
    r->main->subrequests++;
#endif

    p = &r->main->posted_requests;
    for (pr = r->main->posted_requests; pr->next; pr = pr->next) {
        p = &pr->next;
    }

    *p = NULL;

    r->connection->data = r->parent;
}


static ngx_int_t
ngx_http_post_request_to_head(ngx_http_request_t *r)
{
    ngx_http_posted_request_t  *pr;

    pr = ngx_palloc(r->pool, sizeof(ngx_http_posted_request_t));
    if (pr == NULL) {
        return NGX_ERROR;
    }

    pr->request = r;
    pr->next = r->main->posted_requests;
    r->main->posted_requests = pr;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_copy_in_file_request_body(ngx_http_request_t *r)
{
    ngx_temp_file_t     *tf;

    ngx_http_request_body_t   *body;

    tf = r->request_body->temp_file;

    if (!tf->persistent || !tf->clean) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "the request body was not read by ngx_lua");

        return NGX_ERROR;
    }

    body = ngx_palloc(r->pool, sizeof(ngx_http_request_body_t));
    if (body == NULL) {
        return NGX_ERROR;
    }

    ngx_memcpy(body, r->request_body, sizeof(ngx_http_request_body_t));

    body->temp_file = ngx_palloc(r->pool, sizeof(ngx_temp_file_t));
    if (body->temp_file == NULL) {
        return NGX_ERROR;
    }

    ngx_memcpy(body->temp_file, tf, sizeof(ngx_temp_file_t));
    dd("file fd: %d", body->temp_file->file.fd);

    r->request_body = body;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_copy_request_headers(ngx_http_request_t *sr,
    ngx_http_request_t *pr, int pr_not_chunked)
{
    ngx_table_elt_t                 *clh, *header;
    ngx_list_part_t                 *part;
    ngx_chain_t                     *in;
    ngx_uint_t                       i;
    u_char                          *p;
    off_t                            len;

    dd("before: parent req headers count: %d",
       (int) pr->headers_in.headers.part.nelts);

    if (ngx_list_init(&sr->headers_in.headers, sr->pool, 20,
                      sizeof(ngx_table_elt_t)) != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (sr->request_body && !pr_not_chunked) {

        /* craft our own Content-Length */
        len = 0;

        for (in = sr->request_body->bufs; in; in = in->next) {
            len += ngx_buf_size(in->buf);
        }

        clh = ngx_list_push(&sr->headers_in.headers);
        if (clh == NULL) {
            return NGX_ERROR;
        }

        clh->hash = ngx_http_lua_content_length_hash;
        clh->key = ngx_http_lua_content_length_header_key;
        clh->lowcase_key = ngx_pnalloc(sr->pool, clh->key.len);
        if (clh->lowcase_key == NULL) {
            return NGX_ERROR;
        }

        ngx_strlow(clh->lowcase_key, clh->key.data, clh->key.len);

        p = ngx_palloc(sr->pool, NGX_OFF_T_LEN);
        if (p == NULL) {
            return NGX_ERROR;
        }

        clh->value.data = p;
        clh->value.len = ngx_sprintf(clh->value.data, "%O", len)
                         - clh->value.data;

        sr->headers_in.content_length = clh;
        sr->headers_in.content_length_n = len;

        dd("sr crafted content-length: %.*s",
           (int) sr->headers_in.content_length->value.len,
           sr->headers_in.content_length->value.data);
    }

    /* copy the parent request's headers */

    part = &pr->headers_in.headers.part;
    header = part->elts;

    for (i = 0; /* void */; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            header = part->elts;
            i = 0;
        }

        if (!pr_not_chunked && header[i].key.len == sizeof("Content-Length") - 1
            && ngx_strncasecmp(header[i].key.data, (u_char *) "Content-Length",
                               sizeof("Content-Length") - 1) == 0)
        {
            continue;
        }

        dd("sr copied req header %.*s: %.*s", (int) header[i].key.len,
           header[i].key.data, (int) header[i].value.len,
           header[i].value.data);

        if (ngx_http_lua_set_input_header(sr, header[i].key,
                                          header[i].value, 0) == NGX_ERROR)
        {
            return NGX_ERROR;
        }
    }

    dd("after: parent req headers count: %d",
       (int) pr->headers_in.headers.part.nelts);

    return NGX_OK;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
