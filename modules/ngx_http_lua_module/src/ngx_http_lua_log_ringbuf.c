
#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"
#include "ngx_http_lua_log_ringbuf.h"


typedef struct {
    double      time;
    unsigned    len;
    unsigned    log_level;
} ngx_http_lua_log_ringbuf_header_t;


enum {
    HEADER_LEN = sizeof(ngx_http_lua_log_ringbuf_header_t)
};


static void *ngx_http_lua_log_ringbuf_next_header(
    ngx_http_lua_log_ringbuf_t *rb);
static void ngx_http_lua_log_ringbuf_append(
    ngx_http_lua_log_ringbuf_t *rb, int log_level, void *buf, int n);
static size_t ngx_http_lua_log_ringbuf_free_spaces(
    ngx_http_lua_log_ringbuf_t *rb);


void
ngx_http_lua_log_ringbuf_init(ngx_http_lua_log_ringbuf_t *rb, void *buf,
    size_t len)
{
    rb->data = buf;
    rb->size = len;

    rb->tail = rb->data;
    rb->head = rb->data;
    rb->sentinel = rb->data + rb->size;
    rb->count = 0;
    rb->filter_level = NGX_LOG_DEBUG;

    return;
}


void
ngx_http_lua_log_ringbuf_reset(ngx_http_lua_log_ringbuf_t *rb)
{
    rb->tail = rb->data;
    rb->head = rb->data;
    rb->sentinel = rb->data + rb->size;
    rb->count = 0;

    return;
}


/*
 * get the next data header, it'll skip the useless data space or
 * placehold data
 */
static void *
ngx_http_lua_log_ringbuf_next_header(ngx_http_lua_log_ringbuf_t *rb)
{
    /* useless data */
    if (rb->size - (rb->head - rb->data) < HEADER_LEN)
    {
        return rb->data;
    }

    /* placehold data */
    if (rb->head >= rb->sentinel) {
        return rb->data;
    }

    return rb->head;
}


/* append data to ring buffer directly */
static void
ngx_http_lua_log_ringbuf_append(ngx_http_lua_log_ringbuf_t *rb,
    int log_level, void *buf, int n)
{
    ngx_http_lua_log_ringbuf_header_t        *head;
    ngx_time_t                               *tp;

    head = (ngx_http_lua_log_ringbuf_header_t *) rb->tail;
    head->len = n;
    head->log_level = log_level;

    tp = ngx_timeofday();
    head->time = tp->sec + tp->msec / 1000.0L;

    rb->tail += HEADER_LEN;
    ngx_memcpy(rb->tail, buf, n);
    rb->tail += n;
    rb->count++;

    if (rb->tail > rb->sentinel) {
        rb->sentinel = rb->tail;
    }

    return;
}


/* throw away data at head */
static void
ngx_http_lua_log_ringbuf_throw_away(ngx_http_lua_log_ringbuf_t *rb)
{
    ngx_http_lua_log_ringbuf_header_t       *head;

    if (rb->count == 0) {
        return;
    }

    head = (ngx_http_lua_log_ringbuf_header_t *) rb->head;

    rb->head += HEADER_LEN + head->len;
    rb->count--;

    if (rb->count == 0) {
        ngx_http_lua_log_ringbuf_reset(rb);
    }

    rb->head = ngx_http_lua_log_ringbuf_next_header(rb);

    return;
}


/* size of free spaces */
static size_t
ngx_http_lua_log_ringbuf_free_spaces(ngx_http_lua_log_ringbuf_t *rb)
{
    if (rb->count == 0) {
        return rb->size;
    }

    if (rb->tail > rb->head) {
        return rb->data + rb->size - rb->tail;
    }

    return rb->head - rb->tail;
}


/*
 * try to write log data to ring buffer, throw away old data
 * if there was not enough free spaces.
 */
ngx_int_t
ngx_http_lua_log_ringbuf_write(ngx_http_lua_log_ringbuf_t *rb, int log_level,
    void *buf, size_t n)
{
    if (n + HEADER_LEN > rb->size) {
        return NGX_ERROR;
    }

    if (ngx_http_lua_log_ringbuf_free_spaces(rb) < n + HEADER_LEN) {
        /* if the right space is not enough, mark it as placehold data */
        if ((size_t)(rb->data + rb->size - rb->tail) < n + HEADER_LEN) {

            while (rb->head >= rb->tail && rb->count) {
                /* head is after tail, so we will throw away all data between
                 * head and sentinel */
                ngx_http_lua_log_ringbuf_throw_away(rb);
            }

            rb->sentinel = rb->tail;
            rb->tail = rb->data;
        }

        while (ngx_http_lua_log_ringbuf_free_spaces(rb) < n + HEADER_LEN) {
            ngx_http_lua_log_ringbuf_throw_away(rb);
        }
    }

    ngx_http_lua_log_ringbuf_append(rb, log_level, buf, n);

    return NGX_OK;
}


/* read log from ring buffer, do reset if all of the logs were readed. */
ngx_int_t
ngx_http_lua_log_ringbuf_read(ngx_http_lua_log_ringbuf_t *rb, int *log_level,
    void **buf, size_t *n, double *log_time)
{
    ngx_http_lua_log_ringbuf_header_t       *head;

    if (rb->count == 0) {
        return NGX_ERROR;
    }

    head = (ngx_http_lua_log_ringbuf_header_t *) rb->head;

    if (rb->head >= rb->sentinel) {
        return NGX_ERROR;
    }

    *log_level = head->log_level;
    *n = head->len;
    rb->head += HEADER_LEN;
    *buf = rb->head;
    rb->head += head->len;

    if (log_time) {
        *log_time = head->time;
    }

    rb->count--;

    if (rb->count == 0) {
        ngx_http_lua_log_ringbuf_reset(rb);
    }

    rb->head = ngx_http_lua_log_ringbuf_next_header(rb);

    return NGX_OK;
}
