
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#define NGX_HTTP_UPSTREAM_DR_INIT         0
#define NGX_HTTP_UPSTREAM_DR_OK           1
#define NGX_HTTP_UPSTREAM_DR_FAILED       2

#define NGX_HTTP_UPSTREAM_DYN_RESOLVE_NEXT 0
#define NGX_HTTP_UPSTREAM_DYN_RESOLVE_STALE 1
#define NGX_HTTP_UPSTREAM_DYN_RESOLVE_SHUTDOWN 2


typedef struct {
    ngx_int_t                         enabled;
    ngx_int_t                         fallback;
    time_t                            fail_timeout;
    time_t                            fail_check;

    ngx_http_upstream_init_pt         original_init_upstream;
    ngx_http_upstream_init_peer_pt    original_init_peer;

} ngx_http_upstream_dynamic_srv_conf_t;


typedef struct {
    ngx_http_upstream_dynamic_srv_conf_t  *conf;

    ngx_http_upstream_t               *upstream;

    void                              *data;

    ngx_http_request_t                *request;

    ngx_event_get_peer_pt              original_get_peer;
    ngx_event_free_peer_pt             original_free_peer;

#if (NGX_HTTP_SSL)
    ngx_event_set_peer_session_pt      original_set_session;
    ngx_event_save_peer_session_pt     original_save_session;
#endif

} ngx_http_upstream_dynamic_peer_data_t;


static ngx_int_t ngx_http_upstream_init_dynamic_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_dynamic_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_free_dynamic_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);


#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_upstream_dynamic_set_session(
    ngx_peer_connection_t *pc, void *data);
static void ngx_http_upstream_dynamic_save_session(ngx_peer_connection_t *pc,
    void *data);
#endif

static void *ngx_http_upstream_dynamic_create_conf(ngx_conf_t *cf);
static char *ngx_http_upstream_dynamic(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

extern void ngx_http_upstream_finalize_request(ngx_http_request_t *r,
    ngx_http_upstream_t *u, ngx_int_t rc);
extern void ngx_http_upstream_connect(ngx_http_request_t *r,
    ngx_http_upstream_t *u);



static ngx_command_t  ngx_http_upstream_dynamic_commands[] = {

    { ngx_string("dynamic_resolve"),
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE12|NGX_CONF_NOARGS,
      ngx_http_upstream_dynamic,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_upstream_dynamic_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    ngx_http_upstream_dynamic_create_conf, /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};


ngx_module_t  ngx_http_upstream_dynamic_module = {
    NGX_MODULE_V1,
    &ngx_http_upstream_dynamic_module_ctx, /* module context */
    ngx_http_upstream_dynamic_commands,    /* module directives */
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
ngx_http_upstream_init_dynamic(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_uint_t                             i;
    ngx_http_upstream_dynamic_srv_conf_t  *dcf;
    ngx_http_upstream_server_t            *server;
    ngx_str_t                              host;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
                   "init dynamic resolve");

    dcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_dynamic_module);

    if (dcf->original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    if (us->servers) {
        server = us->servers->elts;

        for (i = 0; i < us->servers->nelts; i++) {
            host = server[i].host;
            if (ngx_inet_addr(host.data, host.len) == INADDR_NONE) {
                break;
            }
        }

        if (i == us->servers->nelts) {
            dcf->enabled = 0;

            return NGX_OK;
        }
    }

    dcf->original_init_peer = us->peer.init;

    us->peer.init = ngx_http_upstream_init_dynamic_peer;

    dcf->enabled = 1;

    return NGX_OK;
}


static ngx_int_t
ngx_http_upstream_init_dynamic_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_upstream_dynamic_peer_data_t  *dp;
    ngx_http_upstream_dynamic_srv_conf_t   *dcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "init dynamic peer");

    dcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_dynamic_module);

    dp = ngx_palloc(r->pool, sizeof(ngx_http_upstream_dynamic_peer_data_t));
    if (dp == NULL) {
        return NGX_ERROR;
    }

    if (dcf->original_init_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    dp->conf = dcf;
    dp->upstream = r->upstream;
    dp->data = r->upstream->peer.data;
    dp->original_get_peer = r->upstream->peer.get;
    dp->original_free_peer = r->upstream->peer.free;
    dp->request = r;

    r->upstream->peer.data = dp;
    r->upstream->peer.get = ngx_http_upstream_get_dynamic_peer;
    r->upstream->peer.free = ngx_http_upstream_free_dynamic_peer;

#if (NGX_HTTP_SSL)
    dp->original_set_session = r->upstream->peer.set_session;
    dp->original_save_session = r->upstream->peer.save_session;
    r->upstream->peer.set_session = ngx_http_upstream_dynamic_set_session;
    r->upstream->peer.save_session = ngx_http_upstream_dynamic_save_session;
#endif

    return NGX_OK;
}


static void
ngx_http_upstream_dynamic_handler(ngx_resolver_ctx_t *ctx)
{
    ngx_http_request_t                    *r;
    ngx_http_upstream_t                   *u;
    ngx_peer_connection_t                 *pc;
#if defined(nginx_version) && nginx_version >= 1005008
    socklen_t                              socklen;
    struct sockaddr                       *sockaddr, *csockaddr;
#else
    struct sockaddr_in                    *sin, *csin;
#endif
    in_port_t                              port;
    ngx_str_t                             *addr;
    u_char                                *p;

    size_t                                 len;
    ngx_http_upstream_dynamic_srv_conf_t  *dscf;
    ngx_http_upstream_dynamic_peer_data_t *bp;

    bp = ctx->data;
    r = bp->request;
    u = r->upstream;
    pc = &u->peer;
    dscf = bp->conf;

    if (ctx->state) {

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "%V could not be resolved (%i: %s)",
                      &ctx->name, ctx->state,
                      ngx_resolver_strerror(ctx->state));

        dscf->fail_check = ngx_time();

        pc->resolved = NGX_HTTP_UPSTREAM_DR_FAILED;

    } else {
        /* dns query ok */
#if (NGX_DEBUG)
        {
        u_char      text[NGX_SOCKADDR_STRLEN];
        ngx_str_t   addr;
        ngx_uint_t  i;

        addr.data = text;

        for (i = 0; i < ctx->naddrs; i++) {
            addr.len = ngx_sock_ntop(ctx->addrs[i].sockaddr, ctx->addrs[i].socklen,
                                     text, NGX_SOCKADDR_STRLEN, 0);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "name was resolved to %V", &addr);
        }
        }
#endif
        dscf->fail_check = 0;
#if defined(nginx_version) && nginx_version >= 1005008
        csockaddr = ctx->addrs[0].sockaddr;
        socklen = ctx->addrs[0].socklen;

        if (ngx_cmp_sockaddr(pc->sockaddr, pc->socklen, csockaddr, socklen, 0)
            == NGX_OK)
        {
            pc->resolved = NGX_HTTP_UPSTREAM_DR_OK;
            goto out;
        }

        sockaddr = ngx_pcalloc(r->pool, socklen);
        if (sockaddr == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        ngx_memcpy(sockaddr, csockaddr, socklen);
        port = ngx_inet_get_port(pc->sockaddr);
        
        switch (sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
        case AF_INET6:
            ((struct sockaddr_in6 *) sockaddr)->sin6_port = htons(port);
            break;
#endif
        default: /* AF_INET */
            ((struct sockaddr_in *) sockaddr)->sin_port = htons(port);
        }

        p = ngx_pnalloc(r->pool, NGX_SOCKADDR_STRLEN);
        if (p == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        len = ngx_sock_ntop(sockaddr, socklen, p, NGX_SOCKADDR_STRLEN, 1);

        addr = ngx_palloc(r->pool, sizeof(ngx_str_t));
        if (addr == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        addr->data = p;
        addr->len = len;
        pc->sockaddr = sockaddr;
        pc->socklen = socklen;
        pc->name = addr;

#else
        /* for nginx older than 1.5.8 */

        sin = ngx_pcalloc(r->pool, sizeof(struct sockaddr_in));
        if (sin == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        ngx_memcpy(sin, pc->sockaddr, pc->socklen);

        /* only the first IP addr is used in version 1 */

        csin = (struct sockaddr_in *) ctx->addrs[0].sockaddr;
        if (sin->sin_addr.s_addr == csin->sin_addr.s_addr) {

            pc->resolved = NGX_HTTP_UPSTREAM_DR_OK;

            goto out;
        }

        sin->sin_addr.s_addr = csin->sin_addr.s_addr;

        len = NGX_INET_ADDRSTRLEN + sizeof(":65535") - 1;

        p = ngx_pnalloc(r->pool, len);
        if (p == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        port = ntohs(sin->sin_port);
        len = ngx_inet_ntop(AF_INET, &sin->sin_addr.s_addr,
                            p, NGX_INET_ADDRSTRLEN);
        len = ngx_sprintf(&p[len], ":%d", port) - p;

        addr = ngx_palloc(r->pool, sizeof(ngx_str_t));
        if (addr == NULL) {
            ngx_http_upstream_finalize_request(r, u,
                                               NGX_HTTP_INTERNAL_SERVER_ERROR);
            return;
        }

        addr->data = p;
        addr->len = len;

        pc->sockaddr = (struct sockaddr *) sin;
        pc->socklen = sizeof(struct sockaddr_in);
        pc->name = addr;
#endif

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "name was resolved to %V", pc->name);

        pc->resolved = NGX_HTTP_UPSTREAM_DR_OK;
    }

out:
    ngx_resolve_name_done(ctx);
    u->dyn_resolve_ctx = NULL;

    ngx_http_upstream_connect(r, u);
}


static ngx_int_t
ngx_http_upstream_get_dynamic_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_dynamic_peer_data_t  *bp = data;
    ngx_http_request_t                     *r;
    ngx_http_core_loc_conf_t               *clcf;
    ngx_resolver_ctx_t                     *ctx, temp;
    ngx_http_upstream_t                    *u;
    ngx_int_t                               rc;
    ngx_http_upstream_dynamic_srv_conf_t   *dscf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "get dynamic peer");

    /* The "get" function will be called twice if
     * one host is resolved into an IP address.
     * (via 'ngx_http_upstream_connect' if resolved successfully)
     *
     * So here we need to determine if it is the first
     * time call or the second time call.
     */
    if (pc->resolved == NGX_HTTP_UPSTREAM_DR_OK) {
        return NGX_OK;
    }

    dscf = bp->conf;
    r = bp->request;
    u = r->upstream;

    if (pc->resolved == NGX_HTTP_UPSTREAM_DR_FAILED) {

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "resolve failed! fallback: %ui", dscf->fallback);

        switch (dscf->fallback) {

        case NGX_HTTP_UPSTREAM_DYN_RESOLVE_STALE:
            return NGX_OK;

        case NGX_HTTP_UPSTREAM_DYN_RESOLVE_SHUTDOWN:
            ngx_http_upstream_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
            return NGX_YIELD;

        default:
            /* default fallback action: check next upstream */
            return NGX_DECLINED;
        }

        return NGX_DECLINED;
    }

    if (dscf->fail_check
        && (ngx_time() - dscf->fail_check < dscf->fail_timeout))
    {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "in fail timeout period, fallback: %ui", dscf->fallback);

        switch (dscf->fallback) {

        case NGX_HTTP_UPSTREAM_DYN_RESOLVE_STALE:
            return bp->original_get_peer(pc, bp->data);

        case NGX_HTTP_UPSTREAM_DYN_RESOLVE_SHUTDOWN:
            ngx_http_upstream_finalize_request(r, u, NGX_HTTP_BAD_GATEWAY);
            return NGX_YIELD;

        default:
            /* default fallback action: check next upstream, still need
             * to get peer in fail timeout period
             */
            return bp->original_get_peer(pc, bp->data);
        }

        return NGX_DECLINED;
    }

    /* NGX_HTTP_UPSTREAM_DYN_RESOLVE_INIT,  ask balancer */

    rc = bp->original_get_peer(pc, bp->data);

    if (rc != NGX_OK) {
        return rc;
    }

    /* resolve name */

    if (pc->host == NULL) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "load balancer doesn't support dyn resolve!");
        return NGX_OK;
    }

    if (ngx_inet_addr(pc->host->data, pc->host->len) != INADDR_NONE) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                       "host is an IP address, connect directly!");
        return NGX_OK;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    if (clcf->resolver == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "resolver has not been configured!");
        return NGX_OK;
    }

    temp.name = *pc->host;

    ctx = ngx_resolve_start(clcf->resolver, &temp);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "resolver start failed!");
        return NGX_OK;
    }

    if (ctx == NGX_NO_RESOLVER) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "resolver started but no resolver!");
        return NGX_OK;
    }

    ctx->name = *pc->host;
    /* TODO remove */
    // ctx->type = NGX_RESOLVE_A;
    /* END */
    ctx->handler = ngx_http_upstream_dynamic_handler;
    ctx->data = bp;
    ctx->timeout = clcf->resolver_timeout;

    u->dyn_resolve_ctx = ctx;

    if (ngx_resolve_name(ctx) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0,
                      "resolver name failed!\n");

        u->dyn_resolve_ctx = NULL;

        return NGX_OK;
    }

    return NGX_YIELD;
}


static void
ngx_http_upstream_free_dynamic_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_http_upstream_dynamic_peer_data_t  *bp = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "free dynamic peer");

    bp->original_free_peer(pc, bp->data, state);
}


#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_upstream_dynamic_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_dynamic_peer_data_t  *dp = data;

    return dp->original_set_session(pc, dp->data);
}


static void
ngx_http_upstream_dynamic_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_dynamic_peer_data_t  *dp = data;

    dp->original_save_session(pc, dp->data);

    return;
}

#endif


static void *
ngx_http_upstream_dynamic_create_conf(ngx_conf_t *cf)
{
    ngx_http_upstream_dynamic_srv_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool,
                       sizeof(ngx_http_upstream_dynamic_srv_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->original_init_upstream = NULL;
     *     conf->original_init_peer = NULL;
     */

    return conf;
}


static char *
ngx_http_upstream_dynamic(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_upstream_srv_conf_t            *uscf;
    ngx_http_upstream_dynamic_srv_conf_t    *dcf;
    ngx_str_t   *value, s;
    ngx_uint_t   i;
    time_t       fail_timeout;
    ngx_int_t    fallback;

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    dcf = ngx_http_conf_upstream_srv_conf(uscf,
                                          ngx_http_upstream_dynamic_module);

    if (dcf->original_init_upstream) {
        return "is duplicate";
    }

    dcf->original_init_upstream = uscf->peer.init_upstream
                                  ? uscf->peer.init_upstream
                                  : ngx_http_upstream_init_round_robin;

    uscf->peer.init_upstream = ngx_http_upstream_init_dynamic;

    /* read options */

    value = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {

        if (ngx_strncmp(value[i].data, "fail_timeout=", 13) == 0) {

            s.len = value[i].len - 13;
            s.data = &value[i].data[13];

            fail_timeout = ngx_parse_time(&s, 1);

            if (fail_timeout == (time_t) NGX_ERROR) {
                return "invalid fail_timeout";
            }

            dcf->fail_timeout = fail_timeout;

            continue;
        }

        if (ngx_strncmp(value[i].data, "fallback=", 9) == 0) {

            s.len = value[i].len - 9;
            s.data = &value[i].data[9];

            if (ngx_strncmp(s.data, "next", 4) == 0) {
                fallback = NGX_HTTP_UPSTREAM_DYN_RESOLVE_NEXT;
            } else if (ngx_strncmp(s.data, "stale", 5) == 0) {
                fallback = NGX_HTTP_UPSTREAM_DYN_RESOLVE_STALE;
            } else if (ngx_strncmp(s.data, "shutdown", 8) == 0) {
                fallback = NGX_HTTP_UPSTREAM_DYN_RESOLVE_SHUTDOWN;
            } else {
                return "invalid fallback action";
            }

            dcf->fallback = fallback;

            continue;
        }
    }

    return NGX_CONF_OK;
}
