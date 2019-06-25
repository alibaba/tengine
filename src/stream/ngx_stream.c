
/*
 * Copyright (C) Roman Arutyunyan
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_stream.h>


static char *ngx_stream_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_stream_init_phases(ngx_conf_t *cf,
    ngx_stream_core_main_conf_t *cmcf);
static ngx_int_t ngx_stream_init_phase_handlers(ngx_conf_t *cf,
    ngx_stream_core_main_conf_t *cmcf);
static ngx_int_t ngx_stream_add_ports(ngx_conf_t *cf, ngx_array_t *ports,
    ngx_stream_listen_t *listen);
static char *ngx_stream_optimize_servers(ngx_conf_t *cf, ngx_array_t *ports);
static ngx_int_t ngx_stream_add_addrs(ngx_conf_t *cf, ngx_stream_port_t *stport,
    ngx_stream_conf_addr_t *addr);
#if (NGX_HAVE_INET6)
static ngx_int_t ngx_stream_add_addrs6(ngx_conf_t *cf,
    ngx_stream_port_t *stport, ngx_stream_conf_addr_t *addr);
#endif
static ngx_int_t ngx_stream_cmp_conf_addrs(const void *one, const void *two);


ngx_uint_t  ngx_stream_max_module;


ngx_stream_filter_pt  ngx_stream_top_filter;


static ngx_command_t  ngx_stream_commands[] = {

    { ngx_string("stream"),
      NGX_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_stream_block,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_core_module_t  ngx_stream_module_ctx = {
    ngx_string("stream"),
    NULL,
    NULL
};


ngx_module_t  ngx_stream_module = {
    NGX_MODULE_V1,
    &ngx_stream_module_ctx,                /* module context */
    ngx_stream_commands,                   /* module directives */
    NGX_CORE_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static char *
ngx_stream_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                          *rv;
    ngx_uint_t                     i, m, mi, s;
    ngx_conf_t                     pcf;
    ngx_array_t                    ports;
    ngx_stream_listen_t           *listen;
    ngx_stream_module_t           *module;
    ngx_stream_conf_ctx_t         *ctx;
    ngx_stream_core_srv_conf_t   **cscfp;
    ngx_stream_core_main_conf_t   *cmcf;

    if (*(ngx_stream_conf_ctx_t **) conf) {
        return "is duplicate";
    }

    /* the main stream context */

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_stream_conf_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    *(ngx_stream_conf_ctx_t **) conf = ctx;

    /* count the number of the stream modules and set up their indices */

    ngx_stream_max_module = ngx_count_modules(cf->cycle, NGX_STREAM_MODULE);


    /* the stream main_conf context, it's the same in the all stream contexts */

    ctx->main_conf = ngx_pcalloc(cf->pool,
                                 sizeof(void *) * ngx_stream_max_module);
    if (ctx->main_conf == NULL) {
        return NGX_CONF_ERROR;
    }


    /*
     * the stream null srv_conf context, it is used to merge
     * the server{}s' srv_conf's
     */

    ctx->srv_conf = ngx_pcalloc(cf->pool,
                                sizeof(void *) * ngx_stream_max_module);
    if (ctx->srv_conf == NULL) {
        return NGX_CONF_ERROR;
    }


    /*
     * create the main_conf's and the null srv_conf's of the all stream modules
     */

    for (m = 0; cf->cycle->modules[m]; m++) {
        if (cf->cycle->modules[m]->type != NGX_STREAM_MODULE) {
            continue;
        }

        module = cf->cycle->modules[m]->ctx;
        mi = cf->cycle->modules[m]->ctx_index;

        if (module->create_main_conf) {
            ctx->main_conf[mi] = module->create_main_conf(cf);
            if (ctx->main_conf[mi] == NULL) {
                return NGX_CONF_ERROR;
            }
        }

        if (module->create_srv_conf) {
            ctx->srv_conf[mi] = module->create_srv_conf(cf);
            if (ctx->srv_conf[mi] == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }


    pcf = *cf;
    cf->ctx = ctx;

    for (m = 0; cf->cycle->modules[m]; m++) {
        if (cf->cycle->modules[m]->type != NGX_STREAM_MODULE) {
            continue;
        }

        module = cf->cycle->modules[m]->ctx;

        if (module->preconfiguration) {
            if (module->preconfiguration(cf) != NGX_OK) {
                return NGX_CONF_ERROR;
            }
        }
    }


    /* parse inside the stream{} block */

    cf->module_type = NGX_STREAM_MODULE;
    cf->cmd_type = NGX_STREAM_MAIN_CONF;
    rv = ngx_conf_parse(cf, NULL);

    if (rv != NGX_CONF_OK) {
        *cf = pcf;
        return rv;
    }


    /* init stream{} main_conf's, merge the server{}s' srv_conf's */

    cmcf = ctx->main_conf[ngx_stream_core_module.ctx_index];
    cscfp = cmcf->servers.elts;

    for (m = 0; cf->cycle->modules[m]; m++) {
        if (cf->cycle->modules[m]->type != NGX_STREAM_MODULE) {
            continue;
        }

        module = cf->cycle->modules[m]->ctx;
        mi = cf->cycle->modules[m]->ctx_index;

        /* init stream{} main_conf's */

        cf->ctx = ctx;

        if (module->init_main_conf) {
            rv = module->init_main_conf(cf, ctx->main_conf[mi]);
            if (rv != NGX_CONF_OK) {
                *cf = pcf;
                return rv;
            }
        }

        for (s = 0; s < cmcf->servers.nelts; s++) {

            /* merge the server{}s' srv_conf's */

            cf->ctx = cscfp[s]->ctx;

            if (module->merge_srv_conf) {
                rv = module->merge_srv_conf(cf,
                                            ctx->srv_conf[mi],
                                            cscfp[s]->ctx->srv_conf[mi]);
                if (rv != NGX_CONF_OK) {
                    *cf = pcf;
                    return rv;
                }
            }
        }
    }

    if (ngx_stream_init_phases(cf, cmcf) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    for (m = 0; cf->cycle->modules[m]; m++) {
        if (cf->cycle->modules[m]->type != NGX_STREAM_MODULE) {
            continue;
        }

        module = cf->cycle->modules[m]->ctx;

        if (module->postconfiguration) {
            if (module->postconfiguration(cf) != NGX_OK) {
                return NGX_CONF_ERROR;
            }
        }
    }

    if (ngx_stream_variables_init_vars(cf) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    *cf = pcf;

    if (ngx_stream_init_phase_handlers(cf, cmcf) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    if (ngx_array_init(&ports, cf->temp_pool, 4, sizeof(ngx_stream_conf_port_t))
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    listen = cmcf->listen.elts;

    for (i = 0; i < cmcf->listen.nelts; i++) {
        if (ngx_stream_add_ports(cf, &ports, &listen[i]) != NGX_OK) {
            return NGX_CONF_ERROR;
        }
    }

    return ngx_stream_optimize_servers(cf, &ports);
}


static ngx_int_t
ngx_stream_init_phases(ngx_conf_t *cf, ngx_stream_core_main_conf_t *cmcf)
{
    if (ngx_array_init(&cmcf->phases[NGX_STREAM_POST_ACCEPT_PHASE].handlers,
                       cf->pool, 1, sizeof(ngx_stream_handler_pt))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (ngx_array_init(&cmcf->phases[NGX_STREAM_PREACCESS_PHASE].handlers,
                       cf->pool, 1, sizeof(ngx_stream_handler_pt))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (ngx_array_init(&cmcf->phases[NGX_STREAM_ACCESS_PHASE].handlers,
                       cf->pool, 1, sizeof(ngx_stream_handler_pt))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (ngx_array_init(&cmcf->phases[NGX_STREAM_SSL_PHASE].handlers,
                       cf->pool, 1, sizeof(ngx_stream_handler_pt))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (ngx_array_init(&cmcf->phases[NGX_STREAM_PREREAD_PHASE].handlers,
                       cf->pool, 1, sizeof(ngx_stream_handler_pt))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (ngx_array_init(&cmcf->phases[NGX_STREAM_LOG_PHASE].handlers,
                       cf->pool, 1, sizeof(ngx_stream_handler_pt))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    return NGX_OK;
}

#if (NGX_STREAM_SNI)

static int ngx_libc_cdecl
ngx_stream_cmp_dns_wildcards(const void *one, const void *two)
{
    ngx_hash_key_t  *first, *second;

    first = (ngx_hash_key_t *) one;
    second = (ngx_hash_key_t *) two;

    return ngx_dns_strcmp(first->key.data, second->key.data);
}


static ngx_int_t
ngx_stream_server_names(ngx_conf_t *cf, ngx_stream_core_main_conf_t *cmcf,
    ngx_stream_conf_addr_t *addr)
{
    ngx_int_t                   rc;
    ngx_uint_t                  n, s;
    ngx_hash_init_t             hash;
    ngx_hash_keys_arrays_t      ha;
    ngx_stream_server_name_t   *name;
    ngx_stream_core_srv_conf_t **cscfp;

    ngx_memzero(&ha, sizeof(ngx_hash_keys_arrays_t));

    ha.temp_pool = ngx_create_pool(NGX_DEFAULT_POOL_SIZE, cf->log);
    if (ha.temp_pool == NULL) {
        return NGX_ERROR;
    }

    ha.pool = cf->pool;

    if (ngx_hash_keys_array_init(&ha, NGX_HASH_LARGE) != NGX_OK) {
        goto failed;
    }

    cscfp = addr->servers.elts;

    for (s = 0; s < addr->servers.nelts; s++) {

        name = cscfp[s]->server_names.elts;

        for (n = 0; n < cscfp[s]->server_names.nelts; n++) {

            rc = ngx_hash_add_key(&ha, &name[n].name, name[n].server,
                                  NGX_HASH_WILDCARD_KEY);

            if (rc == NGX_ERROR) {
                return NGX_ERROR;
            }

            if (rc == NGX_DECLINED) {
                ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                              "invalid server name or wildcard \"%V\"",
                              &name[n].name);
                return NGX_ERROR;
            }

            if (rc == NGX_BUSY) {
                ngx_log_error(NGX_LOG_WARN, cf->log, 0,
                              "conflicting server name \"%V\" ignored",
                              &name[n].name);
            }
        }
    }

    hash.key = ngx_hash_key_lc;
    hash.max_size = cmcf->server_names_hash_max_size;
    hash.bucket_size = cmcf->server_names_hash_bucket_size;
    hash.name = "server_names_hash";
    hash.pool = cf->pool;

    if (ha.keys.nelts) {
        hash.hash = &addr->hash;
        hash.temp_pool = NULL;

        if (ngx_hash_init(&hash, ha.keys.elts, ha.keys.nelts) != NGX_OK) {
            goto failed;
        }
    }

    if (ha.dns_wc_head.nelts) {

        ngx_qsort(ha.dns_wc_head.elts, (size_t) ha.dns_wc_head.nelts,
                  sizeof(ngx_hash_key_t), ngx_stream_cmp_dns_wildcards);

        hash.hash = NULL;
        hash.temp_pool = ha.temp_pool;

        if (ngx_hash_wildcard_init(&hash, ha.dns_wc_head.elts,
                                   ha.dns_wc_head.nelts)
            != NGX_OK)
        {
            goto failed;
        }

        addr->wc_head = (ngx_hash_wildcard_t *) hash.hash;
    }

    if (ha.dns_wc_tail.nelts) {

        ngx_qsort(ha.dns_wc_tail.elts, (size_t) ha.dns_wc_tail.nelts,
                  sizeof(ngx_hash_key_t), ngx_stream_cmp_dns_wildcards);

        hash.hash = NULL;
        hash.temp_pool = ha.temp_pool;

        if (ngx_hash_wildcard_init(&hash, ha.dns_wc_tail.elts,
                                   ha.dns_wc_tail.nelts)
            != NGX_OK)
        {
            goto failed;
        }

        addr->wc_tail = (ngx_hash_wildcard_t *) hash.hash;
    }

    ngx_destroy_pool(ha.temp_pool);

    return NGX_OK;

failed:

    ngx_destroy_pool(ha.temp_pool);

    return NGX_ERROR;
}

/* add the server core module configuration to the address:port */

static ngx_int_t
ngx_stream_add_server(ngx_conf_t *cf, ngx_stream_core_srv_conf_t *cscf,
    ngx_stream_conf_addr_t *addr)
{
    ngx_uint_t                  i;
    ngx_stream_core_srv_conf_t  **server;

    if (addr->servers.elts == NULL) {
        if (ngx_array_init(&addr->servers, cf->temp_pool, 4,
                           sizeof(ngx_stream_core_srv_conf_t *))
            != NGX_OK)
        {
            return NGX_ERROR;
        }

    } else {
        server = addr->servers.elts;
        for (i = 0; i < addr->servers.nelts; i++) {
            if (server[i] == cscf) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "a duplicate listen");
                return NGX_ERROR;
            }
        }
    }

    server = ngx_array_push(&addr->servers);
    if (server == NULL) {
        return NGX_ERROR;
    }

    *server = cscf;

    return NGX_OK;
}
#endif


static ngx_int_t
ngx_stream_init_phase_handlers(ngx_conf_t *cf,
    ngx_stream_core_main_conf_t *cmcf)
{
    ngx_int_t                     j;
    ngx_uint_t                    i, n;
    ngx_stream_handler_pt        *h;
    ngx_stream_phase_handler_t   *ph;
    ngx_stream_phase_handler_pt   checker;

    n = 1 /* content phase */;

    for (i = 0; i < NGX_STREAM_LOG_PHASE; i++) {
        n += cmcf->phases[i].handlers.nelts;
    }

    ph = ngx_pcalloc(cf->pool,
                     n * sizeof(ngx_stream_phase_handler_t) + sizeof(void *));
    if (ph == NULL) {
        return NGX_ERROR;
    }

    cmcf->phase_engine.handlers = ph;
    n = 0;

    for (i = 0; i < NGX_STREAM_LOG_PHASE; i++) {
        h = cmcf->phases[i].handlers.elts;

        switch (i) {

        case NGX_STREAM_PREREAD_PHASE:
            checker = ngx_stream_core_preread_phase;
            break;

        case NGX_STREAM_CONTENT_PHASE:
            ph->checker = ngx_stream_core_content_phase;
            n++;
            ph++;

            continue;

        default:
            checker = ngx_stream_core_generic_phase;
        }

        n += cmcf->phases[i].handlers.nelts;

        for (j = cmcf->phases[i].handlers.nelts - 1; j >= 0; j--) {
            ph->checker = checker;
            ph->handler = h[j];
            ph->next = n;
            ph++;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_stream_add_ports(ngx_conf_t *cf, ngx_array_t *ports,
    ngx_stream_listen_t *listen)
{
    in_port_t                p;
    ngx_uint_t               i;
    struct sockaddr         *sa;
    ngx_stream_conf_port_t  *port;
    ngx_stream_conf_addr_t  *addr;
#if (NGX_STREAM_SNI)
    ngx_stream_core_srv_conf_t *cscf;
#endif

    sa = listen->sockaddr;
    p = ngx_inet_get_port(sa);

    port = ports->elts;
    for (i = 0; i < ports->nelts; i++) {

        if (p == port[i].port
            && listen->type == port[i].type
            && sa->sa_family == port[i].family)
        {
            /* a port is already in the port list */

            port = &port[i];
            goto found;
        }
    }

    /* add a port to the port list */

    port = ngx_array_push(ports);
    if (port == NULL) {
        return NGX_ERROR;
    }

    port->family = sa->sa_family;
    port->type = listen->type;
    port->port = p;

    if (ngx_array_init(&port->addrs, cf->temp_pool, 2,
                       sizeof(ngx_stream_conf_addr_t))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

found:
#if (NGX_STREAM_SNI)

    cscf = listen->ctx->srv_conf[ngx_stream_core_module.ctx_index];
    addr = port->addrs.elts;

    for (i = 0; i < port->addrs.nelts; i++) {
        if (ngx_cmp_sockaddr(listen->sockaddr, listen->socklen,
            addr[i].opt.sockaddr,
            addr[i].opt.socklen, 0)
            != NGX_OK)
        {
            continue;
        }

        /* the address is already in the address list */

        if (ngx_stream_add_server(cf, cscf, &addr[i]) != NGX_OK) {
            return NGX_ERROR;
        }

        if (listen->default_server) {

            if (addr[i].opt.default_server) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                        "a duplicate default server for");
                return NGX_ERROR;
            }
            addr[i].default_server = cscf;
            addr[i].opt.default_server = 1;
        }
        return NGX_OK;
    }

    addr = ngx_array_push(&port->addrs);
    if (addr == NULL) {
        return NGX_ERROR;
    }
    ngx_memset(addr, 0, sizeof(ngx_stream_conf_addr_t));
    addr->opt = *listen;
    addr->default_server = cscf;

    return ngx_stream_add_server(cf, cscf, &addr[i]);

#else

    addr = ngx_array_push(&port->addrs);
    if (addr == NULL) {
        return NGX_ERROR;
    }

    addr->opt = *listen;

    return NGX_OK;
#endif
}


static char *
ngx_stream_optimize_servers(ngx_conf_t *cf, ngx_array_t *ports)
{
    ngx_uint_t                   i, p, last, bind_wildcard;
    ngx_listening_t             *ls;
    ngx_stream_port_t           *stport;
    ngx_stream_conf_port_t      *port;
    ngx_stream_conf_addr_t      *addr;
    ngx_stream_core_srv_conf_t  *cscf;

#if (NGX_STREAM_SNI)
    ngx_stream_core_main_conf_t *cmcf;
#endif
    port = ports->elts;
    for (p = 0; p < ports->nelts; p++) {

        ngx_sort(port[p].addrs.elts, (size_t) port[p].addrs.nelts,
                 sizeof(ngx_stream_conf_addr_t), ngx_stream_cmp_conf_addrs);

        addr = port[p].addrs.elts;
        last = port[p].addrs.nelts;

        /*
         * if there is the binding to the "*:port" then we need to bind()
         * to the "*:port" only and ignore the other bindings
         */

        if (addr[last - 1].opt.wildcard) {
            addr[last - 1].opt.bind = 1;
            bind_wildcard = 1;

        } else {
            bind_wildcard = 0;
        }

        i = 0;

        while (i < last) {

            if (bind_wildcard && !addr[i].opt.bind) {
                i++;
                continue;
            }

            ls = ngx_create_listening(cf, addr[i].opt.sockaddr,
                                      addr[i].opt.socklen);
            if (ls == NULL) {
                return NGX_CONF_ERROR;
            }

            ls->addr_ntop = 1;
            ls->handler = ngx_stream_init_connection;
            ls->pool_size = 256;
            ls->type = addr[i].opt.type;

            cscf = addr->opt.ctx->srv_conf[ngx_stream_core_module.ctx_index];

            ls->logp = cscf->error_log;
            ls->log.data = &ls->addr_text;
            ls->log.handler = ngx_accept_log_error;

            ls->backlog = addr[i].opt.backlog;
            ls->rcvbuf = addr[i].opt.rcvbuf;
            ls->sndbuf = addr[i].opt.sndbuf;

            ls->wildcard = addr[i].opt.wildcard;

            ls->keepalive = addr[i].opt.so_keepalive;
#if (NGX_HAVE_KEEPALIVE_TUNABLE)
            ls->keepidle = addr[i].opt.tcp_keepidle;
            ls->keepintvl = addr[i].opt.tcp_keepintvl;
            ls->keepcnt = addr[i].opt.tcp_keepcnt;
#endif

#if (NGX_HAVE_INET6)
            ls->ipv6only = addr[i].opt.ipv6only;
#endif

#if (NGX_HAVE_REUSEPORT)
            ls->reuseport = addr[i].opt.reuseport;
#endif

            stport = ngx_palloc(cf->pool, sizeof(ngx_stream_port_t));
            if (stport == NULL) {
                return NGX_CONF_ERROR;
            }

            ls->servers = stport;

            stport->naddrs = i + 1;

#if (NGX_STREAM_SNI)
            cmcf = addr->opt.ctx->main_conf[ngx_stream_core_module.ctx_index];
            /*Because of ssl_sni_force we have to do this even one server*/
            if (addr[i].servers.nelts >= 1) {
                if (ngx_stream_server_names(cf, cmcf, &addr[i]) != NGX_OK) {
                    return NGX_CONF_ERROR;
                }
            }
#endif

            switch (ls->sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
            case AF_INET6:
                if (ngx_stream_add_addrs6(cf, stport, addr) != NGX_OK) {
                    return NGX_CONF_ERROR;
                }
                break;
#endif
            default: /* AF_INET */
                if (ngx_stream_add_addrs(cf, stport, addr) != NGX_OK) {
                    return NGX_CONF_ERROR;
                }
                break;
            }

            addr++;
            last--;
        }
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_stream_add_addrs(ngx_conf_t *cf, ngx_stream_port_t *stport,
    ngx_stream_conf_addr_t *addr)
{
    ngx_uint_t             i;
    struct sockaddr_in    *sin;
    ngx_stream_in_addr_t  *addrs;
#if (NGX_STREAM_SNI)
    ngx_stream_virtual_names_t  *vn;
#endif

    stport->addrs = ngx_pcalloc(cf->pool,
                                stport->naddrs * sizeof(ngx_stream_in_addr_t));
    if (stport->addrs == NULL) {
        return NGX_ERROR;
    }

    addrs = stport->addrs;

    for (i = 0; i < stport->naddrs; i++) {

        sin = (struct sockaddr_in *) addr[i].opt.sockaddr;
        addrs[i].addr = sin->sin_addr.s_addr;

        addrs[i].conf.ctx = addr[i].opt.ctx;
#if (NGX_STREAM_SSL)
        addrs[i].conf.ssl = addr[i].opt.ssl;
#endif
        addrs[i].conf.proxy_protocol = addr[i].opt.proxy_protocol;
        addrs[i].conf.addr_text = addr[i].opt.addr_text;

#if (NGX_STREAM_SNI)
        addrs[i].conf.default_server = addr[i].default_server;

        if (addr[i].hash.buckets == NULL
            && (addr[i].wc_head == NULL
                || addr[i].wc_head->hash.buckets == NULL)
            && (addr[i].wc_tail == NULL
                || addr[i].wc_tail->hash.buckets == NULL)
            )
        {
            continue;
        }

        vn = ngx_palloc(cf->pool, sizeof(ngx_stream_virtual_names_t));
        if (vn == NULL) {
            return NGX_ERROR;
        }

        addrs[i].conf.virtual_names = vn;

        vn->names.hash = addr[i].hash;
        vn->names.wc_head = addr[i].wc_head;
        vn->names.wc_tail = addr[i].wc_tail;
#endif
    }

    return NGX_OK;
}


#if (NGX_HAVE_INET6)

static ngx_int_t
ngx_stream_add_addrs6(ngx_conf_t *cf, ngx_stream_port_t *stport,
    ngx_stream_conf_addr_t *addr)
{
    ngx_uint_t              i;
    struct sockaddr_in6    *sin6;
    ngx_stream_in6_addr_t  *addrs6;
#if (NGX_STREAM_SNI)
    ngx_stream_virtual_names_t  *vn;
#endif

    stport->addrs = ngx_pcalloc(cf->pool,
                                stport->naddrs * sizeof(ngx_stream_in6_addr_t));
    if (stport->addrs == NULL) {
        return NGX_ERROR;
    }

    addrs6 = stport->addrs;

    for (i = 0; i < stport->naddrs; i++) {

        sin6 = (struct sockaddr_in6 *) addr[i].opt.sockaddr;
        addrs6[i].addr6 = sin6->sin6_addr;

        addrs6[i].conf.ctx = addr[i].opt.ctx;
#if (NGX_STREAM_SSL)
        addrs6[i].conf.ssl = addr[i].opt.ssl;
#endif
        addrs6[i].conf.proxy_protocol = addr[i].opt.proxy_protocol;
        addrs6[i].conf.addr_text = addr[i].opt.addr_text;

#if (NGX_STREAM_SNI)
        if (addr[i].hash.buckets == NULL
            && (addr[i].wc_head == NULL
                || addr[i].wc_head->hash.buckets == NULL)
            && (addr[i].wc_tail == NULL
                || addr[i].wc_tail->hash.buckets == NULL)
            )
        {
            continue;
        }

        vn = ngx_palloc(cf->pool, sizeof(ngx_stream_virtual_names_t));
        if (vn == NULL) {
            return NGX_ERROR;
        }

        addrs6[i].conf.virtual_names = vn;

        vn->names.hash = addr[i].hash;
        vn->names.wc_head = addr[i].wc_head;
        vn->names.wc_tail = addr[i].wc_tail;
#endif
    }

    return NGX_OK;
}

#endif


static ngx_int_t
ngx_stream_cmp_conf_addrs(const void *one, const void *two)
{
    ngx_stream_conf_addr_t  *first, *second;

    first = (ngx_stream_conf_addr_t *) one;
    second = (ngx_stream_conf_addr_t *) two;

    if (first->opt.wildcard) {
        /* a wildcard must be the last resort, shift it to the end */
        return 1;
    }

    if (second->opt.wildcard) {
        /* a wildcard must be the last resort, shift it to the end */
        return -1;
    }

    if (first->opt.bind && !second->opt.bind) {
        /* shift explicit bind()ed addresses to the start */
        return -1;
    }

    if (!first->opt.bind && second->opt.bind) {
        /* shift explicit bind()ed addresses to the start */
        return 1;
    }

    /* do not sort by default */

    return 0;
}
