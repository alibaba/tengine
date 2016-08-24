
/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include <ngx_md5.h>


#define NGX_HTTP_SESSION_STICKY_DELIMITER       '|'
#define NGX_HTTP_SESSION_STICKY_PREFIX          0x0001
#define NGX_HTTP_SESSION_STICKY_INDIRECT        0x0002
#define NGX_HTTP_SESSION_STICKY_INSERT          0x0004
#define NGX_HTTP_SESSION_STICKY_REWRITE         0x0008
#define NGX_HTTP_SESSION_STICKY_FALLBACK_ON     0x0010
#define NGX_HTTP_SESSION_STICKY_FALLBACK_OFF    0x0020
#define NGX_HTTP_SESSION_STICKY_MD5             0x0040
#define NGX_HTTP_SESSION_STICKY_PLAIN           0X0080

#define is_space(c) ((c) == ' ' || (c) == '\t' || (c) == '\n')


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

    ngx_http_upstream_ss_srv_conf_t    *sscf;
} ngx_http_ss_ctx_t;


typedef struct {
    ngx_http_upstream_rr_peer_data_t    rrp;
    ngx_http_request_t                 *r;

#if (NGX_HTTP_SSL)
    ngx_ssl_session_t                  *ssl_session;
#endif

    ngx_event_get_peer_pt               get_rr_peer;

    ngx_http_upstream_ss_srv_conf_t    *sscf;
} ngx_http_upstream_ss_peer_data_t;


static ngx_int_t
    ngx_http_upstream_session_sticky_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t
    ngx_http_upstream_session_sticky_get_peer(ngx_peer_connection_t *pc,
    void *data);
static ngx_int_t ngx_http_session_sticky_header_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_session_sticky_get_cookie(ngx_http_request_t *r);
static void ngx_http_session_sticky_tmtoa(ngx_http_request_t *r,
    ngx_str_t *str, time_t t);
static ngx_int_t ngx_http_session_sticky_header_filter(ngx_http_request_t *r);
static ngx_int_t ngx_http_session_sticky_prefix(ngx_http_request_t *r,
    ngx_table_elt_t *table);
static ngx_int_t ngx_http_session_sticky_rewrite(ngx_http_request_t *r,
    ngx_table_elt_t *table);
static ngx_int_t ngx_http_session_sticky_insert(ngx_http_request_t *r);

static void *ngx_http_upstream_session_sticky_create_srv_conf(ngx_conf_t *cf);
static void *ngx_http_session_sticky_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_session_sticky_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);

static ngx_int_t ngx_http_session_sticky_init(ngx_conf_t *cf);
static char *ngx_http_upstream_session_sticky(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_http_session_sticky_hide_cookie(ngx_conf_t *cf,
    ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_upstream_session_sticky_init_upstream(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_session_sticky_set_sid(ngx_conf_t *cf,
    ngx_http_ss_server_t *s);

#if (NGX_HTTP_SSL)

static ngx_int_t ngx_http_upstream_session_sticky_set_peer_session(
    ngx_peer_connection_t *pc, void *data);
static void ngx_http_upstream_session_sticky_save_peer_session(
    ngx_peer_connection_t *pc, void *data);

#endif


static ngx_conf_deprecated_t ngx_conf_deprecated_session_sticky_header = {
    ngx_conf_deprecated, "session_sticky_header", "session_sticky_hide_cookie"
};

static ngx_http_output_header_filter_pt ngx_http_ss_next_header_filter;


static ngx_command_t ngx_http_session_sticky_commands[] = {

    { ngx_string("session_sticky"),
      NGX_HTTP_UPS_CONF|NGX_CONF_ANY|NGX_CONF_1MORE,
      ngx_http_upstream_session_sticky,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("session_sticky_hide_cookie"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_session_sticky_hide_cookie,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("session_sticky_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_session_sticky_hide_cookie,
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


ngx_module_t ngx_http_upstream_session_sticky_module = {
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


static ngx_int_t
ngx_http_upstream_session_sticky_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_int_t                          rc;
    ngx_http_ss_ctx_t                 *ctx;
    ngx_http_upstream_ss_srv_conf_t   *sscf;
    ngx_http_upstream_ss_peer_data_t  *sspd;

    sspd = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_ss_peer_data_t));
    if (sspd == NULL) {
        return NGX_ERROR;
    }

    r->upstream->peer.data = &sspd->rrp;
    rc = ngx_http_upstream_init_round_robin_peer(r, us);
    if (rc != NGX_OK) {
        return rc;
    }

    sscf = ngx_http_conf_upstream_srv_conf(us,
                                    ngx_http_upstream_session_sticky_module);
    ctx = ngx_http_get_module_ctx(r, ngx_http_upstream_session_sticky_module);
    if (ctx == NULL) {
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_ss_ctx_t));
        if (ctx == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "session sticky ctx allocated failed");
            return NGX_ERROR;
        }

        ctx->sscf = sscf;

        ngx_http_set_ctx(r, ctx, ngx_http_upstream_session_sticky_module);

        rc = ngx_http_session_sticky_get_cookie(r);
        if (rc != NGX_OK) {
            return rc;
        }

    } else {
        if (ctx->sscf != sscf) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "different sscf with header_handler");
        }
    }

    sspd->r = r;
    sspd->sscf = sscf;
    sspd->get_rr_peer = ngx_http_upstream_get_round_robin_peer;

    r->upstream->peer.data = sspd;
    r->upstream->peer.get = ngx_http_upstream_session_sticky_get_peer;

#if (NGX_HTTP_SSL)
    r->upstream->peer.set_session =
                            ngx_http_upstream_session_sticky_set_peer_session;
    r->upstream->peer.save_session =
                            ngx_http_upstream_session_sticky_save_peer_session;
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_http_session_sticky_header_handler(ngx_http_request_t *r)
{
    ngx_http_ss_ctx_t               *ctx;
    ngx_http_ss_loc_conf_t          *slcf;
    ngx_http_upstream_srv_conf_t    *uscf;
    ngx_http_upstream_ss_srv_conf_t *sscf;

    slcf = ngx_http_get_module_loc_conf(r,
                                    ngx_http_upstream_session_sticky_module);

    if (slcf->uscf == NGX_CONF_UNSET_PTR) {
        return NGX_DECLINED;
    }

    uscf = slcf->uscf;
    sscf = ngx_http_conf_upstream_srv_conf(uscf,
                                    ngx_http_upstream_session_sticky_module);
    if (sscf != NULL &&
        (sscf->flag & NGX_HTTP_SESSION_STICKY_REWRITE)) {
        return NGX_DECLINED;
    }

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_ss_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_http_set_ctx(r, ctx, ngx_http_upstream_session_sticky_module);
    ctx->sscf = sscf;

    return ngx_http_session_sticky_get_cookie(r);
}


static ngx_int_t
ngx_http_session_sticky_get_cookie(ngx_http_request_t *r)
{
    time_t                           now;
    u_char                          *p, *v, *vv, *st, *last, *end;
    ngx_int_t                        diff, delimiter, legal;
    ngx_str_t                       *cookie;
    ngx_uint_t                       i;
    ngx_table_elt_t                **cookies;
    ngx_http_ss_ctx_t               *ctx;
    ngx_http_upstream_ss_srv_conf_t *sscf;
    enum {
        pre_key = 0,
        key,
        pre_equal,
        pre_value,
        value
    } state;

    legal = 1;
    ctx = ngx_http_get_module_ctx(r, ngx_http_upstream_session_sticky_module);
    sscf = ctx->sscf;
    ctx->tries = 1;

    p = NULL;
    cookie = NULL;
    now = ngx_time();
    cookies = (ngx_table_elt_t **) r->headers_in.cookies.elts;
    for (i = 0; i < r->headers_in.cookies.nelts; i++) {
        cookie = &cookies[i]->value;
        p = ngx_strnstr(cookie->data, (char *) sscf->cookie.data, cookie->len);
        if (p == NULL) {
            continue;
        }

        if (*(p + sscf->cookie.len) == ' ' || *(p + sscf->cookie.len) == '=') {
            break;
        }
    }

    if (i >= r->headers_in.cookies.nelts) {
        goto not_found;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "session sticky cookie: \"%V\"", &cookies[i]->value);
    st = p;
    v = p + sscf->cookie.len + 1;
    last = cookie->data + cookie->len;

    state = 0;
    while (p < last) {
        switch (state) {
        case pre_key:
            if (*p == ';') {
                goto not_found;

            } else if (!is_space(*p)) {
                state = key;
            }

            break;

        case key:
            if (is_space(*p)) {
                state = pre_equal;

            } else if (*p == '=') {
                state = pre_value;
            }

            break;

        case pre_equal:
            if (*p == '=') {
                state = pre_value;

            } else if (!is_space(*p)) {
                goto not_found;
            }

            break;

        case pre_value:
            if (!is_space(*p)) {
                state = value;
                v = p--;
            }

            break;

        case value:
            if (*p == ';') {
                end = p + 1;
                goto success;
            }

            if (p + 1 == last) {
                end = last;
                p++;
                goto success;
            }

            break;

        default:
                break;
        }

        p++;
    }

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

success:

    if (sscf->flag & NGX_HTTP_SESSION_STICKY_PREFIX) {

        for (vv = v; vv < p; vv++) {
            if (*vv == '~') {
                end = vv + 1;
                break;
            }
        }
        if (vv >= p) {
            goto not_found;
        }
        st = v;

    } else {
        vv = p;
    }

    if ((sscf->flag & NGX_HTTP_SESSION_STICKY_INSERT)
        && sscf->maxidle != NGX_CONF_UNSET)
    {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "session_sticky mode [insert]");

        delimiter = 0;
        for (p = v; p < vv; p++) {
            if (*p == NGX_HTTP_SESSION_STICKY_DELIMITER) {
                delimiter++;
                if (delimiter == 1) {
                    ctx->sid.len = p - v;
                    ctx->sid.data = ngx_pnalloc(r->pool, ctx->sid.len);
                    if (ctx->sid.data == NULL) {
                        return NGX_ERROR;
                    }
                    ngx_memcpy(ctx->sid.data, v, ctx->sid.len);
                    v = p + 1;

                } else if(delimiter == 2) {
                    ctx->s_lastseen.len = p - v;
                    ctx->s_lastseen.data = ngx_pnalloc(r->pool,
                                                       ctx->s_lastseen.len);
                    if (ctx->s_lastseen.data == NULL) {
                        return NGX_ERROR;
                    }
                    ngx_memcpy(ctx->s_lastseen.data, v, ctx->s_lastseen.len);
                    v = p + 1;
                    break;

                } else {
                    legal = 0;
                    goto finish;
                }
            }
        }

        if (p >= vv || v >= vv) {
            legal = 0;
            goto finish;

        }

        ctx->s_firstseen.len = vv - v;
        ctx->s_firstseen.data = ngx_pnalloc(r->pool, ctx->s_firstseen.len);
        if (ctx->s_firstseen.data == NULL) {
            return NGX_ERROR;
        }
        ngx_memcpy(ctx->s_firstseen.data, v, ctx->s_firstseen.len);

        ctx->firstseen = ngx_atotm(ctx->s_firstseen.data, ctx->s_firstseen.len);
        ctx->lastseen = ngx_atotm(ctx->s_lastseen.data, ctx->s_lastseen.len);

        if (ctx->firstseen == NGX_ERROR || ctx->lastseen == NGX_ERROR) {
            legal = 0;
            goto finish;
        }

        if (ctx->sid.len != 0) {
            diff = (ngx_int_t) (now - ctx->lastseen);
            if (diff > ctx->sscf->maxidle || diff < -86400) {
                legal = 0;
                goto finish;
            }

            diff = (ngx_int_t) (now - ctx->firstseen);
            if (diff > ctx->sscf->maxlife || diff < -86400) {
                legal = 0;
                goto finish;
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

finish:

    if (sscf->flag
        & (NGX_HTTP_SESSION_STICKY_PREFIX | NGX_HTTP_SESSION_STICKY_INDIRECT))
    {
        cookie->len -= (end - st);

        if (cookie->len == 0) {
            cookies[i]->hash = 0;
            return NGX_OK;
        }

        while (end < last) {
            *st++ = *end++;
        }
    }

    if (legal == 0) {
        goto not_found;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "session sticky sid [%V]", &ctx->sid);
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
    ngx_http_upstream_ss_srv_conf_t   *sscf;
    ngx_http_upstream_ss_peer_data_t  *sspd = data;

    sscf = sspd->sscf;
    r = sspd->r;
    n = sscf->number;
    server = sscf->server;

    ctx = ngx_http_get_module_ctx(r, ngx_http_upstream_session_sticky_module);

    if (ctx->frist == 1 || ctx->sid.len == 0) {
        goto failed;
    }

    if (ctx->tries == 0
        && !(ctx->sscf->flag & NGX_HTTP_SESSION_STICKY_FALLBACK_OFF))
    {
        goto failed;
    }

    for (i = 0; i < n; i++) {
        if (ctx->sid.len == server[i].sid.len
            && ngx_strncmp(ctx->sid.data, server[i].sid.data,
                           ctx->sid.len) == 0)
        {
#if (NGX_HTTP_UPSTREAM_CHECK)
            if (ngx_http_upstream_check_peer_down(server[i].check_index)) {
                if (ctx->sscf->flag & NGX_HTTP_SESSION_STICKY_FALLBACK_OFF) {
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

            sspd->rrp.current = i;
            ctx->tries--;

            return NGX_OK;
        }
    }

failed:
    if (ctx->frist != 1 &&
        (ctx->sscf->flag & NGX_HTTP_SESSION_STICKY_FALLBACK_OFF))
    {
        return NGX_BUSY;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "session sticky failed, sid[%V]", &ctx->sid);

    rc = sspd->get_rr_peer(pc, &sspd->rrp);
    if (rc != NGX_OK) {
        return rc;
    }

    for (i = 0; i < n; i++) {
        if (server[i].name->len == pc->name->len
            && ngx_strncmp(server[i].name->data, pc->name->data,
                           pc->name->len) == 0)
        {
            ctx->sid.len = server[i].sid.len;
            ctx->sid.data = server[i].sid.data;
            break;
        }
    }
    ctx->frist = 1;

    return rc;
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
    ngx_http_ss_loc_conf_t  *slcf;

    if (r->headers_out.status >= NGX_HTTP_BAD_REQUEST) {
        return ngx_http_ss_next_header_filter(r);
    }

    slcf = ngx_http_get_module_loc_conf(r,
               ngx_http_upstream_session_sticky_module);

    ctx = ngx_http_get_module_ctx(r, ngx_http_upstream_session_sticky_module);
    if (ctx == NULL || ctx->sscf == NULL || ctx->sscf->flag == 0) {
        return ngx_http_ss_next_header_filter(r);
    }

    if ((slcf->uscf == NGX_CONF_UNSET_PTR)
         && ((ctx->sscf->flag & NGX_HTTP_SESSION_STICKY_PREFIX)
            || (ctx->sscf->flag & NGX_HTTP_SESSION_STICKY_INDIRECT)))
    {
        return ngx_http_ss_next_header_filter(r);
    }

    if (ctx->sscf->flag
        & (NGX_HTTP_SESSION_STICKY_PREFIX | NGX_HTTP_SESSION_STICKY_REWRITE))
    {
        part = &r->headers_out.headers.part;
        while (part) {
            table = (ngx_table_elt_t *) part->elts;
            for (i = 0; i < part->nelts; i++) {
                if (table[i].key.len == (sizeof("set-cookie") - 1)
                    && ngx_strncasecmp(table[i].key.data,
                                       (u_char *) "set-cookie",
                                       table[i].key.len) == 0)
                {
                    if (ctx->sscf->flag & NGX_HTTP_SESSION_STICKY_REWRITE) {

                        rc = ngx_http_session_sticky_rewrite(r, &table[i]);
                        if (rc == NGX_AGAIN) {
                            continue;

                        } else if (rc == NGX_ERROR) {
                            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                                          "session_sticky [rewrite]"
                                          "set-cookie failed");
                        }

                        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log,
                                       0,
                                       "session_sticky [rewrite] set-cookie:%V",
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

                    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log,
                                   0, "session_sticky [prefix]"
                                   "set-cookie: %V",
                                   &table[i].value);

                    return ngx_http_ss_next_header_filter(r);
                }
            }

            part = part->next;
        }

    } else if (ctx->sscf->flag & NGX_HTTP_SESSION_STICKY_INSERT) {
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
    enum {
        pre_equal = 0,
        pre_value
    } state;

    ctx = ngx_http_get_module_ctx(r, ngx_http_upstream_session_sticky_module);
    p = ngx_strlcasestrn(table->value.data,
                         table->value.data + table->value.len,
                         ctx->sscf->cookie.data,
                         ctx->sscf->cookie.len - 1);
    if (p == NULL) {
        return NGX_AGAIN;
    }

    last = table->value.data + table->value.len;
    state = 0;
    p += ctx->sscf->cookie.len;
    while (p < last) {
        switch (state) {
        case pre_equal:
            if (*p == '=') {
                state = pre_value;
            }
            break;

        case pre_value:
            if (*p == ';') {
                goto success;
            } else if (!is_space(*p)) {
                goto success;
            }
            break;

        default:
            break;
        }

        p++;
    }

    return NGX_AGAIN;

success:

    table->value.len += ctx->sid.len + 1;
    s = ngx_pnalloc(r->pool, table->value.len);
    if (s == NULL) {
        return NGX_ERROR;
    }

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
    u_char             *p, *st, *en, *last, *start;
    ngx_http_ss_ctx_t  *ctx;
    enum {
        pre_equal = 0,
        pre_value,
        value
    } state;

    ctx = ngx_http_get_module_ctx(r, ngx_http_upstream_session_sticky_module);
    p = ngx_strlcasestrn(table->value.data,
                         table->value.data + table->value.len,
                         ctx->sscf->cookie.data,
                         ctx->sscf->cookie.len - 1);
    if (p == NULL) {
        return NGX_AGAIN;
    }

    st = p;
    start = table->value.data;
    last = table->value.data + table->value.len;

    state = 0;
    while (p < last) {
        switch (state) {
        case pre_equal:
            if (*p == '=') {
                state = pre_value;

            } else if (*p == ';') {
                goto success;
            }

            break;

        case pre_value:
            if (!is_space(*p)) {
                state = value;
                p--;
            }
            break;

        case value:
            if (*p == ';') {
                goto success;
            }
            break;

        default:
            break;
        }

        p++;
    }

    if (p >= last && (state == value || state == pre_equal)) {
        goto success;
    }

    return NGX_AGAIN;

success:

    en = p;
    table->value.len = table->value.len
                     - (en - st)
                     + ctx->sscf->cookie.len
                     + 1 /* '=' */
                     + ctx->sid.len;

    p = ngx_pnalloc(r->pool, table->value.len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    table->value.data = p;
    p = ngx_cpymem(p, start, st - start);
    p = ngx_cpymem(p, ctx->sscf->cookie.data, ctx->sscf->cookie.len);
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

    ctx = ngx_http_get_module_ctx(r, ngx_http_upstream_session_sticky_module);
    if (ctx->frist != 1 && ctx->sscf->maxidle == NGX_CONF_UNSET) {
        return NGX_OK;
    }

    set_cookie = NULL;
    if (ctx->sscf->flag & NGX_HTTP_SESSION_STICKY_INDIRECT) {
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
                                         ctx->sscf->cookie.data,
                                         ctx->sscf->cookie.len - 1);
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

    set_cookie->value.len = ctx->sscf->cookie.len
                          + sizeof("=") - 1
                          + ctx->sid.len
                          + sizeof("; Domain=") - 1
                          + ctx->sscf->domain.len
                          + sizeof("; Path=") - 1
                          + ctx->sscf->path.len;

    if (ctx->sscf->maxidle != NGX_CONF_UNSET) {
        set_cookie->value.len = set_cookie->value.len
                              + ctx->s_lastseen.len
                              + ctx->s_firstseen.len
                              + 2; /* '|' and '|' */
    } else {
        set_cookie->value.len = set_cookie->value.len
                              + sizeof("; Max-Age=") - 1
                              + ctx->sscf->maxage.len
                              + sizeof("; Expires=") - 1
                              + sizeof("Xxx, 00-Xxx-00 00:00:00 GMT") - 1;
    }

    p = ngx_pnalloc(r->pool, set_cookie->value.len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    set_cookie->value.data = p;

    p = ngx_cpymem(p, ctx->sscf->cookie.data, ctx->sscf->cookie.len);
    *p++ = '=';
    p = ngx_cpymem(p, ctx->sid.data, ctx->sid.len);
    if (ctx->sscf->maxidle != NGX_CONF_UNSET) {
        *(p++) = NGX_HTTP_SESSION_STICKY_DELIMITER;
        p = ngx_cpymem(p, ctx->s_lastseen.data, ctx->s_lastseen.len);
        *(p++) = NGX_HTTP_SESSION_STICKY_DELIMITER;
        p = ngx_cpymem(p, ctx->s_firstseen.data, ctx->s_firstseen.len);
    }
    if (ctx->sscf->domain.len) {
        p = ngx_cpymem(p, "; Domain=", sizeof("; Domain=") - 1);
        p = ngx_cpymem(p, ctx->sscf->domain.data, ctx->sscf->domain.len);
    }
    if (ctx->sscf->path.len) {
        p = ngx_cpymem(p, "; Path=", sizeof("; Path=") - 1);
        p = ngx_cpymem(p, ctx->sscf->path.data, ctx->sscf->path.len);
    }
    if (ctx->sscf->maxidle == NGX_CONF_UNSET && ctx->sscf->maxage.len) {
        p = ngx_cpymem(p, "; Max-Age=", sizeof("; Max-Age=") - 1);
        p = ngx_cpymem(p, ctx->sscf->maxage.data, ctx->sscf->maxage.len);
        p = ngx_cpymem(p, "; Expires=", sizeof("; Expires=") - 1);
        ngx_uint_t maxage = ngx_atoi(ctx->sscf->maxage.data,
                                      ctx->sscf->maxage.len);
        p = ngx_http_cookie_time(p, ngx_time() + maxage);
    }

    set_cookie->value.len = p - set_cookie->value.data;

    return NGX_OK;
}


static void *
ngx_http_upstream_session_sticky_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_upstream_ss_srv_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_upstream_ss_srv_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    conf->maxlife = NGX_CONF_UNSET;
    conf->maxidle = NGX_CONF_UNSET;

    conf->flag = NGX_HTTP_SESSION_STICKY_INSERT | NGX_HTTP_SESSION_STICKY_MD5;
    conf->cookie.data = (u_char *) "route";
    conf->cookie.len = sizeof("route") - 1;
    conf->path.data = (u_char *) "/";
    conf->path.len = 1;

    return conf;
}


static void *
ngx_http_session_sticky_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_ss_loc_conf_t  *conf;

    conf = ngx_palloc(cf->pool, sizeof(ngx_http_ss_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    conf->uscf = NGX_CONF_UNSET_PTR;
    return conf;
}


static char *
ngx_http_session_sticky_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child)
{
    ngx_http_ss_loc_conf_t  *prev = parent;
    ngx_http_ss_loc_conf_t  *conf = child;

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
    ngx_int_t                        rc;
    ngx_uint_t                       i;
    ngx_str_t                       *value;
    ngx_http_upstream_srv_conf_t    *uscf;
    ngx_http_upstream_ss_srv_conf_t *sscf = conf;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    uscf->peer.init_upstream = ngx_http_upstream_session_sticky_init_upstream;

    uscf->flags = NGX_HTTP_UPSTREAM_CREATE
                | NGX_HTTP_UPSTREAM_WEIGHT
                | NGX_HTTP_UPSTREAM_MAX_FAILS
                | NGX_HTTP_UPSTREAM_FAIL_TIMEOUT
                | NGX_HTTP_UPSTREAM_DOWN;

    value = cf->args->elts;
    for (i = 1; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data, "cookie=", 7) == 0){
            sscf->cookie.data = value[i].data + 7;
            sscf->cookie.len = value[i].len - 7;
            if (sscf->cookie.len == 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid cookie");
                return NGX_CONF_ERROR;
            }
            continue;
        }

        if (ngx_strncmp(value[i].data, "domain=", 7) == 0) {
            sscf->domain.data = value[i].data + 7;
            sscf->domain.len = value[i].len - 7;
            if (sscf->domain.len == 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid domain");
                return NGX_CONF_ERROR;
            }
            continue;
        }

        if (ngx_strncmp(value[i].data, "path=", 5) == 0) {
            sscf->path.data = value[i].data + 5;
            sscf->path.len = value[i].len - 5;
            if (sscf->path.len == 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid path");
                return NGX_CONF_ERROR;
            }
            continue;
        }

        if (ngx_strncmp(value[i].data, "maxage=", 7) == 0) {
            sscf->maxage.data = value[i].data + 7;
            sscf->maxage.len = value[i].len - 7;
            rc = ngx_atoi(sscf->maxage.data, sscf->maxage.len);
            if (rc == NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid maxage");
                return NGX_CONF_ERROR;
            }
            continue;
        }

        if (ngx_strncmp(value[i].data, "maxidle=", 8) == 0) {
            sscf->maxidle = ngx_atotm(value[i].data + 8, value[i].len - 8);
            if (sscf->maxidle <= NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid maxidle");
                return NGX_CONF_ERROR;
            }

            if (sscf->maxlife == NGX_CONF_UNSET) {
                sscf->maxlife = NGX_MAX_INT32_VALUE;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "maxlife=", 8) == 0) {
            sscf->maxlife = ngx_atotm(value[i].data + 8, value[i].len - 8);
            if (sscf->maxlife <= NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid maxlife");
                return NGX_CONF_ERROR;
            }

            if (sscf->maxidle == NGX_CONF_UNSET) {
                sscf->maxidle = NGX_MAX_INT32_VALUE;
            }
            continue;
        }

        if (ngx_strncmp(value[i].data, "mode=", 5) == 0) {
            value[i].data = value[i].data + 5;
            value[i].len = value[i].len - 5;

            if (ngx_strncmp(value[i].data, "insert", 6) == 0) {
                sscf->flag |= NGX_HTTP_SESSION_STICKY_INSERT;

            } else if (ngx_strncmp(value[i].data, "prefix", 6) == 0) {
                sscf->flag |= NGX_HTTP_SESSION_STICKY_PREFIX;
                sscf->flag &= (~NGX_HTTP_SESSION_STICKY_INSERT);

            } else if (ngx_strncmp(value[i].data, "rewrite", 7) == 0) {
                sscf->flag |= NGX_HTTP_SESSION_STICKY_REWRITE;
                sscf->flag &= (~NGX_HTTP_SESSION_STICKY_INDIRECT);
                sscf->flag &= (~NGX_HTTP_SESSION_STICKY_INSERT);

            } else {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid mode");
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "option=", 7) == 0) {
            value[i].data = value[i].data + 7;
            value[i].len = value[i].len - 7;

            if (ngx_strncmp(value[i].data, "indirect", 8) == 0) {
                sscf->flag |= NGX_HTTP_SESSION_STICKY_INDIRECT;

            } else if (ngx_strncmp(value[i].data, "direct", 6) == 0) {
                sscf->flag &= ~NGX_HTTP_SESSION_STICKY_INDIRECT;

            } else {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid option");
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "fallback=", 9) == 0) {
            value[i].data = value[i].data + 9;
            value[i].len = value[i].len - 9;

            if (ngx_strncmp(value[i].data, "on", 2) == 0) {
                sscf->flag |= NGX_HTTP_SESSION_STICKY_FALLBACK_ON;

            } else if (ngx_strncmp(value[i].data, "off", 3) == 0) {
                sscf->flag |= NGX_HTTP_SESSION_STICKY_FALLBACK_OFF;

            } else {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid fallback");
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "hash=", 5) == 0) {
            value[i].data = value[i].data + 5;
            value[i].len = value[i].len - 5;

            if (ngx_strncmp(value[i].data, "plain", 5) == 0) {
                sscf->flag = (sscf->flag & (~NGX_HTTP_SESSION_STICKY_MD5))
                           | NGX_HTTP_SESSION_STICKY_PLAIN;

            } else if (ngx_strncmp(value[i].data, "md5", 4) == 0) {
                sscf->flag = (sscf->flag & (~NGX_HTTP_SESSION_STICKY_PLAIN))
                           | NGX_HTTP_SESSION_STICKY_MD5;

            } else {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid hash mode");
                return NGX_CONF_ERROR;
            }

            continue;
        }

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid argument");
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_session_sticky_hide_cookie(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_http_ss_loc_conf_t  *slcf = conf;

    size_t      add;
    ngx_str_t  *value;
    ngx_url_t   u;

    value = (ngx_str_t *) cf->args->elts;
    if (ngx_strncmp(value[0].data, "session_sticky_header", 21) == 0) {
        ngx_conf_deprecated(cf,
                            &ngx_conf_deprecated_session_sticky_header, NULL);
    }

    if (ngx_strncmp(value[1].data, "upstream=", 9) == 0) {
        add = 9;
        ngx_memzero(&u, sizeof(ngx_url_t));

        u.url.len = value[1].len - add;
        u.url.data = value[1].data + add;
        u.uri_part = 1;
        u.no_resolve = 1;

        slcf->uscf = ngx_http_upstream_add(cf, &u, 0);
        if (slcf->uscf == NULL) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid upstream name");
            return NGX_CONF_ERROR;
        }
        return NGX_CONF_OK;
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid argument of \"%V\"",
                       &value[1]);
    return NGX_CONF_ERROR;
}


static ngx_int_t
ngx_http_upstream_session_sticky_init_upstream(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_uint_t                        number, i;
    ngx_http_upstream_rr_peer_t      *peer;
    ngx_http_upstream_rr_peers_t     *peers;
    ngx_http_upstream_ss_srv_conf_t  *sscf;

    if (ngx_http_upstream_init_round_robin(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    sscf = ngx_http_conf_upstream_srv_conf(us,
                                    ngx_http_upstream_session_sticky_module);
    if (sscf == NULL) {
        return NGX_ERROR;
    }

    peers = (ngx_http_upstream_rr_peers_t *) us->peer.data;
    number = peers->number;

    sscf->server = ngx_palloc(cf->pool, number * sizeof(ngx_http_ss_server_t));
    if (sscf->server == NULL) {
        return NGX_ERROR;
    }

    sscf->number = number;

    for (i = 0; i < number; i++) {
        peer = &peers->peer[i];

        sscf->server[i].name = &peer->name;
        sscf->server[i].sockaddr = peer->sockaddr;
        sscf->server[i].socklen = peer->socklen;

#if (NGX_HTTP_UPSTREAM_CHECK)
        sscf->server[i].check_index = peer->check_index;
#endif
        if (sscf->flag & NGX_HTTP_SESSION_STICKY_PLAIN) {
            if (peer->id.len == 0) {
                sscf->server[i].sid.data = peer->name.data;
                sscf->server[i].sid.len = peer->name.len;
                continue;
            }

            sscf->server[i].sid.data = peer->id.data;
            sscf->server[i].sid.len = peer->id.len;

        } else if (ngx_http_upstream_session_sticky_set_sid(
                                                cf, &sscf->server[i]) != NGX_OK)
        {
            return NGX_ERROR;
        }
    }

    us->peer.init = ngx_http_upstream_session_sticky_init_peer;

    return NGX_OK;
}


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


#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_upstream_session_sticky_set_peer_session(ngx_peer_connection_t *pc,
    void *data)
{
    ngx_http_upstream_ss_peer_data_t *sspd = data;

    ngx_int_t            rc;
    ngx_ssl_session_t   *ssl_session;

    ssl_session = sspd->ssl_session;
    rc = ngx_ssl_set_session(pc->connection, ssl_session);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "set session: %p:%d",
                   ssl_session, ssl_session ? ssl_session->references : 0);

    return rc;
}


static void
ngx_http_upstream_session_sticky_save_peer_session(ngx_peer_connection_t *pc,
    void *data)
{
    ngx_http_upstream_ss_peer_data_t *sspd = data;

    ngx_ssl_session_t   *old_ssl_session, *ssl_session;

    ssl_session = ngx_ssl_get_session(pc->connection);

    if (ssl_session == NULL) {
        return;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "save session: %p:%d", ssl_session, ssl_session->references);

    old_ssl_session = sspd->ssl_session;
    sspd->ssl_session = ssl_session;

    if (old_ssl_session) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "old session: %p:%d",
                       old_ssl_session, old_ssl_session->references);

        ngx_ssl_free_session(old_ssl_session);
    }
}

#endif
