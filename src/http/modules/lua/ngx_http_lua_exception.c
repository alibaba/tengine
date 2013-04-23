/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

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
    u_char                  *s;
    size_t                   len;
    ngx_http_request_t      *r;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    /*  log Lua VM crashing reason to error log */
    if (r && r->connection && r->connection->log) {
        s = (u_char *) lua_tolstring(L, -1, &len);
        if (s == NULL) {
            s = (u_char *) "unknown reason";
            len = sizeof("unknown reason") - 1;
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "lua atpanic: Lua VM crashed, reason: %*s", len, s);

    } else {

        dd("lua atpanic: can't output Lua VM crashing reason to error log"
                " due to invalid logging context");
    }

    /*  restore nginx execution */
    NGX_LUA_EXCEPTION_THROW(1);

    /* impossible to reach here */
    return 0;
}

