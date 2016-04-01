
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <nginx.h>
#include <ngx_http_tfs.h>
#include <ngx_http_tfs_errno.h>
#include <ngx_http_tfs_duplicate.h>
#include <ngx_http_tfs_root_server_message.h>
#include <ngx_http_tfs_meta_server_message.h>
#include <ngx_http_tfs_rc_server_message.h>
#include <ngx_http_tfs_name_server_message.h>
#include <ngx_http_tfs_data_server_message.h>
#include <ngx_http_tfs_remote_block_cache.h>


#define ngx_http_tfs_clear_content_len()\
    t->header_only |= 1;                \
    r->headers_out.content_length_n = 0


static ngx_str_t rcs_name = ngx_string("rc server");
static ngx_str_t ds_name = ngx_string("data server");
static ngx_str_t ms_name = ngx_string("meta server");


static void ngx_http_tfs_event_handler(ngx_event_t *ev);

static void ngx_http_tfs_process_buf_overflow(ngx_http_request_t *r,
    ngx_http_tfs_t *t);
static void ngx_http_tfs_set_header_line(ngx_http_tfs_t *t);

static void ngx_http_tfs_dummy_handler(ngx_http_request_t *r,
    ngx_http_tfs_t *t);
static void ngx_http_tfs_read_handler(ngx_http_request_t *r, ngx_http_tfs_t *t);
static void ngx_http_tfs_send_handler(ngx_http_request_t *r, ngx_http_tfs_t *t);
static void ngx_http_tfs_send(ngx_http_request_t *r, ngx_http_tfs_t *t);
static void ngx_http_tfs_send_response(ngx_http_request_t *r,
    ngx_http_tfs_t *t);

static void ngx_http_tfs_process_non_buffered_downstream(ngx_http_request_t *r);
static void ngx_http_tfs_process_non_buffered_request(ngx_http_tfs_t *t,
    ngx_uint_t do_write);

static void ngx_http_tfs_process_upstream_request(ngx_http_request_t *r,
    ngx_http_tfs_t *t);

static void ngx_http_tfs_handle_connection_failure(ngx_http_tfs_t *t,
    ngx_http_tfs_peer_connection_t *tp);
static void ngx_http_tfs_rd_check_broken_connection(ngx_http_request_t *r);
static void ngx_http_tfs_wr_check_broken_connection(ngx_http_request_t *r);
static void ngx_http_tfs_check_broken_connection(ngx_http_request_t *r,
    ngx_event_t *ev);


extern ngx_module_t  ngx_http_tfs_module;


ngx_int_t
ngx_http_tfs_init(ngx_http_tfs_t *t)
{
    ngx_int_t                  rc;
    ngx_http_request_t        *r;
    ngx_http_tfs_rc_ctx_t     *rc_ctx;
    ngx_http_tfs_rcs_info_t   *rc_info;
    ngx_http_tfs_upstream_t   *upstream;
    ngx_http_core_loc_conf_t  *clcf;

    t->read_event_handler = ngx_http_tfs_read_handler;
    t->write_event_handler = ngx_http_tfs_send_handler;
    r = NULL;
    rc_info = NULL;
    rc_ctx = NULL;
    upstream = t->loc_conf->upstream;

    if (t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_KEEPALIVE) {
        r = t->data;
        r->read_event_handler = ngx_http_tfs_rd_check_broken_connection;
        r->write_event_handler = ngx_http_tfs_wr_check_broken_connection;

        clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
        if (clcf == NULL) {
            return NGX_ERROR;
        }

        t->output.alignment = clcf->directio_alignment;
        t->output.bufs.size = clcf->client_body_buffer_size;

    } else {
        /* rc-keepalive */
        t->output.alignment = 512;
        t->output.bufs.size = (size_t) 2 * ngx_pagesize;
    }

    t->output.pool = t->pool;
    t->output.bufs.num = 1;
    t->output.output_filter = ngx_chain_writer;
    t->output.filter_ctx = &t->writer;
    t->header_size = sizeof(ngx_http_tfs_header_t);
    t->writer.pool = t->pool;

    rc = ngx_http_tfs_peer_init(t);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "tfs peer init failed");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /* header and body */
    t->recv_chain = ngx_http_tfs_alloc_chains(t->pool, 2);
    if (t->recv_chain == NULL) {
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "tfs alloc chains failed");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_KEEPALIVE) {

        if (!upstream->enable_rcs) {
            switch(t->r_ctx.action.code) {
            case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
                t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO;
                break;
            case NGX_HTTP_TFS_ACTION_STAT_FILE:
                t->state = NGX_HTTP_TFS_STATE_STAT_GET_BLK_INFO;
                break;
            case NGX_HTTP_TFS_ACTION_READ_FILE:
                t->state = NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO;
                break;
            case NGX_HTTP_TFS_ACTION_WRITE_FILE:
                t->state = NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS;
                break;
            default:
                ngx_shmtx_unlock(&rc_ctx->shpool->mutex);
                return NGX_ERROR;
            }

            t->name_server_addr.ip =
                ((struct sockaddr_in*)
                 (upstream->ups_addr->sockaddr))->sin_addr.s_addr;
            t->name_server_addr.port =
                ntohs(((struct sockaddr_in*)
                       (upstream->ups_addr->sockaddr))->sin_port);

            /* skip get cluster id from ns */
            if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
                if (t->main_conf->cluster_id > 0) {
                    t->file.cluster_id = t->main_conf->cluster_id;
                    t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
                }

                /* prepare each segment's data */
                if (t->is_large_file) {
                    rc = ngx_http_tfs_get_segment_for_write(t);
                    if (rc == NGX_ERROR) {
                        return NGX_ERROR;
                    }
                }
            }

            if (!t->is_large_file
                || (t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_WRITE_FILE))
            {
                /* fill meta segment */
                rc = ngx_http_tfs_get_meta_segment(t);
                if (rc == NGX_ERROR) {
                    ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                  "tfs get meta segment failed");
                    return NGX_HTTP_INTERNAL_SERVER_ERROR;
                }

                /* small file */
                if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
                    /* parse meta segment */
                    if (t->r_ctx.write_meta_segment) {
                        rc = ngx_http_tfs_parse_meta_segment(t, t->send_body);
                        if (rc == NGX_ERROR) {
                            return NGX_ERROR;
                        }
                        t->send_body = t->meta_segment_data;
                    }

                    t->file.segment_data[0].data = t->send_body;
                    t->file.segment_data[0].segment_info.size =
                                  ngx_http_tfs_get_chain_buf_size(t->send_body);
                    t->file.left_length =
                                      t->file.segment_data[0].segment_info.size;
                    t->file.segment_data[0].oper_size =
                                        ngx_min(t->file.left_length,
                                                NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);

                } else {
                    /* set oper size && offset,
                     * large file must read the whole meta segment */
                    if (t->is_large_file) {
                        t->is_process_meta_seg = NGX_HTTP_TFS_YES;
                        t->file.file_offset = 0;
                        t->file.left_length = NGX_HTTP_TFS_MAX_SIZE;

                    } else {
                        t->file.file_offset = t->r_ctx.offset;
                        t->file.left_length = t->r_ctx.size;
                    }

                    t->file.segment_data[0].oper_offset = t->file.file_offset;
                    t->file.segment_data[0].oper_size =
                                       ngx_min(t->file.left_length,
                                               NGX_HTTP_TFS_MAX_READ_FILE_SIZE);
                }
            }

        } else {
            /* skip rc server */
            rc_ctx = upstream->rc_ctx;
            ngx_shmtx_lock(&rc_ctx->shpool->mutex);
            rc_info = ngx_http_tfs_rcs_lookup(rc_ctx, t->r_ctx.appkey);
            ngx_shmtx_unlock(&rc_ctx->shpool->mutex);
            if (rc_info != NULL) {
                t->rc_info_node = rc_info;

                if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_GET_APPID) {
                    rc = ngx_http_tfs_set_output_appid(t, rc_info->app_id);
                    if (rc == NGX_ERROR) {
                        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                      "tfs set output appid failed");
                        return NGX_ERROR;
                    }

                    ngx_http_tfs_send_response(r, t);
                    return NGX_OK;
                }

                /* TODO: use fine granularity mutex(per rc_info_node mutex) */
                rc = ngx_http_tfs_misc_ctx_init(t, rc_info);
                if (rc == NGX_DECLINED) {
                    if (t->decline_handler) {
                        rc = t->decline_handler(t);
                        if (rc == NGX_ERROR) {
                            return rc;
                        }
                    }
                    return NGX_OK;
                }

                if (rc != NGX_OK) {
                    return rc;
                }
            }
        }
    }

    t->tfs_peer = ngx_http_tfs_select_peer(t);
    if (t->tfs_peer == NULL) {
        ngx_log_error(NGX_LOG_ERR, t->log, 0, "tfs select peer failed");

        return NGX_ERROR;
    }

    t->recv_chain->buf = &t->header_buffer;
    t->recv_chain->next->buf = &t->tfs_peer->body_buffer;

    ngx_http_tfs_connect(t);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_lookup_block_cache(ngx_http_tfs_t *t)
{
    ngx_int_t                         rc;
    ngx_http_tfs_inet_t              *addr;
    ngx_http_tfs_segment_data_t      *segment_data;
    ngx_http_tfs_block_cache_key_t    key;
    ngx_http_tfs_block_cache_value_t  value;

    segment_data = &t->file.segment_data[t->file.segment_index];
    key.ns_addr = *((uint64_t*)(&t->name_server_addr));
    key.block_id = segment_data->segment_info.block_id;

    rc = ngx_http_tfs_block_cache_lookup(&t->block_cache_ctx, t->pool, t->log,
                                         &key, &value);

    switch (rc) {
    case NGX_DECLINED:
        /* remote cache handler will deal */
        if (t->block_cache_ctx.use_cache & NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {
            return NGX_DECLINED;
        }
        break;
    case NGX_OK:
        /* local cache hit */
        segment_data->cache_hit = NGX_HTTP_TFS_LOCAL_BLOCK_CACHE;

        segment_data->block_info.ds_count = value.ds_count;
        segment_data->block_info.ds_addrs = (ngx_http_tfs_inet_t *)
                                             value.ds_addrs;

        addr = ngx_http_tfs_select_data_server(t, segment_data);
        if (addr == NULL) {
            ngx_http_tfs_remove_block_cache(t, segment_data);

        } else {
            /* skip GET_BLK_INFO state */
            t->state += 1;
            ngx_http_tfs_peer_set_addr(t->pool,
                          &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER], addr);
        }

       break;
    case NGX_ERROR:
        /* block cache should not affect, go for ns */
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "lookup block cache failed.");
        break;
    }
    rc = NGX_OK;

    ngx_http_tfs_finalize_state(t, rc);

    return rc;
}


void
ngx_http_tfs_remove_block_cache(ngx_http_tfs_t *t,
    ngx_http_tfs_segment_data_t *segment_data)
{
    ngx_http_tfs_block_cache_key_t  key;

    key.ns_addr = *((int64_t *)(&t->name_server_addr));
    key.block_id = segment_data->segment_info.block_id;
    ngx_http_tfs_block_cache_remove(&t->block_cache_ctx, t->pool, t->log,
                                    &key, segment_data->cache_hit);

    /* only when cache dirty, need retry current ns */
    if (segment_data->cache_hit != NGX_HTTP_TFS_NO_BLOCK_CACHE) {
        t->retry_curr_ns = NGX_HTTP_TFS_YES;
    }

    segment_data->cache_hit = NGX_HTTP_TFS_NO_BLOCK_CACHE;
}


ngx_int_t
ngx_http_tfs_batch_lookup_block_cache(ngx_http_tfs_t *t)
{
    uint32_t                         i, j, block_count;
    ngx_int_t                        rc;
    ngx_array_t                      keys, kvs;
    ngx_http_tfs_segment_data_t     *segment_data;
    ngx_http_tfs_block_cache_kv_t   *kv;
    ngx_http_tfs_block_cache_key_t  *key;

    block_count = t->file.segment_count - t->file.segment_index;
    if (block_count > NGX_HTTP_TFS_MAX_BATCH_COUNT) {
        block_count = NGX_HTTP_TFS_MAX_BATCH_COUNT;
    }

    rc = ngx_array_init(&keys, t->pool, block_count,
                        sizeof(ngx_http_tfs_block_cache_key_t));
    if (rc == NGX_ERROR) {
        return rc;
    }

    segment_data = &t->file.segment_data[t->file.segment_index];
    for (i = 0; i < block_count; i++) {
        key = (ngx_http_tfs_block_cache_key_t *) ngx_array_push(&keys);
        key->ns_addr = *((uint64_t*)(&t->name_server_addr));
        key->block_id = segment_data[i].segment_info.block_id;
    }

    rc = ngx_array_init(&kvs, t->pool, block_count,
                        sizeof(ngx_http_tfs_block_cache_kv_t));
    if (rc == NGX_ERROR) {
        return rc;
    }

    rc = ngx_http_tfs_block_cache_batch_lookup(&t->block_cache_ctx,
                                               t->pool, t->log,
                                               &keys, &kvs);
    /* local cache hit(maybe partial) */
    if (rc != NGX_ERROR && kvs.nelts > 0) {
        /* local block cache hit count */
        t->file.curr_batch_count += kvs.nelts;
        kv = kvs.elts;
        for (i = 0; i < kvs.nelts; i++, kv++) {
            /* find out segment */
            for (j = 0; j < block_count; j++) {
                if (segment_data[j].segment_info.block_id == kv->key->block_id
                    && segment_data[j].block_info.ds_addrs == NULL)
                {
                    break;
                }
            }

            segment_data[j].block_info.ds_count = kv->value->ds_count;
            segment_data[j].block_info.ds_addrs = (ngx_http_tfs_inet_t *)
                                                   kv->value->ds_addrs;

            segment_data[j].cache_hit = NGX_HTTP_TFS_LOCAL_BLOCK_CACHE;
        }
    }

    switch (rc) {
    case NGX_DECLINED:
        /* remote cache handler will deal */
        if (t->block_cache_ctx.use_cache & NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {
            return NGX_DECLINED;
        }
        rc = NGX_OK;
        break;
    case NGX_OK:
        /* local cache all hit */
        t->decline_handler = ngx_http_tfs_batch_process_start;
        rc = NGX_DECLINED;
        break;
    case NGX_ERROR:
        /* block cache should not affect, go for ns */
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "batch lookup block cache failed.");
        rc = NGX_OK;
    }

    ngx_http_tfs_finalize_state(t, rc);

    return rc;
}


ngx_int_t
ngx_http_tfs_connect(ngx_http_tfs_t *t)
{
    ngx_int_t                        rc;
    ngx_connection_t                *c;
    ngx_http_request_t              *r;
    ngx_peer_connection_t           *p;
    ngx_http_tfs_peer_connection_t  *tp;

    tp = t->tfs_peer;
    p = &tp->peer;
    r = t->data;

    p->log->action = "connecting server";

    rc = t->create_request(t);

    if (rc == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, p->log, 0, "create %V (%s) request failed",
            p->name, tp->peer_addr_text);
        ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return rc;
    }

    ngx_log_error(NGX_LOG_DEBUG, p->log, 0, "connecting %V, addr: %s",
                  p->name, tp->peer_addr_text);

    rc = ngx_event_connect_peer(p);

    if (rc == NGX_ERROR || rc == NGX_BUSY || rc == NGX_DECLINED) {
        ngx_log_error(NGX_LOG_ERR, p->log, 0,
                      "connect to (%V: %s) failed", p->name,
                      tp->peer_addr_text);
        ngx_http_tfs_handle_connection_failure(t, t->tfs_peer);
        return rc;
    }

    c = p->connection;
    c->data = t;

    c->read->handler = ngx_http_tfs_event_handler;
    c->write->handler = ngx_http_tfs_event_handler;

    c->sendfile &= r->connection->sendfile;
    t->output.sendfile = c->sendfile;

    if (c->pool == NULL) {
        c->pool = ngx_create_pool(128, r->connection->log);
        if (c->pool == NULL) {
            ngx_log_error(NGX_LOG_ERR, p->log, 0,
                          "create connection pool failed");
            ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
            return NGX_ERROR;
        }
    }

    c->log = r->connection->log;
    c->pool->log = c->log;
    c->read->log = c->log;
    c->write->log = c->log;

    t->writer.out = NULL;
    t->writer.last = &t->writer.out;
    t->writer.connection = c;
    t->writer.limit = 0;

    if (rc == NGX_AGAIN) {
        ngx_add_timer(c->write, t->main_conf->tfs_connect_timeout);
        return NGX_AGAIN;
    }

    ngx_http_tfs_send(r, t);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_reinit(ngx_http_request_t *r, ngx_http_tfs_t *t)
{
    ngx_chain_t  *cl, *cl_next;

    t->request_sent = 0;

    for (cl = t->request_bufs; cl; cl = cl_next) {
        cl_next = cl->next;
        ngx_free_chain(r->pool, cl);
    }

    /* reinit the subrequest's ngx_output_chain() context */
    if (r->request_body && r->request_body->temp_file
        && r != r->main && t->output.buf)
    {
        t->output.free = ngx_alloc_chain_link(r->pool);
        if (t->output.free == NULL) {
            return NGX_ERROR;
        }

        t->output.free->buf = t->output.buf;
        t->output.free->next = NULL;

        t->output.buf->pos = t->output.buf->start;
        t->output.buf->last = t->output.buf->start;
    }

    t->output.buf = NULL;
    t->output.in = NULL;
    t->output.busy = NULL;

    t->header_buffer.pos = t->header_buffer.start;
    t->header_buffer.last = t->header_buffer.start;

    t->parse_state = NGX_HTTP_TFS_HEADER;
    t->header_size = sizeof(ngx_http_tfs_header_t);
    t->write_event_handler = ngx_http_tfs_send_handler;

    return NGX_OK;
}


static void
ngx_http_tfs_event_handler(ngx_event_t *ev)
{
    ngx_http_tfs_t      *t;
    ngx_connection_t    *c;
    ngx_http_request_t  *r;
    ngx_http_log_ctx_t  *ctx;

    c = ev->data;
    t = c->data;

    r = t->data;
    c = r->connection;

    if (t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_KEEPALIVE) {
        ctx = c->log->data;
        ctx->current_request = r;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http tfs request: \"%V?%V\"", &r->uri, &r->args);

    if (ev->write) {
        t->write_event_handler(r, t);

    } else {
        t->read_event_handler(r, t);
    }

    ngx_http_run_posted_requests(c);
}


static void
ngx_http_tfs_send(ngx_http_request_t *r, ngx_http_tfs_t *t)
{
    ngx_int_t                       rc;
    ngx_connection_t               *c;
    ngx_http_tfs_peer_connection_t *tp;

    tp = t->tfs_peer;
    c = tp->peer.connection;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http tfs send request to %V, addr: %s", tp->peer.name,
                   tp->peer_addr_text);

    if (!t->request_sent && ngx_http_tfs_test_connect(c) != NGX_OK) {
        ngx_http_tfs_handle_connection_failure(t, tp);
        return;
    }

    c->log->action = "sending request to server";

    /* start send  */
    rc = ngx_output_chain(&t->output, t->request_sent ? NULL : t->request_bufs);

    t->request_sent = 1;

    if (rc == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "ngx output chain failed");
        ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    if (rc == NGX_AGAIN) {
        ngx_add_timer(c->write, t->main_conf->tfs_send_timeout);

        if (ngx_handle_write_event(c->write, t->main_conf->send_lowat)
            != NGX_OK)
        {
            ngx_log_error(NGX_LOG_ERR, c->log, 0,
                          "ngx handle write event failed");
            ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        return;
    }

    /* rc == NGX_OK */
    if (c->tcp_nopush == NGX_TCP_NOPUSH_SET) {
        if (ngx_tcp_push(c->fd) == NGX_ERROR) {
            ngx_log_error(NGX_LOG_CRIT, c->log, ngx_socket_errno,
                          ngx_tcp_push_n " failed");
            ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        c->tcp_nopush = NGX_TCP_NOPUSH_UNSET;
    }

    t->write_event_handler = ngx_http_tfs_dummy_handler;

    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "ngx handle write event failed");
        ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    ngx_add_timer(c->read, t->main_conf->tfs_read_timeout);

    if (c->read->ready) {
        ngx_http_tfs_read_handler(r, t);
        return;
    }
}


static void
ngx_http_tfs_dummy_handler(ngx_http_request_t *r, ngx_http_tfs_t *t)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http tfs dummy handler");
}


static ngx_int_t
ngx_http_tfs_alloc_buf(ngx_http_tfs_t *t)
{
    ngx_http_request_t             *r;
    ngx_http_tfs_peer_connection_t *tp;

    tp = t->tfs_peer;
    r = t->data;

    if (t->header_buffer.start == NULL) {
        t->header_buffer.start = ngx_palloc(r->pool, t->main_conf->buffer_size);
        if (t->header_buffer.start == NULL) {
            return NGX_ERROR;
        }

        t->header_buffer.pos = t->header_buffer.start;
        t->header_buffer.last = t->header_buffer.start;
        t->header_buffer.temporary = 1;
    }

    t->header_buffer.end = t->header_buffer.start + t->header_size;

    if (tp->body_buffer.start == NULL) {
        tp->body_buffer.start = ngx_palloc(r->pool,
                                           t->main_conf->body_buffer_size);
        if (tp->body_buffer.start == NULL) {
            return NGX_ERROR;
        }

        tp->body_buffer.pos = tp->body_buffer.start;
        tp->body_buffer.last = tp->body_buffer.start;
        tp->body_buffer.end = tp->body_buffer.start
                               + t->main_conf->body_buffer_size;
        tp->body_buffer.temporary = 1;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_process_header(ngx_http_tfs_t *t, ngx_int_t n)
{
    ngx_int_t                        body_size, rc;
    ngx_http_tfs_peer_connection_t  *tp;

    tp = t->tfs_peer;

    if (n < t->header_size) {
        t->header_buffer.last += n;
        t->header_size -= n;
        return NGX_AGAIN;
    }

    t->header = (void *) t->header_buffer.pos;
    t->header_buffer.last += t->header_size;
    body_size = n - t->header_size;
    if (body_size > 0) {
        tp->body_buffer.last += body_size;
    }
    if (t->input_filter != NULL) {
        rc = t->input_filter(t);
        if (rc != NGX_OK) {
            /* error or NGX_AGAIN or NGX_DONE */
            return rc;
        }
    }

    return NGX_OK;
}


void
ngx_http_tfs_finalize_state(ngx_http_tfs_t *t, ngx_int_t rc)
{
    uint16_t                         action;
    ngx_http_request_t              *r;
    ngx_peer_connection_t           *p;
    ngx_http_tfs_rc_ctx_t           *rc_ctx;
    ngx_http_tfs_rcs_info_t         *rc_info;
    ngx_http_tfs_peer_connection_t  *tp;

    r = t->data;
    tp = t->tfs_peer;
    p = NULL;

    if (tp) {
        p = &tp->peer;
        if (p) {
            ngx_log_error(NGX_LOG_INFO, t->log, 0,
                      "http tfs finalize state %V, %i", p->name, rc);
        }
    }

    /* if one sub process fails, fail all */
    if (t->parent) {
        if (t->parent->sp_fail_count > 0) {
            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                          "other sub process failed, will fail myself");

            ngx_http_tfs_finalize_request(r, t, NGX_ERROR);
            return;
        }
    }

    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_KEEPALIVE) {
        /* NGX_DONE or ERROR */
        if (rc != NGX_OK) {
            ngx_http_tfs_finalize_request(r, t, NGX_DONE);
            return;
        }
    }

    if (rc == NGX_HTTP_CLIENT_CLOSED_REQUEST
        || rc == NGX_HTTP_REQUEST_TIME_OUT)
    {
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "client prematurely closed connection or timed out");
        ngx_http_tfs_finalize_request(r, t, rc);
        return;
    }

    if (rc == NGX_ERROR) {
        if (p) {
            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                "http tfs process %V request failed", p->name);
        }

        ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    if (rc >= NGX_HTTP_SPECIAL_RESPONSE
        || rc <= NGX_HTTP_TFS_EXIT_GENERAL_ERROR)
    {
        t->tfs_status = rc;
        ngx_http_tfs_send_response(r, t);
        return;
    }

    if (rc == NGX_HTTP_TFS_AGAIN) {
        if (t->retry_handler) {
            rc = t->retry_handler(t);
            if (rc == NGX_OK || rc == NGX_DECLINED) {
                return;
            }

            if (rc == NGX_HTTP_TFS_EXIT_SERVER_OBJECT_NOT_FOUND) {
                ngx_log_error(NGX_LOG_ERR, t->log, 0,
                              "can not find retry server");
                ngx_http_tfs_finalize_request(r, t, NGX_HTTP_NOT_FOUND);
                return;
            }
        }

        t->tfs_status = NGX_ERROR;
        ngx_http_tfs_send_response(r, t);

        return;
    }

    if (rc == NGX_DONE) {
        /* need stat data */
        if (!t->parent) {
            if (t->srv_conf->log != NULL) {
                action = t->r_ctx.action.code;
                if (action == NGX_HTTP_TFS_ACTION_REMOVE_FILE){
                    if (t->r_ctx.unlink_type == NGX_HTTP_TFS_UNLINK_UNDELETE) {
                        action = NGX_HTTP_TFS_ACTION_UNDELETE_FILE;

                    } else if (t->r_ctx.unlink_type == NGX_HTTP_TFS_UNLINK_CONCEAL) {
                        action = NGX_HTTP_TFS_ACTION_CONCEAL_FILE;

                    } else if (t->r_ctx.unlink_type == NGX_HTTP_TFS_UNLINK_REVEAL) {
                        action = NGX_HTTP_TFS_ACTION_REVEAL_FILE;
                    }
                }

                ngx_log_error(NGX_LOG_INFO, t->srv_conf->log, 0,
                              "%d, %uL, %V, %V, %uD, %uL, %uL, %uL, %V",
                              action,
                              t->loc_conf->upstream->enable_rcs ?
                              t->rc_info_node->app_id : NGX_HTTP_TFS_DEFAULT_APPID,
                              &t->file_name,
                              &t->r_ctx.file_suffix,
                              t->r_ctx.fsname.file.block_id,
                              ngx_http_tfs_raw_fsname_get_file_id(t->r_ctx.fsname),
                              t->r_ctx.offset,
                              t->stat_info.size,
                              &r->connection->addr_text);
            }

            if (t->loc_conf->upstream->enable_rcs) {
                rc_ctx = t->loc_conf->upstream->rc_ctx;
                ngx_shmtx_lock(&rc_ctx->shpool->mutex);
                rc_info = ngx_http_tfs_rcs_lookup(rc_ctx, t->r_ctx.appkey);

                if (rc_info != NULL) {
                    switch (t->r_ctx.action.code) {
                    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
                        ngx_http_tfs_rcs_stat_update(t, rc_info, NGX_HTTP_TFS_OPER_WRITE);
                        break;
                    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
                        ngx_http_tfs_rcs_stat_update(t, rc_info, NGX_HTTP_TFS_OPER_UNLINK);
                        break;
                    case NGX_HTTP_TFS_ACTION_READ_FILE:
                        ngx_http_tfs_rcs_stat_update(t, rc_info, NGX_HTTP_TFS_OPER_READ);
                        break;
                    default:
                        ngx_http_tfs_rcs_stat_update(t, rc_info, NGX_HTTP_TFS_OPER_INVALID);
                        break;
                    }
                }
                ngx_shmtx_unlock(&rc_ctx->shpool->mutex);
            }
        }

        /* need send data */
        ngx_http_tfs_send_response(r, t);

        return;
    }

    if (p && p->free) {
        p->free(p, p->data, 0);
    }

    if (rc == NGX_DECLINED) {
        if (t->decline_handler) {
            rc = t->decline_handler(t);
            if (rc == NGX_ERROR) {
                ngx_http_tfs_finalize_request(r, t,
                                              NGX_HTTP_INTERNAL_SERVER_ERROR);
            }
        }
        return;
    }

    /* rc == NGX_OK */
    if (ngx_http_tfs_reinit(r, t) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, t->log, 0, "tfs reinit failed");
        ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);

        return;
    }

    t->tfs_peer = ngx_http_tfs_select_peer(t);
    if (t->tfs_peer == NULL) {
        ngx_log_error(NGX_LOG_ERR, t->log, 0, "tfs select peer failed");
        ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);

        return;
    }

    t->recv_chain->buf = &t->header_buffer;
    t->recv_chain->next->buf = &t->tfs_peer->body_buffer;

    ngx_log_error(NGX_LOG_INFO, t->log, 0,
                  "http tfs process next peer is  %V, addr: %s",
                  t->tfs_peer->peer.name,
                  t->tfs_peer->peer_addr_text);

    ngx_http_tfs_connect(t);
}


static void
ngx_http_tfs_process_upstream_request(ngx_http_request_t *r, ngx_http_tfs_t *t)
{
    ngx_int_t                        n, rc;
    ngx_chain_t                     *chain;
    ngx_connection_t                *c;
    ngx_http_tfs_peer_connection_t  *tp;

    tp = t->tfs_peer;
    c = tp->peer.connection;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http tfs process request body for %V, addr: %s",
                   tp->peer.name,
                   tp->peer_addr_text);

    /* for test ds retry */
    //if (ngx_strncmp(p->name->data, ds_name.data, p->name->len) == 0) {
    //    ngx_http_tfs_handle_connection_failure(t, tp);
    //    return;
    //}

    if (!t->request_sent && ngx_http_tfs_test_connect(c) != NGX_OK) {
        ngx_http_tfs_handle_connection_failure(t, tp);
        return;
    }

    rc = ngx_http_tfs_alloc_buf(t);
    if (rc == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "tfs alloc buf failed");
        ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    for ( ;; ) {

        for (chain = t->recv_chain; chain; chain = chain->next) {
            if (chain->buf->last != chain->buf->end) {
                break;
            }
        }

        if (chain == NULL) {
            /* need send data */
            ngx_http_tfs_process_buf_overflow(r, t);
            return;
        }

        n = c->recv_chain(c, chain, 0);

        if (n == NGX_AGAIN) {
            if (chain->buf->last == chain->buf->end) {
                ngx_http_tfs_process_buf_overflow(r, t);
                return;
            }

            ngx_add_timer(c->read, t->main_conf->tfs_read_timeout);
            if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
                ngx_log_error(NGX_LOG_ERR, c->log, 0,
                              "tfs handle read event failed");
                ngx_http_tfs_finalize_request(r, t,
                                              NGX_HTTP_INTERNAL_SERVER_ERROR);
                return;
            }

            return;
        }

        if (n == 0) {
            ngx_log_error(NGX_LOG_ERR, c->log, 0,
                          "tfs prematurely closed connection");
        }

        if (n == NGX_ERROR || n == 0) {
            ngx_log_error(NGX_LOG_ERR, c->log, 0, "recv chain error");
            ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);

            return;
        }

        if (t->parse_state == NGX_HTTP_TFS_HEADER) {
            rc = ngx_http_tfs_process_header(t, n);

            if (rc == NGX_AGAIN) {
                continue;
            }

            if (rc < 0 || rc == NGX_DONE) {
                break;
            }

            t->parse_state = NGX_HTTP_TFS_BODY;

        } else {
            tp->body_buffer.last += n;
        }

        rc = t->process_request_body(t);

        if (rc == NGX_AGAIN) {
            continue;
        }

        break;
    }

    /* rc == NGX_OK */
    ngx_http_tfs_finalize_state(t, rc);
}


static void
ngx_http_tfs_send_response(ngx_http_request_t *r, ngx_http_tfs_t *t)
{
    int                        tcp_nodelay;
    ngx_int_t                  rc;
    ngx_http_tfs_t            *parent_tfs;
    ngx_connection_t          *c;
    ngx_http_core_loc_conf_t  *clcf;

    /* sub process */
    if (t->parent) {
        if (t->tfs_status != NGX_OK) {
            ngx_http_tfs_finalize_request(r, t, NGX_ERROR);
            return;
        }

        if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
            ngx_http_tfs_finalize_request(r, t, NGX_DONE);
            return;
        }

        if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE) {
            /* output in the right turn */
            if (t->parent->sp_curr != t->sp_curr) {
                t->sp_ready = NGX_HTTP_TFS_YES;
                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                               "curr output segment is [%uD], "
                               "[%uD] is ready, wait for call...",
                               t->parent->sp_curr, t->sp_curr);
                return;
            }
            /* set ctx */
            ngx_http_set_ctx(r, t, ngx_http_tfs_module);
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, t->log, 0,
                           "segment[%uD] output...",
                           t->sp_curr);
        }
    }

    if (t->parent == NULL) {
        parent_tfs = t;

    } else {
        parent_tfs = t->parent;
    }

    if (!parent_tfs->header_sent) {
        ngx_http_tfs_set_header_line(t);

        rc = ngx_http_send_header(r);

        if (rc == NGX_ERROR || rc > NGX_OK || r->post_action) {
            ngx_http_tfs_finalize_state(t, rc);
            return;
        }

        parent_tfs->header_sent = 1;

        if (t->header_only) {
            ngx_http_tfs_finalize_request(r, t, rc);
            return;
        }
    }

    c = r->connection;

    if (r->request_body && r->request_body->temp_file) {
        ngx_pool_run_cleanup_file(r->pool, r->request_body->temp_file->file.fd);
        r->request_body->temp_file->file.fd = NGX_INVALID_FILE;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    r->write_event_handler = ngx_http_tfs_process_non_buffered_downstream;

    r->limit_rate = 0;

    if (clcf->tcp_nodelay && c->tcp_nodelay == NGX_TCP_NODELAY_UNSET) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "tcp_nodelay");

        tcp_nodelay = 1;

        if (setsockopt(c->fd, IPPROTO_TCP, TCP_NODELAY,
                (const void *) &tcp_nodelay, sizeof(int)) == -1)
        {
            ngx_connection_error(c, ngx_socket_errno,
                                 "setsockopt(TCP_NODELAY) failed");

            ngx_http_tfs_finalize_request(r, t, 0);
            return;
        }

        c->tcp_nodelay = NGX_TCP_NODELAY_SET;
    }

    ngx_http_tfs_process_non_buffered_downstream(r);
    return;
}


static void
ngx_http_tfs_set_header_line(ngx_http_tfs_t *t)
{
    ngx_http_request_t          *r;
    ngx_http_tfs_restful_ctx_t  *ctx;

    r = t->data;
    ctx = &t->r_ctx;

    /* common error */
    switch (t->tfs_status) {
    case NGX_ERROR:
    case NGX_HTTP_TFS_EXIT_GENERAL_ERROR:
        r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
        goto error_header;

    case NGX_HTTP_SPECIAL_RESPONSE ... NGX_HTTP_INTERNAL_SERVER_ERROR:
        r->headers_out.status = t->tfs_status;
        goto error_header;

    case NGX_HTTP_TFS_EXIT_INVALID_FILE_NAME:
    case NGX_HTTP_TFS_EXIT_READ_OFFSET_ERROR:
    case NGX_HTTP_TFS_EXIT_DISK_OPER_INCOMPLETE:
    case NGX_HTTP_TFS_EXIT_INVALID_ARGU_ERROR:
    case NGX_HTTP_TFS_EXIT_PHYSIC_BLOCK_OFFSET_ERROR:
        r->headers_out.status = NGX_HTTP_BAD_REQUEST;
        goto error_header;

    case NGX_HTTP_TFS_EXIT_OVER_MAX_SUB_DIRS_COUNT:
    case NGX_HTTP_TFS_EXIT_OVER_MAX_SUB_DIRS_DEEP:
    case NGX_HTTP_TFS_EXIT_OVER_MAX_SUB_FILES_COUNT:
        r->headers_out.status = NGX_HTTP_FORBIDDEN;
        goto error_header;

    case NGX_HTTP_TFS_EXIT_SERVER_OBJECT_NOT_FOUND:
    case NGX_HTTP_TFS_EXIT_BLOCK_NOT_FOUND:
    case NGX_HTTP_TFS_EXIT_META_NOT_FOUND_ERROR:
    case NGX_HTTP_TFS_EXIT_FILE_INFO_ERROR:
    case NGX_HTTP_TFS_EXIT_FILE_STATUS_ERROR:
        r->headers_out.status = NGX_HTTP_NOT_FOUND;
        goto error_header;

    case NGX_HTTP_TFS_EXIT_WRITE_EXIST_POS_ERROR:
    case NGX_HTTP_TFS_EXIT_VERSION_CONFLICT_ERROR:
        /* TODO: maybe should handle this using retry */
        r->headers_out.status = NGX_HTTP_CONFLICT;
        goto error_header;
    }

    switch(ctx->action.code) {
    case NGX_HTTP_TFS_ACTION_KEEPALIVE:
        ngx_http_tfs_clear_content_len();
        r->headers_out.status = NGX_HTTP_OK;
        break;

    case NGX_HTTP_TFS_ACTION_GET_APPID:
        r->headers_out.content_type_len = sizeof("application/json") - 1;
        ngx_str_set(&r->headers_out.content_type, "application/json");
        r->headers_out.status = NGX_HTTP_OK;
        break;

    case NGX_HTTP_TFS_ACTION_CREATE_DIR:
    case NGX_HTTP_TFS_ACTION_CREATE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_ACTION_DONE:
            ngx_http_tfs_clear_content_len();
            r->headers_out.status = NGX_HTTP_CREATED;
            break;
            /* errno */

        default:
            switch (t->tfs_status) {
            case NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR:
                r->headers_out.status = NGX_HTTP_CONFLICT;
                break;

            case NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR:
                r->headers_out.status = NGX_HTTP_NOT_FOUND;
                break;

            default:
                r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }

            goto error_header;
        }
        break;

    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_DONE:
            if (t->r_ctx.version == 1) {
                r->headers_out.content_type_len = sizeof("application/json")- 1;
                ngx_str_set(&r->headers_out.content_type, "application/json");
            } else {
                ngx_http_tfs_clear_content_len();
            }
            r->headers_out.status = NGX_HTTP_OK;
            break;
            /* errno */
        default:
            switch (t->tfs_status) {
            case NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR:
            case NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR:
            case NGX_HTTP_TFS_EXIT_NOT_CREATE_ERROR:
                r->headers_out.status = NGX_HTTP_NOT_FOUND;
                break;

            case NGX_HTTP_TFS_EXIT_WRITE_EXIST_POS_ERROR:
                r->headers_out.status = NGX_HTTP_BAD_REQUEST;
                break;

            default:
                r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }

            goto error_header;
        }

        break;

    case NGX_HTTP_TFS_ACTION_STAT_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_STAT_DONE:
            if (t->r_ctx.chk_exist) {
                t->header_only |= 1;
                /* set content length if have */
                if (t->file_stat.size > 0) {
                    r->headers_out.content_length_n = t->file_stat.size;
                }

            } else {
                r->headers_out.content_type_len = sizeof("application/json") - 1;
                ngx_str_set(&r->headers_out.content_type, "application/json");
            }
            /* set last-modified if have */
            if (t->file_stat.modify_time > 0) {
                r->headers_out.last_modified_time = t->file_stat.modify_time;
            }

            r->headers_out.status = NGX_HTTP_OK;
            break;

            /* errno */
        default:
            switch (t->tfs_status) {
            default:
                r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }

            goto error_header;
        }
        break;

    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_DONE:
            ngx_http_tfs_clear_content_len();
            r->headers_out.status = NGX_HTTP_OK;
            break;
            /* errno */
        default:
            switch (t->tfs_status) {
            case NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR:
            case NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR:
                r->headers_out.status = NGX_HTTP_NOT_FOUND;
                break;
            default:
                r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }

            goto error_header;
        }
        break;

    case NGX_HTTP_TFS_ACTION_READ_FILE:
        switch (t->state) {
            /* maybe process buf overflow */
        case NGX_HTTP_TFS_STATE_READ_READ_DATA:
        case NGX_HTTP_TFS_STATE_READ_DONE:
            if (t->r_ctx.chk_file_hole && t->json_output) {
                r->headers_out.content_type_len = sizeof("application/json")- 1;
                ngx_str_set(&r->headers_out.content_type, "application/json");

            } else {
                if (t->headers_in.content_type != NULL) {
                    r->headers_out.content_type_len = t->headers_in.content_type->value.len;
                    r->headers_out.content_type = t->headers_in.content_type->value;
                    r->headers_out.content_type_lowcase = NULL;
                }
            }

            /* set last-modified if have */
            if (t->file_stat.modify_time > 0) {
                r->headers_out.last_modified_time = t->file_stat.modify_time;
            }

            r->headers_out.status = NGX_HTTP_OK;
            break;

        default:
            switch (t->tfs_status) {
            case NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR:
            case NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR:
                r->headers_out.status = NGX_HTTP_NOT_FOUND;
                break;
            default:
                r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }

            goto error_header;
        }
        break;

    case NGX_HTTP_TFS_ACTION_REMOVE_DIR:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_ACTION_DONE:
            ngx_http_tfs_clear_content_len();
            r->headers_out.status = NGX_HTTP_OK;
            break;

        default:
            switch (t->tfs_status) {
            case NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR:
            case NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR:
                r->headers_out.status = NGX_HTTP_NOT_FOUND;
                break;
            case NGX_HTTP_TFS_EXIT_DELETE_DIR_WITH_FILE_ERROR:
                r->headers_out.status = NGX_HTTP_FORBIDDEN;
                break;
            default:
                r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }

            goto error_header;
        }
        break;

    case NGX_HTTP_TFS_ACTION_LS_DIR:
    case NGX_HTTP_TFS_ACTION_LS_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_ACTION_DONE:
            if (t->r_ctx.chk_exist) {
                ngx_http_tfs_clear_content_len();

            } else {
                r->headers_out.content_type_len = sizeof("application/json")- 1;
                ngx_str_set(&r->headers_out.content_type, "application/json");
            }
            r->headers_out.status = NGX_HTTP_OK;
            break;
            /* errno */
        default:
            switch (t->tfs_status) {
            case NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR:
            case NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR:
                r->headers_out.status = NGX_HTTP_NOT_FOUND;
                break;
            default:
                r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }
            goto error_header;
        }
        break;

    case NGX_HTTP_TFS_ACTION_MOVE_DIR:
    case NGX_HTTP_TFS_ACTION_MOVE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_ACTION_DONE:
            ngx_http_tfs_clear_content_len();
            r->headers_out.status = NGX_HTTP_OK;
            break;
            /* errno */
        default:
            switch (t->tfs_status) {
            case NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR:
            case NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR:
                r->headers_out.status = NGX_HTTP_NOT_FOUND;
                break;
            case NGX_HTTP_TFS_EXIT_MOVE_TO_SUB_DIR_ERROR:
                r->headers_out.status = NGX_HTTP_FORBIDDEN;
                break;
            default:
                r->headers_out.status = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }
            goto error_header;
        }

    default:
        break;
    }

    ngx_log_error(NGX_LOG_INFO, t->log, 0,
                  "%V success", &ctx->action.msg);
    return;

error_header:
    ngx_http_tfs_clear_content_len();

    ngx_log_error(NGX_LOG_ERR, t->log, 0, "%V failed, err(%d)",
                  &ctx->action.msg, t->tfs_status);
}


static void
ngx_http_tfs_process_non_buffered_downstream(ngx_http_request_t *r)
{
    ngx_event_t       *wev;
    ngx_http_tfs_t    *t;
    ngx_connection_t  *c;

    c = r->connection;
    wev = c->write;
    t = ngx_http_get_module_ctx(r, ngx_http_tfs_module);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http tfs upstream process downstream");

    c->log->action = "sending to client";

    if (wev->timedout) {
        c->timedout = 1;
        ngx_connection_error(c, NGX_ETIMEDOUT, "client timed out");

        /* write need roll back, remove all segments */
        if (t->r_ctx.version == 1
            && t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE
            && t->r_ctx.is_raw_update == NGX_HTTP_TFS_NO
            && !t->parent)
        {
            r->write_event_handler = ngx_http_request_empty_handler;
            t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
            t->is_rolling_back = NGX_HTTP_TFS_YES;
            t->file.segment_index = 0;
            ngx_http_tfs_finalize_state(t, NGX_OK);
            return;
        }

        ngx_http_tfs_finalize_request(t->data, t,
                                      NGX_HTTP_REQUEST_TIME_OUT);
        return;
    }

    ngx_http_tfs_process_non_buffered_request(t, 1);
}


static void
ngx_http_tfs_process_non_buffered_request(ngx_http_tfs_t *t,
    ngx_uint_t do_write)
{
    size_t                     size;
    ssize_t                    n;
    ngx_int_t                  rc, finalize_state;
    ngx_buf_t                 *b;
    ngx_connection_t          *downstream, *upstream;
    ngx_http_request_t        *r;
    ngx_http_core_loc_conf_t  *clcf;

    r = t->data;
    finalize_state = 0;
    rc = 0;
    b = NULL;
    downstream = r->connection;
    upstream = NULL;

    if (t->r_ctx.version == 1) {
        /* data server */
        b = &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER].body_buffer;
        upstream =t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER].peer.connection;

    } else if (t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_GET_APPID) {
        b = &t->tfs_peer->body_buffer;
        upstream = t->tfs_peer->peer.connection;
    }

    for ( ;; ) {
        if (do_write) {

            if (t->out_bufs || t->busy_bufs) {

                rc = ngx_http_output_filter(r, t->out_bufs);

                if (rc == NGX_ERROR) {
                    ngx_http_tfs_finalize_request(r, t, 0);
                    return;
                }

#if defined(nginx_version) && (nginx_version > 1001003)
                ngx_chain_update_chains(t->pool, &t->free_bufs, &t->busy_bufs,
                                        &t->out_bufs, t->output.tag);
#else
                ngx_chain_update_chains(&t->free_bufs, &t->busy_bufs,
                                        &t->out_bufs, t->output.tag);
#endif
            }

            /* send all end */
            if (t->busy_bufs == NULL) {

                /* sub process */
                if (t->parent) {
                    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE
                        && t->state == NGX_HTTP_TFS_STATE_READ_DONE)
                    {
                        ngx_http_tfs_clear_buf(b);
                        ngx_http_tfs_finalize_request(r, t, NGX_DONE);
                        return;
                    }
                }

                t->output_size += t->main_conf->body_buffer_size;

                if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_GET_APPID
                    || (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE
                        && t->state == NGX_HTTP_TFS_STATE_READ_DONE)
                    || (t->r_ctx.version == 2
                        && t->state == NGX_HTTP_TFS_STATE_ACTION_DONE)
                    || (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_STAT_FILE
                        && t->state == NGX_HTTP_TFS_STATE_STAT_DONE)
                    || (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE
                        && t->state == NGX_HTTP_TFS_STATE_WRITE_DONE))
                {
                    /* need log size */
                    ngx_log_error(NGX_LOG_INFO, t->log, 0,
                                  "%V, output %uL byte",
                                  &t->r_ctx.action.msg, t->output_size);
                    ngx_http_tfs_finalize_request(r, t, 0);
                    return;
                }

                ngx_http_tfs_clear_buf(b);
            }
        }

        size = b->end - b->last;

        if (t->length > 0 && size && upstream->read->ready) {
            n = upstream->recv(upstream, b->last, size);

            if (n == NGX_AGAIN) {
                break;
            }

            if (n > 0) {
                b->last += n;
                do_write = 1;

                /* copy buf to out_bufs */
                rc = t->process_request_body(t);
                if (rc == NGX_ERROR) {
                    ngx_log_error(NGX_LOG_ERR, t->log, 0,
                                  "process request body failed");
                    ngx_http_tfs_finalize_request(t->data, t,
                                                NGX_HTTP_INTERNAL_SERVER_ERROR);
                    return;
                }

                /* ngx_ok or ngx_done */
                if (rc != NGX_AGAIN) {
                    finalize_state = 1;
                    break;
                }
            }

            continue;
        }

        break;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (downstream->data == r) {
        if (ngx_handle_write_event(downstream->write, clcf->send_lowat)
            != NGX_OK)
        {
            ngx_http_tfs_finalize_request(r, t, 0);
            return;
        }
    }

    if (downstream->write->active && !downstream->write->ready) {
        ngx_add_timer(downstream->write, clcf->send_timeout);

    } else if (downstream->write->timer_set) {
        ngx_del_timer(downstream->write);
    }

    if (t->length > 0 && upstream->read->active && !upstream->read->ready) {
        ngx_add_timer(upstream->read, t->main_conf->tfs_read_timeout);

    } else if (upstream->read->timer_set) {
        ngx_del_timer(upstream->read);
    }

    if (finalize_state) {
        ngx_http_tfs_finalize_state(t, rc);
    }
}


static void
ngx_http_tfs_process_buf_overflow(ngx_http_request_t *r, ngx_http_tfs_t *t)
{
    ngx_int_t  rc;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                  "tfs process buf overflow, %V", t->tfs_peer->peer.name);

    if ((t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE
         && t->state == NGX_HTTP_TFS_STATE_READ_READ_DATA))
    {
        rc = t->process_request_body(t);

        if (rc != NGX_AGAIN) {
            if (rc == NGX_ERROR) {
                ngx_log_error(NGX_LOG_ERR, t->log, 0,
                              "process request body failed");
                ngx_http_tfs_finalize_request(t->data, t,
                                              NGX_HTTP_INTERNAL_SERVER_ERROR);

            } else {
                ngx_http_tfs_finalize_state(t, rc);
            }
            return;
        }

        if (ngx_handle_read_event(t->tfs_peer->peer.connection->read, 0)
            != NGX_OK)
        {
            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                          "ngx handle read event failed");
            ngx_http_tfs_finalize_request(t->data, t,
                                          NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        ngx_http_tfs_send_response(r, t);

        return;

    }

    ngx_log_error(NGX_LOG_ERR, t->log, 0,
                  "action: %V should not come to here process buf overflow",
                  &t->r_ctx.action.msg);

    ngx_http_tfs_finalize_request(r, t, NGX_HTTP_INTERNAL_SERVER_ERROR);
}


void
ngx_http_tfs_finalize_request(ngx_http_request_t *r, ngx_http_tfs_t *t,
    ngx_int_t rc)
{
    ngx_uint_t              i;
    ngx_http_tfs_t         *next_st;
    ngx_peer_connection_t  *p;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "finalize http tfs request: %i", rc);

    if (t->parent
        && t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE
        && t->parent->sp_curr != t->sp_curr)
    {
        if (rc != NGX_DONE) {
            t->sp_fail_count++;
        }
        /* output in the right turn */
        t->sp_ready = NGX_HTTP_TFS_YES;
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "curr output segment is [%uD], [%uD] is ready, wait for call...",
                       t->parent->sp_curr, t->sp_curr);
        return;
    }

    for (i = 0; i < t->tfs_peer_count; i++) {
        p = &t->tfs_peer_servers[i].peer;
        if (p->free) {
            p->free(p, p->data, 0);
        }

        if (p->connection) {
            if (p->free) {
                p->free(p, p->data, 0);
            }

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "close http upstream connection: %d",
                           p->connection->fd);

            if (p->connection->pool) {
                ngx_destroy_pool(p->connection->pool);
            }

            ngx_close_connection(p->connection);
        }

        p->connection = NULL;
    }
#if (NGX_DEBUG)
    ngx_http_connection_pool_check(t->main_conf->conn_pool, t->log);
#endif

    /* sub process return here */
    if (t->parent) {
        /* free st for reuse */
        next_st = t->next;
        ngx_http_tfs_free_st(t);

        r->write_event_handler = ngx_http_request_empty_handler;

        if (rc == NGX_DONE) {
            t->parent->sp_succ_count++;
            t->parent->stat_info.size += t->stat_info.size;
            if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
                t->parent->file.left_length -=
                                        t->file.segment_data->segment_info.size;
            }

        } else {
            t->parent->sp_fail_count++;
            if (rc == NGX_HTTP_REQUEST_TIME_OUT) {
                t->parent->request_timeout = NGX_HTTP_TFS_YES;
            }
        }
        t->parent->sp_done_count++;
        t->parent->sp_curr++;
        /* all sub process done, wake up parent process */
        if (t->parent->sp_done_count == t->parent->sp_count){
            t->parent->sp_callback(t->parent);

        } else {
            if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE) {
                /* wake up next sub process */
                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, t->log, 0,
                               "segment[%uD] output complete, call next...",
                               t->sp_curr);
                if (next_st) {
                    next_st->sp_callback(next_st);
                }
            }
        }

        return;
    }

    /* rc-keepalive */
    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_KEEPALIVE) {
        t->finalize_request(t);
        return;
    }

    if (t->json_output) {
        ngx_http_tfs_json_destroy(t->json_output);
    }

    r->connection->log->action = "sending to client";
    if (rc == NGX_OK) {
        rc = ngx_http_send_special(r, NGX_HTTP_LAST);
    }

    ngx_http_finalize_request(r, rc);
}


static void
ngx_http_tfs_read_handler(ngx_http_request_t *r, ngx_http_tfs_t *t)
{
    ngx_connection_t               *c;
    ngx_http_tfs_peer_connection_t *tp;

    tp = t->tfs_peer;
    c = tp->peer.connection;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http tfs process tfs(%V) data", tp->peer.name);

    c->log->action = "reading response header from tfs";

    if (c->read->timedout) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "read from (%V: %s) timeout", tp->peer.name,
                      tp->peer_addr_text);
        ngx_http_tfs_handle_connection_failure(t, tp);
        return;
    }

    ngx_http_tfs_process_upstream_request(r, t);
}


static void
ngx_http_tfs_send_handler(ngx_http_request_t *r, ngx_http_tfs_t *t)
{
    ngx_connection_t                *c;
    ngx_http_tfs_peer_connection_t  *tp;

    tp = t->tfs_peer;
    c = tp->peer.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "http tfs send request");

    c->log->action = "sending request to tfs";

    if (c->write->timedout) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "connect or send to (%V: %s) timeout", tp->peer.name,
                      tp->peer_addr_text);
        ngx_http_tfs_handle_connection_failure(t, tp);
        return;
    }

    ngx_http_tfs_send(r, t);
}


static void
ngx_http_tfs_handle_connection_failure(ngx_http_tfs_t *t,
    ngx_http_tfs_peer_connection_t *tp)
{
    ngx_connection_t            *c;
    ngx_peer_connection_t       *p;
#if (NGX_DEBUG)
    ngx_http_connection_pool_t  *pool;
#endif

    p = &tp->peer;
    c = p->connection;
#if (NGX_DEBUG)
    /* failure connection can not be freed,
     * so make sure get&free op pairs are right
     */
    pool = p->data;
    pool->count++;
#endif

    /* close failure connection */
    if (c != NULL) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "close http upstream connection: %d",
                       c->fd);

        if (c->pool) {
            ngx_destroy_pool(c->pool);
        }

        ngx_close_connection(c);
    }
    p->connection = NULL;

    /* connect metaserver fail, get new table from rootserver */
    if (ngx_strcmp(p->name->data, ms_name.data) == 0) {
        t->state = NGX_HTTP_TFS_STATE_ACTION_GET_META_TABLE;
        ngx_http_tfs_peer_set_addr(t->pool,
                         &t->tfs_peer_servers[NGX_HTTP_TFS_ROOT_SERVER],
                         (ngx_http_tfs_inet_t *)&t->loc_conf->meta_root_server);
        ngx_http_tfs_finalize_state(t, NGX_OK);
        return;
    }

    /* connect dataserver fail, remove block cache */
    if (ngx_strcmp(p->name->data, ds_name.data) == 0) {
        ngx_http_tfs_remove_block_cache(t,
                                  &t->file.segment_data[t->file.segment_index]);
    }

    /*connect rcserver fail, select another rc server*/
    if (ngx_strncmp(p->name->data, rcs_name.data, p->name->len) == 0) {
        ngx_log_error(NGX_LOG_WARN, t->log, 0,
                "select a new rc server");
        ngx_http_tfs_select_rc_server(t);
    }

    ngx_http_tfs_finalize_state(t, NGX_HTTP_TFS_AGAIN);
}


ngx_int_t
ngx_http_tfs_set_output_appid(ngx_http_tfs_t *t, uint64_t app_id)
{
    ngx_chain_t  *cl, **ll;

    t->json_output = ngx_http_tfs_json_init(t->log, t->pool);
    if (t->json_output == NULL) {
        return NGX_ERROR;
    }

    for (cl = t->out_bufs, ll = &t->out_bufs; cl; cl = cl->next) {
        ll = &cl->next;
    }

    cl = ngx_http_tfs_json_appid(t->json_output, app_id);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    *ll = cl;
    return NGX_OK;
}


void
ngx_http_tfs_set_custom_initial_parameters(ngx_http_tfs_t *t)
{
    /* for stat log */
    t->file_name = t->r_ctx.file_path_s;
    t->r_ctx.file_suffix = t->r_ctx.file_path_d;

    switch(t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_CREATE_DIR:
    case NGX_HTTP_TFS_ACTION_CREATE_FILE:
        t->last_file_path = t->r_ctx.file_path_s;
        break;

    case NGX_HTTP_TFS_ACTION_MOVE_DIR:
    case NGX_HTTP_TFS_ACTION_MOVE_FILE:
        t->last_file_path = t->r_ctx.file_path_d;
        break;

    case NGX_HTTP_TFS_ACTION_LS_DIR:
    case NGX_HTTP_TFS_ACTION_LS_FILE:
        /* set initial ls parameter */
        t->last_file_path = t->r_ctx.file_path_s;
        t->last_file_pid = -1;
        t->last_file_type = t->r_ctx.file_type;
        break;

    case NGX_HTTP_TFS_ACTION_READ_FILE:
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        t->file.file_offset = t->r_ctx.offset;
        t->file.left_length = t->r_ctx.size;
        break;
    }
}


ngx_int_t
ngx_http_tfs_misc_ctx_init(ngx_http_tfs_t *t, ngx_http_tfs_rcs_info_t *rc_info)
{
    ngx_int_t                         rc;
    ngx_http_request_t               *r;
    ngx_http_tfs_inet_t              *addr;
    ngx_http_tfs_logical_cluster_t   *logical_cluster;

    /* raw tfs */
    if (t->r_ctx.version == 1) {
        switch (t->r_ctx.action.code) {
        case NGX_HTTP_TFS_ACTION_STAT_FILE:
            t->state = NGX_HTTP_TFS_STATE_STAT_GET_BLK_INFO;
            break;

        case NGX_HTTP_TFS_ACTION_READ_FILE:
            t->state = NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO;
            break;

        case NGX_HTTP_TFS_ACTION_WRITE_FILE:
            t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
            break;

        case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
            t->state = NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO;
            if (!t->is_large_file && rc_info->need_duplicate) {
                /* undelete, conceal and reveal
                 * do not go through de-duplicating
                 */
                if (t->r_ctx.unlink_type == NGX_HTTP_TFS_UNLINK_DELETE) {
                    t->is_stat_dup_file = NGX_HTTP_TFS_YES;
                    t->r_ctx.read_stat_type = NGX_HTTP_TFS_READ_STAT_FORCE;
                    t->use_dedup = NGX_HTTP_TFS_YES;
                    t->dedup_ctx.data = t;
                }
            }
            break;
        }

        rc = ngx_http_tfs_select_name_server(t, rc_info, &t->name_server_addr,
                                             &t->name_server_addr_text);
        if (rc == NGX_ERROR) {
            return NGX_HTTP_NOT_FOUND;
        }

        ngx_http_tfs_peer_set_addr(t->pool,
          &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER], &t->name_server_addr);

        if (!t->is_large_file
            || (t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_WRITE_FILE))
        {
            /* fill meta segment */
            rc = ngx_http_tfs_get_meta_segment(t);
            if (rc == NGX_ERROR) {
                ngx_log_error(NGX_LOG_ERR, t->log, 0,
                              "tfs get meta segment failed");
                return NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            /* small file */
            if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
                /* parse meta segment */
                if (t->r_ctx.write_meta_segment) {
                    rc = ngx_http_tfs_parse_meta_segment(t, t->send_body);
                    if (rc == NGX_ERROR) {
                        return NGX_ERROR;
                    }
                    t->send_body = t->meta_segment_data;
                }

                t->file.segment_data[0].data = t->send_body;
                /* copy data to orig_data so that we can retry write */
                rc = ngx_chain_add_copy_with_buf(t->pool,
                    &t->file.segment_data[0].orig_data, t->file.segment_data[0].data);
                if (rc == NGX_ERROR) {
                    return NGX_ERROR;
                }

                t->file.segment_data[0].segment_info.size =
                                 ngx_http_tfs_get_chain_buf_size(t->send_body);
                t->file.left_length= t->file.segment_data[0].segment_info.size;
                t->file.segment_data[0].oper_size =
                   ngx_min(t->file.left_length, NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);

            } else {
                /* set oper size && offset,
                 * large file must read the whole meta segment
                 */
                if (t->is_large_file) {
                    t->is_process_meta_seg = NGX_HTTP_TFS_YES;
                    t->file.file_offset = 0;
                    t->file.left_length = NGX_HTTP_TFS_MAX_SIZE;

                } else {
                    t->file.file_offset = t->r_ctx.offset;
                    t->file.left_length = t->r_ctx.size;
                }

                t->file.segment_data[0].oper_offset = t->file.file_offset;
                t->file.segment_data[0].oper_size =
                  ngx_min(t->file.left_length, NGX_HTTP_TFS_MAX_READ_FILE_SIZE);
            }
        }

    } else if (t->r_ctx.version == 2) {  /* custom tfs file */
        /* check permission */
        if (t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_READ_FILE
            && t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_LS_DIR
            && t->r_ctx.action.code != NGX_HTTP_TFS_ACTION_LS_FILE)
        {
            if (t->r_ctx.app_id != rc_info->app_id) {
                return NGX_HTTP_UNAUTHORIZED;
            }
        }

        /* check root server */
        if (rc_info->meta_root_server == 0) {
            return NGX_HTTP_BAD_REQUEST;
        }

        if (t->loc_conf->meta_root_server != rc_info->meta_root_server) {
            /* update root server & meta table */
            t->loc_conf->meta_root_server = rc_info->meta_root_server;
            t->loc_conf->meta_server_table.version = 0;
            ngx_http_tfs_peer_set_addr(t->pool,
                             &t->tfs_peer_servers[NGX_HTTP_TFS_ROOT_SERVER],
                             (ngx_http_tfs_inet_t *)&rc_info->meta_root_server);
        }

        /* next => root server */
        t->state += 1;

        /* check meta table */
        if (t->loc_conf->meta_server_table.version != 0) {
            /* skip root server */
            t->state += 1;

            ngx_http_tfs_set_custom_initial_parameters(t);

            addr = ngx_http_tfs_select_meta_server(t);

            ngx_http_tfs_peer_set_addr(t->pool,
                          &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER], addr);
        }
    }

    /* prepare:read:
     * remote block cache instance write(large file and custom file):
     * each segment's data
     */
    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        t->group_seq = -1;
        /* remove large_file && dedup unlink need to stat/read file */
        if (t->r_ctx.version == 2
            || !t->is_stat_dup_file
            || t->state != NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO)
        {
            break;
        }
    case NGX_HTTP_TFS_ACTION_STAT_FILE:
    case NGX_HTTP_TFS_ACTION_READ_FILE:
        if (t->main_conf->enable_remote_block_cache == NGX_CONF_UNSET) {
            if (rc_info->use_remote_block_cache) {
                t->block_cache_ctx.use_cache |= NGX_HTTP_TFS_REMOTE_BLOCK_CACHE;
            }
        }

        if (t->block_cache_ctx.use_cache & NGX_HTTP_TFS_REMOTE_BLOCK_CACHE) {
            rc = ngx_http_tfs_get_remote_block_cache_instance(
                                             &t->block_cache_ctx.remote_ctx,
                                             &rc_info->remote_block_cache_info);
            if (rc == NGX_ERROR) {
                ngx_log_error(NGX_LOG_ERR, t->log, 0,
                              "get remote block cache instance failed.");
                t->block_cache_ctx.use_cache &=~NGX_HTTP_TFS_REMOTE_BLOCK_CACHE;
            }
        }

        /* lookup block cache */
        if (t->r_ctx.version == 1) {
            t->decline_handler = ngx_http_tfs_lookup_block_cache;
            return NGX_DECLINED;
        }
        break;

    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        t->group_seq = -1;
        if (t->is_large_file || t->r_ctx.version == 2) {
            rc = ngx_http_tfs_get_segment_for_write(t);
            if (rc == NGX_ERROR) {
                return NGX_ERROR;
            }
        }
    }

    /* dedup related */
    if (t->r_ctx.version == 1
        && t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE
        && !t->is_large_file
        && rc_info->need_duplicate
        && !t->r_ctx.no_dedup)
    {
        /* update is not allowed when using dedup */
        if (t->r_ctx.is_raw_update > 0) {
            return NGX_HTTP_BAD_REQUEST;
        }

        t->dedup_ctx.data = t;
        logical_cluster = &rc_info->logical_clusters[t->logical_cluster_index];
        rc = ngx_http_tfs_get_dedup_instance(&t->dedup_ctx,
                                         &logical_cluster->dup_server_info,
                                         logical_cluster->dup_server_addr_hash);
        if (rc == NGX_ERROR) {
            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                          "get dedup instance failed.");
            /* no dedup */
            return NGX_OK;
        }

        t->use_dedup = NGX_HTTP_TFS_YES;
        /* dedup do not allow retry other ns */
        t->retry_curr_ns = NGX_HTTP_TFS_YES;

        r = t->data;
        t->dedup_ctx.file_data = r->request_body->bufs;
        t->decline_handler = ngx_http_tfs_get_duplicate_info;

        return NGX_DECLINED;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_get_duplicate_info(ngx_http_tfs_t *t)
{
    ngx_int_t  rc;

    rc = ngx_http_tfs_dedup_get(&t->dedup_ctx, t->pool, t->log);
    if (rc == NGX_ERROR) {
        if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_REMOVE_FILE
            && t->state == NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT)
        {
            /* get dup info from tair failed, do not unlink file */
            t->state = NGX_HTTP_TFS_STATE_REMOVE_DONE;
            rc = NGX_DONE;

        } else {
            /* no dedup */
            rc = NGX_OK;
        }

        ngx_http_tfs_finalize_state(t, rc);
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_set_duplicate_info(ngx_http_tfs_t *t)
{
    ngx_int_t  rc;

    rc = ngx_http_tfs_dedup_set(&t->dedup_ctx, t->pool,
                                t->log);
    /* save tair failed */
    if (rc == NGX_ERROR) {
        if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
            switch (t->state) {
            case NGX_HTTP_TFS_STATE_WRITE_STAT_DUP_FILE:
                /* stat success and file status normal */
                /* need save new tfs file, no more dedup */
                t->state = NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS;
                t->is_stat_dup_file = NGX_HTTP_TFS_NO;
                t->use_dedup = NGX_HTTP_TFS_NO;
                /* need reset output buf */
                t->out_bufs = NULL;
                /* need reset block id and file id */
                t->file.segment_data[0].segment_info.block_id = 0;
                t->file.segment_data[0].segment_info.file_id = 0;
                rc = NGX_OK;
                break;
            case NGX_HTTP_TFS_STATE_WRITE_DONE:
                rc = NGX_DONE;
            }
        }

        ngx_http_tfs_finalize_state(t, rc);
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_batch_process_start(ngx_http_tfs_t *t)
{
    uint32_t                         i;
    ngx_http_tfs_t                  *st, **tt;
    ngx_http_tfs_inet_t             *addr;
    ngx_http_tfs_segment_data_t     *segment_data;
    ngx_http_tfs_peer_connection_t  *data_server;

    segment_data = &t->file.segment_data[t->file.segment_index];

    t->sp_count = 0;
    t->sp_done_count = 0;
    t->sp_fail_count = 0;
    t->sp_succ_count = 0;
    t->sp_curr = t->file.segment_index;
    t->sp_callback = ngx_http_tfs_batch_process_end;
    tt = &t->next;

    /* create sub process */
    for (i = 0; i < t->file.curr_batch_count; i++) {
        st = ngx_http_tfs_alloc_st(t);
        if (st == NULL) {
            return NGX_ERROR;
        }

        st->sp_callback = ngx_http_tfs_batch_process_next;

        /* send(to upstream servers) and output(to client) bufs */
        st->request_bufs = NULL;
        st->out_bufs = NULL;

        /* set remote block cache ctx */
        st->block_cache_ctx.remote_ctx.data = st;

        /* assign segments to each st */
        st->file.segment_index = 0;
        st->file.segment_data = &segment_data[i];
        st->sp_curr = t->file.segment_index + i;
        st->sp_ready = NGX_HTTP_TFS_NO;
        st->stat_info.size = 0;

        if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
            st->file.left_length = st->file.segment_data->segment_info.size;
            st->state = NGX_HTTP_TFS_STATE_WRITE_CREATE_FILE_NAME;

        } else if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE) {
            /* custom file need check file hole before each segment */
            if (t->r_ctx.version == 2) {
                st->file.file_hole_size = 0;
                if (i < t->file.segment_count
                   && (t->file.file_offset
                       < segment_data[i].segment_info.offset))
                {
                    st->file.file_hole_size = ngx_min(t->file.left_length,
                        (uint64_t)(segment_data[i].segment_info.offset
                                   - t->file.file_offset));
                    t->file.file_offset += st->file.file_hole_size;
                    t->file.left_length -= st->file.file_hole_size;
                    ngx_log_error(NGX_LOG_DEBUG, t->log, 0,
                                  "find file hole, size: %uL",
                                  st->file.file_hole_size);
                }
            }
            st->file.file_offset = st->file.segment_data->oper_offset;
            st->file.left_length = st->file.segment_data->oper_size;
            t->file.file_offset += st->file.segment_data->oper_size;
            t->file.left_length -= st->file.segment_data->oper_size;

            st->state = NGX_HTTP_TFS_STATE_READ_READ_DATA;
        }

        /* select data server */
        addr = ngx_http_tfs_select_data_server(st, st->file.segment_data);
        if (addr == NULL) {
            return NGX_ERROR;
        }

        data_server = &st->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];
        ngx_http_tfs_peer_set_addr(t->pool, data_server, addr);

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "block_id: %uD, select data server: %s",
                       st->file.segment_data->segment_info.block_id,
                       data_server->peer_addr_text);

        if (ngx_http_tfs_reinit(t->data, st) != NGX_OK) {
            return NGX_ERROR;
        }

        st->tfs_peer = ngx_http_tfs_select_peer(st);
        if (st->tfs_peer == NULL) {
            return NGX_ERROR;
        }

        st->recv_chain->buf = &st->header_buffer;
        st->recv_chain->next->buf = &st->tfs_peer->body_buffer;

        *tt = st;
        tt = &st->next;

        t->sp_count++;

        if (t->file.left_length == 0) {
            break;
        }
    }
    *tt = NULL;

    /* start sub process */
    for (st = t->next; st; st = t->next) {
        /* st->next may be modified after recycled to free_st */
        t->next = st->next;
        ngx_http_tfs_connect(st);
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_batch_process_end(ngx_http_tfs_t *t)
{
    ngx_int_t            rc = NGX_ERROR;
    ngx_buf_t           *body_buffer;
    ngx_http_request_t  *r;

    /* error in sub process */
    if (t->sp_fail_count > 0) {
        ngx_log_error(NGX_LOG_ERR, t->log, 0,
                      "sub process error, rest segment count: %D ",
                      t->file.segment_count - t->file.segment_index);

        /* write need roll back, remove all segments writtern */
        if (t->r_ctx.version == 1
            && t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE)
        {
            t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;
            t->is_rolling_back = NGX_HTTP_TFS_YES;
            t->file.segment_count = t->file.segment_index + t->sp_count;
            t->file.segment_index = 0;
            ngx_http_tfs_finalize_state(t, NGX_OK);
            return NGX_OK;
        }

        if (t->request_timeout) {
            ngx_http_tfs_finalize_request(t->data, t,
                                          NGX_HTTP_REQUEST_TIME_OUT);

        } else if (t->client_abort) {
            ngx_http_tfs_finalize_request(t->data, t,
                                          NGX_HTTP_CLIENT_CLOSED_REQUEST);

        } else {
            ngx_http_tfs_finalize_state(t, NGX_ERROR);
        }
        return NGX_ERROR;
    }

    t->file.segment_index += t->sp_count;
    t->file.curr_batch_count = 0;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, t->log, 0,
                   "batch process segment count: %uD, rest segment count: %D ",
                   t->sp_count, t->file.segment_count - t->file.segment_index);

    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
        /* large_file data segment && custom file */
        if (t->r_ctx.version == 1 && t->is_large_file) {
            t->state = NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO;

            /* need roll back, remove all segments writtern */
            if (t->client_abort) {
                t->is_rolling_back = NGX_HTTP_TFS_YES;
                t->file.segment_count = t->file.segment_index;
                t->file.segment_index = 0;

            } else {
                /* all data write over */
                if (t->file.left_length == 0) {
                    rc = ngx_http_tfs_set_meta_segment_data(t);
                    if (rc == NGX_ERROR) {
                        ngx_http_tfs_finalize_state(t, NGX_ERROR);
                        return NGX_ERROR;
                    }
                }
            }

        } else if (t->r_ctx.version == 2) {
            t->state = NGX_HTTP_TFS_STATE_WRITE_WRITE_MS;
        }

        rc = NGX_OK;

    } else if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE) {
        if (t->file.segment_index < t->file.segment_count
            && t->file.left_length > 0)
        {
            t->state = NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO;

            /* batch lookup block cache */
            t->block_cache_ctx.curr_lookup_cache =
                                               NGX_HTTP_TFS_LOCAL_BLOCK_CACHE;
            return ngx_http_tfs_batch_lookup_block_cache(t);
        }

        /* read over, restore request's ctx */
        r = t->data;
        ngx_http_set_ctx(r, t, ngx_http_tfs_module);
        rc = NGX_DONE;

        if (t->is_large_file) {
            t->state = NGX_HTTP_TFS_STATE_READ_DONE;
            t->file_name = t->r_ctx.file_path_s;
        }

        if (t->r_ctx.version == 2) {
            if (t->file.still_have) {
                t->state = NGX_HTTP_TFS_STATE_READ_GET_FRAG_INFO;
                body_buffer =
                 &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER].body_buffer;
                ngx_http_tfs_clear_buf(body_buffer);
                rc = NGX_OK;

            } else {
                t->state = NGX_HTTP_TFS_STATE_READ_DONE;
            }
        }
    }

    ngx_http_tfs_finalize_state(t, rc);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_batch_process_next(ngx_http_tfs_t *t)
{
    if (t->sp_ready) {
        if (t->sp_fail_count > 0 || t->parent->sp_fail_count > 0) {
            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                          "(other) sub process failed");

            ngx_http_tfs_finalize_request(t->data, t, NGX_ERROR);
            return NGX_OK;
        }

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, t->log, 0,
                       "segment[%uD] wake up, will output...",
                       t->sp_curr);
        ngx_http_tfs_send_response(t->data, t);
    }

    return NGX_OK;
}


static void
ngx_http_tfs_rd_check_broken_connection(ngx_http_request_t *r)
{
    ngx_http_tfs_check_broken_connection(r, r->connection->read);
}


static void
ngx_http_tfs_wr_check_broken_connection(ngx_http_request_t *r)
{
    ngx_http_tfs_check_broken_connection(r, r->connection->write);
}


static void
ngx_http_tfs_check_broken_connection(ngx_http_request_t *r,
    ngx_event_t *ev)
{
    int               n;
    char              buf[1];
    ngx_err_t         err;
    ngx_int_t         event;
    ngx_http_tfs_t    *t;
    ngx_connection_t  *c;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "http tfs check client, write event:%d, \"%V\"",
                   ev->write, &r->uri);

    c = r->connection;
    t = ngx_http_get_module_ctx(r, ngx_http_tfs_module);

    if (c->error) {
        if ((ngx_event_flags & NGX_USE_LEVEL_EVENT) && ev->active) {

            event = ev->write ? NGX_WRITE_EVENT : NGX_READ_EVENT;

            ngx_del_event(ev, event, 0);
        }

        t->client_abort = NGX_HTTP_TFS_YES;

        return;
    }

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT) {

        if (!ev->pending_eof) {
            return;
        }

        ev->eof = 1;
        c->error = 1;

        if (ev->kq_errno) {
            ev->error = 1;
        }

        ngx_log_error(NGX_LOG_INFO, ev->log, ev->kq_errno,
                      "kevent() reported that client prematurely closed "
                      "connection");
        t->client_abort = NGX_HTTP_TFS_YES;

        return;
    }

#endif

    n = recv(c->fd, buf, 1, MSG_PEEK);

    err = ngx_socket_errno;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ev->log, err,
                   "http tfs recv(): %d", n);

    if (ev->write && (n >= 0 || err == NGX_EAGAIN)) {
        return;
    }

    if ((ngx_event_flags & NGX_USE_LEVEL_EVENT) && ev->active) {

        event = ev->write ? NGX_WRITE_EVENT : NGX_READ_EVENT;

        ngx_del_event(ev, event, 0);
    }

    if (n > 0) {
        return;
    }

    if (n == -1) {
        if (err == NGX_EAGAIN) {
            return;
        }

        ev->error = 1;

    } else { /* n == 0 */
        err = 0;
    }

    ev->eof = 1;
    c->error = 1;

    ngx_log_error(NGX_LOG_INFO, ev->log, err,
                  "client prematurely closed connection");

    t->client_abort = NGX_HTTP_TFS_YES;
}
