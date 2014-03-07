
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

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ngx_http_lua_check_fake_request(L, r);

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
    ngx_connection_t            *c;
    ngx_http_request_t          *r, *mr;
    ngx_http_connection_t       *hc;

    n = lua_gettop(L);
    if (n > 0) {
        no_req_line = lua_toboolean(L, 1);
    }

    dd("no req line: %d", (int) no_req_line);

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ngx_http_lua_check_fake_request(L, r);

    mr = r->main;
    hc = mr->http_connection;
    c = mr->connection;

#if 0
    dd("hc->nbusy: %d", (int) hc->nbusy);

    dd("hc->busy: %p %p %p %p", hc->busy[0]->start, hc->busy[0]->pos,
       hc->busy[0]->last, hc->busy[0]->end);

    dd("request line: %p %p", mr->request_line.data,
       mr->request_line.data + mr->request_line.len);

    dd("header in: %p %p %p %p", mr->header_in->start,
       mr->header_in->pos, mr->header_in->last,
       mr->header_in->end);

    dd("c->buffer: %p %p %p %p", c->buffer->start,
       c->buffer->pos, c->buffer->last,
       c->buffer->end);
#endif

    size = 0;
    b = c->buffer;

    if (mr->request_line.data >= b->start
        && mr->request_line.data + mr->request_line.len + 2 <= b->pos)
    {
        first = b;

        if (mr->header_in == b) {
            size += mr->header_end + 2 - mr->request_line.data;

        } else {
            /* the subsequent part of the header is in the large header
             * buffers */
#if 1
            p = b->pos;
            size += p - mr->request_line.data;

            /* skip truncated header entries (if any) */
            while (b->pos > b->start && b->pos[-1] != LF) {
                b->pos--;
                size--;
            }
#endif
        }
    }

    if (hc->nbusy) {
        b = NULL;
        for (i = 0; i < hc->nbusy; i++) {
            b = hc->busy[i];

            dd("busy buf: %d: [%.*s]", (int) i, (int) (b->pos - b->start),
               b->start);

            if (first == NULL) {
                if (mr->request_line.data >= b->pos
                    || mr->request_line.data
                       + mr->request_line.len + 2
                       <= b->start)
                {
                    continue;
                }

                dd("found first at %d", (int) i);
                first = b;
            }

            if (b == mr->header_in) {
                size += mr->header_end + 2 - b->start;
                break;
            }

            size += b->pos - b->start;
        }
    }

    data = lua_newuserdata(L, size);
    last = data;

    b = c->buffer;
    if (first == b) {
        if (mr->header_in == b) {
            pos = mr->header_end + 2;

        } else {
            pos = b->pos;
        }

        if (no_req_line) {
            last = ngx_copy(data,
                            mr->request_line.data
                            + mr->request_line.len + 2,
                            pos - mr->request_line.data
                            - mr->request_line.len - 2);

        } else {
            last = ngx_copy(data, mr->request_line.data,
                            pos - mr->request_line.data);
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

    if (hc->nbusy) {
        found = (b == c->buffer);
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

            if (b == mr->header_in) {
                pos = mr->header_end + 2;

            } else {
                pos = b->pos;
            }

            if (b == first) {
                dd("request line: %.*s", (int) mr->request_line.len,
                   mr->request_line.data);

                if (no_req_line) {
                    last = ngx_copy(last,
                                    mr->request_line.data
                                    + mr->request_line.len + 2,
                                    pos - mr->request_line.data
                                    - mr->request_line.len - 2);

                } else {
                    last = ngx_copy(last,
                                    mr->request_line.data,
                                    pos - mr->request_line.data);

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

            if (b == mr->header_in) {
                break;
            }
        }
    }

    if (last - data > (ssize_t) size) {
        return luaL_error(L, "buffer error: %d", (int) (last - data - size));
    }

    lua_pushlstring(L, (char *) data, last - data);
    return 1;
}


static int
ngx_http_lua_ngx_req_get_headers(lua_State *L)
{
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

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ngx_http_lua_check_fake_request(L, r);

    part = &r->headers_in.headers.part;
    count = part->nelts;
    while (part->next) {
        part = part->next;
        count += part->nelts;
    }

    if (max > 0 && count > max) {
        count = max;
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua exceeding request header limit %d", max);
    }

    lua_createtable(L, 0, count);

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

        if (--count == 0) {
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

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ngx_http_lua_check_fake_request(L, r);

    /* we skip the first argument that is the table */
    p = (u_char *) luaL_checklstring(L, 2, &len);

    dd("key: %.*s, len %d", (int) len, p, (int) len);

    key.data = ngx_palloc(r->pool, len + 1);
    if (key.data == NULL) {
        return luaL_error(L, "out of memory");
    }

    ngx_memcpy(key.data, p, len);

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->transform_underscores_in_resp_headers) {
        /* replace "_" with "-" */
        for (i = 0; i < len; i++) {
            if (key.data[i] == '_') {
                key.data[i] = '-';
            }
        }
    }

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

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->header_sent) {
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
        rc = ngx_http_lua_set_content_type(r);
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

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->http_version < NGX_HTTP_VERSION_10) {
        return 0;
    }

    p = (u_char *) luaL_checklstring(L, 1, &len);

    dd("key: %.*s, len %d", (int) len, p, (int) len);

#if 0
    /* replace "_" with "-" */
    for (i = 0; i < len; i++) {
        if (p[i] == '_') {
            p[i] = '-';
        }
    }
#endif

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


#ifndef NGX_HTTP_LUA_NO_FFI_API
int
ngx_http_lua_ffi_req_get_headers_count(ngx_http_request_t *r, int max)
{
    int                           count;
    ngx_list_part_t              *part;

    if (r->connection->fd == -1) {
        return NGX_HTTP_LUA_FFI_BAD_CONTEXT;
    }

    if (max < 0) {
        max = NGX_HTTP_LUA_MAX_HEADERS;
    }

    part = &r->headers_in.headers.part;
    count = part->nelts;
    while (part->next) {
        part = part->next;
        count += part->nelts;
    }

    if (max > 0 && count > max) {
        count = max;
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua exceeding request header limit %d", max);
    }

    return count;
}


int
ngx_http_lua_ffi_req_get_headers(ngx_http_request_t *r,
    ngx_http_lua_ffi_table_elt_t *out, int count, int raw)
{
    int                           n;
    ngx_uint_t                    i;
    ngx_list_part_t              *part;
    ngx_table_elt_t              *header;

    if (count <= 0) {
        return NGX_OK;
    }

    n = 0;
    part = &r->headers_in.headers.part;
    header = part->elts;

    for (i = 0; /* void */; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            header = part->elts;
            i = 0;
        }

        if (raw) {
            out[n].key.data = header[i].key.data;
            out[n].key.len = (int) header[i].key.len;

        } else {
            out[n].key.data = header[i].lowcase_key;
            out[n].key.len = (int) header[i].key.len;
        }

        out[n].value.data = header[i].value.data;
        out[n].value.len = (int) header[i].value.len;

        if (++n == count) {
            return NGX_OK;
        }
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_set_resp_header(ngx_http_request_t *r, const u_char *key_data,
    size_t key_len, int is_nil, const u_char *sval, size_t sval_len,
    ngx_str_t *mvals, size_t mvals_len, char **errmsg)
{
    u_char                      *p;
    ngx_str_t                    value, key;
    ngx_uint_t                   i;
    size_t                       len;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;
    ngx_http_lua_loc_conf_t     *llcf;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_HTTP_LUA_FFI_NO_REQ_CTX;
    }

    if (r->connection->fd == -1) {
        return NGX_HTTP_LUA_FFI_BAD_CONTEXT;
    }

    if (r->header_sent) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "attempt to "
                      "set ngx.header.HEADER after sending out "
                      "response headers");
        return NGX_DECLINED;
    }

    key.data = ngx_palloc(r->pool, key_len + 1);
    if (key.data == NULL) {
        goto nomem;
    }

    ngx_memcpy(key.data, key_data, key_len);
    key.data[key_len] = '\0';
    key.len = key_len;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->transform_underscores_in_resp_headers) {
        /* replace "_" with "-" */
        p = key.data;
        for (i = 0; i < key_len; i++) {
            if (p[i] == '_') {
                p[i] = '-';
            }
        }
    }

    if (!ctx->headers_set) {
        rc = ngx_http_lua_set_content_type(r);
        if (rc != NGX_OK) {
            *errmsg = "failed to set default content type";
            return NGX_ERROR;
        }

        ctx->headers_set = 1;
    }

    if (is_nil) {
        value.data = NULL;
        value.len = 0;

    } else if (mvals) {

        if (mvals_len == 0) {
            value.data = NULL;
            value.len = 0;

        } else {
            for (i = 0; i < mvals_len; i++) {
                dd("header value table index %d", (int) i);

                p = mvals[i].data;
                len = mvals[i].len;

                value.data = ngx_palloc(r->pool, len);
                if (value.data == NULL) {
                    goto nomem;
                }

                ngx_memcpy(value.data, p, len);
                value.len = len;

                rc = ngx_http_lua_set_output_header(r, key, value,
                                                    i == 0 /* override */);

                if (rc == NGX_ERROR) {
                    *errmsg = "failed to set header";
                    return NGX_ERROR;
                }
            }

            return NGX_OK;
        }

    } else {
        p = (u_char *) sval;
        value.data = ngx_palloc(r->pool, sval_len);
        if (value.data == NULL) {
            goto nomem;
        }

        ngx_memcpy(value.data, p, sval_len);
        value.len = sval_len;
    }

    dd("key: %.*s, value: %.*s",
       (int) key.len, key.data, (int) value.len, value.data);

    rc = ngx_http_lua_set_output_header(r, key, value, 1 /* override */);

    if (rc == NGX_ERROR) {
        *errmsg = "failed to set header";
        return NGX_ERROR;
    }

    return 0;

nomem:

    *errmsg = "no memory";
    return NGX_ERROR;
}
#endif /* NGX_HTTP_LUA_NO_FFI_API */


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
