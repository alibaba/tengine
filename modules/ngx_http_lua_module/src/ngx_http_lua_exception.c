
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_util.h"


/*  longjmp mark for restoring nginx execution after Lua VM crashing */
jmp_buf ngx_http_lua_exception;

/**
 * Override default Lua panic handler, output VM crash reason to nginx error
 * log, and restore execution to the nearest jmp-mark.
 *
 * @param L Lua state pointer
 * @retval Long jump to the nearest jmp-mark, never returns.
 * @note nginx request pointer should be stored in Lua thread's globals table
 * in order to make logging working.
 * */
int
ngx_http_lua_atpanic(lua_State *L)
{
#ifdef NGX_LUA_ABORT_AT_PANIC
    abort();
#else
    u_char                  *s = NULL;
    size_t                   len = 0;

    if (lua_type(L, -1) == LUA_TSTRING) {
        s = (u_char *) lua_tolstring(L, -1, &len);
    }

    if (s == NULL) {
        s = (u_char *) "unknown reason";
        len = sizeof("unknown reason") - 1;
    }

    ngx_log_stderr(0, "lua atpanic: Lua VM crashed, reason: %*s", len, s);
    ngx_quit = 1;

    /*  restore nginx execution */
    NGX_LUA_EXCEPTION_THROW(1);

    /* impossible to reach here */
#endif
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
