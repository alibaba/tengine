
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_log.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_print(lua_State *L);
static int ngx_http_lua_ngx_log(lua_State *L);
static int log_wrapper(ngx_log_t *log, const char *ident,
    ngx_uint_t level, lua_State *L);
static void ngx_http_lua_inject_log_consts(lua_State *L);


/**
 * Wrapper of nginx log functionality. Take a log level param and varargs of
 * log message params.
 *
 * @param L Lua state pointer
 * @retval always 0 (don't return values to Lua)
 * */
int
ngx_http_lua_ngx_log(lua_State *L)
{
    ngx_log_t                   *log;
    ngx_http_request_t          *r;
    const char                  *msg;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r && r->connection && r->connection->log) {
        log = r->connection->log;

    } else {
        lua_pushlightuserdata(L, &ngx_http_lua_cf_log_key);
        lua_rawget(L, LUA_REGISTRYINDEX);
        log = lua_touserdata(L, -1);
        lua_pop(L, 1);
    }

    int level = luaL_checkint(L, 1);
    if (level < NGX_LOG_STDERR || level > NGX_LOG_DEBUG) {
        msg = lua_pushfstring(L, "bad log level: %d", level);
        return luaL_argerror(L, 1, msg);
    }

    /* remove log-level param from stack */
    lua_remove(L, 1);

    return log_wrapper(log, "[lua] ", (ngx_uint_t) level, L);
}


/**
 * Override Lua print function, output message to nginx error logs. Equal to
 * ngx.log(ngx.NOTICE, ...).
 *
 * @param L Lua state pointer
 * @retval always 0 (don't return values to Lua)
 * */
int
ngx_http_lua_print(lua_State *L)
{
    ngx_log_t                   *log;
    ngx_http_request_t          *r;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r && r->connection && r->connection->log) {
        log = r->connection->log;

    } else {
        lua_pushlightuserdata(L, &ngx_http_lua_cf_log_key);
        lua_rawget(L, LUA_REGISTRYINDEX);
        log = lua_touserdata(L, -1);
        lua_pop(L, 1);
    }

    return log_wrapper(log, "[lua] ", NGX_LOG_NOTICE, L);
}


static int
log_wrapper(ngx_log_t *log, const char *ident, ngx_uint_t level,
    lua_State *L)
{
    u_char              *buf;
    u_char              *p, *q;
    ngx_str_t            name;
    int                  nargs, i;
    size_t               size, len;
    size_t               src_len = 0;
    int                  type;
    const char          *msg;
    lua_Debug            ar;

    if (level > log->log_level) {
        return 0;
    }

#if 1
    /* add debug info */

    lua_getstack(L, 1, &ar);
    lua_getinfo(L, "Snl", &ar);

    /* get the basename of the Lua source file path, stored in q */
    name.data = (u_char *) ar.short_src;
    if (name.data == NULL) {
        name.len = 0;

    } else {
        p = name.data;
        while (*p != '\0') {
            if (*p == '/' || *p == '\\') {
                name.data = p + 1;
            }
            p++;
        }

        name.len = p - name.data;
    }

#endif

    nargs = lua_gettop(L);

    size = name.len + NGX_INT_T_LEN + sizeof(":: ") - 1;

    if (*ar.namewhat != '\0' && *ar.what == 'L') {
        src_len = ngx_strlen(ar.name);
        size += src_len + sizeof("(): ") - 1;
    }

    for (i = 1; i <= nargs; i++) {
        type = lua_type(L, i);
        switch (type) {
            case LUA_TNUMBER:
            case LUA_TSTRING:
                lua_tolstring(L, i, &len);
                size += len;
                break;

            case LUA_TNIL:
                size += sizeof("nil") - 1;
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, i)) {
                    size += sizeof("true") - 1;

                } else {
                    size += sizeof("false") - 1;
                }

                break;

            case LUA_TLIGHTUSERDATA:
                if (lua_touserdata(L, i) == NULL) {
                    size += sizeof("null") - 1;
                    break;
                }

                continue;

            default:
                msg = lua_pushfstring(L, "string, number, boolean, or nil "
                                      "expected, got %s",
                                      lua_typename(L, type));
                return luaL_argerror(L, i, msg);
        }
    }

    buf = lua_newuserdata(L, size);

    p = ngx_copy(buf, name.data, name.len);

    *p++ = ':';

    p = ngx_snprintf(p, NGX_INT_T_LEN, "%d",
                     ar.currentline ? ar.currentline : ar.linedefined);

    *p++ = ':'; *p++ = ' ';

    if (*ar.namewhat != '\0' && *ar.what == 'L') {
        p = ngx_copy(p, ar.name, src_len);
        *p++ = '(';
        *p++ = ')';
        *p++ = ':';
        *p++ = ' ';
    }

    for (i = 1; i <= nargs; i++) {
        type = lua_type(L, i);
        switch (type) {
            case LUA_TNUMBER:
            case LUA_TSTRING:
                q = (u_char *) lua_tolstring(L, i, &len);
                p = ngx_copy(p, q, len);
                break;

            case LUA_TNIL:
                *p++ = 'n';
                *p++ = 'i';
                *p++ = 'l';
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, i)) {
                    *p++ = 't';
                    *p++ = 'r';
                    *p++ = 'u';
                    *p++ = 'e';

                } else {
                    *p++ = 'f';
                    *p++ = 'a';
                    *p++ = 'l';
                    *p++ = 's';
                    *p++ = 'e';
                }

                break;

            case LUA_TLIGHTUSERDATA:
                *p++ = 'n';
                *p++ = 'u';
                *p++ = 'l';
                *p++ = 'l';

                break;

            default:
                return luaL_error(L, "impossible to reach here");
        }
    }

    if (p - buf > (off_t) size) {
        return luaL_error(L, "buffer error: %d > %d", (int) (p - buf),
                          (int) size);
    }

    ngx_log_error(level, log, 0, "%s%*s", ident, (size_t) (p - buf), buf);

    return 0;
}


void
ngx_http_lua_inject_log_api(lua_State *L)
{
    ngx_http_lua_inject_log_consts(L);

    lua_pushcfunction(L, ngx_http_lua_ngx_log);
    lua_setfield(L, -2, "log");

    lua_pushcfunction(L, ngx_http_lua_print);
    lua_setglobal(L, "print");
}


static void
ngx_http_lua_inject_log_consts(lua_State *L)
{
    /* {{{ nginx log level constants */
    lua_pushinteger(L, NGX_LOG_STDERR);
    lua_setfield(L, -2, "STDERR");

    lua_pushinteger(L, NGX_LOG_EMERG);
    lua_setfield(L, -2, "EMERG");

    lua_pushinteger(L, NGX_LOG_ALERT);
    lua_setfield(L, -2, "ALERT");

    lua_pushinteger(L, NGX_LOG_CRIT);
    lua_setfield(L, -2, "CRIT");

    lua_pushinteger(L, NGX_LOG_ERR);
    lua_setfield(L, -2, "ERR");

    lua_pushinteger(L, NGX_LOG_WARN);
    lua_setfield(L, -2, "WARN");

    lua_pushinteger(L, NGX_LOG_NOTICE);
    lua_setfield(L, -2, "NOTICE");

    lua_pushinteger(L, NGX_LOG_INFO);
    lua_setfield(L, -2, "INFO");

    lua_pushinteger(L, NGX_LOG_DEBUG);
    lua_setfield(L, -2, "DEBUG");
    /* }}} */
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
