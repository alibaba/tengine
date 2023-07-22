
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_req_body.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_headers_in.h"


static int ngx_http_lua_ngx_req_read_body(lua_State *L);
static void ngx_http_lua_req_body_post_read(ngx_http_request_t *r);
static int ngx_http_lua_ngx_req_discard_body(lua_State *L);
static int ngx_http_lua_ngx_req_get_body_data(lua_State *L);
static int ngx_http_lua_ngx_req_get_body_file(lua_State *L);
static int ngx_http_lua_ngx_req_set_body_data(lua_State *L);
static void ngx_http_lua_pool_cleanup_file(ngx_pool_t *p, ngx_fd_t fd);
static int ngx_http_lua_ngx_req_set_body_file(lua_State *L);

static int ngx_http_lua_ngx_req_init_body(lua_State *L);
static int ngx_http_lua_ngx_req_append_body(lua_State *L);
static int ngx_http_lua_ngx_req_body_finish(lua_State *L);
static ngx_int_t ngx_http_lua_write_request_body(ngx_http_request_t *r,
    ngx_chain_t *body);
static ngx_int_t ngx_http_lua_read_body_resume(ngx_http_request_t *r);
static void ngx_http_lua_req_body_cleanup(void *data);



void
ngx_http_lua_inject_req_body_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_read_body);
    lua_setfield(L, -2, "read_body");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_discard_body);
    lua_setfield(L, -2, "discard_body");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_body_data);
    lua_setfield(L, -2, "get_body_data");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_body_file);
    lua_setfield(L, -2, "get_body_file");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_body_data);
    lua_setfield(L, -2, "set_body_data");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_body_file);
    lua_setfield(L, -2, "set_body_file");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_init_body);
    lua_setfield(L, -2, "init_body");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_append_body);
    lua_setfield(L, -2, "append_body");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_body_finish);
    lua_setfield(L, -2, "finish_body");
}


static int
ngx_http_lua_ngx_req_read_body(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    ngx_int_t                    rc;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    r->request_body_in_single_buf = 1;
    r->request_body_in_persistent_file = 1;
    r->request_body_in_clean_file = 1;

#if 1
    if (r->request_body_in_file_only) {
        r->request_body_file_log_level = 0;
    }
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_SERVER_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    coctx = ctx->cur_co_ctx;
    if (coctx == NULL) {
        return luaL_error(L, "no co ctx found");
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua start to read buffered request body");

    rc = ngx_http_read_client_request_body(r, ngx_http_lua_req_body_post_read);

    if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        ctx->exit_code = rc;
        ctx->exited = 1;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "http read client request body returned error code %i, "
                       "exitting now", rc);

        return lua_yield(L, 0);
    }

    r->main->count--;
    dd("decrement r->main->count: %d", (int) r->main->count);

    if (rc == NGX_AGAIN) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua read buffered request body requires I/O "
                       "interruptions");

        ctx->waiting_more_body = 1;
        ctx->downstream = coctx;

        ngx_http_lua_cleanup_pending_operation(coctx);
        coctx->cleanup = ngx_http_lua_req_body_cleanup;
        coctx->data = r;

        return lua_yield(L, 0);
    }

    /* rc == NGX_OK */

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua has read buffered request body in a single run");

    return 0;
}


static void
ngx_http_lua_req_body_post_read(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_lua_co_ctx_t   *coctx;

    ngx_http_lua_loc_conf_t             *llcf;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua req body post read, c:%ud", r->main->count);

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx->waiting_more_body) {
        ctx->waiting_more_body = 0;

        coctx = ctx->downstream;
        ctx->cur_co_ctx = coctx;

        coctx->cleanup = NULL;

        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

        if (llcf->check_client_abort) {
            r->read_event_handler = ngx_http_lua_rd_check_broken_connection;

        } else {
            r->read_event_handler = ngx_http_block_reading;
        }

        if (ctx->entered_content_phase) {
            (void) ngx_http_lua_read_body_resume(r);

        } else {
            ctx->resume_handler = ngx_http_lua_read_body_resume;
            ngx_http_core_run_phases(r);
        }
    }
}


static int
ngx_http_lua_ngx_req_discard_body(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_int_t                    rc;
    int                          n;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    ngx_http_lua_check_fake_request(L, r);

    rc = ngx_http_discard_request_body(r);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to discard request body");
    }

    return 0;
}


static int
ngx_http_lua_ngx_req_get_body_data(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    size_t                       len;
    ngx_chain_t                 *cl;
    u_char                      *p;
    u_char                      *buf;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->request_body == NULL
        || r->request_body->temp_file
        || r->request_body->bufs == NULL)
    {
        lua_pushnil(L);
        return 1;
    }

    cl = r->request_body->bufs;

    if (cl->next == NULL) {
        len = cl->buf->last - cl->buf->pos;

        if (len == 0) {
            lua_pushnil(L);
            return 1;
        }

        lua_pushlstring(L, (char *) cl->buf->pos, len);
        return 1;
    }

    /* found multi-buffer body */

    len = 0;

    for (; cl; cl = cl->next) {
        dd("body chunk len: %d", (int) ngx_buf_size(cl->buf));
        len += cl->buf->last - cl->buf->pos;
    }

    if (len == 0) {
        lua_pushnil(L);
        return 1;
    }

    buf = (u_char *) lua_newuserdata(L, len);

    p = buf;
    for (cl = r->request_body->bufs; cl; cl = cl->next) {
        p = ngx_copy(p, cl->buf->pos, cl->buf->last - cl->buf->pos);
    }

    lua_pushlstring(L, (char *) buf, len);
    return 1;
}


static int
ngx_http_lua_ngx_req_get_body_file(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->request_body == NULL || r->request_body->temp_file == NULL) {
        lua_pushnil(L);
        return 1;
    }

    dd("XXX file directio: %u, f:%u, m:%u, t:%u, end - pos %d, size %d",
       r->request_body->temp_file->file.directio,
       r->request_body->bufs->buf->in_file,
       r->request_body->bufs->buf->memory,
       r->request_body->bufs->buf->temporary,
       (int) (r->request_body->bufs->buf->end -
              r->request_body->bufs->buf->pos),
       (int) ngx_buf_size(r->request_body->bufs->buf));

    lua_pushlstring(L, (char *) r->request_body->temp_file->file.name.data,
                    r->request_body->temp_file->file.name.len);
    return 1;
}


static int
ngx_http_lua_ngx_req_set_body_data(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_request_body_t     *rb;
    ngx_temp_file_t             *tf;
    ngx_buf_t                   *b;
    ngx_str_t                    body, key, value;
#if 1
    ngx_int_t                    rc;
#endif
    ngx_chain_t                 *cl;
    ngx_buf_tag_t                tag;

    n = lua_gettop(L);

    if (n != 1) {
        return luaL_error(L, "expecting 1 arguments but seen %d", n);
    }

    body.data = (u_char *) luaL_checklstring(L, 1, &body.len);

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->discard_body) {
        return luaL_error(L, "request body already discarded asynchronously");
    }

    if (r->request_body == NULL) {
        return luaL_error(L, "request body not read yet");
    }

    rb = r->request_body;

    tag = (ngx_buf_tag_t) &ngx_http_lua_module;

    tf = rb->temp_file;

    if (tf) {
        if (tf->file.fd != NGX_INVALID_FILE) {

            dd("cleaning temp file %.*s", (int) tf->file.name.len,
               tf->file.name.data);

            ngx_http_lua_pool_cleanup_file(r->pool, tf->file.fd);
            tf->file.fd = NGX_INVALID_FILE;

            dd("temp file cleaned: %.*s", (int) tf->file.name.len,
               tf->file.name.data);
        }

        rb->temp_file = NULL;
    }

    if (body.len == 0) {

        if (rb->bufs) {

            for (cl = rb->bufs; cl; cl = cl->next) {
                if (cl->buf->tag == tag && cl->buf->temporary) {

                    dd("free old request body buffer: size:%d",
                       (int) ngx_buf_size(cl->buf));

                    ngx_pfree(r->pool, cl->buf->start);
                    cl->buf->tag = (ngx_buf_tag_t) NULL;
                    cl->buf->temporary = 0;
                }
            }
        }

        rb->bufs = NULL;
        rb->buf = NULL;

        dd("request body is set to empty string");
        goto set_header;
    }

    if (rb->bufs) {

        for (cl = rb->bufs; cl; cl = cl->next) {
            if (cl->buf->tag == tag && cl->buf->temporary) {
                dd("free old request body buffer: size:%d",
                   (int) ngx_buf_size(cl->buf));

                ngx_pfree(r->pool, cl->buf->start);
                cl->buf->tag = (ngx_buf_tag_t) NULL;
                cl->buf->temporary = 0;
            }
        }

        rb->bufs->next = NULL;

        b = rb->bufs->buf;

        ngx_memzero(b, sizeof(ngx_buf_t));

        b->temporary = 1;
        b->tag = tag;

        b->start = ngx_palloc(r->pool, body.len);
        if (b->start == NULL) {
            return luaL_error(L, "no memory");
        }

        b->end = b->start + body.len;

        b->pos = b->start;
        b->last = ngx_copy(b->pos, body.data, body.len);

    } else {

        rb->bufs = ngx_alloc_chain_link(r->pool);
        if (rb->bufs == NULL) {
            return luaL_error(L, "no memory");
        }

        rb->bufs->next = NULL;

        b = ngx_create_temp_buf(r->pool, body.len);
        if (b == NULL) {
            return luaL_error(L, "no memory");
        }

        b->tag = tag;
        b->last = ngx_copy(b->pos, body.data, body.len);

        rb->bufs->buf = b;
        rb->buf = b;
    }

set_header:

    /* override input header Content-Length (value must be null terminated) */

    value.data = ngx_palloc(r->pool, NGX_SIZE_T_LEN + 1);
    if (value.data == NULL) {
        return luaL_error(L, "no memory");
    }

    value.len = ngx_sprintf(value.data, "%uz", body.len) - value.data;
    value.data[value.len] = '\0';

    dd("setting request Content-Length to %.*s (%d)",
       (int) value.len, value.data, (int) body.len);

    r->headers_in.content_length_n = body.len;

    if (r->headers_in.content_length) {
        r->headers_in.content_length->value.data = value.data;
        r->headers_in.content_length->value.len = value.len;

    } else {

        ngx_str_set(&key, "Content-Length");

        rc = ngx_http_lua_set_input_header(r, key, value, 1 /* override */);
        if (rc != NGX_OK) {
            return luaL_error(L, "failed to reset the Content-Length "
                              "input header");
        }
    }

    return 0;
}


static int
ngx_http_lua_ngx_req_init_body(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_request_body_t     *rb;
    size_t                       size;
    lua_Integer                  num;
#if 1
    ngx_temp_file_t             *tf;
#endif
    ngx_http_core_loc_conf_t    *clcf;

    n = lua_gettop(L);

    if (n != 1 && n != 0) {
        return luaL_error(L, "expecting 0 or 1 argument but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->discard_body) {
        return luaL_error(L, "request body already discarded asynchronously");
    }

    if (r->request_body == NULL) {
        return luaL_error(L, "request body not read yet");
    }

    if (n == 1) {
        num = luaL_checkinteger(L, 1);
        if (num < 0) {
            return luaL_error(L, "bad size argument: %d", (int) num);
        }

        size = (size_t) num;

    } else {

        clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
        size = clcf->client_body_buffer_size;
    }

    if (size == 0) {
        r->request_body_in_file_only = 1;
    }

    rb = r->request_body;

#if 1
    tf = rb->temp_file;

    if (tf) {
        if (tf->file.fd != NGX_INVALID_FILE) {

            dd("cleaning temp file %.*s", (int) tf->file.name.len,
               tf->file.name.data);

            ngx_http_lua_pool_cleanup_file(r->pool, tf->file.fd);

            ngx_memzero(tf, sizeof(ngx_temp_file_t));

            tf->file.fd = NGX_INVALID_FILE;

            dd("temp file cleaned: %.*s", (int) tf->file.name.len,
               tf->file.name.data);
        }

        rb->temp_file = NULL;
    }
#endif

    r->request_body_in_clean_file = 1;

    r->headers_in.content_length_n = 0;

    rb->buf = ngx_create_temp_buf(r->pool, size);
    if (rb->buf == NULL) {
        return luaL_error(L, "no memory");
    }

    rb->bufs = ngx_alloc_chain_link(r->pool);
    if (rb->bufs == NULL) {
        return luaL_error(L, "no memory");
    }

    rb->bufs->buf = rb->buf;
    rb->bufs->next = NULL;

    return 0;
}


static int
ngx_http_lua_ngx_req_append_body(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_request_body_t     *rb;
    ngx_str_t                    body;
    size_t                       size, rest;
    size_t                       offset = 0;
    ngx_chain_t                  chain;
    ngx_buf_t                    buf;

    n = lua_gettop(L);

    if (n != 1) {
        return luaL_error(L, "expecting 1 arguments but seen %d", n);
    }

    body.data = (u_char *) luaL_checklstring(L, 1, &body.len);

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->request_body == NULL
        || r->request_body->buf == NULL
        || r->request_body->bufs == NULL)
    {
        return luaL_error(L, "request_body not initialized");
    }

    if (r->request_body_in_file_only) {
        buf.start = body.data;
        buf.pos = buf.start;
        buf.last = buf.start + body.len;
        buf.end = buf.last;
        buf.temporary = 1;

        chain.buf = &buf;
        chain.next = NULL;

        if (ngx_http_lua_write_request_body(r, &chain) != NGX_OK) {
            return luaL_error(L, "fail to write file");
        }

        r->headers_in.content_length_n += body.len;
        return 0;
    }

    rb = r->request_body;

    rest = body.len;

    while (rest > 0) {
        if (rb->buf->last == rb->buf->end) {
            if (ngx_http_lua_write_request_body(r, rb->bufs) != NGX_OK) {
                return luaL_error(L, "fail to write file");
            }

            rb->buf->last = rb->buf->start;
        }

        size = rb->buf->end - rb->buf->last;

        if (size > rest) {
            size = rest;
        }

        ngx_memcpy(rb->buf->last, body.data + offset, size);

        rb->buf->last += size;
        rest -= size;
        offset += size;
        r->headers_in.content_length_n += size;
    }

    return 0;
}


static int
ngx_http_lua_ngx_req_body_finish(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_request_body_t     *rb;
    ngx_buf_t                   *b;
    size_t                       size;
    ngx_str_t                    value;
    ngx_str_t                    key;
    ngx_int_t                    rc;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 argument but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->request_body == NULL
        || r->request_body->buf == NULL
        || r->request_body->bufs == NULL)
    {
        return luaL_error(L, "request_body not initialized");
    }

    rb = r->request_body;

    if (rb->temp_file) {

        /* save the last part */

        if (ngx_http_lua_write_request_body(r, rb->bufs) != NGX_OK) {
            return luaL_error(L, "fail to write file");
        }

        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            return luaL_error(L, "no memory");
        }

        b->in_file = 1;
        b->file_pos = 0;
        b->file_last = rb->temp_file->file.offset;
        b->file = &rb->temp_file->file;

        if (rb->bufs->next) {
            rb->bufs->next->buf = b;

        } else {
            rb->bufs->buf = b;
        }
    }

    /* override input header Content-Length (value must be null terminated) */

    value.data = ngx_palloc(r->pool, NGX_SIZE_T_LEN + 1);
    if (value.data == NULL) {
        return luaL_error(L, "no memory");
    }

    size = (size_t) r->headers_in.content_length_n;

    value.len = ngx_sprintf(value.data, "%uz", size) - value.data;
    value.data[value.len] = '\0';

    dd("setting request Content-Length to %.*s (%d)", (int) value.len,
       value.data, (int) size);

    if (r->headers_in.content_length) {
        r->headers_in.content_length->value.data = value.data;
        r->headers_in.content_length->value.len = value.len;

    } else {

        ngx_str_set(&key, "Content-Length");

        rc = ngx_http_lua_set_input_header(r, key, value, 1 /* override */);
        if (rc != NGX_OK) {
            return luaL_error(L, "failed to reset the Content-Length "
                              "input header");
        }
    }

    return 0;

}


static void
ngx_http_lua_pool_cleanup_file(ngx_pool_t *p, ngx_fd_t fd)
{
    ngx_pool_cleanup_t       *c;
    ngx_pool_cleanup_file_t  *cf;

    for (c = p->cleanup; c; c = c->next) {
        if (c->handler == ngx_pool_cleanup_file
            || c->handler == ngx_pool_delete_file)
        {
            cf = c->data;

            if (cf->fd == fd) {
                c->handler(cf);
                c->handler = NULL;
                return;
            }
        }
    }
}


static int
ngx_http_lua_ngx_req_set_body_file(lua_State *L)
{
    u_char                      *p;
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_request_body_t     *rb;
    ngx_temp_file_t             *tf;
    ngx_buf_t                   *b;
    ngx_str_t                    name;
    ngx_int_t                    rc;
    int                          clean;
    ngx_open_file_info_t         of;
    ngx_str_t                    key, value;
    ngx_pool_cleanup_t          *cln;
    ngx_pool_cleanup_file_t     *clnf;
    ngx_err_t                    err;
    ngx_chain_t                 *cl;
    ngx_buf_tag_t                tag;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 arguments but seen %d", n);
    }

    p = (u_char *) luaL_checklstring(L, 1, &name.len);

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if (r->discard_body) {
        return luaL_error(L, "request body already discarded asynchronously");
    }

    if (r->request_body == NULL) {
        return luaL_error(L, "request body not read yet");
    }

    name.data = ngx_palloc(r->pool, name.len + 1);
    if (name.data == NULL) {
        return luaL_error(L, "no memory");
    }

    ngx_memcpy(name.data, p, name.len);
    name.data[name.len] = '\0';

    if (n == 2) {
        luaL_checktype(L, 2, LUA_TBOOLEAN);
        clean = lua_toboolean(L, 2);

    } else {
        clean = 0;
    }

    dd("clean: %d", (int) clean);

    rb = r->request_body;

    /* clean up existing r->request_body->bufs (if any) */

    tag = (ngx_buf_tag_t) &ngx_http_lua_module;

    if (rb->bufs) {
        dd("XXX reusing buf");

        for (cl = rb->bufs; cl; cl = cl->next) {
            if (cl->buf->tag == tag && cl->buf->temporary) {
                dd("free old request body buffer: size:%d",
                   (int) ngx_buf_size(cl->buf));

                ngx_pfree(r->pool, cl->buf->start);
                cl->buf->tag = (ngx_buf_tag_t) NULL;
                cl->buf->temporary = 0;
            }
        }

        rb->bufs->next = NULL;
        b = rb->bufs->buf;

        ngx_memzero(b, sizeof(ngx_buf_t));

        b->tag = tag;
        rb->buf = NULL;

    } else {

        dd("XXX creating new buf");

        rb->bufs = ngx_alloc_chain_link(r->pool);
        if (rb->bufs == NULL) {
            return luaL_error(L, "no memory");
        }

        rb->bufs->next = NULL;

        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            return luaL_error(L, "no memory");
        }

        b->tag = tag;

        rb->bufs->buf = b;
        rb->buf = NULL;
    }

    b->last_in_chain = 1;

    /* just make r->request_body->temp_file a bare stub */

    tf = rb->temp_file;

    if (tf) {
        if (tf->file.fd != NGX_INVALID_FILE) {

            dd("cleaning temp file %.*s", (int) tf->file.name.len,
               tf->file.name.data);

            ngx_http_lua_pool_cleanup_file(r->pool, tf->file.fd);

            ngx_memzero(tf, sizeof(ngx_temp_file_t));

            tf->file.fd = NGX_INVALID_FILE;

            dd("temp file cleaned: %.*s", (int) tf->file.name.len,
               tf->file.name.data);
        }

    } else {

        tf = ngx_pcalloc(r->pool, sizeof(ngx_temp_file_t));
        if (tf == NULL) {
            return luaL_error(L, "no memory");
        }

        tf->file.fd = NGX_INVALID_FILE;
        rb->temp_file = tf;
    }

    /* read the file info and construct an in-file buf */

    ngx_memzero(&of, sizeof(ngx_open_file_info_t));

    of.directio = NGX_OPEN_FILE_DIRECTIO_OFF;

    if (ngx_http_lua_open_and_stat_file(name.data, &of, r->connection->log)
        != NGX_OK)
    {
        return luaL_error(L, "%s \"%s\" failed", of.failed, name.data);
    }

    dd("XXX new body file fd: %d", of.fd);

    tf->file.fd = of.fd;
    tf->file.name = name;
    tf->file.log = r->connection->log;
    tf->file.directio = 0;

    if (of.size == 0) {
        if (clean) {
            if (ngx_delete_file(name.data) == NGX_FILE_ERROR) {
                err = ngx_errno;

                if (err != NGX_ENOENT) {
                    ngx_log_error(NGX_LOG_CRIT, r->connection->log, err,
                                  ngx_delete_file_n " \"%s\" failed",
                                  name.data);
                }
            }
        }

        if (ngx_close_file(of.fd) == NGX_FILE_ERROR) {
            ngx_log_error(NGX_LOG_ALERT, r->connection->log, ngx_errno,
                          ngx_close_file_n " \"%s\" failed", name.data);
        }

        r->request_body->bufs = NULL;
        r->request_body->buf = NULL;

        goto set_header;
    }

    /* register file cleanup hook */

    cln = ngx_pool_cleanup_add(r->pool,
                               sizeof(ngx_pool_cleanup_file_t));

    if (cln == NULL) {
        return luaL_error(L, "no memory");
    }

    cln->handler = clean ? ngx_pool_delete_file : ngx_pool_cleanup_file;
    clnf = cln->data;

    clnf->fd = of.fd;
    clnf->name = name.data;
    clnf->log = r->pool->log;

    b->file = &tf->file;
    if (b->file == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    dd("XXX file size: %d", (int) of.size);

    b->file_pos = 0;
    b->file_last = of.size;

    b->in_file = 1;

    dd("buf file: %p, f:%u", b->file, b->in_file);

set_header:

    /* override input header Content-Length (value must be null terminated) */

    value.data = ngx_palloc(r->pool, NGX_OFF_T_LEN + 1);
    if (value.data == NULL) {
        return luaL_error(L, "no memory");
    }

    value.len = ngx_sprintf(value.data, "%O", of.size) - value.data;
    value.data[value.len] = '\0';

    r->headers_in.content_length_n = of.size;

    if (r->headers_in.content_length) {
        r->headers_in.content_length->value.data = value.data;
        r->headers_in.content_length->value.len = value.len;

    } else {

        ngx_str_set(&key, "Content-Length");

        rc = ngx_http_lua_set_input_header(r, key, value, 1 /* override */);
        if (rc != NGX_OK) {
            return luaL_error(L, "failed to reset the Content-Length "
                              "input header");
        }
    }

    return 0;
}


static ngx_int_t
ngx_http_lua_write_request_body(ngx_http_request_t *r, ngx_chain_t *body)
{
    ssize_t                    n;
    ngx_temp_file_t           *tf;
    ngx_http_request_body_t   *rb;
    ngx_http_core_loc_conf_t  *clcf;

    rb = r->request_body;

    if (rb->temp_file == NULL) {
        tf = ngx_pcalloc(r->pool, sizeof(ngx_temp_file_t));
        if (tf == NULL) {
            return NGX_ERROR;
        }

        clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

        tf->file.fd = NGX_INVALID_FILE;
        tf->file.log = r->connection->log;
        tf->path = clcf->client_body_temp_path;
        tf->pool = r->pool;
        tf->warn = "a client request body is buffered to a temporary file";
        tf->log_level = r->request_body_file_log_level;
        tf->persistent = 1;
        tf->clean = 1;

        if (r->request_body_file_group_access) {
            tf->access = 0660;
        }

        rb->temp_file = tf;

        if (body == NULL) {
            /* empty body with r->request_body_in_file_only */

            if (ngx_create_temp_file(&tf->file, tf->path, tf->pool,
                                     tf->persistent, tf->clean, tf->access)
                != NGX_OK)
            {
                return NGX_ERROR;
            }

            return NGX_OK;
        }
    }

    n = ngx_write_chain_to_temp_file(rb->temp_file, body);

    /* TODO: n == 0 or not complete and level event */

    if (n == NGX_ERROR) {
        return NGX_ERROR;
    }

    rb->temp_file->offset += n;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_read_body_resume(ngx_http_request_t *r)
{
    lua_State                   *vm;
    ngx_int_t                    rc;
    ngx_uint_t                   nreqs;
    ngx_connection_t            *c;
    ngx_http_lua_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    ctx->resume_handler = ngx_http_lua_wev_handler;

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(vm, r, ctx, 0);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static void
ngx_http_lua_req_body_cleanup(void *data)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_ctx_t                  *ctx;
    ngx_http_lua_co_ctx_t               *coctx = data;

    r = coctx->data;
    if (r == NULL) {
        return;
    }

    if (r->connection->read->timer_set) {
        ngx_del_timer(r->connection->read);
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return;
    }

    ctx->waiting_more_body = 0;
    r->keepalive = 0;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
