
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#define NGX_HTTP_UA_MATCH_LE            '-'
#define NGX_HTTP_UA_MATCH_GE            '+'
#define NGX_HTTP_UA_MATCH_INTERVAL      '~'
#define NGX_HTTP_UA_MATCH_EXACT         '='

#define NGX_HTTP_UA_MAX_OFFSET          8

#define NGX_HTTP_UA_MAX_VERSION_VALUE   99999999999999999ULL
#define NGX_HTTP_UA_MIN_VERSION_VALUE   0ULL
#define NGX_HTTP_UA_MAX_INT64           1000000000000ULL


typedef struct {
    uint64_t                            left;
    uint64_t                            right;

    ngx_http_variable_value_t          *var;
} ngx_http_user_agent_interval_t;


typedef struct {
    ngx_trie_t                         *trie;
    ngx_http_variable_value_t          *default_value;
    ngx_pool_t                         *pool;
} ngx_http_user_agent_ctx_t;


static char *ngx_http_user_agent_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_user_agent(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_user_agent_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_http_user_agent_interval_t *ngx_http_user_agent_get_version(
    ngx_conf_t *cf, ngx_str_t *value);


static ngx_command_t ngx_http_user_agent_commands[] = {

    { ngx_string("user_agent"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_TAKE1,
      ngx_http_user_agent_block,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t ngx_http_user_agent_module_ctx = {
    NULL,                               /* preconfiguration */
    NULL,                               /* postconfiguration */

    NULL,                               /* create main configuration */
    NULL,                               /* init main configuration */

    NULL,                               /* create server configuration */
    NULL,                               /* merge server configuration */

    NULL,                               /* create location configuration */
    NULL                                /* merge lcoation configuration */
};


ngx_module_t ngx_http_user_agent_module = {
    NGX_MODULE_V1,
    &ngx_http_user_agent_module_ctx,    /* module context */
    ngx_http_user_agent_commands,       /* module directives */
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


static char *
ngx_http_user_agent_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                      *rv;
    ngx_str_t                 *value, name;
    ngx_conf_t                 save;
    ngx_http_variable_t       *var;
    ngx_http_user_agent_ctx_t *ctx;

    value = cf->args->elts;

    name = value[1];
    name.data++;
    name.len--;

    var = ngx_http_add_variable(cf, &name, NGX_HTTP_VAR_CHANGEABLE);
    if (var == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx = ngx_palloc(cf->pool, sizeof(ngx_http_user_agent_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->pool = cf->pool;
    ctx->trie = ngx_trie_create(ctx->pool);
    if (ctx->trie == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->default_value = NULL;

    var->get_handler = ngx_http_user_agent_variable;
    var->data = (uintptr_t) ctx;

    save = *cf;
    cf->ctx = ctx;
    cf->handler = ngx_http_user_agent;
    cf->handler_conf = conf;

    rv = ngx_conf_parse(cf, NULL);
    if (NGX_OK != ctx->trie->build_clue(ctx->trie)) {
        return NGX_CONF_ERROR;
    }

    *cf = save;
    if (ctx->default_value == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "no default value");
        rv = NGX_CONF_ERROR;
    }

    return rv;
}


static ngx_http_user_agent_interval_t *
ngx_http_user_agent_get_version(ngx_conf_t *cf, ngx_str_t *value)
{
    char                            op;
    uint64_t                        ver, scale, version;
    ngx_uint_t                      i, n;
    ngx_http_user_agent_interval_t *interval;

    op = NGX_HTTP_UA_MATCH_EXACT;
    scale = NGX_HTTP_UA_MAX_INT64;
    version = 0;
    ver = 0;
    n = 0;

    interval = ngx_palloc(cf->pool, sizeof(ngx_http_user_agent_interval_t));
    if(interval == NULL) {
        return NULL;
    }

    interval->var = ngx_pcalloc(cf->pool, sizeof(ngx_http_variable_value_t));
    if (interval->var == NULL) {
        return NULL;
    }

    interval->left = NGX_HTTP_UA_MIN_VERSION_VALUE;
    interval->right = NGX_HTTP_UA_MAX_VERSION_VALUE;

    for (i = 0; i < value->len; i++) {
        if (value->data[i] >= '0' && value->data[i] <= '9') {
            ver = ver * 10 + value->data[i] - '0';
            continue;
        }

        if (value->data[i] == '.') {
            version += ver * scale;
            ver = 0;
            scale /= 10000;

        } else if (value->data[i] == NGX_HTTP_UA_MATCH_LE) {
            if (i != value->len - 1) {
                goto error;
            }

            op = NGX_HTTP_UA_MATCH_LE;
        } else if (value->data[i] == NGX_HTTP_UA_MATCH_EXACT) {
            if (i != value->len - 1) {
                goto error;
            }
        } else if (value->data[i] == NGX_HTTP_UA_MATCH_GE) {
            if (i != value->len - 1) {
                goto error;
            }

            op = NGX_HTTP_UA_MATCH_GE;
        } else if (value->data[i] == NGX_HTTP_UA_MATCH_INTERVAL) {
            op = NGX_HTTP_UA_MATCH_INTERVAL;
            if (n >= 2) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "too many versions");
                return NULL;
            }

            version += ver * scale;
            interval->left = version;
            n++;

            ver = 0;
            scale = NGX_HTTP_UA_MAX_INT64;
            version = 0;

            if (i + 1 >= value->len) {
                goto error;
            }

            if (!(value->data[i + 1] >= '0'&&value->data[i + 1] <= '9')) {
                goto error;
            }
        } else {
            goto error;
        }
    }

    version += ver * scale;
    if (op == NGX_HTTP_UA_MATCH_LE || op == NGX_HTTP_UA_MATCH_INTERVAL) {
        interval->right = version;

    } else if (op == NGX_HTTP_UA_MATCH_GE) {
        interval->left = version;

    } else if (op == NGX_HTTP_UA_MATCH_EXACT) {
        interval->left = version;
        interval->right = version;
    }

    return interval;

error:
    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid version");
    return NULL;
}


static char *
ngx_http_user_agent(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                      *args, *name, file;
    ngx_uint_t                      i, nelts, mode;
    ngx_trie_t                     *trie;
    ngx_array_t                    *value;
    ngx_trie_node_t                *node;
    ngx_http_user_agent_ctx_t      *ctx;
    ngx_http_user_agent_interval_t *interval, *p;

    ctx = cf->ctx;
    trie = ctx->trie;

    args = cf->args->elts;
    nelts = cf->args->nelts;

    name = NULL;

    if (nelts <= 1) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                 "invalid first parameter");
        return NGX_CONF_ERROR;

    }

    if (nelts == 2) {
        if (ngx_strcmp(args[0].data, "include") == 0) {

            file = args[1];
            if (ngx_conf_full_name(cf->cycle, &file, 1) != NGX_OK) {
                return NGX_CONF_ERROR;
            }

            ngx_log_debug1(NGX_LOG_DEBUG_CORE, cf->log, 0, "include %s",
                           file.data);
            return ngx_conf_parse(cf, &file);
        }

        if (ngx_strcmp(args[0].data, "default") == 0) {

            if (ctx->default_value != NULL) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "is duplicate");
                return NGX_CONF_ERROR;
            }

            ctx->default_value = ngx_pcalloc(ctx->pool,
                                             sizeof(ngx_http_variable_t));
            if (ctx->default_value == NULL) {
                return NGX_CONF_ERROR;
            }

            ctx->default_value->len = args[1].len;
            ctx->default_value->data = args[1].data;

            ctx->default_value->not_found = 0;
            ctx->default_value->no_cacheable =0;
            ctx->default_value->valid =1;

            return NGX_CONF_OK;
        }

        if (ngx_strcmp(args[0].data, "greedy") == 0) {
            mode = NGX_TRIE_REVERSE | NGX_TRIE_CONTINUE;
            trie->insert(trie, args + 1, mode);

            return NGX_CONF_OK;
        }
    }

    if (nelts == 2) {

        name = args;

        interval = ngx_pcalloc(ctx->pool,
                               sizeof(ngx_http_user_agent_interval_t));
        if (interval == NULL) {
            return NGX_CONF_ERROR;
        }

        interval->var = ngx_pcalloc(ctx->pool,
                                    sizeof(ngx_http_variable_value_t));
        if (interval->var == NULL) {
            return NGX_CONF_ERROR;
        }

        interval->left = NGX_HTTP_UA_MIN_VERSION_VALUE;
        interval->right = NGX_HTTP_UA_MAX_VERSION_VALUE;

        interval->var->len = args[1].len;
        interval->var->data = args[1].data;

        interval->var->not_found = 0;
        interval->var->no_cacheable = 0;
        interval->var->valid = 1;

        goto insert;
    }

    if (nelts == 3) {

        name = args;
        interval = ngx_http_user_agent_get_version(cf, args + 1);
        if (interval == NULL) {
            return NGX_CONF_ERROR;
        }

        interval->var->len = args[2].len;
        interval->var->data = args[2].data;

        interval->var->not_found = 0;
        interval->var->no_cacheable =0;
        interval->var->valid = 1;

        goto insert;
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "too many args");
    return NGX_CONF_ERROR;

insert:

    mode = NGX_TRIE_REVERSE;
    node = trie->insert(trie, name, mode);
    if (node == NULL) {
        return NGX_CONF_ERROR;
    }

    value = (ngx_array_t *) node->value;
    if (value == NULL) {
        value = ngx_array_create(ctx->pool, 2,
                                 sizeof(ngx_http_user_agent_interval_t));
        if (value == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    p = (ngx_http_user_agent_interval_t *) value->elts;
    for (i = 0; i < value->nelts; i++) {
        if ((p[i].left >= interval->left && p[i].left <= interval->right)
            || (p[i].right >= interval->left && p[i].right <= interval->right)
            || (interval->left >= p[i].left && interval->left <= p[i].right)
            || (interval->right >= p[i].left && interval->right <= p[i].right))
        {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "interval covered");
            return NGX_CONF_ERROR;
        }
    }

    p = (ngx_http_user_agent_interval_t *) ngx_array_push(value);
    if (p == NULL) {
        return NGX_CONF_ERROR;
    }

    *p = *interval;
    node->value = (void *) value;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_user_agent_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    uint64_t                        ver, scale, version;
    ngx_int_t                       i, n, pos, offset;
    ngx_str_t                      *user_agent;
    ngx_trie_t                     *trie;
    ngx_array_t                    *value;
    ngx_http_user_agent_ctx_t      *uacf;
    ngx_http_user_agent_interval_t *array;

    uacf = (ngx_http_user_agent_ctx_t *) data;
    trie = uacf->trie;

    if (r->headers_in.user_agent == NULL) {
      goto end;
    }

    user_agent = &(r->headers_in.user_agent->value);

    value = trie->query(trie, user_agent, &pos, NGX_TRIE_REVERSE);
    if (value == NULL || pos < 0) {
        goto end;
    }

    version = 0;
    scale = NGX_HTTP_UA_MAX_INT64;
    ver = 0;
    offset = 0;

    for (/* void */; pos < (ngx_int_t) user_agent->len; pos++, offset++) {
        if (user_agent->data[pos] >= '0'
            && user_agent->data[pos] <= '9') {
            break;

        } else if (user_agent->data[pos] == ';'
                   || user_agent->data[pos] == '('
                   || user_agent->data[pos] == ')')
        {
            break;
        }

        if(offset >= NGX_HTTP_UA_MAX_OFFSET) {
            break;
        }
    }

    array = value->elts;
    n = value->nelts;

    for (/* void */ ; pos < (ngx_int_t) user_agent->len; pos++) {

        if (user_agent->data[pos] == '.') {
            version += ver * scale;
            ver = 0;
            scale /= 10000;
            continue;

        } else if(user_agent->data[pos] >= '0'
                  && user_agent->data[pos] <= '9') {

            ver = ver * 10 +user_agent->data[pos] - '0';
            continue;
        }

        break;
    }

    version += ver * scale;
    for (i = 0; i < n; i++) {
        if (version >= array[i].left && version <= array[i].right) {
            *v = *(array[i].var);
            return NGX_OK;
        }
    }

end:

    *v = *uacf->default_value;
    return NGX_OK;
}
