
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
#include "ngx_http_lua_time.h"
#include "ngx_http_lua_log.h"
#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_variable.h"
#include "ngx_http_lua_string.h"
#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_consts.h"
#include "ngx_http_lua_output.h"


static void ngx_http_lua_body_filter_by_lua_env(lua_State *L,
    ngx_http_request_t *r, ngx_chain_t *in);
static ngx_http_output_body_filter_pt ngx_http_next_body_filter;


/* light user data key for the ngx_chain_t *in pointer in the
 * Lua VM registory */
static char ngx_http_lua_body_filter_chain_key;


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
    /*  set nginx request pointer to current lua thread's globals table */
    ngx_http_lua_set_req(L, r);

    lua_pushlightuserdata(L, &ngx_http_lua_body_filter_chain_key);
    lua_pushlightuserdata(L, in);
    lua_rawset(L, LUA_GLOBALSINDEX);

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
    ngx_http_lua_create_new_global_table(L, 0 /* narr */, 1 /* nrec */);

    /*  {{{ make new env inheriting main thread's globals table */
    lua_createtable(L, 0, 1 /* nrec */);    /*  the metatable for the new
                                                env */
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
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

        /*  error occured */
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
    rc = ngx_http_lua_cache_loadbuffer(L, llcf->body_filter_src.value.data,
                                       llcf->body_filter_src.value.len,
                                       llcf->body_filter_src_key,
                                       "body_filter_by_lua");
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
    rc = ngx_http_lua_cache_loadfile(L, script_path,
                                     llcf->body_filter_src_key);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    /*  make sure we have a valid code chunk */
    assert(lua_isfunction(L, -1));

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
    ngx_http_cleanup_t          *cln;
    lua_State                   *L;
    ngx_chain_t                 *out;
    ngx_buf_tag_t                tag;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua body filter for user lua code, uri \"%V\"", &r->uri);

    if (in == NULL) {
        return ngx_http_next_body_filter(r, in);
    }

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->body_filter_handler == NULL) {
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

        return NGX_OK;
    }

    if (ctx->cleanup == NULL) {
        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            return NGX_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup_handler;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;
    }

    old_context = ctx->context;
    ctx->context = NGX_HTTP_LUA_CONTEXT_BODY_FILTER;

    dd("calling body filter handler");
    rc = llcf->body_filter_handler(r, in);

    dd("calling body filter handler returned %d", (int) rc);

    ctx->context = old_context;

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    L = ngx_http_lua_get_lua_vm(r, ctx);

    lua_pushlightuserdata(L, &ngx_http_lua_body_filter_chain_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    out = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (in == out) {
        return ngx_http_next_body_filter(r, in);
    }

    /* in != out */
    rc = ngx_http_next_body_filter(r, out);

    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    tag = (ngx_buf_tag_t) &ngx_http_lua_module;

#if nginx_version >= 1001004
    ngx_chain_update_chains(r->pool,
#else
    ngx_chain_update_chains(
#endif
                            &ctx->free_bufs, &ctx->busy_bufs, &out, tag);

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
ngx_http_lua_body_filter_param_get(lua_State *L)
{
    u_char              *data, *p;
    size_t               size;
    ngx_chain_t         *cl;
    ngx_buf_t           *b;
    int                  idx;
    ngx_chain_t         *in;

    idx = luaL_checkint(L, 2);

    dd("index: %d", idx);

    if (idx != 1 && idx != 2) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushlightuserdata(L, &ngx_http_lua_body_filter_chain_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    in = lua_touserdata(L, -1);

    if (idx == 2) {
        /* asking for the eof argument */

        for (cl = in; cl; cl = cl->next) {
            if (cl->buf->last_buf || cl->buf->last_in_chain) {
                lua_pushboolean(L, 1);
                return 1;
            }
        }

        lua_pushboolean(L, 0);
        return 1;
    }

    /* idx == 1 */

    size = 0;

    if (in->next == NULL) {

        dd("seen only single buffer");

        b = in->buf;
        lua_pushlstring(L, (char *) b->pos, b->last - b->pos);
        return 1;
    }

    dd("seen multiple buffers");

    for (cl = in; cl; cl = cl->next) {
        b = cl->buf;

        size += b->last - b->pos;

        if (b->last_buf || b->last_in_chain) {
            break;
        }
    }

    data = (u_char *) lua_newuserdata(L, size);

    for (p = data, cl = in; cl; cl = cl->next) {
        b = cl->buf;
        p = ngx_copy(p, b->pos, b->last - b->pos);

        if (b->last_buf || b->last_in_chain) {
            break;
        }
    }

    lua_pushlstring(L, (char *) data, size);
    return 1;
}


int
ngx_http_lua_body_filter_param_set(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx)
{
    int                      type;
    int                      idx;
    u_char                  *data;
    size_t                   size;
    unsigned                 last;
    ngx_chain_t             *cl;
    ngx_chain_t             *in;
    ngx_buf_tag_t            tag;

    idx = luaL_checkint(L, 2);

    dd("index: %d", idx);

    if (idx != 1 && idx != 2) {
        return luaL_error(L, "bad index: %d", idx);
    }

    if (idx == 2) {
        /* overwriting the eof flag */
        last = lua_toboolean(L, 3);

        lua_pushlightuserdata(L, &ngx_http_lua_body_filter_chain_key);
        lua_rawget(L, LUA_GLOBALSINDEX);
        in = lua_touserdata(L, -1);

        if (last) {
            ctx->seen_last_in_filter = 1;

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

            for (cl = in; cl; cl = cl->next) {
                if (cl->buf->last_buf) {
                    cl->buf->last_buf = 0;
                }

                if (cl->buf->last_in_chain) {
                    cl->buf->last_in_chain = 0;
                }

                if (cl->buf->last - cl->buf->pos == 0) {
                    cl->buf->temporary = 0;
                    cl->buf->memory = 0;
                    cl->buf->mmap = 0;
                    cl->buf->in_file = 0;
                    cl->buf->sync = 1;
                }
            }
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
        lua_pushlightuserdata(L, &ngx_http_lua_body_filter_chain_key); /* key */
        lua_pushvalue(L, -1); /* key key */
        lua_rawget(L, LUA_GLOBALSINDEX); /* key val */
        in = lua_touserdata(L, -1);
        lua_pop(L, 1); /* key */

        for (cl = in; cl; cl = cl->next) {
            dd("mark the buf as consumed: %d", (int) ngx_buf_size(cl->buf));
            cl->buf->pos = cl->buf->last;
            cl->buf->file_pos = cl->buf->file_last;

            cl->buf->temporary = 0;
            cl->buf->memory = 0;
            cl->buf->mmap = 0;
            cl->buf->in_file = 0;
            cl->buf->sync = 1;
        }

        return 0;

    case LUA_TTABLE:
        size = ngx_http_lua_calc_strlen_in_table(L, 3 /* index */, 3 /* arg */,
                                                 1 /* strict */);
        data = NULL;
        break;

    default:
        return luaL_error(L, "bad chunk data type: %s",
                          lua_typename(L, type));
    }

    lua_pushlightuserdata(L, &ngx_http_lua_body_filter_chain_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    in = lua_touserdata(L, -1);
    lua_pop(L, 1);

    last = 0;
    for (cl = in; cl; cl = cl->next) {
        if (cl->buf->last_buf || cl->buf->last_in_chain) {
            last = 1;
        }

        dd("mark the buf as consumed: %d", (int) ngx_buf_size(cl->buf));
        cl->buf->pos = cl->buf->last;
    }

    if (size == 0) {
        if (last) {
            if (r == r->main) {
                in->buf->last_buf = 1;

            } else {
                in->buf->last_in_chain = 1;
            }

        } else {
            for (cl = in; cl; cl = cl->next) {
                cl->buf->sync = 1;
                cl->buf->temporary = 0;
                cl->buf->memory = 0;
                cl->buf->mmap = 0;
                cl->buf->in_file = 0;
            }
        }

        return 0;
    }

    tag = (ngx_buf_tag_t) &ngx_http_lua_module;

    cl = ngx_http_lua_chains_get_free_buf(r->connection->log, r->pool,
                                          &ctx->free_bufs, size, tag);
    if (cl == NULL) {
        return luaL_error(L, "out of memory");
    }

    if (type == LUA_TTABLE) {
        cl->buf->last = ngx_http_lua_copy_str_in_table(L, 3, cl->buf->last);

    } else {
        cl->buf->last = ngx_copy(cl->buf->pos, data, size);
    }

    if (last) {
        ctx->seen_last_in_filter = 1;

        if (r == r->main) {
            cl->buf->last_buf = 1;

        } else {
            cl->buf->last_in_chain = 1;
        }
    }

    lua_pushlightuserdata(L, &ngx_http_lua_body_filter_chain_key);
    lua_pushlightuserdata(L, cl);
    lua_rawset(L, LUA_GLOBALSINDEX);
    return 0;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
