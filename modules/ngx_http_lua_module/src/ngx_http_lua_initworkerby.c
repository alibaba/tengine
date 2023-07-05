
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_pipe.h"


static u_char *ngx_http_lua_log_init_worker_error(ngx_log_t *log,
    u_char *buf, size_t len);


ngx_int_t
ngx_http_lua_init_worker(ngx_cycle_t *cycle)
{
    char                        *rv;
    void                        *cur, *prev;
    ngx_uint_t                   i;
    ngx_conf_t                   conf;
    ngx_conf_file_t              cf_file;
    ngx_cycle_t                 *fake_cycle;
    ngx_module_t               **modules;
    ngx_open_file_t             *file, *ofile;
    ngx_list_part_t             *part;
    ngx_connection_t            *c = NULL;
    ngx_http_module_t           *module;
    ngx_http_request_t          *r = NULL;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_conf_ctx_t         *conf_ctx, http_ctx;
    ngx_http_lua_loc_conf_t     *top_llcf;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_core_loc_conf_t    *clcf, *top_clcf;

    lmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_lua_module);

    if (lmcf == NULL || lmcf->lua == NULL) {
        return NGX_OK;
    }

    /* lmcf != NULL && lmcf->lua != NULL */

#if !(NGX_WIN32)
    if (ngx_process == NGX_PROCESS_HELPER
#   ifdef HAVE_PRIVILEGED_PROCESS_PATCH
        && !ngx_is_privileged_agent
#   endif
       )
    {
        /* disable init_worker_by_lua* and destroy lua VM in cache processes */

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua close the global Lua VM %p in the "
                       "cache helper process %P", lmcf->lua, ngx_pid);

        lmcf->vm_cleanup->handler(lmcf->vm_cleanup->data);
        lmcf->vm_cleanup->handler = NULL;

        return NGX_OK;
    }

#   ifdef HAVE_NGX_LUA_PIPE
    if (ngx_http_lua_pipe_add_signal_handler(cycle) != NGX_OK) {
        return NGX_ERROR;
    }
#   endif

#endif  /* NGX_WIN32 */

#if (NGX_HTTP_LUA_HAVE_SA_RESTART)
    if (lmcf->set_sa_restart) {
        ngx_http_lua_set_sa_restart(ngx_cycle->log);
    }
#endif

    if (lmcf->init_worker_handler == NULL) {
        return NGX_OK;
    }

    conf_ctx = (ngx_http_conf_ctx_t *) cycle->conf_ctx[ngx_http_module.index];
    http_ctx.main_conf = conf_ctx->main_conf;

    top_clcf = conf_ctx->loc_conf[ngx_http_core_module.ctx_index];
    top_llcf = conf_ctx->loc_conf[ngx_http_lua_module.ctx_index];

    ngx_memzero(&conf, sizeof(ngx_conf_t));

    conf.temp_pool = ngx_create_pool(NGX_CYCLE_POOL_SIZE, cycle->log);
    if (conf.temp_pool == NULL) {
        return NGX_ERROR;
    }

    conf.temp_pool->log = cycle->log;

    /* we fake a temporary ngx_cycle_t here because some
     * modules' merge conf handler may produce side effects in
     * cf->cycle (like ngx_proxy vs cf->cycle->paths).
     * also, we cannot allocate our temp cycle on the stack
     * because some modules like ngx_http_core_module reference
     * addresses within cf->cycle (i.e., via "&cf->cycle->new_log")
     */

    fake_cycle = ngx_palloc(cycle->pool, sizeof(ngx_cycle_t));
    if (fake_cycle == NULL) {
        goto failed;
    }

    ngx_memcpy(fake_cycle, cycle, sizeof(ngx_cycle_t));

    ngx_queue_init(&fake_cycle->reusable_connections_queue);

    if (ngx_array_init(&fake_cycle->listening, cycle->pool,
                       cycle->listening.nelts ? cycle->listening.nelts : 1,
                       sizeof(ngx_listening_t))
        != NGX_OK)
    {
        goto failed;
    }

    if (ngx_array_init(&fake_cycle->paths, cycle->pool,
                       cycle->paths.nelts ? cycle->paths.nelts : 1,
                       sizeof(ngx_path_t *))
        != NGX_OK)
    {
        goto failed;
    }

    part = &cycle->open_files.part;
    ofile = part->elts;

    if (ngx_list_init(&fake_cycle->open_files, cycle->pool,
                      part->nelts ? part->nelts : 1,
                      sizeof(ngx_open_file_t))
        != NGX_OK)
    {
        goto failed;
    }

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            ofile = part->elts;
            i = 0;
        }

        file = ngx_list_push(&fake_cycle->open_files);
        if (file == NULL) {
            goto failed;
        }

        ngx_memcpy(file, ofile, sizeof(ngx_open_file_t));
    }

    if (ngx_list_init(&fake_cycle->shared_memory, cycle->pool, 1,
                      sizeof(ngx_shm_zone_t))
        != NGX_OK)
    {
        goto failed;
    }

    conf.ctx = &http_ctx;
    conf.cycle = fake_cycle;
    conf.pool = fake_cycle->pool;
    conf.log = cycle->log;

    ngx_memzero(&cf_file, sizeof(cf_file));
    cf_file.file.name = cycle->conf_file;
    conf.conf_file = &cf_file;

    http_ctx.loc_conf = ngx_pcalloc(conf.pool,
                                    sizeof(void *) * ngx_http_max_module);
    if (http_ctx.loc_conf == NULL) {
        return NGX_ERROR;
    }

    http_ctx.srv_conf = ngx_pcalloc(conf.pool,
                                    sizeof(void *) * ngx_http_max_module);
    if (http_ctx.srv_conf == NULL) {
        return NGX_ERROR;
    }

#if (nginx_version >= 1009011)
    modules = cycle->modules;
#else
    modules = ngx_modules;
#endif

    for (i = 0; modules[i]; i++) {
        if (modules[i]->type != NGX_HTTP_MODULE) {
            continue;
        }

        module = modules[i]->ctx;

        if (module->create_srv_conf) {
            cur = module->create_srv_conf(&conf);
            if (cur == NULL) {
                return NGX_ERROR;
            }

            http_ctx.srv_conf[modules[i]->ctx_index] = cur;

            if (module->merge_srv_conf) {
                prev = module->create_srv_conf(&conf);
                if (prev == NULL) {
                    return NGX_ERROR;
                }

                rv = module->merge_srv_conf(&conf, prev, cur);
                if (rv != NGX_CONF_OK) {
                    goto failed;
                }
            }
        }

        if (module->create_loc_conf) {
            cur = module->create_loc_conf(&conf);
            if (cur == NULL) {
                return NGX_ERROR;
            }

            http_ctx.loc_conf[modules[i]->ctx_index] = cur;

            if (module->merge_loc_conf) {
                if (modules[i] == &ngx_http_lua_module) {
                    prev = top_llcf;

                } else if (modules[i] == &ngx_http_core_module) {
                    prev = top_clcf;

                } else {
                    prev = module->create_loc_conf(&conf);
                    if (prev == NULL) {
                        return NGX_ERROR;
                    }
                }

                rv = module->merge_loc_conf(&conf, prev, cur);
                if (rv != NGX_CONF_OK) {
                    goto failed;
                }
            }
        }
    }

    ngx_destroy_pool(conf.temp_pool);
    conf.temp_pool = NULL;

    c = ngx_http_lua_create_fake_connection(NULL);
    if (c == NULL) {
        goto failed;
    }

    c->log->handler = ngx_http_lua_log_init_worker_error;

    r = ngx_http_lua_create_fake_request(c);
    if (r == NULL) {
        goto failed;
    }

    r->main_conf = http_ctx.main_conf;
    r->srv_conf = http_ctx.srv_conf;
    r->loc_conf = http_ctx.loc_conf;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

#if (nginx_version >= 1009000)
    ngx_set_connection_log(r->connection, clcf->error_log);

#else
    ngx_http_set_connection_log(r->connection, clcf->error_log);
#endif

    ctx = ngx_http_lua_create_ctx(r);
    if (ctx == NULL) {
        goto failed;
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_INIT_WORKER;
    ctx->cur_co_ctx = NULL;
    r->read_event_handler = ngx_http_block_reading;

    ngx_http_lua_set_req(lmcf->lua, r);

    (void) lmcf->init_worker_handler(cycle->log, lmcf, lmcf->lua);

    ngx_destroy_pool(c->pool);
    return NGX_OK;

failed:

    if (conf.temp_pool) {
        ngx_destroy_pool(conf.temp_pool);
    }

    if (c) {
        ngx_http_lua_close_fake_connection(c);
    }

    return NGX_ERROR;
}


ngx_int_t
ngx_http_lua_init_worker_by_inline(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L)
{
    int         status;
    const char *chunkname;

    if (lmcf->init_worker_chunkname == NULL) {
        chunkname = "=init_worker_by_lua";

    } else {
        chunkname = (const char *) lmcf->init_worker_chunkname;
    }

    status = luaL_loadbuffer(L, (char *) lmcf->init_worker_src.data,
                             lmcf->init_worker_src.len, chunkname)
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "init_worker_by_lua");
}


ngx_int_t
ngx_http_lua_init_worker_by_file(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
    lua_State *L)
{
    int         status;

    status = luaL_loadfile(L, (char *) lmcf->init_worker_src.data)
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "init_worker_by_lua_file");
}


static u_char *
ngx_http_lua_log_init_worker_error(ngx_log_t *log, u_char *buf, size_t len)
{
    u_char              *p;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    return ngx_snprintf(buf, len, ", context: init_worker_by_lua*");
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
