
/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include <ngx_md5.h>


#define NGX_HTTP_SESSION_STICKY_PREFIX          0x0001
#define NGX_HTTP_SESSION_STICKY_INDIRECT        0x0002
#define NGX_HTTP_SESSION_STICKY_INSERT          0x0004
#define NGX_HTTP_SESSION_STICKY_REWRITE         0x0008
#define NGX_HTTP_SESSION_STICKY_FALLBACK_ON     0x0010
#define NGX_HTTP_SESSION_STICKY_FALLBACK_OFF    0x0020


typedef struct {
    ngx_str_t                           sid;
    ngx_str_t                          *name;
    struct sockaddr                    *sockaddr;
    socklen_t                           socklen;

#if (NGX_HTTP_UPSTREAM_CHECK)
    ngx_uint_t                          check_index;
#endif
} ngx_http_ss_server_t;


typedef struct {
    ngx_uint_t                          flag;

    ngx_int_t                           maxidle;
    ngx_int_t                           maxlife;
    ngx_str_t                           cookie;
    ngx_str_t                           domain;
    ngx_str_t                           path;
    ngx_str_t                           maxage;

    ngx_uint_t                          number;
    ngx_http_ss_server_t               *server;
} ngx_http_upstream_ss_srv_conf_t;


typedef struct {
    ngx_flag_t                          enable;
    ngx_http_upstream_srv_conf_t       *uscf;
} ngx_http_ss_loc_conf_t;


typedef struct {
    time_t                              lastseen;
    time_t                              firstseen;
    ngx_str_t                           s_lastseen;
    ngx_str_t                           s_firstseen;
    ngx_str_t                           sid;

    ngx_int_t                           tries;
    ngx_flag_t                          frist;

    ngx_http_upstream_ss_srv_conf_t    *ss_srv;
} ngx_http_ss_ctx_t;


typedef struct {
    ngx_http_upstream_rr_peer_data_t     rrp;
    ngx_http_request_t                  *r;

    ngx_event_get_peer_pt                get_rr_peer;

    ngx_http_upstream_ss_srv_conf_t     *ss_srv;
} ngx_http_upstream_ss_peer_data_t;


static void *ngx_http_upstream_session_sticky_create_srv_conf(ngx_conf_t *cf);
static void *ngx_http_session_sticky_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_session_sticky_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);
static ngx_int_t ngx_http_session_sticky_init(ngx_conf_t *cf);
static char *ngx_http_upstream_session_sticky(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_http_session_sticky_header(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_upstream_session_sticky_init_upstream(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_session_sticky_set_sid(ngx_conf_t *cf,
    ngx_http_ss_server_t *s);
static ngx_int_t ngx_http_upstream_session_sticky_init_peer(
    ngx_http_request_t *r, ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_session_sticky_get_peer(
    ngx_peer_connection_t *pc, void *data);
static ngx_int_t ngx_http_session_sticky_header_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_session_sticky_get_cookie(ngx_http_request_t *r);
static time_t ngx_http_session_sticky_atotm(u_char *s, ngx_int_t len);
static void ngx_http_session_sticky_tmtoa(ngx_http_request_t *r,
    ngx_str_t *str, time_t t);
static ngx_int_t ngx_http_session_sticky_header_filter(ngx_http_request_t *r);
static ngx_int_t ngx_http_session_sticky_prefix(ngx_http_request_t *r,
    ngx_table_elt_t *table);
static ngx_int_t ngx_http_session_sticky_rewrite(ngx_http_request_t *r,
    ngx_table_elt_t *table);
static ngx_int_t ngx_http_session_sticky_insert(ngx_http_request_t *r);


static ngx_http_output_header_filter_pt ngx_http_ss_next_header_filter;


static ngx_command_t ngx_http_session_sticky_commands[] = {
    { ngx_string("session_sticky"),
      NGX_HTTP_UPS_CONF|NGX_CONF_ANY|NGX_CONF_1MORE,
      ngx_http_upstream_session_sticky,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("session_sticky_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE12,
      ngx_http_session_sticky_header,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    ngx_null_command
};


static ngx_http_module_t ngx_http_session_sticky_ctx = {
    NULL,                                /* preconfiguration */
    ngx_http_session_sticky_init,        /* postconfiguration */

    NULL,                                /* create main configuration */
    NULL,                                /* init main configuration */

    ngx_http_upstream_session_sticky_create_srv_conf,
                                         /* create server configuration */
    NULL,                                /* merge server configuration */

    ngx_http_session_sticky_create_loc_conf,
                                         /* create location configuration */
    ngx_http_session_sticky_merge_loc_conf
                                         /* merge location configuration */
};


ngx_module_t ngx_http_session_sticky_module = {
    NGX_MODULE_V1,
    &ngx_http_session_sticky_ctx,        /* module context */
    ngx_http_session_sticky_commands,    /* module directives */
    NGX_HTTP_MODULE,                     /* module type */
    NULL,                                /* init master */
    NULL,                                /* init module */
    NULL,                                /* init process */
    NULL,                                /* init thread */
    NULL,                                /* exit thread */
    NULL,                                /* exit process */
    NULL,                                /* exit master */
    NGX_MODULE_V1_PADDING
};


static void *
ngx_http_upstream_session_sticky_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_upstream_ss_srv_conf_t  *ss_srv;

    ss_srv = ngx_pcalloc(cf->pool, sizeof(ngx_http_upstream_ss_srv_conf_t));
    if (ss_srv == NULL) {
        return NULL;
    }

    ss_srv->maxlife = NGX_MAX_INT32_VALUE;
    ss_srv->maxidle = NGX_MAX_INT32_VALUE;

    ss_srv->flag = NGX_HTTP_SESSION_STICKY_INSERT;
    ss_srv->cookie.data = (u_char *) "route";
    ss_srv->cookie.len = sizeof("route") - 1;

    return ss_srv;
}


static void *
ngx_http_session_sticky_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_ss_loc_conf_t  *ss_lcf;

    ss_lcf = ngx_palloc(cf->pool, sizeof(ngx_http_ss_loc_conf_t));
    if (ss_lcf == NULL) {
        return NULL;
    }

    ss_lcf->uscf = NGX_CONF_UNSET_PTR;
    ss_lcf->enable = NGX_CONF_UNSET;

    return ss_lcf;
}


static char *
ngx_http_session_sticky_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child)
{
    ngx_http_ss_loc_conf_t  *prev = parent;
    ngx_http_ss_loc_conf_t  *conf = child;

    ngx_conf_merge_value(conf->enable, prev->enable, 0);
    ngx_conf_merge_ptr_value(conf->uscf, prev->uscf, NGX_CONF_UNSET_PTR);

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_session_sticky_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt       *h;
    ngx_http_core_main_conf_t *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_PREACCESS_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_session_sticky_header_handler;

    ngx_http_ss_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_session_sticky_header_filter;

    return NGX_OK;
}


static char *
ngx_http_upstream_session_sticky(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_uint_t                       i;
    ngx_str_t                       *value;
    ngx_http_upstream_srv_conf_t    *uscf;
    ngx_http_upstream_ss_srv_conf_t *ss_srv = conf;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    uscf->peer.init_upstream = ngx_http_upstream_session_sticky_init_upstream;

    uscf->flags = NGX_HTTP_UPSTREAM_CREATE
                | NGX_HTTP_UPSTREAM_WEIGHT
                | NGX_HTTP_UPSTREAM_MAX_FAILS
                | NGX_HTTP_UPSTREAM_FAIL_TIMEOUT
                | NGX_HTTP_UPSTREAM_DOWN;

    value = cf->args->elts;
    for (i = 1; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data,
                        "cookie=",
                        sizeof("cookie=") - 1) == 0) {
            ss_srv->cookie.data = value[i].data + sizeof("cookie=") - 1;
            ss_srv->cookie.len = value[i].len - sizeof("cookie=") + 1;

        } else if (ngx_strncmp(value[i].data,
                               "domain=",
                               sizeof("domain=") - 1) == 0) {
            ss_srv->domain.data = value[i].data + sizeof("domain=") - 1;
            ss_srv->domain.len = value[i].len - sizeof("domain=") + 1;

        } else if (ngx_strncmp(value[i].data,
                               "path=",
                               sizeof("path=") - 1) == 0) {
            ss_srv->path.data = value[i].data + sizeof("path=") - 1;
            ss_srv->path.len = value[i].len - sizeof("path=") + 1;

        } else if (ngx_strncmp(value[i].data,
                               "maxage=",
                               sizeof("maxage=") - 1) == 0) {
            ss_srv->maxage.data = value[i].data + sizeof("maxage=") - 1;
            ss_srv->maxage.len = value[i].len - sizeof("maxage=") + 1;

        } else if (ngx_strncmp(value[i].data,
                               "maxidle=",
                               sizeof("maxidle=") - 1) == 0) {
            ss_srv->maxidle = ngx_atotm(value[i].data + sizeof("maxidle=") - 1,
                                        value[i].len - sizeof("maxidle=") + 1);
            if (ss_srv->maxidle == NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid maxidle");
                return NGX_CONF_ERROR;
            }

            if (ss_srv->maxlife == NGX_CONF_UNSET) {
                ss_srv->maxlife = NGX_MAX_INT32_VALUE;
            }

        } else if (ngx_strncmp(value[i].data,
                               "maxlife=",
                               sizeof("maxlife=") - 1) == 0) {
            ss_srv->maxlife = ngx_atotm(value[i].data + sizeof("maxlife=") - 1,
                                        value[i].len - sizeof("maxlife=") + 1);
            if (ss_srv->maxlife == NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid maxlife");
                return NGX_CONF_ERROR;
            }

            if (ss_srv->maxidle == NGX_CONF_UNSET) {
                ss_srv->maxidle = NGX_MAX_INT32_VALUE;
            }

        } else if (ngx_strncmp(value[i].data,
                               "mode=",
                               sizeof("mode=") - 1) == 0) {

            value[i].data = value[i].data + sizeof("mode=") - 1;
            value[i].len = value[i].len - sizeof("mode=") + 1;

            if (ngx_strncmp(value[i].data, "insert", value[i].len) == 0) {
                ss_srv->flag |= NGX_HTTP_SESSION_STICKY_INSERT;

            } else if (ngx_strncmp(value[i].data,
                                   "prefix",
                                   value[i].len) == 0)
            {
                ss_srv->flag = NGX_HTTP_SESSION_STICKY_PREFIX;

            } else if (ngx_strncmp(value[i].data,
                                   "rewrite",
                                   value[i].len) == 0)
            {
                ss_srv->flag = NGX_HTTP_SESSION_STICKY_REWRITE;

            } else {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid mode");
                return NGX_CONF_ERROR;
            }

        } else if (ngx_strncmp(value[i].data,
                               "option=",
                               sizeof("option=") - 1) == 0) {
            value[i].data = value[i].data + sizeof("option=") - 1;
            value[i].len = value[i].len - sizeof("option=") + 1;

            if (ngx_strncmp(value[i].data, "indirect", value[i].len) == 0) {
                ss_srv->flag |= NGX_HTTP_SESSION_STICKY_INDIRECT;

            } else if (ngx_strncmp(value[i].data,
                                   "direct",
                                   value[i].len) == 0)
            {
                ss_srv->flag &= ~NGX_HTTP_SESSION_STICKY_INDIRECT;

            } else {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid option");
                return NGX_CONF_ERROR;
            }

        } else if (ngx_strncmp(value[i].data,
                               "fallback=",
                               sizeof("fallback=") - 1) == 0) {
            value[i].data = value[i].data + sizeof("fallback=") - 1;
            value[i].len = value[i].len - sizeof("fallback=") + 1;

            if (ngx_strncmp(value[i].data, "on", sizeof("on") - 1) == 0) {
                ss_srv->flag |= NGX_HTTP_SESSION_STICKY_FALLBACK_ON;

            } else if (ngx_strncmp(value[i].data,
                                   "off",
                                   sizeof("off") - 1) == 0)
            {
                ss_srv->flag |= NGX_HTTP_SESSION_STICKY_FALLBACK_OFF;

            } else {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid fallback");
                return NGX_CONF_ERROR;
            }

        } else {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid argument");
            return NGX_CONF_ERROR;
        }
    }
    return NGX_CONF_OK;
}


static char *
ngx_http_session_sticky_header(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    size_t                   add;
    ngx_str_t               *value;
    ngx_url_t                u;
    ngx_uint_t               i;
    ngx_http_ss_loc_conf_t  *ss_lcf = conf;

    value = (ngx_str_t *) cf->args->elts;
    ss_lcf->enable = 1;

    for (i = 1; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data,
                        "upstream=",
                        sizeof("upstream=") - 1) == 0) {

            add = sizeof("upstream=") - 1;

            ngx_memzero(&u, sizeof(ngx_url_t));

            u.url.len = value[i].len - add;
            u.url.data = value[i].data + add;
            u.uri_part = 1;
            u.no_resolve = 1;

            ss_lcf->uscf = ngx_http_upstream_add(cf, &u, 0);
            if (ss_lcf->uscf == NULL) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid upstream name");
                return NGX_CONF_ERROR;
            }

        } else if (ngx_strncmp(value[i].data,
                               "switch",
                               sizeof("switch") - 1) == 0) {
            add = sizeof("switch=") - 1;

            if (ngx_strncmp(value[i].data + add,
                            "on",
                            sizeof("on") - 1) == 0)
            {
                ss_lcf->enable = 1;
            } else {
                ss_lcf->enable = 0;
            }

        } else {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid argument of \"%V\"", &value[i]);
            return NGX_CONF_ERROR;
        }
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_upstream_session_sticky_init_upstream(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_uint_t                        number, i;
    ngx_http_upstream_rr_peer_t      *peer;
    ngx_http_upstream_rr_peers_t     *peers;
    ngx_http_upstream_ss_srv_conf_t  *ss_scf;

    if (ngx_http_upstream_init_round_robin(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    ss_scf = ngx_http_conf_upstream_srv_conf(us,
                                    ngx_http_session_sticky_module);
    if (ss_scf == NULL) {
        return NGX_ERROR;
    }

    peers = (ngx_http_upstream_rr_peers_t *) us->peer.data;
    number = peers->number;

    ss_scf->server = ngx_palloc(cf->pool,
                                number * sizeof(ngx_http_ss_server_t));
    if (ss_scf->server == NULL) {
        return NGX_ERROR;
    }

    ss_scf->number = number;

    for (i = 0; i < number; i++) {
        peer = &peers->peer[i];

        ss_scf->server[i].name = &peer->name;
        ss_scf->server[i].sockaddr = peer->sockaddr;
        ss_scf->server[i].socklen = peer->socklen;

#if (NGX_HTTP_UPSTREAM_CHECK)
        ss_scf->server[i].check_index = peer->check_index;
#endif

        if (ngx_http_upstream_session_sticky_set_sid(cf,
                                    &ss_scf->server[i]) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    us->peer.init = ngx_http_upstream_session_sticky_init_peer;

    return NGX_OK;
}

/*
 * TODO: now the ID could be fetched from the server argument.
 * This session ID could be equal to the server ID.
 */
static ngx_int_t
ngx_http_upstream_session_sticky_set_sid(ngx_conf_t *cf,
    ngx_http_ss_server_t *s)
{
    u_char     buf[16];
    ngx_md5_t  md5;

    s->sid.len = 32;
    s->sid.data = ngx_pnalloc(cf->pool, 32);
    if (s->sid.data == NULL) {
        return NGX_ERROR;
    }

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, s->name->data, s->name->len);
    ngx_md5_final(buf, &md5);

    ngx_hex_dump(s->sid.data, buf, 16);

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_session_sticky_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_int_t                          rc;
    ngx_http_ss_ctx_t                 *ctx;
    ngx_http_upstream_ss_srv_conf_t   *ss_srv;
    ngx_http_upstream_ss_peer_data_t  *ss_pd;

    ss_pd = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_ss_peer_data_t));
    if (ss_pd == NULL) {
        return NGX_ERROR;
    }

    r->upstream->peer.data = &ss_pd->rrp;
    rc = ngx_http_upstream_init_round_robin_peer(r, us);
    if (rc != NGX_OK) {
        return rc;
    }

    ss_srv = ngx_http_conf_upstream_srv_conf(us,
                                    ngx_http_session_sticky_module);
    ctx = ngx_http_get_module_ctx(r, ngx_http_session_sticky_module);
    if (ctx == NULL) {
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_ss_ctx_t));
        if (ctx == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "session sticky ctx allocated failed");
            return NGX_ERROR;
        }

        ctx->ss_srv = ss_srv;

        ngx_http_set_ctx(r, ctx, ngx_http_session_sticky_module);

        rc = ngx_http_session_sticky_get_cookie(r);
        if (rc != NGX_OK) {
            return rc;
        }
    } else {
        if (ctx->ss_srv != ss_srv) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "different ss_srv with header_handler");
        }
    }

    ss_pd->r = r;
    ss_pd->ss_srv = ss_srv;
    ss_pd->get_rr_peer = ngx_http_upstream_get_round_robin_peer;

    r->upstream->peer.data = ss_pd;
    r->upstream->peer.get = ngx_http_upstream_session_sticky_get_peer;

    return NGX_OK;
}


static ngx_int_t
ngx_http_session_sticky_header_handler(ngx_http_request_t *r)
{
    ngx_http_ss_ctx_t               *ctx;
    ngx_http_ss_loc_conf_t          *ss_lcf;
    ngx_http_upstream_srv_conf_t    *uscf;
    ngx_http_upstream_ss_srv_conf_t *ss_srv;

    ss_lcf = ngx_http_get_module_loc_conf(r, ngx_http_session_sticky_module);
    if (ss_lcf->enable == 0) {
        return NGX_DECLINED;
    }

    if (ss_lcf->uscf == NGX_CONF_UNSET_PTR) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "session sticky didn't configure session_sticky_header");

        return NGX_DECLINED;
    }

    uscf = ss_lcf->uscf;
    ss_srv = ngx_http_conf_upstream_srv_conf(uscf,
                                             ngx_http_session_sticky_module);
    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_ss_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_http_set_ctx(r, ctx, ngx_http_session_sticky_module);
    ctx->ss_srv = ss_srv;

    return ngx_http_session_sticky_get_cookie(r);
}


static ngx_int_t
ngx_http_session_sticky_get_cookie(ngx_http_request_t *r)
{
    time_t                           now;
    u_char                          *p, *v, *vv, *st, *last, *end;
    ngx_int_t                        diff;
    ngx_str_t                       *cookie;
    ngx_uint_t                       i;
    ngx_table_elt_t                **cookies;
    ngx_http_ss_ctx_t               *ctx;
    ngx_http_upstream_ss_srv_conf_t *ss_srv;

    ctx = ngx_http_get_module_ctx(r, ngx_http_session_sticky_module);
    ss_srv = ctx->ss_srv;
    ctx->tries = 1;

    p = NULL;
    cookie = NULL;
    now = ngx_time();
    cookies = (ngx_table_elt_t **) r->headers_in.cookies.elts;
    for (i = 0; i < r->headers_in.cookies.nelts; i++) {
        cookie = &cookies[i]->value;
        p = ngx_strnstr(cookie->data,
                        (char *) ss_srv->cookie.data,
                        cookie->len);
        if (p == NULL) {
            continue;
        }

        if (*(p + ss_srv->cookie.len) == ' '
            || *(p + ss_srv->cookie.len) == '=')
        {
            break;
        }
    }

    if (i >= r->headers_in.cookies.nelts) {
        goto not_found;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "session sticky cookie: \"%V\"", &cookies[i]->value);
    st = p;
    last = cookie->data + cookie->len;

    /* TODO: need fix */
    while (p < last) {
        if (*p == '=') {
            p++;
            break;
        } else if (*p == ';') {
            goto not_found;
        }
        p++;
    }

    if (p >= last) {
        goto not_found;
    }

    while ((*p == ' ' || *p == '"') && p < last){ p++;}
    if (p >= last) {
        goto not_found;
    }

    v = p;
    while (*p != ' ' && *p != '"' && *p != ';' && *p != ',' && p < last) { p++;}

    end = p;
    while (end < last) {
        if (*end == ';') {
            end++;
            break;
        }
        end++;
    }

    if (ss_srv->flag & NGX_HTTP_SESSION_STICKY_PREFIX) {
        st = v;
        for (vv = v; vv < p; vv++) {
            if (*vv == '~') {
                end = vv + 1;
                break;
            }
        }

    } else {
        vv = p;
    }

    if (ss_srv->flag & NGX_HTTP_SESSION_STICKY_INSERT
        && ss_srv->maxidle != NGX_CONF_UNSET) {

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "session_sticky mode [insert]");

        for (p = v; p < vv; p++) {
            if (*p == '!') {
                ctx->sid.len = p - v;
                ctx->sid.data = ngx_pnalloc(r->pool, ctx->sid.len);
                if (ctx->sid.data == NULL) {
                    return NGX_ERROR;
                }
                ngx_memcpy(ctx->sid.data, v, ctx->sid.len);
                v = p + 1;

            } else if (*p == '^') {
                ctx->s_lastseen.len = p - v;
                ctx->s_lastseen.data = ngx_pnalloc(r->pool,
                                                   ctx->s_lastseen.len);
                if (ctx->s_lastseen.data == NULL) {
                    return NGX_ERROR;
                }
                ngx_memcpy(ctx->s_lastseen.data, v, ctx->s_lastseen.len);
                v = p + 1;
                break;
            }
        }

        if (p >= vv || v >= vv) {
            goto not_found;
        }

        ctx->s_firstseen.len = vv - v;
        ctx->s_firstseen.data = ngx_pnalloc(r->pool, ctx->s_firstseen.len);
        if (ctx->s_firstseen.data == NULL) {
            return NGX_ERROR;
        }
        ngx_memcpy(ctx->s_firstseen.data, v, ctx->s_firstseen.len);

        ctx->firstseen = ngx_http_session_sticky_atotm(ctx->s_firstseen.data,
                                                       ctx->s_firstseen.len);
        ctx->lastseen = ngx_http_session_sticky_atotm(ctx->s_lastseen.data,
                                                      ctx->s_lastseen.len);

        if (ctx->firstseen == NGX_ERROR || ctx->lastseen == NGX_ERROR) {
            goto not_found;
        }

        if (ctx->sid.len != 0) {
            diff = (ngx_int_t) (now - ctx->lastseen);
            if (diff < 0 || diff > ctx->ss_srv->maxidle) {
                goto not_found;
            }

            diff = (ngx_int_t) (now - ctx->firstseen);
            if (diff < 0 || diff > ctx->ss_srv->maxlife) {
                goto not_found;
            }
        }

        ngx_http_session_sticky_tmtoa(r, &ctx->s_lastseen, now);

    } else {
        ctx->sid.len = vv - v;
        ctx->sid.data = ngx_pnalloc(r->pool, ctx->sid.len);
        if (ctx->sid.data == NULL) {
            return NGX_ERROR;
        }
        ngx_memcpy(ctx->sid.data, v, ctx->sid.len);
    }

    if (ss_srv->flag
        & (NGX_HTTP_SESSION_STICKY_PREFIX
           | NGX_HTTP_SESSION_STICKY_INDIRECT)) {

        cookie->len -= (end - st);
        if (cookie->len == 0) {
            return ngx_list_delete(&r->headers_in.headers, cookies[i]);
        }
        while (end < last) {
            *st = *end;
            st++;
            end++;
        }
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "session sticky sid [%V]", &ctx->sid);
    return NGX_OK;

not_found:

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "session sticky [firstseen]");
    ctx->frist = 1;
    ctx->sid.len = 0;
    ctx->sid.data = NULL;
    ctx->firstseen = now;
    ctx->lastseen = now;

    ngx_http_session_sticky_tmtoa(r, &ctx->s_lastseen, ctx->lastseen);
    ngx_http_session_sticky_tmtoa(r, &ctx->s_firstseen, ctx->firstseen);

    if (ctx->s_lastseen.data == NULL || ctx->s_firstseen.data == NULL) {
        return NGX_ERROR;
    }
    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_session_sticky_get_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_int_t                          rc;
    ngx_uint_t                         i, n;
    ngx_http_ss_ctx_t                 *ctx;
    ngx_http_request_t                *r;
    ngx_http_ss_server_t              *server;
    ngx_http_upstream_ss_srv_conf_t   *ss_srv;
    ngx_http_upstream_ss_peer_data_t  *ss_pd = data;

    ss_srv = ss_pd->ss_srv;
    r = ss_pd->r;
    n = ss_srv->number;
    server = ss_srv->server;

    ctx = ngx_http_get_module_ctx(r, ngx_http_session_sticky_module);

    if (ctx->frist == 1 || ctx->sid.len == 0) {
        goto failed;
    }

    if (ctx->tries == 0
        && !(ctx->ss_srv->flag & NGX_HTTP_SESSION_STICKY_FALLBACK_OFF))
    {
        goto failed;
    }

    for (i = 0; i < n; i++) {
        if (ctx->sid.len == server[i].sid.len
            && ngx_strncmp(ctx->sid.data,
                           server[i].sid.data,
                           ctx->sid.len) == 0)
        {
#if (NGX_HTTP_UPSTREAM_CHECK)
            if (ngx_http_upstream_check_peer_down(server[i].check_index)) {
                if (ctx->ss_srv->flag & NGX_HTTP_SESSION_STICKY_FALLBACK_OFF) {
                    return NGX_BUSY;
                } else {
                    goto failed;
                }
            }
#endif
            pc->name = server[i].name;
            pc->socklen = server[i].socklen;
            pc->sockaddr = server[i].sockaddr;

            ctx->sid.len = server[i].sid.len;
            ctx->sid.data = server[i].sid.data;

            ss_pd->rrp.current = i;
            ctx->tries--;

            return NGX_OK;
        }
    }

    if (ctx->ss_srv->flag & NGX_HTTP_SESSION_STICKY_FALLBACK_OFF) {
        return NGX_BUSY;
    }

failed:

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "session sticky failed, sid[%V]", &ctx->sid);

    rc = ss_pd->get_rr_peer(pc, &ss_pd->rrp);
    if (rc != NGX_OK) {
        return rc;
    }

    for (i = 0; i < n; i++) {
        if (server[i].name->len == pc->name->len
            && ngx_strncmp(server[i].name->data,
                           pc->name->data,
                           pc->name->len) == 0)
        {
            ctx->sid.len = server[i].sid.len;
            ctx->sid.data = server[i].sid.data;
            break;
        }
    }

    return rc;
}


static time_t
ngx_http_session_sticky_atotm(u_char *s, ngx_int_t len)
{
    time_t     value;
    ngx_int_t  i;

    value = 0;

    for (i = 0; i < len; i++) {
        if (s[i] >= '0' && s[i] <= '9') {
            value = value * 10 + s[i] - '0';
        } else {
            return NGX_ERROR;
        }
    }

    return value;
}


static void
ngx_http_session_sticky_tmtoa(ngx_http_request_t *r, ngx_str_t *str, time_t t)
{
    time_t      temp;
    ngx_uint_t  len;

    len = 0;
    temp = t;
    while (temp) {
        len++;
        temp /= 10;
    }

    str->len = len;
    str->data = ngx_pcalloc(r->pool, len);
    if (str->data == NULL) {
        return;
    }

    while (t) {
        str->data[--len] = t % 10 + '0';
        t /= 10;
    }
}


static ngx_int_t
ngx_http_session_sticky_header_filter(ngx_http_request_t *r)
{
    ngx_int_t                rc;
    ngx_uint_t               i;
    ngx_list_part_t         *part;
    ngx_table_elt_t         *table;
    ngx_http_ss_ctx_t       *ctx;
    ngx_http_ss_loc_conf_t  *ss_lcf;

    if (r->headers_out.status >= NGX_HTTP_BAD_REQUEST) {
        return ngx_http_ss_next_header_filter(r);
    }

    ss_lcf = ngx_http_get_module_loc_conf(r, ngx_http_session_sticky_module);

    ctx = ngx_http_get_module_ctx(r, ngx_http_session_sticky_module);
    if (ctx == NULL || ctx->ss_srv == NULL || ctx->ss_srv->flag == 0) {
        return ngx_http_ss_next_header_filter(r);
    }

    if (ss_lcf->enable == 0
        && !(ctx->ss_srv->flag & NGX_HTTP_SESSION_STICKY_REWRITE)) {
        return ngx_http_ss_next_header_filter(r);
    }

    if (ctx->ss_srv->flag
        & (NGX_HTTP_SESSION_STICKY_PREFIX
           | NGX_HTTP_SESSION_STICKY_REWRITE)) {
        part = &r->headers_out.headers.part;
        while (part) {
            table = (ngx_table_elt_t *) part->elts;
            for (i = 0; i < part->nelts; i++) {
                if (table[i].key.len == (sizeof("set-cookie") - 1)
                    && ngx_strncasecmp(table[i].key.data,
                                        (u_char *) "set-cookie",
                                        table[i].key.len) == 0)
                {
                    if (ctx->ss_srv->flag & NGX_HTTP_SESSION_STICKY_REWRITE) {

                        rc = ngx_http_session_sticky_rewrite(r, &table[i]);
                        if (rc == NGX_AGAIN) {
                            continue;

                        } else if (rc == NGX_ERROR) {
                            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                                          "session_sticky [rewrite]"
                                          "set-cookie failed");
                        }

                        ngx_log_debug1(NGX_LOG_DEBUG_HTTP,
                                       r->connection->log,
                                       0,
                                       "session_sticky [rewrite]"
                                       "set-cookie: %V",
                                       &table[i].value);

                        return ngx_http_ss_next_header_filter(r);
                    }

                    rc = ngx_http_session_sticky_prefix(r, &table[i]);
                    if (rc == NGX_AGAIN) {
                        continue;

                    } else if (rc == NGX_ERROR) {
                        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                                      "session_sticky [prefix]"
                                      "set-cookie failed");
                    }

                    ngx_log_debug1(NGX_LOG_DEBUG_HTTP,
                                   r->connection->log,
                                   0,
                                   "session_sticky [prefix]"
                                   "set-cookie: %V",
                                   &table[i].value);

                    return ngx_http_ss_next_header_filter(r);
                }
            }
            part = part->next;
        }

    } else if (ctx->ss_srv->flag & NGX_HTTP_SESSION_STICKY_INSERT) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "session_sticky [insert]");

        rc = ngx_http_session_sticky_insert(r);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "session_sticky [insert] failed");
        }
    }

    return ngx_http_ss_next_header_filter(r);
}


static ngx_int_t
ngx_http_session_sticky_prefix(ngx_http_request_t *r, ngx_table_elt_t *table)
{
    u_char             *p, *s, *t, *last;
    ngx_http_ss_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_session_sticky_module);
    p = ngx_strlcasestrn(table->value.data,
                         table->value.data + table->value.len,
                         ctx->ss_srv->cookie.data,
                         ctx->ss_srv->cookie.len - 1);
    if (p == NULL) {
        return NGX_AGAIN;
    }

    last = table->value.data + table->value.len;
    table->value.len += ctx->sid.len + 1;

    s = ngx_pnalloc(r->pool, table->value.len);
    if (s == NULL) {
        return NGX_ERROR;
    }

    p += ctx->ss_srv->cookie.len;
    /* TODO: need fix */
    while(*p != '=' && p < last) { p++;}
    if (p < last) { p++;}
    while (*p == ' ' && p < last) { p++;}

    t = s;
    t = ngx_cpymem(t, table->value.data, p - table->value.data);
    t = ngx_cpymem(t, ctx->sid.data, ctx->sid.len);
    *t++ = '~';
    t = ngx_cpymem(t, p, last - p);

    table->value.data = s;

    return NGX_OK;
}


static ngx_int_t
ngx_http_session_sticky_rewrite(ngx_http_request_t *r, ngx_table_elt_t *table)
{
    u_char              *p, *st, *en, *last, *start;
    ngx_http_ss_ctx_t   *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_session_sticky_module);
    p = ngx_strlcasestrn(table->value.data,
                         table->value.data + table->value.len,
                         ctx->ss_srv->cookie.data,
                         ctx->ss_srv->cookie.len - 1);
    if (p == NULL) {
        return NGX_AGAIN;
    }

    st = p;
    start = table->value.data;
    last = table->value.data + table->value.len;

    /* TODO: need fix */
    while (p < last && *p != '=') { p++; }
    p += (p < last ? 1 : 0);

    while (p < last && (*p == ' ' || *p == '\t' || *p == '\n')) { p++; }
    p += (p < last ? 1 : 0);

    while (p < last && *p != ';') { p++;}

    en = p;

    table->value.len = table->value.len
                     - (en - st)
                     + ctx->ss_srv->cookie.len
                     + 1 /* '=' */
                     + ctx->sid.len;

    p = ngx_pnalloc(r->pool, table->value.len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    table->value.data = p;
    p = ngx_cpymem(p, start, st - start);
    p = ngx_cpymem(p, ctx->ss_srv->cookie.data, ctx->ss_srv->cookie.len);
    *p++ = '=';
    p = ngx_cpymem(p, ctx->sid.data, ctx->sid.len);
    p = ngx_cpymem(p, en, last - en);

    return NGX_OK;
}


static ngx_int_t
ngx_http_session_sticky_insert(ngx_http_request_t *r)
{
    u_char             *p;
    ngx_uint_t          i;
    ngx_list_part_t    *part;
    ngx_table_elt_t    *set_cookie, *table;
    ngx_http_ss_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_session_sticky_module);
    if (ctx->frist != 1 && ctx->ss_srv->maxidle == NGX_CONF_UNSET) {
        return NGX_OK;
    }

    set_cookie = NULL;
    if (ctx->ss_srv->flag & NGX_HTTP_SESSION_STICKY_INDIRECT) {
        part = &r->headers_out.headers.part;
        while (part && set_cookie == NULL) {
            table = (ngx_table_elt_t *) part->elts;
            for (i = 0; i < part->nelts; i++) {
                if (table[i].key.len == (sizeof("set-cookie") - 1)
                    && ngx_strncasecmp(table[i].key.data,
                                       (u_char *) "set-cookie",
                                       table[i].key.len) == 0)
                {
                    p = ngx_strlcasestrn(table[i].value.data,
                                         table[i].value.data +
                                         table[i].value.len,
                                         ctx->ss_srv->cookie.data,
                                         ctx->ss_srv->cookie.len - 1);
                    if (p != NULL) {
                        set_cookie = &table[i];
                        break;
                    }
                }
            }
            part = part->next;
        }
    }

    if (set_cookie == NULL) {
        set_cookie = ngx_list_push(&r->headers_out.headers);
        if (set_cookie == NULL) {
            return NGX_ERROR;
        }

        set_cookie->hash = 1;
        ngx_str_set(&set_cookie->key, "Set-Cookie");
    }

    set_cookie->value.len = ctx->ss_srv->cookie.len
                          + sizeof("=") - 1
                          + ctx->sid.len
                          + sizeof(";Domain=") - 1
                          + ctx->ss_srv->domain.len
                          + sizeof(";Path=") - 1
                          + ctx->ss_srv->path.len;

    if (ctx->ss_srv->maxidle != NGX_CONF_UNSET) {
        set_cookie->value.len = set_cookie->value.len
                              + ctx->s_lastseen.len
                              + ctx->s_firstseen.len
                              + 2; /* '!' and '^' */
    } else {
        set_cookie->value.len = set_cookie->value.len
                              + sizeof(";Max-Age=") - 1
                              + ctx->ss_srv->maxage.len;
    }

    p = ngx_pnalloc(r->pool, set_cookie->value.len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    set_cookie->value.data = p;

    p = ngx_cpymem(p, ctx->ss_srv->cookie.data, ctx->ss_srv->cookie.len);
    *p++ = '=';
    p = ngx_cpymem(p, ctx->sid.data, ctx->sid.len);
    if (ctx->ss_srv->maxidle != NGX_CONF_UNSET) {
        *(p++) = '!';
        p = ngx_cpymem(p, ctx->s_lastseen.data, ctx->s_lastseen.len);
        *(p++) = '^';
        p = ngx_cpymem(p, ctx->s_firstseen.data, ctx->s_firstseen.len);
    }
    if (ctx->ss_srv->domain.len) {
        p = ngx_cpymem(p, ";Domain=", sizeof(";Domain=") - 1);
        p = ngx_cpymem(p, ctx->ss_srv->domain.data, ctx->ss_srv->domain.len);
    }
    if (ctx->ss_srv->path.len) {
        p = ngx_cpymem(p, ";Path=", sizeof(";Path=") - 1);
        p = ngx_cpymem(p, ctx->ss_srv->path.data, ctx->ss_srv->path.len);
    }
    if (ctx->ss_srv->maxidle == NGX_CONF_UNSET && ctx->ss_srv->maxage.len) {
        p = ngx_cpymem(p, ";Max-Age=", sizeof(";Max-Age=") - 1);
        p = ngx_cpymem(p, ctx->ss_srv->maxage.data, ctx->ss_srv->maxage.len);
    }

    set_cookie->value.len = p - set_cookie->value.data;

    return NGX_OK;
}
