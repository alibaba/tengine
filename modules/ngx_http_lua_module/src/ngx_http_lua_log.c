
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
#include "ngx_http_lua_log_ringbuf.h"
#include "ngx_http_lua_output.h"


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
    int                          level;

    r = ngx_http_lua_get_req(L);

    if (r && r->connection && r->connection->log) {
        log = r->connection->log;

    } else {
        log = ngx_cycle->log;
    }

    level = luaL_checkint(L, 1);
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

    r = ngx_http_lua_get_req(L);

    if (r && r->connection && r->connection->log) {
        log = r->connection->log;

    } else {
        log = ngx_cycle->log;
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
                size += ngx_http_lua_get_num_len(L, i);
                break;

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

            case LUA_TTABLE:
                if (!luaL_callmeta(L, i, "__tostring")) {
                    return luaL_argerror(L, i, "expected table to have "
                                         "__tostring metamethod");
                }

                lua_tolstring(L, -1, &len);
                size += len;
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
                     ar.currentline > 0 ? ar.currentline : ar.linedefined);

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
                p = ngx_http_lua_write_num(L, i, p);
                break;

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

            case LUA_TTABLE:
                luaL_callmeta(L, i, "__tostring");
                q = (u_char *) lua_tolstring(L, -1, &len);
                p = ngx_copy(p, q, len);
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


#ifdef HAVE_INTERCEPT_ERROR_LOG_PATCH
ngx_int_t
ngx_http_lua_capture_log_handler(ngx_log_t *log,
    ngx_uint_t level, u_char *buf, size_t n)
{
    ngx_http_lua_log_ringbuf_t  *ringbuf;

    dd("enter");

    ringbuf = (ngx_http_lua_log_ringbuf_t  *)
                    ngx_cycle->intercept_error_log_data;

    if (level > ringbuf->filter_level) {
        return NGX_OK;
    }

    ngx_http_lua_log_ringbuf_write(ringbuf, level, buf, n);

    dd("capture log: %s\n", buf);

    return NGX_OK;
}
#endif


int
ngx_http_lua_ffi_errlog_set_filter_level(int level, u_char *err, size_t *errlen)
{
#ifdef HAVE_INTERCEPT_ERROR_LOG_PATCH
    ngx_http_lua_log_ringbuf_t     *ringbuf;

    ringbuf = ngx_cycle->intercept_error_log_data;

    if (ringbuf == NULL) {
        *errlen = ngx_snprintf(err, *errlen,
                               "directive \"lua_capture_error_log\" is not set")
                  - err;
        return NGX_ERROR;
    }

    if (level > NGX_LOG_DEBUG || level < NGX_LOG_STDERR) {
        *errlen = ngx_snprintf(err, *errlen, "bad log level: %d", level)
                  - err;
        return NGX_ERROR;
    }

    ringbuf->filter_level = level;
    return NGX_OK;
#else
    *errlen = ngx_snprintf(err, *errlen,
                           "missing the capture error log patch for nginx")
              - err;
    return NGX_ERROR;
#endif
}


int
ngx_http_lua_ffi_errlog_get_msg(char **log, int *loglevel, u_char *err,
    size_t *errlen, double *log_time)
{
#ifdef HAVE_INTERCEPT_ERROR_LOG_PATCH
    ngx_uint_t           loglen;

    ngx_http_lua_log_ringbuf_t     *ringbuf;

    ringbuf = ngx_cycle->intercept_error_log_data;

    if (ringbuf == NULL) {
        *errlen = ngx_snprintf(err, *errlen,
                               "directive \"lua_capture_error_log\" is not set")
                  - err;
        return NGX_ERROR;
    }

    if (ringbuf->count == 0) {
        return NGX_DONE;
    }

    ngx_http_lua_log_ringbuf_read(ringbuf, loglevel, (void **) log, &loglen,
                                  log_time);
    return loglen;
#else
    *errlen = ngx_snprintf(err, *errlen,
                           "missing the capture error log patch for nginx")
              - err;
    return NGX_ERROR;
#endif
}


int
ngx_http_lua_ffi_errlog_get_sys_filter_level(ngx_http_request_t *r)
{
    ngx_log_t                   *log;
    int                          log_level;

    if (r && r->connection && r->connection->log) {
        log = r->connection->log;

    } else {
        log = ngx_cycle->log;
    }

    log_level = log->log_level;
    if (log_level == NGX_LOG_DEBUG_ALL) {
        log_level = NGX_LOG_DEBUG;
    }

    return log_level;
}


int
ngx_http_lua_ffi_raw_log(ngx_http_request_t *r, int level, u_char *s,
    size_t s_len)
{
    ngx_log_t           *log;

    if (level > NGX_LOG_DEBUG || level < NGX_LOG_STDERR) {
        return NGX_ERROR;
    }

    if (r && r->connection && r->connection->log) {
        log = r->connection->log;

    } else {
        log = ngx_cycle->log;
    }

    ngx_log_error((unsigned) level, log, 0, "%*s", s_len, s);

    return NGX_OK;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
