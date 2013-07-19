/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_config.h>
#include <ngx_crc32.h>
#include <ngx_http.h>
#if (NGX_LIMIT_TCP_WITH_MAIL)
#include <ngx_mail.h>
#endif


typedef struct ngx_limit_tcp_conf_s ngx_limit_tcp_conf_t;
typedef struct ngx_limit_tcp_addr_s ngx_limit_tcp_addr_t;
typedef struct ngx_limit_tcp_ctx_s ngx_limit_tcp_ctx_t;


typedef struct {
    ngx_limit_tcp_addr_t       **addrs;
} ngx_limit_tcp_listen_ctx_t;


typedef struct {
    /* ngx_mail_in_addr_t or ngx_mail_in6_addr_t */
    /* ngx_http_in_addr_t or ngx_http_in6_addr_t */
    void                        *addrs;
    ngx_uint_t                   naddrs;
} ngx_limit_tcp_port_t;


typedef struct {
    in_addr_t                    mask;
    in_addr_t                    addr;
    ngx_uint_t                   deny;      /* unsigned  deny:1; */
} ngx_limit_tcp_rule_t;

#if (NGX_HAVE_INET6)

typedef struct {
    struct in6_addr              addr;
    struct in6_addr              mask;
    ngx_uint_t                   deny;      /* unsigned  deny:1; */
} ngx_limit_tcp_rule6_t;

#endif

typedef struct {
    ngx_connection_t            *connection;
    void                        *rdata;
    void                        *wdata;
    ngx_event_handler_pt         rhandler;
    ngx_event_handler_pt         whandler;
    ngx_connection_handler_pt    handler;
} ngx_limit_tcp_delay_ctx_t;


typedef struct {
    ngx_connection_t            *connection;
    ngx_limit_tcp_listen_ctx_t  *lctx;
} ngx_limit_tcp_accept_ctx_t;


typedef struct {
    u_char                       color;
    u_char                       dummy;
    u_short                      len;
    ngx_queue_t                  queue;
    ngx_msec_t                   last;
    /* integer value, 1 corresponds to 0.001 r/s */
    ngx_uint_t                   count;
    ngx_uint_t                   excess;
    u_char                       data[1];
} ngx_limit_tcp_node_t;


typedef struct {
    ngx_connection_t            *connection;
    ngx_limit_tcp_node_t        *node;
} ngx_limit_tcp_clean_ctx_t;


typedef struct {
    ngx_rbtree_t                 rbtree;
    ngx_rbtree_node_t            sentinel;
    ngx_queue_t                  queue;
} ngx_limit_tcp_shctx_t;


struct ngx_limit_tcp_ctx_s {
    ngx_uint_t                   rate;
    ngx_uint_t                   burst;
    ngx_uint_t                   nodelay;
    ngx_uint_t                   concurrent;
    ngx_uint_t                   shm_size;
    ngx_slab_pool_t             *shpool;
    ngx_limit_tcp_shctx_t       *sh;
};


struct ngx_limit_tcp_addr_s {
    struct sockaddr              sockaddr;
    socklen_t                    socklen;    /* size of sockaddr */
    ngx_str_t                    addr_text;
    ngx_limit_tcp_ctx_t         *ctx;
};


struct ngx_limit_tcp_conf_s {
    ngx_flag_t                   enable;
    ngx_array_t                  lsocks;    /* ngx_limit_tcp_addr_t* */
    ngx_array_t                 *rules;     /* array of ngx_limit_tcp_rule_t */
#if (NGX_HAVE_INET6)
    ngx_array_t                 *rules6;    /* array of ngx_limit_tcp_rule6_t */
#endif
};


static char *ngx_conf_limit_tcp(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_limit_tcp_rule(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static void *ngx_limit_tcp_create_conf(ngx_cycle_t *cycle);
static ngx_int_t ngx_limit_tcp_init_zone(ngx_shm_zone_t *shm_zone,
    void *data);
static ngx_int_t ngx_limit_tcp_init_module(ngx_cycle_t *cycle);
static ngx_int_t ngx_limit_tcp_init_process(ngx_cycle_t *cycle);
static void ngx_limit_tcp_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel);
static ngx_int_t ngx_limit_tcp_lookup(ngx_connection_t *c,
    ngx_limit_tcp_ctx_t *ctx, ngx_uint_t *ep, ngx_limit_tcp_node_t **node);
static void ngx_limit_tcp_expire(ngx_connection_t *c, ngx_limit_tcp_ctx_t *ctx,
    ngx_uint_t n);
static void ngx_limit_tcp_test_reading(ngx_event_t *ev);
static void ngx_limit_tcp_delay(ngx_event_t *ev);
static void ngx_limit_tcp_cleanup(void *data);
static ngx_int_t ngx_limit_tcp_find(ngx_connection_t *c);
static ngx_int_t ngx_limit_tcp_inet(ngx_connection_t *c,
    ngx_limit_tcp_conf_t *ltcf, in_addr_t addr);
#if (NGX_HAVE_INET6)
static ngx_int_t ngx_limit_tcp_inet6(ngx_connection_t *c,
    ngx_limit_tcp_conf_t *ltcf, u_char *p);
#endif
static ngx_int_t ngx_limit_tcp_get_addr_index(ngx_listening_t *ls,
    struct sockaddr *addr, ngx_flag_t type);
#if (NGX_LIMIT_TCP_WITH_MAIL)
static ngx_int_t ngx_limit_tcp_mail_get_addr_index(ngx_listening_t *ls,
    struct sockaddr *addr, ngx_flag_t type);
#endif
static ngx_int_t ngx_limit_tcp_http_get_addr_index(ngx_listening_t *ls,
    struct sockaddr *addr, ngx_flag_t type);
static void ngx_limit_tcp_accepted(ngx_event_t *ev);
static ngx_int_t ngx_event_limit_accept_filter(ngx_connection_t *c);


static ngx_core_module_t ngx_limit_tcp_ctx = {
    ngx_string("limit_tcp"),
    ngx_limit_tcp_create_conf,
    NULL
};


static ngx_command_t ngx_limit_tcp_commands[] = {

    { ngx_string("limit_tcp"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_2MORE,
      ngx_conf_limit_tcp,
      0,
      0,
      NULL },

    { ngx_string("limit_tcp_allow"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE1,
      ngx_limit_tcp_rule,
      0,
      0,
      NULL },

    { ngx_string("limit_tcp_deny"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE1,
      ngx_limit_tcp_rule,
      0,
      0,
      NULL },

      ngx_null_command
};


ngx_module_t ngx_limit_tcp_module = {
    NGX_MODULE_V1,
    &ngx_limit_tcp_ctx,                    /* module context */
    ngx_limit_tcp_commands,                /* module directives */
    NGX_CORE_MODULE,                       /* module type */
    NULL,                                  /* init master */
    ngx_limit_tcp_init_module,             /* init module */
    ngx_limit_tcp_init_process,            /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_event_accept_filter_pt ngx_event_next_accept_filter;


static void *
ngx_limit_tcp_create_conf(ngx_cycle_t *cycle)
{
    ngx_limit_tcp_conf_t  *conf;

    conf = ngx_pcalloc(cycle->pool, sizeof(ngx_limit_tcp_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    if (ngx_array_init(&conf->lsocks, cycle->pool, 4,
                       sizeof(ngx_limit_tcp_addr_t *))
        != NGX_OK)
    {
        return NULL;
    }

    return conf;
}


static ngx_int_t
ngx_limit_tcp_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    size_t                len;
    ngx_limit_tcp_ctx_t  *ctx, *octx;

    ctx = shm_zone->data;
    octx = data;

    if (octx) {
        ctx->shpool = octx->shpool;
        ctx->sh = octx->sh;
        return NGX_OK;
    }

    ctx->shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;
    if (shm_zone->shm.exists) {
        ctx->sh = ctx->shpool->data;
    }

    /* init sh */
    ctx->sh = ngx_slab_alloc(ctx->shpool, sizeof(ngx_limit_tcp_shctx_t));
    if (ctx->sh == NULL) {
        return NGX_ERROR;
    }

    ctx->shpool->data = ctx->sh;

    ngx_rbtree_init(&ctx->sh->rbtree, &ctx->sh->sentinel,
                    ngx_limit_tcp_rbtree_insert_value);

    ngx_queue_init(&ctx->sh->queue);

    len = sizeof(" in limit_tcp zone \"\"") + shm_zone->shm.name.len;

    ctx->shpool->log_ctx = ngx_slab_alloc(ctx->shpool, len);
    if (ctx->shpool->log_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_sprintf(ctx->shpool->log_ctx, " in limit_req zone \"%V\"%Z",
                &shm_zone->shm.name);

    return NGX_OK;
}


static char *
ngx_conf_limit_tcp(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_limit_tcp_conf_t  *ltcf = conf;

    u_char                *p;
    size_t                 len;
    ssize_t                size;
    ngx_int_t              burst, rate, scale, concurrent;
    ngx_str_t             *value, s, name;
    ngx_url_t              u;
    ngx_uint_t             i, j, nodelay;
    ngx_array_t           *ls;
    ngx_shm_zone_t        *shm_zone;
    ngx_limit_tcp_ctx_t   *ctx;
    ngx_limit_tcp_addr_t  *addr, **paddr, **taddr;

    burst = 0;
    nodelay = 0;
    concurrent = 0;
    rate = 0;
    scale = 1;
    size = 1024 * 1024 * 2;

    ngx_str_set(&name, "limit_tcp_shm");

    ls = ngx_array_create(cf->pool, 1, sizeof(ngx_limit_tcp_addr_t));

    if (ls == NULL) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data, "name=", 5) == 0) {

            name.data = value[i].data + 5;

            p = (u_char *) ngx_strchr(name.data, ':');

            if (p) {
                *p = '\0';

                name.len = p - name.data;

                p++;

                s.len = value[i].data + value[i].len - p;
                s.data = p;

                size = ngx_parse_size(&s);
                if (size > 8191) {
                    continue;
                }
            }

            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid size \"%V\"", &value[i]);
            return NGX_CONF_ERROR;

        } else if (ngx_strncmp(value[i].data, "rate=", 5) == 0) {

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
            if (rate <= NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid rate \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

        } else if (ngx_strncmp(value[i].data, "burst=", 6) == 0) {

            burst = ngx_atoi(value[i].data + 6, value[i].len - 6);
            if (burst <= 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid burst rate \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

            continue;

        } else if (ngx_strncmp(value[i].data, "concurrent=", 11) == 0) {

            concurrent = ngx_atoi(value[i].data + 11, value[i].len - 11);
            if (concurrent <= 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid concurrent \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

            continue;

        } else if (ngx_strncmp(value[i].data, "nodelay", 7) == 0) {

            nodelay = 1;
            continue;

        } else {

            /* ip:port */
            ngx_memzero(&u, sizeof(ngx_url_t));

            u.url = value[i];
            u.listen = 1;
            u.default_port = 80;
            if (ngx_parse_url(cf->pool, &u) != NGX_OK) {
                if (u.err) {
                    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                       "%s in \"%V\" of the \"limit_tcp\""
                                       " directive", u.err, &u.url);
                }

                return NGX_CONF_ERROR;
            }

            addr = ngx_array_push(ls);
            if (addr == NULL) {
                return NGX_CONF_ERROR;
            }

            ngx_memzero(addr, sizeof(ngx_limit_tcp_addr_t));
            ngx_memcpy(&addr->sockaddr, u.sockaddr, u.socklen);
            addr->socklen = u.socklen;
            addr->addr_text = u.url;
        }
    }

    shm_zone = ngx_shared_memory_add(cf, &name, size, &ngx_limit_tcp_module);
    if (shm_zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (shm_zone->data) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "\"%V\" is already bound",
                            &name);
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_limit_tcp_ctx_t));

    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->nodelay = nodelay;
    ctx->concurrent = concurrent;
    ctx->rate = rate * 1000 / scale;
    ctx->burst = burst * 1000;
    ctx->shm_size = size;

    shm_zone->init = ngx_limit_tcp_init_zone;
    shm_zone->data = ctx;

    paddr = ltcf->lsocks.elts;
    addr = ls->elts;

    for (i = 0; i < ls->nelts; i++) {
        for (j = 0; j < ltcf->lsocks.nelts; j++) {

            if (addr[i].addr_text.len != paddr[j]->addr_text.len) {
                continue;
            }

            if (ngx_strncmp(addr[i].addr_text.data, paddr[j]->addr_text.data,
                            addr[i].addr_text.len)
                != 0)
            {
                continue;
            }

            break;
        }

        if (j != ltcf->lsocks.nelts) {
            continue;
        }

        taddr = ngx_array_push(&ltcf->lsocks);
        if (taddr == NULL) {
            return NGX_CONF_ERROR;
        }

        addr[i].ctx = ctx;
        *taddr = &addr[i];
    }

    ltcf->enable = 1;

    return NGX_CONF_OK;
}


static char *
ngx_limit_tcp_rule(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_limit_tcp_conf_t     *ltcf = conf;

    ngx_int_t               rc;
    ngx_uint_t              all;
    ngx_str_t              *value;
    ngx_cidr_t              cidr;
    ngx_limit_tcp_rule_t   *rule;
#if (NGX_HAVE_INET6)
    ngx_limit_tcp_rule6_t  *rule6;
#endif

    ngx_memzero(&cidr, sizeof(ngx_cidr_t));

    value = cf->args->elts;

    all = (value[1].len == 3 && ngx_strcmp(value[1].data, "all") == 0);

    if (!all) {

        rc = ngx_ptocidr(&value[1], &cidr);

        if (rc == NGX_ERROR) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                         "invalid parameter \"%V\"", &value[1]);
            return NGX_CONF_ERROR;
        }

        if (rc == NGX_DONE) {
            ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                         "low address bits of %V are meaningless", &value[1]);
        }
    }

    switch (cidr.family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:
    case 0: /* all */

        if (ltcf->rules6 == NULL) {
            ltcf->rules6 = ngx_array_create(cf->pool, 4,
                                            sizeof(ngx_limit_tcp_rule6_t));
            if (ltcf->rules6 == NULL) {
                return NGX_CONF_ERROR;
            }
        }

        rule6 = ngx_array_push(ltcf->rules6);
        if (rule6 == NULL) {
            return NGX_CONF_ERROR;
        }

        rule6->mask = cidr.u.in6.mask;
        rule6->addr = cidr.u.in6.addr;
        rule6->deny = (value[0].data[10] == 'd') ? 1 : 0;

        if (!all) {
            break;
        }

        /* "all" passes through */
#endif

    default: /* AF_INET */

        if (ltcf->rules == NULL) {
            ltcf->rules = ngx_array_create(cf->pool, 4,
                                           sizeof(ngx_limit_tcp_rule_t));
            if (ltcf->rules == NULL) {
                return NGX_CONF_ERROR;
            }
        }

        rule = ngx_array_push(ltcf->rules);
        if (rule == NULL) {
            return NGX_CONF_ERROR;
        }

        rule->mask = cidr.u.in.mask;
        rule->addr = cidr.u.in.addr;
        rule->deny = (value[0].data[10] == 'd') ? 1 : 0;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_limit_tcp_get_addr_index(ngx_listening_t *ls, struct sockaddr *addr,
    ngx_flag_t type)
{
#if (NGX_LIMIT_TCP_WITH_MAIL)

    return ls->handler == ngx_mail_init_connection ?
        ngx_limit_tcp_mail_get_addr_index(ls, addr, type) :
        ngx_limit_tcp_http_get_addr_index(ls, addr, type);
#else
    return ngx_limit_tcp_http_get_addr_index(ls, addr, type);
#endif
}


#if (NGX_LIMIT_TCP_WITH_MAIL)
static ngx_int_t
ngx_limit_tcp_mail_get_addr_index(ngx_listening_t *ls, struct sockaddr *addr,
    ngx_flag_t type)
{
    ngx_uint_t            i;
    ngx_mail_port_t      *port;
    struct sockaddr_in   *sin, *lsin;
    ngx_mail_in_addr_t   *maddr;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6  *sin6, *lsin6;
    ngx_mail_in6_addr_t  *maddr6;
#endif

    switch (ls->sockaddr->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:

        sin6 = (struct sockaddr_in6 *) addr;
        maddr6 = port->addrs;

        if (type) {
            lsin6 = (struct sockaddr_in6 *) ls->sockaddr;
            if (ngx_memcmp(&lsin6->sin6_port, &sin6->sin6_port,
                           sizeof(in_port_t))
                != 0)
            {
                return NGX_ERROR;
            }
        }

        if (port->naddrs > 1) {
            for (i = 0; i < port->naddrs; i++) {
                if (ngx_memcmp(&maddr6[i].addr6, &sin6->sin6_addr, 16) == 0) {
                    return i;
                }
            }
        } else {
            return 0;
        }

        break;
#endif

    default:
        sin = (struct sockaddr_in *) addr;
        maddr = port->addrs;

        if (type) {
            lsin = (struct sockaddr_in *) ls->sockaddr;
            if (lsin->sin_port != sin->sin_port) {
                return NGX_ERROR;
            }
        }

        if (port->naddrs > 1) {

            for (i = 0; i < port->naddrs; i++) {
                if (maddr[i].addr == sin->sin_addr.s_addr) {
                    return i;
                }
            }
        } else {
            return 0;
        }

        break;

    }

    return NGX_ERROR;
}
#endif

static ngx_int_t
ngx_limit_tcp_http_get_addr_index(ngx_listening_t *ls, struct sockaddr *addr,
    ngx_flag_t type)
{
    ngx_uint_t            i;
    ngx_http_port_t      *port;
    struct sockaddr_in   *sin, *lsin;
    ngx_http_in_addr_t   *haddr;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6  *sin6, *lsin6;
    ngx_http_in6_addr_t  *haddr6;
#endif

    port = ls->servers;

    ngx_log_debug2(NGX_LOG_DEBUG_CORE, ngx_cycle->log, 0,
                   "listen: %V port num: %ui", &ls->addr_text, port->naddrs);

    switch (ls->sockaddr->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:

        sin6 = (struct sockaddr_in6 *) addr;
        haddr6 = port->addrs;

        if (type) {
            lsin6 = (struct sockaddr_in6 *) ls->sockaddr;
            if (ngx_memcmp(&lsin6->sin6_port, &sin6->sin6_port,
                           sizeof(in_port_t))
                != 0)
            {
                return NGX_ERROR;
            }
        }

        if (port->naddrs > 1) {

            for (i = 0; i < port->naddrs; i++) {
                if (ngx_memcmp(&haddr6[i].addr6, &sin6->sin6_addr, 16) == 0) {
                    return i;
                }
            }

        } else {
            return 0;
        }

        break;
#endif

    default:
        sin = (struct sockaddr_in *) addr;
        haddr = port->addrs;

        if (type) {
            lsin = (struct sockaddr_in *) ls->sockaddr;
            if (lsin->sin_port != sin->sin_port) {
                return NGX_ERROR;
            }
        }

        if (port->naddrs > 1) {

            for (i = 0; i < port->naddrs; i++) {

#if NGX_DEBUG
                u_char                     ip_str[80];

                ngx_memzero(ip_str, 80);

                (void) ngx_inet_ntop(AF_INET, &sin->sin_addr, ip_str, 80);

                ngx_log_debug1(NGX_LOG_DEBUG_CORE, ngx_cycle->log, 0,
                               "%s", ip_str);
#endif

                if (haddr[i].addr == sin->sin_addr.s_addr) {
                    return i;
                }
            }

        } else {
            return 0;
        }

        break;

    }

    return NGX_ERROR;
}


static ngx_int_t
ngx_limit_tcp_init_module(ngx_cycle_t *cycle)
{
    ngx_event_next_accept_filter = ngx_event_top_accept_filter;
    ngx_event_top_accept_filter = ngx_event_limit_accept_filter;

    return NGX_OK;
}


static ngx_int_t
ngx_limit_tcp_init_process(ngx_cycle_t *cycle)
{
    ngx_int_t                    idx;
    ngx_uint_t                   i, j;
    ngx_listening_t             *ls;
    ngx_connection_t            *c;
    ngx_limit_tcp_port_t        *port;
    ngx_limit_tcp_conf_t        *ltcf;
    ngx_limit_tcp_addr_t       **paddr;
    ngx_limit_tcp_listen_ctx_t  *lctx;

    ltcf = (ngx_limit_tcp_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx,
                                                 ngx_limit_tcp_module);

    if (!ltcf->enable) {
        return NGX_OK;
    }

    paddr = ltcf->lsocks.elts;
    ls = cycle->listening.elts;

    for (i = 0; i < cycle->listening.nelts; i++) {

        c = ls[i].connection;

        if (!c) {
            ngx_log_debug1(NGX_LOG_DEBUG_CORE, cycle->log, 0,
                           "listen %V has no connection", &ls[i].addr_text);
            continue;
        }

        port = ls[i].servers;

        lctx = ngx_pcalloc(cycle->pool, sizeof(ngx_limit_tcp_listen_ctx_t));
        if (lctx == NULL) {
            return NGX_ERROR;
        }

        lctx->addrs = ngx_pcalloc(cycle->pool,
                                  sizeof(ngx_limit_tcp_addr_t) * port->naddrs);


        for (j = 0; j < ltcf->lsocks.nelts; j++) {

            idx = ngx_limit_tcp_get_addr_index(&ls[i], &paddr[j]->sockaddr, 1);

            ngx_log_debug3(NGX_LOG_DEBUG_CORE, cycle->log, 0,
                           "listen %V %V matched idx: %i",
                           &ls[i].addr_text, &paddr[j]->addr_text, idx);

            if (idx == NGX_ERROR) {
                continue;
            }

            lctx->addrs[idx] = paddr[j];
        }

        c->data = lctx;
    }

    return NGX_OK;
}


static void
ngx_limit_tcp_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel)
{
    ngx_rbtree_node_t     **p;
    ngx_limit_tcp_node_t  *lrn, *lrnt;

    for ( ;; ) {

        if (node->key < temp->key) {

            p = &temp->left;

        } else if (node->key > temp->key) {

            p = &temp->right;

        } else { /* node->key == temp->key */

            lrn = (ngx_limit_tcp_node_t *) &node->color;
            lrnt = (ngx_limit_tcp_node_t *) &temp->color;

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
ngx_event_limit_accept_filter(ngx_connection_t *c)
{
    ngx_event_t                 *aev;
    ngx_listening_t             *ls;
    ngx_connection_t            *lc;
    ngx_limit_tcp_listen_ctx_t  *lctx;
    ngx_limit_tcp_accept_ctx_t  *actx;

    ngx_log_debug0(NGX_LOG_DEBUG_CORE, c->log, 0, "limit accept filter");

    ls = c->listening;
    lc = ls->connection;
    lctx = lc->data;

    if (lctx == NULL) {
        return ngx_event_next_accept_filter(lc);
    }

    aev = ngx_pcalloc(c->pool, sizeof(ngx_event_t));
    if (aev == NULL) {
        return NGX_ERROR;
    }

    actx = ngx_pcalloc(c->pool, sizeof(ngx_limit_tcp_accept_ctx_t));
    if (actx == NULL) {
        return NGX_ERROR;
    }

    ngx_log_error(NGX_LOG_DEBUG, c->log, 0, "limit accept effective %p", c);

    actx->connection = c;
    actx->lctx = lctx;

    aev->data = actx;
    aev->handler = ngx_limit_tcp_accepted;
    aev->log = c->log;

    if (ngx_use_accept_mutex) {
        ngx_post_event(aev, &ngx_posted_events);
        return NGX_DECLINED;
    }

    ngx_limit_tcp_accepted(aev);

    return NGX_DECLINED;
}


static void
ngx_limit_tcp_accepted(ngx_event_t *ev)
{
    ngx_limit_tcp_accept_ctx_t  *actx = ev->data;

    ngx_int_t                    rc, idx;
    ngx_uint_t                   excess, delay_excess;
    ngx_msec_t                   delay_time;
    ngx_listening_t             *ls;
    ngx_connection_t            *c;
    ngx_pool_cleanup_t          *cln;
    ngx_limit_tcp_ctx_t         *ctx;
    ngx_limit_tcp_node_t        *node;
    ngx_limit_tcp_delay_ctx_t   *dctx;
    ngx_limit_tcp_clean_ctx_t   *cctx;
    ngx_limit_tcp_listen_ctx_t  *lctx;

    c = actx->connection;
    ls = c->listening;
    lctx = actx->lctx;

    ngx_log_debug0(NGX_LOG_DEBUG_CORE, ev->log, 0, "limit tcp accepted");

    if (ngx_connection_local_sockaddr(c, NULL, 0) != NGX_OK) {
        ngx_close_accepted_connection(c);
        return;
    }

    idx = ngx_limit_tcp_get_addr_index(ls, c->local_sockaddr, 0);

    ngx_log_debug2(NGX_LOG_DEBUG_CORE, ev->log, 0,
                   "accept listen %V idx: %i", &ls->addr_text, idx);

    if (idx == NGX_ERROR || lctx->addrs[idx] == NULL) {
        goto accept_continue;
    }

    ctx = lctx->addrs[idx]->ctx;

    rc = ngx_limit_tcp_find(c);
    if (rc == NGX_BUSY) {

        ngx_log_debug1(NGX_LOG_DEBUG_CORE, ev->log, 0,
                       "limit %V find in black list", &c->addr_text);
        ngx_close_accepted_connection(c);

        return;

    } else if (rc == NGX_DECLINED) {
        ngx_log_debug1(NGX_LOG_DEBUG_CORE, ev->log, 0,
                       "limit %V find in white list", &c->addr_text);
        goto accept_continue;
    }

    delay_excess = 0;

    ngx_shmtx_lock(&ctx->shpool->mutex);
    ngx_limit_tcp_expire(c, ctx, 1);

    excess = 0;
    node = 0;
    rc = ngx_limit_tcp_lookup(c, ctx, &excess, &node);

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    if (rc == NGX_ERROR || node == 0) {
        goto accept_continue;
    }

    if (rc == NGX_BUSY) {
        ngx_close_accepted_connection(c);
        return;
    }

    cctx = ngx_pcalloc(c->pool, sizeof(ngx_limit_tcp_clean_ctx_t));
    if (cctx == NULL) {
        ngx_close_accepted_connection(c);
        return;
    }

    cctx->node = node;
    cctx->connection = c;

    cln = ngx_pool_cleanup_add(c->pool, 0);
    if (cln == NULL) {
        ngx_close_accepted_connection(c);
        return;
    }

    cln->handler = ngx_limit_tcp_cleanup;
    cln->data = cctx;

    if (rc == NGX_AGAIN) {
        if (delay_excess < excess) {
            delay_excess = excess;
        }
    }

    if (delay_excess) {
        if (ctx->nodelay) {
            goto accept_continue;
        }

        delay_time = (ngx_msec_t) delay_excess * 1000 / ctx->rate;

        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            ngx_close_accepted_connection(c);
            return;
        }

        dctx = ngx_pcalloc(c->pool, sizeof(ngx_limit_tcp_delay_ctx_t));

        if (dctx == NULL) {
            ngx_close_accepted_connection(c);
            return;
        }

        dctx->connection = c;

        dctx->rdata = c->read->data;
        dctx->rhandler = c->read->handler;

        dctx->whandler = c->write->handler;
        dctx->wdata = c->write->data;

        dctx->handler = ls->handler;

        c->read->data = dctx;
        c->write->data = dctx;
        c->read->handler = ngx_limit_tcp_test_reading;
        c->write->handler = ngx_limit_tcp_delay;

        ngx_add_timer(c->write, delay_time);

        return;
    }

accept_continue:

    ls->handler(c);
}


static ngx_int_t
ngx_limit_tcp_lookup(ngx_connection_t *c, ngx_limit_tcp_ctx_t *ctx,
    ngx_uint_t *ep, ngx_limit_tcp_node_t **rnode)
{
    size_t                           n;
    uint32_t                         hash;
    ngx_str_t                        addr;
    ngx_int_t                        rc, excess;
    ngx_time_t                      *tp;
    ngx_msec_t                       now;
    ngx_msec_int_t                   ms;
    ngx_rbtree_node_t               *node, *sentinel;
    ngx_limit_tcp_node_t            *lr;

    addr = c->addr_text;
    hash = ngx_crc32_short(addr.data, addr.len);
    node = ctx->sh->rbtree.root;
    sentinel = ctx->sh->rbtree.sentinel;
    rc = -1;

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

        lr = (ngx_limit_tcp_node_t *) &node->color;

        rc = ngx_memn2cmp(addr.data, lr->data, addr.len, (size_t) lr->len);

        if (rc == 0) {
            *rnode = lr;

            ngx_queue_remove(&lr->queue);
            ngx_queue_insert_head(&ctx->sh->queue, &lr->queue);

            ngx_log_debug3(NGX_LOG_DEBUG_CORE, c->log, 0,
                           "limit tcp count %ui %ui %p",
                           lr->count, addr.len, addr.data);

            if (ctx->concurrent && lr->count + 1 > ctx->concurrent) {
                ngx_log_error(NGX_LOG_INFO, c->log, 0,
                              "limit %V over concurrent: %ui",
                              &c->addr_text, lr->count);
                return NGX_BUSY;
            }

            (void) ngx_atomic_fetch_add(&lr->count, 1);

            if (!ctx->rate) {
                return NGX_OK;
            }

            tp = ngx_timeofday();

            now = (ngx_msec_t) (tp->sec * 1000 + tp->msec);
            ms = (ngx_msec_int_t) (now - lr->last);

            excess = lr->excess - ctx->rate * ngx_abs(ms) / 1000 + 1000;

            if (excess < 0) {
                excess = 0;
            }

            *ep = excess;

            if ((ngx_uint_t) excess > ctx->burst) {
                ngx_log_error(NGX_LOG_INFO, c->log, 0,
                              "limit %V over rate: %ui", &c->addr_text);
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

    n = offsetof(ngx_rbtree_node_t, color)
        + offsetof(ngx_limit_tcp_node_t, data)
        + addr.len;

    node = ngx_slab_alloc_locked(ctx->shpool, n);
    if (node == NULL) {
        ngx_limit_tcp_expire(c, ctx, 0);
        node = ngx_slab_alloc_locked(ctx->shpool, n);
        if (node == NULL) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);
            return NGX_ERROR;
        }
    }

    tp = ngx_timeofday();

    lr = (ngx_limit_tcp_node_t *) &node->color;

    node->key = hash;
    lr->len = (u_char) addr.len;
    lr->excess = 0;
    lr->count = 1;
    lr->last = (ngx_msec_t) (tp->sec * 1000 + tp->msec);

    ngx_memcpy(lr->data, addr.data, addr.len);

    ngx_queue_insert_head(&ctx->sh->queue, &lr->queue);
    ngx_rbtree_insert(&ctx->sh->rbtree, node);

    ngx_log_debug2(NGX_LOG_DEBUG_CORE, c->log, 0,
                   "limit tcp new %ui %uV", lr->count, &addr);
    *rnode = lr;

    return NGX_OK;
}


static void
ngx_limit_tcp_expire(ngx_connection_t *c, ngx_limit_tcp_ctx_t *ctx,
    ngx_uint_t n)
{
    ngx_int_t              excess;
    ngx_time_t            *tp;
    ngx_msec_t             now;
    ngx_queue_t           *q;
    ngx_msec_int_t         ms;
    ngx_rbtree_node_t     *node;
    ngx_limit_tcp_node_t  *lr;

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

        lr = ngx_queue_data(q, ngx_limit_tcp_node_t, queue);

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

        if (lr->count) {
            return;
        }

        ngx_queue_remove(q);

        node = (ngx_rbtree_node_t *)
                   ((u_char *) lr - offsetof(ngx_rbtree_node_t, color));

        ngx_rbtree_delete(&ctx->sh->rbtree, node);

        ngx_slab_free_locked(ctx->shpool, node);
    }
}


static void
ngx_limit_tcp_test_reading(ngx_event_t *ev)
{
    ngx_limit_tcp_delay_ctx_t  *dctx = ev->data;

    int                n;
    char               buf[1];
    ngx_err_t          err;
    ngx_event_t       *rev;
    ngx_connection_t  *c;

    c = dctx->connection;
    rev = c->read;

    ngx_log_debug0(NGX_LOG_DEBUG_CORE, c->log, 0, "limit tcp test reading");

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT) {

        if (!rev->pending_eof) {
            return;
        }

        rev->eof = 1;
        c->error = 1;
        err = rev->kq_errno;

        goto closed;
    }

#endif

    n = recv(c->fd, buf, 1, MSG_PEEK);

    if (n == 0) {
        rev->eof = 1;
        c->error = 1;
        err = 0;

        goto closed;

    } else if (n == -1) {
        err = ngx_socket_errno;

        if (err != NGX_EAGAIN) {
            rev->eof = 1;
            c->error = 1;

            goto closed;
        }
    }

    /* aio does not call this handler */

    if ((ngx_event_flags & NGX_USE_LEVEL_EVENT) && rev->active) {

        if (ngx_del_event(rev, NGX_READ_EVENT, 0) != NGX_OK) {
            ngx_close_accepted_connection(c);
        }
    }

    return;

closed:

    if (err) {
        rev->error = 1;
    }

    ngx_log_error(NGX_LOG_INFO, c->log, err,
                  "client closed prematurely connection");

    ngx_close_accepted_connection(c);
}


static void
ngx_limit_tcp_delay(ngx_event_t *ev)
{
    ngx_limit_tcp_delay_ctx_t  *dctx = ev->data;

    ngx_connection_t  *c;

    c = dctx->connection;

    ngx_log_debug0(NGX_LOG_DEBUG_CORE, c->log, 0, "limit_tcp delay");

    c->read->data = dctx->rdata;
    c->write->data = dctx->wdata;
    c->read->handler = dctx->rhandler;
    c->write->handler = dctx->whandler;

    if (!c->write->timedout) {

        if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
            ngx_close_accepted_connection(c);
        }

        return;
    }

    c->write->timedout = 0;

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        ngx_close_accepted_connection(c);
        return;
    }

    c->read->ready = 1;
    c->write->ready = 1;

    dctx->handler(c);
}


static void
ngx_limit_tcp_cleanup(void *data)
{
    ngx_limit_tcp_clean_ctx_t  *cctx = data;

    ngx_limit_tcp_node_t  *node;
    ngx_connection_t      *c;

    node = cctx->node;
    c = cctx->connection;

    if (c->write->timer_set) {
        ngx_log_debug0(NGX_LOG_DEBUG_CORE, c->log, 0,
                       "delete connection timer");
        ngx_del_timer(c->write);
    }

    (void) ngx_atomic_fetch_add(&node->count, -1);
}


static ngx_int_t
ngx_limit_tcp_find(ngx_connection_t *c)
{
    struct sockaddr_in    *sin;
    ngx_limit_tcp_conf_t  *ltcf;
#if (NGX_HAVE_INET6)
    u_char                *p;
    in_addr_t              addr;
    struct sockaddr_in6   *sin6;
#endif

    ltcf = (ngx_limit_tcp_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx,
                                                 ngx_limit_tcp_module);
    switch (c->sockaddr->sa_family) {

    case AF_INET:
        if (ltcf->rules) {
            sin = (struct sockaddr_in *) c->sockaddr;
            return ngx_limit_tcp_inet(c, ltcf, sin->sin_addr.s_addr);
        }
        break;

#if (NGX_HAVE_INET6)

    case AF_INET6:
        sin6 = (struct sockaddr_in6 *) c->sockaddr;
        p = sin6->sin6_addr.s6_addr;

        if (ltcf->rules && IN6_IS_ADDR_V4MAPPED(&sin6->sin6_addr)) {
            addr = p[12] << 24;
            addr += p[13] << 16;
            addr += p[14] << 8;
            addr += p[15];
            return ngx_limit_tcp_inet(c, ltcf, htonl(addr));
        }

        if (ltcf->rules6) {
            return ngx_limit_tcp_inet6(c, ltcf, p);
        }

#endif
    }

    return NGX_OK;
}


#if (NGX_HAVE_INET6)
static ngx_int_t
ngx_limit_tcp_inet6(ngx_connection_t *c, ngx_limit_tcp_conf_t *ltcf,
    u_char *p)
{
    ngx_uint_t                n;
    ngx_uint_t                i;
    ngx_limit_tcp_rule6_t    *rule6;

    rule6 = ltcf->rules6->elts;
    for (i = 0; i < ltcf->rules6->nelts; i++) {

#if (NGX_DEBUG)
        {
        size_t  cl, ml, al;
        u_char  ct[NGX_INET6_ADDRSTRLEN];
        u_char  mt[NGX_INET6_ADDRSTRLEN];
        u_char  at[NGX_INET6_ADDRSTRLEN];

        cl = ngx_inet6_ntop(p, ct, NGX_INET6_ADDRSTRLEN);
        ml = ngx_inet6_ntop(rule6[i].mask.s6_addr, mt, NGX_INET6_ADDRSTRLEN);
        al = ngx_inet6_ntop(rule6[i].addr.s6_addr, at, NGX_INET6_ADDRSTRLEN);

        ngx_log_debug6(NGX_LOG_DEBUG_CORE, c->log, 0,
                       "access: %*s %*s %*s", cl, ct, ml, mt, al, at);
        }
#endif

        for (n = 0; n < 16; n++) {
            if ((p[n] & rule6[i].mask.s6_addr[n]) != rule6[i].addr.s6_addr[n]) {
                goto next;
            }
        }

        return (rule6[i].deny ? NGX_BUSY : NGX_DECLINED);

    next:
        continue;
    }

    return NGX_OK;
}
#endif


static ngx_int_t
ngx_limit_tcp_inet(ngx_connection_t *c, ngx_limit_tcp_conf_t *ltcf,
    in_addr_t addr)
{
    ngx_uint_t               i;
    ngx_limit_tcp_rule_t  *rule;

    rule = ltcf->rules->elts;
    for (i = 0; i < ltcf->rules->nelts; i++) {

        ngx_log_debug3(NGX_LOG_DEBUG_CORE, c->log, 0,
                       "access: %08XD %08XD %08XD",
                       addr, rule[i].mask, rule[i].addr);

        if ((addr & rule[i].mask) == rule[i].addr) {
            return (rule[i].deny ? NGX_BUSY : NGX_DECLINED);
        }
    }

    return NGX_OK;
}
