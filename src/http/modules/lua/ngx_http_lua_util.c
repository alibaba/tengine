/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "nginx.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_args.h"
#include "ngx_http_lua_uri.h"
#include "ngx_http_lua_req_body.h"
#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_output.h"
#include "ngx_http_lua_time.h"
#include "ngx_http_lua_control.h"
#include "ngx_http_lua_ndk.h"
#include "ngx_http_lua_subrequest.h"
#include "ngx_http_lua_log.h"
#include "ngx_http_lua_variable.h"
#include "ngx_http_lua_string.h"
#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_consts.h"
#include "ngx_http_lua_req_method.h"
#include "ngx_http_lua_shdict.h"
#include "ngx_http_lua_socket_tcp.h"
#include "ngx_http_lua_socket_udp.h"
#include "ngx_http_lua_sleep.h"
#include "ngx_http_lua_setby.h"
#include "ngx_http_lua_headerfilterby.h"
#include "ngx_http_lua_bodyfilterby.h"
#include "ngx_http_lua_logby.h"
#include "ngx_http_lua_phase.h"


char ngx_http_lua_code_cache_key;
char ngx_http_lua_ctx_tables_key;
char ngx_http_lua_regex_cache_key;
char ngx_http_lua_socket_pool_key;
char ngx_http_lua_request_key;


/*  coroutine anchoring table key in Lua vm registry */
static char ngx_http_lua_coroutines_key;

static ngx_int_t ngx_http_lua_send_http10_headers(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx);
static void ngx_http_lua_init_registry(ngx_conf_t *cf, lua_State *L);
static void ngx_http_lua_init_globals(ngx_conf_t *cf, lua_State *L);
static void ngx_http_lua_set_path(ngx_conf_t *cf, lua_State *L, int tab_idx,
        const char *fieldname, const char *path, const char *default_path);
static ngx_int_t ngx_http_lua_handle_exec(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int cc_ref);
static ngx_int_t ngx_http_lua_handle_exit(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int cc_ref);
static ngx_int_t ngx_http_lua_handle_rewrite_jump(lua_State *L,
    ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, int cc_ref);
static int ngx_http_lua_ngx_check_aborted(lua_State *L);
static int ngx_http_lua_thread_traceback(lua_State *L, lua_State *cc);
static void ngx_http_lua_inject_ngx_api(ngx_conf_t *cf, lua_State *L);
static void ngx_http_lua_inject_arg_api(lua_State *L);
static int ngx_http_lua_param_get(lua_State *L);
static int ngx_http_lua_param_set(lua_State *L);


#ifndef LUA_PATH_SEP
#define LUA_PATH_SEP ";"
#endif

#define AUX_MARK "\1"


enum {
    LEVELS1	= 12,       /* size of the first part of the stack */
    LEVELS2	= 10        /* size of the second part of the stack */
};


static void
ngx_http_lua_set_path(ngx_conf_t *cf, lua_State *L, int tab_idx,
        const char *fieldname, const char *path, const char *default_path)
{
    const char          *tmp_path;
    const char          *prefix;

    /* XXX here we use some hack to simplify string manipulation */
    tmp_path = luaL_gsub(L, path, LUA_PATH_SEP LUA_PATH_SEP,
            LUA_PATH_SEP AUX_MARK LUA_PATH_SEP);

    lua_pushlstring(L, (char *) cf->cycle->prefix.data, cf->cycle->prefix.len);
    prefix = lua_tostring(L, -1);
    tmp_path = luaL_gsub(L, tmp_path, "$prefix", prefix);
    tmp_path = luaL_gsub(L, tmp_path, "${prefix}", prefix);
    lua_pop(L, 3);

    dd("tmp_path path: %s", tmp_path);

    tmp_path = luaL_gsub(L, tmp_path, AUX_MARK, default_path);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua setting lua package.%s to \"%s\"", fieldname, tmp_path);

    lua_remove(L, -2);

    /* fix negative index as there's new data on stack */
    tab_idx = (tab_idx < 0) ? (tab_idx - 1) : tab_idx;
    lua_setfield(L, tab_idx, fieldname);
}


/**
 * Create new table and set _G field to itself.
 *
 * After:
 *         | new table | <- top
 *         |    ...    |
 * */
void
ngx_http_lua_create_new_global_table(lua_State *L, int narr, int nrec)
{
    lua_createtable(L, narr, nrec + 1);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "_G");
}


lua_State *
ngx_http_lua_new_state(ngx_conf_t *cf, ngx_http_lua_main_conf_t *lmcf)
{
    lua_State       *L;
    const char      *old_path;
    const char      *new_path;
    size_t           old_path_len;
    const char      *old_cpath;
    const char      *new_cpath;
    size_t           old_cpath_len;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0, "lua creating new vm state");

    L = luaL_newstate();
    if (L == NULL) {
        return NULL;
    }

    luaL_openlibs(L);

    lua_getglobal(L, "package");

    if (!lua_istable(L, -1)) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                "the \"package\" table does not exist");
        return NULL;
    }

#ifdef LUA_DEFAULT_PATH
#   define LUA_DEFAULT_PATH_LEN (sizeof(LUA_DEFAULT_PATH) - 1)
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua prepending default package.path with %s", LUA_DEFAULT_PATH);

    lua_pushliteral(L, LUA_DEFAULT_PATH ";"); /* package default */
    lua_getfield(L, -2, "path"); /* package default old */
    old_path = lua_tolstring(L, -1, &old_path_len);
    lua_concat(L, 2); /* package new */
    lua_setfield(L, -2, "path"); /* package */
#endif

#ifdef LUA_DEFAULT_CPATH
#   define LUA_DEFAULT_CPATH_LEN (sizeof(LUA_DEFAULT_CPATH) - 1)
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua prepending default package.cpath with %s", LUA_DEFAULT_CPATH);

    lua_pushliteral(L, LUA_DEFAULT_CPATH ";"); /* package default */
    lua_getfield(L, -2, "cpath"); /* package default old */
    old_cpath = lua_tolstring(L, -1, &old_cpath_len);
    lua_concat(L, 2); /* package new */
    lua_setfield(L, -2, "cpath"); /* package */
#endif

    if (lmcf->lua_path.len != 0) {
        lua_getfield(L, -1, "path"); /* get original package.path */
        old_path = lua_tolstring(L, -1, &old_path_len);

        dd("old path: %s", old_path);

        lua_pushlstring(L, (char *) lmcf->lua_path.data, lmcf->lua_path.len);
        new_path = lua_tostring(L, -1);

        ngx_http_lua_set_path(cf, L, -3, "path", new_path, old_path);

        lua_pop(L, 2);
    }

    if (lmcf->lua_cpath.len != 0) {
        lua_getfield(L, -1, "cpath"); /* get original package.cpath */
        old_cpath = lua_tolstring(L, -1, &old_cpath_len);

        dd("old cpath: %s", old_cpath);

        lua_pushlstring(L, (char *) lmcf->lua_cpath.data, lmcf->lua_cpath.len);
        new_cpath = lua_tostring(L, -1);

        ngx_http_lua_set_path(cf, L, -3, "cpath", new_cpath, old_cpath);


        lua_pop(L, 2);
    }

    lua_remove(L, -1); /* remove the "package" table */

    ngx_http_lua_init_registry(cf, L);
    ngx_http_lua_init_globals(cf, L);

    return L;
}


lua_State *
ngx_http_lua_new_thread(ngx_http_request_t *r, lua_State *L, int *ref)
{
    int              base;
    lua_State       *cr;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua creating new thread");

    base = lua_gettop(L);

    lua_pushlightuserdata(L, &ngx_http_lua_coroutines_key);
    lua_rawget(L, LUA_REGISTRYINDEX);

    cr = lua_newthread(L);

    if (cr) {
        /*  {{{ inherit coroutine's globals to main thread's globals table
         *  for print() function will try to find tostring() in current
         *  globals table.
         */
        /*  new globals table for coroutine */
        ngx_http_lua_create_new_global_table(cr, 0, 0);

        lua_createtable(cr, 0, 1);
        lua_pushvalue(cr, LUA_GLOBALSINDEX);
        lua_setfield(cr, -2, "__index");
        lua_setmetatable(cr, -2);

        lua_replace(cr, LUA_GLOBALSINDEX);
        /*  }}} */

        *ref = luaL_ref(L, -2);

        if (*ref == LUA_NOREF) {
            lua_settop(L, base);  /* restore main thread stack */
            return NULL;
        }
    }

    /*  pop coroutine reference on main thread's stack after anchoring it
     *  in registry */
    lua_pop(L, 1);

    return cr;
}


void
ngx_http_lua_del_thread(ngx_http_request_t *r, lua_State *L, int ref)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua deleting thread");

    lua_pushlightuserdata(L, &ngx_http_lua_coroutines_key);
    lua_rawget(L, LUA_REGISTRYINDEX);

    /* release reference to coroutine */
    luaL_unref(L, -1, ref);
    lua_pop(L, 1);
}


ngx_int_t
ngx_http_lua_has_inline_var(ngx_str_t *s)
{
    return (ngx_http_script_variables_count(s) != 0);
}


u_char *
ngx_http_lua_rebase_path(ngx_pool_t *pool, u_char *src, size_t len)
{
    u_char            *p, *dst;

    if (len == 0) {
        return NULL;
    }

    if (src[0] == '/') {
        /* being an absolute path already */
        dst = ngx_palloc(pool, len + 1);
        if (dst == NULL) {
            return NULL;
        }

        p = ngx_copy(dst, src, len);

        *p = '\0';

        return dst;
    }

    dst = ngx_palloc(pool, ngx_cycle->prefix.len + len + 1);
    if (dst == NULL) {
        return NULL;
    }

    p = ngx_copy(dst, ngx_cycle->prefix.data, ngx_cycle->prefix.len);
    p = ngx_copy(p, src, len);

    *p = '\0';

    return dst;
}


ngx_int_t
ngx_http_lua_send_header_if_needed(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx)
{
    ngx_int_t            rc;

    if (!ctx->headers_sent) {
        if (r->headers_out.status == 0) {
            r->headers_out.status = NGX_HTTP_OK;
        }

        if (!ctx->headers_set && ngx_http_set_content_type(r) != NGX_OK) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        if (!ctx->headers_set) {
            ngx_http_clear_content_length(r);
            ngx_http_clear_accept_ranges(r);
        }

        if (!ctx->buffering) {
            dd("sending headers");
            rc = ngx_http_send_header(r);
            ctx->headers_sent = 1;
            return rc;
        }
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_send_chain_link(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx,
        ngx_chain_t *in)
{
    ngx_int_t                     rc;
    ngx_chain_t                  *cl;
    ngx_chain_t                 **ll;
    ngx_http_lua_loc_conf_t      *llcf;

#if 1
    if (ctx->eof) {
        dd("ctx->eof already set");
        return NGX_OK;
    }
#endif

    if ((r->method & NGX_HTTP_HEAD) && !r->header_only) {
        r->header_only = 1;
    }

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->http10_buffering
        && !ctx->buffering
        && !ctx->headers_sent
        && r->http_version < NGX_HTTP_VERSION_11
        && r->headers_out.content_length_n < 0)
    {
        ctx->buffering = 1;
    }

    rc = ngx_http_lua_send_header_if_needed(r, ctx);

    if (rc == NGX_ERROR || rc > NGX_OK) {
        return rc;
    }

    if (r->header_only) {
        ctx->eof = 1;

        if (ctx->buffering) {
            return ngx_http_lua_send_http10_headers(r, ctx);
        }

        return rc;
    }

    if (in == NULL) {
        if (ctx->buffering) {
            rc = ngx_http_lua_send_http10_headers(r, ctx);
            if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
                return rc;
            }

            if (ctx->out) {
                rc = ngx_http_output_filter(r, ctx->out);

                if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
                    return rc;
                }

                ctx->out = NULL;
            }
        }

#if defined(nginx_version) && nginx_version <= 8004

        /* earlier versions of nginx does not allow subrequests
           to send last_buf themselves */
        if (r != r->main) {
            return NGX_OK;
        }

#endif

        ctx->eof = 1;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua sending last buf of the response body");

        rc = ngx_http_send_special(r, NGX_HTTP_LAST);
        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return rc;
        }

        return NGX_OK;
    }

    /* in != NULL */

    if (ctx->buffering) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua buffering output bufs for the HTTP 1.0 request");

        for (cl = ctx->out, ll = &ctx->out; cl; cl = cl->next) {
            ll = &cl->next;
        }

        *ll = in;

        return NGX_OK;
    }

    return ngx_http_output_filter(r, in);
}


static ngx_int_t
ngx_http_lua_send_http10_headers(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx)
{
    size_t               size;
    ngx_chain_t         *cl;
    ngx_int_t            rc;

    if (ctx->headers_sent) {
        return NGX_OK;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua sending HTTP 1.0 response headers");

    if (r->header_only) {
        goto send;
    }

    if (r->headers_out.content_length == NULL) {
        for (size = 0, cl = ctx->out; cl; cl = cl->next) {
            size += ngx_buf_size(cl->buf);
        }

        r->headers_out.content_length_n = (off_t) size;

        if (r->headers_out.content_length) {
            r->headers_out.content_length->hash = 0;
        }
    }

send:
    rc = ngx_http_send_header(r);
    ctx->headers_sent = 1;
    return rc;
}


static void
ngx_http_lua_init_registry(ngx_conf_t *cf, lua_State *L)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua initializing lua registry");

    /* {{{ register a table to anchor lua coroutines reliably:
     * {([int]ref) = [cort]} */
    lua_pushlightuserdata(L, &ngx_http_lua_coroutines_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    /* create the registry entry for the Lua request ctx data table */
    lua_pushlightuserdata(L, &ngx_http_lua_ctx_tables_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);

    /* create the registry entry for the Lua socket connection pool table */
    lua_pushlightuserdata(L, &ngx_http_lua_socket_pool_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);

#if (NGX_PCRE)
    /* create the registry entry for the Lua precompiled regex object cache */
    lua_pushlightuserdata(L, &ngx_http_lua_regex_cache_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);
#endif

    /* {{{ register table to cache user code:
     * {([string]cache_key) = [code closure]} */
    lua_pushlightuserdata(L, &ngx_http_lua_code_cache_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);
    /* }}} */

    lua_pushlightuserdata(L, &ngx_http_lua_cf_log_key);
    lua_pushlightuserdata(L, cf->log);
    lua_rawset(L, LUA_REGISTRYINDEX);
}


static void
ngx_http_lua_init_globals(ngx_conf_t *cf, lua_State *L)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua initializing lua globals");

    /* {{{ remove unsupported globals */
    lua_pushnil(L);
    lua_setfield(L, LUA_GLOBALSINDEX, "coroutine");
    /* }}} */

#if defined(NDK) && NDK
    ngx_http_lua_inject_ndk_api(L);
#endif /* defined(NDK) && NDK */

    ngx_http_lua_inject_ngx_api(cf, L);
}


static void
ngx_http_lua_inject_ngx_api(ngx_conf_t *cf, lua_State *L)
{
    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lua_createtable(L, 0 /* narr */, 89 /* nrec */);    /* ngx.* */

    ngx_http_lua_inject_internal_utils(cf->log, L);

    ngx_http_lua_inject_arg_api(L);

    ngx_http_lua_inject_http_consts(L);
    ngx_http_lua_inject_core_consts(L);

    ngx_http_lua_inject_log_api(L);
    ngx_http_lua_inject_output_api(L);
    ngx_http_lua_inject_time_api(L);
    ngx_http_lua_inject_string_api(L);
    ngx_http_lua_inject_control_api(cf->log, L);
    ngx_http_lua_inject_subrequest_api(L);
    ngx_http_lua_inject_sleep_api(L);
    ngx_http_lua_inject_phase_api(L);

#if (NGX_PCRE)
    ngx_http_lua_inject_regex_api(L);
#endif

    ngx_http_lua_inject_req_api(cf->log, L);
    ngx_http_lua_inject_resp_header_api(L);
    ngx_http_lua_inject_variable_api(L);
    ngx_http_lua_inject_shdict_api(lmcf, L);
    ngx_http_lua_inject_socket_tcp_api(cf->log, L);
    ngx_http_lua_inject_socket_udp_api(cf->log, L);

    ngx_http_lua_inject_misc_api(L);

    lua_getglobal(L, "package"); /* ngx package */
    lua_getfield(L, -1, "loaded"); /* ngx package loaded */
    lua_pushvalue(L, -3); /* ngx package loaded ngx */
    lua_setfield(L, -2, "ngx"); /* ngx package loaded */
    lua_pop(L, 2);

    lua_setglobal(L, "ngx");
}


void
ngx_http_lua_discard_bufs(ngx_pool_t *pool, ngx_chain_t *in)
{
    ngx_chain_t         *cl;

    for (cl = in; cl; cl = cl->next) {
        cl->buf->pos = cl->buf->last;
        cl->buf->file_pos = cl->buf->file_last;
    }
}


ngx_int_t
ngx_http_lua_add_copy_chain(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx,
        ngx_chain_t **chain, ngx_chain_t *in)
{
    ngx_chain_t     *cl, **ll;
    size_t           len;
    ngx_buf_t       *b;

    ll = chain;

    for (cl = *chain; cl; cl = cl->next) {
        ll = &cl->next;
    }

    len = 0;

    for (cl = in; cl; cl = cl->next) {
        if (ngx_buf_in_memory(cl->buf)) {
            len += cl->buf->last - cl->buf->pos;
        }
    }

    if (len == 0) {
        return NGX_OK;
    }

    cl = ngx_http_lua_chains_get_free_buf(r->connection->log, r->pool,
                                          &ctx->free_bufs, len,
                                          (ngx_buf_tag_t) &ngx_http_lua_module);

    if (cl == NULL) {
        return NGX_ERROR;
    }

    dd("chains get free buf: %d == %d", (int) (cl->buf->end - cl->buf->start),
       (int) len);

    b = cl->buf;

    while (in) {
        if (ngx_buf_in_memory(in->buf)) {
            b->last = ngx_copy(b->last, in->buf->pos,
                    in->buf->last - in->buf->pos);
        }

        in = in->next;
    }

    *ll = cl;

    return NGX_OK;
}


void
ngx_http_lua_reset_ctx(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_ctx_t *ctx)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua reset ctx");

    if (ctx->cc_ref != LUA_NOREF) {
        ngx_http_lua_del_thread(r, L, ctx->cc_ref);
        ctx->cc_ref = LUA_NOREF;
    }

    ctx->waiting = 0;
    ctx->done = 0;

    ctx->entered_rewrite_phase = 0;
    ctx->entered_access_phase = 0;
    ctx->entered_content_phase = 0;

    ctx->exit_code = 0;
    ctx->exited = 0;
    ctx->exec_uri.data = NULL;
    ctx->exec_uri.len = 0;

    ctx->sr_statuses = NULL;
    ctx->sr_headers = NULL;
    ctx->sr_bodies = NULL;

    ctx->aborted = 0;
}


/* post read callback for rewrite and access phases */
void
ngx_http_lua_generic_phase_post_read(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua post read for rewrite/access phases");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    ctx->read_body_done = 1;

#if defined(nginx_version) && nginx_version >= 8011
    r->main->count--;
#endif

    if (ctx->waiting_more_body) {
        ctx->waiting_more_body = 0;
        ngx_http_core_run_phases(r);
    }
}


void
ngx_http_lua_request_cleanup(void *data)
{
    ngx_http_request_t          *r = data;
    lua_State                   *L;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_loc_conf_t     *llcf;
    ngx_http_lua_main_conf_t    *lmcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua request cleanup");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    /*  force coroutine handling the request quit */
    if (ctx == NULL) {
        return;
    }

    if (ctx->cleanup) {
        *ctx->cleanup = NULL;
        ctx->cleanup = NULL;
    }

    if (ctx->sleep.timer_set) {
        dd("cleanup: deleting timer for ngx.sleep");

        ngx_del_timer(&ctx->sleep);
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    L = lmcf->lua;

    /* we cannot release the ngx.ctx table if we have log_by_lua* hooks
     * because request cleanup runs before log phase handlers */

    if (ctx->ctx_ref != LUA_NOREF) {

        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->log_handler == NULL) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                    "lua release ngx.ctx");

            lua_pushlightuserdata(L, &ngx_http_lua_ctx_tables_key);
            lua_rawget(L, LUA_REGISTRYINDEX);
            luaL_unref(L, -1, ctx->ctx_ref);
            ctx->ctx_ref = LUA_NOREF;
            lua_pop(L, 1);
        }
    }

    if (ctx->cc_ref == LUA_NOREF) {
        return;
    }

    lua_pushlightuserdata(L, &ngx_http_lua_coroutines_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_rawgeti(L, -1, ctx->cc_ref);

    if (lua_isthread(L, -1)) {
        /*  coroutine not finished yet, force quit */
        ngx_http_lua_del_thread(r, L, ctx->cc_ref);
        ctx->cc_ref = LUA_NOREF;

    } else {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua internal error: not a thread object for the current "
                "coroutine");

        luaL_unref(L, -2, ctx->cc_ref);
    }

    lua_pop(L, 2);
}


ngx_int_t
ngx_http_lua_run_thread(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int nret)
{
    int                      rv;
    int                      cc_ref;
    lua_State               *cc;
    const char              *err, *msg, *trace;
    ngx_int_t                rc;
#if (NGX_PCRE)
    ngx_pool_t              *old_pool;
    unsigned                 pcre_pool_resumed = 0;
#endif

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua run thread");

    /* set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    dd("ctx = %p", ctx);

    cc = ctx->cc;
    cc_ref = ctx->cc_ref;

#if (NGX_PCRE)
        /* XXX: work-around to nginx regex subsystem */
    old_pool = ngx_http_lua_pcre_malloc_init(r->pool);
#endif

    NGX_LUA_EXCEPTION_TRY {
        dd("calling lua_resume: vm %p, nret %d", cc, (int) nret);

        /*  run code */
        rv = lua_resume(cc, nret);

#if (NGX_PCRE)
        /* XXX: work-around to nginx regex subsystem */
        ngx_http_lua_pcre_malloc_done(old_pool);
        pcre_pool_resumed = 1;
#endif

#if 0
        /* test the longjmp thing */
        if (rand() % 2 == 0) {
            NGX_LUA_EXCEPTION_THROW(1);
        }
#endif

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua resume returned %d", rv);

        switch (rv) {
            case LUA_YIELD:
                /*  yielded, let event handler do the rest job */
                /*  FIXME: add io cmd dispatcher here */

                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                        "lua thread yielded");

                if (r->uri_changed) {
                    return ngx_http_lua_handle_rewrite_jump(L, r, ctx, cc_ref);
                }

                if (ctx->exited) {
                    return ngx_http_lua_handle_exit(L, r, ctx, cc_ref);
                }

                if (ctx->exec_uri.len) {
                    return ngx_http_lua_handle_exec(L, r, ctx, cc_ref);
                }

#if 0
                ngx_http_lua_dump_postponed(r);
#endif

                lua_settop(cc, 0);
                return NGX_AGAIN;

            case 0:
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                        "lua thread ended normally");

#if 0
                ngx_http_lua_dump_postponed(r);
#endif

                ngx_http_lua_del_thread(r, L, cc_ref);
                ctx->cc_ref = LUA_NOREF;

                if (ctx->entered_content_phase) {
                    rc = ngx_http_lua_send_chain_link(r, ctx,
                            NULL /* indicate last_buf */);

                    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
                        return rc;
                    }
                }

                return NGX_OK;

            case LUA_ERRRUN:
                err = "runtime error";
                break;

            case LUA_ERRSYNTAX:
                err = "syntax error";
                break;

            case LUA_ERRMEM:
                err = "memory allocation error";
                break;

            case LUA_ERRERR:
                err = "error handler error";
                break;

            default:
                err = "unknown error";
                break;
        }

        if (lua_isstring(cc, -1)) {
            dd("user custom error msg");
            msg = lua_tostring(cc, -1);

        } else {
            msg = "unknown reason";
        }

        ngx_http_lua_thread_traceback(L, cc);
        trace = lua_tostring(L, -1);
        lua_pop(L, 1);

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "lua handler aborted: %s: %s\n%s", err, msg, trace);

        ngx_http_lua_del_thread(r, L, cc_ref);
        ctx->cc_ref = LUA_NOREF;

        ngx_http_lua_request_cleanup(r);

        dd("headers sent? %d", ctx->headers_sent ? 1 : 0);

        return ctx->headers_sent ? NGX_ERROR : NGX_HTTP_INTERNAL_SERVER_ERROR;

    } NGX_LUA_EXCEPTION_CATCH {

        dd("nginx execution restored");

#if (NGX_PCRE)
        if (!pcre_pool_resumed) {
            ngx_http_lua_pcre_malloc_done(old_pool);
        }
#endif
    }

    return NGX_ERROR;
}


ngx_int_t
ngx_http_lua_wev_handler(ngx_http_request_t *r)
{
    ngx_int_t                    rc;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_main_conf_t    *lmcf;
    int                          nret = 0;
    ngx_connection_t            *c;
    ngx_event_t                 *wev;
    ngx_http_core_loc_conf_t    *clcf;
    ngx_chain_t                 *cl;

    ngx_http_lua_socket_tcp_upstream_t      *tcp;
    ngx_http_lua_socket_udp_upstream_t      *udp;

    c = r->connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
            "lua run write event handler");

    wev = c->write;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        goto error;
    }

    clcf = ngx_http_get_module_loc_conf(r->main, ngx_http_core_module);

    if (wev->timedout) {
        if (!wev->delayed) {
            ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT,
                          "client timed out");
            c->timedout = 1;

            if (ctx->entered_content_phase) {
                ngx_http_finalize_request(r, NGX_HTTP_REQUEST_TIME_OUT);
            }

            return NGX_HTTP_REQUEST_TIME_OUT;
        }

        wev->timedout = 0;
        wev->delayed = 0;

        if (!wev->ready) {
            ngx_add_timer(wev, clcf->send_timeout);

            if (ngx_handle_write_event(wev, clcf->send_lowat) != NGX_OK) {
                ngx_http_finalize_request(r, NGX_ERROR);
                return NGX_ERROR;
            }
        }
    }

    dd("wev handler %.*s %.*s a:%d, postponed:%p",
            (int) r->uri.len, r->uri.data,
            (int) ngx_cached_err_log_time.len,
            ngx_cached_err_log_time.data,
            r == c->data,
            r->postponed);
#if 0
    ngx_http_lua_dump_postponed(r);
#endif

    dd("ctx = %p", ctx);
    dd("request done: %d", (int) r->done);
    dd("cleanup done: %p", ctx->cleanup);

    if (ctx->cleanup == NULL) {
        /* already done */
        dd("cleanup is null: %.*s", (int) r->uri.len, r->uri.data);

        if (ctx->entered_content_phase) {
            ngx_http_finalize_request(r,
                    ngx_http_lua_flush_postponed_outputs(r));
        }

        return NGX_OK;
    }

    if (ctx->waiting_more_body && !ctx->req_read_body_done) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                "lua write event handler waiting for more request body data");

        return NGX_DONE;
    }

    dd("waiting: %d, done: %d", (int) ctx->waiting,
            ctx->done);

    if (ctx->waiting && !ctx->done) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                "lua waiting for pending subrequests");

#if 0
        ngx_http_lua_dump_postponed(r);
#endif

        if (r == c->data && r->postponed) {
            if (r->postponed->request) {
                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                        "lua activating the next postponed request %V?%V",
                        &r->postponed->request->uri,
                        &r->postponed->request->args);

                c->data = r->postponed->request;

#if defined(nginx_version) && nginx_version >= 8012
                ngx_http_post_request(r->postponed->request, NULL);
#else
                ngx_http_post_request(r->postponed->request);
#endif

            } else {
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                        "lua flushing postponed output");

                ngx_http_lua_flush_postponed_outputs(r);
            }
        }

        return NGX_DONE;
    }

    dd("req read body done: %d", (int) ctx->req_read_body_done);

    if (c->buffered) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                "lua wev handler flushing output: buffered 0x%uxd",
                c->buffered);

        rc = ngx_http_output_filter(r, NULL);

        if (rc == NGX_ERROR || rc > NGX_OK) {
            if (ctx->entered_content_phase) {
                ngx_http_finalize_request(r, rc);
                return NGX_DONE;
            }

            return rc;
        }

        if (ctx->busy_bufs) {
            cl = NULL;

            dd("updating chains...");

#if nginx_version >= 1001004
            ngx_chain_update_chains(r->pool,
#else
            ngx_chain_update_chains(
#endif
                                    &ctx->free_bufs, &ctx->busy_bufs, &cl,
                                    (ngx_buf_tag_t) &ngx_http_lua_module);

            dd("update lua buf tag: %p, buffered: %x, busy bufs: %p",
                &ngx_http_lua_module, (int) c->buffered, ctx->busy_bufs);
        }

        if (c->buffered) {

            if (!wev->delayed) {
                ngx_add_timer(wev, clcf->send_timeout);
            }

            if (ngx_handle_write_event(wev, clcf->send_lowat) != NGX_OK) {
                if (ctx->entered_content_phase) {
                    ngx_http_finalize_request(r, NGX_ERROR);
                    return NGX_DONE;
                }

                return NGX_ERROR;
            }

            if (ctx->waiting_flush) {
                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                        "lua flush still waiting: buffered 0x%uxd",
                        c->buffered);

                return NGX_DONE;
            }
        }
    }

    if (ctx->sleep.timer_set) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua still waiting for a sleep timer: \"%V?%V\"",
                       &r->uri, &r->args);

        if (wev->ready) {
            ngx_handle_write_event(wev, 0);
        }

        return NGX_DONE;
    }

    if (ctx->sleep.timedout) {
        ctx->sleep.timedout = 0;
        nret = 0;
        goto run;
    }

    if (ctx->socket_busy && !ctx->socket_ready) {
        return NGX_DONE;
    }

    if (ctx->udp_socket_busy && !ctx->udp_socket_ready) {
        return NGX_DONE;
    }

    if (!ctx->udp_socket_busy && ctx->udp_socket_ready) {
        ctx->udp_socket_ready = 0;

        udp = ctx->data;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua dup socket calling prepare retvals handler %p",
                       udp->prepare_retvals);

        nret = udp->prepare_retvals(r, udp, ctx->cc);
        if (nret == NGX_AGAIN) {
            return NGX_DONE;
        }

        goto run;
    }

    if (!ctx->socket_busy && ctx->socket_ready) {

        dd("resuming socket api");

        dd("setting socket_ready to 0");

        ctx->socket_ready = 0;

        tcp = ctx->data;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua tcp socket calling prepare retvals handler %p",
                       tcp->prepare_retvals);

        nret = tcp->prepare_retvals(r, tcp, ctx->cc);
        if (nret == NGX_AGAIN) {
            return NGX_DONE;
        }

        goto run;

    } else if (ctx->waiting_flush) {

        ctx->waiting_flush = 0;
        nret = 0;

        goto run;

    } else if (ctx->req_read_body_done) {

        dd("turned off req read body done");

        ctx->req_read_body_done = 0;

        nret = 0;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                "lua read req body done, resuming lua thread");

        goto run;

    } else if (ctx->done) {

        ctx->done = 0;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                "lua run subrequests done, resuming lua thread");

        dd("nsubreqs: %d", (int) ctx->nsubreqs);

        ngx_http_lua_handle_subreq_responses(r, ctx);

        dd("free sr_statues/headers/bodies memory ASAP");

#if 1
        ngx_pfree(r->pool, ctx->sr_statuses);

        ctx->sr_statuses = NULL;
        ctx->sr_headers = NULL;
        ctx->sr_bodies = NULL;
#endif

        nret = ctx->nsubreqs;

        dd("location capture nret: %d", (int) nret);

        goto run;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
            "useless lua write event handler");

    if (ctx->entered_content_phase) {
        ngx_http_finalize_request(r, NGX_DONE);
    }

    return NGX_OK;

run:
    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    dd("about to run thread for %.*s...", (int) r->uri.len, r->uri.data);

    rc = ngx_http_lua_run_thread(lmcf->lua, r, ctx, nret);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
            "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return NGX_DONE;
    }

    if (rc == NGX_DONE) {
        ngx_http_finalize_request(r, rc);
        return NGX_DONE;
    }

    dd("entered content phase: %d", (int) ctx->entered_content_phase);

    if (ctx->entered_content_phase) {
        ngx_http_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;

error:
    if (ctx && ctx->entered_content_phase) {
        ngx_http_finalize_request(r,
                ctx->headers_sent ? NGX_ERROR: NGX_HTTP_INTERNAL_SERVER_ERROR);
    }

    return NGX_ERROR;
}


u_char *
ngx_http_lua_digest_hex(u_char *dest, const u_char *buf, int buf_len)
{
    ngx_md5_t                     md5;
    u_char                        md5_buf[MD5_DIGEST_LENGTH];

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, buf, buf_len);
    ngx_md5_final(md5_buf, &md5);

    return ngx_hex_dump(dest, md5_buf, sizeof(md5_buf));
}


void
ngx_http_lua_dump_postponed(ngx_http_request_t *r)
{
    ngx_http_postponed_request_t    *pr;
    ngx_uint_t                       i;
    ngx_str_t                        out;
    size_t                           len;
    ngx_chain_t                     *cl;
    u_char                          *p;
    ngx_str_t                        nil_str;

    ngx_str_set(&nil_str, "(nil)");

    for (i = 0, pr = r->postponed; pr; pr = pr->next, i++) {
        out.data = NULL;
        out.len = 0;

        len = 0;
        for (cl = pr->out; cl; cl = cl->next) {
            len += ngx_buf_size(cl->buf);
        }

        if (len) {
            p = ngx_palloc(r->pool, len);
            if (p == NULL) {
                return;
            }

            out.data = p;

            for (cl = pr->out; cl; cl = cl->next) {
                p = ngx_copy(p, cl->buf->pos, ngx_buf_size(cl->buf));
            }

            out.len = len;
        }

        ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                "postponed request for %V: "
                "c:%d, "
                "a:%d, i:%d, r:%V, out:%V",
                &r->uri,
                r->main->count,
                r == r->connection->data, i,
                pr->request ? &pr->request->uri : &nil_str, &out);
    }
}


ngx_int_t
ngx_http_lua_flush_postponed_outputs(ngx_http_request_t *r)
{
    if (r == r->connection->data && r->postponed) {
        /* notify the downstream postpone filter to flush the postponed
         * outputs of the current request */
        return ngx_http_lua_next_body_filter(r, NULL);
    }

    /* do nothing */
    return NGX_OK;
}


void
ngx_http_lua_set_multi_value_table(lua_State *L, int index)
{
    if (index < 0) {
        index = lua_gettop(L) + index + 1;
    }

    lua_pushvalue(L, -2); /* stack: table key value key */
    lua_rawget(L, index);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1); /* stack: table key value */
        lua_rawset(L, index); /* stack: table */

    } else {
        if (!lua_istable(L, -1)) {
            /* just inserted one value */
            lua_createtable(L, 4, 0);
                /* stack: table key value value table */
            lua_insert(L, -2);
                /* stack: table key value table value */
            lua_rawseti(L, -2, 1);
                /* stack: table key value table */
            lua_insert(L, -2);
                /* stack: table key table value */

            lua_rawseti(L, -2, 2); /* stack: table key table */

            lua_rawset(L, index); /* stack: table */

        } else {
            /* stack: table key value table */
            lua_insert(L, -2); /* stack: table key table value */

            lua_rawseti(L, -2, lua_objlen(L, -2) + 1);
                /* stack: table key table  */
            lua_pop(L, 2); /* stack: table */
        }
    }
}


uintptr_t
ngx_http_lua_escape_uri(u_char *dst, u_char *src, size_t size, ngx_uint_t type)
{
    ngx_uint_t      n;
    uint32_t       *escape;
    static u_char   hex[] = "0123456789abcdef";

                    /* " ", "#", "%", "?", %00-%1F, %7F-%FF */

    static uint32_t   uri[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0xfc00886d, /* 1111 1100 0000 0000  1000 1000 0110 1101 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x78000000, /* 0111 1000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0xa8000000, /* 1010 1000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff  /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

                    /* " ", "#", "%", "+", "?", %00-%1F, %7F-%FF */

    static uint32_t   args[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x80000829, /* 1000 0000 0000 0000  0000 1000 0010 1001 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff  /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

                    /* " ", "#", """, "%", "'", %00-%1F, %7F-%FF */

    static uint32_t   html[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x000000ad, /* 0000 0000 0000 0000  0000 0000 1010 1101 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff  /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

                    /* " ", """, "%", "'", %00-%1F, %7F-%FF */

    static uint32_t   refresh[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x00000085, /* 0000 0000 0000 0000  0000 0000 1000 0101 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff  /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

                    /* " ", "%", %00-%1F */

    static uint32_t   memcached[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x00000021, /* 0000 0000 0000 0000  0000 0000 0010 0001 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    };

                    /* mail_auth is the same as memcached */

    static uint32_t  *map[] =
        { uri, args, html, refresh, memcached, memcached };


    escape = map[type];

    if (dst == NULL) {

        /* find the number of the characters to be escaped */

        n = 0;

        while (size) {
            if (escape[*src >> 5] & (1 << (*src & 0x1f))) {
                n++;
            }
            src++;
            size--;
        }

        return (uintptr_t) n;
    }

    while (size) {
        if (escape[*src >> 5] & (1 << (*src & 0x1f))) {
            *dst++ = '%';
            *dst++ = hex[*src >> 4];
            *dst++ = hex[*src & 0xf];
            src++;

        } else {
            *dst++ = *src++;
        }
        size--;
    }

    return (uintptr_t) dst;
}


/* XXX we also decode '+' to ' ' */
void
ngx_http_lua_unescape_uri(u_char **dst, u_char **src, size_t size,
        ngx_uint_t type)
{
    u_char  *d, *s, ch, c, decoded;
    enum {
        sw_usual = 0,
        sw_quoted,
        sw_quoted_second
    } state;

    d = *dst;
    s = *src;

    state = 0;
    decoded = 0;

    while (size--) {

        ch = *s++;

        switch (state) {
        case sw_usual:
            if (ch == '?'
                && (type & (NGX_UNESCAPE_URI|NGX_UNESCAPE_REDIRECT)))
            {
                *d++ = ch;
                goto done;
            }

            if (ch == '%') {
                state = sw_quoted;
                break;
            }

            if (ch == '+') {
                *d++ = ' ';
                break;
            }

            *d++ = ch;
            break;

        case sw_quoted:

            if (ch >= '0' && ch <= '9') {
                decoded = (u_char) (ch - '0');
                state = sw_quoted_second;
                break;
            }

            c = (u_char) (ch | 0x20);
            if (c >= 'a' && c <= 'f') {
                decoded = (u_char) (c - 'a' + 10);
                state = sw_quoted_second;
                break;
            }

            /* the invalid quoted character */

            state = sw_usual;

            *d++ = ch;

            break;

        case sw_quoted_second:

            state = sw_usual;

            if (ch >= '0' && ch <= '9') {
                ch = (u_char) ((decoded << 4) + ch - '0');

                if (type & NGX_UNESCAPE_REDIRECT) {
                    if (ch > '%' && ch < 0x7f) {
                        *d++ = ch;
                        break;
                    }

                    *d++ = '%'; *d++ = *(s - 2); *d++ = *(s - 1);
                    break;
                }

                *d++ = ch;

                break;
            }

            c = (u_char) (ch | 0x20);
            if (c >= 'a' && c <= 'f') {
                ch = (u_char) ((decoded << 4) + c - 'a' + 10);

                if (type & NGX_UNESCAPE_URI) {
                    if (ch == '?') {
                        *d++ = ch;
                        goto done;
                    }

                    *d++ = ch;
                    break;
                }

                if (type & NGX_UNESCAPE_REDIRECT) {
                    if (ch == '?') {
                        *d++ = ch;
                        goto done;
                    }

                    if (ch > '%' && ch < 0x7f) {
                        *d++ = ch;
                        break;
                    }

                    *d++ = '%'; *d++ = *(s - 2); *d++ = *(s - 1);
                    break;
                }

                *d++ = ch;

                break;
            }

            /* the invalid quoted character */

            break;
        }
    }

done:

    *dst = d;
    *src = s;
}


void
ngx_http_lua_inject_req_api(ngx_log_t *log, lua_State *L)
{
    /* ngx.req table */

    lua_createtable(L, 0 /* narr */, 21 /* nrec */);    /* .req */

    ngx_http_lua_inject_req_header_api(L);

    ngx_http_lua_inject_req_uri_api(log, L);

    ngx_http_lua_inject_req_args_api(L);

    ngx_http_lua_inject_req_body_api(L);

    ngx_http_lua_inject_req_socket_api(L);

    ngx_http_lua_inject_req_method_api(L);

    lua_setfield(L, -2, "req");
}


static ngx_int_t
ngx_http_lua_handle_exec(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int cc_ref)
{
    ngx_int_t               rc;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua thread initiated internal redirect to %V",
            &ctx->exec_uri);

    ngx_http_lua_del_thread(r, L, cc_ref);
    ctx->cc_ref = LUA_NOREF;

    ngx_http_lua_request_cleanup(r);

    if (ctx->exec_uri.data[0] == '@') {
        if (ctx->exec_args.len > 0) {
            ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                    "query strings %V ignored when exec'ing "
                    "named location %V",
                    &ctx->exec_args, &ctx->exec_uri);
        }

        r->write_event_handler = ngx_http_request_empty_handler;

#if 1
        /* clear the modules contexts */
        ngx_memzero(r->ctx, sizeof(void *) * ngx_http_max_module);
#endif

        rc = ngx_http_named_location(r, &ctx->exec_uri);
        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE)
        {
            return rc;
        }

#if 0
        if (!ctx->entered_content_phase) {
            /* XXX ensure the main request ref count
             * is decreased because the current
             * request will be quit */
            r->main->count--;
            dd("XXX decrement main count: c:%d", (int) r->main->count);
        }
#endif

        return NGX_DONE;
    }

    dd("internal redirect to %.*s", (int) ctx->exec_uri.len,
            ctx->exec_uri.data);

    /* resume the write event handler */
    r->write_event_handler = ngx_http_request_empty_handler;

    rc = ngx_http_internal_redirect(r, &ctx->exec_uri,
            &ctx->exec_args);

    dd("internal redirect returned %d when in content phase? "
            "%d", (int) rc, ctx->entered_content_phase);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return rc;
    }

    dd("XXYY HERE %d\n", (int) r->main->count);

#if 0
    if (!ctx->entered_content_phase) {
        /* XXX ensure the main request ref count
         * is decreased because the current
         * request will be quit */
        dd("XXX decrement main count");
        r->main->count--;
    }
#endif

    return NGX_DONE;
}


static ngx_int_t
ngx_http_lua_handle_exit(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int cc_ref)
{
    ngx_int_t           rc;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua thread aborting request with status %d",
            ctx->exit_code);

#if 1
    if (!ctx->headers_sent && ctx->exit_code >= NGX_HTTP_OK) {
        r->headers_out.status = ctx->exit_code;
    }
#endif

    ngx_http_lua_del_thread(r, L, cc_ref);
    ctx->cc_ref = LUA_NOREF;

    ngx_http_lua_request_cleanup(r);

    if ((ctx->exit_code == NGX_OK
         && ctx->entered_content_phase)
        || (ctx->exit_code >= NGX_HTTP_OK
            && ctx->exit_code < NGX_HTTP_SPECIAL_RESPONSE))
    {
        rc = ngx_http_lua_send_chain_link(r, ctx,
                NULL /* indicate last_buf */);

        if (rc == NGX_ERROR ||
                rc >= NGX_HTTP_SPECIAL_RESPONSE)
        {
            return rc;
        }
    }

    return ctx->exit_code;
}


void
ngx_http_lua_process_args_option(ngx_http_request_t *r, lua_State *L,
        int table, ngx_str_t *args)
{
    u_char              *key;
    size_t               key_len;
    u_char              *value;
    size_t               value_len;
    size_t               len = 0;
    size_t               key_escape = 0;
    uintptr_t            total_escape = 0;
    int                  n;
    int                  i;
    u_char              *p;

    if (table < 0) {
        table = lua_gettop(L) + table + 1;
    }

    n = 0;
    lua_pushnil(L);
    while (lua_next(L, table) != 0) {
        if (lua_type(L, -2) != LUA_TSTRING) {
            luaL_error(L, "attempt to use a non-string key in the "
                    "\"args\" option table");
            return;
        }

        key = (u_char *) lua_tolstring(L, -2, &key_len);

        key_escape = 2 * ngx_http_lua_escape_uri(NULL, key, key_len,
                                                 NGX_ESCAPE_URI);
        total_escape += key_escape;

        switch (lua_type(L, -1)) {
        case LUA_TNUMBER:
        case LUA_TSTRING:
            value = (u_char *) lua_tolstring(L, -1, &value_len);

            total_escape += 2 * ngx_http_lua_escape_uri(NULL, value, value_len,
                    NGX_ESCAPE_URI);

            len += key_len + value_len + (sizeof("=") - 1);
            n++;

            break;

        case LUA_TBOOLEAN:
            if (lua_toboolean(L, -1)) {
                len += key_len;
                n++;
            }

            break;

        case LUA_TTABLE:

            i = 0;
            lua_pushnil(L);
            while (lua_next(L, -2) != 0) {
                value = (u_char *) lua_tolstring(L, -1, &value_len);

                if (value == NULL) {
                    luaL_error(L, "attempt to use %s as query arg value",
                            luaL_typename(L, -1));
                    return;
                }

                total_escape += 2 * ngx_http_lua_escape_uri(NULL, value,
                                                            value_len,
                                                            NGX_ESCAPE_URI);

                len += key_len + value_len + (sizeof("=") - 1);

                if (i++ > 0) {
                    total_escape += key_escape;
                }

                n++;

                lua_pop(L, 1);
            }

            break;

        default:
            luaL_error(L, "attempt to use %s as query arg value",
                    luaL_typename(L, -1));
            return;
        }

        lua_pop(L, 1);
    }

    len += (size_t) total_escape;

    if (n > 1) {
        len += (n - 1) * (sizeof("&") - 1);
    }

    dd("len 1: %d", (int) len);

    p = ngx_palloc(r->pool, len);
    if (p == NULL) {
        luaL_error(L, "out of memory");
        return;
    }

    args->data = p;
    args->len = len;

    i = 0;
    lua_pushnil(L);
    while (lua_next(L, table) != 0) {
        key = (u_char *) lua_tolstring(L, -2, &key_len);

        switch (lua_type(L, -1)) {
        case LUA_TNUMBER:
        case LUA_TSTRING:

            if (total_escape) {
                p = (u_char *) ngx_http_lua_escape_uri(p, key, key_len,
                        NGX_ESCAPE_URI);

            } else {
                dd("shortcut: no escape required");

                p = ngx_copy(p, key, key_len);
            }

            *p++ = '=';

            value = (u_char *) lua_tolstring(L, -1, &value_len);

            if (total_escape) {
                p = (u_char *) ngx_http_lua_escape_uri(p, value, value_len,
                        NGX_ESCAPE_URI);

            } else {
                p = ngx_copy(p, value, value_len);
            }

            if (i != n - 1) {
                /* not the last pair */
                *p++ = '&';
            }

            i++;

            break;

        case LUA_TBOOLEAN:
            if (lua_toboolean(L, -1)) {
                if (total_escape) {
                    p = (u_char *) ngx_http_lua_escape_uri(p, key, key_len,
                            NGX_ESCAPE_URI);

                } else {
                    dd("shortcut: no escape required");

                    p = ngx_copy(p, key, key_len);
                }

                if (i != n - 1) {
                    /* not the last pair */
                    *p++ = '&';
                }

                i++;
            }

            break;

        case LUA_TTABLE:

            lua_pushnil(L);
            while (lua_next(L, -2) != 0) {

                if (total_escape) {
                    p = (u_char *) ngx_http_lua_escape_uri(p, key, key_len,
                                                           NGX_ESCAPE_URI);

                } else {
                    dd("shortcut: no escape required");

                    p = ngx_copy(p, key, key_len);
                }

                *p++ = '=';

                value = (u_char *) lua_tolstring(L, -1, &value_len);

                if (total_escape) {
                    p = (u_char *) ngx_http_lua_escape_uri(p, value, value_len,
                                                           NGX_ESCAPE_URI);

                } else {
                    p = ngx_copy(p, value, value_len);
                }

                if (i != n - 1) {
                    /* not the last pair */
                    *p++ = '&';
                }

                i++;

                lua_pop(L, 1);
            }

            break;

        default:
            luaL_error(L, "should not reach here");
            return;
        }

        lua_pop(L, 1);
    }

    if (p - args->data != (ssize_t) len) {
        luaL_error(L, "buffer error: %d != %d",
                (int) (p - args->data), (int) len);
        return;
    }
}


static ngx_int_t
ngx_http_lua_handle_rewrite_jump(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int cc_ref)
{
    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua thread aborting request with URI rewrite jump: \"%V?%V\"",
            &r->uri, &r->args);

    ngx_http_lua_del_thread(r, L, cc_ref);
    ctx->cc_ref = LUA_NOREF;

    ngx_http_lua_request_cleanup(r);

    return NGX_OK;
}


/* XXX ngx_open_and_stat_file is static in the core. sigh. */
ngx_int_t
ngx_http_lua_open_and_stat_file(u_char *name, ngx_open_file_info_t *of,
        ngx_log_t *log)
{
    ngx_fd_t         fd;
    ngx_file_info_t  fi;

    if (of->fd != NGX_INVALID_FILE) {

        if (ngx_file_info(name, &fi) == NGX_FILE_ERROR) {
            of->failed = ngx_file_info_n;
            goto failed;
        }

        if (of->uniq == ngx_file_uniq(&fi)) {
            goto done;
        }

    } else if (of->test_dir) {

        if (ngx_file_info(name, &fi) == NGX_FILE_ERROR) {
            of->failed = ngx_file_info_n;
            goto failed;
        }

        if (ngx_is_dir(&fi)) {
            goto done;
        }
    }

    if (!of->log) {

        /*
         * Use non-blocking open() not to hang on FIFO files, etc.
         * This flag has no effect on a regular files.
         */

        fd = ngx_open_file(name, NGX_FILE_RDONLY|NGX_FILE_NONBLOCK,
                           NGX_FILE_OPEN, 0);

    } else {
        fd = ngx_open_file(name, NGX_FILE_APPEND, NGX_FILE_CREATE_OR_OPEN,
                           NGX_FILE_DEFAULT_ACCESS);
    }

    if (fd == NGX_INVALID_FILE) {
        of->failed = ngx_open_file_n;
        goto failed;
    }

    if (ngx_fd_info(fd, &fi) == NGX_FILE_ERROR) {
        ngx_log_error(NGX_LOG_CRIT, log, ngx_errno,
                      ngx_fd_info_n " \"%s\" failed", name);

        if (ngx_close_file(fd) == NGX_FILE_ERROR) {
            ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                          ngx_close_file_n " \"%s\" failed", name);
        }

        of->fd = NGX_INVALID_FILE;

        return NGX_ERROR;
    }

    if (ngx_is_dir(&fi)) {
        if (ngx_close_file(fd) == NGX_FILE_ERROR) {
            ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                          ngx_close_file_n " \"%s\" failed", name);
        }

        of->fd = NGX_INVALID_FILE;

    } else {
        of->fd = fd;

        if (of->directio <= ngx_file_size(&fi)) {
            if (ngx_directio_on(fd) == NGX_FILE_ERROR) {
                ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                              ngx_directio_on_n " \"%s\" failed", name);

            } else {
                of->is_directio = 1;
            }
        }
    }

done:

    of->uniq = ngx_file_uniq(&fi);
    of->mtime = ngx_file_mtime(&fi);
    of->size = ngx_file_size(&fi);
#if defined(nginx_version) && nginx_version >= 1000001
    of->fs_size = ngx_file_fs_size(&fi);
#endif
    of->is_dir = ngx_is_dir(&fi);
    of->is_file = ngx_is_file(&fi);
    of->is_link = ngx_is_link(&fi);
    of->is_exec = ngx_is_exec(&fi);

    return NGX_OK;

failed:

    of->fd = NGX_INVALID_FILE;
    of->err = ngx_errno;

    return NGX_ERROR;
}


void
ngx_http_lua_inject_internal_utils(ngx_log_t *log, lua_State *L)
{
    ngx_int_t         rc;

    lua_pushcfunction(L, ngx_http_lua_ngx_check_aborted);
    lua_setfield(L, -2, "_check_aborted"); /* deprecated */

    /* override the default pcall */

    lua_getglobal(L, "pcall");
    lua_setfield(L, -2, "_pcall");

    {
        const char    buf[] = "local ret = {ngx._pcall(...)} "
                              "ngx._check_aborted() return unpack(ret)";

        rc = luaL_loadbuffer(L, buf, sizeof(buf) - 1, "ngx_lua pcall");
    }

    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_CRIT, log, 0,
                      "failed to load Lua code for ngx_lua pcall(): %i",
                      rc);

    } else {
        lua_setglobal(L, "pcall");
    }

    /* override the default xpcall */

    lua_getglobal(L, "xpcall");
    lua_setfield(L, -2, "_xpcall");

    {
        const char    buf[] = "local ret = {ngx._xpcall(...)} "
                              "ngx._check_aborted() return unpack(ret)";

        rc = luaL_loadbuffer(L, buf, sizeof(buf) - 1, "ngx_lua xpcall");
    }

    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_CRIT, log, 0,
                      "failed to load Lua code for ngx_lua xpcall(): %i",
                      rc);

    } else {
        lua_setglobal(L, "xpcall");
    }
}


static int
ngx_http_lua_ngx_check_aborted(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return 0;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return 0;
    }

    NGX_HTTP_LUA_CHECK_ABORTED(L, ctx);

    return 0;
}


ngx_chain_t *
ngx_http_lua_chains_get_free_buf(ngx_log_t *log, ngx_pool_t *p,
    ngx_chain_t **free, size_t len, ngx_buf_tag_t tag)
{
    ngx_chain_t  *cl;
    ngx_buf_t    *b;

    if (*free) {
        cl = *free;
        *free = cl->next;
        cl->next = NULL;

        b = cl->buf;
        if ((size_t) (b->end - b->start) >= len) {
            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, log, 0,
                    "lua reuse free buf memory %O >= %uz, cl:%p, p:%p",
                    (off_t) (b->end - b->start), len, cl, b->start);

            b->pos = b->start;
            b->last = b->start;
            b->tag = tag;
            return cl;
        }

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, log, 0,
                       "lua reuse free buf chain, but reallocate memory "
                       "because %uz >= %O, cl:%p, p:%p", len,
                       (off_t) (b->end - b->start), cl, b->start);

        if (ngx_buf_in_memory(b) && b->start) {
            ngx_pfree(p, b->start);
        }

        if (len) {
            b->start = ngx_palloc(p, len);
            if (b->start == NULL) {
                return NULL;
            }

            b->end = b->start + len;

        } else {
            b->last = NULL;
            b->end = NULL;
        }

        dd("buf start: %p", cl->buf->start);

        b->pos = b->start;
        b->last = b->start;
        b->tag = tag;

        return cl;
    }

    cl = ngx_alloc_chain_link(p);
    if (cl == NULL) {
        return NULL;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "lua allocate new chainlink and new buf of size %uz, cl:%p",
                   len, cl);

    cl->buf = ngx_create_temp_buf(p, len);
    if (cl->buf == NULL) {
        return NULL;
    }

    dd("buf start: %p", cl->buf->start);

    cl->buf->tag = tag;
    cl->next = NULL;

    return cl;
}


static int
ngx_http_lua_thread_traceback(lua_State *L, lua_State *cc)
{
    int         base;
    int         level = 0;
    int         firstpart = 1;  /* still before eventual `...' */
    lua_Debug   ar;

    base = lua_gettop(L);

    lua_pushliteral(L, "stack traceback:");

    while (lua_getstack(cc, level++, &ar)) {

        if (level > LEVELS1 && firstpart) {
            /* no more than `LEVELS2' more levels? */
            if (!lua_getstack(cc, level + LEVELS2, &ar)) {
                level--;  /* keep going */

            } else {
                lua_pushliteral(L, "\n\t...");  /* too many levels */
                /* This only works with LuaJIT 2.x. Avoids O(n^2) behaviour. */
                lua_getstack(cc, -10, &ar);
                level = ar.i_ci - LEVELS2;
            }

            firstpart = 0;
            continue;
        }

        lua_pushliteral(L, "\n\t");
        lua_getinfo(cc, "Snl", &ar);
        lua_pushfstring(L, "%s:", ar.short_src);

        if (ar.currentline > 0) {
            lua_pushfstring(L, "%d:", ar.currentline);
        }

        if (*ar.namewhat != '\0') {  /* is there a name? */
            lua_pushfstring(L, " in function " LUA_QS, ar.name);

        } else {
            if (*ar.what == 'm') {  /* main? */
                lua_pushfstring(L, " in main chunk");

            } else if (*ar.what == 'C' || *ar.what == 't') {
                lua_pushliteral(L, " ?");  /* C function or tail call */

            } else {
                lua_pushfstring(L, " in function <%s:%d>",
                                ar.short_src, ar.linedefined);
            }
        }
    }

    lua_concat(L, lua_gettop(L) - base);
    return 1;
}


int
ngx_http_lua_traceback(lua_State *L)
{
    if (!lua_isstring(L, 1)) { /* 'message' not a string? */
        return 1;  /* keep it intact */
    }

    lua_getfield(L, LUA_GLOBALSINDEX, "debug");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return 1;
    }

    lua_getfield(L, -1, "traceback");
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 2);
        return 1;
    }

    lua_pushvalue(L, 1);  /* pass error message */
    lua_pushinteger(L, 2);  /* skip this function and traceback */
    lua_call(L, 2, 1);  /* call debug.traceback */
    return 1;
}


static void
ngx_http_lua_inject_arg_api(lua_State *L)
{
    lua_pushliteral(L, "arg");
    lua_newtable(L);    /*  .arg table aka {} */

    lua_createtable(L, 0 /* narr */, 2 /* nrec */);    /*  the metatable */

    lua_pushcfunction(L, ngx_http_lua_param_get);
    lua_setfield(L, -2, "__index");

    lua_pushcfunction(L, ngx_http_lua_param_set);
    lua_setfield(L, -2, "__newindex");

    lua_setmetatable(L, -2);    /*  tie the metatable to param table */

    dd("top: %d, type -1: %s", lua_gettop(L), luaL_typename(L, -1));

    lua_rawset(L, -3);    /*  set ngx.arg table */
}


static int
ngx_http_lua_param_get(lua_State *L)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_request_t          *r;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return 0;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "ctx not found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_SET
                               | NGX_HTTP_LUA_CONTEXT_BODY_FILTER);

    if (ctx->context & (NGX_HTTP_LUA_CONTEXT_SET)) {
        return ngx_http_lua_setby_param_get(L);
    }

    /* ctx->context & (NGX_HTTP_LUA_CONTEXT_BODY_FILTER) */

    return ngx_http_lua_body_filter_param_get(L);
}


static int
ngx_http_lua_param_set(lua_State *L)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_request_t          *r;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return 0;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "ctx not found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_BODY_FILTER);

    return ngx_http_lua_body_filter_param_set(L, r, ctx);
}

