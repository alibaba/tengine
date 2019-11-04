
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */

void
ngx_http_multi_upstream_send_response(ngx_http_request_t *r, ngx_http_upstream_t *u)
{
    int                        tcp_nodelay;
    ngx_int_t                  rc;
    ngx_connection_t          *c;
    ngx_http_core_loc_conf_t  *clcf;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http multi upstream send response: %p, %p", r, u);

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->post_action) {
        ngx_http_upstream_finalize_request(r, u, rc);
        return;
    }

    u->header_sent = 1;

    c = r->connection;

    if (r->header_only) {

        if (!u->buffering) {
            ngx_http_upstream_finalize_request(r, u, rc);
            return;
        }

        if (!u->cacheable && !u->store) {
            ngx_http_upstream_finalize_request(r, u, rc);
            return;
        }

        u->pipe->downstream_error = 1;
    }

    if (r->request_body && r->request_body->temp_file
            && !u->conf->preserve_output) {
        ngx_pool_run_cleanup_file(r->pool, r->request_body->temp_file->file.fd);
        r->request_body->temp_file->file.fd = NGX_INVALID_FILE;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (!u->buffering) {

        if (u->input_filter == NULL) {
            u->input_filter_init = ngx_http_upstream_non_buffered_filter_init;
            u->input_filter = ngx_http_upstream_non_buffered_filter;
            u->input_filter_ctx = r;
        }

        u->read_event_handler = ngx_http_upstream_process_non_buffered_upstream;
        r->write_event_handler =
                             ngx_http_upstream_process_non_buffered_downstream;

        r->limit_rate = 0;

        if (u->input_filter_init(u->input_filter_ctx) == NGX_ERROR) {
            ngx_http_upstream_finalize_request(r, u, NGX_ERROR);
            return;
        }

        if (clcf->tcp_nodelay && c->tcp_nodelay == NGX_TCP_NODELAY_UNSET) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "tcp_nodelay");

            tcp_nodelay = 1;

            if (setsockopt(c->fd, IPPROTO_TCP, TCP_NODELAY,
                               (const void *) &tcp_nodelay, sizeof(int)) == -1)
            {
                ngx_connection_error(c, ngx_socket_errno,
                                     "setsockopt(TCP_NODELAY) failed");
                ngx_http_upstream_finalize_request(r, u, NGX_ERROR);
                return;
            }

            c->tcp_nodelay = NGX_TCP_NODELAY_SET;
        }

        if (u->length == 0) {
            if (ngx_http_send_special(r, NGX_HTTP_FLUSH) == NGX_ERROR) {
                ngx_http_upstream_finalize_request(r, u, NGX_ERROR);
                return;
            }

            ngx_http_upstream_process_non_buffered_downstream(r);
        }

        return;
    }
}


//backend pc next, will close pc and do upstream_next for each front relate the pc
void
ngx_http_multi_upstream_next(ngx_connection_t *pc, ngx_uint_t ft_type)
{
    ngx_multi_connection_t      *multi_c;
    ngx_multi_data_t            *item;
    ngx_queue_t                 *data, *q, *tmp;
    ngx_http_request_t          *r;

    multi_c = ngx_get_multi_connection(pc);
    data = &multi_c->data;

    ngx_http_multi_upstream_connection_detach(pc);

    for ( ; ; ) {
        if (ngx_queue_empty(data)) {
            break;
        }

        q = ngx_queue_last(data);
        item = ngx_queue_data(q, ngx_multi_data_t, queue);
        r = item->data;
        ngx_http_upstream_next(r, r->upstream, ft_type);

        tmp = ngx_queue_last(data);
        if (tmp == q) {
            ngx_queue_remove(tmp);
            ngx_log_error(NGX_LOG_ERR, pc->log, 0,
                    "multi connection next but queue exist %p", pc);
            continue;
        }
    }

    ngx_http_multi_upstream_connection_close(pc);
}

//backend pc finalize, will close pc and do finalize for each front relate  the pc
void
ngx_http_multi_upstream_finalize_request(ngx_connection_t *c, ngx_int_t rc)
{
    ngx_multi_connection_t      *multi_c;
    ngx_multi_data_t            *item;
    ngx_queue_t                 *data, *q, *tmp;
    ngx_http_request_t          *r;

    multi_c = ngx_get_multi_connection(c);
    data = &multi_c->data;

    ngx_http_multi_upstream_connection_detach(c);

    for ( ; ; ) {
        if (ngx_queue_empty(data)) {
            break;
        }

        q = ngx_queue_last(data);
        item = ngx_queue_data(q, ngx_multi_data_t, queue);
        r = item->data;
        ngx_http_upstream_finalize_request(r, r->upstream, rc);

        tmp = ngx_queue_last(data);
        if (tmp == q) {
            ngx_queue_remove(tmp);
            ngx_log_error(NGX_LOG_ERR, c->log, 0,
                    "multi connection finalize but queue exist %p", c);
            continue;
        }
    }

    ngx_http_multi_upstream_connection_close(c);
}


void
ngx_http_multi_upstream_process_non_buffered_request(ngx_http_request_t *r)
{
    ngx_int_t                  rc;
    ngx_http_upstream_t       *u;
    ngx_http_core_loc_conf_t  *clcf;

    ngx_connection_t          *downstream;

    u = r->upstream;
    downstream = r->connection;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "multi: http upstream send body: %p, %p", r, u);

    if (u->out_bufs || u->busy_bufs || downstream->buffered) {
        rc = ngx_http_output_filter(r, u->out_bufs);

        if (rc == NGX_ERROR) {
            ngx_http_upstream_finalize_request(r, u, NGX_ERROR);
            return;
        }

        ngx_chain_update_chains(r->pool, &u->free_bufs, &u->busy_bufs,
                &u->out_bufs, u->output.tag);
    }

    if (u->busy_bufs == NULL) {

        if (u->length == 0) {

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                    "http multi upstream finalize: %p, %p", r, u);
            ngx_http_upstream_finalize_request(r, u, 0);
            return;
        }

        ngx_reset_pool(u->send_pool);

    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (downstream->data == r) {
        if (ngx_handle_write_event(downstream->write, clcf->send_lowat)
                != NGX_OK)
        {
            ngx_http_upstream_finalize_request(r, u, NGX_ERROR);
            return;
        }
    }

    if (downstream->write->active && !downstream->write->ready) {
        ngx_add_timer(downstream->write, clcf->send_timeout);
    } else if (downstream->write->timer_set) {
        ngx_del_timer(downstream->write);
    }
#if 0
    if (ngx_handle_read_event(upstream->read, 0) != NGX_OK) {
        ngx_http_upstream_finalize_request(r, u, NGX_ERROR);
        return;
    }

    if (upstream->read->active && !upstream->read->ready) {
        ngx_add_timer(upstream->read, u->conf->read_timeout);
    } else if (upstream->read->timer_set) {
        ngx_del_timer(upstream->read);
    }
#endif
}

ngx_int_t
ngx_http_multi_upstream_write_handler(ngx_connection_t *pc)
{
    ngx_http_request_t      *fake_r, *real_r;
    ngx_http_upstream_t     *fake_u, *real_u;
    ngx_multi_connection_t  *multi_c;
    ngx_queue_t             *q, tmp_queue;

    fake_r = pc->data;
    fake_u = fake_r->upstream;

    multi_c = ngx_get_multi_connection(pc);

    ngx_queue_init(&tmp_queue);

    while (!ngx_queue_empty(&multi_c->waiting_list)) {
        q = ngx_queue_head(&multi_c->waiting_list);

        ngx_queue_remove(q);
        real_r = ngx_queue_data(q, ngx_http_request_t, waiting_queue);
        real_r->waiting = 0;

        ngx_queue_insert_tail(&tmp_queue, q);
    }

    while (!ngx_queue_empty(&tmp_queue)) {
        q = ngx_queue_head(&tmp_queue);

        ngx_queue_remove(q);

        real_r = ngx_queue_data(q, ngx_http_request_t, waiting_queue);

        real_u = real_r->upstream;

        if (real_u->write_event_handler) {
            real_u->write_event_handler(real_r, real_u);
        }
    }

    if (fake_u->write_event_handler) {
        fake_u->write_event_handler(fake_r, fake_u);
    }

    return NGX_OK;
}

void
ngx_http_multi_upstream_read_handler(ngx_connection_t *pc)
{
    ssize_t                  n;
    ngx_int_t                rc;
    ngx_http_request_t      *r, *fake_r, *real_r;
    ngx_http_upstream_t     *u, *fake_u, *real_u;
    ngx_connection_t        *c, *real_c;
    ngx_multi_connection_t  *multi_c;
    ngx_buf_t               *b;

    c = pc;
    multi_c = ngx_get_multi_connection(pc);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "multi: http upstream read handler %p", pc);

    pc->log->action = "reading from multi upstream";

    if (ngx_http_upstream_test_connect(pc) != NGX_OK) {
        ngx_http_multi_upstream_next(pc, NGX_HTTP_UPSTREAM_FT_ERROR);
        return;
    }

    r = pc->data;           //fake_r
    u = r->upstream;        //fake_u
    fake_u = r->upstream;

    fake_r = r;

    if (u->buffer.start == NULL) {
        u->buffer.start = ngx_palloc(r->pool, u->conf->buffer_size);
        if (u->buffer.start == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        u->buffer.pos = u->buffer.start;
        u->buffer.last = u->buffer.start;
        u->buffer.end = u->buffer.start + u->conf->buffer_size;
        u->buffer.temporary = 1;

        u->buffer.tag = u->output.tag;

        if (ngx_list_init(&u->headers_in.headers, r->pool, 8,
                          sizeof(ngx_table_elt_t))
            != NGX_OK)
        {
            ngx_http_multi_upstream_finalize_request(pc,
                                                     NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        if (ngx_list_init(&u->headers_in.trailers, r->pool, 2,
                          sizeof(ngx_table_elt_t))
            != NGX_OK)
        {
            ngx_http_multi_upstream_finalize_request(pc,
                                                     NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }
    }

    //fake_u buffer
    b = &fake_u->buffer;

    for ( ;; ) {
        if (b->last == b->end) {
            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "multi: read buffer full %p, %p, %p, %p"
                           , b->start, b->end, b->pos, b->last);
        } else {
            n = c->recv(c, b->last, b->end - b->last);

            if (n == NGX_AGAIN) {
                ngx_add_timer(pc->read, u->conf->read_timeout);

                if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
                    ngx_http_multi_upstream_finalize_request(pc,
                            NGX_HTTP_INTERNAL_SERVER_ERROR);
                    return;
                }

                return;
            }

            if (n == 0) {
                ngx_log_error(NGX_LOG_ERR, c->log, 0,
                        "upstream prematurely closed connection");
            }

            if (n == NGX_ERROR || n == 0) {
                ngx_http_multi_upstream_next(pc, NGX_HTTP_UPSTREAM_FT_ERROR);
                return;
            }

            b->last += n;
        }

#if 0
        u->valid_header_in = 0;

        u->peer.cached = 0;
#endif

        for ( ; ; ) {
            ngx_log_debug5(NGX_LOG_DEBUG_HTTP, c->log, 0
                    , "multi: process parse start: %d, %p, %p, %p, %p"
                    , b->last - b->pos, b->start, b->end, b->pos, b->last);
            rc = u->process_header(fake_r);

            ngx_log_debug5(NGX_LOG_DEBUG_HTTP, c->log, 0
                    , "multi: process parse end: %d, %p, %p, %p, %p"
                    , b->last - b->pos, b->start, b->end, b->pos, b->last);

            if (rc == NGX_AGAIN) {
                if (b->last == b->end && b->pos == b->last) {
                    b->pos = b->start;
                    b->last = b->start;
                }

                break;
            }

            if (rc == NGX_HTTP_UPSTREAM_INVALID_HEADER) {
                ngx_http_multi_upstream_next(pc, NGX_HTTP_UPSTREAM_FT_INVALID_HEADER);
                return;
            }

            if (rc == NGX_ERROR) {
                ngx_http_multi_upstream_finalize_request(pc, NGX_HTTP_INTERNAL_SERVER_ERROR);
                return;
            }

            /* rc == NGX_OK || rc == NGX_ERROR */

            if (!multi_c->cur) {
                ngx_log_error(NGX_LOG_ERR, c->log, 0,
                              "multi: upstream next because parse cur is empty");
                ngx_http_multi_upstream_finalize_request(pc, NGX_HTTP_INTERNAL_SERVER_ERROR);
                return;
            }

            real_r = multi_c->cur;
            real_u = real_r->upstream;
            real_c = real_r->connection;

            if (rc == NGX_HTTP_UPSTREAM_HEADER_END) {
                real_u->state->header_time = ngx_current_msec - real_u->state->response_time;

                if (real_u->headers_in.status_n >= NGX_HTTP_SPECIAL_RESPONSE) {

                    if (ngx_http_upstream_test_next(real_r, real_u) == NGX_OK) {
                        continue;
                    }

                    if (ngx_http_upstream_intercept_errors(real_r, real_u) == NGX_OK) {
                        continue;
                    }
                }

                if (ngx_http_upstream_process_headers(real_r, real_u) != NGX_OK) {
                    continue;
                }

                ngx_http_multi_upstream_send_response(real_r, real_u);
            } else if (rc == NGX_HTTP_UPSTREAM_GET_BODY_DATA) {
                if (!real_u->header_sent) {
                    ngx_log_error(NGX_LOG_INFO, c->log, 0,
                                  "multi: get body immediate %p", fake_r);
                    //handle header first
                    real_u->state->header_time = ngx_current_msec - real_u->state->response_time;
                    if (real_u->headers_in.status_n >= NGX_HTTP_SPECIAL_RESPONSE) {
                        if (ngx_http_upstream_test_next(real_r, real_u) == NGX_OK) {
                            continue;
                        }

                        if (ngx_http_upstream_intercept_errors(real_r, real_u) == NGX_OK) {
                            continue;
                        }
                    }

                    if (ngx_http_upstream_process_headers(real_r, real_u) != NGX_OK) {
                        continue;
                    }

                    ngx_http_multi_upstream_send_response(real_r, real_u);
                }

                ngx_http_multi_upstream_process_non_buffered_request(real_r);
            } else if (rc == NGX_HTTP_UPSTREAM_PARSE_ERROR) {
                ngx_log_error(NGX_LOG_WARN, c->log, 0,
                              "multi: parse get error %p", fake_r);
                if (!real_u->header_sent) {
                    ngx_http_upstream_finalize_request(real_r, real_u, NGX_HTTP_BAD_GATEWAY);
                } else {
                    ngx_http_upstream_finalize_request(real_r, real_u, NGX_ERROR);
                }
            } else {
                ngx_log_error(NGX_LOG_ERR, c->log, 0,
                              "multi: parse code unknown: %d", rc);
                if (!real_u->header_sent) {
                    ngx_http_upstream_finalize_request(real_r, real_u, NGX_HTTP_INTERNAL_SERVER_ERROR);
                } else {
                    ngx_http_upstream_finalize_request(real_r, real_u, NGX_ERROR);
                }
            }

            ngx_http_run_posted_requests(real_c);
        }
    }
}

//backend handler main
void
ngx_http_multi_upstream_process(ngx_connection_t *pc, ngx_uint_t do_write)
{
    if (do_write) {
        //write
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                "multi: http upstream process write");

        pc->log->action = "multi sending to upstream";

        ngx_http_multi_upstream_write_handler(pc);
        return;
    } else {
        //read
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                "multi: http upstream process read");

        pc->log->action = "multi reading from upstream";

        ngx_http_multi_upstream_read_handler(pc);
        return;
    }
}

void
ngx_http_multi_upstream_handler(ngx_event_t *ev)
{
    ngx_connection_t    *pc;

    pc = ev->data;

    if (ev->timedout) {
        ngx_http_multi_upstream_next(pc, NGX_HTTP_UPSTREAM_FT_TIMEOUT);
        return;
    }

    ngx_http_multi_upstream_process(pc, ev->write);
}

void
ngx_http_multi_upstream_send_pool_cleanup(void *data)
{
    ngx_pool_t      *pool = data;

    ngx_destroy_pool(pool);
}


//impl for start send request, run every ngx_http_request_t
void
ngx_http_multi_upstream_init_request(ngx_connection_t *pc, ngx_http_request_t *r)
{
    ngx_http_upstream_t         *u;
    ngx_http_request_t          *fake_r;
    ngx_pool_cleanup_t          *cln;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "multi: http upstream init request: %p, %p", pc, r);

    u = r->upstream;
    fake_r = pc->data;

    u->write_event_handler = ngx_http_upstream_send_request_handler;
    u->read_event_handler = ngx_http_upstream_process_header;

    u->output.sendfile = pc->sendfile;

    /* init or reinit the ngx_output_chain() and ngx_chain_writer() contexts */
    u->writer.pool = fake_r->pool;
    u->writer.out = NULL;
    u->writer.last = &u->writer.out;
    u->writer.connection = pc;
    u->writer.limit = 0;

    if (u->request_sent) {
        if (ngx_http_upstream_reinit(r, u) != NGX_OK) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }
    }

    if (r->request_body
        && r->request_body->buf
        && r->request_body->temp_file
        && r == r->main)
    {
        /*
         * the r->request_body->buf can be reused for one request only,
         * the subrequests should allocate their own temporary bufs
         */

        u->output.free = ngx_alloc_chain_link(r->pool);
        if (u->output.free == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        u->output.free->buf = r->request_body->buf;
        u->output.free->next = NULL;
        u->output.allocated = 1;

        r->request_body->buf->pos = r->request_body->buf->start;
        r->request_body->buf->last = r->request_body->buf->start;
        r->request_body->buf->tag = u->output.tag;
    }

    u->request_sent = 0;

    if (u->buffer.start == NULL) {
        u->buffer.start = ngx_palloc(r->pool, u->conf->buffer_size);
        if (u->buffer.start == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        u->buffer.pos = u->buffer.start;
        u->buffer.last = u->buffer.start;
        u->buffer.end = u->buffer.start + u->conf->buffer_size;
        u->buffer.temporary = 1;

        u->buffer.tag = u->output.tag;

        if (ngx_list_init(&u->headers_in.headers, r->pool, 8,
                          sizeof(ngx_table_elt_t))
            != NGX_OK)
        {
            ngx_http_multi_upstream_finalize_request(pc,
                                                     NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        if (ngx_list_init(&u->headers_in.trailers, r->pool, 2,
                          sizeof(ngx_table_elt_t))
            != NGX_OK)
        {
            ngx_http_multi_upstream_finalize_request(pc,
                                                     NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }
    }

    if (u->send_pool == NULL) {
        u->send_pool = ngx_create_pool(NGX_DEFAULT_POOL_SIZE, r->connection->log);
        if (u->send_pool == NULL) {
            return;
        }

        cln = ngx_pool_cleanup_add(r->pool, 0);
        if (cln == NULL) {
            return;
        }

        cln->handler = ngx_http_multi_upstream_send_pool_cleanup;
        cln->data = u->send_pool;

    }

    ngx_http_upstream_send_request(r, u, 1);
}

//impl for init multi connection, run every ngx_connection_t success
void
ngx_http_multi_upstream_connect_init(ngx_connection_t *pc)
{
    ngx_multi_connection_t              *multi_c;
    ngx_http_request_t                  *fake_r, *r;
    ngx_http_upstream_t                 *fake_u;
    ngx_queue_t                         *data, *q;
    ngx_array_t                          tmp;
    ngx_multi_data_t                    *item;
    size_t                               i;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "multi: http upstream init connection: %p", pc);

    fake_r = pc->data;
    fake_u = fake_r->upstream;

    pc->read->handler = ngx_http_multi_upstream_handler;
    pc->write->handler = ngx_http_multi_upstream_handler;

    fake_u->write_event_handler = ngx_http_upstream_send_request_handler;
    fake_u->read_event_handler = ngx_http_upstream_process_header;
    fake_u->output.filter_ctx = fake_r;
    fake_u->output.sendfile = pc->sendfile;

    fake_u->writer.out = NULL;
    fake_u->writer.last = &fake_u->writer.out;
    fake_u->writer.connection = pc;
    fake_u->writer.limit = 0;


    //init
    multi_c = ngx_get_multi_connection(pc);
    multi_c->connected = 1;
    data = &multi_c->data;

    if (NGX_OK != ngx_array_init(&tmp, pc->pool, 4, sizeof(ngx_multi_data_t))) {
        return;
    }

    for (q = ngx_queue_head(data);
            q != ngx_queue_sentinel(data);
            q = ngx_queue_next(q))
    {
        item = ngx_array_push(&tmp);
        if (item == NULL) {
            return;
        }
        *item = *(ngx_multi_data_t*) q;
    }

    item = tmp.elts;
    for (i=0; i < tmp.nelts; i++) {

        r = item[i].data;

        ngx_http_multi_upstream_init_request(pc, r);
    }
}

void
ngx_http_multi_upstream_connect_handler(ngx_event_t *ev)
{
    ngx_connection_t                    *pc;

    ngx_http_request_t                  *r;
    ngx_http_upstream_t                 *u;

    pc = ev->data;
    r = pc->data;
    u = r->upstream;

    if (ev->timedout) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0, "multi: connect timeout %p", pc);
        ngx_http_multi_upstream_next(pc, NGX_HTTP_UPSTREAM_FT_TIMEOUT);
        return;
    }

    ngx_del_timer(pc->write);

    if (ngx_http_upstream_test_connect(pc) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0, "multi: connect failed %p", pc);
        ngx_http_multi_upstream_next(pc, NGX_HTTP_UPSTREAM_FT_ERROR);
        return;
    }

#if (NGX_HTTP_SSL)

    //do ssl handshake first if need
    if (u->ssl && pc->ssl == NULL) {
        ngx_http_upstream_ssl_init_connection(r, u, pc);
        return;
    }

#endif

    ngx_http_multi_upstream_connect_init(pc);
}
