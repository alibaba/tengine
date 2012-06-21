
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    u_char              color;
    u_char              len;
    u_short             conn;
    u_char              data[1];
} ngx_http_limit_conn_node_t;


typedef struct {
    ngx_shm_zone_t     *shm_zone;
    ngx_rbtree_node_t  *node;
} ngx_http_limit_conn_cleanup_t;


typedef struct {
    ngx_rbtree_t       *rbtree;
    ngx_int_t           index;
    ngx_str_t           var;
} ngx_http_limit_conn_ctx_t;


typedef struct {
    ngx_shm_zone_t     *shm_zone;
    ngx_uint_t          conn;
} ngx_http_limit_conn_limit_t;


typedef struct {
    ngx_array_t         limits;
    ngx_uint_t          log_level;
} ngx_http_limit_conn_conf_t;


static ngx_rbtree_node_t *ngx_http_limit_conn_lookup(ngx_rbtree_t *rbtree,
    ngx_http_variable_value_t *vv, uint32_t hash);
static void ngx_http_limit_conn_cleanup(void *data);
static ngx_inline void ngx_http_limit_conn_cleanup_all(ngx_pool_t *pool);

static void *ngx_http_limit_conn_create_conf(ngx_conf_t *cf);
static char *ngx_http_limit_conn_merge_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_limit_conn_zone(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_limit_zone(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_limit_conn(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_limit_conn_init(ngx_conf_t *cf);


static ngx_conf_deprecated_t  ngx_conf_deprecated_limit_zone = {
    ngx_conf_deprecated, "limit_zone", "limit_conn_zone"
};


static ngx_conf_enum_t  ngx_http_limit_conn_log_levels[] = {
    { ngx_string("info"), NGX_LOG_INFO },
    { ngx_string("notice"), NGX_LOG_NOTICE },
    { ngx_string("warn"), NGX_LOG_WARN },
    { ngx_string("error"), NGX_LOG_ERR },
    { ngx_null_string, 0 }
};


static ngx_command_t  ngx_http_limit_conn_commands[] = {

    { ngx_string("limit_conn_zone"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE2,
      ngx_http_limit_conn_zone,
      0,
      0,
      NULL },

    { ngx_string("limit_zone"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE3,
      ngx_http_limit_zone,
      0,
      0,
      NULL },

    { ngx_string("limit_conn"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_http_limit_conn,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("limit_conn_log_level"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_enum_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_limit_conn_conf_t, log_level),
      &ngx_http_limit_conn_log_levels },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_limit_conn_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_http_limit_conn_init,              /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_limit_conn_create_conf,       /* create location configuration */
    ngx_http_limit_conn_merge_conf         /* merge location configuration */
};


ngx_module_t  ngx_http_limit_conn_module = {
    NGX_MODULE_V1,
    &ngx_http_limit_conn_module_ctx,       /* module context */
    ngx_http_limit_conn_commands,          /* module directives */
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


static ngx_int_t
ngx_http_limit_conn_handler(ngx_http_request_t *r)
{
    size_t                          len, n;
    uint32_t                        hash;
    ngx_uint_t                      i;
    ngx_slab_pool_t                *shpool;
    ngx_rbtree_node_t              *node;
    ngx_pool_cleanup_t             *cln;
    ngx_http_variable_value_t      *vv;
    ngx_http_limit_conn_ctx_t      *ctx;
    ngx_http_limit_conn_node_t     *lc;
    ngx_http_limit_conn_conf_t     *lccf;
    ngx_http_limit_conn_limit_t    *limits;
    ngx_http_limit_conn_cleanup_t  *lccln;

    if (r->main->limit_conn_set) {
        return NGX_DECLINED;
    }

    lccf = ngx_http_get_module_loc_conf(r, ngx_http_limit_conn_module);
    limits = lccf->limits.elts;

    for (i = 0; i < lccf->limits.nelts; i++) {
        ctx = limits[i].shm_zone->data;

        vv = ngx_http_get_indexed_variable(r, ctx->index);

        if (vv == NULL || vv->not_found) {
            continue;
        }

        len = vv->len;

        if (len == 0) {
            continue;
        }

        if (len > 255) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "the value of the \"%V\" variable "
                          "is more than 255 bytes: \"%v\"",
                          &ctx->var, vv);
            continue;
        }

        r->main->limit_conn_set = 1;

        hash = ngx_crc32_short(vv->data, len);

        shpool = (ngx_slab_pool_t *) limits[i].shm_zone->shm.addr;

        ngx_shmtx_lock(&shpool->mutex);

        node = ngx_http_limit_conn_lookup(ctx->rbtree, vv, hash);

        if (node == NULL) {

            n = offsetof(ngx_rbtree_node_t, color)
                + offsetof(ngx_http_limit_conn_node_t, data)
                + len;

            node = ngx_slab_alloc_locked(shpool, n);

            if (node == NULL) {
                ngx_shmtx_unlock(&shpool->mutex);
                ngx_http_limit_conn_cleanup_all(r->pool);
                return NGX_HTTP_SERVICE_UNAVAILABLE;
            }

            lc = (ngx_http_limit_conn_node_t *) &node->color;

            node->key = hash;
            lc->len = (u_char) len;
            lc->conn = 1;
            ngx_memcpy(lc->data, vv->data, len);

            ngx_rbtree_insert(ctx->rbtree, node);

        } else {

            lc = (ngx_http_limit_conn_node_t *) &node->color;

            if ((ngx_uint_t) lc->conn >= limits[i].conn) {

                ngx_shmtx_unlock(&shpool->mutex);

                ngx_log_error(lccf->log_level, r->connection->log, 0,
                              "limiting connections by zone \"%V\"",
                              &limits[i].shm_zone->shm.name);

                ngx_http_limit_conn_cleanup_all(r->pool);
                return NGX_HTTP_SERVICE_UNAVAILABLE;
            }

            lc->conn++;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "limit zone: %08XD %d", node->key, lc->conn);

        ngx_shmtx_unlock(&shpool->mutex);

        cln = ngx_pool_cleanup_add(r->pool,
                                   sizeof(ngx_http_limit_conn_cleanup_t));
        if (cln == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        cln->handler = ngx_http_limit_conn_cleanup;
        lccln = cln->data;

        lccln->shm_zone = limits[i].shm_zone;
        lccln->node = node;
    }

    return NGX_DECLINED;
}


static void
ngx_http_limit_conn_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel)
{
    ngx_rbtree_node_t           **p;
    ngx_http_limit_conn_node_t   *lcn, *lcnt;

    for ( ;; ) {

        if (node->key < temp->key) {

            p = &temp->left;

        } else if (node->key > temp->key) {

            p = &temp->right;

        } else { /* node->key == temp->key */

            lcn = (ngx_http_limit_conn_node_t *) &node->color;
            lcnt = (ngx_http_limit_conn_node_t *) &temp->color;

            p = (ngx_memn2cmp(lcn->data, lcnt->data, lcn->len, lcnt->len) < 0)
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


static ngx_rbtree_node_t *
ngx_http_limit_conn_lookup(ngx_rbtree_t *rbtree, ngx_http_variable_value_t *vv,
    uint32_t hash)
{
    ngx_int_t                    rc;
    ngx_rbtree_node_t           *node, *sentinel;
    ngx_http_limit_conn_node_t  *lcn;

    node = rbtree->root;
    sentinel = rbtree->sentinel;

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

        lcn = (ngx_http_limit_conn_node_t *) &node->color;

        rc = ngx_memn2cmp(vv->data, lcn->data,
                          (size_t) vv->len, (size_t) lcn->len);
        if (rc == 0) {
            return node;
        }

        node = (rc < 0) ? node->left : node->right;
    }

    return NULL;
}


static void
ngx_http_limit_conn_cleanup(void *data)
{
    ngx_http_limit_conn_cleanup_t  *lccln = data;

    ngx_slab_pool_t             *shpool;
    ngx_rbtree_node_t           *node;
    ngx_http_limit_conn_ctx_t   *ctx;
    ngx_http_limit_conn_node_t  *lc;

    ctx = lccln->shm_zone->data;
    shpool = (ngx_slab_pool_t *) lccln->shm_zone->shm.addr;
    node = lccln->node;
    lc = (ngx_http_limit_conn_node_t *) &node->color;

    ngx_shmtx_lock(&shpool->mutex);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, lccln->shm_zone->shm.log, 0,
                   "limit zone cleanup: %08XD %d", node->key, lc->conn);

    lc->conn--;

    if (lc->conn == 0) {
        ngx_rbtree_delete(ctx->rbtree, node);
        ngx_slab_free_locked(shpool, node);
    }

    ngx_shmtx_unlock(&shpool->mutex);
}


static ngx_inline void
ngx_http_limit_conn_cleanup_all(ngx_pool_t *pool)
{
    ngx_pool_cleanup_t  *cln;

    cln = pool->cleanup;

    while (cln && cln->handler == ngx_http_limit_conn_cleanup) {
        ngx_http_limit_conn_cleanup(cln->data);
        cln = cln->next;
    }

    pool->cleanup = cln;
}


static ngx_int_t
ngx_http_limit_conn_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_http_limit_conn_ctx_t  *octx = data;

    size_t                      len;
    ngx_slab_pool_t            *shpool;
    ngx_rbtree_node_t          *sentinel;
    ngx_http_limit_conn_ctx_t  *ctx;

    ctx = shm_zone->data;

    if (octx) {
        if (ngx_strcmp(ctx->var.data, octx->var.data) != 0) {
            ngx_log_error(NGX_LOG_EMERG, shm_zone->shm.log, 0,
                          "limit_conn_zone \"%V\" uses the \"%V\" variable "
                          "while previously it used the \"%V\" variable",
                          &shm_zone->shm.name, &ctx->var, &octx->var);
            return NGX_ERROR;
        }

        ctx->rbtree = octx->rbtree;

        return NGX_OK;
    }

    shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;

    if (shm_zone->shm.exists) {
        ctx->rbtree = shpool->data;

        return NGX_OK;
    }

    ctx->rbtree = ngx_slab_alloc(shpool, sizeof(ngx_rbtree_t));
    if (ctx->rbtree == NULL) {
        return NGX_ERROR;
    }

    shpool->data = ctx->rbtree;

    sentinel = ngx_slab_alloc(shpool, sizeof(ngx_rbtree_node_t));
    if (sentinel == NULL) {
        return NGX_ERROR;
    }

    ngx_rbtree_init(ctx->rbtree, sentinel,
                    ngx_http_limit_conn_rbtree_insert_value);

    len = sizeof(" in limit_conn_zone \"\"") + shm_zone->shm.name.len;

    shpool->log_ctx = ngx_slab_alloc(shpool, len);
    if (shpool->log_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_sprintf(shpool->log_ctx, " in limit_conn_zone \"%V\"%Z",
                &shm_zone->shm.name);

    return NGX_OK;
}


static void *
ngx_http_limit_conn_create_conf(ngx_conf_t *cf)
{
    ngx_http_limit_conn_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_limit_conn_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->limits.elts = NULL;
     */

    conf->log_level = NGX_CONF_UNSET_UINT;

    return conf;
}


static char *
ngx_http_limit_conn_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_limit_conn_conf_t *prev = parent;
    ngx_http_limit_conn_conf_t *conf = child;

    if (conf->limits.elts == NULL) {
        conf->limits = prev->limits;
    }

    ngx_conf_merge_uint_value(conf->log_level, prev->log_level, NGX_LOG_ERR);

    return NGX_CONF_OK;
}


static char *
ngx_http_limit_conn_zone(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char                     *p;
    ssize_t                     size;
    ngx_str_t                  *value, name, s;
    ngx_uint_t                  i;
    ngx_shm_zone_t             *shm_zone;
    ngx_http_limit_conn_ctx_t  *ctx;

    value = cf->args->elts;

    ctx = NULL;
    size = 0;
    name.len = 0;

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

        if (value[i].data[0] == '$') {

            value[i].len--;
            value[i].data++;

            ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_limit_conn_ctx_t));
            if (ctx == NULL) {
                return NGX_CONF_ERROR;
            }

            ctx->index = ngx_http_get_variable_index(cf, &value[i]);
            if (ctx->index == NGX_ERROR) {
                return NGX_CONF_ERROR;
            }

            ctx->var = value[i];

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

    if (ctx == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "no variable is defined for %V \"%V\"",
                           &cmd->name, &name);
        return NGX_CONF_ERROR;
    }

    shm_zone = ngx_shared_memory_add(cf, &name, size,
                                     &ngx_http_limit_conn_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (shm_zone->data) {
        ctx = shm_zone->data;

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "%V \"%V\" is already bound to variable \"%V\"",
                           &cmd->name, &name, &ctx->var);
        return NGX_CONF_ERROR;
    }

    shm_zone->init = ngx_http_limit_conn_init_zone;
    shm_zone->data = ctx;

    return NGX_CONF_OK;
}


static char *
ngx_http_limit_zone(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ssize_t                     n;
    ngx_str_t                  *value;
    ngx_shm_zone_t             *shm_zone;
    ngx_http_limit_conn_ctx_t  *ctx;

    ngx_conf_deprecated(cf, &ngx_conf_deprecated_limit_zone, NULL);

    value = cf->args->elts;

    if (value[2].data[0] != '$') {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid variable name \"%V\"", &value[2]);
        return NGX_CONF_ERROR;
    }

    value[2].len--;
    value[2].data++;

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_limit_conn_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->index = ngx_http_get_variable_index(cf, &value[2]);
    if (ctx->index == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    ctx->var = value[2];

    n = ngx_parse_size(&value[3]);

    if (n == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid size of limit_zone \"%V\"", &value[3]);
        return NGX_CONF_ERROR;
    }

    if (n < (ngx_int_t) (8 * ngx_pagesize)) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "limit_zone \"%V\" is too small", &value[1]);
        return NGX_CONF_ERROR;
    }


    shm_zone = ngx_shared_memory_add(cf, &value[1], n,
                                     &ngx_http_limit_conn_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (shm_zone->data) {
        ctx = shm_zone->data;

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                        "limit_zone \"%V\" is already bound to variable \"%V\"",
                        &value[1], &ctx->var);
        return NGX_CONF_ERROR;
    }

    shm_zone->init = ngx_http_limit_conn_init_zone;
    shm_zone->data = ctx;

    return NGX_CONF_OK;
}


static char *
ngx_http_limit_conn(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_shm_zone_t               *shm_zone;
    ngx_http_limit_conn_conf_t   *lccf = conf;
    ngx_http_limit_conn_limit_t  *limit, *limits;

    ngx_str_t  *value;
    ngx_int_t   n;
    ngx_uint_t  i;

    value = cf->args->elts;

    shm_zone = ngx_shared_memory_add(cf, &value[1], 0,
                                     &ngx_http_limit_conn_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    limits = lccf->limits.elts;

    if (limits == NULL) {
        if (ngx_array_init(&lccf->limits, cf->pool, 1,
                           sizeof(ngx_http_limit_conn_limit_t))
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }
    }

    for (i = 0; i < lccf->limits.nelts; i++) {
        if (shm_zone == limits[i].shm_zone) {
            return "is duplicate";
        }
    }

    n = ngx_atoi(value[2].data, value[2].len);
    if (n <= 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid number of connections \"%V\"", &value[2]);
        return NGX_CONF_ERROR;
    }

    if (n > 65535) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "connection limit must be less 65536");
        return NGX_CONF_ERROR;
    }

    limit = ngx_array_push(&lccf->limits);
    limit->conn = n;
    limit->shm_zone = shm_zone;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_limit_conn_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_PREACCESS_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_limit_conn_handler;

    return NGX_OK;
}
