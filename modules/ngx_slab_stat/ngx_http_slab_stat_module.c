
/*
 * Copyright (C) 2017 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_slab.h>


static char *ngx_http_slab_stat(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_slab_stat_buf(ngx_pool_t *pool, ngx_buf_t *b);

static ngx_command_t  ngx_http_slab_stat_commands[] = {

    { ngx_string("slab_stat"),
      NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
      ngx_http_slab_stat,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_slab_stat_module_ctx = {
    NULL,                          /* preconfiguration */
    NULL,                          /* postconfiguration */

    NULL,                          /* create main configuration */
    NULL,                          /* init main configuration */

    NULL,                          /* create server configuration */
    NULL,                          /* merge server configuration */

    NULL,                          /* create location configuration */
    NULL                           /* merge location configuration */
};


ngx_module_t  ngx_http_slab_stat_module = {
    NGX_MODULE_V1,
    &ngx_http_slab_stat_module_ctx,     /* module context */
    ngx_http_slab_stat_commands,        /* module directives */
    NGX_HTTP_MODULE,                    /* module type */
    NULL,                               /* init master */
    NULL,                               /* init module */
    NULL,                               /* init process */
    NULL,                               /* init thread */
    NULL,                               /* exit thread */
    NULL,                               /* exit process */
    NULL,                               /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_slab_stat_handler(ngx_http_request_t *r)
{
    ngx_int_t    rc;
    ngx_buf_t   *b;
    ngx_chain_t  out;

    if (r->method != NGX_HTTP_GET) {
        return NGX_HTTP_NOT_ALLOWED;
    }

    rc = ngx_http_discard_request_body(r);
    if (rc != NGX_OK) {
        return rc;
    }

    b = ngx_pcalloc(r->pool, sizeof(ngx_buf_t));
    if (b == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (ngx_http_slab_stat_buf(r->pool, b) == NGX_ERROR) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = b->last - b->pos;

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    out.buf = b;
    out.next = NULL;

    return ngx_http_output_filter(r, &out);
}


static ngx_int_t
ngx_http_slab_stat_buf(ngx_pool_t *pool, ngx_buf_t *b)
{
    u_char                       *p;
    size_t                        pz, size;
    ngx_uint_t                    i, k, n;
    ngx_shm_zone_t               *shm_zone;
    ngx_slab_pool_t              *shpool;
    ngx_slab_page_t              *page;
    ngx_slab_stat_t              *stats;
    volatile ngx_list_part_t     *part;

#define NGX_SLAB_SHM_SIZE               (sizeof("* shared memory: \n") - 1)
#define NGX_SLAB_SHM_FORMAT             "* shared memory: %V\n"
#define NGX_SLAB_SUMMARY_SIZE           \
    (3 * 12 + sizeof("total:(KB) free:(KB) size:(KB)\n") - 1)
#define NGX_SLAB_SUMMARY_FORMAT         \
    "total:%12z(KB) free:%12z(KB) size:%12z(KB)\n"
#define NGX_SLAB_PAGE_ENTRY_SIZE        \
    (12 + 2 * 16 + sizeof("pages:(KB) start: end:\n") - 1)
#define NGX_SLAB_PAGE_ENTRY_FORMAT      \
    "pages:%12z(KB) start:%p end:%p\n"
#define NGX_SLAB_SLOT_ENTRY_SIZE        \
    (12 * 5 + sizeof("slot:(Bytes) total: used: reqs: fails:\n") - 1)
#define NGX_SLAB_SLOT_ENTRY_FORMAT      \
    "slot:%12z(Bytes) total:%12z used:%12z reqs:%12z fails:%12z\n"

    pz = 0;

    /* query shared memory */

    part = &ngx_cycle->shared_memory.part;
    shm_zone = part->elts;

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            shm_zone = part->elts;
            i = 0;
        }

        pz += NGX_SLAB_SHM_SIZE + (size_t)shm_zone[i].shm.name.len;
        pz += NGX_SLAB_SUMMARY_SIZE;

        shpool = (ngx_slab_pool_t *) shm_zone[i].shm.addr;

        ngx_shmtx_lock(&shpool->mutex);

        for (page = shpool->free.next; page != &shpool->free; page = page->next) {
            pz += NGX_SLAB_PAGE_ENTRY_SIZE;
        }

        n = ngx_pagesize_shift - shpool->min_shift;

        ngx_shmtx_unlock(&shpool->mutex);

        for (k = 0; k < n; k++) {
            pz += NGX_SLAB_SLOT_ENTRY_SIZE;
        }

    }

    /* preallocate pz * 2 to make sure memory enough */
    p = ngx_palloc(pool, pz * 2);
    if (p == NULL) {
        return NGX_ERROR;
    }

    b->pos = p;

    size = 1 << ngx_pagesize_shift;

    part = &ngx_cycle->shared_memory.part;
    shm_zone = part->elts;

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            shm_zone = part->elts;
            i = 0;
        }

        shpool = (ngx_slab_pool_t *) shm_zone[i].shm.addr;

        p = ngx_snprintf(p, NGX_SLAB_SHM_SIZE + shm_zone[i].shm.name.len,
            NGX_SLAB_SHM_FORMAT, &shm_zone[i].shm.name);

        ngx_shmtx_lock(&shpool->mutex);

        p = ngx_snprintf(p, NGX_SLAB_SUMMARY_SIZE, NGX_SLAB_SUMMARY_FORMAT,
            shm_zone[i].shm.size / 1024, shpool->pfree * size / 1024,
            size / 1024, shpool->pfree);

        for (page = shpool->free.next; page != &shpool->free; page = page->next) {
            p = ngx_snprintf(p, NGX_SLAB_PAGE_ENTRY_SIZE,
                NGX_SLAB_PAGE_ENTRY_FORMAT, page->slab * size / 1024,
                shpool->start, shpool->end);
        }

        stats = shpool->stats;

        n = ngx_pagesize_shift - shpool->min_shift;

        for (k = 0; k < n; k++) {
            p = ngx_snprintf(p, NGX_SLAB_SLOT_ENTRY_SIZE, NGX_SLAB_SLOT_ENTRY_FORMAT,
                1 << (k + shpool->min_shift),
                stats[k].total, stats[k].used, stats[k].reqs, stats[k].fails);
        }

        ngx_shmtx_unlock(&shpool->mutex);
    }

    b->last = p;
    b->memory = 1;
    b->last_buf = 1;

    return NGX_OK;
}


static char *
ngx_http_slab_stat(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_slab_stat_handler;

    return NGX_CONF_OK;
}
