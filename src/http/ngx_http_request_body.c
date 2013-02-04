/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


static void ngx_http_read_client_request_body_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_do_read_client_request_body(ngx_http_request_t *r);
static ngx_int_t ngx_http_write_request_body(ngx_http_request_t *r,
    ngx_chain_t *body);
static ngx_int_t ngx_http_read_discarded_request_body(ngx_http_request_t *r);
static ngx_int_t ngx_http_test_expect(ngx_http_request_t *r);


/*
 * on completion ngx_http_read_client_request_body() adds to
 * r->request_body->bufs one or two bufs:
 *    *) one memory buf that was preread in r->header_in;
 *    *) one memory or file buf that contains the rest of the body
 */

ngx_int_t
ngx_http_read_client_request_body(ngx_http_request_t *r,
    ngx_http_client_body_handler_pt post_handler)
{
    size_t                     preread;
    ssize_t                    size;
    ngx_buf_t                 *b, buf;
    ngx_int_t                  rc;
    ngx_chain_t               *cl, **next;
    ngx_http_request_body_t   *rb;
    ngx_http_core_loc_conf_t  *clcf;

    r->main->count++;

    if (r->request_body || r->discard_body) {
        post_handler(r);
        return NGX_OK;
    }

    if (ngx_http_test_expect(r) != NGX_OK) {
        rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
        goto done;
    }

    rb = ngx_pcalloc(r->pool, sizeof(ngx_http_request_body_t));
    if (rb == NULL) {
        rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
        goto done;
    }

    r->request_body = rb;

    if (r->headers_in.content_length_n < 0) {
        post_handler(r);
        return NGX_OK;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (r->headers_in.content_length_n == 0) {

        if (r->request_body_in_file_only) {
            if (ngx_http_write_request_body(r, NULL) != NGX_OK) {
                rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
                goto done;
            }
        }

        post_handler(r);

        return NGX_OK;
    }

    rb->post_handler = post_handler;

    /*
     * set by ngx_pcalloc():
     *
     *     rb->bufs = NULL;
     *     rb->buf = NULL;
     *     rb->rest = 0;
     */

    preread = r->header_in->last - r->header_in->pos;

    if (preread) {

        /* there is the pre-read part of the request body */

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "http client request body preread %uz", preread);

        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
            goto done;
        }

        b->temporary = 1;
        b->start = r->header_in->pos;
        b->pos = r->header_in->pos;
        b->last = r->header_in->last;
        b->end = r->header_in->end;

        ngx_memzero(&buf, sizeof(ngx_buf_t));
        buf.memory = 1;
        buf.start = r->header_in->pos;
        buf.pos = r->header_in->pos;
        buf.last = (off_t) preread >= r->headers_in.content_length_n
                 ? r->header_in->pos + (size_t) r->headers_in.content_length_n
                 : r->header_in->last;
        buf.end = r->header_in->end;

        rb->bufs = ngx_alloc_chain_link(r->pool);
        if (rb->bufs == NULL) {
            rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
            goto done;
        }

        rb->bufs->buf = b;
        rb->bufs->next = NULL;

        rb->buf = b;

        rc = ngx_http_top_input_body_filter(r, &buf);
        if (rc != NGX_OK) {
            if (rc > NGX_OK && rc < NGX_HTTP_SPECIAL_RESPONSE) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                              "input filter: return code 1xx or 2xx "
                              "will cause trouble and is converted to 500");
            }

            /**
             * NGX_OK: success and continue;
             * NGX_ERROR: failed and exit;
             * NGX_AGAIN: not ready and retry later.
             */

            if (rc < NGX_HTTP_SPECIAL_RESPONSE && rc != NGX_AGAIN) {
                rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            return rc;
        }

        if ((off_t) preread >= r->headers_in.content_length_n) {

            /* the whole request body was pre-read */

            r->header_in->pos += (size_t) r->headers_in.content_length_n;
            r->request_length += r->headers_in.content_length_n;
            b->last = r->header_in->pos;

            if (r->request_body_in_file_only) {
                if (ngx_http_write_request_body(r, rb->bufs) != NGX_OK) {
                    rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
                    goto done;
                }
            }

            post_handler(r);

            return NGX_OK;
        }

        /*
         * to not consider the body as pipelined request in
         * ngx_http_set_keepalive()
         */
        r->header_in->pos = r->header_in->last;

        r->request_length += preread;

        rb->rest = r->headers_in.content_length_n - preread;

        if (rb->rest <= (off_t) (b->end - b->last)) {

            /* the whole request body may be placed in r->header_in */

            rb->to_write = rb->bufs;

            r->read_event_handler = ngx_http_read_client_request_body_handler;

            rc = ngx_http_do_read_client_request_body(r);
            goto done;
        }

        next = &rb->bufs->next;

    } else {
        b = NULL;
        rb->rest = r->headers_in.content_length_n;
        next = &rb->bufs;
    }

    size = clcf->client_body_buffer_size;
    size += size >> 2;

    if (rb->rest < size) {
        size = (ssize_t) rb->rest;

        if (r->request_body_in_single_buf) {
            size += preread;
        }

    } else {
        size = clcf->client_body_buffer_size;

        /* disable copying buffer for r->request_body_in_single_buf */
        b = NULL;
    }

    rb->buf = ngx_create_temp_buf(r->pool, size);
    if (rb->buf == NULL) {
        rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
        goto done;
    }

    cl = ngx_alloc_chain_link(r->pool);
    if (cl == NULL) {
        rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
        goto done;
    }

    cl->buf = rb->buf;
    cl->next = NULL;

    if (b && r->request_body_in_single_buf) {
        size = b->last - b->pos;
        ngx_memcpy(rb->buf->pos, b->pos, size);
        rb->buf->last += size;

        next = &rb->bufs;
    }

    *next = cl;

    if (r->request_body_in_file_only || r->request_body_in_single_buf) {
        rb->to_write = rb->bufs;

    } else {
        rb->to_write = rb->bufs->next ? rb->bufs->next : rb->bufs;
    }

    r->read_event_handler = ngx_http_read_client_request_body_handler;

    rc = ngx_http_do_read_client_request_body(r);

done:

    if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        r->main->count--;
    }

    return rc;
}


static void
ngx_http_read_client_request_body_handler(ngx_http_request_t *r)
{
    ngx_int_t  rc;

    if (r->connection->read->timedout) {
        r->connection->timedout = 1;
        ngx_http_finalize_request(r, NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    rc = ngx_http_do_read_client_request_body(r);

    if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        ngx_http_finalize_request(r, rc);
    }
}


static ngx_int_t
ngx_http_do_read_client_request_body(ngx_http_request_t *r)
{
    size_t                     size;
    ssize_t                    n;
    ngx_buf_t                 *b, buf;
    ngx_int_t                  rc;
    ngx_connection_t          *c;
    ngx_http_request_body_t   *rb;
    ngx_http_core_loc_conf_t  *clcf;

    c = r->connection;
    rb = r->request_body;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http read client request body");

    for ( ;; ) {
        for ( ;; ) {
            if (rb->buf->last == rb->buf->end) {

                if (ngx_http_write_request_body(r, rb->to_write) != NGX_OK) {
                    return NGX_HTTP_INTERNAL_SERVER_ERROR;
                }

                rb->to_write = rb->bufs->next ? rb->bufs->next : rb->bufs;
                rb->buf->last = rb->buf->start;
            }

            size = rb->buf->end - rb->buf->last;

            if ((off_t) size > rb->rest) {
                size = (size_t) rb->rest;
            }

            n = c->recv(c, rb->buf->last, size);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "http client request body recv %z", n);

            if (n == NGX_AGAIN) {
                break;
            }

            if (n == 0) {
                ngx_log_error(NGX_LOG_INFO, c->log, 0,
                              "client prematurely closed connection");
            }

            if (n == 0 || n == NGX_ERROR) {
                c->error = 1;
                return NGX_HTTP_BAD_REQUEST;
            }

            ngx_memzero(&buf, sizeof(ngx_buf_t));
            buf.memory = 1;
            buf.start = rb->buf->last;
            buf.pos = rb->buf->last;
            buf.last = buf.start + n;
            buf.end = buf.last;

            rb->buf->last += n;
            rb->rest -= n;
            r->request_length += n;

            rc = ngx_http_top_input_body_filter(r, &buf);
            if (rc != NGX_OK) {
                if (rc > NGX_OK && rc < NGX_HTTP_SPECIAL_RESPONSE) {
                    ngx_log_error(NGX_LOG_ERR, c->log, 0,
                              "input filter: return code 1xx or 2xx "
                              "will cause trouble and is converted to 500");
                }

                if (rc < NGX_HTTP_SPECIAL_RESPONSE && rc != NGX_AGAIN) {
                    rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
                }

                return rc;
            }

            if (rb->rest == 0) {
                break;
            }

            if (rb->buf->last < rb->buf->end) {
                break;
            }
        }

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "http client request body rest %O", rb->rest);

        if (rb->rest == 0) {
            break;
        }

        if (!c->read->ready) {
            clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
            ngx_add_timer(c->read, clcf->client_body_timeout);

            if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
                return NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            return NGX_AGAIN;
        }
    }

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    if (rb->temp_file || r->request_body_in_file_only) {

        /* save the last part */

        if (ngx_http_write_request_body(r, rb->to_write) != NGX_OK) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
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

    if (rb->bufs->next
        && (r->request_body_in_file_only || r->request_body_in_single_buf))
    {
        rb->bufs = rb->bufs->next;
    }

    r->read_event_handler = ngx_http_block_reading;

    rb->post_handler(r);

    return NGX_OK;
}


static ngx_int_t
ngx_http_write_request_body(ngx_http_request_t *r, ngx_chain_t *body)
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
        tf->persistent = r->request_body_in_persistent_file;
        tf->clean = r->request_body_in_clean_file;

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


ngx_int_t
ngx_http_discard_request_body(ngx_http_request_t *r)
{
    ssize_t       size;
    ngx_event_t  *rev;

    if (r != r->main || r->discard_body) {
        return NGX_OK;
    }

    if (ngx_http_test_expect(r) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    rev = r->connection->read;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, rev->log, 0, "http set discard body");

    if (rev->timer_set) {
        ngx_del_timer(rev);
    }

    if (r->headers_in.content_length_n <= 0 || r->request_body) {
        return NGX_OK;
    }

    size = r->header_in->last - r->header_in->pos;

    if (size) {
        if (r->headers_in.content_length_n > size) {
            r->header_in->pos += size;
            r->headers_in.content_length_n -= size;

        } else {
            r->header_in->pos += (size_t) r->headers_in.content_length_n;
            r->headers_in.content_length_n = 0;
            return NGX_OK;
        }
    }

    if (ngx_http_read_discarded_request_body(r) == NGX_OK) {
        r->lingering_close = 0;
        return NGX_OK;
    }

    /* == NGX_AGAIN */

    r->read_event_handler = ngx_http_discarded_request_body_handler;

    if (ngx_handle_read_event(rev, 0) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    r->count++;
    r->discard_body = 1;

    return NGX_OK;
}


void
ngx_http_discarded_request_body_handler(ngx_http_request_t *r)
{
    ngx_int_t                  rc;
    ngx_msec_t                 timer;
    ngx_event_t               *rev;
    ngx_connection_t          *c;
    ngx_http_core_loc_conf_t  *clcf;

    c = r->connection;
    rev = c->read;

    if (rev->timedout) {
        c->timedout = 1;
        c->error = 1;
        ngx_http_finalize_request(r, NGX_ERROR);
        return;
    }

    if (r->lingering_time) {
        timer = (ngx_msec_t) (r->lingering_time - ngx_time());

        if (timer <= 0) {
            r->discard_body = 0;
            r->lingering_close = 0;
            ngx_http_finalize_request(r, NGX_ERROR);
            return;
        }

    } else {
        timer = 0;
    }

    rc = ngx_http_read_discarded_request_body(r);

    if (rc == NGX_OK) {
        r->discard_body = 0;
        r->lingering_close = 0;
        ngx_http_finalize_request(r, NGX_DONE);
        return;
    }

    /* rc == NGX_AGAIN */

    if (ngx_handle_read_event(rev, 0) != NGX_OK) {
        c->error = 1;
        ngx_http_finalize_request(r, NGX_ERROR);
        return;
    }

    if (timer) {

        clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

        timer *= 1000;

        if (timer > clcf->lingering_timeout) {
            timer = clcf->lingering_timeout;
        }

        ngx_add_timer(rev, timer);
    }
}


static ngx_int_t
ngx_http_read_discarded_request_body(ngx_http_request_t *r)
{
    size_t   size;
    ssize_t  n;
    u_char   buffer[NGX_HTTP_DISCARD_BUFFER_SIZE];

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http read discarded body");

    for ( ;; ) {
        if (r->headers_in.content_length_n == 0) {
            r->read_event_handler = ngx_http_block_reading;
            return NGX_OK;
        }

        if (!r->connection->read->ready) {
            return NGX_AGAIN;
        }

        size = (r->headers_in.content_length_n > NGX_HTTP_DISCARD_BUFFER_SIZE) ?
                   NGX_HTTP_DISCARD_BUFFER_SIZE:
                   (size_t) r->headers_in.content_length_n;

        n = r->connection->recv(r->connection, buffer, size);

        if (n == NGX_ERROR) {
            r->connection->error = 1;
            return NGX_OK;
        }

        if (n == NGX_AGAIN) {
            return NGX_AGAIN;
        }

        if (n == 0) {
            return NGX_OK;
        }

        r->headers_in.content_length_n -= n;
    }
}


static ngx_int_t
ngx_http_test_expect(ngx_http_request_t *r)
{
    ngx_int_t   n;
    ngx_str_t  *expect;

    if (r->expect_tested
        || r->headers_in.expect == NULL
        || r->http_version < NGX_HTTP_VERSION_11)
    {
        return NGX_OK;
    }

    r->expect_tested = 1;

    expect = &r->headers_in.expect->value;

    if (expect->len != sizeof("100-continue") - 1
        || ngx_strncasecmp(expect->data, (u_char *) "100-continue",
                           sizeof("100-continue") - 1)
           != 0)
    {
        return NGX_OK;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "send 100 Continue");

    n = r->connection->send(r->connection,
                            (u_char *) "HTTP/1.1 100 Continue" CRLF CRLF,
                            sizeof("HTTP/1.1 100 Continue" CRLF CRLF) - 1);

    if (n == sizeof("HTTP/1.1 100 Continue" CRLF CRLF) - 1) {
        return NGX_OK;
    }

    /* we assume that such small packet should be send successfully */

    return NGX_ERROR;
}
