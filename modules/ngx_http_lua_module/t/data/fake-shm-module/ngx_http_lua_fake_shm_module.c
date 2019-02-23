#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>


#include "ngx_http_lua_api.h"


static void *ngx_http_lua_fake_shm_create_main_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_lua_fake_shm_init(ngx_conf_t *cf);

static char *ngx_http_lua_fake_shm(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_lua_fake_shm_init_zone(ngx_shm_zone_t *shm_zone,
    void *data);
static int ngx_http_lua_fake_shm_preload(lua_State *L);
static int ngx_http_lua_fake_shm_get_info(lua_State *L);


typedef struct {
    ngx_array_t     *shm_zones;
} ngx_http_lua_fake_shm_main_conf_t;


static ngx_command_t ngx_http_lua_fake_shm_cmds[] = {

    { ngx_string("lua_fake_shm"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE2,
      ngx_http_lua_fake_shm,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_lua_fake_shm_module_ctx = {
    NULL,                                   /* preconfiguration */
    ngx_http_lua_fake_shm_init,             /* postconfiguration */

    ngx_http_lua_fake_shm_create_main_conf, /* create main configuration */
    NULL,                                   /* init main configuration */

    NULL,                                   /* create server configuration */
    NULL,                                   /* merge server configuration */

    NULL,                                   /* create location configuration */
    NULL,                                   /* merge location configuration */
};


ngx_module_t  ngx_http_lua_fake_shm_module = {
    NGX_MODULE_V1,
    &ngx_http_lua_fake_shm_module_ctx, /* module context */
    ngx_http_lua_fake_shm_cmds,        /* module directives */
    NGX_HTTP_MODULE,                   /* module type */
    NULL,                              /* init master */
    NULL,                              /* init module */
    NULL,                              /* init process */
    NULL,                              /* init thread */
    NULL,                              /* exit thread */
    NULL,                              /* exit process */
    NULL,                              /* exit master */
    NGX_MODULE_V1_PADDING
};


typedef struct {
    ngx_str_t   name;
    size_t      size;
    ngx_int_t   isold;
    ngx_int_t   isinit;
} ngx_http_lua_fake_shm_ctx_t;


static void *
ngx_http_lua_fake_shm_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_lua_fake_shm_main_conf_t *lfsmcf;

    lfsmcf = ngx_pcalloc(cf->pool, sizeof(*lfsmcf));
    if (lfsmcf == NULL) {
        return NULL;
    }

    return lfsmcf;
}


static char *
ngx_http_lua_fake_shm(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_lua_fake_shm_main_conf_t   *lfsmcf = conf;

    ngx_str_t                   *value, name;
    ngx_shm_zone_t              *zone;
    ngx_shm_zone_t             **zp;
    ngx_http_lua_fake_shm_ctx_t *ctx;
    ssize_t                      size;

    if (lfsmcf->shm_zones == NULL) {
        lfsmcf->shm_zones = ngx_palloc(cf->pool, sizeof(ngx_array_t));
        if (lfsmcf->shm_zones == NULL) {
            return NGX_CONF_ERROR;
        }

        if (ngx_array_init(lfsmcf->shm_zones, cf->pool, 2,
                           sizeof(ngx_shm_zone_t *))
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }
    }

    value = cf->args->elts;

    ctx = NULL;

    if (value[1].len == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid lua fake_shm name \"%V\"", &value[1]);
        return NGX_CONF_ERROR;
    }

    name = value[1];

    size = ngx_parse_size(&value[2]);

    if (size <= 8191) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid lua fake_shm size \"%V\"", &value[2]);
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_fake_shm_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->name = name;
    ctx->size = size;

    zone = ngx_http_lua_shared_memory_add(cf, &name, (size_t) size,
                                          &ngx_http_lua_fake_shm_module);
    if (zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (zone->data) {
        ctx = zone->data;

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "lua_fake_shm \"%V\" is already defined as "
                           "\"%V\"", &name, &ctx->name);
        return NGX_CONF_ERROR;
    }

    zone->init = ngx_http_lua_fake_shm_init_zone;
    zone->data = ctx;

    zp = ngx_array_push(lfsmcf->shm_zones);
    if (zp == NULL) {
        return NGX_CONF_ERROR;
    }

    *zp = zone;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_lua_fake_shm_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_http_lua_fake_shm_ctx_t  *octx = data;

    ngx_http_lua_fake_shm_ctx_t  *ctx;

    ctx = shm_zone->data;

    if (octx) {
        ctx->isold = 1;
    }

    ctx->isinit = 1;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_fake_shm_init(ngx_conf_t *cf)
{
    ngx_http_lua_add_package_preload(cf, "fake_shm_zones",
                                     ngx_http_lua_fake_shm_preload);
    return NGX_OK;
}


static int
ngx_http_lua_fake_shm_preload(lua_State *L)
{
    ngx_http_lua_fake_shm_main_conf_t *lfsmcf;
    ngx_http_conf_ctx_t               *hmcf_ctx;
    ngx_cycle_t                       *cycle;

    ngx_uint_t                   i;
    ngx_shm_zone_t             **zone;
    ngx_shm_zone_t             **zone_udata;

    cycle = (ngx_cycle_t *) ngx_cycle;

    hmcf_ctx = (ngx_http_conf_ctx_t *) cycle->conf_ctx[ngx_http_module.index];
    lfsmcf = hmcf_ctx->main_conf[ngx_http_lua_fake_shm_module.ctx_index];

    if (lfsmcf->shm_zones != NULL) {
        lua_createtable(L, 0, lfsmcf->shm_zones->nelts /* nrec */);

        lua_createtable(L, 0 /* narr */, 2 /* nrec */); /* shared mt */

        lua_pushcfunction(L, ngx_http_lua_fake_shm_get_info);
        lua_setfield(L, -2, "get_info");

        lua_pushvalue(L, -1); /* shared mt mt */
        lua_setfield(L, -2, "__index"); /* shared mt */

        zone = lfsmcf->shm_zones->elts;

        for (i = 0; i < lfsmcf->shm_zones->nelts; i++) {
            lua_pushlstring(L, (char *) zone[i]->shm.name.data,
                            zone[i]->shm.name.len);

            /* shared mt key */

            lua_createtable(L, 1 /* narr */, 0 /* nrec */);
                /* table of zone[i] */
            zone_udata = lua_newuserdata(L, sizeof(ngx_shm_zone_t *));
                /* shared mt key ud */
            *zone_udata = zone[i];
            lua_rawseti(L, -2, 1); /* {zone[i]} */
            lua_pushvalue(L, -3); /* shared mt key ud mt */
            lua_setmetatable(L, -2); /* shared mt key ud */
            lua_rawset(L, -4); /* shared mt */
        }

        lua_pop(L, 1); /* shared */

    } else {
        lua_newtable(L);    /* ngx.shared */
    }

    return 1;
}


static int
ngx_http_lua_fake_shm_get_info(lua_State *L)
{
    ngx_int_t                         n;
    ngx_shm_zone_t                   *zone;
    ngx_shm_zone_t                  **zone_udata;
    ngx_http_lua_fake_shm_ctx_t      *ctx;

    n = lua_gettop(L);

    if (n != 1) {
        return luaL_error(L, "expecting exactly one arguments, "
                          "but only seen %d", n);
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, 1);
    zone_udata = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (zone_udata == NULL) {
        return luaL_error(L, "bad \"zone\" argument");
    }

    zone = *zone_udata;

    ctx = (ngx_http_lua_fake_shm_ctx_t *) zone->data;

    lua_pushlstring(L, (char *) zone->shm.name.data, zone->shm.name.len);
    lua_pushnumber(L, zone->shm.size);
    lua_pushboolean(L, ctx->isinit);
    lua_pushboolean(L, ctx->isold);

    return 4;
}
