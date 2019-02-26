/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http.h>
#include <ngx_http_dyups.h>
#include <ngx_http_dyups_lua.h>


static int ngx_http_dyups_lua_register(lua_State *L);
static int ngx_http_lua_update_upstream(lua_State *L);
static int ngx_http_lua_delete_upstream(lua_State *L);


static int
ngx_http_lua_update_upstream(lua_State *L)
{
    size_t     size;
    ngx_int_t  status;
    ngx_str_t  name, rv;
    ngx_buf_t  buf;

    if (lua_gettop(L) != 2) {
        return luaL_error(L, "exactly 2 arguments expected");
    }

    name.data = (u_char *) luaL_checklstring(L, 1, &name.len);
    buf.pos = buf.start = (u_char *) luaL_checklstring(L, 2, &size);
    buf.last = buf.end = buf.pos + size;

    status = ngx_dyups_update_upstream(&name, &buf, &rv);

    lua_pushinteger(L, (lua_Integer) status);
    lua_pushlstring(L, (char *) rv.data, rv.len);

    return 2;
}


static int
ngx_http_lua_delete_upstream(lua_State *L)
{
    ngx_int_t  status;
    ngx_str_t  name, rv;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "exactly 1 argument expected");
    }

    name.data = (u_char *) luaL_checklstring(L, 1, &name.len);

    status = ngx_dyups_delete_upstream(&name, &rv);

    lua_pushinteger(L, (lua_Integer) status);
    lua_pushlstring(L, (char *) rv.data, rv.len);

    return 2;
}


static int
ngx_http_dyups_lua_register(lua_State *L)
{
    lua_createtable(L, 0, 1);

    lua_pushcfunction(L, ngx_http_lua_update_upstream);
    lua_setfield(L, -2, "update");

    lua_pushcfunction(L, ngx_http_lua_delete_upstream);
    lua_setfield(L, -2, "delete");

    return 1;
}


ngx_int_t
ngx_http_dyups_lua_preload(ngx_conf_t *cf)
{
    if (ngx_http_lua_add_package_preload(cf, "ngx.dyups",
                                         ngx_http_dyups_lua_register)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    return NGX_OK;
}
