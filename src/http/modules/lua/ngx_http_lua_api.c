/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#include "ddebug.h"

#include "ngx_http_lua_common.h"
#include "api/ngx_http_lua_api.h"


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
    ngx_http_request_t *r;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    return r;
}


void
ngx_http_lua_add_package_preload(ngx_conf_t *cf, const char *package,
                         lua_CFunction func)
{
    ngx_http_lua_main_conf_t *lmcf;
    lua_State                *L;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);
    L = lmcf->lua;
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");
    lua_pushcfunction(L, func);
    lua_setfield(L, -2, package);
    lua_pop(L, 2);
}

