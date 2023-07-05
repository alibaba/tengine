/*
 * Copyright (C) Yichun Zhang (agentzh)
 * Copyright (C) Jinhua Luo (kingluo)
 * I hereby assign copyright in this code to the lua-nginx-module project,
 * to be licensed under the same terms as the rest of the code.
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_worker_thread.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_string.h"
#include "ngx_http_lua_config.h"
#include "ngx_http_lua_shdict.h"

#ifndef STRINGIFY
#define TOSTRING(x)  #x
#define STRINGIFY(x) TOSTRING(x)
#endif

#if (NGX_THREADS)


#include <ngx_thread.h>
#include <ngx_thread_pool.h>

#define LUA_COPY_MAX_DEPTH 100

typedef struct ngx_http_lua_task_ctx_s {
    lua_State                        *vm;
    struct ngx_http_lua_task_ctx_s   *next;
} ngx_http_lua_task_ctx_t;


typedef struct {
    ngx_http_lua_task_ctx_t *ctx;
    ngx_http_lua_co_ctx_t   *wait_co_ctx;
    int                      n_args;
    int                      rc;
    int                      is_abort:1;
} ngx_http_lua_worker_thread_ctx_t;


static  ngx_http_lua_task_ctx_t   dummy_ctx;
static  ngx_http_lua_task_ctx_t  *ctxpool = &dummy_ctx;
static  ngx_uint_t                worker_thread_vm_count;


void
ngx_http_lua_thread_exit_process(void)
{
    ngx_http_lua_task_ctx_t  *ctx;

    while (ctxpool->next != NULL) {
        ctx = ctxpool->next;
        ctxpool->next = ctx->next;
        lua_close(ctx->vm);
        ngx_free(ctx);
    }
}


/*
 * Re-implement ngx_thread_task_alloc to avoid alloc from request pool
 * since the request may exit before worker thread finish.
 * And we may implement a memory pool for this allocation in the future
 * to avoid memory fragmentation.
 */
static ngx_thread_task_t *
ngx_http_lua_thread_task_alloc(size_t size)
{
    ngx_thread_task_t  *task;

    task = ngx_calloc(sizeof(ngx_thread_task_t) + size, ngx_cycle->log);
    if (task == NULL) {
        return NULL;
    }

    task->ctx = task + 1;

    return task;
}


static void
ngx_http_lua_thread_task_free(void *ctx)
{
    ngx_thread_task_t *task = ctx;
    ngx_free(task - 1);
}


static ngx_http_lua_task_ctx_t *
ngx_http_lua_get_task_ctx(lua_State *L, ngx_http_request_t *r)
{
    ngx_http_lua_task_ctx_t *ctx = NULL;

    size_t           path_len;
    const char      *path;
    size_t           cpath_len;
    const char      *cpath;
    lua_State       *vm;

    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    if (ctxpool->next == NULL) {
        if (worker_thread_vm_count >= lmcf->worker_thread_vm_pool_size) {
            return NULL;
        }

        ctx = ngx_calloc(sizeof(ngx_http_lua_task_ctx_t), ngx_cycle->log);
        if (ctx == NULL) {
            return NULL;
        }

        vm = luaL_newstate();

        if (vm == NULL) {
            ngx_free(ctx);
            return NULL;
        }

        worker_thread_vm_count++;

        ctx->vm = vm;

        luaL_openlibs(vm);

        /* copy package.path and package.cpath */
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "path");
        path = lua_tolstring(L, -1, &path_len);
        lua_getfield(L, -2, "cpath");
        cpath = lua_tolstring(L, -1, &cpath_len);

        lua_getglobal(vm, "package");
        lua_pushlstring(vm, path, path_len);
        lua_setfield(vm, -2, "path");
        lua_pushlstring(vm, cpath, cpath_len);
        lua_setfield(vm, -2, "cpath");
        lua_pop(vm, 1);

        /* pop path, cpath and "package" table from L */
        lua_pop(L, 3);

        /* inject API from C */
        lua_newtable(vm);    /* ngx.* */
        ngx_http_lua_inject_string_api(vm);
        ngx_http_lua_inject_config_api(vm);
        ngx_http_lua_inject_shdict_api(lmcf, vm);
        lua_setglobal(vm, "ngx");

        /* inject API via ffi */
        lua_getglobal(vm, "require");
        lua_pushstring(vm, "resty.core.regex");
        if (lua_pcall(vm, 1, 0, 0) != 0) {
            lua_close(vm);
            ngx_free(ctx);
            return NULL;
        }

        lua_getglobal(vm, "require");
        lua_pushstring(vm, "resty.core.hash");
        if (lua_pcall(vm, 1, 0, 0) != 0) {
            lua_close(vm);
            ngx_free(ctx);
            return NULL;
        }

        lua_getglobal(vm, "require");
        lua_pushstring(vm, "resty.core.base64");
        if (lua_pcall(vm, 1, 0, 0) != 0) {
            lua_close(vm);
            ngx_free(ctx);
            return NULL;
        }

        lua_getglobal(vm, "require");
        lua_pushstring(vm, "resty.core.shdict");
        if (lua_pcall(vm, 1, 0, 0) != 0) {
            lua_close(vm);
            ngx_free(ctx);
            return NULL;
        }

    } else {
        ctx = ctxpool->next;
        ctxpool->next = ctx->next;
        ctx->next = NULL;
    }

    return ctx;
}


static void
ngx_http_lua_free_task_ctx(ngx_http_lua_task_ctx_t *ctx)
{
    ctx->next = ctxpool->next;
    ctxpool->next = ctx;

    /* clean Lua stack */
    lua_settop(ctx->vm, 0);
}


static int
ngx_http_lua_xcopy(lua_State *from, lua_State *to, int idx,
    const int allow_nil, const int depth, const char **err)
{
    size_t           len = 0;
    const char      *str;
    int              typ;
    int              top_from, top_to;

    typ = lua_type(from, idx);
    switch (typ) {
    case LUA_TBOOLEAN:
        lua_pushboolean(to, lua_toboolean(from, idx));
        return LUA_TBOOLEAN;

    case LUA_TLIGHTUSERDATA:
        lua_pushlightuserdata(to, lua_touserdata(from, idx));
        return LUA_TLIGHTUSERDATA;

    case LUA_TNUMBER:
        lua_pushnumber(to, lua_tonumber(from, idx));
        return LUA_TNUMBER;

    case LUA_TSTRING:
        str = lua_tolstring(from, idx, &len);
        lua_pushlstring(to, str, len);
        return LUA_TSTRING;

    case LUA_TTABLE:
        if (depth >= LUA_COPY_MAX_DEPTH) {
            *err = "suspicious circular references, "
                   "table depth exceed max depth: "
                   STRINGIFY(LUA_COPY_MAX_DEPTH);
            return LUA_TNONE;
        }

        top_from = lua_gettop(from);
        top_to = lua_gettop(to);

        lua_newtable(to);

        /* to positive number */
        if (idx < 0) {
            idx = lua_gettop(from) + idx + 1;
        }

        lua_pushnil(from);

        while (lua_next(from, idx) != 0) {
            if (ngx_http_lua_xcopy(from, to, -2, 0, depth + 1, err) != LUA_TNONE
                && ngx_http_lua_xcopy(from, to, -1, 0,
                                      depth + 1, err) != LUA_TNONE)
            {
                lua_rawset(to, -3);

            } else {
                lua_settop(from, top_from);
                lua_settop(to, top_to);
                return LUA_TNONE;
            }

            lua_pop(from, 1);
        }

        return LUA_TTABLE;

    case LUA_TNIL:
        if (allow_nil) {
            lua_pushnil(to);
            return LUA_TNIL;
        }

        *err = "unsupported Lua type: LUA_TNIL";
        return LUA_TNONE;

    case LUA_TFUNCTION:
        *err = "unsupported Lua type: LUA_TFUNCTION";
        return LUA_TNONE;

    case LUA_TUSERDATA:
        *err = "unsupported Lua type: LUA_TUSERDATA";
        return LUA_TNONE;

    case LUA_TTHREAD:
        *err = "unsupported Lua type: LUA_TTHREAD";
        return LUA_TNONE;

    default:
        *err = "unsupported Lua type";
        return LUA_TNONE;
    }
}


/* executed in a separate thread */
static void
ngx_http_lua_worker_thread_handler(void *data, ngx_log_t *log)
{
    ngx_http_lua_worker_thread_ctx_t     *ctx = data;
    lua_State                            *vm = ctx->ctx->vm;

    /* function + args in the lua stack */
    ngx_http_lua_assert(lua_gettop(vm) == ctx->n_args + 1);

    ctx->rc = lua_pcall(vm, ctx->n_args, LUA_MULTRET, 0);
}


static ngx_int_t
ngx_http_lua_worker_thread_resume(ngx_http_request_t *r)
{
    lua_State                   *vm;
    ngx_connection_t            *c;
    ngx_int_t                    rc;
    ngx_uint_t                   nreqs;
    ngx_http_lua_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(vm, r, ctx,
                                 ctx->cur_co_ctx->nresults_from_worker_thread);

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


/* executed in nginx event loop */
static void
ngx_http_lua_worker_thread_event_handler(ngx_event_t *ev)
{
    ngx_http_lua_worker_thread_ctx_t *worker_thread_ctx;
    lua_State                        *L;
    ngx_http_request_t               *r;
    ngx_connection_t                 *c;
    int                               nresults;
    size_t                            len;
    const char                       *str;
    int                               i;
    ngx_http_lua_ctx_t               *ctx;
    lua_State                        *vm;
    int                               saved_top;
    const char                       *err;

    worker_thread_ctx = ev->data;

    if (worker_thread_ctx->is_abort) {
        goto failed;
    }

    L = worker_thread_ctx->wait_co_ctx->co;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        goto failed;
    }

    c = r->connection;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        goto failed;
    }

    vm = worker_thread_ctx->ctx->vm;

    if (worker_thread_ctx->rc != 0) {
        str = lua_tolstring(vm, 1, &len);
        lua_pushboolean(L, 0);
        lua_pushlstring(L, str, len);
        nresults = 2;

    } else {
        /* copying return values */
        saved_top = lua_gettop(L);
        lua_pushboolean(L, 1);
        nresults = lua_gettop(vm) + 1;
        for (i = 1; i < nresults; i++) {
            err = NULL;
            if (ngx_http_lua_xcopy(vm, L, i, 1, 1, &err) == LUA_TNONE) {
                lua_settop(L, saved_top);
                lua_pushboolean(L, 0);
                lua_pushfstring(L, "%s in the return value",
                                err != NULL ? err : "unsupoorted Lua type");
                nresults = 2;
                break;
            }
        }
    }

    ctx->cur_co_ctx = worker_thread_ctx->wait_co_ctx;
    ctx->cur_co_ctx->nresults_from_worker_thread = nresults;
    ctx->cur_co_ctx->cleanup = NULL;

    ngx_http_lua_free_task_ctx(worker_thread_ctx->ctx);
    ngx_http_lua_thread_task_free(worker_thread_ctx);

    /* resume the caller coroutine */

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_worker_thread_resume(r);

    } else {
        ctx->resume_handler = ngx_http_lua_worker_thread_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);

    return;

failed:

    ngx_http_lua_free_task_ctx(worker_thread_ctx->ctx);
    ngx_http_lua_thread_task_free(worker_thread_ctx);
    return;
}


static void
ngx_http_lua_worker_thread_cleanup(void *data)
{
    ngx_http_lua_co_ctx_t *ctx                          = data;
    ngx_http_lua_worker_thread_ctx_t *worker_thread_ctx = ctx->data;
    worker_thread_ctx->is_abort                         = 1;
}


/* It's not easy to use pure ffi here, using the Lua C API for now. */
static int
ngx_http_lua_run_worker_thread(lua_State *L)
{
    ngx_http_request_t                 *r;
    ngx_http_lua_ctx_t                 *ctx;
    int                                 n_args;
    ngx_str_t                           thread_pool_name;
    ngx_thread_pool_t                  *thread_pool;
    ngx_http_lua_task_ctx_t            *tctx;
    lua_State                          *vm;
    size_t                              len;
    const char                         *mod_name;
    const char                         *func_name;
    int                                 rc;
    const char                         *err;
    int                                 i;
    ngx_thread_task_t                  *task;
    ngx_http_lua_worker_thread_ctx_t   *worker_thread_ctx;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_YIELDABLE);

    n_args = lua_gettop(L);

    if (n_args < 3) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "expecting at least 3 arguments");
        return 2;
    }

    thread_pool_name.data = (u_char *)
                            lua_tolstring(L, 1, &thread_pool_name.len);

    if (thread_pool_name.data == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "threadpool should be a string");
        return 2;
    }

    thread_pool = ngx_thread_pool_get((ngx_cycle_t *) ngx_cycle,
                                      &thread_pool_name);

    if (thread_pool == NULL) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "thread pool %s not found", thread_pool_name.data);
        return 2;
    }

    mod_name = lua_tolstring(L, 2, &len);
    if (mod_name == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "module name should be a string");
        return 2;
    }

    func_name = lua_tolstring(L, 3, NULL);
    if (func_name == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "function name should be a string");
        return 2;
    }

    /* get vm */
    tctx = ngx_http_lua_get_task_ctx(L, r);
    if (tctx == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "no available Lua vm");
        return 2;
    }

    vm = tctx->vm;

    ngx_http_lua_assert(lua_gettop(vm) == 0);

    /* push function from module require */
    lua_getfield(vm, LUA_GLOBALSINDEX, "require");
    lua_pushlstring(vm, mod_name, len);
    rc = lua_pcall(vm, 1, 1, 0);

    if (rc != 0) {
        err = lua_tolstring(vm, 1, &len);
        lua_pushboolean(L, 0);
        lua_pushlstring(L, err, len);
        ngx_http_lua_free_task_ctx(tctx);
        return 2;
    }

    if (!lua_istable(vm, -1)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "invalid lua module");
        ngx_http_lua_free_task_ctx(tctx);
        return 2;
    }

    lua_getfield(vm, -1, func_name);
    if (!lua_isfunction(vm, -1)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "invalid function");
        ngx_http_lua_free_task_ctx(tctx);
        return 2;
    }

    /* remove the table returned by require */
    lua_remove(vm, 1);

    /* copying passed arguments */
    for (i = 4; i <= n_args; i++) {
        err = NULL;
        if (ngx_http_lua_xcopy(L, vm, i, 1, 1, &err) == LUA_TNONE) {
            lua_pushboolean(L, 0);
            lua_pushfstring(L, "%s in the argument",
                            err != NULL ? err : "unsupoorted Lua type");
            ngx_http_lua_free_task_ctx(tctx);
            return 2;
        }
    }

    /* post task */
    task = ngx_http_lua_thread_task_alloc(
                sizeof(ngx_http_lua_worker_thread_ctx_t));

    if (task == NULL) {
        ngx_http_lua_free_task_ctx(tctx);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "no memory");
        return 2;
    }

    worker_thread_ctx = task->ctx;

    worker_thread_ctx->ctx = tctx;
    worker_thread_ctx->wait_co_ctx = ctx->cur_co_ctx;

    ctx->cur_co_ctx->cleanup = ngx_http_lua_worker_thread_cleanup;
    ctx->cur_co_ctx->data = worker_thread_ctx;

    worker_thread_ctx->n_args = n_args - 3;
    worker_thread_ctx->rc = 0;
    worker_thread_ctx->is_abort = 0;

    task->handler = ngx_http_lua_worker_thread_handler;
    task->event.handler = ngx_http_lua_worker_thread_event_handler;
    task->event.data = worker_thread_ctx;

    if (ngx_thread_task_post(thread_pool, task) != NGX_OK) {
        ngx_http_lua_free_task_ctx(tctx);
        ngx_http_lua_thread_task_free(task);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "ngx_thread_task_post failed");
        return 2;
    }

    return lua_yield(L, 0);
}


void
ngx_http_lua_inject_worker_thread_api(ngx_log_t *log, lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_run_worker_thread);
    lua_setfield(L, -2, "run_worker_thread");
}

#endif

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
