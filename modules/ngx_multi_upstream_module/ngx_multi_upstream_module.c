
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>

#include "ngx_multi_upstream_module.h"

ngx_multi_connection_t* 
ngx_get_multi_connection(ngx_connection_t *c)
{
    ngx_multi_connection_t  *multi_c;

    multi_c = c->multi_c;

    return multi_c;
}

ngx_flag_t 
ngx_multi_connected(ngx_connection_t *c)
{
    ngx_multi_connection_t  *multi_c;

    multi_c = ngx_get_multi_connection(c);

    return multi_c->connected;
}

static void
ngx_multi_cleanup(void *data)
{
    ngx_multi_connection_t      *multi_c = data;
    ngx_multi_request_t         *multi_r;
    ngx_queue_t                 *q;

    //clean multi_r on sending
    while (!ngx_queue_empty(&multi_c->send_list)) {
        q = ngx_queue_head(&multi_c->send_list);

        ngx_queue_remove(q);

        multi_r = ngx_queue_data(q, ngx_multi_request_t, backend_queue);

        ngx_log_error(NGX_LOG_WARN, multi_c->connection->log, 0, 
                      "multi: cleanup send list has multi_r unfinished %p, %p",
                      multi_r, multi_r->data);

        //clean front list on front connection
        ngx_queue_remove(&multi_r->front_queue);

        //free multi_r and pool
        ngx_destroy_pool(multi_r->pool);
    }

    while (!ngx_queue_empty(&multi_c->leak_list)) {
        q = ngx_queue_head(&multi_c->leak_list);

        ngx_queue_remove(q);

        multi_r = ngx_queue_data(q, ngx_multi_request_t, backend_queue);

        ngx_log_error(NGX_LOG_WARN, multi_c->connection->log, 0,
                      "multi: cleanup leak list has multi_r unfinished %p, %p",
                      multi_r, multi_r->data);

        //free multi_r and pool
        ngx_destroy_pool(multi_r->pool);
    }
}

ngx_multi_connection_t*
ngx_create_multi_connection(ngx_connection_t *c)
{
    ngx_multi_connection_t      *multi_c;
    ngx_pool_cleanup_t          *cln;

    //init multi connection
    multi_c = ngx_pcalloc(c->pool, sizeof(ngx_multi_connection_t));
    if (multi_c == NULL) {
        return NULL;
    }

    ngx_queue_init(&multi_c->data);
    ngx_queue_init(&multi_c->send_list);
    ngx_queue_init(&multi_c->leak_list);
    ngx_queue_init(&multi_c->waiting_list);
    
    multi_c->connection = c;

    cln = ngx_pool_cleanup_add(c->pool, 0);
    if (cln == NULL) {
        return NULL;
    }

    cln->handler = ngx_multi_cleanup;
    cln->data = multi_c;

    return multi_c;
}

ngx_multi_request_t*
ngx_create_multi_request(ngx_connection_t *c, void *data)
{
    ngx_multi_request_t     *multi_r;
    ngx_pool_t              *pool;

    pool = ngx_create_pool(4096, c->log);
    if (pool == NULL) {
        return NULL;
    }

    multi_r = ngx_pcalloc(pool, sizeof(ngx_multi_request_t));
    if (multi_r == NULL) {
        ngx_destroy_pool(pool);
        return NULL;
    }

    multi_r->data = data;
    multi_r->pool = pool;

    return multi_r;
}

void
ngx_multi_clean_leak(ngx_connection_t *c)
{
    ngx_queue_t             *q;
    ngx_multi_connection_t  *multi_c;
    ngx_multi_request_t     *multi_r;

    multi_c = ngx_get_multi_connection(c);

    if (multi_c) {
        while (!ngx_queue_empty(&multi_c->leak_list)) {
            q = ngx_queue_head(&multi_c->leak_list);

            ngx_queue_remove(q);

            multi_r = ngx_queue_data(q, ngx_multi_request_t, backend_queue);

            //free hsf_r and pool
            ngx_destroy_pool(multi_r->pool);
        }
    }
}

