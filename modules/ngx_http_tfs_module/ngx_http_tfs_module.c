
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include <ngx_http_tfs.h>
#include <ngx_http_tfs_timers.h>
#include <ngx_http_tfs_local_block_cache.h>


#define NGX_HTTP_TFS_BLOCK_CACHE_ZONE_NAME "tfs_module_block_cache_zone"

#define NGX_HTTP_TFS_UPSTREAM_CREATE           1
#define NGX_HTTP_TFS_UPSTREAM_FIND             2

#define NGX_HTTP_TFS_RCSERVER_TYPE             "rcs"
#define NGX_HTTP_TFS_NAMESERVER_TYPE           "ns"


static void *ngx_http_tfs_create_main_conf(ngx_conf_t *cf);
static char *ngx_http_tfs_init_main_conf(ngx_conf_t *cf, void *conf);

static void *ngx_http_tfs_create_srv_conf(ngx_conf_t *cf);
static char *ngx_http_tfs_merge_srv_conf(ngx_conf_t *cf,
    void *parent, void *child);

static void *ngx_http_tfs_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_tfs_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);

static ngx_int_t ngx_http_tfs_module_init(ngx_cycle_t *cycle);

static char *ngx_http_tfs_upstream(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_tfs_pass(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static char *ngx_http_tfs_log(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static char *ngx_http_tfs_rcs_interface(ngx_conf_t *cf,
    ngx_http_tfs_upstream_t *tu);

static char *ngx_http_tfs_lowat_check(ngx_conf_t *cf, void *post, void *data);
static void ngx_http_tfs_read_body_handler(ngx_http_request_t *r);
static char *ngx_http_tfs_keepalive(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static char *ngx_http_tfs_rcs_heartbeat(ngx_conf_t *cf,
    ngx_http_tfs_upstream_t *tu);

static char *ngx_http_tfs_rcs_zone(ngx_conf_t *cf, ngx_http_tfs_upstream_t *tu);
static char *ngx_http_tfs_block_cache_zone(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static char *ngx_http_tfs_upstream_parse(ngx_conf_t *cf, ngx_command_t *dummy,
    void *conf);

/* rc server keepalive */
static ngx_int_t ngx_http_tfs_check_init_worker(ngx_cycle_t *cycle);
#ifdef NGX_HTTP_TFS_USE_TAIR
/* destroy tair servers */
static void ngx_http_tfs_check_exit_worker(ngx_cycle_t *cycle);
#endif


static ngx_conf_post_t  ngx_http_tfs_lowat_post =
    { ngx_http_tfs_lowat_check };


static ngx_command_t  ngx_http_tfs_commands[] = {

    { ngx_string("tfs_upstream"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_TAKE1,
      ngx_http_tfs_upstream,
      0,
      0,
      NULL },

    { ngx_string("tfs_pass"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE12,
      ngx_http_tfs_pass,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("tfs_keepalive"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE2,
      ngx_http_tfs_keepalive,
      0,
      0,
      NULL },

    { ngx_string("tfs_log"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE12,
      ngx_http_tfs_log,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("tfs_connect_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      0,
      offsetof(ngx_http_tfs_main_conf_t, tfs_connect_timeout),
      NULL },

    { ngx_string("tfs_send_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      0,
      offsetof(ngx_http_tfs_main_conf_t, tfs_send_timeout),
      NULL },

    { ngx_string("tfs_read_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      0,
      offsetof(ngx_http_tfs_main_conf_t, tfs_read_timeout),
      NULL },

    { ngx_string("tair_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      0,
      offsetof(ngx_http_tfs_main_conf_t, tair_timeout),
      NULL },

    { ngx_string("tfs_send_lowat"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      0,
      offsetof(ngx_http_tfs_main_conf_t, send_lowat),
      &ngx_http_tfs_lowat_post },

    { ngx_string("tfs_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      0,
      offsetof(ngx_http_tfs_main_conf_t, buffer_size),
      NULL },

    { ngx_string("tfs_body_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      0,
      offsetof(ngx_http_tfs_main_conf_t, body_buffer_size),
      NULL },

    { ngx_string("tfs_block_cache_zone"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_1MORE,
      ngx_http_tfs_block_cache_zone,
      0,
      0,
      NULL },

    { ngx_string("tfs_enable_remote_block_cache"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      0,
      offsetof(ngx_http_tfs_main_conf_t, enable_remote_block_cache),
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_tfs_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    ngx_http_tfs_create_main_conf,         /* create main configuration */
    ngx_http_tfs_init_main_conf,           /* init main configuration */

    ngx_http_tfs_create_srv_conf,          /* create server configuration */
    ngx_http_tfs_merge_srv_conf,           /* merge server configuration */

    ngx_http_tfs_create_loc_conf,          /* create location configuration */
    ngx_http_tfs_merge_loc_conf            /* merge location configuration */
};


ngx_module_t  ngx_http_tfs_module = {
    NGX_MODULE_V1,
    &ngx_http_tfs_module_ctx,              /* module context */
    ngx_http_tfs_commands,                 /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    ngx_http_tfs_module_init,              /* init module */
    ngx_http_tfs_check_init_worker,        /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
#ifdef NGX_HTTP_TFS_USE_TAIR
    ngx_http_tfs_check_exit_worker,        /* exit process */
#else
    NULL,
#endif
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_tfs_handler(ngx_http_request_t *r)
{
    ngx_int_t                  rc;
    ngx_http_tfs_t            *t;
    ngx_http_tfs_loc_conf_t   *tlcf;
    ngx_http_tfs_srv_conf_t   *tscf;
    ngx_http_tfs_main_conf_t  *tmcf;

    tlcf = ngx_http_get_module_loc_conf(r, ngx_http_tfs_module);
    tscf = ngx_http_get_module_srv_conf(r, ngx_http_tfs_module);
    tmcf = ngx_http_get_module_main_conf(r, ngx_http_tfs_module);

    t = ngx_pcalloc(r->pool, sizeof(ngx_http_tfs_t));

    if (t == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "alloc ngx_http_tfs_t failed");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    t->pool = r->pool;
    t->data = r;
    t->log = r->connection->log;
    t->loc_conf = tlcf;
    t->srv_conf = tscf;
    t->main_conf = tmcf;
    t->output.tag = (ngx_buf_tag_t) &ngx_http_tfs_module;
    if (tmcf->local_block_cache_ctx != NULL) {
        t->block_cache_ctx.use_cache |= NGX_HTTP_TFS_LOCAL_BLOCK_CACHE;
        t->block_cache_ctx.local_ctx = tmcf->local_block_cache_ctx;
    }
    if (tmcf->enable_remote_block_cache == NGX_HTTP_TFS_YES) {
        t->block_cache_ctx.use_cache |= NGX_HTTP_TFS_REMOTE_BLOCK_CACHE;
    }
    t->block_cache_ctx.remote_ctx.data = t;
    t->block_cache_ctx.remote_ctx.tair_instance =
                                             &tmcf->remote_block_cache_instance;
    t->block_cache_ctx.curr_lookup_cache = NGX_HTTP_TFS_LOCAL_BLOCK_CACHE;

    rc = ngx_http_restful_parse(r, &t->r_ctx);
    if (rc != NGX_OK) {
        return rc;
    }

    t->header_only = r->header_only;

    if (!t->loc_conf->upstream->enable_rcs && t->r_ctx.version == 2) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "custom file requires tfs_enable_rcs on,"
                      " and make sure you have MetaServer and RootServer!");
        return NGX_HTTP_BAD_REQUEST;
    }

    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_CREATE_DIR:
    case NGX_HTTP_TFS_ACTION_CREATE_FILE:
    case NGX_HTTP_TFS_ACTION_REMOVE_DIR:
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
    case NGX_HTTP_TFS_ACTION_MOVE_DIR:
    case NGX_HTTP_TFS_ACTION_MOVE_FILE:
    case NGX_HTTP_TFS_ACTION_LS_DIR:
    case NGX_HTTP_TFS_ACTION_LS_FILE:
    case NGX_HTTP_TFS_ACTION_STAT_FILE:
    case NGX_HTTP_TFS_ACTION_KEEPALIVE:
    case NGX_HTTP_TFS_ACTION_READ_FILE:
    case NGX_HTTP_TFS_ACTION_GET_APPID:
        rc = ngx_http_discard_request_body(r);

        if (rc != NGX_OK) {
            return rc;
        }

        r->headers_out.content_length_n = -1;
        ngx_http_set_ctx(r, t, ngx_http_tfs_module);
        r->main->count++;
        ngx_http_tfs_read_body_handler(r);
        break;
    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        r->headers_out.content_length_n = -1;
        ngx_http_set_ctx(r, t, ngx_http_tfs_module);
        rc = ngx_http_read_client_request_body(r,
                                               ngx_http_tfs_read_body_handler);
        if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return rc;
        }
        break;
    }

    return NGX_DONE;
}


ngx_http_tfs_upstream_t *
ngx_http_tfs_upstream_add(ngx_conf_t *cf, ngx_url_t *u, ngx_uint_t flags)
{
    ngx_uint_t                 i;
    ngx_http_tfs_upstream_t   *tu, **tup;
    ngx_http_tfs_main_conf_t  *tmcf;

    if (!(flags & NGX_HTTP_TFS_UPSTREAM_CREATE)) {

        if (ngx_parse_url(cf->pool, u) != NGX_OK) {
            if (u->err) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "%s in tfs upstream \"%V\"",
                                   u->err, &u->url);
            }

            return NULL;
        }
    }

    tmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_tfs_module);

    tup = tmcf->upstreams.elts;

    for (i = 0; i < tmcf->upstreams.nelts; i++)  {

        if (tup[i]->host.len != u->host.len
            || ngx_strncasecmp(tup[i]->host.data, u->host.data, u->host.len)
               != 0)
        {
            continue;
        }

        if (flags & NGX_HTTP_TFS_UPSTREAM_CREATE)
        {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "duplicate tfs upstream \"%V\"", &u->host);
            return NULL;
        }

        return tup[i];
    }

    if (flags & NGX_HTTP_TFS_UPSTREAM_FIND) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           " host not found in tfs upstream \"%V\"", &u->url);
        return NULL;
    }

    /* NGX_HTTP_TFS_UPSTREAM_CREATE */

    tu = ngx_pcalloc(cf->pool, sizeof(ngx_http_tfs_upstream_t));
    if (tu == NULL) {
        return NULL;
    }

    tu->host = u->host;

    tup = ngx_array_push(&tmcf->upstreams);
    if (tup == NULL) {
        return NULL;
    }

    *tup = tu;

    return tu;
}


static char *
ngx_http_tfs_upstream(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                     *rv;
    ngx_url_t                 u;
    ngx_str_t                *value;
    ngx_conf_t                pcf;
    ngx_http_tfs_upstream_t  *tu;

    ngx_memzero(&u, sizeof(ngx_url_t));

    value = cf->args->elts;
    u.host = value[1];
    u.no_resolve = 1;

    tu = ngx_http_tfs_upstream_add(cf, &u, NGX_HTTP_TFS_UPSTREAM_CREATE);
    if (tu == NULL) {
        return NGX_CONF_ERROR;
    }

    /* parse inside tfs_upstream{} */

    pcf = *cf;
    cf->ctx = tu;
    cf->handler = ngx_http_tfs_upstream_parse;
    cf->handler_conf = conf;

    rv = ngx_conf_parse(cf, NULL);

    *cf = pcf;

    if (rv != NGX_CONF_OK) {
        return rv;
    }

    if (tu->ups_addr == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "no servers are inside tfs upstream");
        return NGX_CONF_ERROR;
    }

    if (tu->enable_rcs) {
        if (tu->local_addr_text[0] == '\0') {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "type rcs_server must set rcs_interface "
                               "directives in tfs_upstream block");
            return NGX_CONF_ERROR;
        }

        if (tu->lock_file.len == 0) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "type rcs must set rcs_heartbeat directives"
                               " in tfs_upstream block");
            return NGX_CONF_ERROR;
        }

        if (tu->rc_ctx == NULL) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "type rcs must set "
                               "rcs_zone directives in tfs_upstream block");
            return NGX_CONF_ERROR;
        }
    }

    return rv;
}


static char *
ngx_http_tfs_upstream_parse(ngx_conf_t *cf, ngx_command_t *dummy, void *conf)
{
    ngx_url_t                 u;
    ngx_str_t                *value, *server_addr;
    ngx_http_tfs_upstream_t  *tu;

    tu = cf->ctx;

    value = cf->args->elts;

    if (ngx_strcmp(value[0].data, "server") == 0) {

        value = cf->args->elts;
        server_addr = &value[1];

        ngx_memzero(&u, sizeof(ngx_url_t));

        u.url.len = server_addr->len;
        u.url.data = server_addr->data;

        if (ngx_parse_url(cf->pool, &u) != NGX_OK) {
            if (u.err) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "%s in tfs \"%V\"", u.err, &u.url);
            }

            return NGX_CONF_ERROR;
        }

        tu->ups_addr = u.addrs;

        return NGX_CONF_OK;
    }

    if (ngx_strcmp(value[0].data, "type") == 0) {

        if (cf->args->nelts != 2) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid number of arguments in "
                               "\"%s\" directive",
                               &value[0]);
            return NGX_CONF_ERROR;
        }

        if ((sizeof(NGX_HTTP_TFS_NAMESERVER_TYPE) - 1) == value[1].len
             && ngx_strcmp(value[1].data, NGX_HTTP_TFS_NAMESERVER_TYPE) == 0)
        {
            tu->enable_rcs = NGX_HTTP_TFS_NO;

        } else if ((sizeof(NGX_HTTP_TFS_RCSERVER_TYPE) - 1) == value[1].len
                   &&ngx_strcmp(value[1].data, NGX_HTTP_TFS_RCSERVER_TYPE) == 0)
        {
            tu->enable_rcs = NGX_HTTP_TFS_YES;

        } else {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid type \"%V\" in type directive",
                               &value[1]);
            return NGX_CONF_ERROR;
        }

        return NGX_CONF_OK;
    }

    if (ngx_strcmp(value[0].data, "rcs_zone") == 0) {
        return ngx_http_tfs_rcs_zone(cf, tu);
    }

    if (ngx_strcmp(value[0].data, "rcs_interface") == 0) {
        return ngx_http_tfs_rcs_interface(cf, tu);
    }

    if (ngx_strcmp(value[0].data, "rcs_heartbeat") == 0) {
        return ngx_http_tfs_rcs_heartbeat(cf, tu);
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[0]);

    return NGX_CONF_ERROR;
}


static char *
ngx_http_tfs_keepalive(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_tfs_main_conf_t  *tmcf = conf;

    ngx_int_t                    max_cached, bucket_count;
    ngx_str_t                   *value, s;
    ngx_uint_t                   i;
    ngx_http_connection_pool_t  *p;

    value = cf->args->elts;
    max_cached = 0;
    bucket_count = 0;

    for (i = 1; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data, "max_cached=", 11) == 0) {

            s.len = value[i].len - 11;
            s.data = value[i].data + 11;

            max_cached = ngx_atoi(s.data, s.len);

            if (max_cached == NGX_ERROR || max_cached == 0) {
                goto invalid;
            }
            continue;
        }

        if (ngx_strncmp(value[i].data, "bucket_count=", 13) == 0) {

            s.len = value[i].len - 13;
            s.data = value[i].data + 13;

            bucket_count = ngx_atoi(s.data, s.len);
            if (bucket_count == NGX_ERROR || bucket_count == 0) {
                goto invalid;
            }
            continue;
        }

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[i]);
        return NGX_CONF_ERROR;
    }

    p = ngx_http_connection_pool_init(cf->pool, max_cached, bucket_count);
    if (p == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "connection pool init failed");
        return NGX_CONF_ERROR;
    }

    tmcf->conn_pool = p;
    return NGX_CONF_OK;

invalid:
    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid value \"%V\" in \"%V\" directive",
                       &value[i], &cmd->name);
    return NGX_CONF_ERROR;
}


static char *
ngx_http_tfs_rcs_heartbeat(ngx_conf_t *cf, ngx_http_tfs_upstream_t *tu)
{
    ngx_str_t  *value, s;
    ngx_msec_t  interval;
    ngx_uint_t  i;

    value = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data, "lock_file=", 10) == 0) {
            s.data = value[i].data + 10;
            s.len = value[i].len - 10;

            if (ngx_conf_full_name(cf->cycle, &s, 0) != NGX_OK) {
                goto rcs_timers_error;
            }

            tu->lock_file = s;
            continue;
        }

        if (ngx_strncmp(value[i].data, "interval=", 9) == 0) {
            s.data = value[i].data + 9;
            s.len = value[i].len - 9;

            interval = ngx_parse_time(&s, 0);

            if (interval == (ngx_msec_t) NGX_ERROR) {
                return "invalid value";
            }

            tu->rcs_interval = interval;
            continue;
        }

        goto rcs_timers_error;
    }

    if (tu->lock_file.len == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "tfs_poll directive must have lock file");
        return NGX_CONF_ERROR;
    }

    if (tu->rcs_interval < NGX_HTTP_TFS_MIN_TIMER_DELAY) {
        tu->rcs_interval = NGX_HTTP_TFS_MIN_TIMER_DELAY;
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "tfs_poll interval is small, "
                           "so reset this value to 1000");
    }

    return NGX_CONF_OK;

rcs_timers_error:
    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid value \"%V\" in \"%V\" directive",
                       &value[i], &value[0]);
    return NGX_CONF_ERROR;
}


static char *
ngx_http_tfs_rcs_interface(ngx_conf_t *cf, ngx_http_tfs_upstream_t *tu)
{
    ngx_int_t   rc;
    ngx_str_t  *value;

    if (cf->args->nelts != 2) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid number of arguments in "
                           "\"rcs_interface\" directive");
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;
    rc = ngx_http_tfs_get_local_ip(value[1], &tu->local_addr);
    if (rc == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "device is invalid(%V)",
                           &value[1]);
        return NGX_CONF_ERROR;
    }

    ngx_inet_ntop(AF_INET, &tu->local_addr.sin_addr, tu->local_addr_text,
                  NGX_INET_ADDRSTRLEN);
    return NGX_CONF_OK;
}


static char *
ngx_http_tfs_log(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_tfs_srv_conf_t  *tscf = conf;

    if (tscf->log != NULL) {
        return "is duplicate";
    }

    return ngx_log_set_log(cf, &tscf->log);
}


static void *
ngx_http_tfs_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_tfs_srv_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_tfs_srv_conf_t));
    if (conf == NULL) {
        return NGX_CONF_ERROR;
    }

    return conf;
}


static char *
ngx_http_tfs_merge_srv_conf(ngx_conf_t *cf, void *parent, void *child)
{
    return NGX_CONF_OK;
}


static void *
ngx_http_tfs_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_tfs_main_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_tfs_main_conf_t));
    if (conf == NULL) {
        return NGX_CONF_ERROR;
    }

    conf->tfs_connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->tfs_send_timeout = NGX_CONF_UNSET_MSEC;
    conf->tfs_read_timeout = NGX_CONF_UNSET_MSEC;

    conf->tair_timeout = NGX_CONF_UNSET_MSEC;

    conf->send_lowat = NGX_CONF_UNSET_SIZE;
    conf->buffer_size = NGX_CONF_UNSET_SIZE;
    conf->body_buffer_size = NGX_CONF_UNSET_SIZE;

    conf->conn_pool = NGX_CONF_UNSET_PTR;

    conf->enable_remote_block_cache = NGX_CONF_UNSET;

    if (ngx_array_init(&conf->upstreams, cf->pool, 4,
                       sizeof(ngx_http_tfs_upstream_t *))
        != NGX_OK)
    {
        return NULL;
    }

    return conf;
}


static char *
ngx_http_tfs_init_main_conf(ngx_conf_t *cf, void *conf)
{
    ngx_http_tfs_main_conf_t *tmcf = conf;

    if (tmcf->tfs_connect_timeout == NGX_CONF_UNSET_MSEC) {
        tmcf->tfs_connect_timeout = 3000;
    }

    if (tmcf->tfs_send_timeout == NGX_CONF_UNSET_MSEC) {
        tmcf->tfs_send_timeout = 3000;
    }

    if (tmcf->tfs_read_timeout == NGX_CONF_UNSET_MSEC) {
        tmcf->tfs_read_timeout = 3000;
    }

    if (tmcf->tair_timeout == NGX_CONF_UNSET_MSEC) {
        tmcf->tair_timeout = 3000;
    }

    if (tmcf->send_lowat == NGX_CONF_UNSET_SIZE) {
        tmcf->send_lowat = 0;
    }

    if (tmcf->buffer_size == NGX_CONF_UNSET_SIZE) {
        tmcf->buffer_size = (size_t) ngx_pagesize / 2;
    }

    if (tmcf->body_buffer_size == NGX_CONF_UNSET_SIZE) {
        tmcf->body_buffer_size = NGX_HTTP_TFS_DEFAULT_BODY_BUFFER_SIZE;
    }

    return NGX_CONF_OK;
}


static void *
ngx_http_tfs_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_tfs_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_tfs_loc_conf_t));
    if (conf == NULL) {
        return NGX_CONF_ERROR;
    }

    return conf;
}


static char *ngx_http_tfs_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child)
{
    return NGX_CONF_OK;
}


static char *
ngx_http_tfs_pass(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_int_t                  add;
    ngx_str_t                 *value, s;
    ngx_url_t                  u;
    ngx_http_tfs_loc_conf_t   *tlcf;
    ngx_http_tfs_main_conf_t  *tmcf;
    ngx_http_core_loc_conf_t  *clcf;

    value = cf->args->elts;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    tmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_tfs_module);
    tlcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_tfs_module);

    if (ngx_strncasecmp(value[1].data, (u_char *) "tfs://", 6) == 0) {
        add = 6;

    } else {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid URL prefix in tfs_pass");
        return NGX_CONF_ERROR;
    }

    ngx_memzero(&u, sizeof(ngx_url_t));

    u.url.len = value[1].len - add;
    u.url.data = value[1].data + add;
    u.uri_part = 1;
    u.no_resolve = 1;

    tlcf->upstream = ngx_http_tfs_upstream_add(cf, &u,
                                               NGX_HTTP_TFS_UPSTREAM_FIND);
    if (tlcf->upstream == NULL) {
        return NGX_CONF_ERROR;
    }

    clcf->handler = ngx_http_tfs_handler;

    if (clcf->name.data[clcf->name.len - 1] == '/') {
        clcf->auto_redirect = 1;
    }

    if (tlcf->upstream->enable_rcs) {
        if (tlcf->upstream->local_addr_text[0] == '\0') {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "in tfs module must assign net device name, "
                               "use directives \"rcs_interface\" ");
            return NGX_CONF_ERROR;
        }

        tlcf->upstream->rcs_shm_zone = ngx_shared_memory_add(cf,
                                              &tlcf->upstream->rcs_zone_name, 0,
                                              &ngx_http_tfs_module);
        if (tlcf->upstream->rcs_shm_zone == NULL) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "in tfs module must assign rcs shm zone,"
                               "use directives \"rcs_zone\" ");
            return NGX_CONF_ERROR;
        }
    }

    if (tmcf->local_block_cache_ctx != NULL) {
        s.data = (u_char *) NGX_HTTP_TFS_BLOCK_CACHE_ZONE_NAME;
        s.len = sizeof(NGX_HTTP_TFS_BLOCK_CACHE_ZONE_NAME) - 1;

        tmcf->block_cache_shm_zone = ngx_shared_memory_add(cf, &s, 0,
                                                          &ngx_http_tfs_module);
        if (tmcf->block_cache_shm_zone == NULL) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "in tfs module must assign block cache shm zone,"
                               "use directives \"tfs_block_cache_zone\" ");
            return NGX_CONF_ERROR;
        }
    }

    tlcf->upstream->used = 1;

    return NGX_CONF_OK;
}


static char *
ngx_http_tfs_lowat_check(ngx_conf_t *cf, void *post, void *data)
{
#if (NGX_FREEBSD)
    ssize_t *np = data;

    if ((u_long) *np >= ngx_freebsd_net_inet_tcp_sendspace) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"tfs_send_lowat\" must be less than %d "
                           "(sysctl net.inet.tcp.sendspace)",
                           ngx_freebsd_net_inet_tcp_sendspace);

        return NGX_CONF_ERROR;
    }

#elif !(NGX_HAVE_SO_SNDLOWAT)
    ssize_t *np = data;

    ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                       "\"tfs_send_lowat\" is not supported, ignored");

    *np = 0;

#endif

    return NGX_CONF_OK;
}


static char *
ngx_http_tfs_rcs_zone(ngx_conf_t *cf, ngx_http_tfs_upstream_t *tu)
{
    ssize_t                 size;
    ngx_str_t              *value, s, name;
    ngx_uint_t              i;
    ngx_shm_zone_t         *shm_zone;
    ngx_http_tfs_rc_ctx_t  *ctx;

    value = cf->args->elts;
    size = 0;
    name.len = 0;

    if (cf->args->nelts != 3) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid number of arguments in "
                           "\"rcs_zone\" directive");
        return NGX_CONF_ERROR;
    }

    for (i = 1; i < cf->args->nelts; i++) {

        if (ngx_strncmp(value[i].data, "size=", 5) == 0) {
            s.len = value[i].len - 5;
            s.data = value[i].data + 5;

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

        if (ngx_strncmp(value[i].data, "name=", 5) == 0) {
            name.len = value[i].len - 5;
            name.data = value[i].data + 5;

            continue;
        }

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[i]);
        return NGX_CONF_ERROR;
    }


    if (size == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"rcs_zone\" must have \"size\" parameter");
        return NGX_CONF_ERROR;
    }

    if (name.len == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"rcs_zone\" must have  \"name\" parameter");
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_tfs_rc_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    shm_zone = ngx_shared_memory_add(cf, &name, size,
                                     &ngx_http_tfs_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    shm_zone->init = ngx_http_tfs_rc_server_init_zone;
    shm_zone->data = ctx;

    tu->rc_ctx = ctx;
    tu->rcs_zone_name = name;

    return NGX_CONF_OK;
}


static char *
ngx_http_tfs_block_cache_zone(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    size_t                                 size;
    ngx_str_t                             *value, s, name;
    ngx_uint_t                             i;
    ngx_shm_zone_t                        *shm_zone;
    ngx_http_tfs_main_conf_t              *tmcf = conf;
    ngx_http_tfs_local_block_cache_ctx_t  *ctx;

    value = cf->args->elts;
    size = 0;

    for (i = 1; i < cf->args->nelts; i++) {

        if (ngx_strncmp(value[i].data, "size=", 5) == 0) {
            s.len = value[i].len - 5;
            s.data = value[i].data + 5;

            size = ngx_parse_size(&s);
            if (size > 8191) {
                continue;
            }
        }

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[i]);
        return NGX_CONF_ERROR;
    }


    if (size == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"%V\" must have \"size\" parameter",
                           &cmd->name);
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_tfs_local_block_cache_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    name.data = (u_char *) NGX_HTTP_TFS_BLOCK_CACHE_ZONE_NAME;
    name.len = sizeof(NGX_HTTP_TFS_BLOCK_CACHE_ZONE_NAME) - 1;

    shm_zone = ngx_shared_memory_add(cf, &name, size,
                                     &ngx_http_tfs_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    shm_zone->init = ngx_http_tfs_local_block_cache_init_zone;
    shm_zone->data = ctx;

    tmcf->local_block_cache_ctx = ctx;

    return NGX_CONF_OK;
}


static void
ngx_http_tfs_read_body_handler(ngx_http_request_t *r)
{
    ngx_int_t          rc;
    ngx_http_tfs_t    *t;
    ngx_connection_t  *c;

    c = r->connection;
    t = ngx_http_get_module_ctx(r, ngx_http_tfs_module);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "http init tfs, client timer: %d", c->read->timer_set);

    if (c->read->timer_set) {
        ngx_del_timer(c->read);
    }

    if (ngx_event_flags & NGX_USE_CLEAR_EVENT) {

        if (!c->write->active) {
            if (ngx_add_event(c->write, NGX_WRITE_EVENT, NGX_CLEAR_EVENT)
                == NGX_ERROR)
            {
                ngx_http_finalize_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
                return;
            }
        }
    }

    if (t->r_ctx.large_file
        || t->r_ctx.fsname.file_type == NGX_HTTP_TFS_LARGE_FILE_TYPE)
    {
        t->is_large_file = NGX_HTTP_TFS_YES;
    }

    if (r->request_body) {
        t->send_body = r->request_body->bufs;
        if (t->send_body == NULL) {
            ngx_http_finalize_request(r, NGX_HTTP_BAD_REQUEST);
            return;
        }
        if (r->headers_in.content_length_n > NGX_HTTP_TFS_USE_LARGE_FILE_SIZE
            && t->r_ctx.version == 1)
        {
            t->is_large_file = NGX_HTTP_TFS_YES;
        }
        /* save large file data len here */
        if (t->is_large_file) {
            t->r_ctx.size = r->headers_in.content_length_n;
        }
    }

    rc = ngx_http_tfs_init(t);

    if (rc != NGX_OK) {
        switch (rc) {
        case NGX_HTTP_SPECIAL_RESPONSE ... NGX_HTTP_INTERNAL_SERVER_ERROR:
            ngx_http_finalize_request(r, rc);
            break;
        default:
            ngx_log_error(NGX_LOG_ERR, t->log, 0,
                          "ngx_http_tfs_init failed");
            ngx_http_finalize_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
        }
    }
}


static ngx_int_t
ngx_http_tfs_module_init(ngx_cycle_t *cycle)
{
    ngx_uint_t                   i;
    ngx_http_tfs_upstream_t    **tup;
    ngx_http_tfs_main_conf_t    *tmcf;
    ngx_http_tfs_timers_data_t  *data;

    tmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_tfs_module);
    if (tmcf == NULL) {
        return NGX_ERROR;
    }

    tup = tmcf->upstreams.elts;

    for (i = 0; i < tmcf->upstreams.nelts; i++) {
        if (!tup[i]->enable_rcs
            || !tup[i]->lock_file.len
            || !tup[i]->used)
        {
            return NGX_OK;
        }

        data = ngx_pcalloc(cycle->pool, sizeof(ngx_http_tfs_timers_data_t));
        if (data == NULL) {
            return NGX_ERROR;
        }

        data->main_conf = tmcf;
        data->upstream = tup[i];
        data->lock = ngx_http_tfs_timers_init(cycle, tup[i]->lock_file.data);
        if (data->lock == NULL)
        {
            return NGX_ERROR;
        }

        tup[i]->timer_data = data;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_tfs_check_init_worker(ngx_cycle_t *cycle)
{
    ngx_uint_t                 i;
    ngx_http_tfs_upstream_t  **tup;
    ngx_http_tfs_main_conf_t  *tmcf;

    /* rc keepalive */
    tmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_tfs_module);
    if (tmcf == NULL) {
        return NGX_ERROR;
    }

    tup = tmcf->upstreams.elts;

    for (i = 0; i < tmcf->upstreams.nelts; i++) {
        if (!tup[i]->enable_rcs
            || !tup[i]->lock_file.len
            || !tup[i]->used)
        {
            return NGX_OK;
        }

        if (ngx_http_tfs_add_rcs_timers(cycle, tup[i]->timer_data) == NGX_ERROR)
        {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


#ifdef NGX_HTTP_TFS_USE_TAIR
static void
ngx_http_tfs_check_exit_worker(ngx_cycle_t *cycle)
{
    ngx_int_t                      i;
    ngx_http_tfs_main_conf_t      *tmcf;
    ngx_http_tfs_tair_instance_t  *dup_instance;

    tmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_tfs_module);
    if (tmcf == NULL) {
        return;
    }

    /* destroy duplicate server */
    for (i = 0; i < NGX_HTTP_TFS_MAX_CLUSTER_COUNT; i++) {
        dup_instance = &tmcf->dup_instances[i];
        if (dup_instance->server != NULL) {
            ngx_http_etair_destory_server(dup_instance->server,
                                          (ngx_cycle_t *) ngx_cycle);
        }
    }

    /* destroy remote block cache server */
    if (tmcf->remote_block_cache_instance.server != NULL) {
        ngx_http_etair_destory_server(tmcf->remote_block_cache_instance.server,
                                      (ngx_cycle_t *) ngx_cycle);
    }

}
#endif
