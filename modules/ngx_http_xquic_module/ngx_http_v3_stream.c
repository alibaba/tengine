/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <nginx.h>

#include <ngx_http_v3_stream.h>
#include <ngx_http_xquic_module.h>
#include <ngx_xquic_send.h>
#include <ngx_xquic.h>
#include <ngx_http_xquic.h>


#include <xquic/xquic.h>
#include <xquic/xquic_typedef.h>



static void ngx_http_v3_run_request(ngx_http_request_t *r, ngx_http_v3_stream_t *h3_stream);
static void ngx_http_v3_stream_free(ngx_http_v3_stream_t *h3_stream);
void ngx_http_v3_stream_cancel(ngx_http_v3_stream_t *h3_stream,
    ngx_int_t status);


static void
ngx_http_v3_close_stream_handler(ngx_event_t *ev)
{
    ngx_connection_t    *fc;
    ngx_http_request_t  *r;

    fc = ev->data;
    r = fc->data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "|xquic|http3 close stream handler|%p|", r->xqstream);

    ngx_http_v3_close_stream(r->xqstream, 0);
}


static void
ngx_http_v3_request_cleanup(void *data)
{
    ngx_http_v3_stream_t *stream = data;
    if (stream) {
        stream->request_freed = 1;
    }
}


static ngx_http_v3_stream_t *
ngx_http_v3_create_stream(ngx_http_xquic_connection_t *h3c, uint64_t stream_id)
{
    ngx_log_t                  *log;
    ngx_event_t                *rev, *wev;
    ngx_connection_t           *fc;
    ngx_http_log_ctx_t         *ctx;
    ngx_http_request_t         *r;
    ngx_http_cleanup_t         *cln;
    ngx_http_v3_stream_t       *stream;
    ngx_http_core_srv_conf_t   *cscf;
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);


    /* get fake connection */
    fc = h3c->free_fake_connections;

    if (fc) {
        /* use (void *)data as next point  */
        h3c->free_fake_connections = fc->data;

        rev = fc->read;
        wev = fc->write;
        log = fc->log;
        ctx = log->data;

    } else {
        fc = ngx_palloc(h3c->pool, sizeof(ngx_connection_t));
        if (fc == NULL) {
            return NULL;
        }

        rev = ngx_palloc(h3c->pool, sizeof(ngx_event_t));
        if (rev == NULL) {
            return NULL;
        }

        wev = ngx_palloc(h3c->pool, sizeof(ngx_event_t));
        if (wev == NULL) {
            return NULL;
        }

        log = ngx_palloc(h3c->pool, sizeof(ngx_log_t));
        if (log == NULL) {
            return NULL;
        }

        ctx = ngx_palloc(h3c->pool, sizeof(ngx_http_log_ctx_t));
        if (ctx == NULL) {
            return NULL;
        }

        ctx->connection = fc;
        ctx->request = NULL;
        ctx->current_request = NULL;
    }

    ngx_memcpy(log, h3c->connection->log, sizeof(ngx_log_t));

    log->data = ctx;

    ngx_memzero(rev, sizeof(ngx_event_t));

    rev->data = fc;
    rev->ready = 1;
    rev->handler = ngx_http_v3_close_stream_handler;
    rev->log = log;

    ngx_memcpy(wev, rev, sizeof(ngx_event_t));

    wev->write = 1;

    ngx_memcpy(fc, h3c->connection, sizeof(ngx_connection_t));

    fc->data = h3c->http_connection;
    fc->read = rev;
    fc->write = wev;
    fc->sent = 0;
    fc->log = log;
    fc->buffered = 0;
    fc->sndlowat = 1;
    fc->tcp_nodelay = NGX_TCP_NODELAY_DISABLED;


    /* create request */
    r = ngx_http_create_request(fc);
    if (r == NULL) {
        return NULL;
    }

    ngx_str_set(&r->http_protocol, "HTTP/3.0");

    r->http_version = NGX_HTTP_VERSION_30;
    r->valid_location = 1;

    fc->data = r;
    h3c->connection->requests++;

    cscf = ngx_http_get_module_srv_conf(r, ngx_http_core_module);

    r->header_in = ngx_create_temp_buf(r->pool,
                                       cscf->client_header_buffer_size);
    if (r->header_in == NULL) {
        ngx_http_free_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return NULL;
    }

    if (ngx_list_init(&r->headers_in.headers, r->pool, 20,
                      sizeof(ngx_table_elt_t))
        != NGX_OK)
    {
        ngx_http_free_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return NULL;
    }

    r->headers_in.connection_type = NGX_HTTP_CONNECTION_CLOSE;

    /* create stream */
#if 0
    stream = ngx_pcalloc(r->pool, sizeof(ngx_http_v3_stream_t));
    if (stream == NULL) {
        goto free_request;
    }
#endif

    stream = h3c->free_streams;

    if (stream) {
        /* use (void *)data as next point  */
        h3c->free_streams = stream->next;
        ngx_memzero(stream, sizeof(ngx_http_v3_stream_t));

    } else {
        stream = ngx_pcalloc(h3c->pool, sizeof(ngx_http_v3_stream_t));
        if (stream == NULL) {
            goto free_request;
        }
    }

    stream->id = stream_id;

    /* use in ngx_http_v3_finalize_connection, don't alloc from request pool */
    stream->list_node = ngx_pcalloc(h3c->pool, sizeof(ngx_xquic_list_node_t));
    if (stream->list_node == NULL) {
        goto free_request;
    }
    stream->list_node->entry = stream;

    /* insert to streams_index */
    ngx_uint_t index = ngx_http_xquic_index(qmcf, stream->id);
    stream->list_node->next = h3c->streams_index[index];
    h3c->streams_index[index] = stream->list_node;

    /* relate to request */
    r->xqstream = stream;

    stream->request = r;
    stream->connection = h3c;

    h3c->processing++;

    cln = ngx_http_cleanup_add(r, 0);
    if (cln == NULL) {
        goto free_request;
    }

    cln->handler = ngx_http_v3_request_cleanup;
    cln->data = r->xqstream;

    return stream;

free_request:
    ngx_http_free_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
    return NULL;
}


ngx_int_t
ngx_http_v3_check_request_limit(ngx_http_v3_stream_t *user_stream)
{
    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);

    /* limit is not configured */
    if (qmcf->max_quic_qps == NGX_CONF_UNSET_UINT) {
        return NGX_OK;
    }

    /* check max qps limit */
    ngx_atomic_uint_t quic_qps_nexttime = *ngx_stat_quic_qps_nexttime;
    if (ngx_current_msec <= quic_qps_nexttime) {
        /* still in current stat round, check cps limit. decline if reach max QPS limit */
        if (*ngx_stat_quic_qps >= qmcf->max_quic_qps) {
            ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "|xquic|reached max qps limit"
                      "|limit:%ui|", qmcf->max_quic_qps);
            return NGX_DECLINED;
        }

    } else {
        /* start a new stat round */
        ngx_atomic_cmp_set(ngx_stat_quic_qps_nexttime,
            *ngx_stat_quic_qps_nexttime, ngx_current_msec + 1000);
        ngx_atomic_cmp_set(ngx_stat_quic_qps, *ngx_stat_quic_qps, 0);
    }

    return NGX_OK;
}


void
ngx_http_v3_stream_refuse(ngx_http_v3_stream_t *h3_stream,
    ngx_int_t status)
{
    h3_stream->cancel_status = status;

    if (!h3_stream->request_closed) {
        ngx_http_finalize_request(h3_stream->request, status);
        h3_stream->request = NULL;
    }
}


int 
ngx_http_v3_request_create_notify(xqc_h3_request_t *h3_request, void *user_data)
{
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                                "|xquic|xqc_http_v3_request_create_notify|");

    ngx_http_xquic_connection_t *h3c = xqc_h3_get_conn_user_data_by_request(h3_request);

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                                "|xquic|xqc_http_v3_request_create_notify in connection|%p|", h3c);

    xqc_stream_id_t stream_id = xqc_h3_stream_id(h3_request);

    ngx_http_v3_stream_t *user_stream = ngx_http_v3_create_stream(h3c, (uint64_t)stream_id);
    user_stream->h3_request = h3_request;
    xqc_h3_request_set_user_data(h3_request, user_stream);

    /* limit while allow creation of usere_stream, which will be freed in request_close_notify */
    if (ngx_http_v3_check_request_limit(user_stream) != NGX_OK) {
        /* if request is limited, refuse it */
        ngx_http_v3_stream_refuse(user_stream, NGX_HTTP_REQUEST_LIMITED);
        (void) ngx_atomic_fetch_add(ngx_stat_quic_queries_refused, 1);
        return NGX_OK;
    }


    /* add stat */
    (void) ngx_atomic_fetch_add(ngx_stat_quic_qps, 1);
    (void) ngx_atomic_fetch_add(ngx_stat_quic_queries, 1);

    return NGX_OK;
}


/**
 * only free user_stream here,
 * make sure user_stream has the same life cycle of h3_request in xquic engine
 */
int 
ngx_http_v3_request_close_notify(xqc_h3_request_t *h3_request, 
    void *user_data)
{
    ngx_http_v3_stream_t        *h3_stream = (ngx_http_v3_stream_t *)user_data;
    xqc_request_stats_t          stats = xqc_h3_request_get_stats(h3_request);

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                                "|xquic|xqc_http_v3_request_close_notify|err=%d|", stats.stream_err);

    if (!h3_stream->run_request) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                                    "|xquic|h3 request closed before run|err=%d|", stats.stream_err);
        /* h3_stream must be freed at last, so h3_stream is not reused now */
        if (!h3_stream->request_freed) {
            ngx_http_finalize_request(h3_stream->request, NGX_ERROR);
            h3_stream->request = NULL;
        }
    }

    if (!h3_stream->request_closed) {
        h3_stream->engine_inner_closed = 1;
        ngx_http_v3_close_stream(h3_stream, 0);
        return NGX_OK;
    }

    if (h3_stream->closed) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                                "|xquic|ngx_http_v3_request_close_notify|free stream twice|stream_id=%ui|err=%d|", 
                                h3_stream->id, stats.stream_err);
        return NGX_OK;
    }

    ngx_http_v3_close_stream(h3_stream, 0);
    /* free user_stream & insert into free_streams */
    ngx_http_v3_stream_free(h3_stream);

    return NGX_OK;
}


int 
ngx_http_v3_request_write_notify(xqc_h3_request_t *h3_request, 
    void *user_data)
{
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                                "|xquic|xqc_http_v3_request_write_notify|");

    ngx_http_v3_stream_t *h3_stream = (ngx_http_v3_stream_t *) user_data;

    /* request closed */
    if (h3_stream->request_closed) {
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                                "|xquic|xqc_http_v3_request_write_notify|request_closed|");
        return NGX_OK;
    }

    h3_stream->wait_to_write = 0;


    /* don't have data to send */
    if (h3_stream->queued == 0) {
        return NGX_OK;
    }

    /* don't need limit here */
    if (ngx_http_xquic_send_chain(h3_stream->request->connection, NULL, 0) == NGX_CHAIN_ERROR) {

        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                                "|xquic|ngx_http_write_filter error|");

        return NGX_OK;
    }

    return NGX_OK;
}




static ngx_int_t
ngx_http_v3_parse_path(ngx_http_request_t *r, 
    ngx_http_v3_header_t *header)
{
    if (r->unparsed_uri.len) {
        ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                      "|xquic|client sent duplicate :path header|");

        return NGX_DECLINED;
    }

    if (header->value.len == 0) {
        ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                      "|xquic|client sent empty :path header|");

        return NGX_DECLINED;
    }

    r->uri_start = header->value.data;
    r->uri_end = header->value.data + header->value.len;

    if (ngx_http_parse_uri(r) != NGX_OK) {
        ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                      "|xquic|client sent invalid :path header: \"%V\"|",
                      &header->value);

        return NGX_DECLINED;
    }

    if (ngx_http_process_request_uri(r) != NGX_OK) {
        /*
         * request has been finalized already
         * in ngx_http_process_request_uri()
         */
        return NGX_ABORT;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_v3_parse_method(ngx_http_request_t *r, 
    ngx_http_v3_header_t *header)
{
    size_t         k, len;
    ngx_uint_t     n;
    const u_char  *p, *m;

    /*
     * This array takes less than 256 sequential bytes,
     * and if typical CPU cache line size is 64 bytes,
     * it is prefetched for 4 load operations.
     */
    static const struct {
        u_char            len;
        const u_char      method[11];
        uint32_t          value;
    } tests[] = {
        { 3, "GET",       NGX_HTTP_GET },
        { 4, "POST",      NGX_HTTP_POST },
        { 4, "HEAD",      NGX_HTTP_HEAD },
        { 7, "OPTIONS",   NGX_HTTP_OPTIONS },
        { 8, "PROPFIND",  NGX_HTTP_PROPFIND },
        { 3, "PUT",       NGX_HTTP_PUT },
        { 5, "MKCOL",     NGX_HTTP_MKCOL },
        { 6, "DELETE",    NGX_HTTP_DELETE },
        { 4, "COPY",      NGX_HTTP_COPY },
        { 4, "MOVE",      NGX_HTTP_MOVE },
        { 9, "PROPPATCH", NGX_HTTP_PROPPATCH },
        { 4, "LOCK",      NGX_HTTP_LOCK },
        { 6, "UNLOCK",    NGX_HTTP_UNLOCK },
        { 5, "PATCH",     NGX_HTTP_PATCH },
        { 5, "TRACE",     NGX_HTTP_TRACE }
    }, *test;

    if (r->method_name.len) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "client sent duplicate :method header");

        return NGX_DECLINED;
    }

    if (header->value.len == 0) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "client sent empty :method header");

        return NGX_DECLINED;
    }

    r->method_name.len = header->value.len;
    r->method_name.data = header->value.data;

    len = r->method_name.len;
    n = sizeof(tests) / sizeof(tests[0]);
    test = tests;

    do {
        if (len == test->len) {
            p = r->method_name.data;
            m = test->method;
            k = len;

            do {
                if (*p++ != *m++) {
                    goto next;
                }
            } while (--k);

            r->method = test->value;
            return NGX_OK;
        }

    next:
        test++;

    } while (--n);

    p = r->method_name.data;

    do {
        if ((*p < 'A' || *p > 'Z') && *p != '_') {
            ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                          "client sent invalid method: \"%V\"",
                          &r->method_name);

            return NGX_DECLINED;
        }

        p++;

    } while (--len);

    return NGX_OK;
}


static ngx_int_t
ngx_http_v3_parse_scheme(ngx_http_request_t *r, 
    ngx_http_v3_header_t *header)
{
    if (r->schema_start) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "client sent duplicate :schema header");

        return NGX_DECLINED;
    }

    if (header->value.len == 0) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "client sent empty :schema header");

        return NGX_DECLINED;
    }

    r->schema_start = header->value.data;
    r->schema_end = header->value.data + header->value.len;

    return NGX_OK;
}


static ngx_int_t
ngx_http_v3_parse_authority(ngx_http_request_t *r, 
    ngx_http_v3_header_t *header)
{
    ngx_table_elt_t            *h;
    ngx_http_header_t          *hh;
    ngx_http_core_main_conf_t  *cmcf;

    static ngx_str_t host = ngx_string("host");

    h = ngx_list_push(&r->headers_in.headers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    h->hash = ngx_hash_key(host.data, host.len);

    h->key.len = host.len;
    h->key.data = host.data;

    h->value.len = header->value.len;
    h->value.data = header->value.data;

    h->lowcase_key = host.data;

    cmcf = ngx_http_get_module_main_conf(r, ngx_http_core_module);

    hh = ngx_hash_find(&cmcf->headers_in_hash, h->hash,
                       h->lowcase_key, h->key.len);

    if (hh == NULL) {
        return NGX_ERROR;
    }

    if (hh->handler(r, h, hh->offset) != NGX_OK) {
        /*
         * request has been finalized already
         * in ngx_http_process_host()
         */
        return NGX_ABORT;
    }

    return NGX_OK;
}



static ngx_int_t
ngx_http_v3_pseudo_header(ngx_http_request_t *r, 
    ngx_http_v3_header_t *header)
{
    header->name.len--;
    header->name.data++;

    switch (header->name.len) {
    case 4:
        if (ngx_memcmp(header->name.data, "path", sizeof("path") - 1)
            == 0)
        {
            return ngx_http_v3_parse_path(r, header);
        }

        break;

    case 6:
        if (ngx_memcmp(header->name.data, "method", sizeof("method") - 1)
            == 0)
        {
            return ngx_http_v3_parse_method(r, header);
        }

        if (ngx_memcmp(header->name.data, "scheme", sizeof("scheme") - 1)
            == 0)
        {
            return ngx_http_v3_parse_scheme(r, header);
        }

        break;

    case 9:
        if (ngx_memcmp(header->name.data, "authority", sizeof("authority") - 1)
            == 0)
        {
            return ngx_http_v3_parse_authority(r, header);
        }

        break;
    }

    ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                  "|xquic|client sent unknown pseudo header \"%V\"|",
                  &header->name);

    return NGX_ERROR;
}


static ngx_int_t
ngx_http_v3_cookie(ngx_http_request_t *r, ngx_http_v3_header_t *header)
{
    ngx_str_t    *val;
    ngx_array_t  *cookies;

    cookies = r->xqstream->cookies;

    if (cookies == NULL) {
        cookies = ngx_array_create(r->pool, 2, sizeof(ngx_str_t));
        if (cookies == NULL) {
            return NGX_ERROR;
        }

        r->xqstream->cookies = cookies;
    }

    val = ngx_array_push(cookies);
    if (val == NULL) {
        return NGX_ERROR;
    }

    val->len = header->value.len;
    val->data = header->value.data;

    return NGX_OK;
}



ngx_int_t
ngx_http_v3_request_process_header(ngx_http_request_t *r,
    xqc_http_header_t * in_header)
{
    ngx_table_elt_t            *h;
    ngx_http_header_t          *hh;
    ngx_http_core_main_conf_t  *cmcf;

    static ngx_str_t cookie = ngx_string("cookie");


    /* invalid name length */
    if (in_header->name.iov_len <= 0) {
        return NGX_ERROR;
    }

    /* copy to tmp_header for parsing */
    ngx_http_v3_header_t tmp_header;
    ngx_http_v3_header_t *header = &tmp_header;
    
    header->name.data = ngx_pcalloc(r->pool, in_header->name.iov_len + 1);
    if (header->name.data == NULL) {
        return NGX_ERROR;
    }
    ngx_memcpy(header->name.data, in_header->name.iov_base, in_header->name.iov_len);
    header->name.len = in_header->name.iov_len;
    header->name.data[header->name.len] = '\0';


    header->value.data = ngx_pcalloc(r->pool, in_header->value.iov_len + 1);
    if (header->value.data == NULL) {
        return NGX_ERROR;
    }
    ngx_memcpy(header->value.data, in_header->value.iov_base, in_header->value.iov_len);
    header->value.len = in_header->value.iov_len;  
    header->value.data[header->value.len] = '\0';

    /* check for pseudo header */
    if (header->name.data[0] == ':') {
        return ngx_http_v3_pseudo_header(r, header);
    }


    /* check for cookies */
    if (header->name.len == cookie.len
        && ngx_memcmp(header->name.data, cookie.data, cookie.len) == 0)
    {
        return ngx_http_v3_cookie(r, header);
    }

    /* copy to headers_in */
    h = ngx_list_push(&r->headers_in.headers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    h->key.len = header->name.len;
    h->key.data = header->name.data;

    /* TODO Optimization: precalculate hash and handler for indexed headers. */
    h->hash = ngx_hash_key(h->key.data, h->key.len);

    h->value.len = header->value.len;
    h->value.data = header->value.data;

    h->lowcase_key = h->key.data;
    
    cmcf = ngx_http_get_module_main_conf(r, ngx_http_core_module);

    hh = ngx_hash_find(&cmcf->headers_in_hash, h->hash,
                       h->lowcase_key, h->key.len);

    if (hh && hh->handler(r, h, hh->offset) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_v3_init_request_body(ngx_http_request_t *r)
{
    ngx_buf_t                 *buf;
    ngx_temp_file_t           *tf;
    ngx_http_request_body_t   *rb;
    ngx_http_core_loc_conf_t  *clcf;

    rb = ngx_pcalloc(r->pool, sizeof(ngx_http_request_body_t));
    if (rb == NULL) {
        return NGX_ERROR;
    }

    r->request_body = rb;

    if (r->xqstream->in_closed) {
        return NGX_OK;
    }

    rb->rest = r->headers_in.content_length_n;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (r->request_body_in_file_only
        || rb->rest > (off_t) clcf->client_body_buffer_size
        /*|| rb->rest < 0*/)
    {
        tf = ngx_pcalloc(r->pool, sizeof(ngx_temp_file_t));
        if (tf == NULL) {
            return NGX_ERROR;
        }

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

        if (r->xqstream->in_closed
            && ngx_create_temp_file(&tf->file, tf->path, tf->pool,
                                    tf->persistent, tf->clean, tf->access)
               != NGX_OK)
        {
            return NGX_ERROR;
        }

        buf = ngx_calloc_buf(r->pool);
        if (buf == NULL) {
            return NGX_ERROR;
        }

    } else {

        if (rb->rest == 0) {
            return NGX_OK;
        }

        buf = ngx_create_temp_buf(r->pool,
                rb->rest < 0 ? clcf->client_body_buffer_size : ngx_min((size_t)rb->rest, clcf->client_body_buffer_size));
        if (buf == NULL) {
            return NGX_ERROR;
        }
    }

    rb->buf = buf;

    rb->bufs = ngx_alloc_chain_link(r->pool);
    if (rb->bufs == NULL) {
        return NGX_ERROR;
    }

    rb->bufs->buf = buf;
    rb->bufs->next = NULL;

    rb->rest = 0;

    return NGX_OK;
}


ngx_int_t
ngx_http_v3_recv_body(ngx_http_request_t         *r, 
    ngx_http_v3_stream_t      *stream, 
    xqc_h3_request_t          *h3_request)
{
    ngx_http_core_loc_conf_t  *clcf;
    ngx_buf_t                 *buf;
    ngx_int_t                  rc;
    ngx_connection_t          *fc;
    off_t                      len;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    fc = r->connection;

    /* check if skip data */
    if (stream->skip_data) {
        stream->in_closed = 1;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, fc->log, 0,
                       "|xquic|ngx_http_v3_recv_body|skipping http3 DATA, reason: %d|",
                       stream->skip_data);

        return NGX_ERROR;
    }

    if (r->request_body && r->request_body->buf) {
        buf = r->request_body->buf;

    } else {
        buf = stream->body_buffer;

        if (buf == NULL) {
            len = clcf->client_body_buffer_size;

            buf = ngx_create_temp_buf(r->pool, (size_t) len);
            if (buf == NULL) {
                ngx_log_error(NGX_LOG_WARN, fc->log, 0,
                              "|xquic|ngx_http_v3_recv_body|create temp buf error|");

                return NGX_ERROR;
            }

            stream->body_buffer = buf;
        }
    }

    ssize_t size = 0;
    uint8_t fin = 0;

    do {
        if (buf->last == buf->end) {
            len = buf->end - buf->start;
            off_t pos_len = buf->pos - buf->start;

            u_char *new_buf = ngx_pcalloc(r->pool, len * 2);
            if (new_buf == NULL) {
                ngx_log_error(NGX_LOG_WARN, fc->log, 0,
                              "|xquic|ngx_http_v3_recv_body|ngx_pcalloc error|");

                return NGX_ERROR;
            }

            ngx_memcpy(new_buf, buf->start, len);
            buf->pos = new_buf + pos_len;
            buf->last = new_buf + len;
            buf->end = new_buf + len * 2;
            ngx_pfree(r->pool, buf->start);
            buf->start = new_buf;
        }

        ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                      "|xquic|ngx_http_v3_recv_body|buf->size:%z|", buf->end - buf->last);

        size = xqc_h3_request_recv_body(h3_request, buf->last, buf->end - buf->last, &fin);
        if (size == -XQC_EAGAIN) {
            break;
        }
        if (size < 0) {
            ngx_log_error(NGX_LOG_WARN, fc->log, 0,
                          "|xquic|ngx_http_v3_recv_body|xqc_h3_request_recv_body error:%z|", size);
            return NGX_ERROR;
        }

        buf->last += size;
        ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                      "|xquic|ngx_http_v3_recv_body|xqc_h3_request_recv_body size:%z|", size);

    } while (size > 0 && !fin);

    if (r->request_body) {
        rc = ngx_http_v3_process_request_body(r, NULL, 0, fin);

        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_WARN, fc->log, 0,
                          "|xquic|ngx_http_v3_recv_body|ngx_http_v3_process_request_body error:%z|", rc);
            return NGX_ERROR;
        }

    }

    if (fin) {

        stream->in_closed = 1;
    }

    return NGX_OK;
}


void
ngx_http_v3_state_headers_complete(ngx_http_v3_stream_t *h3_stream)
{
    ngx_http_v3_run_request(h3_stream->request, h3_stream);
}


int 
ngx_http_v3_request_read_notify(xqc_h3_request_t *h3_request, xqc_request_notify_flag_t flag,
    void *user_data)
{
    size_t                       i;
    unsigned char                fin = 0;
    ngx_http_v3_stream_t        *user_stream = (ngx_http_v3_stream_t *) user_data;
    ngx_http_request_t          *r = user_stream->request;
  //ngx_connection_t            *fc = r->connection;
  //ngx_http_request_body_t     *rb = r->request_body;
    ngx_int_t                    ret;

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                                "|xquic|ngx_http_v3_request_read_notify|");

    if (user_stream->request_closed) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                                "|xquic|ngx_http_v3_request_read_notify|request_closed|");
        return NGX_OK;
    }

    if (user_stream->header_recvd == 0
        && (flag & XQC_REQ_NOTIFY_READ_HEADER)) 
    {
        xqc_http_headers_t *headers;
        headers = xqc_h3_request_recv_headers(h3_request, &fin);
        if (headers == NULL) {
            ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                            "|xquic|xqc_h3_request_recv_headers error|");
            return NGX_ERROR;
        }

        for (i = 0; i < headers->count; i++) {
            ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                            "|xquic|header name:%*s value:%*s|",
                            headers->headers[i].name.iov_len, headers->headers[i].name.iov_base, 
                            headers->headers[i].value.iov_len, headers->headers[i].value.iov_base);

            ret = ngx_http_v3_request_process_header(user_stream->request, 
                        &(headers->headers[i]));

            /* NGX_ABORT - request has been closed */
            /* NGX_ERROR,NGX_DECLINED - request err but not closed */   

            if (ret != NGX_OK) {
                ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                                "|xquic|ngx_http_v3_request_process_header error|header name:%*s value:%*s|",
                                headers->headers[i].name.iov_len, headers->headers[i].name.iov_base, 
                                headers->headers[i].value.iov_len,headers->headers[i].value.iov_base);
                return NGX_ERROR; 
            }
        }

        user_stream->header_recvd = 1;

        if (fin) {
            user_stream->in_closed = 1;
        }

        /* MUST finish read header first, then run request */
        ngx_http_v3_state_headers_complete(user_stream);
    }

    /* wait for request body */
    if (!(flag & XQC_REQ_NOTIFY_READ_BODY)) {
        return NGX_OK;
    }

    if (user_stream->request_closed) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                   "|xquic|ngx_http_v3_recv_body error, request closed|");
        return NGX_ERROR;
    }

    /* read request body */
    if (ngx_http_v3_recv_body(r, user_stream, h3_request) != NGX_OK) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                        "|xquic|ngx_http_v3_recv_body error|");
        return NGX_ERROR; 
    }

    return NGX_OK;
}




static ngx_int_t
ngx_http_v3_construct_request_line(ngx_http_request_t *r)
{
    u_char  *p;

    static const u_char ending[] = " HTTP/3.0";

    if (r->method_name.len == 0
        || r->unparsed_uri.len == 0)
    {
        ngx_http_v3_stream_cancel(r->xqstream, NGX_HTTP_BAD_REQUEST);
        return NGX_ERROR;
    }

    r->request_line.len = r->method_name.len + 1
                          + r->unparsed_uri.len
                          + sizeof(ending) - 1;

    p = ngx_pnalloc(r->pool, r->request_line.len + 1);
    if (p == NULL) {
        ngx_http_v3_stream_cancel(r->xqstream, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return NGX_ERROR;
    }

    r->request_line.data = p;

    p = ngx_cpymem(p, r->method_name.data, r->method_name.len);

    *p++ = ' ';

    p = ngx_cpymem(p, r->unparsed_uri.data, r->unparsed_uri.len);

    ngx_memcpy(p, ending, sizeof(ending));

    /* some modules expect the space character after method name */
    r->method_name.data = r->request_line.data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "|xquic|http3 http request line: \"%V\"|", &r->request_line);

    return NGX_OK;
}


static ngx_int_t
ngx_http_v3_construct_cookie_header(ngx_http_request_t *r)
{
    u_char                     *buf, *p, *end;
    size_t                      len;
    ngx_str_t                  *vals;
    ngx_uint_t                  i;
    ngx_array_t                *cookies;
    ngx_table_elt_t            *h;
    ngx_http_header_t          *hh;
    ngx_http_core_main_conf_t  *cmcf;

    static ngx_str_t cookie = ngx_string("cookie");

    cookies = r->xqstream->cookies;

    if (cookies == NULL) {
        return NGX_OK;
    }

    vals = cookies->elts;

    i = 0;
    len = 0;

    do {
        len += vals[i].len + 2;
    } while (++i != cookies->nelts);

    len -= 2;

    buf = ngx_pnalloc(r->pool, len + 1);
    if (buf == NULL) {
        ngx_http_v3_close_stream(r->xqstream, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return NGX_ERROR;
    }

    p = buf;
    end = buf + len;

    for (i = 0; /* void */ ; i++) {

        p = ngx_cpymem(p, vals[i].data, vals[i].len);

        if (p == end) {
            *p = '\0';
            break;
        }

        *p++ = ';'; *p++ = ' ';
    }

    h = ngx_list_push(&r->headers_in.headers);
    if (h == NULL) {
        ngx_http_v3_close_stream(r->xqstream, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return NGX_ERROR;
    }

    h->hash = ngx_hash_key(cookie.data, cookie.len);

    h->key.len = cookie.len;
    h->key.data = cookie.data;

    h->value.len = len;
    h->value.data = buf;

    h->lowcase_key = cookie.data;

    cmcf = ngx_http_get_module_main_conf(r, ngx_http_core_module);

    hh = ngx_hash_find(&cmcf->headers_in_hash, h->hash,
                       h->lowcase_key, h->key.len);

    if (hh == NULL) {
        ngx_http_v3_close_stream(r->xqstream, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return NGX_ERROR;
    }

    if (hh->handler(r, h, hh->offset) != NGX_OK) {
        /*
         * request has been finalized already
         * in ngx_http_process_multi_header_lines()
         */
        return NGX_ERROR;
    }

    return NGX_OK;
}



static void
ngx_http_v3_run_request(ngx_http_request_t *r, 
    ngx_http_v3_stream_t *h3_stream)
{
    /* MUST only run once */
    if (h3_stream->run_request) {
        return;
    }
    h3_stream->run_request = 1;

    if (ngx_http_v3_construct_request_line(r) != NGX_OK) {
        return;
    }

    if (ngx_http_v3_construct_cookie_header(r) != NGX_OK) {
        return;
    }

    r->http_state = NGX_HTTP_PROCESS_REQUEST_STATE;

    if (ngx_http_process_request_header(r) != NGX_OK) {
        ngx_http_v3_stream_cancel(r->xqstream, NGX_HTTP_BAD_REQUEST);
        return;
    }

    if (r->headers_in.content_length_n == -1 && !r->xqstream->in_closed) {
        r->headers_in.chunked = 1;
    }

    ngx_http_process_request(r);
}


/**
 * Abnormal
 */
void
ngx_http_v3_stream_cancel(ngx_http_v3_stream_t *h3_stream,
    ngx_int_t status)
{
    xqc_h3_request_t *h3_request = h3_stream->h3_request;
    h3_stream->cancel_status = status;

    /* engine will call ngx_http_v3_request_close_notify and free stream */
    ngx_int_t ret = xqc_h3_request_close(h3_request);
    if (ret != NGX_OK) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                    "|xquic|xqc_h3_request_close err|%i|", ret);
    }

    if (!h3_stream->request_closed) {
        ngx_http_finalize_request(h3_stream->request, status);
        h3_stream->request = NULL;
    }
}


static void
ngx_http_v3_stream_free(ngx_http_v3_stream_t *h3_stream)
{
    ngx_http_xquic_connection_t  *h3c;

    h3c = h3_stream->connection;

    /* don't delete node from streams_index, free in conn close */
    h3_stream->list_node->entry = NULL;
    h3_stream->list_node = NULL;
    ngx_memzero(h3_stream, sizeof(ngx_http_v3_stream_t));

    /* recycle stream */
    h3_stream->next = h3c->free_streams;
    h3c->free_streams = h3_stream;        
    h3_stream->closed = 1;
}


/**
 * Normal - ngx_http_close_request
 */
void
ngx_http_v3_close_stream(ngx_http_v3_stream_t *h3_stream, 
    ngx_int_t rc)
{
    ngx_event_t                  *ev;
    ngx_connection_t             *fc;
    ngx_http_xquic_connection_t  *h3c;
    ngx_http_request_t           *r = NULL;

    if (h3_stream->request_closed || h3_stream->closed) {
        return;
    }

    h3c = h3_stream->connection;
    fc = h3_stream->request->connection;
    r = h3_stream->request;

//    if (h3_stream->queued) {
//        fc->write->handler = ngx_http_v3_close_stream_handler;
//        fc->read->handler = ngx_http_v3_close_stream_handler;
//        return;
//    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, fc->log, 0,
                   "|xquic| close stream %ui, processing %ui|",
                   h3_stream->id, h3c->processing);


    h3_stream->request_closed = 1;

    if (!h3_stream->closed 
        && h3_stream->engine_inner_closed) 
    {
        /* only free here if engine_inner_closed */
        ngx_http_v3_stream_free(h3_stream);
    }

    /* h3_stream has been freed */

    fc = r->connection;

    /* Do not need to close xquic h3 request here */

    ngx_http_free_request(r, rc);

    ev = fc->read;

    if (ev->timer_set) {
        ngx_del_timer(ev);
    }

#if (nginx_version >= 1007005 || tengine_version >= 2000002)
    if (ev->posted) {
#else
    if (ev->prev) {
#endif
        ngx_delete_posted_event(ev);
    }

    ev = fc->write;

    if (ev->timer_set) {
        ngx_del_timer(ev);
    }

#if (nginx_version >= 1007005 || tengine_version >= 2000002)
    if (ev->posted) {
#else
    if (ev->prev) {
#endif
        ngx_delete_posted_event(ev);
    }

    /* use (void *)data as next point  */
    fc->data = (void *) h3c->free_fake_connections;
    h3c->free_fake_connections = fc;


    h3c->processing--;

    if (h3c->processing == 0) {
        if (h3c->closing && h3c->wait_to_close) {
            ngx_log_debug(NGX_LOG_DEBUG_HTTP, h3c->connection->log, 0,
                          "|xquic|close connection after stream close|");
            ngx_http_v3_finalize_connection(h3c, NGX_XQUIC_CONN_NO_ERR);

            return;
        }

    }
}



