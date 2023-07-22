/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_xudp_module.h>
#include <ngx_xudp_internal.h>
#include <ngx_http.h>
#include <ngx_xudp.h>
#include <ngx_process_cycle.h>


#ifndef XUDP_XQUIC_MAP_NAME
#define XUDP_XQUIC_MAP_NAME "map_xquic"
#endif

#ifndef XUDP_XQUIC_MAP_DEFAULT_KEY
#define XUDP_XQUIC_MAP_DEFAULT_KEY (0)
#endif


#define NGX_RADIX32_MASK   0xffffffff

#if (NGX_HAVE_INET6)
static uint32_t _ngx_radix128_mask[4] = {NGX_RADIX32_MASK,NGX_RADIX32_MASK,NGX_RADIX32_MASK,NGX_RADIX32_MASK};
#define NGX_RADIX128_MASK ((u_char *) (&_ngx_radix128_mask[0]))
#endif

static ngx_inline ngx_int_t
ngx_xudp_error(ngx_xudp_conf_t *xcf, ngx_int_t errorcode)
{
return xcf->allow_degrade ? NGX_OK : errorcode;
}

/**
 * load xudp engine
 * @allow_degrade allow degrade to system udp if xudp load faield
 * @return NGX_OK for success , other for failed
 * */
static ngx_int_t ngx_xudp_load(ngx_cycle_t *cycle);

/**
 * stop xudp , udp packet will pass to kernel
 * */
static void ngx_xudp_stop(ngx_cycle_t *cycle);

/**
 * cleanup xudp engine
 * */
static void ngx_xudp_free(ngx_cycle_t *cycle);

/**
 * clear xudp ctx
 * */
static xudp *ngx_xudp_clear(ngx_cycle_t *cycle);

/**
 * convert nginx log level to xudp level
 * */
static int ngx_xudp_from_ngx_log_level(ngx_cycle_t *cycle);

/**
 * xudp engine log callback
 * */
static int ngx_xudp_log(char *buf, int size, void *data);

/**
 * create xudp core module configure
 * */
static void *ngx_xudp_core_module_create_conf(ngx_cycle_t *cycle);

/**
 * init xudp core module configure with default value , and
 * load xudp engine if necessary
 * */
static char *ngx_xudp_core_module_init_conf(ngx_cycle_t *cycle, void *conf);

/**
 * create xudp listening sockets
 * */
static ngx_int_t ngx_xudp_create_listening_sockets(ngx_cycle_t *cycle);

/**
 * according to xudp listening ports, create radix tree
 * */
static ngx_int_t ngx_xudp_create_address_map(ngx_cycle_t *cycle);

/**
 * flush NIC send queue 
 * */
static void ngx_xudp_flush_send_data(ngx_event_t *ev);

static ngx_int_t ngx_xudp_core_module_init_module(ngx_cycle_t *cycle);

/**
 * add xudp listening before event module
 * @return NGX_OK for success , other for failed
 * rely on `ngx_xudp_add_listening` , `ngx_xudp_create_address_map`
 * */
static ngx_int_t ngx_xudp_core_module_init_process(ngx_cycle_t *cycle);

static void ngx_xudp_core_module_exit_process(ngx_cycle_t *cycle);

/**
 * core module exit master
 * */
static void ngx_xudp_core_module_exit_master(ngx_cycle_t *cycle);

// --- //

/**
 * get xudp variable
 * */
static ngx_int_t ngx_xudp_variable (ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);

/**
 * http module pre configure handler
 * */
static ngx_int_t ngx_xudp_add_http_variables(ngx_conf_t *cf);

/**
 * http module post configure handler
 * */

static ngx_int_t ngx_xudp_http_postconfiguration(ngx_conf_t *cf);

/**
 * set xudp listening recv & write event callback
 * @return NGX_OK for success ,other for failed
 * rely on  `ngx_event_xudp_recvmsg`
 * */
static ngx_int_t ngx_xudp_module_init_process(ngx_cycle_t *cycle);

/**
 * xudp recv event callback
 * */
static void ngx_event_xudp_recvmsg(ngx_event_t *rev);

/**
 * choose connection based on the destination address of the packet
 * */
static ngx_listening_t *ngx_xudp_find_listening(ngx_listening_t *xudp_ls, const struct sockaddr *sa);


/** xudp core module */
static ngx_command_t ngx_xudp_core_commands[] = {

        {
                ngx_string("xudp_off"),
                NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_FLAG,
                ngx_conf_set_flag_slot,
                0,
                offsetof(ngx_xudp_conf_t, no_xudp),
                NULL
        },
        {
                ngx_string("xudp_no_tx"),
                NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_FLAG,
                ngx_conf_set_flag_slot,
                0,
                offsetof(ngx_xudp_conf_t, no_xudp_tx),
                NULL
        },
        {
                ngx_string("xudp_core_path"),
                NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_1MORE,
                ngx_conf_set_str_slot,
                0,
                offsetof(ngx_xudp_conf_t, dispatcher_path),
                NULL
        },
        {
                ngx_string("xudp_sndnum"),
                NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_1MORE,
                ngx_conf_set_num_slot,
                0,
                offsetof(ngx_xudp_conf_t, sndnum),
                NULL
        },
        {
                ngx_string("xudp_rcvnum"),
                NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_1MORE,
                ngx_conf_set_num_slot,
                0,
                offsetof(ngx_xudp_conf_t, rcvnum),
                NULL
        },

        {
                ngx_string("xudp_retries_interval"),
                NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_1MORE,
                ngx_conf_set_msec_slot,
                0,
                offsetof(ngx_xudp_conf_t, retries_interval),
                NULL
        },

        {
                ngx_string("max_retries"),
                NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_1MORE,
                ngx_conf_set_num_slot,
                0,
                offsetof(ngx_xudp_conf_t, max_retries),
                NULL
        },

        ngx_null_command
};

static ngx_core_module_t  ngx_xudp_core_module_ctx = {
        ngx_string("xudp_core"),
        ngx_xudp_core_module_create_conf,
        ngx_xudp_core_module_init_conf,
};

ngx_module_t ngx_xudp_core_module = {
        NGX_MODULE_V1,
        &ngx_xudp_core_module_ctx,             /* module context */
        ngx_xudp_core_commands,                /* module directives */
        NGX_CORE_MODULE,                       /* module type */
        NULL,                                  /* init master */
        ngx_xudp_core_module_init_module,      /* init module */
        ngx_xudp_core_module_init_process,     /* init process */
        NULL,                                  /* init thread */
        NULL,                                  /* exit thread */
        ngx_xudp_core_module_exit_process,     /* exit process */
        ngx_xudp_core_module_exit_master,      /* exit master */
        NGX_MODULE_V1_PADDING
};

static void *
ngx_xudp_core_module_create_conf(ngx_cycle_t *cycle)
{
    ngx_xudp_conf_t *xcf;
    xcf = ngx_pcalloc(cycle->pool, sizeof(ngx_xudp_conf_t));
    if (xcf == NULL) {
        return NULL;
    }

    ngx_array_init(&xcf->xudp_address, cycle->pool, NGX_CONF_MAX_ARGS, sizeof(ngx_sockaddr_t));

    xcf->rcvnum             = NGX_CONF_UNSET_UINT;
    xcf->sndnum             = NGX_CONF_UNSET_UINT;
    xcf->no_xudp            = NGX_CONF_UNSET;
    xcf->no_xudp_tx         = NGX_CONF_UNSET;
    xcf->retries_interval   = NGX_CONF_UNSET_MSEC;
    xcf->max_retries        = NGX_CONF_UNSET;
    xcf->allow_degrade      = 1;

    return xcf;
}


/**
 * fill sockaddr in (r) with target af and port
 * @param port required network order
 * return (r)
 * */
static struct sockaddr *
ngx_xudp_built_sockaddr(ngx_sockaddr_t *r, int af, int port)
{
    /* zero */
    ngx_memzero(r, sizeof(*r));

    /* set family */
    r->sockaddr.sa_family = af ;

    if (af == AF_INET) {
        r->sockaddr_in.sin_port = port;
    }else if(af == AF_INET6) {
#if (NGX_HAVE_INET6)
        r->sockaddr_in6.sin6_port = port;
#endif
    }

    return &r->sockaddr;
}

static ngx_int_t
ngx_xudp_add_address(ngx_xudp_conf_t *xcf, struct sockaddr *sa)
{
    ngx_sockaddr_t *addr;

    addr = (ngx_sockaddr_t*) ngx_array_push(&xcf->xudp_address);
    if (addr == NULL) {
        return NGX_ERROR;
    }

    switch(sa->sa_family) {
        case AF_INET:
            ngx_memcpy(addr, sa, sizeof(struct sockaddr_in));
            break;
        case AF_INET6:
            ngx_memcpy(addr, sa, sizeof(struct sockaddr_in6));
            break;
        default:
            /* un support family*/
            return NGX_ERROR;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_xudp_get_address_from_http_core_module(ngx_xudp_conf_t *xcf, ngx_http_core_main_conf_t *cmcf)
{
    size_t                       i, j, r;
    ngx_http_conf_port_t        *port;
    ngx_http_conf_addr_t        *addr;
    ngx_sockaddr_t               wildcard;

    if (cmcf->ports == NULL) {
        return NGX_OK;
    }

    port = (ngx_http_conf_port_t*) cmcf->ports->elts;

    for(i = 0; i < cmcf->ports->nelts; i++) {
        if (port[i].xudp) {
            r = ngx_xudp_add_address(xcf, ngx_xudp_built_sockaddr(&wildcard, port[i].family, port[i].port));
            if (r != NGX_OK) {
                return r;
            }
            continue;
        }
        addr = (ngx_http_conf_addr_t*) port[i].addrs.elts;
        for(j = 0; j < port[i].addrs.nelts; j++) {

            if (!addr[j].opt.xudp) {
                continue;
            }

            r = ngx_xudp_add_address(xcf, addr[j].opt.sockaddr);
            if (r != NGX_OK) {
                return r;
            }
        }
    }

    return NGX_OK;
}

static ngx_int_t
ngx_xudp_http_postconfiguration(ngx_conf_t *cf)
{
    ngx_xudp_conf_t             *xcf;
    ngx_cycle_t                 *cycle;
    ngx_http_core_main_conf_t   *cmcf;

    cycle = cf->cycle;

    xcf = (ngx_xudp_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_xudp_core_module);

    cmcf = (ngx_http_core_main_conf_t*) ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    /* get xudp binding address from http configure */
    if (ngx_xudp_get_address_from_http_core_module(xcf, cmcf) != NGX_OK) {
        return  NGX_ERROR;
    }

    return NGX_OK;
}

static char *
ngx_xudp_core_module_init_conf(ngx_cycle_t *cycle, void *conf)
{
    ngx_core_conf_t *ccf;
    ngx_xudp_conf_t *xcf;
    u_char          *c_str;

    xcf = (ngx_xudp_conf_t *) (conf);
    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);

#define NGX_XUDP_RCVNUM  1024
    ngx_conf_init_uint_value(xcf->rcvnum, NGX_XUDP_RCVNUM);
#undef NGX_XUDP_RCVNUM

#define NGX_XUDP_SNDNUM   1024
    ngx_conf_init_uint_value(xcf->sndnum, NGX_XUDP_SNDNUM);
#undef NGX_XUDP_SNDNUM

    if (xcf->no_xudp == NGX_CONF_UNSET) {
        xcf->no_xudp = 0;
    }

    if (xcf->no_xudp_tx == NGX_CONF_UNSET) {
        xcf->no_xudp_tx = 0;
    }

    ngx_conf_init_msec_value(xcf->retries_interval, 200);
    ngx_conf_init_uint_value(xcf->max_retries, 2);

    ngx_xudp_conf.isolate_group = 1;
    ngx_xudp_conf.group_num     = ccf->worker_processes;

    // xudp log info
    ngx_xudp_conf.log_cb    = ngx_xudp_log;
    ngx_xudp_conf.log_level = ngx_xudp_from_ngx_log_level(cycle);

    ngx_xudp_conf.noarp     = 1;
    ngx_xudp_conf.force_xdp = 1;

    ngx_xudp_conf.sndnum    = xcf->sndnum;
    ngx_xudp_conf.rcvnum    = xcf->rcvnum;

    /* for xudp_dump, default to 2MB */
    ngx_xudp_conf.dump_prepare_size = 2 * 1024 * 1024;

    if (xcf->dispatcher_path.data) {
        c_str = ngx_pcalloc(cycle->pool, xcf->dispatcher_path.len + 1);
        if (!c_str) {
            return "nomem";
        }
        ngx_memcpy(c_str, xcf->dispatcher_path.data, xcf->dispatcher_path.len);
        ngx_xudp_conf.map_dict_n_max_pid    = /**true*/ 1;
        ngx_xudp_conf.flow_dispatch         = XUDP_FLOW_DISPATCH_TYPE_CUSTOM;
        ngx_xudp_conf.xdp_custom_path       = (char *) c_str;
    }else {
#if (T_NGX_XQUIC)
        return "xquic over xudp required xquic dispatcher";
#endif
    }

    xcf->on = xcf->xudp_address.nelts && !xcf->no_xudp;
    return NGX_CONF_OK;
}

static ngx_int_t
ngx_xudp_core_module_init_module(ngx_cycle_t *cycle)
{
    int  ret, need_wait;
    ngx_uint_t loop;
    ngx_xudp_conf_t        *xcf;
    xcf = (ngx_xudp_conf_t *)ngx_get_conf(cycle->conf_ctx, ngx_xudp_core_module);

    if (ngx_process != NGX_PROCESS_SINGLE && ngx_process != NGX_PROCESS_MASTER) {
        return NGX_OK;
    }

    need_wait = 0;
    loop  = 0;

    /* free old xudp engine if necessary */
    if (ngx_xudp_engine) {

        /* notify old worker to unbind xudp asap */
        ngx_xudp_signal_worker_process(cycle);

        /* free current ngx_xudp_engine */
        ngx_xudp_free(cycle);

        /* wait old worker for unbinding */
        need_wait = 1;

        ngx_memory_barrier();
    }

    /* just return */
    if (!xcf->on) {
        /* in case of multi master */
        xudp_xdp_clear();
        return NGX_OK;
    }

    do {

        loop++;

        if (need_wait) {
            ngx_msleep(xcf->retries_interval);
        }

        /* try load new xudp engine */
        if (ngx_xudp_load(cycle) == NGX_OK) {
            break;
        }

    }while(need_wait && loop < xcf->max_retries);

    if (ngx_xudp_engine == NULL) {
        goto failed;
    }

    /* has custom dispatcher */
    if (xcf->dispatcher_path.data) {
#if (T_NGX_XQUIC)
        /* required xquic cid route */
        if (ngx_xquic_is_cid_route_on(cycle)) {

            int key = XUDP_XQUIC_MAP_DEFAULT_KEY;
            struct kern_xquic  value = {0};

            value.capture       = 1;
            value.mask          = ngx_xquic_cid_worker_id_secret(cycle);
            value.offset        = ngx_xquic_cid_worker_id_offset(cycle);
            value.salt_range    = ngx_xquic_cid_worker_id_salt_range(cycle);

            /* need compare */
            if (ngx_xudp_xquic_kern_cid_route_info.capture) {
                if (ngx_memcmp(&value, &ngx_xudp_xquic_kern_cid_route_info, sizeof(value)) != 0) {
                    ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                        "|xudp|nginx|update cid route stuff may result in incorrect udp dispatch with old workers");
                    goto failed;
                }
            }
            /* sync */
            memcpy(&ngx_xudp_xquic_kern_cid_route_info, &value, sizeof(value));
            ret = xudp_bpf_map_update(ngx_xudp_engine, XUDP_XQUIC_MAP_NAME, &key , &ngx_xudp_xquic_kern_cid_route_info);
            if (ret != 0) {
                ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                    "|xudp|nginx|update map[%s] xquic failed [xudp_error:%d]", XUDP_XQUIC_MAP_NAME, ret);
                goto failed;
            }
        }else {
            ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "|xudp|nginx|xudp required xquic enable cid route, degrade to system");
            goto failed;
        }
#endif
    }

    return NGX_OK;

    failed:
    ngx_xudp_free(cycle);
    return ngx_xudp_error(xcf, NGX_ERROR);
}

ngx_int_t
ngx_xudp_open_listening_sockets(ngx_cycle_t *cycle)
{
    ngx_xudp_cycle_ctx_t    *ctx;
    ngx_xudp_conf_t         *xcf;
    xcf = (ngx_xudp_conf_t *)ngx_get_conf(cycle->conf_ctx, ngx_xudp_core_module);

    /* no xudp */
    if (ngx_xudp_engine == NULL) {
        return NGX_OK;
    }

    ctx = ngx_palloc(cycle->pool,sizeof(*ctx));
    if (!ctx) {
        // fatal error , ignore degrade
        return NGX_ERROR ;
    }

    do {

        cycle->xudp_ctx = ctx;

        if (ngx_xudp_create_listening_sockets(cycle) != NGX_OK) {
            break;
        }

        if (ngx_xudp_create_address_map(cycle) != NGX_OK) {
            break;
        }

        return NGX_OK;

    }while(0);

    cycle->xudp_ctx = NULL;
    return ngx_xudp_error(xcf, NGX_ERROR);
}


static ngx_int_t
ngx_xudp_core_module_init_process(ngx_cycle_t *cycle)
{
    /**
     * NOTICE
     * xdp socket in the worker needs CAP_NET_RAW and CAP_NET_ADMIN at least
     * nginx with setuid, the worker cannot save any permission
     * 
     * there are three methods:
     * 1. set ngx_xudp_core_module_init_process as a empty function, execute ngx_xudp_open_listening_sockets before setuid
     * 2. for the ngx_xudp_core_module_init_process, execute setuid in the end 
     * 3. save permission during the linux setuid via keep_caps, manage permission of worker
     * 
     * Now, xudp uses the method 1.
     * If nginx supports linux permission mod, the method 3 will be better.
     * */
    return NGX_OK;
    //return ngx_xudp_open_listening_sockets(cycle);
}

static void
ngx_xudp_core_module_exit_process(ngx_cycle_t *cycle)
{
    ngx_xudp_clear(cycle);
}

static void
ngx_xudp_core_module_exit_master(ngx_cycle_t *cycle)
{
    (void) cycle;
    if (ngx_xudp_engine) {
        ngx_log_error(NGX_LOG_NOTICE, ngx_cycle->log, 0, "free xudp");
        ngx_xudp_free(cycle);
    }
}

/** xudp module */

static ngx_http_variable_t  ngx_xudp_vars[] = {

        { ngx_string("xudp"), NULL, ngx_xudp_variable,
                                       0, NGX_HTTP_VAR_NOCACHEABLE, 0 },

        { ngx_null_string, NULL, NULL, 0, 0, 0 }
};

static ngx_http_module_t  ngx_xudp_module_ctx = {
        ngx_xudp_add_http_variables,
        ngx_xudp_http_postconfiguration,

        NULL,
        NULL,

        NULL,
        NULL,

        NULL,
        NULL,
};

ngx_module_t ngx_xudp_module = {
        NGX_MODULE_V1,
        &ngx_xudp_module_ctx,                  /* module context */
        NULL,                                  /* module directives */
        NGX_HTTP_MODULE,                       /* module type */
        NULL,                                  /* init master */
        NULL,                                  /* init module */
        ngx_xudp_module_init_process,          /* init process */
        NULL,                                  /* init thread */
        NULL,                                  /* exit thread */
        NULL,                                  /* exit process */
        NULL,                                  /* exit master */
        NGX_MODULE_V1_PADDING
};

static ngx_int_t
ngx_xudp_add_http_variables(ngx_conf_t *cf)
{
    ngx_http_variable_t  *var, *v;
    for (v = ngx_xudp_vars; v->name.len; v++) {
        var = ngx_http_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }
        var->get_handler = v->get_handler;
        var->data = v->data;
    }
    return NGX_OK;
}

#define NGX_XUDP_STR    "XUDP"
static ngx_int_t
ngx_xudp_variable (ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_connection_t *c;

    c = r->connection;

    if (c->listening && c->listening->xudp) {
        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;
        v->data = (u_char *) NGX_XUDP_STR;
        v->len  = sizeof(NGX_XUDP_STR) - 1;
        return NGX_OK;
    }

    *v = ngx_http_variable_null_value;
    return NGX_OK;
}

#undef NGX_XUDP_STR

static ngx_int_t
ngx_xudp_module_init_process(ngx_cycle_t *cycle)
{
    ngx_listening_t     *ls;
#if (T_DYRELOAD)
    ngx_uint_t           j;
    ngx_listening_t    **lsp;
#endif
    ngx_connection_t    *c;
    ngx_event_t         *rev, *wev;
    size_t               i;

/* for each listening socket */
#if (T_DYRELOAD)
    i = 0;
    lsp = cycle->listening.elts;
    for (j = 0; j < cycle->listening.nelts; j++) {
        ls = lsp[j];
#else
    ls = cycle->listening.elts;
    for (i = 0; i < cycle->listening.nelts; i++) {
#endif

#if (T_PROCESS_IDX)
        if (ls[i].proc_idx &&ls[i].proc_idx != ngx_process_idx) {
            continue;
        }
#endif

        if (!ls[i].for_xudp || ls[i].worker != ngx_worker) {
            continue;
        }

        c   = ls[i].connection;
        rev = c->read;
        wev = c->write;

        rev->handler        = ngx_event_xudp_recvmsg ;
        wev->handler        = ngx_udpv2_write_handler_mainlogic;

        wev->log            = c->log;

        if (xudp_channel_is_tx(ls[i].ngx_xudp_ch->ch)) {
            cycle->xudp_ctx->tx = &ls[i];
        }

    }

    return NGX_OK;
}

static void
ngx_xudp_flush_send_data(ngx_event_t *ev)
{
    xudp_commit_channel((xudp_channel*)(ev->data));
}

static ngx_xudp_port_map_node_t*
ngx_xudp_get_or_create_ports_map(ngx_pool_t *pool, ngx_radix_tree_t *ports_map, u16 port)
{
    ngx_xudp_port_map_node_t    *v;
    /* find */
    v = (ngx_xudp_port_map_node_t *) ngx_radix32tree_find(ports_map, port);
    if (v == (void *) NGX_RADIX_NO_VALUE) {
        /* create */
        v = ngx_palloc(pool, sizeof(*v));
        if (v == NULL) {
            return NULL;
        }
        /* init */
        v->regular = NULL;
        ngx_queue_init(&v->wildcard);
        /* map port*/
        ngx_radix32tree_insert(ports_map, port, NGX_RADIX32_MASK, (uintptr_t) v);
    }
    return v;
}

static ngx_int_t
ngx_xudp_built_address_map(ngx_pool_t *pool, ngx_radix_tree_t *ports_map, ngx_listening_t *ls)
{
    ngx_xudp_port_map_node_t    *v;
    struct sockaddr_in          *addr;
#if (NGX_HAVE_INET6)
    u_char                     *p;
    struct sockaddr_in6         *addr6;
#endif
    ngx_queue_t                 *q = NULL;

    if (ls->sockaddr->sa_family == AF_INET) {

        addr = (struct sockaddr_in *)ls->sockaddr;
        /* get ports map */
        v = ngx_xudp_get_or_create_ports_map(pool, ports_map, ntohs(addr->sin_port));
        if (v == NULL) {
            return NGX_ERROR;
        }

        if (addr->sin_addr.s_addr == INADDR_ANY) {
            q = &v->wildcard;
        } else {
            if (v->regular == NULL) {
                v->regular = ngx_radix_tree_create(pool, NGX_CONF_MAX_ARGS);
                if (!v->regular) {
                    return NGX_ERROR;
                }
            }
            q = (void*) ngx_radix32tree_find(v->regular, addr->sin_addr.s_addr);
            if (q == (void*) NGX_RADIX_NO_VALUE) {
                /* create */
                q = ngx_palloc(pool, sizeof(*q));
                if (q == NULL) {
                    return NGX_ERROR;
                }
                ngx_queue_init(q);
                ngx_radix32tree_insert(v->regular, addr->sin_addr.s_addr, NGX_RADIX32_MASK, (uintptr_t) q);
            }
        }
    } else
#if (NGX_HAVE_INET6)
        if (ls->sockaddr->sa_family == AF_INET6)
    {
        addr6 = (struct sockaddr_in6 *)ls->sockaddr;
        p = addr6->sin6_addr.s6_addr;
        /* get ports map */
        v = ngx_xudp_get_or_create_ports_map(pool, ports_map, ntohs(addr6->sin6_port));
        if (v == NULL) {
            return NGX_ERROR;
        }

        if (IN6_IS_ADDR_UNSPECIFIED(&addr6->sin6_addr)) {
            q = &v->wildcard;
        } else {

            if (v->regular == NULL) {
                v->regular = ngx_radix_tree_create(pool, NGX_CONF_MAX_ARGS);
                if (!v->regular) {
                    return NGX_ERROR;
                }
            }

            q = (void*) ngx_radix128tree_find(v->regular, p);
            if (q == (void*) NGX_RADIX_NO_VALUE) {
                /* create */
                q = ngx_palloc(pool,sizeof(*q));
                if (q == NULL) {
                    return NGX_ERROR;
                }
                ngx_queue_init(q);
                ngx_radix128tree_insert(v->regular, p, NGX_RADIX128_MASK, (uintptr_t) q);
            }
        }
    } else
#endif
    {}
    ngx_log_error(NGX_LOG_NOTICE, ngx_cycle->log, 0,"|xudp|add fd %d to xudp|", ls->fd);
    /* add to list */
    if (q) {
        ngx_queue_insert_tail(q, &ls->xudp_sentinel);
    } else {
        return NGX_ERROR;
    }
    return NGX_OK;
}

static ngx_int_t
ngx_xudp_create_address_map(ngx_cycle_t *cycle)
{
    ngx_radix_tree_t    *ports_map;
    size_t               i;
    ngx_listening_t     *ls ;
#if (T_DYRELOAD)
    ngx_uint_t           j;
    ngx_listening_t    **lsp;
#endif

    ports_map = ngx_radix_tree_create(cycle->pool, NGX_CONF_MAX_ARGS);
    if (!ports_map) {
        return NGX_ERROR;
    }

    i = 0 ;

    /* for each listening socket */
#if (T_DYRELOAD)
    i = 0;
    lsp = cycle->listening.elts;
    for (j = 0; j < cycle->listening.nelts; j++) {
        ls = lsp[j];
#else
    ls = cycle->listening.elts;
    for (i = 0; i < cycle->listening.nelts; i++) {
#endif

#if (T_PROCESS_IDX)
        if (ls[i].proc_idx &&ls[i].proc_idx != ngx_process_idx) {
            continue;
        }
#endif

#if ! (T_RELOAD)
#if (NGX_HAVE_REUSEPORT)
        if (ls[i].reuseport && ls[i].worker != ngx_worker) {
            continue;
        }
#endif
#endif

        if (!ls[i].xudp) {
            continue;
        }

        if (ngx_xudp_built_address_map(cycle->pool, ports_map, &ls[i]) != NGX_OK) {
            return NGX_ERROR;
        }
        ls[i].support_udpv2 = 1;
    }

    cycle->xudp_ctx->ports_map = ports_map;
    return NGX_OK ;
}

static ngx_int_t
ngx_xudp_create_listening_sockets(ngx_cycle_t *cycle)
{
    ngx_conf_t           cf;
    struct sockaddr_in  *xsk_addr;
    ngx_listening_t     *ls;
    xudp_channel        *ch;
    ngx_xudp_channel_t  *xudp_ch;
    ngx_pid_t            pid;
    xudp_group          *group;

    xsk_addr = ngx_pcalloc(cycle->pool, sizeof(*xsk_addr));
    if (!xsk_addr) {
        return NGX_ERROR;
    }

    pid = getpid();

    xsk_addr->sin_family = AF_UNSPEC;

    //mock cf
    cf.cycle = cycle;
    cf.log   = cycle->log;
    cf.pool  = cycle->pool;

    group =  xudp_group_new(ngx_xudp_engine, ngx_worker);
    if (group == NULL) {
        ngx_xudp_stop(cycle);
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "|xudp|nginx|xudp_group_new fail");
        goto failed;
    }

    xudp_group_channel_foreach(ch, group) {

        xudp_ch = ngx_palloc(cycle->pool, sizeof(ngx_xudp_channel_t));
        if (!xudp_ch) {
            ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "|xudp|nginx|palloc xudp_channels fail");
            goto failed;
        }

        xudp_ch->ch = ch ;
        xudp_ch->commit.handler = ngx_xudp_flush_send_data ;
        xudp_ch->commit.data    = ch ;
        xudp_ch->commit.log     = cycle->log;

        ls              = ngx_create_listening(&cf, (struct sockaddr *) xsk_addr, sizeof(*xsk_addr));
        if (!ls) {
            goto failed;
        }

        ls->fd          = xudp_channel_get_fd(ch);
        ls->type        = SOCK_DGRAM;
        ls->listen      = 1;
        ls->for_xudp    = 1;
        ls->worker      = xudp_channel_get_groupid(ch);
        ls->logp        = cycle->log;
        // protect against load balancing
        ls->reuseport   = 1 ;
        ls->ngx_xudp_ch = xudp_ch;
        ngx_log_error(NGX_LOG_INFO, cycle->log, 0, "|xudp|nginx|init[sockfd:%d] success", ls->fd);
    }

    // set group key
    xudp_dict_set_group_key(group, pid);
    cycle->xudp_ctx->group = group;
    return NGX_OK;
    failed:
    if (group != NULL) {
        xudp_group_free(group);
    }
    return NGX_ERROR;
}

static int
ngx_xudp_log(char *buf, int size, void *data)
{
    char buffer [size + 1] ;
    memcpy(buffer, buf, size);
    buffer[size] = '\0';
    /** .*s is not work in ngx_log */
    ngx_log_error(NGX_LOG_NOTICE, ngx_cycle->log, 0, "|xudp|libs|[%s]",buffer);
    return size ;
}

static ngx_int_t
ngx_xudp_load(ngx_cycle_t *cycle)
{
    size_t              sz, ret;
    ngx_sockaddr_t     *addr;
    ngx_xudp_conf_t    *xcf;

    xcf    = (ngx_xudp_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_xudp_core_module);

    sz     = xcf->xudp_address.nelts;
    addr   = (ngx_sockaddr_t*) xcf->xudp_address.elts;

    if (ngx_xudp_engine == NULL) {
        ngx_xudp_engine = xudp_init(&ngx_xudp_conf, sizeof(ngx_xudp_conf));
        if (!ngx_xudp_engine) {
            ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "|xudp|nginx|create failed");
            goto error;
        }
        ret = xudp_bind(ngx_xudp_engine, (struct sockaddr*) addr, sizeof(ngx_sockaddr_t), sz);
        if (ret != 0) {
            ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "|xudp|nginx|bind failed, degrade to system udp [xudp_error:%d]", ret);
            goto error;
        }
    }
    return NGX_OK;
    error:
    ngx_xudp_free(cycle);
    return NGX_ERROR;
}

static void
ngx_xudp_stop(ngx_cycle_t *cycle)
{
    int key = 0;
    ngx_xudp_xquic_kern_cid_route_info.capture = 0 ;
    xudp_bpf_map_update(ngx_xudp_engine, XUDP_XQUIC_MAP_NAME, &key , &ngx_xudp_xquic_kern_cid_route_info);
    return;
}

static xudp *
ngx_xudp_clear(ngx_cycle_t *cycle)
{
    xudp *engine;
    engine = ngx_xudp_engine;
    ngx_xudp_engine = NULL;

    if (cycle->xudp_ctx) {
        if (cycle->xudp_ctx->group) {
            xudp_group_free(cycle->xudp_ctx->group);
            cycle->xudp_ctx->group = NULL;
        }
        cycle->xudp_ctx = NULL;
    }

    return engine;
}

static void
ngx_xudp_free(ngx_cycle_t *cycle)
{
    xudp *engine;
    engine = ngx_xudp_clear(cycle);
    if (engine) {
        xudp_free(engine);
    }
}

static ngx_listening_t *
ngx_xudp_find_listening(ngx_listening_t *xudp_ls, const struct sockaddr *sa)
{
    ngx_listening_t *ls;
    ngx_queue_t     *q;
    ngx_radix_tree_t *ports_map;
    ngx_xudp_port_map_node_t * m;
    struct sockaddr_in      *addr = NULL;
#if (NGX_HAVE_INET6)
    u_char                  *p;
    struct sockaddr_in6     *addr6 = NULL;
#endif // NGX_HAVE_INET6
    int port ;

    if (sa->sa_family == AF_INET) {
        addr = (struct sockaddr_in *) sa ;
        port = ntohs(addr->sin_port);
    }else
#if (NGX_HAVE_INET6)
        if (sa->sa_family == AF_INET6) {
        addr6 = (struct sockaddr_in6 *) sa ;
        port  = ntohs(addr6->sin6_port);
    }else
#endif
    {
        return NULL ;
    }

    q = (void*) NGX_RADIX_NO_VALUE;
    ports_map = ngx_cycle->xudp_ctx->ports_map;

    m = (void*) ngx_radix32tree_find(ports_map, port);
    if (m == (void*) NGX_RADIX_NO_VALUE) {
        return NULL ;
    }

    if (m->regular) {
        if (sa->sa_family == AF_INET) {
            q = (void*) ngx_radix32tree_find(m->regular, addr->sin_addr.s_addr);
        }else
#if (NGX_HAVE_INET6)
            if (sa->sa_family == AF_INET6) {
            p = addr6->sin6_addr.s6_addr;
            q = (void*) ngx_radix128tree_find(m->regular, p);
        }
#endif
        if (q == (void*)NGX_RADIX_NO_VALUE) {
            q = &m->wildcard;
        }
    }else {
        q = &m->wildcard;
    }

    /* unlikey */
    if (ngx_queue_empty(q)) {
        return NULL;
    }

    ngx_queue_t *h = ngx_queue_head(q);
    ls = ngx_queue_data(h, ngx_listening_t, xudp_sentinel);
    ngx_queue_remove(h);
    ngx_queue_insert_tail(q, h);

    return ls;
}

static inline socklen_t
ngx_xudp_copy_addr(ngx_sockaddr_t *dest, const struct sockaddr *source)
{
    switch(source->sa_family)
    {
        case AF_INET:
            memcpy(dest, source, sizeof(struct sockaddr_in));
            return sizeof(struct sockaddr_in);
        case AF_INET6:
            memcpy(dest, source, sizeof(struct sockaddr_in6));
            return sizeof(struct sockaddr_in6);
        default:
            break;
    }
    /* unkown address family */
    return 0;
}

static void
xudp_redirect_udpv2(ngx_listening_t *ls, ngx_udpv2_packets_hdr_t *urphdr, xudp_msg *msg)
{
    ngx_listening_t     *target;
    ngx_udpv2_packet_t  *upkt;

    upkt = NGX_UDPV2_PACKETS_HDR_FIRST_PACKET(urphdr);

    target = ngx_xudp_find_listening(ls, (struct sockaddr *)&msg->local_addr);

    if (target != NULL) {

        urphdr->ls = target;

        upkt->pkt_socklen        = ngx_xudp_copy_addr(&upkt->pkt_sockaddr, (struct sockaddr*) &msg->peer_addr);
        upkt->pkt_local_socklen  = ngx_xudp_copy_addr(&upkt->pkt_local_sockaddr, (struct sockaddr*) &msg->local_addr);

        upkt->pkt_sz             = msg->size;
        upkt->pkt_payload        = (u_char*) msg->p;

        urphdr->npkts = 1;
        ngx_udpv2_dispatch_traffic(urphdr);
        urphdr->npkts = 0;

    } else {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "|xudp|nginx|ngx_xudp_find_listening failed");
    }
}

static void
ngx_event_xudp_recvmsg(ngx_event_t *rev)
{
    ngx_connection_t *c ;
    ngx_listening_t  *ls;
    int n, i, j;

    ngx_udpv2_packets_hdr_t urphdr = NGX_UDPV2_PACKETS_HDR_INIT(urphdr);
    ngx_udpv2_packet_t upkt;

    /* handle traffic balance */
    if (rev->timedout) {
        if (ngx_enable_accept_events((ngx_cycle_t *) ngx_cycle) != NGX_OK) {
            return;
        }
        rev->timedout = 0;
    }

    c = (ngx_connection_t *) (rev->data);
    ls = c->listening;
    xudp_def_msg(hdr, 32);

    NGX_UDPV2_PACKETS_HDR_ADD_PACKET(&urphdr, &upkt);
    upkt.pkt_micrs = 0 ;

    do {

        n = xudp_recv_channel(ls->ngx_xudp_ch->ch, hdr, 0);
        ngx_log_error(NGX_LOG_INFO, ngx_cycle->log, 0, "|xudp|nginx|ngx_event_xudp_recvmsg recv[n=%d]",n);

        if (n <= 0) {
            break ;
        }

        j = hdr->used - 1;

        for(i = 0; i < j; i++) {
            __builtin_prefetch(&hdr->msg[i + 1]);
            __builtin_prefetch(hdr->msg[i + 1].p);
            xudp_redirect_udpv2(ls, &urphdr, &hdr->msg[i]);
        }

        if (j >= 0) {
            xudp_redirect_udpv2(ls, &urphdr, &hdr->msg[j]);
        }

        xudp_recycle(hdr);

    }while(1);

    ngx_udpv2_process_posted_traffic();
}

static int
ngx_xudp_from_ngx_log_level(ngx_cycle_t *cycle)
{
    ngx_uint_t lev;
    if (cycle->log) {
        lev = cycle->log->log_level;
        if (lev <= NGX_LOG_ERR) {
            return XUDP_LOG_ERR;
        }else if(lev <= NGX_LOG_WARN) {
            return XUDP_LOG_WARN;
        }else if(lev <= NGX_LOG_INFO) {
            return XUDP_LOG_INFO;
        }else if(lev == NGX_LOG_DEBUG) {
            return XUDP_LOG_DEBUG;
        }
    }
    return XUDP_LOG_ERR;
}

ngx_int_t
ngx_xudp_error_is_fatal(int error)
{
    if (error == -XUDP_ERR_CQ_NOSPACE || error == -XUDP_ERR_TX_NOSPACE) {
        return 0;
    }
    return 1;
}

/**
 * @param c
 * @return  enable connection for xudp tx
 * */
void
ngx_xudp_enable_tx(ngx_connection_t *c)
{
    ngx_xudp_conf_t     *xcf;
    xcf = (ngx_xudp_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx, ngx_xudp_core_module);
    if (!ngx_xudp_engine || xcf->no_xudp_tx) {
        return ;
    }
    if (c->listening && c->listening->xudp) {
        c->xudp_tx = 1;
    }
}

void
ngx_xudp_terminate_xudp_binding(ngx_cycle_t *cycle)
{
    ngx_uint_t         i;
    ngx_listening_t   *ls;
    ngx_connection_t  *c;
#if (T_DYRELOAD)
    ngx_uint_t         j;
    ngx_listening_t  **lsp;
#endif
    xudp               *engine;

    if (!ngx_xudp_engine) {
        return;
    }

    /* reset global ngx_xudp_engine */
    engine  = ngx_xudp_clear(cycle);
    ngx_memory_barrier();

    i = 0;

    /* for each listening socket */
#if (T_DYRELOAD)
    i = 0;
    lsp = cycle->listening.elts;
    for (j = 0; j < cycle->listening.nelts; j++) {
        ls = lsp[j];
#else
    ls = cycle->listening.elts;
    for (i = 0; i < cycle->listening.nelts; i++) {
#endif

#if (T_PROCESS_IDX)
        if (ls[i].proc_idx &&ls[i].proc_idx != ngx_process_idx) {
            continue;
        }
#endif

#if ! (T_RELOAD)
#if (NGX_HAVE_REUSEPORT)
        if (ls[i].reuseport && ls[i].worker != ngx_worker) {
            continue;
        }
#endif
#endif

        if (!ls[i].for_xudp) {
            continue;
        }

        if (ls[i].worker != ngx_worker) {
            continue;
        }

        if (ls[i].fd == (ngx_socket_t) -1) {
            continue;
        }

        c = ls[i].connection;
        if (c) {

            if (c->read->active) {
                ngx_del_event(c->read, NGX_READ_EVENT, 0);
            }

            if (c->write->active) {
                /**
                 * trigger all the events that run on this event
                 * because the ngx_xudp_engine has been cleared in advance,
                 * xudp send will be failed
                 * trigger degrade at last
                 * */
                ngx_event_process_posted((ngx_cycle_t *) ngx_cycle, &ls[i].writable_queue);
                /* del from event poll */
                ngx_del_event(c->read, NGX_WRITE_EVENT, 0);
            }

            c->fd = (ngx_socket_t) -1;
            ngx_free_connection(c);
            ls[i].connection = NULL;
        }

        if (ngx_close_socket(ls[i].fd) == -1) {
            ngx_log_error(NGX_LOG_DEBUG, cycle->log, ngx_socket_errno,
                          "close xudp socket() %V failed ", &ls[i].addr_text);
        }

        ls[i].fd = (ngx_socket_t) -1;
    }

    /* call unbind */
    xudp_unbind(engine);
}
