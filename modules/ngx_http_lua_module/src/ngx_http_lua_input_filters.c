
/*
 * Copyright (C) by OpenResty Inc.
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"


ngx_int_t
ngx_http_lua_read_bytes(ngx_buf_t *src, ngx_chain_t *buf_in, size_t *rest,
    ssize_t bytes, ngx_log_t *log)
{
    if (bytes == 0) {
        return NGX_ERROR;
    }

    if ((size_t) bytes >= *rest) {

        buf_in->buf->last += *rest;
        src->pos += *rest;
        *rest = 0;

        return NGX_OK;
    }

    /* bytes < *rest */

    buf_in->buf->last += bytes;
    src->pos += bytes;
    *rest -= bytes;

    return NGX_AGAIN;
}


ngx_int_t
ngx_http_lua_read_all(ngx_buf_t *src, ngx_chain_t *buf_in, ssize_t bytes,
    ngx_log_t *log)
{
    if (bytes == 0) {
        return NGX_OK;
    }

    buf_in->buf->last += bytes;
    src->pos += bytes;

    return NGX_AGAIN;
}


ngx_int_t
ngx_http_lua_read_any(ngx_buf_t *src, ngx_chain_t *buf_in, size_t *max,
    ssize_t bytes, ngx_log_t *log)
{
    if (bytes == 0) {
        return NGX_ERROR;
    }

    if (bytes >= (ssize_t) *max) {
        bytes = (ssize_t) *max;
    }

    buf_in->buf->last += bytes;
    src->pos += bytes;

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_read_line(ngx_buf_t *src, ngx_chain_t *buf_in, ssize_t bytes,
    ngx_log_t *log)
{
    u_char                      *dst;
    u_char                       c;
#if (NGX_DEBUG)
    u_char                      *begin;
#endif

#if (NGX_DEBUG)
    begin = src->pos;
#endif

    if (bytes == 0) {
        return NGX_ERROR;
    }

    dd("already read: %p: %.*s", buf_in,
       (int) (buf_in->buf->last - buf_in->buf->pos), buf_in->buf->pos);

    dd("data read: %.*s", (int) bytes, src->pos);

    dst = buf_in->buf->last;

    while (bytes--) {

        c = *src->pos++;

        switch (c) {
        case '\n':
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                           "lua read the final line part: \"%*s\"",
                           src->pos - 1 - begin, begin);

            buf_in->buf->last = dst;

            dd("read a line: %p: %.*s", buf_in,
               (int) (buf_in->buf->last - buf_in->buf->pos), buf_in->buf->pos);

            return NGX_OK;

        case '\r':
            /* ignore it */
            break;

        default:
            *dst++ = c;
            break;
        }
    }

#if (NGX_DEBUG)
    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "lua read partial line data: %*s", dst - begin, begin);
#endif

    buf_in->buf->last = dst;

    return NGX_AGAIN;
}
