
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_headers_out.h"
#include "ngx_http_lua_headers_in.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_http_version(lua_State *L);
static int ngx_http_lua_ngx_req_raw_header(lua_State *L);
static int ngx_http_lua_ngx_req_header_set_helper(lua_State *L);
static int ngx_http_lua_ngx_header_get(lua_State *L);
static int ngx_http_lua_ngx_header_set(lua_State *L);
static int ngx_http_lua_ngx_req_get_headers(lua_State *L);
static int ngx_http_lua_ngx_req_header_clear(lua_State *L);
static int ngx_http_lua_ngx_req_header_set(lua_State *L);


static int
ngx_http_lua_ngx_req_http_version(lua_State *L)
{
    ngx_http_request_t          *r;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    switch (r->http_version) {
    case NGX_HTTP_VERSION_9:
        lua_pushnumber(L, 0.9);
        break;

    case NGX_HTTP_VERSION_10:
        lua_pushnumber(L, 1.0);
        break;

    case NGX_HTTP_VERSION_11:
        lua_pushnumber(L, 1.1);
        break;

    default:
        lua_pushnil(L);
        break;
    }

    return 1;
}


static int
ngx_http_lua_ngx_req_raw_header(lua_State *L)
{
    int                          n;
    u_char                      *data, *p, *last, *pos;
    unsigned                     no_req_line = 0, found;
    size_t                       size;
    ngx_buf_t                   *b, *first = NULL;
    ngx_int_t                    i;
    ngx_http_request_t          *r;
    ngx_http_connection_t       *hc;

    n = lua_gettop(L);
    if (n > 0) {
        no_req_line = lua_toboolean(L, 1);
    }

    dd("no req line: %d", (int) no_req_line);

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    hc = r->main->http_connection;

    if (hc->nbusy) {
        b = NULL;  /* to suppress a gcc warning */
        size = 0;
        for (i = 0; i < hc->nbusy; i++) {
            b = hc->busy[i];

            if (first == NULL) {
                if (r->main->request_line.data >= b->pos
                    || r->main->request_line.data
                       + r->main->request_line.len + 2
                       <= b->start)
                {
                    continue;
                }

                dd("found first at %d", (int) i);
                first = b;
            }

            if (b == r->main->header_in) {
                size += r->main->header_end + 2 - b->start;
                break;
            }

            size += b->pos - b->start;
        }

    } else {
        b = r->main->header_in;

        if (b == NULL) {
            lua_pushnil(L);
            return 1;
        }

        if (b == r->main->header_in) {
            size = r->main->header_end + 2 - r->main->request_line.data;

        } else {
            size = b->pos - r->main->request_line.data;
        }
    }

    data = lua_newuserdata(L, size);

    if (hc->nbusy) {
        last = data;
        found = 0;
        for (i = 0; i < hc->nbusy; i++) {
            b = hc->busy[i];

            if (!found) {
                if (b != first) {
                    continue;
                }

                dd("found first");
                found = 1;
            }

            p = last;

            if (b == r->main->header_in) {
                pos = r->main->header_end + 2;

            } else {
                pos = b->pos;
            }

            if (b == first) {
                dd("request line: %.*s", (int) r->main->request_line.len,
                   r->main->request_line.data);

                if (no_req_line) {
                    last = ngx_copy(last,
                                    r->main->request_line.data
                                    + r->main->request_line.len + 2,
                                    pos - r->main->request_line.data
                                    - r->main->request_line.len - 2);

                } else {
                    last = ngx_copy(last,
                                    r->main->request_line.data,
                                    pos - r->main->request_line.data);

                }

            } else {
                last = ngx_copy(last, b->start, pos - b->start);
            }

#if 1
            /* skip truncated header entries (if any) */
            while (last > p && last[-1] != LF) {
                last--;
            }
#endif

            for (; p != last; p++) {
                if (*p == '\0') {
                    if (p + 1 == last) {
                        /* XXX this should not happen */
                        dd("found string end!!");

                    } else if (*(p + 1) == LF) {
                        *p = CR;

                    } else {
                        *p = ':';
                    }
                }
            }

            if (b == r->main->header_in) {
                break;
            }
        }

    } else {
        if (no_req_line) {
            last = ngx_copy(data,
                            r->main->request_line.data
                            + r->main->request_line.len + 2,
                            size - r->main->request_line.len - 2);

        } else {
            last = ngx_copy(data, r->main->request_line.data, size);
        }

        for (p = data; p != last; p++) {
            if (*p == '\0') {
                if (p + 1 != last && *(p + 1) == LF) {
                    *p = CR;

                } else {
                    *p = ':';
                }
            }
        }
    }

    if (last - data > (ssize_t) size) {
        return luaL_error(L, "buffer error");
    }

    lua_pushlstring(L, (char *) data, last - data);
    return 1;
}


static int
ngx_http_lua_ngx_req_get_headers(lua_State *L) {
    ngx_list_part_t              *part;
    ngx_table_elt_t              *header;
    ngx_http_request_t           *r;
    ngx_uint_t                    i;
    int                           n;
    int                           max;
    int                           raw = 0;
    int                           count = 0;

    n = lua_gettop(L);

    if (n >= 1) {
        if (lua_isnil(L, 1)) {
            max = NGX_HTTP_LUA_MAX_HEADERS;

        } else {
            max = luaL_checkinteger(L, 1);
        }

        if (n >= 2) {
            raw = lua_toboolean(L, 2);
        }

    } else {
        max = NGX_HTTP_LUA_MAX_HEADERS;
    }

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    lua_createtable(L, 0, 4);

    if (!raw) {
        lua_pushlightuserdata(L, &ngx_http_lua_req_get_headers_metatable_key);
        lua_rawget(L, LUA_REGISTRYINDEX);
        lua_setmetatable(L, -2);
    }

    part = &r->headers_in.headers.part;
    header = part->elts;

    for (i = 0; /* void */; i++) {

        dd("stack top: %d", lua_gettop(L));

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            header = part->elts;
            i = 0;
        }

        if (raw) {
            lua_pushlstring(L, (char *) header[i].key.data, header[i].key.len);

        } else {
            lua_pushlstring(L, (char *) header[i].lowcase_key,
                            header[i].key.len);
        }

        /* stack: table key */

        lua_pushlstring(L, (char *) header[i].value.data,
                        header[i].value.len); /* stack: table key value */

        ngx_http_lua_set_multi_value_table(L, -3);

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua request header: \"%V: %V\"",
                       &header[i].key, &header[i].value);

        if (max > 0 && ++count == max) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua hit request header limit %d", max);

            return 1;
        }
    }

    return 1;
}


static int
ngx_http_lua_ngx_header_get(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p;
    ngx_str_t                    key;
    ngx_uint_t                   i;
    size_t                       len;
    ngx_http_lua_loc_conf_t     *llcf;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    /* we skip the first argument that is the table */
    p = (u_char *) luaL_checklstring(L, 2, &len);

    dd("key: %.*s, len %d", (int) len, p, (int) len);

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->transform_underscores_in_resp_headers) {
        /* replace "_" with "-" */
        for (i = 0; i < len; i++) {
            if (p[i] == '_') {
                p[i] = '-';
            }
        }
    }

    key.data = ngx_palloc(r->pool, len + 1);
    if (key.data == NULL) {
        return luaL_error(L, "out of memory");
    }

    ngx_memcpy(key.data, p, len);

    key.data[len] = '\0';

    key.len = len;

    return ngx_http_lua_get_output_header(L, r, &key);
}


static int
ngx_http_lua_ngx_header_set(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p;
    ngx_str_t                    key;
    ngx_str_t                    value;
    ngx_uint_t                   i;
    size_t                       len;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    ngx_http_lua_loc_conf_t     *llcf;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx->headers_sent) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "attempt to "
                      "set ngx.header.HEADER after sending out "
                      "response headers");
        return 0;
    }

    /* we skip the first argument that is the table */
    p = (u_char *) luaL_checklstring(L, 2, &len);

    dd("key: %.*s, len %d", (int) len, p, (int) len);

    key.data = ngx_palloc(r->pool, len + 1);
    if (key.data == NULL) {
        return luaL_error(L, "out of memory");
    }

    ngx_memcpy(key.data, p, len);
    key.data[len] = '\0';
    key.len = len;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->transform_underscores_in_resp_headers) {
        /* replace "_" with "-" */
        p = key.data;
        for (i = 0; i < len; i++) {
            if (p[i] == '_') {
                p[i] = '-';
            }
        }
    }

    if (!ctx->headers_set) {
        rc = ngx_http_set_content_type(r);
        if (rc != NGX_OK) {
            return luaL_error(L,
                              "failed to set default content type: %d",
                              (int) rc);
        }

        ctx->headers_set = 1;
    }

    if (lua_type(L, 3) == LUA_TNIL) {
        value.data = NULL;
        value.len = 0;

    } else if (lua_type(L, 3) == LUA_TTABLE) {
        n = luaL_getn(L, 3);
        if (n == 0) {
            value.data = NULL;
            value.len = 0;

        } else {
            for (i = 1; i <= n; i++) {
                dd("header value table index %d", (int) i);

                lua_rawgeti(L, 3, i);
                p = (u_char *) luaL_checklstring(L, -1, &len);

                value.data = ngx_palloc(r->pool, len);
                if (value.data == NULL) {
                    return luaL_error(L, "out of memory");
                }

                ngx_memcpy(value.data, p, len);
                value.len = len;

                rc = ngx_http_lua_set_output_header(r, key, value,
                                                    i == 1 /* override */);

                if (rc == NGX_ERROR) {
                    return luaL_error(L,
                                      "failed to set header %s (error: %d)",
                                      key.data, (int) rc);
                }
            }

            return 0;
        }

    } else {
        p = (u_char *) luaL_checklstring(L, 3, &len);
        value.data = ngx_palloc(r->pool, len);
        if (value.data == NULL) {
            return luaL_error(L, "out of memory");
        }

        ngx_memcpy(value.data, p, len);
        value.len = len;
    }

    dd("key: %.*s, value: %.*s",
       (int) key.len, key.data, (int) value.len, value.data);

    rc = ngx_http_lua_set_output_header(r, key, value, 1 /* override */);

    if (rc == NGX_ERROR) {
        return luaL_error(L, "failed to set header %s (error: %d)",
                          key.data, (int) rc);
    }

    return 0;
}


static int
ngx_http_lua_ngx_req_header_clear(lua_State *L)
{
    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one arguments, but seen %d",
                          lua_gettop(L));
    }

    lua_pushnil(L);

    return ngx_http_lua_ngx_req_header_set_helper(L);
}


static int
ngx_http_lua_ngx_req_header_set(lua_State *L)
{
    if (lua_gettop(L) != 2) {
        return luaL_error(L, "expecting two arguments, but seen %d",
                          lua_gettop(L));
    }

    return ngx_http_lua_ngx_req_header_set_helper(L);
}


static int
ngx_http_lua_ngx_req_header_set_helper(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p;
    ngx_str_t                    key;
    ngx_str_t                    value;
    ngx_uint_t                   i;
    size_t                       len;
    ngx_int_t                    rc;
    ngx_uint_t                   n;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    p = (u_char *) luaL_checklstring(L, 1, &len);

    dd("key: %.*s, len %d", (int) len, p, (int) len);

    /* replace "_" with "-" */
    for (i = 0; i < len; i++) {
        if (p[i] == '_') {
            p[i] = '-';
        }
    }

    key.data = ngx_palloc(r->pool, len + 1);
    if (key.data == NULL) {
        return luaL_error(L, "out of memory");
    }

    ngx_memcpy(key.data, p, len);

    key.data[len] = '\0';

    key.len = len;

    if (lua_type(L, 2) == LUA_TNIL) {
        value.data = NULL;
        value.len = 0;

    } else if (lua_type(L, 2) == LUA_TTABLE) {
        n = luaL_getn(L, 2);
        if (n == 0) {
            value.data = NULL;
            value.len = 0;

        } else {
            for (i = 1; i <= n; i++) {
                dd("header value table index %d, top: %d", (int) i,
                   lua_gettop(L));

                lua_rawgeti(L, 2, i);
                p = (u_char *) luaL_checklstring(L, -1, &len);

                /*
                 * we also copy the trailling '\0' char here because nginx
                 * header values must be null-terminated
                 * */

                value.data = ngx_palloc(r->pool, len + 1);
                if (value.data == NULL) {
                    return luaL_error(L, "out of memory");
                }

                ngx_memcpy(value.data, p, len + 1);
                value.len = len;

                rc = ngx_http_lua_set_input_header(r, key, value,
                                                   i == 1 /* override */);

                if (rc == NGX_ERROR) {
                    return luaL_error(L,
                                      "failed to set header %s (error: %d)",
                                      key.data, (int) rc);
                }
            }

            return 0;
        }

    } else {

        /*
         * we also copy the trailling '\0' char here because nginx
         * header values must be null-terminated
         * */

        p = (u_char *) luaL_checklstring(L, 2, &len);
        value.data = ngx_palloc(r->pool, len + 1);
        if (value.data == NULL) {
            return luaL_error(L, "out of memory");
        }

        ngx_memcpy(value.data, p, len + 1);
        value.len = len;
    }

    dd("key: %.*s, value: %.*s",
       (int) key.len, key.data, (int) value.len, value.data);

    rc = ngx_http_lua_set_input_header(r, key, value, 1 /* override */);

    if (rc == NGX_ERROR) {
        return luaL_error(L, "failed to set header %s (error: %d)",
                          key.data, (int) rc);
    }

    return 0;
}


void
ngx_http_lua_inject_resp_header_api(lua_State *L)
{
    lua_newtable(L);    /* .header */

    lua_createtable(L, 0, 2); /* metatable for .header */
    lua_pushcfunction(L, ngx_http_lua_ngx_header_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_ngx_header_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    lua_setfield(L, -2, "header");
}


void
ngx_http_lua_inject_req_header_api(ngx_log_t *log, lua_State *L)
{
    int         rc;

    lua_pushcfunction(L, ngx_http_lua_ngx_req_http_version);
    lua_setfield(L, -2, "http_version");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_raw_header);
    lua_setfield(L, -2, "raw_header");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_header_clear);
    lua_setfield(L, -2, "clear_header");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_header_set);
    lua_setfield(L, -2, "set_header");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_headers);
    lua_setfield(L, -2, "get_headers");

    lua_pushlightuserdata(L, &ngx_http_lua_req_get_headers_metatable_key);
    lua_createtable(L, 0, 1); /* metatable for ngx.req.get_headers(_, true) */

    {
        const char buf[] =
            "local tb, key = ...\n"
            "local new_key = string.gsub(string.lower(key), '_', '-')\n"
            "if new_key ~= key then return tb[new_key] else return nil end";

        rc = luaL_loadbuffer(L, buf, sizeof(buf) - 1,
                             "ngx.req.get_headers __index");
    }

    if (rc != 0) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "failed to load Lua code of the metamethod for "
                      "ngx.req.get_headers: %i: %s", rc, lua_tostring(L, -1));

        lua_pop(L, 3);
        return;
    }

    lua_setfield(L, -2, "__index");
    lua_rawset(L, LUA_REGISTRYINDEX);
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
