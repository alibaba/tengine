/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_http_xquic.h>
#include <ngx_http_v3_stream.h>
#include <ngx_http_xquic_module.h>

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>

#include <xquic/xqc_errno.h>


#define NGX_HTTP_XQUIC_NAME_SERVER           "server"
#define NGX_HTTP_XQUIC_NAME_DATE             "date"
#define NGX_HTTP_XQUIC_NAME_CONTENT_TYPE     "content-type"
#define NGX_HTTP_XQUIC_NAME_CONTENT_LENGTH   "content-length"
#define NGX_HTTP_XQUIC_NAME_LAST_MODIFIED    "last-modified"
#define NGX_HTTP_XQUIC_NAME_LOCATION         "location"
#define NGX_HTTP_XQUIC_NAME_VARY             "vary"

#define NGX_XQUIC_HEADERS_INIT_CAPACITY      64
#define NGX_XQUIC_TMP_BUF_SIZE               1024



static ngx_http_output_header_filter_pt  ngx_http_next_header_filter;

static ngx_int_t ngx_http_xquic_filter_init(ngx_conf_t *cf);


static ngx_http_module_t  ngx_http_xquic_filter_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_http_xquic_filter_init,            /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};

ngx_module_t  ngx_http_xquic_filter_module = {
    NGX_MODULE_V1,
    &ngx_http_xquic_filter_module_ctx,     /* module context */
    NULL,                                  /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


ssize_t
ngx_http_xquic_stream_send_header(ngx_http_v3_stream_t *qstream)
{
    ssize_t ret = 0;
    uint8_t header_only = (qstream->request->header_only == 1);

    ret = xqc_h3_request_send_headers(qstream->h3_request,
                        &(qstream->resp_headers), header_only);
    if (ret < 0) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                    "|xquic|xqc_h3_request_send_headers error %z|", ret);
        return NGX_ERROR;
    } else {
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|xqc_h3_request_send_headers success size=%z|", ret);
        qstream->queued--;
    }

    if (header_only) {
        return ret;
    }

    return ret;
}


ssize_t
ngx_http_xquic_stream_send_body(ngx_http_v3_stream_t *qstream,
    u_char *buf, size_t size, int fin)
{
    ssize_t ret = xqc_h3_request_send_body(qstream->h3_request,
                                           buf, size, fin);

    if (ret == -XQC_EAGAIN) {

        /* inner buf full, congestion control, flow control */
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|xqc_h3_request_send_body EAGAIN|");
        return NGX_AGAIN;

    } else if (ret < 0) {
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|xqc_h3_request_send_body error %z|", ret);
        return NGX_ERROR;
    }

    qstream->body_sent += ret;

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|xquic|xqc_h3_request_send_body offset=%z|%i|", qstream->body_sent, fin);

    return ret;
}



ngx_int_t
ngx_http_xquic_headers_initial(xqc_http_headers_t *headers)
{
    headers->headers = NULL;
    headers->count = 0;
    headers->capacity = 0;
    return NGX_OK;
}


ngx_int_t
ngx_http_xquic_headers_realloc_buf(ngx_http_request_t *r,
    xqc_http_headers_t *headers, size_t capacity)
{

    if(headers->count > capacity){
        return NGX_ERROR;
    }
    xqc_http_header_t * old = headers->headers;

    headers->headers = ngx_pcalloc(r->pool, sizeof(xqc_http_header_t) * capacity);

    if(headers->headers == NULL){
        ngx_pfree(r->pool, old);
        headers->count = 0;
        headers->capacity = 0;
        return NGX_ERROR;
    }

    headers->capacity = capacity;
    memcpy(headers->headers, old, headers->count * sizeof(xqc_http_headers_t));
    ngx_pfree(r->pool, old);

    return NGX_OK;
}



ngx_int_t
ngx_http_xquic_headers_create_buf(ngx_http_request_t *r,
    xqc_http_headers_t *headers, size_t capacity)
{
    headers->headers = ngx_pcalloc(r->pool, sizeof(xqc_http_header_t) * capacity);
    if (headers->headers == NULL) {
        return NGX_ERROR;
    }

    ngx_memset(headers->headers, 0, sizeof(xqc_http_header_t) * capacity);
    headers->count = 0;
    headers->capacity = capacity;
    return NGX_OK;
}


ngx_int_t
ngx_http_xquic_header_save(ngx_http_request_t *r,
    xqc_http_headers_t * headers, ngx_str_t * name, ngx_str_t * value)
{
    if(headers->capacity == 0){
        ngx_http_xquic_headers_create_buf(r, headers, NGX_XQUIC_HEADERS_INIT_CAPACITY);
    }

    if(headers->count >= headers->capacity){
        size_t capacity = headers->capacity + NGX_XQUIC_HEADERS_INIT_CAPACITY;
        if(ngx_http_xquic_headers_realloc_buf(r, headers, capacity) < 0){
            return NGX_ERROR;
        }
    }

    xqc_http_header_t * header  = &headers->headers[headers->count++];

    header->name.iov_base = ngx_pcalloc(r->pool, name->len + 1);
    header->name.iov_len = name->len;
    header->value.iov_base = ngx_pcalloc(r->pool, value->len + 1);
    header->value.iov_len = value->len;
    ngx_memcpy(header->name.iov_base, name->data, header->name.iov_len);
    ngx_memcpy(header->value.iov_base, value->data, header->value.iov_len);

    return NGX_OK;
}


ngx_int_t
ngx_http_xquic_save_response_headers(ngx_http_request_t *r)
{
    ngx_list_part_t           *part;
    ngx_table_elt_t           *header;
    ngx_uint_t                 i;
    u_char                     tmp_buf[NGX_XQUIC_TMP_BUF_SIZE];
    ngx_str_t                  name_status = ngx_string(":status");
    ngx_str_t                  name_location = ngx_string("location");
    ngx_str_t                  value;

    /* put in xqstream->resp_headers */
    ngx_http_v3_stream_t *qstream = r->xqstream;
    ngx_http_xquic_headers_initial(&(qstream->resp_headers));

    /* set status & location */
    ngx_snprintf(tmp_buf, sizeof(tmp_buf), "%3D", r->headers_out.status);
    value.data = tmp_buf;
    value.len = 3;
    if (ngx_http_xquic_header_save(r, &(qstream->resp_headers),
            &name_status, &value) != NGX_OK)
    {
        ngx_log_error(NGX_LOG_CRIT, r->connection->log, 0,
                      "|xquic|add response header value fail: \"%V: %V\"|",
                      &name_status, &value);
        return NGX_ERROR;
    }

    if (r->headers_out.location && r->headers_out.location->value.len) {

        if (ngx_http_xquic_header_save(r, &(qstream->resp_headers),
                &name_location, &(r->headers_out.location->value)) != NGX_OK)
        {
            ngx_log_error(NGX_LOG_CRIT, r->connection->log, 0,
                      "|xquic|add response header value fail: \"%V: %V\"|",
                      &name_status, &value);
            return NGX_ERROR;
        }
    }


    part = &r->headers_out.headers.part;
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

        if (header[i].hash == 0) {
            continue;
        }

        if (header[i].key.len > NGX_HTTP_V3_MAX_FIELD) {
            ngx_log_error(NGX_LOG_CRIT, r->connection->log, 0,
                          "too long response header name: \"%V\"",
                          &header[i].key);
            return NGX_ERROR;
        }

        if (header[i].value.len > NGX_HTTP_V3_MAX_FIELD) {
            ngx_log_error(NGX_LOG_CRIT, r->connection->log, 0,
                          "too long response header value: \"%V: %V\"",
                          &header[i].key, &header[i].value);
            return NGX_ERROR;
        }

        if (ngx_http_xquic_header_save(r, &(qstream->resp_headers),
                &header[i].key, &header[i].value) != NGX_OK)
        {
            ngx_log_error(NGX_LOG_CRIT, r->connection->log, 0,
                          "|xquic|add response header value fail: \"%V: %V\"|",
                          &header[i].key, &header[i].value);
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_xquic_header_filter(ngx_http_request_t *r)
{
    u_char                    *p;
    u_char                     addr[NGX_SOCKADDR_STRLEN];
    size_t                     len;
    ngx_int_t                  bytes_sent;
    ngx_str_t                  host, location;
    ngx_uint_t                 port;
    ngx_connection_t          *fc;
    ngx_table_elt_t           *h;
    ngx_http_core_loc_conf_t  *clcf;
    ngx_http_core_srv_conf_t  *cscf;
    struct sockaddr_in        *sin;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6       *sin6;
#endif

    if (!r->xqstream) {
        return ngx_http_next_header_filter(r);
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "|xquic|xquic header filter|");

    if (r->xqstream->engine_inner_closed) {
        ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                            "|xquic|inner closed and fail to send header|");
        return NGX_ERROR;
    }

    if (r->header_sent) {
        return NGX_OK;
    }

    r->header_sent = 1;

    if (r != r->main) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "|xquic|not main request in xquic|");
        return NGX_OK;
    }

    fc = r->connection;

    if (fc->error) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, fc->log, 0, "|xquic|fake connection error|");
        return NGX_ERROR;
    }

    if (r->method == NGX_HTTP_HEAD) {
        r->header_only = 1;
    }

    switch (r->headers_out.status) {

    case NGX_HTTP_OK:
    case NGX_HTTP_PARTIAL_CONTENT:
        break;

    case NGX_HTTP_NO_CONTENT:
        r->header_only = 1;

        ngx_str_null(&r->headers_out.content_type);

        r->headers_out.content_length = NULL;
        r->headers_out.content_length_n = -1;

        r->headers_out.last_modified_time = -1;
        r->headers_out.last_modified = NULL;
        break;

    case NGX_HTTP_NOT_MODIFIED:
        r->header_only = 1;
        break;

    default:
        r->headers_out.last_modified_time = -1;
        r->headers_out.last_modified = NULL;
        break;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (r->headers_out.location && r->headers_out.location->value.len) {

        if (r->headers_out.location->value.data[0] == '/') {
            if (clcf->server_name_in_redirect) {
                cscf = ngx_http_get_module_srv_conf(r, ngx_http_core_module);
                host = cscf->server_name;

            } else if (r->headers_in.server.len) {
                host = r->headers_in.server;

            } else {
                host.len = NGX_SOCKADDR_STRLEN;
                host.data = addr;

                if (ngx_connection_local_sockaddr(fc, &host, 0) != NGX_OK) {
                    return NGX_ERROR;
                }
            }

            switch (fc->local_sockaddr->sa_family) {

#if (NGX_HAVE_INET6)
            case AF_INET6:
                sin6 = (struct sockaddr_in6 *) fc->local_sockaddr;
                port = ntohs(sin6->sin6_port);
                break;
#endif
#if (NGX_HAVE_UNIX_DOMAIN)
            case AF_UNIX:
                port = 0;
                break;
#endif
            default: /* AF_INET */
                sin = (struct sockaddr_in *) fc->local_sockaddr;
                port = ntohs(sin->sin_port);
                break;
            }

            location.len = sizeof("https://") - 1 + host.len
                           + r->headers_out.location->value.len;

            if (clcf->port_in_redirect) {
                port = (port == 443) ? 0 : port;
            } else {
                port = 0;
            }

            if (port) {
                location.len += sizeof(":65535") - 1;
            }

            location.data = ngx_pnalloc(r->pool, location.len);
            if (location.data == NULL) {
                return NGX_ERROR;
            }

            p = ngx_cpymem(location.data, "https", sizeof("https") - 1);

            *p++ = ':'; *p++ = '/'; *p++ = '/';
            p = ngx_cpymem(p, host.data, host.len);

            if (port) {
                p = ngx_sprintf(p, ":%ui", port);
            }

            p = ngx_cpymem(p, r->headers_out.location->value.data,
                              r->headers_out.location->value.len);

            /* update r->headers_out.location->value for possible logging */

            r->headers_out.location->value.len = p - location.data;
            r->headers_out.location->value.data = location.data;
            ngx_str_set(&r->headers_out.location->key, "Location");
        }

        r->headers_out.location->hash = 0;
    }

#if (NGX_HTTP_GZIP)
    if (r->gzip_vary) {
        if (!clcf->gzip_vary) {
            r->gzip_vary = 0;
        }
    }
#endif

    /* server */
    if (r->headers_out.server == NULL) {
        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        h->hash = 1;
        ngx_str_set(&h->key, NGX_HTTP_XQUIC_NAME_SERVER);
        if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
#if (T_NGX_SERVER_INFO)
            ngx_str_set(&h->value, TENGINE_VER);
#else
            ngx_str_set(&h->value, NGINX_VER);
#endif
        } else if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_BUILD) {
#if (T_NGX_SERVER_INFO)
            ngx_str_set(&h->value, TENGINE_VER_BUILD);
#else
            ngx_str_set(&h->value, NGINX_VER_BUILD);
#endif
        } else {
            ngx_str_set(&h->value, TENGINE);
        }
        r->headers_out.server = h;
    }

    /* date */
    if (r->headers_out.date == NULL) {
        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        h->hash = 1;
        ngx_str_set(&h->key, NGX_HTTP_XQUIC_NAME_DATE);
        h->value = ngx_cached_http_time;

        r->headers_out.date = h;
    }

    /* content-type */
    if (r->headers_out.content_type.len) {
        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        h->hash = 1;
        ngx_str_set(&h->key, NGX_HTTP_XQUIC_NAME_CONTENT_TYPE);

        if (r->headers_out.content_type_len == r->headers_out.content_type.len
            && r->headers_out.charset.len)
        {
            len = r->headers_out.content_type.len + sizeof("; charset=") - 1
                  + r->headers_out.charset.len;

            p = ngx_palloc(r->pool, len);
            if (p == NULL) {
                return NGX_ERROR;
            }

            p = ngx_cpymem(p, r->headers_out.content_type.data,
                             r->headers_out.content_type.len);

            p = ngx_cpymem(p, "; charset=", sizeof("; charset=") - 1);

            p = ngx_cpymem(p, r->headers_out.charset.data,
                             r->headers_out.charset.len);

            /* update r->headers_out.content_type for possible logging */

            r->headers_out.content_type.len = len;
            r->headers_out.content_type.data = p - len;
        }


        h->value = r->headers_out.content_type;
    }

    /* content-length */
    if (r->headers_out.content_length == NULL
        && r->headers_out.content_length_n >= 0)
    {
        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        h->hash = 1;
        ngx_str_set(&h->key, NGX_HTTP_XQUIC_NAME_CONTENT_LENGTH);

        h->value.data = ngx_palloc(r->pool, NGX_INT_T_LEN);
        if (h->value.data == NULL) {
            return NGX_ERROR;
        }

        h->value.len = ngx_sprintf(h->value.data, "%O", r->headers_out.content_length_n)
                       - h->value.data;

        r->headers_out.content_length = h;
    }

    /* last-modified */
    if (r->headers_out.last_modified == NULL
        && r->headers_out.last_modified_time != -1)
    {
        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        h->hash = 1;
        ngx_str_set(&h->key, NGX_HTTP_XQUIC_NAME_LAST_MODIFIED);

        h->value.data = ngx_palloc(r->pool, sizeof("Wed, 31 Dec 1986 18:00:00 GMT") - 1);
        if (h->value.data == NULL) {
            return NGX_ERROR;
        }

        h->value.len = ngx_http_time(h->value.data, r->headers_out.last_modified_time)
                       - h->value.data;

        r->headers_out.last_modified = h;
    }

    /* vary: accept-encoding */
#if (NGX_HTTP_GZIP)
    if (r->gzip_vary) {
        h = ngx_list_push(&r->headers_out.headers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        h->hash = 1;
        ngx_str_set(&h->key, NGX_HTTP_XQUIC_NAME_VARY);
        ngx_str_set(&h->value, "Accept-Encoding");

    }
#endif

    if (ngx_http_xquic_save_response_headers(r) != NGX_OK) {
        return NGX_ERROR;
    }

    /* xqc_h3_send_headers may return err, so we should set send_chain before send header */
    fc->send_chain = ngx_http_xquic_send_chain;
    fc->need_last_buf = 1;

    r->xqstream->queued++;

    bytes_sent = ngx_http_xquic_stream_send_header(r->xqstream);
    if (bytes_sent < 0) {
        ngx_log_error(NGX_LOG_WARN, fc->log, 0, "|xquic|quic send header error|");
        return NGX_ERROR;
    }

    r->header_size += bytes_sent;
    fc->sent += bytes_sent;

    return NGX_OK;
}


ngx_chain_t *
ngx_http_xquic_send_chain(ngx_connection_t *c, ngx_chain_t *in, off_t limit)
{
    size_t                   size;
    ssize_t                  n = 0;
    off_t                    send = 0, buf_size = 0;
    ngx_http_request_t      *r;
    ngx_http_v3_stream_t    *h3_stream;
    ngx_chain_t             *last_out = NULL, *last_chain, *cl;
    ngx_buf_t               *buf;

    r = c->data;

    if (r->xqstream->engine_inner_closed) {
        ngx_log_error(NGX_LOG_WARN, c->log, 0,
                            "|xquic|inner closed and fail to send chain|");
        return NGX_CHAIN_ERROR;
    }


    if (limit == 0 || limit > (off_t) (NGX_MAX_SIZE_T_VALUE - ngx_pagesize)) {
        limit = NGX_MAX_SIZE_T_VALUE - ngx_pagesize;
    }

    /* update h3_stream->output_queue here */
    h3_stream = r->xqstream;

    last_chain = h3_stream->output_queue;

    while (last_chain != NULL) {
        if (last_chain->next == NULL) {
            break;
        }
        last_chain = last_chain->next;
    }

    for ( /* void */ ; in; in = in->next) {
        if (in == NULL) {
            break;
        }

        cl = ngx_chain_get_free_buf(h3_stream->request->pool,
                                    &h3_stream->free_bufs);
        if (cl == NULL) {
            goto RETURN_ERROR;
        }

        cl->next = NULL;
        buf = cl->buf;
        buf_size = ngx_buf_size(in->buf);
        
        if (!buf->start) {
            buf->start = ngx_palloc(h3_stream->request->pool,
                                    buf_size);
            if (buf->start == NULL) {
                goto RETURN_ERROR;
            }
        
            buf->end = buf->start + buf_size;
            buf->last = buf->end;
        
            buf->tag = (ngx_buf_tag_t) &ngx_http_xquic_module;
            buf->memory = 1;
        }
        
        buf->pos = buf->start;
        buf->last = buf->pos;
        
        buf->last = ngx_cpymem(buf->last, in->buf->pos, buf_size);
        buf->last_buf = in->buf->last_buf;
        in->buf->pos += buf_size;

        /* update output_queue */
        if (last_chain == NULL) {
            h3_stream->output_queue = cl;
            
        } else {
            last_chain->next = cl;
        }

        last_chain = cl;
        r->xqstream->queued++; /* used to count buffers not sent*/
    }


    last_out = h3_stream->output_queue;
    send = 0;
    
    for ( /* void */ ; last_out; last_out = last_out->next) {

        if (h3_stream->wait_to_write) {
            break;
        }

        if (ngx_buf_special(last_out->buf)) {
            if (last_out->buf->last_buf) {
                ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                               "|xquic|ngx_http_xquic_send_chain|send size %ui|last=%i|",
                               r->xqstream->body_sent, last_out->buf->last_buf);

                n = ngx_http_xquic_stream_send_body(r->xqstream, NULL, 0, 1);

                if (n == NGX_AGAIN) {

                    /* need to send NULL + FIN again */
                    //return in;
                    goto RETURN_EAGAIN;

                } else if (n < 0) {

                    goto RETURN_ERROR;
                }

                r->xqstream->queued--;
                //return NULL;
                goto FINISH;
            }
            continue;
        }

        /* not support sendfile */
        if (!ngx_buf_in_memory(last_out->buf)) {
            ngx_log_error(NGX_LOG_ALERT, c->log, 0,
                          "|xquic|ngx_http_xquic_send_chain|not memory buf|"
                          "t:%d r:%d f:%d %p %p-%p %p %O-%O|",
                          last_out->buf->temporary,
                          last_out->buf->recycled,
                          last_out->buf->in_file,
                          last_out->buf->start,
                          last_out->buf->pos,
                          last_out->buf->last,
                          last_out->buf->file,
                          last_out->buf->file_pos,
                          last_out->buf->file_last);

            ngx_debug_point();

            goto RETURN_ERROR;
        }

        if (send >= limit) {
            break;
        }

        size = last_out->buf->last - last_out->buf->pos;

        n = ngx_http_xquic_stream_send_body(r->xqstream,
                                             last_out->buf->pos, size,
                                             last_out->buf->last_buf);

        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                       "|xquic|ngx_http_xquic_send_chain|send tot_size %ui, size %O, n=%z|last=%i|",
                       r->xqstream->body_sent, size, n, last_out->buf->last_buf);


        if (n < 0) {
            if (n == NGX_AGAIN) {
                h3_stream->wait_to_write = 1;
            }
        
            break;
        }

        c->sent += n;
        send += n;
        size -= n;
        last_out->buf->pos += n;  /* in->buf->pos = in->buf->last */

        if (size != 0) {
            /* xquic inner send buffer full will cause n < size */

            break;
        } else {
            /* finish sending this buffer */
            r->xqstream->queued--;
        }
    }

RETURN_EAGAIN:

FINISH:

    r->xqstream->output_queue = last_out;

    return in;

RETURN_ERROR:

    r->xqstream->output_queue = last_out;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "|xquic|ngx_http_xquic_send_chain|send tot_size %ui, size %O, n=%z|chain error|", 
                   r->xqstream->body_sent, send, n);

    return NGX_CHAIN_ERROR;
}

ngx_int_t
ngx_http_xquic_filter_init(ngx_conf_t *cf)
{
    ngx_http_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_xquic_header_filter;


    return NGX_OK;
}

