
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_exitworkerby.h"
#include "ngx_http_lua_util.h"

#if (NGX_THREADS)
#include "ngx_http_lua_worker_thread.h"
#endif


void
ngx_http_lua_exit_worker(ngx_cycle_t *cycle)
{
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_connection_t            *c = NULL;
    ngx_http_request_t          *r = NULL;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_conf_ctx_t         *conf_ctx;

#if (NGX_THREADS)
    ngx_http_lua_thread_exit_process();
#endif

    lmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_lua_module);
    if (lmcf == NULL
        || lmcf->exit_worker_handler == NULL
        || lmcf->lua == NULL
#if !(NGX_WIN32)
        || (ngx_process == NGX_PROCESS_HELPER
#   ifdef HAVE_PRIVILEGED_PROCESS_PATCH
            && !ngx_is_privileged_agent
#   endif
           )
#endif  /* NGX_WIN32 */
       )
    {
        return;
    }

    conf_ctx = ((ngx_http_conf_ctx_t *) cycle->conf_ctx[ngx_http_module.index]);

    c = ngx_http_lua_create_fake_connection(NULL);
    if (c == NULL) {
        goto failed;
    }

    c->log = ngx_cycle->log;

    r = ngx_http_lua_create_fake_request(c);
    if (r == NULL) {
        goto failed;
    }

    r->main_conf = conf_ctx->main_conf;
    r->srv_conf = conf_ctx->srv_conf;
    r->loc_conf = conf_ctx->loc_conf;

    ctx = ngx_http_lua_create_ctx(r);
    if (ctx == NULL) {
        goto failed;
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_EXIT_WORKER;
    ctx->cur_co_ctx = NULL;

    ngx_http_lua_set_req(lmcf->lua, r);

    (void) lmcf->exit_worker_handler(cycle->log, lmcf, lmcf->lua);

    ngx_destroy_pool(c->pool);
    return;

failed:

    if (c) {
        ngx_http_lua_close_fake_connection(c);
    }

    return;
}


ngx_int_t
ngx_http_lua_exit_worker_by_inline(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L)
{
    int         status;
    const char *chunkname;

    if (lmcf->exit_worker_chunkname == NULL) {
        chunkname = "=exit_worker_by_lua";

    } else {
        chunkname = (const char *) lmcf->exit_worker_chunkname;
    }

    status = luaL_loadbuffer(L, (char *) lmcf->exit_worker_src.data,
                             lmcf->exit_worker_src.len, chunkname)
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "exit_worker_by_lua");
}


ngx_int_t
ngx_http_lua_exit_worker_by_file(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
    lua_State *L)
{
    int         status;

    status = luaL_loadfile(L, (char *) lmcf->exit_worker_src.data)
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "exit_worker_by_lua_file");
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
