
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
#if defined(nginx_version) && nginx_version >= 1009000
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
        && lmcf->init_handler)
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

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
