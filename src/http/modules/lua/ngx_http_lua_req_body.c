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
}


static int
ngx_http_lua_ngx_req_read_body(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

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
        return luaL_error(L, "request context is null");
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua start to read buffered request body");

    rc = ngx_http_read_client_request_body(r, ngx_http_lua_req_body_post_read);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to read request body");
    }

    if (rc == NGX_AGAIN) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua read buffered request body requires I/O interruptions");

        ctx->waiting_more_body = 1;
        ctx->req_read_body_done = 0;

        return lua_yield(L, 0);
    }

    /* rc == NGX_OK */

    ctx->req_read_body_done = 0;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua has read buffered request body in a single run");

    return 0;
}


static void
ngx_http_lua_req_body_post_read(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua req body post read");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    ctx->req_read_body_done = 1;

#if defined(nginx_version) && nginx_version >= 8011
    r->main->count--;
#endif

    if (ctx->waiting_more_body) {
        ctx->waiting_more_body = 0;

        if (ctx->entered_content_phase) {
            ngx_http_lua_wev_handler(r);

        } else {
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

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

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

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

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

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

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
            (int) ngx_buf_size(r->request_body->bufs->buf)
            );

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

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r->request_body == NULL) {

#if 1
        rc = ngx_http_discard_request_body(r);
        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return luaL_error(L, "failed to discard request body");
        }
#endif

        rb = ngx_pcalloc(r->pool, sizeof(ngx_http_request_body_t));
        if (rb == NULL) {
            return luaL_error(L, "out of memory");
        }

        r->request_body = rb;

    } else {
        rb = r->request_body;
    }

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
            return luaL_error(L, "out of memory");
        }
        b->end = b->start + body.len;

        b->pos = b->start;
        b->last = ngx_copy(b->pos, body.data, body.len);

    } else {

        rb->bufs = ngx_alloc_chain_link(r->pool);
        if (rb->bufs == NULL) {
            return luaL_error(L, "out of memory");
        }
        rb->bufs->next = NULL;

        b = ngx_create_temp_buf(r->pool, body.len);
        b->tag = tag;
        b->last = ngx_copy(b->pos, body.data, body.len);

        rb->bufs->buf = b;
        rb->buf = b;
    }

set_header:

    /* override input header Content-Length (value must be null terminated) */

    value.data = ngx_palloc(r->pool, NGX_SIZE_T_LEN + 1);
    if (value.data == NULL) {
        return luaL_error(L, "out of memory");
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

    name.data = (u_char *) luaL_checklstring(L, 1, &name.len);

    if (n == 2) {
        luaL_checktype(L, 2, LUA_TBOOLEAN);
        clean = lua_toboolean(L, 2);

    } else {
        clean = 0;
    }

    dd("clean: %d", (int) clean);

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r->request_body == NULL) {

#if 1
        rc = ngx_http_discard_request_body(r);
        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return luaL_error(L, "failed to discard request body");
        }
#endif

        rb = ngx_pcalloc(r->pool, sizeof(ngx_http_request_body_t));
        if (rb == NULL) {
            return luaL_error(L, "out of memory");
        }

        r->request_body = rb;

    } else {
        rb = r->request_body;
    }

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

    } else {

        dd("XXX creating new buf");

        rb->bufs = ngx_alloc_chain_link(r->pool);
        if (rb->bufs == NULL) {
            return luaL_error(L, "out of memory");
        }
        rb->bufs->next = NULL;

        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            return luaL_error(L, "out of memory");
        }

        b->tag = tag;

        rb->bufs->buf = b;
        rb->buf = b;
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
            return luaL_error(L, "out of memory");
        }

        tf->file.fd = NGX_INVALID_FILE;
        rb->temp_file = tf;
    }

    /* read the file info and construct an in-file buf */

    ngx_memzero(&of, sizeof(ngx_open_file_info_t));

    if (ngx_http_lua_open_and_stat_file(name.data, &of, r->connection->log)
        != NGX_OK)
    {
        return luaL_error(L, "%s \"%s\" failed", of.failed, name.data);
    }

    dd("XXX new body file fd: %d", of.fd);

    tf->file.fd = of.fd;
    tf->file.name = name;
    tf->file.log = r->connection->log;

    /* FIXME we should not always set directio here */
    tf->file.directio = 1;

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
        return luaL_error(L, "out of memory");
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
        return luaL_error(L, "out of memory");
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

