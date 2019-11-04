/*
 * This fake_delayed_load delayed load module was used to reproduce
 * a bug in ngx_lua's function ngx_http_lua_add_package_preload.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


#include "ngx_http_lua_api.h"


static ngx_int_t ngx_http_lua_fake_delayed_load_init(ngx_conf_t *cf);
static int ngx_http_lua_fake_delayed_load_preload(lua_State *L);
static int ngx_http_lua_fake_delayed_load_function(lua_State * L);


static ngx_http_module_t ngx_http_lua_fake_delayed_load_module_ctx = {
    NULL,                                 /* preconfiguration */
    ngx_http_lua_fake_delayed_load_init,  /* postconfiguration */

    NULL,                                 /* create main configuration */
    NULL,                                 /* init main configuration */

    NULL,                                 /* create server configuration */
    NULL,                                 /* merge server configuration */

    NULL,                                 /* create location configuration */
    NULL,                                 /* merge location configuration */
};

/* flow identify module struct */
ngx_module_t  ngx_http_lua_fake_delayed_load_module = {
    NGX_MODULE_V1,
    &ngx_http_lua_fake_delayed_load_module_ctx,   /* module context */
    NULL,                                         /* module directives */
    NGX_HTTP_MODULE,                              /* module type */
    NULL,                                         /* init master */
    NULL,                                         /* init module */
    NULL,                                         /* init process */
    NULL,                                         /* init thread */
    NULL,                                         /* exit thread */
    NULL,                                         /* exit process */
    NULL,                                         /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_lua_fake_delayed_load_init(ngx_conf_t *cf)
{
    ngx_http_lua_add_package_preload(cf, "ngx.delayed_load",
                                     ngx_http_lua_fake_delayed_load_preload);
    return NGX_OK;
}


static int
ngx_http_lua_fake_delayed_load_preload(lua_State *L)
{
    lua_createtable(L, 0, 1);

    lua_pushcfunction(L, ngx_http_lua_fake_delayed_load_function);
    lua_setfield(L, -2, "get_function");

    return 1;
}


static int
ngx_http_lua_fake_delayed_load_function(lua_State * L)
{
    return 0;
}
