
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_bodyfilterby.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_log.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_string.h"
#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_consts.h"
#include "ngx_http_lua_output.h"


static void ngx_http_lua_body_filter_by_lua_env(lua_State *L,
    ngx_http_request_t *r, ngx_chain_t *in);
static ngx_http_output_body_filter_pt ngx_http_next_body_filter;


/**
 * Set environment table for the given code closure.
 *
 * Before:
 *         | code closure | <- top
 *         |      ...     |
 *
 * After:
 *         | code closure | <- top
 *         |      ...     |
 * */
static void
ngx_http_lua_body_filter_by_lua_env(lua_State *L, ngx_http_request_t *r,
    ngx_chain_t *in)
{
    ngx_http_lua_main_conf_t    *lmcf;

    ngx_http_lua_set_req(L, r);

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    lmcf->body_filter_chain = in;

#ifndef OPENRESTY_LUAJIT
    /**
     * we want to create empty environment for current script
     *
     * setmetatable({}, {__index = _G})
     *
     * if a function or symbol is not defined in our env, __index will lookup
     * in the global env.
     *
     * all variables created in the script-env will be thrown away at the end
     * of the script run.
     * */
    ngx_http_lua_create_new_globals_table(L, 0 /* narr */, 1 /* nrec */);

    /*  {{{ make new env inheriting main thread's globals table */
    lua_createtable(L, 0, 1 /* nrec */);    /*  the metatable for the new
                                                env */
    ngx_http_lua_get_globals_table(L);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
#endif /* OPENRESTY_LUAJIT */
}


ngx_int_t
ngx_http_lua_body_filter_by_chunk(lua_State *L, ngx_http_request_t *r,
    ngx_chain_t *in)
{
    ngx_int_t        rc;
    u_char          *err_msg;
    size_t           len;
#if (NGX_PCRE)
    ngx_pool_t      *old_pool;
#endif

    dd("initialize nginx context in Lua VM, code chunk at stack top  sp = 1");
    ngx_http_lua_body_filter_by_lua_env(L, r, in);

#if (NGX_PCRE)
    /* XXX: work-around to nginx regex subsystem */
    old_pool = ngx_http_lua_pcre_malloc_init(r->pool);
#endif

    lua_pushcfunction(L, ngx_http_lua_traceback);
    lua_insert(L, 1);  /* put it under chunk and args */

    dd("protected call user code");
    rc = lua_pcall(L, 0, 1, 1);

    lua_remove(L, 1);  /* remove traceback function */

#if (NGX_PCRE)
    /* XXX: work-around to nginx regex subsystem */
    ngx_http_lua_pcre_malloc_done(old_pool);
#endif

    if (rc != 0) {

        /*  error occurred */
        err_msg = (u_char *) lua_tolstring(L, -1, &len);

        if (err_msg == NULL) {
            err_msg = (u_char *) "unknown reason";
            len = sizeof("unknown reason") - 1;
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to run body_filter_by_lua*: %*s", len, err_msg);

        lua_settop(L, 0);    /*  clear remaining elems on stack */

        return NGX_ERROR;
    }

    /* rc == 0 */

    rc = (ngx_int_t) lua_tointeger(L, -1);

    dd("got return value: %d", (int) rc);

    lua_settop(L, 0);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_body_filter_inline(ngx_http_request_t *r, ngx_chain_t *in)
{
    lua_State                   *L;
    ngx_int_t                    rc;
    ngx_http_lua_loc_conf_t     *llcf;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    L = ngx_http_lua_get_lua_vm(r, NULL);

    /*  load Lua inline script (w/ cache) sp = 1 */
    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       llcf->body_filter_src.value.data,
                                       llcf->body_filter_src.value.len,
                                       &llcf->body_filter_src_ref,
                                       llcf->body_filter_src_key,
                                       (const char *)
                                       llcf->body_filter_chunkname);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    rc = ngx_http_lua_body_filter_by_chunk(L, r, in);

    dd("body filter by chunk returns %d", (int) rc);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_body_filter_file(ngx_http_request_t *r, ngx_chain_t *in)
{
    lua_State                       *L;
    ngx_int_t                        rc;
    u_char                          *script_path;
    ngx_http_lua_loc_conf_t         *llcf;
    ngx_str_t                        eval_src;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    /* Eval nginx variables in code path string first */
    if (ngx_http_complex_value(r, &llcf->body_filter_src, &eval_src)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    script_path = ngx_http_lua_rebase_path(r->pool, eval_src.data,
                                           eval_src.len);

    if (script_path == NULL) {
        return NGX_ERROR;
    }

    L = ngx_http_lua_get_lua_vm(r, NULL);

    /*  load Lua script file (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadfile(r->connection->log, L, script_path,
                                     &llcf->body_filter_src_ref,
                                     llcf->body_filter_src_key);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    rc = ngx_http_lua_body_filter_by_chunk(L, r, in);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_body_filter(ngx_http_request_t *r, ngx_chain_t *in)
{
    ngx_http_lua_loc_conf_t     *llcf;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;
    uint16_t                     old_context;
    ngx_pool_cleanup_t          *cln;
    ngx_chain_t                 *out;
    ngx_chain_t                 *cl, *ln;
    ngx_http_lua_main_conf_t    *lmcf;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua body filter for user lua code, uri \"%V\"", &r->uri);

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->body_filter_handler == NULL || r->header_only) {
        dd("no body filter handler found");
        return ngx_http_next_body_filter(r, in);
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    dd("ctx = %p", ctx);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_ERROR;
        }
    }

    if (ctx->seen_last_in_filter) {
        for (/* void */; in; in = in->next) {
            dd("mark the buf as consumed: %d", (int) ngx_buf_size(in->buf));
            in->buf->pos = in->buf->last;
            in->buf->file_pos = in->buf->file_last;
        }

        in = NULL;

        /* continue to call ngx_http_next_body_filter to process cached data */
    }

    if (in != NULL
        && ngx_chain_add_copy(r->pool, &ctx->filter_in_bufs, in) != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (ctx->filter_busy_bufs != NULL
        && (r->connection->buffered
            & (NGX_HTTP_LOWLEVEL_BUFFERED | NGX_LOWLEVEL_BUFFERED)))
    {
        /* Socket write buffer was full on last write.
         * Try to write the remain data, if still can not write
         * do not execute body_filter_by_lua otherwise the `in` chain will be
         * replaced by new content from lua and buf of `in` mark as consumed.
         * And then ngx_output_chain will call the filter chain again which
         * make all the data cached in the memory and long ngx_chain_t link
         * cause CPU 100%.
         */
        rc = ngx_http_next_body_filter(r, NULL);

        if (rc == NGX_ERROR) {
            return rc;
        }

        out = NULL;
        ngx_chain_update_chains(r->pool,
                                &ctx->free_bufs, &ctx->filter_busy_bufs, &out,
                                (ngx_buf_tag_t) &ngx_http_lua_body_filter);
        if (rc != NGX_OK
            && ctx->filter_busy_bufs != NULL
            && (r->connection->buffered
                & (NGX_HTTP_LOWLEVEL_BUFFERED | NGX_LOWLEVEL_BUFFERED)))
        {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "waiting body filter busy buffer to be sent");
            return NGX_AGAIN;
        }

        /* continue to process bufs in ctx->filter_in_bufs */
    }

    if (ctx->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(r->pool, 0);
        if (cln == NULL) {
            return NGX_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup_handler;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;
    }

    old_context = ctx->context;
    ctx->context = NGX_HTTP_LUA_CONTEXT_BODY_FILTER;

    in = ctx->filter_in_bufs;
    ctx->filter_in_bufs = NULL;

    if (in != NULL) {
        dd("calling body filter handler");
        rc = llcf->body_filter_handler(r, in);

        dd("calling body filter handler returned %d", (int) rc);

        ctx->context = old_context;

        if (rc != NGX_OK) {
            return NGX_ERROR;
        }

        lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

        /* lmcf->body_filter_chain is the new buffer chain if
         * body_filter_by_lua set new body content via ngx.arg[1] = new_content
         * otherwise it is the original `in` buffer chain.
         */
        out = lmcf->body_filter_chain;

        if (in != out) {
            /* content of body was replaced in
             * ngx_http_lua_body_filter_param_set and the buffers was marked
             * as consumed.
             */
            for (cl = in; cl != NULL; cl = ln) {
                ln = cl->next;
                ngx_free_chain(r->pool, cl);
            }

            if (out == NULL) {
                /* do not forward NULL to the next filters because the input is
                 * not NULL */
                return NGX_OK;
            }
        }

    } else {
        out = NULL;
    }

    rc = ngx_http_next_body_filter(r, out);
    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    ngx_chain_update_chains(r->pool,
                            &ctx->free_bufs, &ctx->filter_busy_bufs, &out,
                            (ngx_buf_tag_t) &ngx_http_lua_body_filter);

    return rc;
}


ngx_int_t
ngx_http_lua_body_filter_init(void)
{
    dd("calling body filter init");
    ngx_http_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_lua_body_filter;

    return NGX_OK;
}


int
ngx_http_lua_ffi_get_body_filter_param_eof(ngx_http_request_t *r)
{
    ngx_chain_t         *cl;
    ngx_chain_t         *in;

    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    in = lmcf->body_filter_chain;

    /* asking for the eof argument */

    for (cl = in; cl; cl = cl->next) {
        if (cl->buf->last_buf || cl->buf->last_in_chain) {
            return 1;
        }
    }

    return 0;
}


int
ngx_http_lua_ffi_get_body_filter_param_body(ngx_http_request_t *r,
    u_char **data_p, size_t *len_p)
{
    size_t               size;
    ngx_chain_t         *cl;
    ngx_buf_t           *b;
    ngx_chain_t         *in;

    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    in = lmcf->body_filter_chain;

    size = 0;

    if (in == NULL) {
        /* being a cleared chain on the Lua land */
        *len_p = 0;
        return NGX_OK;
    }

    if (in->next == NULL) {

        dd("seen only single buffer");

        b = in->buf;
        *data_p = b->pos;
        *len_p = b->last - b->pos;
        return NGX_OK;
    }

    dd("seen multiple buffers");

    for (cl = in; cl; cl = cl->next) {
        b = cl->buf;

        size += b->last - b->pos;

        if (b->last_buf || b->last_in_chain) {
            break;
        }
    }

    /* the buf is need and is not allocated from Lua land yet, return with
     * the actual size */
    *len_p = size;
    return NGX_AGAIN;
}


int
ngx_http_lua_ffi_copy_body_filter_param_body(ngx_http_request_t *r,
    u_char *data)
{
    u_char              *p;
    ngx_chain_t         *cl;
    ngx_buf_t           *b;
    ngx_chain_t         *in;

    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    in = lmcf->body_filter_chain;

    for (p = data, cl = in; cl; cl = cl->next) {
        b = cl->buf;
        p = ngx_copy(p, b->pos, b->last - b->pos);

        if (b->last_buf || b->last_in_chain) {
            break;
        }
    }

    return NGX_OK;
}


int
ngx_http_lua_body_filter_param_set(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx)
{
    int                      type;
    int                      idx;
    int                      found;
    u_char                  *data;
    size_t                   size;
    unsigned                 last;
    unsigned                 flush = 0;
    ngx_buf_t               *b;
    ngx_chain_t             *cl;
    ngx_chain_t             *in;

    ngx_http_lua_main_conf_t    *lmcf;

    idx = luaL_checkint(L, 2);

    dd("index: %d", idx);

    if (idx != 1 && idx != 2) {
        return luaL_error(L, "bad index: %d", idx);
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    if (idx == 2) {
        /* overwriting the eof flag */
        last = lua_toboolean(L, 3);

        in = lmcf->body_filter_chain;

        if (last) {
            ctx->seen_last_in_filter = 1;

            /* the "in" chain cannot be NULL and we set the "last_buf" or
             * "last_in_chain" flag in the last buf of "in" */

            for (cl = in; cl; cl = cl->next) {
                if (cl->next == NULL) {
                    if (r == r->main) {
                        cl->buf->last_buf = 1;

                    } else {
                        cl->buf->last_in_chain = 1;
                    }

                    break;
                }
            }

        } else {
            /* last == 0 */

            found = 0;

            for (cl = in; cl; cl = cl->next) {
                b = cl->buf;

                if (b->last_buf) {
                    b->last_buf = 0;
                    found = 1;
                }

                if (b->last_in_chain) {
                    b->last_in_chain = 0;
                    found = 1;
                }

                if (found && b->last == b->pos && !ngx_buf_in_memory(b)) {
                    /* make it a special sync buf to make
                     * ngx_http_write_filter_module happy. */
                    b->sync = 1;
                }
            }

            ctx->seen_last_in_filter = 0;
        }

        return 0;
    }

    /* idx == 1, overwriting the chunk data */

    type = lua_type(L, 3);

    switch (type) {
    case LUA_TSTRING:
    case LUA_TNUMBER:
        data = (u_char *) lua_tolstring(L, 3, &size);
        break;

    case LUA_TNIL:
        /* discard the buffers */

        in = lmcf->body_filter_chain;

        last = 0;

        for (cl = in; cl; cl = cl->next) {
            b = cl->buf;

            if (b->flush) {
                flush = 1;
            }

            if (b->last_in_chain || b->last_buf) {
                last = 1;
            }

            dd("mark the buf as consumed: %d", (int) ngx_buf_size(b));
            b->pos = b->last;
        }

        /* cl == NULL */

        goto done;

    case LUA_TTABLE:
        size = ngx_http_lua_calc_strlen_in_table(L, 3 /* index */, 3 /* arg */,
                                                 1 /* strict */);
        data = NULL;
        break;

    default:
        return luaL_error(L, "bad chunk data type: %s",
                          lua_typename(L, type));
    }

    in = lmcf->body_filter_chain;

    last = 0;

    for (cl = in; cl; cl = cl->next) {
        b = cl->buf;

        if (b->flush) {
            flush = 1;
        }

        if (b->last_buf || b->last_in_chain) {
            last = 1;
        }

        dd("mark the buf as consumed: %d", (int) ngx_buf_size(cl->buf));
        cl->buf->pos = cl->buf->last;
    }

    /* cl == NULL */

    if (size == 0) {
        goto done;
    }

    cl = ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                         &ctx->free_bufs, size);
    if (cl == NULL) {
        return luaL_error(L, "no memory");
    }

    cl->buf->tag = (ngx_buf_tag_t) &ngx_http_lua_body_filter;
    if (type == LUA_TTABLE) {
        cl->buf->last = ngx_http_lua_copy_str_in_table(L, 3, cl->buf->last);

    } else {
        cl->buf->last = ngx_copy(cl->buf->pos, data, size);
    }

done:

    if (last || flush) {
        if (cl == NULL) {
            cl = ngx_http_lua_chain_get_free_buf(r->connection->log,
                                                 r->pool,
                                                 &ctx->free_bufs, 0);
            if (cl == NULL) {
                return luaL_error(L, "no memory");
            }

            cl->buf->tag = (ngx_buf_tag_t) &ngx_http_lua_body_filter;
        }

        if (last) {
            ctx->seen_last_in_filter = 1;

            if (r == r->main) {
                cl->buf->last_buf = 1;

            } else {
                cl->buf->last_in_chain = 1;
            }
        }

        if (flush) {
            cl->buf->flush = 1;
        }
    }

    lmcf->body_filter_chain = cl;

    return 0;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
