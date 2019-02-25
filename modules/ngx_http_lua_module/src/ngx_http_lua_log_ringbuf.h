
#ifndef _NGX_HTTP_LUA_RINGBUF_H_INCLUDED_
#define _NGX_HTTP_LUA_RINGBUF_H_INCLUDED_


#include "ngx_http_lua_common.h"


typedef struct {
    ngx_uint_t   filter_level;
    char        *tail;              /* writed point */
    char        *head;              /* readed point */
    char        *data;              /* buffer */
    char        *sentinel;
    size_t       size;              /* buffer total size */
    size_t       count;             /* count of logs */
} ngx_http_lua_log_ringbuf_t;


void ngx_http_lua_log_ringbuf_init(ngx_http_lua_log_ringbuf_t *rb,
    void *buf, size_t len);
void ngx_http_lua_log_ringbuf_reset(ngx_http_lua_log_ringbuf_t *rb);
ngx_int_t ngx_http_lua_log_ringbuf_read(ngx_http_lua_log_ringbuf_t *rb,
    int *log_level, void **buf, size_t *n, double *log_time);
ngx_int_t ngx_http_lua_log_ringbuf_write(ngx_http_lua_log_ringbuf_t *rb,
    int log_level, void *buf, size_t n);


#endif /* _NGX_HTTP_LUA_RINGBUF_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
