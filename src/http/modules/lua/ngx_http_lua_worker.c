
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_worker.h"


static int ngx_http_lua_ngx_worker_exiting(lua_State *L);


void
ngx_http_lua_inject_worker_api(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 1 /* nrec */);    /* ngx.timer. */

    lua_pushcfunction(L, ngx_http_lua_ngx_worker_exiting);
    lua_setfield(L, -2, "exiting");

    lua_setfield(L, -2, "worker");
}


static int
ngx_http_lua_ngx_worker_exiting(lua_State *L)
{
    lua_pushboolean(L, ngx_exiting);
    return 1;
}
