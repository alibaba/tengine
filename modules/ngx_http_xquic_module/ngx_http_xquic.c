/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

/**  
 * for http v3 connection
 */

#include <ngx_http_xquic.h>
#include <ngx_http_xquic_module.h>
#include <ngx_http_v3_stream.h>
#include <ngx_xquic_recv.h>
#include <ngx_xquic.h>

#include <sys/socket.h>
#include <netinet/udp.h>

#if (T_NGX_HAVE_XUDP)
#include <ngx_xudp.h>
#endif


#ifdef T_NGX_HTTP_HAVE_LUA_MODULE
#include <ngx_http_lua_ssl_certby.h>
extern ngx_module_t ngx_http_lua_module;
#endif

ngx_int_t
ngx_http_v3_conn_check_concurrent_cnt(ngx_http_xquic_main_conf_t *qmcf)
{
    /* limit not configured */
    if (qmcf->max_quic_concurrent_connection_cnt == NGX_CONF_UNSET_UINT) {
        return NGX_OK;
    }

    /* decline if limitation is set and reached max connection count limit */
    ngx_atomic_uint_t quic_concurrent_conn_cnt = *ngx_stat_quic_concurrent_conns;
    if (quic_concurrent_conn_cnt >= qmcf->max_quic_concurrent_connection_cnt) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "|xquic|reached max connection limit"
                      "|limit:%ui|cnt:%ui|", qmcf->max_quic_concurrent_connection_cnt, quic_concurrent_conn_cnt);
        return NGX_DECLINED;
    }

    return NGX_OK;
}

ngx_int_t
ngx_http_v3_conn_check_cps(ngx_http_xquic_main_conf_t *qmcf)
{
    /* limit not configured */
    if (qmcf->max_quic_cps == NGX_CONF_UNSET_UINT) {
        return NGX_OK;
    }

    /* check max cps limit */
    ngx_atomic_uint_t quic_cps_nexttime = *ngx_stat_quic_cps_nexttime;
    if (ngx_current_msec <= quic_cps_nexttime) {
        /* still in current stat round, check cps limit, decline if reached max cps limit */
        if (*ngx_stat_quic_cps >= qmcf->max_quic_cps) {
            ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "|xquic|reached max cps limit"
                    "|limit:%ui|now:%ui|next_time:%ui|", qmcf->max_quic_cps, ngx_current_msec, quic_cps_nexttime);
            return NGX_DECLINED;
        }

    } else {
        /* start a new stat round */
        ngx_atomic_cmp_set(ngx_stat_quic_cps_nexttime,
            *ngx_stat_quic_cps_nexttime, ngx_current_msec + 1000);
        ngx_atomic_cmp_set(ngx_stat_quic_cps, *ngx_stat_quic_cps, 0);
    }

    return NGX_OK;
}

int 
ngx_xquic_conn_accept(xqc_engine_t *engine, xqc_connection_t *conn, 
    const xqc_cid_t * cid, void * user_data)
{
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                    "|xquic|ngx_xquic_server_conn_accept|dcid=%s|", xqc_dcid_str(cid));

    if (user_data == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
                      "|xquic|ngx_xquic_server_conn_accept|user_data is NULL|dcid=%s|", xqc_dcid_str(cid));
        return XQC_ERROR;
    }

    ngx_connection_t *lc = (ngx_connection_t *)user_data;

    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);

    /* check connection limit */
    if (ngx_http_v3_conn_check_concurrent_cnt(qmcf) != NGX_OK
        || ngx_http_v3_conn_check_cps(qmcf) != NGX_OK)
    {
        (void) ngx_atomic_fetch_add(ngx_stat_quic_conns_refused, 1);
        return XQC_ERROR;
    }
  

    socklen_t peer_addrlen; 
    socklen_t local_addrlen;
    struct sockaddr_storage peer_addr;
    struct sockaddr_storage local_addr;
    if (xqc_conn_get_peer_addr(conn, (struct sockaddr *)(&peer_addr), sizeof(peer_addr), &peer_addrlen) != XQC_OK) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                    "|xquic|ngx accept copy peer addr fail|");
        return NGX_ERROR;
    }
    if (xqc_conn_get_local_addr(conn, (struct sockaddr *)(&local_addr), sizeof(local_addr), &local_addrlen) != XQC_OK) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                    "|xquic|ngx accept copy local addr fail|");
        return NGX_ERROR;
    }

    /* init user data */
    ngx_http_xquic_connection_t* qc = ngx_http_v3_create_connection(
                            (ngx_connection_t *)lc, cid, 
                            (struct sockaddr *)&local_addr, local_addrlen,
                            (struct sockaddr *)&peer_addr, peer_addrlen,
                            qmcf->xquic_engine);
    if (qc == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                    "|xquic|ngx_http_v3_create_connection fail|");
        return NGX_ERROR;
    }

    xqc_conn_set_transport_user_data(conn, qc);
    /* temporarily set the alp user_data of conn, will overwrite when h3_conn_create_notify callback triggers */
    xqc_conn_set_alp_user_data(conn, qc);

    /* add connection count and cps statistics */
    (void) ngx_atomic_fetch_add(ngx_stat_quic_conns, 1);
    (void) ngx_atomic_fetch_add(ngx_stat_quic_cps, 1);
    (void) ngx_atomic_fetch_add(ngx_stat_quic_concurrent_conns, 1);

    return NGX_OK;
}

void
ngx_xquic_conn_refuse(xqc_engine_t *engine, xqc_connection_t *conn, 
    const xqc_cid_t *cid, void *user_data)
{
    ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                    "|xquic|ngx_xquic_server_conn_refuse|scid=%s|", xqc_dcid_str(cid));

    uint64_t err = xqc_conn_get_errno(conn);

    ngx_http_xquic_connection_t *qc = (ngx_http_xquic_connection_t *)user_data;
    if (qc == NULL) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                    "|xquic|user_data is NULL|cid:%s|", xqc_dcid_str(cid));
        return;
    }

    ngx_http_v3_finalize_connection(qc, err);

    (void) ngx_atomic_fetch_add(ngx_stat_quic_concurrent_conns, -1);
}

ngx_int_t
ngx_http_find_virtual_server_inner(ngx_connection_t *c,
    ngx_http_virtual_names_t *virtual_names, ngx_str_t *host,
    ngx_http_request_t *r, ngx_http_core_srv_conf_t **cscfp);

xqc_int_t
ngx_http_v3_cert_cb(const char *sni, void **chain,
    void **cert, void **key, void *conn_user_data)
{
    ngx_int_t                       ret;
    int                             ssl_ret;
    ngx_str_t                       host;
    ngx_connection_t               *c;
    ngx_http_connection_t          *hc;
    ngx_http_ssl_srv_conf_t        *sscf;
    ngx_http_core_srv_conf_t       *cscf;
    ngx_http_xquic_connection_t    *qc;
    STACK_OF(X509)                 *cert_chain;
    X509                           *certificate;
    EVP_PKEY                       *private_key;

    if (NULL == sni || NULL == conn_user_data) {
        return -XQC_EPARAM;
    }

    host.data = (u_char *)sni;
    host.len = strlen(sni);

    /* default http connection */
    qc = (ngx_http_xquic_connection_t *)conn_user_data;
    hc = qc->http_connection;
    c = qc->connection;

#ifdef T_NGX_HTTP_HAVE_LUA_MODULE
    ngx_http_lua_srv_conf_t *lscf = NULL;

    lscf = ngx_http_get_module_srv_conf(hc->conf_ctx, ngx_http_lua_module);
    if (lscf != NULL && lscf->srv.ssl_cert_src.len)  {
        ngx_ssl_conn_t *ssl_conn = qc->ssl_conn;
        
        ngx_http_lua_ssl_cert_handler(ssl_conn, NULL);
        *chain = NULL;
        *cert = NULL;
        *key = NULL;

        return XQC_OK;
    }
#endif

    /* The ngx_http_find_virtual_server() function requires ngx_http_connection_t in c->data */
    c->data = hc;

    /*
     * get the server core conf by sni, this is useful when multiple server
     * block listen on the same port. but useless when there is noly a single
     * server block
    */
   ret = ngx_http_find_virtual_server_inner(c,
            hc->addr_conf->virtual_names, &host, NULL, &cscf);
   c->data = qc;

    if (ret == NGX_OK) {
        hc->ssl_servername = ngx_palloc(c->pool, sizeof(ngx_str_t));
        if (hc->ssl_servername == NULL) {
            ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0,
                        "|xquic|crete ssl_servername fail|");

            return XQC_ERROR;
        }

        /* get server config */
        *hc->ssl_servername = host;
        hc->conf_ctx = cscf->ctx;

    } else {
        /* try to get ssl config from the default connection */
        ngx_log_error(NGX_LOG_INFO, ngx_cycle->log, 0,
                     "|xquic|can't find virtual server, use default server|");
    }

    /* get http ssl config */
    sscf = ngx_http_get_module_srv_conf(hc->conf_ctx, ngx_http_ssl_module);
    if (NULL == sscf || NULL == sscf->ssl.ctx) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                    "|xquic|CFG or CTX not found||sni:%s|", sni);
        return XQC_ERROR;
    }

    ssl_ret = SSL_CTX_get0_chain_certs(sscf->ssl.ctx, &cert_chain);
    if (ssl_ret != 1) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                    "|xquic|get chain certificate fail|err=%i", ssl_ret);
        return XQC_ERROR;
    }

    certificate = SSL_CTX_get0_certificate(sscf->ssl.ctx);
    private_key = SSL_CTX_get0_privatekey(sscf->ssl.ctx);

    if (NULL == certificate) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                    "|xquic|get certificate fail|");
        return XQC_ERROR;
    }

    if (NULL == private_key) {
        /*  keyless server */
        ngx_log_error(NGX_LOG_INFO, ngx_cycle->log, 0,
                    "|xquic|get private key fail, \"ssl_keyless off\" config "
                    "lost|sni:%s", sni);
        return XQC_ERROR;
    }

    *chain = cert_chain;
    *cert = certificate;
    *key = private_key;

    return XQC_OK;
}

int 
ngx_http_v3_conn_create_notify(xqc_h3_conn_t *h3_conn, 
    const xqc_cid_t *cid, void *user_data)
{
    ngx_connection_t               *c;

    /* we set alp user_data when accept connection */
    ngx_http_xquic_connection_t *user_conn = (ngx_http_xquic_connection_t *) user_data;
    user_conn->ssl_conn = (ngx_ssl_conn_t *) xqc_h3_conn_get_ssl(h3_conn);

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                    "|xquic|ngx_http_v3_conn_create_notify|%p|", user_conn->engine);

    xqc_h3_conn_set_user_data(h3_conn, user_conn);

    c = user_conn->connection;

    if (SSL_set_ex_data(user_conn->ssl_conn, ngx_ssl_connection_index, c) == 0)
    {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "|xquic|SSL_set_ex_data() failed|");
        return XQC_ERROR;
    }
    
    c->xquic_conn = 1;

    ngx_ssl_connection_t *p_ssl = ngx_pcalloc(c->pool, sizeof(ngx_ssl_connection_t));
    if (p_ssl ==  NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "|xquic|alloc ngx_ssl_connection_t failed|");
        return XQC_ERROR;
    }
    p_ssl->connection = user_conn->ssl_conn;
    c->ssl = p_ssl;

    return NGX_OK;
}


int 
ngx_http_v3_conn_close_notify(xqc_h3_conn_t *h3_conn, 
    const xqc_cid_t *cid, void *user_data) 
{
    uint64_t err = xqc_h3_conn_get_errno(h3_conn);

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                    "|xquic|ngx_http_v3_conn_close_notify|err=%i|", err);

    if (err != H3_NO_ERROR) {
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                    "|xquic|ngx_http_v3_conn_close|err=%i|", err);
    }

    ngx_http_xquic_connection_t *h3c = (ngx_http_xquic_connection_t *)user_data;
    ngx_http_v3_finalize_connection(h3c, err);

    (void) ngx_atomic_fetch_add(ngx_stat_quic_concurrent_conns, -1);

    return NGX_OK;
}


void 
ngx_http_v3_conn_handshake_finished(xqc_h3_conn_t *h3_conn, void *user_data)
{
    ngx_http_xquic_connection_t *user_conn = (ngx_http_xquic_connection_t *) user_data;

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                    "|xquic|ngx_http_v3_conn_handshake_finished|dcid=%s|", 
                    xqc_dcid_str(&user_conn->dcid));


    /* TODO */
}


void
ngx_http_v3_conn_update_cid_notify(xqc_connection_t *conn, const xqc_cid_t *retire_cid,
    const xqc_cid_t *new_cid, void *conn_user_data)
{
    ngx_http_xquic_connection_t *user_conn = (ngx_http_xquic_connection_t *) conn_user_data;

    ngx_log_error(NGX_LOG_INFO, ngx_cycle->log, 0, 
                "|xquic|ngx_http_v3_conn_update_cid_notify|old_cid=%s|new_cid:%s|", 
                xqc_dcid_str(retire_cid), xqc_scid_str(new_cid));

    memcpy(&user_conn->dcid, new_cid, sizeof(xqc_cid_t));
}


ngx_int_t
ngx_http_v3_read_request_body(ngx_http_request_t *r)
{
    off_t                      len;
    ngx_http_v3_stream_t      *stream;
    ngx_http_request_body_t   *rb;
    ngx_http_core_loc_conf_t  *clcf;
    ngx_buf_t                 *buf;
    ngx_int_t                  rc;
    ngx_connection_t          *fc;

    stream = r->xqstream;
    rb = r->request_body;
    fc = r->connection;

    ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                  "|xquic|ngx_http_v3_read_request_body|");

    if (stream->skip_data) {
        r->request_body_no_buffering = 0;
        rb->post_handler(r);
        return NGX_OK;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    len = r->headers_in.content_length_n;

    if (r->request_body_no_buffering && !stream->in_closed) {

        if (len < 0 || len > (off_t) clcf->client_body_buffer_size) {
            len = clcf->client_body_buffer_size;
        }

        rb->buf = ngx_create_temp_buf(r->pool, (size_t) len);

    } else if (len >= 0 && len <= (off_t) clcf->client_body_buffer_size
               && !r->request_body_in_file_only)
    {
        rb->buf = ngx_create_temp_buf(r->pool, (size_t) len);

    } else {
        rb->buf = ngx_create_temp_buf(r->pool, (size_t) clcf->client_body_buffer_size);
        if (rb->buf != NULL) {
            rb->buf->sync = 1;
        }
    }

    if (rb->buf == NULL) {
        stream->skip_data = 1;
        ngx_log_error(NGX_LOG_WARN, fc->log, 0,
                      "|xquic|ngx_http_v3_read_request_body|create request_body error|");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    rb->rest = 1;

    buf = stream->body_buffer;

    if (stream->in_closed) {
        r->request_body_no_buffering = 0;

        if (buf) {
            rc = ngx_http_v3_process_request_body(r, buf->pos, buf->last - buf->pos, 1);

            ngx_pfree(r->pool, buf->start);

            return rc;
        }

        return ngx_http_v3_process_request_body(r, NULL, 0, 1);
    }

    if (buf) {
        rc = ngx_http_v3_process_request_body(r, buf->pos, buf->last - buf->pos, 0);

        ngx_pfree(r->pool, buf->start);

        if (rc != NGX_OK) {
            stream->skip_data = 1;
            return rc;
        }
    } else {
        ngx_add_timer(r->connection->read, clcf->client_body_timeout);
    }

    r->read_event_handler = ngx_http_v3_read_client_request_body_handler;
    r->write_event_handler = ngx_http_request_empty_handler;

    return NGX_AGAIN;
}


ngx_int_t
ngx_http_v3_read_unbuffered_request_body(ngx_http_request_t *r)
{
    ngx_buf_t                   *buf;
    ngx_int_t                    rc;
    ngx_connection_t            *fc;
    ngx_http_v3_stream_t        *stream;

    stream = r->xqstream;
    fc = r->connection;

    ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                  "|ngx_http_v3_read_unbuffered_request_body|");

    if (fc->read->timedout) {
        stream->skip_data = 1;
        fc->timedout = 1;

        return NGX_HTTP_REQUEST_TIME_OUT;
    }

    if (fc->error) {
        stream->skip_data = 1;
        return NGX_HTTP_BAD_REQUEST;
    }

    rc = ngx_http_v3_filter_request_body(r);

    if (rc != NGX_OK) {
        stream->skip_data = 1;
        return rc;
    }

    if (!r->request_body->rest) {
        return NGX_OK;
    }

    if (r->request_body->busy != NULL) {
        return NGX_AGAIN;
    }

    buf = r->request_body->buf;

    buf->pos = buf->last = buf->start;

    return NGX_AGAIN;
}


ngx_int_t
ngx_http_v3_process_request_body(ngx_http_request_t *r, u_char *pos,
    size_t size, ngx_uint_t last)
{
    ngx_buf_t                 *buf;
    ngx_int_t                  rc;
    ngx_connection_t          *fc;
    ngx_http_request_body_t   *rb;
    ngx_http_core_loc_conf_t  *clcf;

    fc = r->connection;
    rb = r->request_body;
    buf = rb->buf;

    ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                  "|xquic|ngx_http_v3_process_request_body|size:%O, last:%O|", size, last);

    if (size) {
        if (buf->sync) {
            buf->pos = buf->start = pos;
            buf->last = buf->end = pos + size;

            r->request_body_in_file_only = 1;

        } else {
            if (size > (size_t) (buf->end - buf->last)) {
                ngx_log_error(NGX_LOG_INFO, fc->log, 0,
                              "|xquic|ngx_http_v3_process_request_body"
                              "|client intended to send body data larger than declared|%O > %O|",
                              size, buf->end - buf->last);

                return NGX_HTTP_BAD_REQUEST;
            }

            buf->last = ngx_cpymem(buf->last, pos, size);

            ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                          "|xquic|ngx_http_v3_process_request_body|size:%O|", size);
        }
    }

    if (last) {
        ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                      "|xquic|ngx_http_v3_process_request_body|last buf|");

        rb->rest = 0;

        if (fc->read->timer_set) {
            ngx_del_timer(fc->read);
        }

        if (r->request_body_no_buffering) {
            ngx_post_event(fc->read, &ngx_posted_events);
            ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                          "|xquic|ngx_http_v3_process_request_body|ngx_post_event|");
            return NGX_OK;
        }

        rc = ngx_http_v3_filter_request_body(r);

        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                          "|xquic|ngx_http_v3_process_request_body"
                          "|ngx_http_v3_filter_request_body error:%O|", rc);
            return rc;
        }

        if (buf->sync) {
            /* prevent reusing this buffer in the upstream module */
            rb->buf = NULL;
        }

        if (r->headers_in.chunked) {
            r->headers_in.content_length_n = rb->received;
        }

        r->read_event_handler = ngx_http_block_reading;
        ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                      "|xquic|ngx_http_v3_process_request_body|post_handler|");

        rb->post_handler(r);

        return NGX_OK;
    }

    if (buf->pos == buf->last) {
        return NGX_OK;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    ngx_add_timer(fc->read, clcf->client_body_timeout);

    if (r->request_body_no_buffering) {
        ngx_post_event(fc->read, &ngx_posted_events);
        ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                      "|xquic|ngx_http_v3_process_request_body|ngx_post_event|");
        return NGX_OK;
    }

    if (buf->sync) {
        return ngx_http_v3_filter_request_body(r);
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_v3_filter_request_body(ngx_http_request_t *r)
{
    ngx_buf_t                 *b, *buf;
    ngx_int_t                  rc;
    ngx_chain_t               *cl;
    ngx_http_request_body_t   *rb;
    ngx_connection_t          *fc;
    ngx_http_core_loc_conf_t  *clcf;
    ngx_uint_t                 fin;
//    size_t                     size;

    rb = r->request_body;
    fc = r->connection;
    buf = rb->buf;
    fin = rb->rest == 0 ? 1 : 0;

    ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                  "|xquic|ngx_http_v3_filter_request_body|size:%O, fin:%O|", buf->last - buf->pos, fin);

    if (buf->pos == buf->last && rb->rest) {
        cl = NULL;
        goto update;
    }

    cl = ngx_chain_get_free_buf(r->pool, &rb->free);
    if (cl == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    b = cl->buf;

    ngx_memzero(b, sizeof(ngx_buf_t));

    if (buf->pos != buf->last) {
        r->request_length += buf->last - buf->pos;
        rb->received += buf->last - buf->pos;

        if (r->headers_in.content_length_n != -1) {
            if (rb->received > r->headers_in.content_length_n) {
                ngx_log_error(NGX_LOG_INFO, fc->log, 0,
                              "|xquic|ngx_http_v3_filter_request_body"
                              "|client intended to send body data larger than declared|:%O > %O|",
                              rb->received, r->headers_in.content_length_n);

                return NGX_HTTP_BAD_REQUEST;
            }

        } else {
            clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

            if (clcf->client_max_body_size
                && rb->received > clcf->client_max_body_size)
            {
                ngx_log_error(NGX_LOG_ERR, fc->log, 0,
                              "|xquic|ngx_http_v3_filter_request_body"
                              "|client intended to send too large chunked body:%O > %O|",
                              rb->received, clcf->client_max_body_size);

                return NGX_HTTP_REQUEST_ENTITY_TOO_LARGE;
            }
        }

        b->temporary = 1;
        b->pos = buf->pos;
        b->last = buf->last;
        b->start = b->pos;
        b->end = b->last;
    }

    buf->pos = buf->last = buf->start;
    ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                  "|xquic|ngx_http_v3_filter_request_body|received:%O|", rb->received);

    if (!rb->rest) {
        if (r->headers_in.content_length_n != -1
            && r->headers_in.content_length_n != rb->received)
        {
            ngx_log_error(NGX_LOG_INFO, fc->log, 0,
                          "|xquic|ngx_http_v3_filter_request_body"
                          "|client prematurely closed stream:only %O out of %O bytes of request body received|",
                          rb->received, r->headers_in.content_length_n);

            return NGX_HTTP_BAD_REQUEST;
        }

        b->last_buf = 1;
    }

    b->tag = (ngx_buf_tag_t) &ngx_http_v3_filter_request_body;
    b->flush = r->request_body_no_buffering;

update:

    rc = ngx_http_top_request_body_filter(r, cl);

    ngx_chain_update_chains(r->pool, &rb->free, &rb->busy, &cl,
                            (ngx_buf_tag_t) &ngx_http_v3_filter_request_body);

    return rc;
}


void
ngx_http_v3_read_client_request_body_handler(ngx_http_request_t *r)
{
    ngx_connection_t  *fc;

    fc = r->connection;

    ngx_log_error(NGX_LOG_DEBUG, fc->log, 0,
                  "|xquic|ngx_http_v3_read_client_request_body_handler|");

    if (fc->read->timedout) {
        ngx_log_error(NGX_LOG_INFO, fc->log, NGX_ETIMEDOUT,
                      "|xquic|ngx_http_v3_read_client_request_body_handler|client timed out|");

        fc->timedout = 1;
        r->xqstream->skip_data = 1;

        ngx_http_finalize_request(r, NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    if (fc->error) {
        ngx_log_error(NGX_LOG_INFO, fc->log, 0,
                      "|xquic|ngx_http_v3_read_client_request_body_handler|client prematurely closed stream|");

        r->xqstream->skip_data = 1;

        ngx_http_finalize_request(r, NGX_HTTP_CLIENT_CLOSED_REQUEST);
        return;
    }
}


static ngx_int_t
ngx_http_xquic_connect(ngx_http_xquic_connection_t *qc, ngx_connection_t *lc)
{
    int                              value;
    u_char                           text[NGX_SOCKADDR_STRLEN];
    ngx_str_t                        addr;
    ngx_log_t                       *log;
    ngx_event_t                     *rev, *wev;
    ngx_socket_t                     s;
    ngx_listening_t                 *ls;
    ngx_connection_t                *c;
    ngx_http_xquic_main_conf_t      *qmcf;

    ls = lc->listening;

    switch(qc->local_sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
    case AF_INET6:
        s = ngx_socket(AF_INET6, SOCK_DGRAM, 0);
        break;
#endif
    default: /* AF_INET */
        s = ngx_socket(AF_INET, SOCK_DGRAM, 0);
        break;
    }

    if (s == (ngx_socket_t) -1) {
        ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                      "xquic" ngx_socket_n " %V failed",
                      &ls->addr_text);
        return NGX_ERROR;
    }

    c = ngx_get_connection(s, lc->log);

    if (c == NULL) {
        if (ngx_close_socket(s) == -1) {
            ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                          "quic" ngx_close_socket_n " failed");
        }

        return NGX_ERROR;
    }

    value = 1;
    if (setsockopt(s, SOL_SOCKET, SO_REUSEADDR,
                   (const void *) &value, sizeof(int))
        == -1)
    {
        ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                      "|xquic| setsockopt(SO_REUSEADDR) %V failed|",
                       &ls->addr_text);

        goto failed;
    }

    qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);

    if (qmcf->new_udp_hash == 1 &&
        setsockopt(s, SOL_UDP, 200,
                   (const void *) &value, sizeof(int))
        == -1)
    {
        ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                      "|xquic| setsockopt(new-udp-hash) %V failed|",
                      &ls->addr_text);
    }

    int socket_sndbuf = qmcf->socket_sndbuf;
    if (setsockopt(s, SOL_SOCKET, SO_SNDBUF,
                   (const void *) &(socket_sndbuf), sizeof(int))
        == -1)
    {
        ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                      "|xquic| setsockopt(SO_SNDBUF, %d) %V failed, ignored|",
                      qmcf->socket_sndbuf, &ls->addr_text);
    }    

    int socket_rcvbuf = qmcf->socket_rcvbuf;
    if (setsockopt(s, SOL_SOCKET, SO_RCVBUF,
                   (const void *) &(socket_rcvbuf), sizeof(int))
        == -1)
    {
        ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                      "|xquic| setsockopt(SO_RCVBUF, %d) %V failed, ignored|",
                      qmcf->socket_rcvbuf, &ls->addr_text);
    }

    if (ngx_nonblocking(s) == -1) {
        ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                      "xquic" ngx_nonblocking_n " failed");

        goto failed;
    }

    if (bind(s, qc->local_sockaddr, qc->local_socklen) == -1) {
        addr.data = text;
        addr.len = ngx_sock_ntop(qc->local_sockaddr, qc->local_socklen,
                                 text, NGX_SOCKADDR_STRLEN, 1);
        ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                      "|xquic|bind() to %V failed|", &addr);

        goto failed;
    }

    if (connect(s, qc->peer_sockaddr, qc->peer_socklen) == -1) {
        addr.data = text;
        addr.len = ngx_sock_ntop(qc->peer_sockaddr, qc->peer_socklen, text,
                                 NGX_SOCKADDR_STRLEN, 1);

        ngx_log_error(NGX_LOG_EMERG, lc->log, ngx_socket_errno,
                      "|xquic|connect() to %V failed|", &addr);

        goto failed;
    }

    log = ngx_palloc(qc->pool, sizeof(ngx_log_t));
    if (log == NULL) {
        goto failed;
    }

    *log = ls->log;

    log->data = NULL;
    log->handler = NULL;

    c->log = log;
    c->type = SOCK_DGRAM;

    c->listening = ls;
    c->pool = qc->pool;
    c->sockaddr = qc->peer_sockaddr;
    c->socklen = qc->peer_socklen;
    c->local_sockaddr = qc->local_sockaddr;
    c->local_socklen = qc->local_socklen;
    c->addr_text = qc->addr_text;
    c->ssl = NULL;
#if (NGX_SLIGHT_SSL)
    c->s_ssl = NULL;
#endif

    rev = c->read;
    wev = c->write;

    wev->ready = 1;

    rev->log = c->log;
    wev->log = c->log;

    c->number = ngx_atomic_fetch_add(ngx_connection_counter, 1);

#if (NGX_DEBUG)
    {
        if (lc->log->log_level & NGX_LOG_DEBUG_HTTP) {
            addr.data = text;
            addr.len = ngx_sock_ntop(qc->peer_sockaddr, qc->peer_socklen, text,
                                     NGX_SOCKADDR_STRLEN, 1);
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, lc->log, 0,
                           "|xquic|create connect fd %d to %V|", s, &addr);
        }
    }
#endif

    qc->connection = c;

    return NGX_OK;

failed:
    ngx_close_connection(c);
    return NGX_ERROR;
}


static u_char *
ngx_http_xquic_log_error(ngx_log_t *log, u_char *buf, size_t len)
{
    u_char              *p;
    ngx_http_request_t  *r;
    ngx_http_log_ctx_t  *ctx;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    ctx = log->data;

    p = ngx_snprintf(buf, len, ", xquic connection, client: %V", &ctx->connection->addr_text);
    len -= p - buf;

    r = ctx->request;

    if (r) {
        return r->log_handler(r, ctx->current_request, p, len);

    } else {
        p = ngx_snprintf(p, len, ", server: %V",
                         &ctx->connection->listening->addr_text);
    }

    return p;
}


void
ngx_http_xquic_session_process_packet(ngx_http_xquic_connection_t *qc, 
    ngx_xquic_recv_packet_t *packet, size_t recv_size)
{
    uint64_t recv_time = ngx_xquic_get_time();
    ngx_log_error(NGX_LOG_DEBUG, qc->connection->log, 0,
                    "|xquic|xqc_server_read_handler recv_size=%zd, recv_time=%llu, recv_total=%d|", 
                    recv_size, recv_time, ++qc->recv_packets_num);

    if (xqc_engine_packet_process(qc->engine, (u_char *)packet->buf, recv_size,
                                  qc->local_sockaddr, qc->local_socklen,
                                  qc->peer_sockaddr, qc->peer_socklen,
                                  (xqc_msec_t) recv_time, NULL) != 0) 
    {
        ngx_log_error(NGX_LOG_DEBUG, qc->connection->log, 0,
                    "|xquic|xqc_server_read_handler: packet process err|");
        return;
    }
}


/**
 * used to recv udp packets
 */
static void
ngx_http_xquic_read_handler(ngx_event_t *rev)
{
    ssize_t                        n;
    ngx_connection_t              *c, *lc;
    ngx_xquic_recv_packet_t        packet;
    ngx_http_xquic_connection_t   *qc;

    c = rev->data;
    qc = c->data;

    if (rev->timedout) {
        ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT, "|xquic|client timed out|");
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "|xquic|connection read handler|");

    do {
        n = ngx_xquic_recv(c, packet.buf, sizeof(packet.buf));

        if (n == NGX_AGAIN) {
            break;
        } else if (n == 0) {
            ngx_log_error(NGX_LOG_WARN, c->log, 0,
                          "|xquic|ngx_xquic_recv 0|");
            break;
        } else if (n < 0) {
            ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT,
                        "|xquic|recv = %z|", n);
 

            if (n == NGX_DONE && qc->processing == 0) {
                ngx_http_v3_connection_error(qc, NGX_XQUIC_CONN_NO_ERR, "client request done");
            } else {
                ngx_http_v3_connection_error(qc, NGX_XQUIC_CONN_RECV_ERR, "read packet error");
            }

            goto finish_recv;
        }

        packet.len = n;

        /* check QUIC magic bit */
        if (!NGX_XQUIC_CHECK_MAGIC_BIT(packet.buf)) {
            ngx_log_debug(NGX_LOG_WARN, c->log, 0,
                          "|xquic|invalid packet head|");
            continue;
        }

        /* get dcid here */
        ngx_xquic_packet_get_cid(&packet, qc->engine);

        //ngx_xquic_server_session_process_packet(qc, &packet, n);

        if (xqc_cid_is_equal(&(qc->dcid), &(packet.xquic.dcid)) != NGX_OK) {
            ngx_log_error(NGX_LOG_NOTICE, c->log, 0, "|xquic|ngx_http_xquic_read_handler: "
                          "packet connectionID %s != %s (qc connection ID), processing: %d|",
                          xqc_dcid_str(&packet.xquic.dcid), xqc_scid_str(&qc->dcid), qc->processing);

            if (qc->processing == 0) {
                lc = c->listening->connection;

                ngx_memcpy(&packet.sockaddr, qc->peer_sockaddr, qc->peer_socklen);
                packet.socklen = qc->peer_socklen;
                ngx_memcpy(&packet.local_sockaddr, qc->local_sockaddr, qc->local_socklen);
                packet.local_socklen = qc->local_socklen;

                /* ngx_http_v3_finalize_connection(qc, NGX_XQUIC_CONN_HANDSHAKE_ERR); */
                ngx_xquic_dispatcher_process_packet(lc, &packet);

                return;
            }
			//from the same source address
			//if not client retry handshake, just drop the packets with different cid
        } else {
            ngx_http_xquic_session_process_packet(qc, &packet, n);
        }

        if (qc->xquic_off) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "xquic not allow");
        
            ngx_http_v3_connection_error(qc, NGX_XQUIC_CONN_NO_ERR, "xquic not allow");
        
            return;
        }

    } while (rev->ready);

finish_recv:
    xqc_engine_finish_recv(qc->engine);
}


/**
 * connection readmsg_handler used to recv udp packets
 */
static void
ngx_http_xquic_readmsg_handler(ngx_event_t *rev)
{
    ngx_int_t                       rc;
    ngx_connection_t               *c, *lc;
    ngx_http_xquic_connection_t    *qc;
    static ngx_xquic_recv_packet_t  packet;
    ngx_http_xquic_main_conf_t     *qmcf;


    c = rev->data;
    qc = c->data;
    lc = c->listening->connection;

    qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);

    if (rev->timedout) {
        ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT, "|xquic| client readmsg timed out|");
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "|xquic| connection readmsg handler|");

    for ( ;; ) {
        packet.local_socklen = qc->local_socklen;
        ngx_memcpy(&packet.local_sockaddr, qc->local_sockaddr, qc->local_socklen);

        rc = ngx_xquic_recv_packet(c, &packet, rev->log, qmcf->xquic_engine);

        if (rc == NGX_AGAIN) {
            break;
        } else if (rc < 0) {


            if (rc == NGX_DONE && qc->processing == 0) {
                ngx_http_v3_connection_error(qc, NGX_XQUIC_CONN_NO_ERR, "client request done");
            } else {
                ngx_http_v3_connection_error(qc, NGX_XQUIC_CONN_RECV_ERR, "read packet error");
            }

            goto finish_recv;
        }

        ngx_xquic_dispatcher_process_packet(lc, &packet);

        if (qc->xquic_off) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "xquic not allow");
        
            ngx_http_v3_connection_error(qc, NGX_XQUIC_CONN_NO_ERR, "xquic not allow");
        
            return;
        }
    }

    rev->ready = 0;
    rev->handler = ngx_http_xquic_read_handler;

finish_recv:
    xqc_engine_finish_recv(qmcf->xquic_engine);
}


/**
 * init http v3 connection
 */
static ngx_int_t
ngx_http_xquic_init_connection(ngx_http_xquic_connection_t *qc)
{
    ngx_uint_t                   i;
    ngx_http_port_t             *port;
    ngx_connection_t            *c;
    ngx_http_log_ctx_t          *ctx;
    struct sockaddr_in          *sin;
    ngx_http_in_addr_t          *addr;
#if (NGX_HAVE_INET6)
    ngx_http_in6_addr_t         *addr6;
    struct sockaddr_in6         *sin6;
#endif
    ngx_http_connection_t       *hc;


    hc = ngx_pcalloc(qc->pool, sizeof(ngx_http_connection_t));
    if (hc == NULL) {
        return NGX_ERROR;
    }

    qc->http_connection = hc;

    /* find the server configuration for the address:port */

    c = qc->connection;
    port = c->listening->servers;

    if (port->naddrs > 1) {

        switch(qc->local_sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
        case AF_INET6:
            sin6 = (struct sockaddr_in6 *) qc->local_sockaddr;

            addr6 = port->addrs;

            /* the last address is "*" */

            for (i = 0; i < port->naddrs - 1; i++) {
                if (ngx_memcmp(&addr6[i].addr6, &sin6->sin6_addr, 16) == 0) {
                    break;
                }
            }

            hc->addr_conf = &addr6[i].conf;

            break;
#endif
        default: /* AF_INET */
            sin = (struct sockaddr_in *) qc->local_sockaddr;

            addr = port->addrs;

            /* the last address is "*" */

            for (i = 0; i < port->naddrs - 1; i++) {
                if (addr[i].addr == sin->sin_addr.s_addr) {
                    break;
                }
            }

            hc->addr_conf = &addr[i].conf;
            break;
        }

    } else {
        switch(qc->local_sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
        case AF_INET6:
            addr6 = port->addrs;
            hc->addr_conf = &addr6[0].conf;
            break;
#endif
        default: /* AF_INET */
            addr = port->addrs;
            hc->addr_conf = &addr[0].conf;
            break;
        }
    }

    /* the default server configuration for the address:port */
    hc->conf_ctx = hc->addr_conf->default_server->ctx;

    ctx = ngx_palloc(qc->pool, sizeof(ngx_http_log_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->connection = c;
    ctx->request = NULL;
    ctx->current_request = NULL;

    c->log->connection = c->number;
    c->log->handler = ngx_http_xquic_log_error;
    c->log->data = ctx;
    c->log->action = "xquic waiting for request";

    c->log_error = NGX_ERROR_INFO;

    c->data = qc;
    c->read->handler = ngx_http_xquic_readmsg_handler;
    c->write->handler = ngx_http_xquic_write_handler;

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


/**
 * create http v3 connection
 */
ngx_http_xquic_connection_t *
ngx_http_v3_create_connection(ngx_connection_t *lc, const xqc_cid_t *connection_id,
                                struct sockaddr *local_sockaddr, socklen_t local_socklen,
                                struct sockaddr *peer_sockaddr, socklen_t peer_socklen,
                                xqc_engine_t *engine)
{
    ngx_int_t                    rc;
    ngx_pool_t                  *pool;
    ngx_listening_t             *ls;
    ngx_http_xquic_connection_t *qc;
    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, 
                                                                    ngx_http_xquic_module);


    pool = ngx_create_pool(lc->listening->pool_size, lc->log);
    if (pool == NULL) {
        return NULL;
    }

    qc = ngx_pcalloc(pool, sizeof(ngx_http_xquic_connection_t));
    if (qc == NULL) {
        ngx_destroy_pool(pool);
        return NULL;
    }

    qc->pool = pool;
    qc->dcid = *connection_id;
    qc->engine = engine;

    qc->start_msec = ngx_current_msec;
    qc->fb_time = (ngx_msec_t) -1;
    qc->handshake_time = (ngx_msec_t) -1;

    /* init stream_index */
    qc->streams_index = ngx_pcalloc(qc->pool, ngx_http_xquic_index_size(qmcf)
                                              * sizeof(ngx_xquic_list_node_t *));
    if (qc->streams_index == NULL) {
        ngx_destroy_pool(pool);
        return NULL;
    }

    qc->peer_sockaddr = ngx_palloc(pool, peer_socklen);
    if (qc->peer_sockaddr == NULL) {
        ngx_destroy_pool(pool);
        return NULL;
    }

    qc->local_sockaddr = ngx_palloc(pool, local_socklen);
    if (qc->local_sockaddr == NULL) {
        ngx_destroy_pool(pool);
        return NULL;
    }

    ngx_memcpy(qc->peer_sockaddr, peer_sockaddr, peer_socklen);
    ngx_memcpy(qc->local_sockaddr, local_sockaddr, local_socklen);

    qc->peer_socklen = peer_socklen;
    qc->local_socklen = local_socklen;

    ls = lc->listening;
    qc->addr_text.data = ngx_pnalloc(pool, ls->addr_text_max_len);
    if (qc->addr_text.data == NULL) {
        ngx_destroy_pool(pool);
        return NULL;
    }
    qc->addr_text.len = ngx_sock_ntop(qc->peer_sockaddr, qc->peer_socklen,
                                      qc->addr_text.data,
                                      ls->addr_text_max_len, 0);
    if (qc->addr_text.len == 0) {
        ngx_destroy_pool(pool);
        return NULL;
    }

    rc = ngx_http_xquic_connect(qc, lc);
    if (rc == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, lc->log, 0, "|xquic|quic connect failed|");
        ngx_destroy_pool(pool);
        return NULL;
    }

    if(ngx_http_xquic_init_connection(qc) != NGX_OK) {
        ngx_close_connection(qc->connection);
        ngx_destroy_pool(pool);
        return NULL;
    }

#if (NGX_STAT_STUB)
    (void) ngx_atomic_fetch_add(ngx_stat_active, 1);
#endif

#if (T_NGX_HAVE_XUDP)
    /* enable by default */
    ngx_xudp_enable_tx(qc->connection);
#endif

    //ngx_quic_monitor_register(qc);

    return qc;
}


/**
 * used in xqc engine h3 conn close callback
 * to free h3 connection
 */
void
ngx_http_v3_finalize_connection(ngx_http_xquic_connection_t *h3c,
    ngx_uint_t status)
{
    ngx_uint_t                       i, size;
    ngx_event_t                     *ev;
    ngx_connection_t                *c, *fc;
    ngx_http_request_t              *r;
    ngx_http_v3_stream_t            *stream = NULL;
    ngx_xquic_list_node_t           *node = NULL;
    ngx_http_xquic_main_conf_t      *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);


    c = h3c->connection;

    h3c->blocked = 1;
    h3c->closing = 1;
    h3c->wait_to_close = 0;

    c->error = 1;

    if (!h3c->processing) {
        ngx_http_close_connection(c);
        return;
    }

    c->read->handler = ngx_http_empty_handler;
    c->write->handler = ngx_http_empty_handler;


    /* check all the streams */
    size = ngx_http_xquic_index_size(qmcf);

    for (i = 0; i < size; i++) {

        if (h3c->streams_index[i] == NULL) {
            continue;
        }

        /* may delete stream in the loop, will not delete node */
        for (node = h3c->streams_index[i]; node != NULL; node = node->next) {

            stream = node->entry;

            if (stream == NULL || stream->request_closed) {
                continue;
            }

            ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, 
                    "|xquic|find unclosed stream while finalizing request|stream_id=%i|", stream->id);

            stream->handled = 0;

            r = stream->request;

            /* stream->request may be closed before engine close h3 stream */
            if (r == NULL) {
                continue;
            }
            
            fc = r->connection;

            fc->error = 1;

            if (stream->queued) {
                stream->queued = 0;

                ev = fc->write;
                ev->delayed = 0;

            } else {
                ev = fc->read;
            }

            ev->eof = 1;
            ev->handler(ev);

            /* ev->handler may call ngx_http_v3_close_stream.
             * struct stream will memset to zero and stream->closed will set to 1 in ngx_http_v3_close_stream */
            if (r == stream->request && !stream->closed) {
                ngx_http_v3_close_stream(stream, 0);
            }
        }
    }

    h3c->blocked = 0;

    if (h3c->processing) {
        h3c->wait_to_close = 1;
        return;
    }

    ngx_http_close_connection(c);
}


/**
 * call xqc_h3_conn_close, and free connection in h3_conn_close_notify
 */
void
ngx_http_v3_connection_error(ngx_http_xquic_connection_t *qc, 
    ngx_uint_t err, const char *err_details)
{
    ngx_event_t                 *ev;
    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, qc->connection->log, 0,
                  "|xquic|ngx_xquic_server_session_close: close connection_id: %ul|err=%i|%s|",
                  qc->connection_id, err, err_details);

    ev = qc->connection->read;

    ev->handler = ngx_http_empty_handler;

    /* xquic close connection here */
    ngx_int_t ret = xqc_h3_conn_close(qmcf->xquic_engine, &(qc->dcid));
    if (ret != NGX_OK) {
        ngx_log_error(NGX_LOG_WARN, qc->connection->log, 0,
                      "|xquic|xqc_h3_conn_close err|connection_id: %ul|err=%i|%s|",
                      qc->connection_id, ret, err_details);
    }
}


