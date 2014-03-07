
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif

#include "ddebug.h"
#include "ngx_http_lua_initby.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_report(ngx_log_t *log, lua_State *L, int status);
static int ngx_http_lua_do_call(ngx_log_t *log, lua_State *L);


int
ngx_http_lua_init_by_inline(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
    lua_State *L)
{
    int         status;

    status = luaL_loadbuffer(L, (char *) lmcf->init_src.data,
                             lmcf->init_src.len, "init_by_lua")
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status);
}


int
ngx_http_lua_init_by_file(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
    lua_State *L)
{
    int         status;

    status = luaL_loadfile(L, (char *) lmcf->init_src.data)
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status);
}


static int
ngx_http_lua_report(ngx_log_t *log, lua_State *L, int status)
{
    const char      *msg;

    if (status && !lua_isnil(L, -1)) {
        msg = lua_tostring(L, -1);
        if (msg == NULL) {
            msg = "unknown error";
        }

        ngx_log_error(NGX_LOG_ERR, log, 0, "failed to run init_by_lua*: %s",
                      msg);
        lua_pop(L, 1);
    }

    /* force a full garbage-collection cycle */
    lua_gc(L, LUA_GCCOLLECT, 0);

    return status;
}


static int
ngx_http_lua_do_call(ngx_log_t *log, lua_State *L)
{
    int     status, base;

    base = lua_gettop(L);  /* function index */
    lua_pushcfunction(L, ngx_http_lua_traceback);  /* push traceback function */
    lua_insert(L, base);  /* put it under chunk and args */
    status = lua_pcall(L, 0, 0, base);
    lua_remove(L, base);

    return status;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
