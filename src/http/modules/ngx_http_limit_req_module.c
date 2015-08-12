
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    u_char                       color;
    u_char                       dummy;
    u_short                      len;
    ngx_queue_t                  queue;
    ngx_msec_t                   last;
    /* integer value, 1 corresponds to 0.001 r/s */
    ngx_uint_t                   excess;
    ngx_uint_t                   count;
    u_char                       data[1];
} ngx_http_limit_req_node_t;


typedef struct {
    ngx_rbtree_t                  rbtree;
    ngx_rbtree_node_t             sentinel;
    ngx_queue_t                   queue;
} ngx_http_limit_req_shctx_t;


typedef struct {
    ngx_int_t                    index;
    ngx_str_t                    var;
} ngx_http_limit_req_variable_t;


typedef struct {
    ngx_http_limit_req_shctx_t  *sh;
    ngx_slab_pool_t             *shpool;
    /* integer value, 1 corresponds to 0.001 r/s */
    ngx_uint_t                   rate;
    ngx_http_complex_value_t     key;
    ngx_http_limit_req_node_t   *node;
    ngx_array_t                 *limit_vars;
} ngx_http_limit_req_ctx_t;


typedef struct {
    ngx_shm_zone_t              *shm_zone;
    /* integer value, 1 corresponds to 0.001 r/s */
    ngx_uint_t                   burst;
    ngx_uint_t                   nodelay; /* unsigned  nodelay:1 */
    ngx_str_t                    forbid_action;
} ngx_http_limit_req_limit_t;


typedef struct {
    ngx_flag_t                   enable;

    ngx_array_t                 *rules;

    ngx_str_t                    geo_var_name;
    ngx_int_t                    geo_var_index;
    ngx_str_t                    geo_var_value;

    ngx_array_t                  limits;
    ngx_uint_t                   limit_log_level;
    ngx_uint_t                   delay_log_level;
    ngx_uint_t                   status_code;
} ngx_http_limit_req_conf_t;


static void ngx_http_limit_req_delay(ngx_http_request_t *r);
static ngx_int_t ngx_http_limit_req_lookup(ngx_http_request_t *r,
    ngx_http_limit_req_limit_t *limit_req, ngx_uint_t hash, ngx_uint_t *ep);
static void ngx_http_limit_req_expire(ngx_http_request_t *r, ngx_http_limit_req_ctx_t *ctx,
    ngx_uint_t n);

static void *ngx_http_limit_req_create_conf(ngx_conf_t *cf);
static char *ngx_http_limit_req_merge_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_limit_req_zone(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_limit_req(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_limit_req_whitelist(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_limit_req_init(ngx_conf_t *cf);



static ngx_conf_enum_t  ngx_http_limit_req_log_levels[] = {
    { ngx_string("info"), NGX_LOG_INFO },
    { ngx_string("notice"), NGX_LOG_NOTICE },
    { ngx_string("warn"), NGX_LOG_WARN },
    { ngx_string("error"), NGX_LOG_ERR },
    { ngx_null_string, 0 }
};


static ngx_conf_num_bounds_t  ngx_http_limit_req_status_bounds = {
    ngx_conf_check_num_bounds, 400, 599
};


static ngx_command_t  ngx_http_limit_req_commands[] = {

    { ngx_string("limit_req_zone"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_2MORE,
      ngx_http_limit_req_zone,
      0,
      0,
      NULL },

    { ngx_string("limit_req"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1234,
      ngx_http_limit_req,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("limit_req_whitelist"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_http_limit_req_whitelist,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("limit_req_log_level"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_enum_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_limit_req_conf_t, limit_log_level),
      &ngx_http_limit_req_log_levels },

    { ngx_string("limit_req_status"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_limit_req_conf_t, status_code),
      &ngx_http_limit_req_status_bounds },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_limit_req_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_http_limit_req_init,               /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_limit_req_create_conf,        /* create location configuration */
    ngx_http_limit_req_merge_conf          /* merge location configuration */
};


ngx_module_t  ngx_http_limit_req_module = {
    NGX_MODULE_V1,
    &ngx_http_limit_req_module_ctx,        /* module context */
    ngx_http_limit_req_commands,           /* module directives */
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


static inline ngx_int_t
ngx_http_limit_req_ip_filter(ngx_http_request_t *r,
    ngx_http_limit_req_conf_t *lrcf)
{
    ngx_http_variable_value_t    *vv;

    if (lrcf->geo_var_index != NGX_CONF_UNSET) {
        vv = ngx_http_get_indexed_variable(r, lrcf->geo_var_index);

        if (vv == NULL || vv->not_found) {
            return NGX_DECLINED;
        }

        if ((vv->len == lrcf->geo_var_value.len)
             && (ngx_memcmp(vv->data, lrcf->geo_var_value.data, vv->len) == 0))
        {
            return NGX_OK;
        }
    }

    return NGX_DECLINED;
}


static ngx_int_t
ngx_http_limit_req_copy_variables(ngx_http_request_t *r, uint32_t *hash,
    ngx_http_limit_req_ctx_t *ctx, ngx_http_limit_req_node_t *node)
{
    u_char                        *p;
    size_t                         len, total_len;
    ngx_uint_t                     j;
    ngx_http_variable_value_t     *vv;
    ngx_http_limit_req_variable_t *lrv;

    total_len = 0;
    p = NULL;

    if (node != NULL) {
        p = node->data;
    }

    lrv = ctx->limit_vars->elts;
    for (j = 0; j < ctx->limit_vars->nelts; j++) {
        vv = ngx_http_get_indexed_variable(r, lrv[j].index);
        if (vv == NULL || vv->not_found) {
            total_len = 0;
            break;
        }

        len = vv->len;

        if (len == 0) {
            total_len = 0;
            break;
        }

        if (len > 65535) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "the value of the \"%V\" variable "
                          "is more than 65535 bytes: \"%v\"",
                          &lrv[j].var, vv);
            total_len = 0;
            break;
        }

        if (node == NULL) {
            total_len += len;
            ngx_crc32_update(hash, vv->data, len);
        } else {
            p = ngx_cpymem(p, vv->data, len);
        }
    }

    return total_len;
}


static ngx_int_t
ngx_http_limit_req_handler(ngx_http_request_t *r)
{
    size_t                         n, total_len;
    uint32_t                       hash;
    ngx_int_t                      rc;
    ngx_msec_t                     delay_time;
    ngx_uint_t                     excess, delay_excess, delay_postion,
                                   nodelay, i;
    ngx_time_t                    *tp;
    ngx_rbtree_node_t             *node;
    ngx_http_limit_req_limit_t    *limit_req;
    ngx_http_limit_req_ctx_t      *ctx;
    ngx_http_limit_req_node_t     *lr;
    ngx_http_limit_req_conf_t     *lrcf;

    delay_excess = 0;
    excess = 0;
    delay_postion = 0;
    nodelay = 0;
    ctx = NULL;
    rc = NGX_DECLINED;

    if (r->main->limit_req_set) {
        return NGX_DECLINED;
    }

    lrcf = ngx_http_get_module_loc_conf(r, ngx_http_limit_req_module);
    if (lrcf->rules == NULL) {
        return NGX_DECLINED;
    }

    if (!lrcf->enable) {
        return NGX_DECLINED;
    }

    /* filter whitelist */
    if (ngx_http_limit_req_ip_filter(r, lrcf) == NGX_OK) {
        return NGX_DECLINED;
    }

    /* to match limit_req rule*/
    limit_req = lrcf->rules->elts;
    for (i = 0; i < lrcf->rules->nelts; i++) {
        ctx = limit_req[i].shm_zone->data;

        ngx_crc32_init(hash);

        total_len = ngx_http_limit_req_copy_variables(r, &hash, ctx, NULL);
        if (total_len == 0) {
            continue;
        }

        ngx_crc32_final(hash);

        ngx_shmtx_lock(&ctx->shpool->mutex);

        ngx_http_limit_req_expire(r, ctx, 1);

        rc = ngx_http_limit_req_lookup(r, &limit_req[i], hash, &excess);

        ngx_log_debug5(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "limit_req module: %i %ui.%03ui "
                       "hash is %D total_len is %uz",
                       rc, excess / 1000, excess % 1000, hash, total_len);

        /* first limit_req */
        if (rc == NGX_DECLINED) {

            n = offsetof(ngx_rbtree_node_t, color)
                + offsetof(ngx_http_limit_req_node_t, data)
                + total_len;

            node = ngx_slab_alloc_locked(ctx->shpool, n);
            if (node == NULL) {
                ngx_http_limit_req_expire(r, ctx, 0);
                node = ngx_slab_alloc_locked(ctx->shpool, n);
                if (node == NULL) {
                    ngx_log_error(NGX_LOG_ALERT, ngx_cycle->log, 0,
                                  "could not allocate node%s",
                                  ctx->shpool->log_ctx);

                    ngx_shmtx_unlock(&ctx->shpool->mutex);
                    return lrcf->status_code;
                }
            }

            lr = (ngx_http_limit_req_node_t *) &node->color;

            node->key = hash;
            lr->len = (u_short) total_len;

            tp = ngx_timeofday();
            lr->last = (ngx_msec_t) (tp->sec * 1000 + tp->msec);

            lr->excess = 0;
            ngx_http_limit_req_copy_variables(r, &hash, ctx, lr);

            ngx_queue_insert_head(&ctx->sh->queue, &lr->queue);
            ngx_rbtree_insert(&ctx->sh->rbtree, node);

            ngx_shmtx_unlock(&ctx->shpool->mutex);

            continue;
        }

        ngx_shmtx_unlock(&ctx->shpool->mutex);

        if (rc == NGX_BUSY || rc == NGX_ERROR) {
            break;
        }

        /* NGX_AGAIN or NGX_OK */

        if (delay_excess < excess) {
            delay_excess = excess;
            nodelay = limit_req[i].nodelay;
            delay_postion = i;
        }
    }

    r->main->limit_req_set = 1;

    if (rc == NGX_BUSY || rc == NGX_ERROR) {
        if (rc == NGX_BUSY) {
            ngx_log_error(lrcf->limit_log_level, r->connection->log, 0,
                          "limiting requests, excess: %ui.%03ui by zone \"%V\"",
                          excess / 1000, excess % 1000,
                          &limit_req[i].shm_zone->shm.name);
        }

        if (rc == NGX_ERROR || limit_req[i].forbid_action.len == 0) {
            return lrcf->status_code;

        } else if (limit_req[i].forbid_action.data[0] == '@') {

            ngx_log_error(lrcf->limit_log_level, r->connection->log, 0,
                          "limiting requests, forbid_action is %V",
                          &limit_req[i].forbid_action);
            (void) ngx_http_named_location(r, &limit_req[i].forbid_action);

        } else {

            ngx_log_error(lrcf->limit_log_level, r->connection->log, 0,
                          "limiting requests, forbid_action is %V",
                          &limit_req[i].forbid_action);
            (void) ngx_http_internal_redirect(r,
                                             &limit_req[i].forbid_action,
                                             &r->args);
        }

        ngx_http_finalize_request(r, NGX_DONE);
        return NGX_DONE;
    }

    /* rc = NGX_AGAIN */
    if (delay_excess != 0) {

        if (nodelay) {
            return NGX_DECLINED;
        }

        delay_time = (ngx_msec_t) delay_excess * 1000 / ctx->rate;
        ngx_log_error(lrcf->delay_log_level, r->connection->log, 0,
                      "delaying request,"
                      "excess: %ui.%03ui, by zone \"%V\", delay \"%M\" ms",
                      delay_excess / 1000, delay_excess % 1000,
                      &limit_req[delay_postion].shm_zone->shm.name, delay_time);

        if (ngx_handle_read_event(r->connection->read, 0) != NGX_OK) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        r->read_event_handler = ngx_http_test_reading;
        r->write_event_handler = ngx_http_limit_req_delay;
        ngx_add_timer(r->connection->write, delay_time);

        return NGX_AGAIN;
    }

    /* rc == NGX_OK or rc == NGX_DECLINED */

    return NGX_DECLINED;
}


static void
ngx_http_limit_req_delay(ngx_http_request_t *r)
{
    ngx_event_t  *wev;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "limit_req delay");

    wev = r->connection->write;

    if (!wev->timedout) {

        if (ngx_handle_write_event(wev, 0) != NGX_OK) {
            ngx_http_finalize_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
        }

        return;
    }

    wev->timedout = 0;

    if (ngx_handle_read_event(r->connection->read, 0) != NGX_OK) {
        ngx_http_finalize_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    r->read_event_handler = ngx_http_block_reading;
    r->write_event_handler = ngx_http_core_run_phases;

    ngx_http_core_run_phases(r);
}


static void
ngx_http_limit_req_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel)
{
    ngx_rbtree_node_t          **p;
    ngx_http_limit_req_node_t   *lrn, *lrnt;

    for ( ;; ) {

        if (node->key < temp->key) {

            p = &temp->left;

        } else if (node->key > temp->key) {

            p = &temp->right;

        } else { /* node->key == temp->key */

            lrn = (ngx_http_limit_req_node_t *) &node->color;
            lrnt = (ngx_http_limit_req_node_t *) &temp->color;

            p = (ngx_memn2cmp(lrn->data, lrnt->data, lrn->len, lrnt->len) < 0)
                ? &temp->left : &temp->right;
        }

        if (*p == sentinel) {
            break;
        }

        temp = *p;
    }

    *p = node;
    node->parent = temp;
    node->left = sentinel;
    node->right = sentinel;
    ngx_rbt_red(node);
}


static ngx_int_t
ngx_http_limit_req_lookup(ngx_http_request_t *r,
    ngx_http_limit_req_limit_t *limit_req, ngx_uint_t hash, ngx_uint_t *ep)
{
    u_char                          *lr_data, *lr_last;
    size_t                           lr_vv_len;
    ngx_int_t                        rc, excess;
    ngx_uint_t                       i;
    ngx_time_t                      *tp;
    ngx_msec_t                       now;
    ngx_msec_int_t                   ms;
    ngx_rbtree_node_t               *node, *sentinel;
    ngx_http_limit_req_ctx_t        *ctx;
    ngx_http_limit_req_node_t       *lr;
    ngx_http_variable_value_t       *vv;
    ngx_http_limit_req_variable_t   *lrv;

    ctx = limit_req->shm_zone->data;

    node = ctx->sh->rbtree.root;
    sentinel = ctx->sh->rbtree.sentinel;
    rc = -1;

    lrv = ctx->limit_vars->elts;

    while (node != sentinel) {

        if (hash < node->key) {
            node = node->left;
            continue;
        }

        if (hash > node->key) {
            node = node->right;
            continue;
        }

        /* hash == node->key */

        lr = (ngx_http_limit_req_node_t *) &node->color;

        lr_data = lr->data;
        lr_last = lr_data + lr->len;

        for (i = 0; i < ctx->limit_vars->nelts; i++) {
            vv = ngx_http_get_indexed_variable(r, lrv[i].index);

            ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "limit_req vv is %i %v node is %s",
                           lrv[i].index, vv, lr_data);

            lr_vv_len = ngx_min(lr_last - lr_data, vv->len);

            if ((rc = ngx_memcmp(vv->data, lr_data, lr_vv_len)) != 0) {
                break;
            }

            if (lr_vv_len != vv->len) {
                rc = 1;
                break;
            }

            /* lr_vv_len == vv->len */
            lr_data += lr_vv_len;
        }

        if (rc == 0 && lr_last > lr_data) {
            rc = -1;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "limit_req lookup is : %i, size is %ui",
                       rc, ctx->limit_vars->nelts);

        if (rc == 0) {
            ngx_queue_remove(&lr->queue);
            ngx_queue_insert_head(&ctx->sh->queue, &lr->queue);

            tp = ngx_timeofday();

            now = (ngx_msec_t) (tp->sec * 1000 + tp->msec);
            ms = (ngx_msec_int_t) (now - lr->last);

            excess = lr->excess - ctx->rate * ngx_abs(ms) / 1000 + 1000;

            if (excess < 0) {
                excess = 0;
            }

            *ep = excess;

            if ((ngx_uint_t) excess > limit_req->burst) {
                return NGX_BUSY;
            }

            lr->excess = excess;
            lr->last = now;

            if (excess) {
                return NGX_AGAIN;
            }

            return NGX_OK;
        }

        node = (rc < 0) ? node->left : node->right;
    }

    *ep = 0;

    return NGX_DECLINED;
}


static void
ngx_http_limit_req_expire(ngx_http_request_t *r, ngx_http_limit_req_ctx_t *ctx,
    ngx_uint_t n)
{
    ngx_int_t                   excess;
    ngx_time_t                 *tp;
    ngx_msec_t                  now;
    ngx_queue_t                *q;
    ngx_msec_int_t              ms;
    ngx_rbtree_node_t          *node;
    ngx_http_limit_req_node_t  *lr;

    tp = ngx_timeofday();

    now = (ngx_msec_t) (tp->sec * 1000 + tp->msec);

    /*
     * n == 1 deletes one or two zero rate entries
     * n == 0 deletes oldest entry by force
     *        and one or two zero rate entries
     */

    while (n < 3) {

        if (ngx_queue_empty(&ctx->sh->queue)) {
            return;
        }

        q = ngx_queue_last(&ctx->sh->queue);

        lr = ngx_queue_data(q, ngx_http_limit_req_node_t, queue);

        if (n++ != 0) {

            ms = (ngx_msec_int_t) (now - lr->last);
            ms = ngx_abs(ms);

            if (ms < 60000) {
                return;
            }

            excess = lr->excess - ctx->rate * ms / 1000;

            if (excess > 0) {
                return;
            }
        }

        ngx_queue_remove(q);

        node = (ngx_rbtree_node_t *)
                   ((u_char *) lr - offsetof(ngx_rbtree_node_t, color));

        ngx_rbtree_delete(&ctx->sh->rbtree, node);

        ngx_slab_free_locked(ctx->shpool, node);
    }
}


static ngx_int_t
ngx_http_limit_req_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_http_limit_req_ctx_t  *octx = data;

    size_t                       len;
    ngx_uint_t                   i, j;
    ngx_http_limit_req_ctx_t    *ctx;
    ngx_http_limit_req_variable_t *v1, *v2;

    ctx = shm_zone->data;
    v1 = ctx->limit_vars->elts;

    if (octx) {
        v2 = octx->limit_vars->elts;
        if (ctx->limit_vars->nelts != octx->limit_vars->nelts) {
            ngx_log_error(NGX_LOG_EMERG, shm_zone->shm.log, 0,
                          "limit_req \"%V\" uses the \"%V\" variable "
                          "while previously it used the \"%V\" variable",
                          &shm_zone->shm.name, &v1[0].var, &v2[0].var);
            return NGX_ERROR;
        }

        for (i = 0, j = 0;
             i < ctx->limit_vars->nelts && j < octx->limit_vars->nelts;
             i++, j++)
        {
            if (ngx_strcmp(v1[i].var.data, v2[j].var.data) != 0) {
                ngx_log_error(NGX_LOG_EMERG, shm_zone->shm.log, 0,
                              "limit_req \"%V\" uses the \"%V\" variable "
                              "while previously it used the \"%V\" variable",
                              &shm_zone->shm.name, &v1[i].var,
                              &v2[j].var);
                return NGX_ERROR;
            }
        }

        ctx->sh = octx->sh;
        ctx->shpool = octx->shpool;

        return NGX_OK;
    }

    ctx->shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;

    if (shm_zone->shm.exists) {
        ctx->sh = ctx->shpool->data;

        return NGX_OK;
    }

    ctx->sh = ngx_slab_alloc(ctx->shpool, sizeof(ngx_http_limit_req_shctx_t));
    if (ctx->sh == NULL) {
        return NGX_ERROR;
    }

    ctx->shpool->data = ctx->sh;

    ngx_rbtree_init(&ctx->sh->rbtree, &ctx->sh->sentinel,
                    ngx_http_limit_req_rbtree_insert_value);

    ngx_queue_init(&ctx->sh->queue);

    len = sizeof(" in limit_req zone \"\"") + shm_zone->shm.name.len;

    ctx->shpool->log_ctx = ngx_slab_alloc(ctx->shpool, len);
    if (ctx->shpool->log_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_sprintf(ctx->shpool->log_ctx, " in limit_req zone \"%V\"%Z",
                &shm_zone->shm.name);

    ctx->shpool->log_nomem = 0;

    return NGX_OK;
}


static void *
ngx_http_limit_req_create_conf(ngx_conf_t *cf)
{
    ngx_http_limit_req_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_limit_req_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->shm_zone = NULL;
     *     conf->burst = 0;
     *     conf->nodelay = 0;
     */

    conf->enable = NGX_CONF_UNSET;
    conf->limit_log_level = NGX_CONF_UNSET_UINT;
    conf->status_code = NGX_CONF_UNSET_UINT;
    conf->geo_var_index = NGX_CONF_UNSET;

    return conf;
}


static char *
ngx_http_limit_req_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_limit_req_conf_t *prev = parent;
    ngx_http_limit_req_conf_t *conf = child;

    if (conf->rules == NULL) {
        conf->rules = prev->rules;
    }

    ngx_conf_merge_value(conf->enable, prev->enable, 0);

    ngx_conf_merge_uint_value(conf->limit_log_level, prev->limit_log_level,
                              NGX_LOG_ERR);

    conf->delay_log_level = (conf->limit_log_level == NGX_LOG_INFO) ?
                                NGX_LOG_INFO : conf->limit_log_level + 1;

    ngx_conf_merge_uint_value(conf->status_code, prev->status_code,
                              NGX_HTTP_SERVICE_UNAVAILABLE);

    ngx_conf_merge_value(conf->geo_var_index, prev->geo_var_index,
                         NGX_CONF_UNSET);

    ngx_conf_merge_str_value(conf->geo_var_value, prev->geo_var_value, "");

    return NGX_CONF_OK;
}


static char *
ngx_http_limit_req_zone(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char                         *p;
    size_t                          len;
    ssize_t                         size;
    ngx_str_t                      *value, name, s;
    ngx_int_t                       rate, scale;
    ngx_uint_t                      i;
    ngx_array_t                    *variables;
    ngx_shm_zone_t                 *shm_zone;
    ngx_http_limit_req_ctx_t       *ctx;
    ngx_http_limit_req_variable_t  *v;

    value = cf->args->elts;

    ctx = NULL;
    v = NULL;
    size = 0;
    rate = 1;
    scale = 1;
    name.len = 0;

    variables = ngx_array_create(cf->pool, 5,
                                 sizeof(ngx_http_limit_req_variable_t));
    if (variables == NULL) {
        return NGX_CONF_ERROR;
    }

    for (i = 1; i < cf->args->nelts; i++) {

        if (ngx_strncmp(value[i].data, "zone=", 5) == 0) {

            name.data = value[i].data + 5;

            p = (u_char *) ngx_strchr(name.data, ':');

            if (p == NULL) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid zone size \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

            name.len = p - name.data;

            s.data = p + 1;
            s.len = value[i].data + value[i].len - s.data;

            size = ngx_parse_size(&s);

            if (size == NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid zone size \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

            if (size < (ssize_t) (8 * ngx_pagesize)) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "zone \"%V\" is too small", &value[i]);
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "rate=", 5) == 0) {

            len = value[i].len;
            p = value[i].data + len - 3;

            if (ngx_strncmp(p, "r/s", 3) == 0) {
                scale = 1;
                len -= 3;

            } else if (ngx_strncmp(p, "r/m", 3) == 0) {
                scale = 60;
                len -= 3;
            }

            rate = ngx_atoi(value[i].data + 5, len - 5);
            if (rate <= 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid rate \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (value[i].data[0] == '$') {

            value[i].len--;
            value[i].data++;

            v = ngx_array_push(variables);
            if (v == NULL) {
                return NGX_CONF_ERROR;
            }

            v->index = ngx_http_get_variable_index(cf, &value[i]);
            if (v->index == NGX_ERROR) {
                return NGX_CONF_ERROR;
            }

            v->var = value[i];

            continue;
        }

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[i]);
        return NGX_CONF_ERROR;
    }

    if (name.len == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"%V\" must have \"zone\" parameter",
                           &cmd->name);
        return NGX_CONF_ERROR;
    }


    if (variables->nelts == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "no variable is defined for %V \"%V\"",
                           &cmd->name, &name);
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_limit_req_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }
    ctx->rate = rate * 1000 / scale;
    ctx->limit_vars = variables;

    shm_zone = ngx_shared_memory_add(cf, &name, size,
                                     &ngx_http_limit_req_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (shm_zone->data) {

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                   "limit_req_zone \"%V\" is already bound to variable \"%V\"",
                   &value[1], &v->var);
        return NGX_CONF_ERROR;
    }

    shm_zone->init = ngx_http_limit_req_init_zone;
    shm_zone->data = ctx;

    return NGX_CONF_OK;
}


static char *
ngx_http_limit_req(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_limit_req_conf_t  *lrcf = conf;

    ngx_int_t                      burst;
    ngx_str_t                     *value, s, forbid_action;
    ngx_uint_t                     i, nodelay;
    ngx_shm_zone_t                *shm_zone;
    ngx_http_limit_req_limit_t    *limit_req;

    value = cf->args->elts;
    if (cf->args->nelts == 2) {
        if (ngx_strncmp(value[1].data, "off", 3) == 0) {
            lrcf->enable = 0;
            return NGX_CONF_OK;
        }
    }

    lrcf->enable = 1;

    shm_zone = NULL;
    burst = 0;
    nodelay = 0;
    ngx_str_null(&forbid_action);

    for (i = 1; i < cf->args->nelts; i++) {

        if (ngx_strncmp(value[i].data, "zone=", 5) == 0) {

            s.len = value[i].len - 5;
            s.data = value[i].data + 5;

            shm_zone = ngx_shared_memory_add(cf, &s, 0,
                                             &ngx_http_limit_req_module);
            if (shm_zone == NULL) {
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "burst=", 6) == 0) {

            burst = ngx_atoi(value[i].data + 6, value[i].len - 6);
            if (burst == NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid burst rate \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "forbid_action=", 14) == 0) {

            s.len = value[i].len - 14;
            s.data = value[i].data + 14;

            if (s.len < 2 || (s.data[0] != '@' && s.data[0] != '/')) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid forbid_action \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

            forbid_action = s;

            continue;
        }

        if (ngx_strcmp(value[i].data, "nodelay") == 0) {
            nodelay = 1;
            continue;
        }

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[i]);
        return NGX_CONF_ERROR;
    }

    if (shm_zone == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"%V\" must have \"zone\" parameter",
                           &cmd->name);
        return NGX_CONF_ERROR;
    }
/*
    if (shm_zone->data == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "unknown limit_req_zone \"%V\"",
                           &shm_zone->shm.name);
        return NGX_CONF_ERROR;
    }
*/
    if (lrcf->rules == NULL) {
        lrcf->rules = ngx_array_create(cf->pool, 5,
                                       sizeof(ngx_http_limit_req_limit_t));
        if (lrcf->rules == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    limit_req = lrcf->rules->elts;

    for (i = 0; i < lrcf->rules->nelts; i++) {
        if (shm_zone == limit_req[i].shm_zone) {
            return "is duplicate";
        }
    }

    limit_req = ngx_array_push(lrcf->rules);
    if (limit_req == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_memzero(limit_req, sizeof(ngx_http_limit_req_limit_t));

    limit_req->shm_zone = shm_zone;
    limit_req->burst = burst * 1000;
    limit_req->nodelay = nodelay;
    limit_req->forbid_action = forbid_action;

    return NGX_CONF_OK;
}


static char *
ngx_http_limit_req_whitelist(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_http_limit_req_conf_t  *lrcf = conf;

    ngx_str_t              *value, s;
    ngx_uint_t              i;

    value = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data, "geo_var_name=", 13) == 0) {

            s.len = value[i].len - 13;
            s.data = value[i].data + 13;

            lrcf->geo_var_name = s;

            lrcf->geo_var_index = ngx_http_get_variable_index(cf,
                &lrcf->geo_var_name);

            if (lrcf->geo_var_index == NGX_ERROR) {
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "geo_var_value=", 14) == 0) {

            s.len = value[i].len - 14;
            s.data = value[i].data + 14;

            lrcf->geo_var_value = s;

            continue;
        }

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[i]);
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_limit_req_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_PREACCESS_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_limit_req_handler;

    return NGX_OK;
}
