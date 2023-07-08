
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"
#include "api/ngx_http_lua_api.h"
#include "ngx_http_lua_shdict.h"
#include "ngx_http_lua_util.h"


lua_State *
ngx_http_lua_get_global_state(ngx_conf_t *cf)
{
    ngx_http_lua_main_conf_t *lmcf;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    return lmcf->lua;
}


ngx_http_request_t *
ngx_http_lua_get_request(lua_State *L)
{
    return ngx_http_lua_get_req(L);
}


static ngx_int_t ngx_http_lua_shared_memory_init(ngx_shm_zone_t *shm_zone,
    void *data);


ngx_int_t
ngx_http_lua_add_package_preload(ngx_conf_t *cf, const char *package,
    lua_CFunction func)
{
    lua_State                     *L;
    ngx_http_lua_main_conf_t      *lmcf;
    ngx_http_lua_preload_hook_t   *hook;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    L = lmcf->lua;

    if (L) {
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "preload");
        lua_pushcfunction(L, func);
        lua_setfield(L, -2, package);
        lua_pop(L, 2);
    }

    /* we always register preload_hooks since we always create new Lua VMs
     * when lua code cache is off. */

    if (lmcf->preload_hooks == NULL) {
        lmcf->preload_hooks =
            ngx_array_create(cf->pool, 4,
                             sizeof(ngx_http_lua_preload_hook_t));

        if (lmcf->preload_hooks == NULL) {
            return NGX_ERROR;
        }
    }

    hook = ngx_array_push(lmcf->preload_hooks);
    if (hook == NULL) {
        return NGX_ERROR;
    }

    hook->package = (u_char *) package;
    hook->loader = func;

    return NGX_OK;
}


ngx_shm_zone_t *
ngx_http_lua_shared_memory_add(ngx_conf_t *cf, ngx_str_t *name, size_t size,
    void *tag)
{
    ngx_http_lua_main_conf_t     *lmcf;
    ngx_shm_zone_t              **zp;
    ngx_shm_zone_t               *zone;
    ngx_http_lua_shm_zone_ctx_t  *ctx;
    ngx_int_t                     n;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);
    if (lmcf == NULL) {
        return NULL;
    }

    if (lmcf->shm_zones == NULL) {
        lmcf->shm_zones = ngx_palloc(cf->pool, sizeof(ngx_array_t));
        if (lmcf->shm_zones == NULL) {
            return NULL;
        }

        if (ngx_array_init(lmcf->shm_zones, cf->pool, 2,
                           sizeof(ngx_shm_zone_t *))
            != NGX_OK)
        {
            return NULL;
        }
    }

    zone = ngx_shared_memory_add(cf, name, (size_t) size, tag);
    if (zone == NULL) {
        return NULL;
    }

    if (zone->data) {
        ctx = (ngx_http_lua_shm_zone_ctx_t *) zone->data;
        return &ctx->zone;
    }

    n = sizeof(ngx_http_lua_shm_zone_ctx_t);

    ctx = ngx_pcalloc(cf->pool, n);
    if (ctx == NULL) {
        return NULL;
    }

    ctx->lmcf = lmcf;
    ctx->log = &cf->cycle->new_log;
    ctx->cycle = cf->cycle;

    ngx_memcpy(&ctx->zone, zone, sizeof(ngx_shm_zone_t));

    zp = ngx_array_push(lmcf->shm_zones);
    if (zp == NULL) {
        return NULL;
    }

    *zp = zone;

    /* set zone init */
    zone->init = ngx_http_lua_shared_memory_init;
    zone->data = ctx;

    lmcf->requires_shm = 1;

    return &ctx->zone;
}


static ngx_int_t
ngx_http_lua_shared_memory_init(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_http_lua_shm_zone_ctx_t *octx = data;
    ngx_shm_zone_t              *ozone;
    void                        *odata;

    ngx_int_t                    rc;
    volatile ngx_cycle_t        *saved_cycle;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_shm_zone_ctx_t *ctx;
    ngx_shm_zone_t              *zone;

    ctx = (ngx_http_lua_shm_zone_ctx_t *) shm_zone->data;
    zone = &ctx->zone;

    odata = NULL;
    if (octx) {
        ozone = &octx->zone;
        odata = ozone->data;
    }

    zone->shm = shm_zone->shm;
#if (nginx_version >= 1009000)
    zone->noreuse = shm_zone->noreuse;
#endif

    if (zone->init(zone, odata) != NGX_OK) {
        return NGX_ERROR;
    }

    dd("get lmcf");

    lmcf = ctx->lmcf;
    if (lmcf == NULL) {
        return NGX_ERROR;
    }

    dd("lmcf->lua: %p", lmcf->lua);

    lmcf->shm_zones_inited++;

    if (lmcf->shm_zones_inited == lmcf->shm_zones->nelts
        && lmcf->init_handler && !ngx_test_config)
    {
        saved_cycle = ngx_cycle;
        ngx_cycle = ctx->cycle;

        rc = lmcf->init_handler(ctx->log, lmcf, lmcf->lua);

        ngx_cycle = saved_cycle;

        if (rc != NGX_OK) {
            /* an error happened */
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


ngx_http_lua_co_ctx_t *
ngx_http_lua_get_cur_co_ctx(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    return ctx->cur_co_ctx;
}


void
ngx_http_lua_set_cur_co_ctx(ngx_http_request_t *r, ngx_http_lua_co_ctx_t *coctx)
{
    ngx_http_lua_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    coctx->data = r;

    ctx->cur_co_ctx = coctx;
}


lua_State *
ngx_http_lua_get_co_ctx_vm(ngx_http_lua_co_ctx_t *coctx)
{
    return coctx->co;
}


static ngx_int_t
ngx_http_lua_co_ctx_resume(ngx_http_request_t *r)
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

    rc = ngx_http_lua_run_thread(vm, r, ctx, ctx->cur_co_ctx->nrets);

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


void
ngx_http_lua_co_ctx_resume_helper(ngx_http_lua_co_ctx_t *coctx, int nrets)
{
    ngx_connection_t        *c;
    ngx_http_request_t      *r;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_log_ctx_t      *log_ctx;

    r = coctx->data;
    c = r->connection;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        return;
    }

    if (c->fd != (ngx_socket_t) -1) {  /* not a fake connection */
        log_ctx = c->log->data;
        log_ctx->current_request = r;
    }

    coctx->nrets = nrets;
    coctx->cleanup = NULL;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua coctx resume handler: \"%V?%V\"", &r->uri, &r->args);

    ctx->cur_co_ctx = coctx;

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_co_ctx_resume(r);

    } else {
        ctx->resume_handler = ngx_http_lua_co_ctx_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
}


int
ngx_http_lua_get_lua_http10_buffering(ngx_http_request_t *r)
{
    ngx_http_lua_loc_conf_t      *llcf;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    return llcf->http10_buffering;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
