
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <nginx.h>
#include <ngx_md5.h>
#include "ngx_http_lua_common.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_clfactory.h"
#include "ngx_http_lua_util.h"


/**
 * Find code chunk associated with the given key in code cache,
 * and push it to the top of Lua stack if found.
 *
 * Stack layout before call:
 *         |     ...    | <- top
 *
 * Stack layout after call:
 *         | code chunk | <- top
 *         |     ...    |
 *
 * */
static ngx_int_t
ngx_http_lua_cache_load_code(ngx_log_t *log, lua_State *L,
    const char *key)
{
#ifndef OPENRESTY_LUAJIT
    int          rc;
    u_char      *err;
#endif

    /*  get code cache table */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          code_cache_key));
    lua_rawget(L, LUA_REGISTRYINDEX);    /*  sp++ */

    dd("Code cache table to load: %p", lua_topointer(L, -1));

    if (!lua_istable(L, -1)) {
        dd("Error: code cache table to load did not exist!!");
        return NGX_ERROR;
    }

    lua_getfield(L, -1, key);    /*  sp++ */

    if (lua_isfunction(L, -1)) {
#ifdef OPENRESTY_LUAJIT
        lua_remove(L, -2);   /*  sp-- */
        return NGX_OK;
#else
        /*  call closure factory to gen new closure */
        rc = lua_pcall(L, 0, 1, 0);
        if (rc == 0) {
            /*  remove cache table from stack, leave code chunk at
             *  top of stack */
            lua_remove(L, -2);   /*  sp-- */
            return NGX_OK;
        }

        if (lua_isstring(L, -1)) {
            err = (u_char *) lua_tostring(L, -1);

        } else {
            err = (u_char *) "unknown error";
        }

        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "lua: failed to run factory at key \"%s\": %s",
                      key, err);
        lua_pop(L, 2);
        return NGX_ERROR;
#endif /* OPENRESTY_LUAJIT */
    }

    dd("Value associated with given key in code cache table is not code "
       "chunk: stack top=%d, top value type=%s\n",
       lua_gettop(L), lua_typename(L, -1));

    /*  remove cache table and value from stack */
    lua_pop(L, 2);                                /*  sp-=2 */

    return NGX_DECLINED;
}


/**
 * Store the closure factory at the top of Lua stack to code cache, and
 * associate it with the given key. Then generate new closure.
 *
 * Stack layout before call:
 *         | code factory | <- top
 *         |     ...      |
 *
 * Stack layout after call:
 *         | code chunk | <- top
 *         |     ...    |
 *
 * */
static ngx_int_t
ngx_http_lua_cache_store_code(lua_State *L, const char *key)
{
#ifndef OPENRESTY_LUAJIT
    int rc;
#endif

    /*  get code cache table */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          code_cache_key));
    lua_rawget(L, LUA_REGISTRYINDEX);

    dd("Code cache table to store: %p", lua_topointer(L, -1));

    if (!lua_istable(L, -1)) {
        dd("Error: code cache table to load did not exist!!");
        return NGX_ERROR;
    }

    lua_pushvalue(L, -2); /* closure cache closure */
    lua_setfield(L, -2, key); /* closure cache */

    /*  remove cache table, leave closure factory at top of stack */
    lua_pop(L, 1); /* closure */

#ifndef OPENRESTY_LUAJIT
    /*  call closure factory to generate new closure */
    rc = lua_pcall(L, 0, 1, 0);
    if (rc != 0) {
        dd("Error: failed to call closure factory!!");
        return NGX_ERROR;
    }
#endif

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_cache_loadbuffer(ngx_log_t *log, lua_State *L,
    const u_char *src, size_t src_len, const u_char *cache_key,
    const char *name)
{
    int          n;
    ngx_int_t    rc;
    const char  *err = NULL;

    n = lua_gettop(L);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                   "looking up Lua code cache with key '%s'", cache_key);

    rc = ngx_http_lua_cache_load_code(log, L, (char *) cache_key);
    if (rc == NGX_OK) {
        /*  code chunk loaded from cache, sp++ */
        dd("Code cache hit! cache key='%s', stack top=%d, script='%.*s'",
           cache_key, lua_gettop(L), (int) src_len, src);
        return NGX_OK;
    }

    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    /* rc == NGX_DECLINED */

    dd("Code cache missed! cache key='%s', stack top=%d, script='%.*s'",
       cache_key, lua_gettop(L), (int) src_len, src);

    /* load closure factory of inline script to the top of lua stack, sp++ */
    rc = ngx_http_lua_clfactory_loadbuffer(L, (char *) src, src_len, name);

    if (rc != 0) {
        /*  Oops! error occurred when loading Lua script */
        if (rc == LUA_ERRMEM) {
            err = "memory allocation error";

        } else {
            if (lua_isstring(L, -1)) {
                err = lua_tostring(L, -1);

            } else {
                err = "unknown error";
            }
        }

        goto error;
    }

    /*  store closure factory and gen new closure at the top of lua stack to
     *  code cache */
    rc = ngx_http_lua_cache_store_code(L, (char *) cache_key);
    if (rc != NGX_OK) {
        err = "fail to generate new closure from the closure factory";
        goto error;
    }

    return NGX_OK;

error:

    ngx_log_error(NGX_LOG_ERR, log, 0,
                  "failed to load inlined Lua code: %s", err);
    lua_settop(L, n);
    return NGX_ERROR;
}


ngx_int_t
ngx_http_lua_cache_loadfile(ngx_log_t *log, lua_State *L,
    const u_char *script, const u_char *cache_key)
{
    int              n;
    ngx_int_t        rc, errcode = NGX_ERROR;
    u_char          *p;
    u_char           buf[NGX_HTTP_LUA_FILE_KEY_LEN + 1];
    const char      *err = NULL;

    n = lua_gettop(L);

    /*  calculate digest of script file path */
    if (cache_key == NULL) {
        dd("CACHE file key not pre-calculated...calculating");
        p = ngx_copy(buf, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);

        p = ngx_http_lua_digest_hex(p, script, ngx_strlen(script));

        *p = '\0';
        cache_key = buf;

    } else {
        dd("CACHE file key already pre-calculated");
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                   "looking up Lua code cache with key '%s'", cache_key);

    rc = ngx_http_lua_cache_load_code(log, L, (char *) cache_key);
    if (rc == NGX_OK) {
        /*  code chunk loaded from cache, sp++ */
        dd("Code cache hit! cache key='%s', stack top=%d, file path='%s'",
           cache_key, lua_gettop(L), script);
        return NGX_OK;
    }

    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    /* rc == NGX_DECLINED */

    dd("Code cache missed! cache key='%s', stack top=%d, file path='%s'",
       cache_key, lua_gettop(L), script);

    /*  load closure factory of script file to the top of lua stack, sp++ */
    rc = ngx_http_lua_clfactory_loadfile(L, (char *) script);

    dd("loadfile returns %d (%d)", (int) rc, LUA_ERRFILE);

    if (rc != 0) {
        /*  Oops! error occurred when loading Lua script */
        switch (rc) {
        case LUA_ERRMEM:
            err = "memory allocation error";
            break;

        case LUA_ERRFILE:
            errcode = NGX_HTTP_NOT_FOUND;
            /* fall through */

        default:
            if (lua_isstring(L, -1)) {
                err = lua_tostring(L, -1);

            } else {
                err = "unknown error";
            }
        }

        goto error;
    }

    /*  store closure factory and gen new closure at the top of lua stack
     *  to code cache */
    rc = ngx_http_lua_cache_store_code(L, (char *) cache_key);
    if (rc != NGX_OK) {
        err = "fail to generate new closure from the closure factory";
        goto error;
    }

    return NGX_OK;

error:

    ngx_log_error(NGX_LOG_ERR, log, 0,
                  "failed to load external Lua file \"%s\": %s", script, err);

    lua_settop(L, n);
    return errcode;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
