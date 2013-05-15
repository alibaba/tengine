
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_args.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_set_uri_args(lua_State *L);
static int ngx_http_lua_ngx_req_get_uri_args(lua_State *L);
static int ngx_http_lua_ngx_req_get_post_args(lua_State *L);


static int
ngx_http_lua_ngx_req_set_uri_args(lua_State *L) {
    ngx_http_request_t          *r;
    ngx_str_t                    args;
    const char                  *msg;
    size_t                       len;
    u_char                      *p;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting 1 argument but seen %d",
                          lua_gettop(L));
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    switch (lua_type(L, 1)) {
    case LUA_TNUMBER:
    case LUA_TSTRING:
        p = (u_char *) lua_tolstring(L, 1, &len);

        args.data = ngx_palloc(r->pool, len);
        if (args.data == NULL) {
            return luaL_error(L, "out of memory");
        }

        ngx_memcpy(args.data, p, len);

        args.len = len;
        break;

    case LUA_TTABLE:
        ngx_http_lua_process_args_option(r, L, 1, &args);

        dd("args: %.*s", (int) args.len, args.data);

        break;

    default:
        msg = lua_pushfstring(L, "string, number, or table expected, "
                              "but got %s", luaL_typename(L, 2));
        return luaL_argerror(L, 1, msg);
    }

    dd("args: %.*s", (int) args.len, args.data);

    r->args.data = args.data;
    r->args.len = args.len;

    r->valid_unparsed_uri = 0;

    return 0;
}


static int
ngx_http_lua_ngx_req_get_uri_args(lua_State *L) {
    ngx_http_request_t          *r;
    u_char                      *buf;
    u_char                      *last;
    int                          retval;
    int                          n;
    int                          max;

    n = lua_gettop(L);

    if (n != 0 && n != 1) {
        return luaL_error(L, "expecting 0 or 1 arguments but seen %d", n);
    }

    if (n == 1) {
        max = luaL_checkinteger(L, 1);
        lua_pop(L, 1);

    } else {
        max = NGX_HTTP_LUA_MAX_ARGS;
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    lua_createtable(L, 0, 4);

    /* we copy r->args over to buf to simplify
     * unescaping query arg keys and values */

    buf = ngx_palloc(r->pool, r->args.len);
    if (buf == NULL) {
        return luaL_error(L, "out of memory");
    }

    ngx_memcpy(buf, r->args.data, r->args.len);

    last = buf + r->args.len;

    retval = ngx_http_lua_parse_args(r, L, buf, last, max);

    ngx_pfree(r->pool, buf);

    return retval;
}


static int
ngx_http_lua_ngx_req_get_post_args(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *buf;
    int                          retval;
    size_t                       len;
    ngx_chain_t                 *cl;
    u_char                      *p;
    u_char                      *last;
    int                          n;
    int                          max;

    n = lua_gettop(L);

    if (n != 0 && n != 1) {
        return luaL_error(L, "expecting 0 or 1 arguments but seen %d", n);
    }

    if (n == 1) {
        max = luaL_checkinteger(L, 1);
        lua_pop(L, 1);

    } else {
        max = NGX_HTTP_LUA_MAX_ARGS;
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (r->discard_body) {
        lua_createtable(L, 0, 4);
        return 1;
    }

    if (r->request_body == NULL) {
        return luaL_error(L, "no request body found; "
                          "maybe you should turn on lua_need_request_body?");
    }

    if (r->request_body->temp_file) {
        return luaL_error(L, "requesty body in temp file not supported");
    }

    lua_createtable(L, 0, 4);

    if (r->request_body->bufs == NULL) {
        return 1;
    }

    /* we copy r->request_body->bufs over to buf to simplify
     * unescaping query arg keys and values */

    len = 0;
    for (cl = r->request_body->bufs; cl; cl = cl->next) {
        len += cl->buf->last - cl->buf->pos;
    }

    dd("post body length: %d", (int) len);

    buf = ngx_palloc(r->pool, len);
    if (buf == NULL) {
        return luaL_error(L, "out of memory");
    }

    p = buf;
    for (cl = r->request_body->bufs; cl; cl = cl->next) {
        p = ngx_copy(p, cl->buf->pos, cl->buf->last - cl->buf->pos);
    }

    dd("post body: %.*s", (int) len, buf);

    last = buf + len;

    retval = ngx_http_lua_parse_args(r, L, buf, last, max);

    ngx_pfree(r->pool, buf);

    return retval;
}


int
ngx_http_lua_parse_args(ngx_http_request_t *r, lua_State *L, u_char *buf,
        u_char *last, int max)
{
    u_char                      *p, *q;
    u_char                      *src, *dst;
    unsigned                     parsing_value;
    size_t                       len;
    int                          count = 0;
    int                          top;

    top = lua_gettop(L);

    p = buf;

    parsing_value = 0;
    q = p;

    while (p != last) {
        if (*p == '=' && ! parsing_value) {
            /* key data is between p and q */

            src = q; dst = q;

            ngx_http_lua_unescape_uri(&dst, &src, p - q,
                                      NGX_UNESCAPE_URI_COMPONENT);

            dd("pushing key %.*s", (int) (dst - q), q);

            /* push the key */
            lua_pushlstring(L, (char *) q, dst - q);

            /* skip the current '=' char */
            p++;

            q = p;
            parsing_value = 1;

        } else if (*p == '&') {
            /* reached the end of a key or a value, just save it */
            src = q; dst = q;

            ngx_http_lua_unescape_uri(&dst, &src, p - q,
                                      NGX_UNESCAPE_URI_COMPONENT);

            dd("pushing key or value %.*s", (int) (dst - q), q);

            /* push the value or key */
            lua_pushlstring(L, (char *) q, dst - q);

            /* skip the current '&' char */
            p++;

            q = p;

            if (parsing_value) {
                /* end of the current pair's value */
                parsing_value = 0;

            } else {
                /* the current parsing pair takes no value,
                 * just push the value "true" */
                dd("pushing boolean true");

                lua_pushboolean(L, 1);
            }

            (void) lua_tolstring(L, -2, &len);

            if (len == 0) {
                /* ignore empty string key pairs */
                dd("popping key and value...");
                lua_pop(L, 2);

            } else {
                dd("setting table...");
                ngx_http_lua_set_multi_value_table(L, top);
            }

            if (max > 0 && ++count == max) {
                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "lua hit query args limit %d", max);

                return 1;
            }

        } else {
            p++;
        }
    }

    if (p != q || parsing_value) {
        src = q; dst = q;

        ngx_http_lua_unescape_uri(&dst, &src, p - q,
                                  NGX_UNESCAPE_URI_COMPONENT);

        dd("pushing key or value %.*s", (int) (dst - q), q);

        lua_pushlstring(L, (char *) q, dst - q);

        if (!parsing_value) {
            dd("pushing boolean true...");
            lua_pushboolean(L, 1);
        }

        (void) lua_tolstring(L, -2, &len);

        if (len == 0) {
            /* ignore empty string key pairs */
            dd("popping key and value...");
            lua_pop(L, 2);

        } else {
            dd("setting table...");
            ngx_http_lua_set_multi_value_table(L, top);
        }
    }

    dd("gettop: %d", lua_gettop(L));
    dd("type: %s", lua_typename(L, lua_type(L, 1)));

    if (lua_gettop(L) != top) {
        return luaL_error(L, "internal error: stack in bad state");
    }

    return 1;
}


void
ngx_http_lua_inject_req_args_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_uri_args);
    lua_setfield(L, -2, "set_uri_args");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_uri_args);
    lua_setfield(L, -2, "get_uri_args");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_uri_args);
    lua_setfield(L, -2, "get_query_args"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_post_args);
    lua_setfield(L, -2, "get_post_args");
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
