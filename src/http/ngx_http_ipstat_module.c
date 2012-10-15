#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_channel.h>

#include <ngx_http_ipstat_module.h>


#define NGX_CMD_IPSTAT     (NGX_CMD_USER + 1)


typedef struct {
    uintptr_t              key;
    unsigned               ipv6:1;
    unsigned               port:16;
} ngx_http_ipstat_vip_index_t;


typedef struct {
    ngx_cycle_t           *cycle;
    void                  *data;
} ngx_http_ipstat_zone_ctx_t;


typedef enum {
    op_count,
    op_min,
    op_max,
    op_avg,
    op_rate,
    op_ts_min,
    op_ts_max
} ngx_http_ipstat_op_t;


typedef struct {
    off_t                  offset;
    ngx_http_ipstat_op_t   type;
} ngx_http_ipstat_field_t;


typedef struct {
    ngx_channel_t          channel;
    uintptr_t              dst;
    ngx_http_ipstat_vip_t  val;
} ngx_http_ipstat_channel_t;


typedef struct {
    ngx_shmtx_sh_t         shmtx;
    ngx_shmtx_t            mutex;
    ngx_uint_t             workers;
    ngx_uint_t             num;
    time_t                 rt_interval;
    time_t                 rt_unit;
    size_t                 index_size;
    size_t                 block_size;
} ngx_http_ipstat_zone_hdr_t;


#define VIP_INDEX_START(start)                                            \
    ((ngx_http_ipstat_vip_index_t *)                                      \
        ((char *) (start) + sizeof(ngx_pid_t)))

#define VIP_FIELD(vip, offset) ((ngx_uint_t *) ((char *) vip + offset))

#define VIP_LOCATE(start, boff, voff, off)                                \
    ((ngx_http_ipstat_vip_t *)                                            \
         ((char *) (start) + (boff) + (voff)                              \
                           + sizeof(ngx_http_ipstat_vip_t) * (off)))

#define VIP_HEADER(content)                                               \
    ((ngx_http_ipstat_zone_hdr_t *) ((char *) (content)                   \
        - ngx_align(sizeof(ngx_http_ipstat_zone_hdr_t), 128)))

#define VIP_CONTENT(header)                                               \
    ((void *) ((char *) (header)                                          \
        + ngx_align(sizeof(ngx_http_ipstat_zone_hdr_t), 128)))

#define VIP_PID(start, boff)                                              \
    ((ngx_pid_t *) ((char *) (start) + boff))


static ngx_str_t vip_zn = ngx_string("vip_status_zone");

static ngx_channel_handler_pt ngx_channel_next_handler;


static ngx_http_ipstat_field_t fields[] = {
    { NGX_HTTP_IPSTAT_CONN_TOTAL, op_count },
    { NGX_HTTP_IPSTAT_CONN_CURRENT, op_count },
    { NGX_HTTP_IPSTAT_REQ_TOTAL, op_count },
    { NGX_HTTP_IPSTAT_REQ_CURRENT, op_count },
    { NGX_HTTP_IPSTAT_BYTES_IN, op_count },
    { NGX_HTTP_IPSTAT_BYTES_OUT, op_count },
    { NGX_HTTP_IPSTAT_RT_MIN, op_ts_min },
    { NGX_HTTP_IPSTAT_RT_MAX, op_ts_max },
    { NGX_HTTP_IPSTAT_RT_AVG, op_avg },
    { NGX_HTTP_IPSTAT_CONN_RATE, op_rate },
    { NGX_HTTP_IPSTAT_REQ_RATE, op_rate }
};


static const ngx_uint_t field_num = sizeof(fields)
                                  / sizeof(ngx_http_ipstat_field_t);

static const size_t channel_len = sizeof(ngx_http_ipstat_channel_t)
                                - offsetof(ngx_http_ipstat_channel_t, dst);


static void *ngx_http_ipstat_create_main_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_ipstat_init(ngx_conf_t *cf);
static ngx_int_t ngx_http_ipstat_init_vip_zone(ngx_shm_zone_t *shm_zone,
    void *data);
static ngx_int_t ngx_http_ipstat_init_process(ngx_cycle_t *cycle);
static ngx_int_t ngx_http_ipstat_log_handler(ngx_http_request_t *r);
static void ngx_http_ipstat_merge_old_cycles(void *data);

static void
    ngx_http_ipstat_insert_vip_index(ngx_http_ipstat_vip_index_t *start,
    ngx_http_ipstat_vip_index_t *end, ngx_http_ipstat_vip_index_t *insert);
static ngx_http_ipstat_vip_index_t *
    ngx_http_ipstat_lookup_vip_index(ngx_uint_t key,
    ngx_http_ipstat_vip_index_t *start, ngx_http_ipstat_vip_index_t *end);
static ngx_uint_t
    ngx_http_ipstat_distinguish_same_vip(ngx_http_ipstat_vip_index_t *key,
    ngx_cycle_t *old_cycle);
static void ngx_http_ipstat_merge_val(ngx_http_ipstat_vip_t *dst,
    ngx_http_ipstat_vip_t *src);
static void ngx_http_ipstat_eval_rt_unit(ngx_http_ipstat_main_conf_t *conf);
static void ngx_http_ipstat_init_ts(ngx_http_ipstat_vip_t *vip,
    ngx_http_ipstat_field_t *fields, ngx_uint_t num, time_t itv, time_t unit);

static void ngx_http_ipstat_notify(ngx_pid_t pid, ngx_http_ipstat_vip_t *src,
    ngx_http_ipstat_vip_t *dst);
static void ngx_http_ipstat_channel_handler(ngx_channel_t *ch, u_char *buf,
    size_t len, ngx_log_t *log);

static char *ngx_http_ipstat_show(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_ipstat_show_handler(ngx_http_request_t *r);


static ngx_command_t   ngx_http_ipstat_commands[] = {

    { ngx_string("vip_status_show"),
      NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
      ngx_http_ipstat_show,
      0,
      0,
      NULL },

    { ngx_string("vip_rt_interval"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_sec_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_ipstat_main_conf_t, rt_interval),
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_ipstat_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_http_ipstat_init,                  /* postconfiguration */

    ngx_http_ipstat_create_main_conf,      /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};


ngx_module_t  ngx_http_ipstat_module = {
    NGX_MODULE_V1,
    &ngx_http_ipstat_module_ctx,           /* module context */
    ngx_http_ipstat_commands,              /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    ngx_http_ipstat_init_process,          /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static void *
ngx_http_ipstat_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_ipstat_main_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_ipstat_main_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    conf->rt_interval = NGX_CONF_UNSET;

    return conf;
}


static ngx_int_t
ngx_http_ipstat_init(ngx_conf_t *cf)
{
    size_t                        size;
    ngx_int_t                     workers;
    ngx_uint_t                    i, n;
    ngx_shm_zone_t               *shm_zone;
    ngx_core_conf_t              *ccf;
    ngx_http_handler_pt          *h;
    ngx_http_conf_port_t         *port;
    ngx_http_core_main_conf_t    *cmcf;
    ngx_http_ipstat_zone_ctx_t   *ctx;
    ngx_http_ipstat_main_conf_t  *smcf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cf->cycle->conf_ctx,
                                           ngx_core_module);
    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);
    smcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_ipstat_module);

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_ipstat_zone_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_conf_init_value(smcf->rt_interval, 60);
    ngx_http_ipstat_eval_rt_unit(smcf);

    port = cmcf->ports->elts;
    for (i = 0, n = 0; i < cmcf->ports->nelts; i++) {
        n += port[i].addrs.nelts;
    }

    /* comparible to cpu affinity */

    workers = ccf->worker_processes;

    if (workers == NGX_CONF_UNSET || workers == 0) {
        workers = ngx_ncpu;
    }

    smcf->workers = workers;
    smcf->num = n;
    smcf->index_size = sizeof(ngx_http_ipstat_vip_index_t) * n
                     + sizeof(ngx_pid_t);
    size = sizeof(ngx_http_ipstat_vip_t) * n + smcf->index_size;
    smcf->block_size = ngx_align(size, 128);
    size = ngx_align(sizeof(ngx_http_ipstat_zone_hdr_t), 128)
         + smcf->block_size * smcf->workers;

    ngx_log_debug6(NGX_LOG_DEBUG_HTTP, cf->log, 0,
                   "ipstat_init: cycle=%p, workers=%ui, num=%ui, "
                   "index_size=%z, block_size=%z, size=%z",
                   cf->cycle, smcf->workers, smcf->num,
                   smcf->index_size, smcf->block_size, size);

    shm_zone = ngx_shm_cycle_add(cf, &vip_zn, size,
                                 &ngx_http_ipstat_module, 0);

    if (shm_zone == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "failed to alloc shared memory");
        return NGX_ERROR;
    }

    if (shm_zone->data) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "the vip status zone already exists");
        return NGX_ERROR;
    }

    ctx->cycle = cf->cycle;
    shm_zone->data = ctx;
    shm_zone->init = ngx_http_ipstat_init_vip_zone;
    smcf->vip_zone = shm_zone;

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_LOG_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_ipstat_log_handler;

    ngx_channel_next_handler = ngx_channel_top_handler;
    ngx_channel_top_handler = ngx_http_ipstat_channel_handler;

    ngx_shm_cycle_add_cleanup(&vip_zn, ngx_http_ipstat_merge_old_cycles);

    return NGX_OK;
}


static void
ngx_http_ipstat_insert_vip_index(ngx_http_ipstat_vip_index_t *start,
    ngx_http_ipstat_vip_index_t *end, ngx_http_ipstat_vip_index_t *insert)
{
    while (insert->key > start->key && start < end) {
        ++start;
    }

    while (end > start) {
        *end = *(end - 1);
        --end;
    }

    *start = *insert;
}


static ngx_http_ipstat_vip_index_t *
ngx_http_ipstat_lookup_vip_index(ngx_uint_t key,
    ngx_http_ipstat_vip_index_t *start, ngx_http_ipstat_vip_index_t *end)
{
    ngx_http_ipstat_vip_index_t  *mid;

    while (start < end) {
        mid = start + (end - start) / 2;

        if (mid->key == key) {
            return mid;
        } else if (mid->key < key) {
            start = mid + 1;
        } else {
            end = mid;
        }
    }

    return NULL;
}


/**
 * In this function, we divide the zone into pieces,
 * whose number equals the number of worker processes.
 * Each worker uses a piece independantly, so no mutex is needed.
 * Each piece aligns at 128 byte address so that when cpu affinity is set,
 * no cpu cache line overlap occurs.
 */

static ngx_int_t
ngx_http_ipstat_init_vip_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_uint_t                    i, j, n, okey;
    ngx_listening_t              *ls;
    ngx_http_port_t              *port;
    ngx_http_in_addr_t           *addr;
#if (NGX_HAVE_INET6)
    ngx_http_in6_addr_t          *addr6;
#endif
    ngx_http_ipstat_vip_t        *vip, *ovip;
    ngx_http_ipstat_zone_ctx_t   *ctx, *octx;
    ngx_http_ipstat_zone_hdr_t   *hdr;
    ngx_http_ipstat_main_conf_t  *smcf, *osmcf;
    ngx_http_ipstat_vip_index_t  *idx, *oidx, key, *oidx_c;

    ctx = (ngx_http_ipstat_zone_ctx_t *) shm_zone->data;
    smcf = ngx_http_cycle_get_module_main_conf(ctx->cycle,
                                               ngx_http_ipstat_module);

    ngx_memzero(shm_zone->shm.addr, shm_zone->shm.size);

    hdr = (ngx_http_ipstat_zone_hdr_t *) shm_zone->shm.addr;

    if (ngx_shmtx_create(&hdr->mutex, &hdr->shmtx, ctx->cycle->lock_file.data)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    hdr->workers = smcf->workers;
    hdr->num = smcf->num;
    hdr->rt_unit = smcf->rt_unit;
    hdr->rt_interval = smcf->rt_interval;
    hdr->index_size = smcf->index_size;
    hdr->block_size = smcf->block_size;

    ngx_log_debug7(NGX_LOG_DEBUG_HTTP, shm_zone->shm.log, 0,
                   "ipstat_init_zone(current hdr %p): "
                   "workers=%ui, num=%ui, index_size=%z, block_size=%z, "
                   "rt_interval=%T, rt_unit=%T",
                   hdr, hdr->workers, hdr->num,
                   hdr->index_size, hdr->block_size,
                   hdr->rt_interval, hdr->rt_unit);

    ctx->data = VIP_CONTENT(shm_zone->shm.addr);
    ls = ctx->cycle->listening.elts;
    idx = VIP_INDEX_START(ctx->data);
    
    for (i = 0, n = 0; i < ctx->cycle->listening.nelts; i++) {

        port = ls[i].servers;
        key.ipv6 = 0;
        key.port = port->port;
        addr = NULL;

#if (NGX_HAVE_INET6)
        addr6 = NULL;

        if (port->ipv6) {
            key.ipv6 = 1;
        }
#endif

        if (port->naddrs > 1) {

#if (NGX_HAVE_INET6)
            if (port->ipv6) {
                addr6 = port->addrs;

            } else {
#endif
                addr = port->addrs;

#if (NGX_HAVE_INET6)
            }
#endif

            for (j = 0; j < port->naddrs; j++) {

#if (NGX_HAVE_INET6)
                if (port->ipv6) {
                    key.key = (uintptr_t) &addr6[j];

                } else {
#endif
                    key.key = (uintptr_t) &addr[j];

#if (NGX_HAVE_INET6)
                }
#endif
                ngx_http_ipstat_insert_vip_index(idx, idx + (n++), &key);
            }

        } else {
            key.key = (uintptr_t) port->addrs;
            ngx_http_ipstat_insert_vip_index(idx, idx + (n++), &key);
        }
    }

    /* init time slice statistics structure */

    vip = VIP_LOCATE(ctx->data, 0, smcf->index_size, 0);
    for (j = 0; j < n; vip++, j++) {
        ngx_http_ipstat_init_ts(vip, fields, field_num,
                                smcf->rt_interval, smcf->rt_unit);
    }

    for (i = 1; i < (ngx_uint_t) smcf->workers; i++) {
        ngx_memcpy((char *) ctx->data + i * smcf->block_size, ctx->data,
                   smcf->block_size);
    }

    /* build vip chain */

    if (data == NULL) {
        return NGX_OK;
    }

    octx = data;
    oidx = VIP_INDEX_START(octx->data);
    osmcf = ngx_http_cycle_get_module_main_conf(octx->cycle,
                                                ngx_http_ipstat_module);
    for (i = 0; i < n; ++i, ++idx) {
        okey = ngx_http_ipstat_distinguish_same_vip(idx, octx->cycle);
        if (okey == 0) {
            continue;
        }

        oidx_c = ngx_http_ipstat_lookup_vip_index(okey, oidx,
                                                  oidx + osmcf->num);
        if (oidx_c == NULL) {
            continue;
        }

        vip = VIP_LOCATE(ctx->data, 0, smcf->index_size, i);
        ovip = VIP_LOCATE(octx->data, 0, osmcf->index_size, oidx_c - oidx);
        vip->prev = ovip;
    }

    return NGX_OK;
}


static ngx_uint_t
ngx_http_ipstat_distinguish_same_vip(ngx_http_ipstat_vip_index_t *key,
    ngx_cycle_t *old_cycle)
{
    ngx_uint_t                    i, j;
    ngx_listening_t              *ls;
    ngx_http_port_t              *port;

    ngx_http_in_addr_t           *oaddr, *addr;
#if (NGX_HAVE_INET6)
    ngx_http_in6_addr_t          *oaddr6, *addr6;
#endif

    addr = NULL;

#if (NGX_HAVE_INET6)
    addr6 = NULL;
#endif

    switch (key->ipv6) {
#if (NGX_HAVE_INET6)
    case 1:
        addr6 = (ngx_http_in6_addr_t *) key->key;
        break;
#endif
    default:
        addr = (ngx_http_in_addr_t *) key->key;
        break;
    }

    ls = old_cycle->listening.elts;

    for (i = 0; i < old_cycle->listening.nelts; i++) {

        port = ls[i].servers;

        if (port->port != key->port) {
            continue;
        }

#if (NGX_HAVE_INET6)
        if (port->ipv6 != key->ipv6) {
            continue;
        }
#endif

        if (port->naddrs > 1) {
            switch (key->ipv6) {

#if (NGX_HAVE_INET6)
            case 1:
                oaddr6 = port->addrs;

                for (j = 0; j + 1 < port->naddrs; i++) {
                    if (ngx_memcmp(&oaddr6[j].addr6, &addr6->addr6, 16) == 0) {
                        break;
                    }
                }

                return (uintptr_t) &oaddr6[j];
#endif
            default:
                oaddr = port->addrs;

                for (j = 0; j + 1 < port->naddrs; j++) {
                    if (oaddr[j].addr == addr->addr) {
                        break;
                    }
                }

                return (uintptr_t) &oaddr[j];
            }

        } else {
            switch (key->ipv6) {

#if (NGX_HAVE_INET6)
            case 1:
                oaddr6 = port->addrs;

                if (ngx_memcmp(&oaddr6->addr6, &addr6->addr6, 16) == 0) {
                    return (uintptr_t) oaddr6;
                }

                break;
#endif
            default:
                oaddr = port->addrs;

                if (oaddr->addr == addr->addr) {
                    return (uintptr_t) oaddr;
                }

                break;
            }

            return 0;
        }
    }

    return 0;
}


static ngx_int_t
ngx_http_ipstat_init_process(ngx_cycle_t *cycle)
{
    ngx_pid_t                    *ppid;
    ngx_uint_t                    i, j;
    ngx_http_ipstat_zone_ctx_t   *ctx;
    ngx_http_ipstat_zone_hdr_t   *hdr;
    ngx_http_ipstat_main_conf_t  *smcf;

    ppid = NULL;
    smcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_ipstat_module);
    ctx = (ngx_http_ipstat_zone_ctx_t *) smcf->vip_zone->data;
    hdr = (ngx_http_ipstat_zone_hdr_t *) smcf->vip_zone->shm.addr;

    for (i = 0; i < smcf->workers; i++) {

        ppid = VIP_PID(ctx->data, i * smcf->block_size);

        ngx_shmtx_lock(&hdr->mutex);

        /* case 1: in a new cycle, take a spare position */

        if (*ppid == 0) {
            goto found;
        }

        /* case 2: when a worker is down, take its position */

        for (j = 0; j < (ngx_uint_t) ngx_last_process; j++) {

            if (ngx_processes[j].pid == -1) {
                continue;
            }

            if (ngx_processes[j].pid != *ppid) {
                continue;
            }

            if (ngx_processes[j].exited) {
                goto found;
            }
        }

        ngx_shmtx_unlock(&hdr->mutex);
    }

    /* never reach this point */

    ngx_log_error(NGX_LOG_WARN, cycle->log, 0,
                  "ipstat: any worker fails to attach a block is impossible");

    return NGX_OK;

found:

    *ppid = ngx_pid;

    ngx_shmtx_unlock(&hdr->mutex);

    smcf->data = (void *) ppid;

    return NGX_OK;
}


static char *
ngx_http_ipstat_show(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t     *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_ipstat_show_handler;

    return NGX_CONF_OK;
}


void
ngx_http_ipstat_close_request(void *data)
{
    ngx_connection_t             *c;

    c = data;

    ngx_http_ipstat_count(c->status, NGX_HTTP_IPSTAT_REQ_CURRENT, -1);
}


ngx_http_ipstat_vip_t *
ngx_http_ipstat_find_vip(ngx_uint_t key)
{
    ngx_http_ipstat_main_conf_t  *smcf;
    ngx_http_ipstat_vip_index_t  *idx, *idx_c;
    
    smcf = ngx_http_cycle_get_module_main_conf(ngx_cycle,
                                               ngx_http_ipstat_module);

    idx = VIP_INDEX_START(smcf->data);
    idx_c = ngx_http_ipstat_lookup_vip_index(key, idx, idx + smcf->num);

    if (idx_c == NULL) {
        return NULL;
    }

    return VIP_LOCATE(smcf->data, 0, smcf->index_size, idx_c - idx);
}


static ngx_int_t
ngx_http_ipstat_log_handler(ngx_http_request_t *r)
{
    ngx_time_t                   *tp;
    ngx_msec_int_t                ms;

    tp = ngx_timeofday();
    ms = (ngx_msec_int_t)
             ((tp->sec - r->start_sec) * 1000 + (tp->msec - r->start_msec));

    ms = ngx_max(ms, 0);

    ngx_http_ipstat_count(r->connection->status, NGX_HTTP_IPSTAT_BYTES_IN,
                         r->connection->received);
    ngx_http_ipstat_count(r->connection->status, NGX_HTTP_IPSTAT_BYTES_OUT,
                         r->connection->sent);
    ngx_http_ipstat_ts_min(r->connection->status, NGX_HTTP_IPSTAT_RT_MIN,
                        (ngx_uint_t) ms);
    ngx_http_ipstat_ts_max(r->connection->status, NGX_HTTP_IPSTAT_RT_MAX,
                        (ngx_uint_t) ms);
    ngx_http_ipstat_avg(r->connection->status, NGX_HTTP_IPSTAT_RT_AVG,
                        (ngx_uint_t) ms);

    return NGX_OK;
}


void
ngx_http_ipstat_count(void *data, off_t offset, ngx_int_t incr)
{
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_incr: %p, %O, %i",
                   data, offset, incr);

    *VIP_FIELD(vip, offset) += incr;
}


void
ngx_http_ipstat_min(void *data, off_t offset, ngx_uint_t val)
{
    ngx_uint_t                   *f, v;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_min: %p, %O, %ui",
                   data, offset, val);

    f = VIP_FIELD(vip, offset);
    if (*f) {
        v = ngx_min(*f, val);
        if (v) {
            *f = v;
        }
    } else {
        *f = val;
    }
}


void
ngx_http_ipstat_max(void *data, off_t offset, ngx_uint_t val)
{
    ngx_uint_t                   *f;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_max: %p, %O, %ui",
                   data, offset, val);

    f = VIP_FIELD(vip, offset);
    if (*f < val) {
        *f = val;
    }
}


void
ngx_http_ipstat_avg(void *data, off_t offset, ngx_uint_t val)
{
    ngx_uint_t                   *n;
    ngx_http_ipstat_avg_t        *avg;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_avg: %p, %O, %ui",
                   data, offset, val);

    avg = (ngx_http_ipstat_avg_t *) VIP_FIELD(vip, offset);
    n = VIP_FIELD(vip, NGX_HTTP_IPSTAT_REQ_TOTAL);

    if (*n) {
        avg->val += ((double) val - avg->val) / *n;
        avg->int_val = (ngx_uint_t) avg->val;
    }
}


void
ngx_http_ipstat_rate(void *data, off_t offset, ngx_uint_t val)
{
    time_t                        now;
    ngx_http_ipstat_rate_t       *rate;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_rate: %p, %O, %ui",
                    data, offset, val);

    now = ngx_time();

    rate = (ngx_http_ipstat_rate_t *) VIP_FIELD(vip, offset);

    if (rate->t == now) {
        rate->curr_rate += val;
    } else {
        rate->last_rate = (now - rate->t == 1) ? rate->curr_rate : 0;
        rate->curr_rate = val;
        rate->t = now;
    }
}


static void
ngx_http_ipstat_merge_val(ngx_http_ipstat_vip_t *dst,
    ngx_http_ipstat_vip_t *src)
{
    time_t                   now;
    ngx_uint_t               i, j, k, l, tmp;
    ngx_uint_t              *src_field, *dst_field, src_req_n, dst_req_n;
    ngx_http_ipstat_ts_t    *ts, *ots;
    ngx_http_ipstat_avg_t   *avg, *oavg;
    ngx_http_ipstat_rate_t  *rate, *orate;

    now = ngx_time();

    for (i = 0; i < field_num; i++) {
        dst_field = VIP_FIELD(dst, fields[i].offset);
        src_field = VIP_FIELD(src, fields[i].offset);

        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "ipstat_merge_val: dst=%p, op=%d, val=%ui",
                       dst_field, fields[i].type, *src_field);

        switch (fields[i].type) {

        case op_count:
            *dst_field += *src_field;
            break;

        case op_avg:
            avg = (ngx_http_ipstat_avg_t *) dst_field;
            oavg = (ngx_http_ipstat_avg_t *) src_field;
            dst_req_n = *VIP_FIELD(dst, NGX_HTTP_IPSTAT_REQ_TOTAL);
            src_req_n = *VIP_FIELD(src, NGX_HTTP_IPSTAT_REQ_TOTAL);

            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "ipstat_merge_val(average): "
                           "oavg->val=%f, avg->val=%f, oreq_n=%ui, req_n=%ui",
                           oavg->val, avg->val, src_req_n, dst_req_n);

            if (dst_req_n > 0) {
                avg->val += (oavg->val - avg->val) * src_req_n / dst_req_n;
                avg->int_val = (ngx_uint_t) avg->val;
            }
            break;

        case op_min:
            if (*dst_field) {
                if (*src_field) {
                    *dst_field = ngx_min(*dst_field, *src_field);
                }
            } else {
                *dst_field = *src_field;
            }
            break;

        case op_max:
            *dst_field = ngx_max(*dst_field, *src_field);
            break;

        case op_ts_min:
            ts = (ngx_http_ipstat_ts_t *) dst_field;
            ots = (ngx_http_ipstat_ts_t *) src_field;

            if (ts->unit == ots->unit) {
                k = ngx_max(now - ts->t, 0) / ts->unit;
                tmp = ngx_min(k, 60);

                for (j = 1; j <= tmp; j++) {
                    ts->slot[(ts->index + j) % 60] = 0;
                }

                l = ngx_max(now - ots->t, 0) / ots->unit;
                ts->t = now;

                ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                               "ipstat_merge_val(time slice): "
                               "ts->index=%d, distance=%ui, "
                               "ots->index=%d, distance=%ui",
                               ts->index, k, ots->index, l);

                ts->index = (ts->index + k) % 60;
                tmp = (ots->index + l) % 60;
                ts->val = 0;

                for (j = l; j < ts->slice; j++) {
                    k = (ts->index + 60 - j) % 60;
                    l = (tmp + 60 - j) % 60;
                    if (ts->slot[k]) {
                        if (ots->slot[l]) {
                            ts->slot[k] = ngx_min(ts->slot[k], ots->slot[l]);
                        }
                    } else {
                        ts->slot[k] = ots->slot[l];
                    }

                    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                                   "ipstat merge ts val: "
                                   "ts->slot[%ui]=%ui, ots->slot[%ui]=%ui",
                                   k, ts->slot[k], l, ots->slot[l]);
                }

                for (j = 0; j < ts->slice; j++) {
                    k = (ts->index + 60 - j) % 60;
                    if (ts->slot[k]) {
                        if (ts->val) {
                            ts->val = ngx_min(ts->val, ts->slot[k]);
                        } else {
                            ts->val = ts->slot[k];
                        }
                    }
                }
            }
            break;

        case op_ts_max:
            ts = (ngx_http_ipstat_ts_t *) dst_field;
            ots = (ngx_http_ipstat_ts_t *) src_field;

            if (ts->unit == ots->unit) {
                k = ngx_max(now - ts->t, 0) / ts->unit;
                tmp = ngx_min(k, 60);
                for (j = 1; j <= tmp; j++) {
                    ts->slot[(ts->index + j) % 60] = 0;
                }

                l = ngx_max(now - ots->t, 0) / ots->unit;
                ts->t = now;

                ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                               "ipstat_merge_val(time slice): "
                               "ts->index=%d, distance=%ui, "
                               "ots->index=%d, distance=%ui",
                               ts->index, k, ots->index, l);

                ts->index = (ts->index + k) % 60;
                tmp = (ots->index + l) % 60;
                ts->val = 0;

                if (l > ts->slice) {
                    break;
                }

                for (j = l; j < ts->slice; j++) {
                    k = (ts->index + 60 - j) % 60;
                    l = (tmp + 60 - j) % 60;
                    ts->slot[k] = ngx_max(ts->slot[k], ots->slot[l]);

                    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                                   "ipstat merge ts val: "
                                   "ts->slot[%ui]=%ui, ots->slot[%ui]=%ui",
                                   k, ts->slot[k], l, ots->slot[l]);
                }

                for (j = 0; j < ts->slice; j++) {
                    k = (ts->index + 60 - j) % 60;
                    if (ts->val < ts->slot[k]) {
                        ts->val = ts->slot[k];
                    }
                }
            }
            break;

        default:
            rate = (ngx_http_ipstat_rate_t *) dst_field;
            orate = (ngx_http_ipstat_rate_t *) src_field;

            rate->t = now;

            if (now == orate->t) {
                rate->last_rate += orate->last_rate;
                rate->curr_rate += orate->curr_rate;
            } else if (now == orate->t + 1) {
                rate->last_rate += orate->curr_rate;
            }
            break;
        }

        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "ipstat_merge_val: dst=%p, src=%p, result=%ui",
                       dst_field, src_field, *dst_field);
    }
}

static ngx_int_t
ngx_http_ipstat_show_handler(ngx_http_request_t *r)
{
    ngx_int_t                     rc;
    ngx_buf_t                    *b;
    ngx_uint_t                    i, j, k, l, *src_field;
    ngx_array_t                  *live_cycles;
    ngx_chain_t                  *tl, *free, *busy;
    ngx_shm_zone_t              **shm_zone;
    struct sockaddr_in            sin;
    ngx_http_in_addr_t           *addr;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6           sin6;
    ngx_http_in6_addr_t          *addr6;
#endif
    ngx_http_ipstat_vip_t        *vip_k, *vip_v, *vip_w, total;
    ngx_http_ipstat_zone_ctx_t   *ctx;
    ngx_http_ipstat_zone_hdr_t   *hdr;
    ngx_http_ipstat_vip_index_t  *idx;
    ngx_http_ipstat_main_conf_t  *smcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "ipstat: into ngx_http_ipstat_show_handler");

    smcf = ngx_http_get_module_main_conf(r, ngx_http_ipstat_module);
    ctx = (ngx_http_ipstat_zone_ctx_t *) smcf->vip_zone->data;
    idx = VIP_INDEX_START(ctx->data);
    vip_k = VIP_LOCATE(ctx->data, 0, smcf->index_size, 0);
    free = busy = NULL;

    live_cycles = ngx_shm_cycle_get_live_cycles(r->pool, &vip_zn);
    if (live_cycles == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    r->headers_out.status = NGX_HTTP_OK;
    ngx_http_clear_content_length(r);

    rc = ngx_http_send_header(r);
    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    tl = ngx_chain_get_free_buf(r->pool, &free);
    if (tl == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    b = tl->buf;
    b->start = ngx_pcalloc(r->pool, 512);
    if (b->start == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    b->end = b->start + 512;
    b->pos = b->start;
    b->memory = 1;
    b->temporary = 1;
    b->last = ngx_slprintf(b->pos, b->end, "%ui\n", smcf->workers);

    if (ngx_http_output_filter(r, tl) == NGX_ERROR) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ngx_chain_update_chains(r->pool, &free, &busy, &tl,
                            (ngx_buf_tag_t) &ngx_http_ipstat_module);

    for (i = 0; i < smcf->num; i++, vip_k++, idx++) {
        tl = ngx_chain_get_free_buf(r->pool, &free);
        if (tl == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        b = tl->buf;
        if (b->start == NULL) {
            b->start = ngx_pcalloc(r->pool, 512);
            if (b->start == NULL) {
                return NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            b->end = b->start + 512;
        }

        b->last = b->pos = b->start;
        b->memory = 1;
        b->temporary = 1;

        switch (idx->ipv6) {
#if (NGX_HAVE_INET6)
        case 1:
            addr6 = (ngx_http_in6_addr_t *) idx->key;
            sin6.sin6_family = AF_INET6;
            ngx_memcpy(&sin6.sin6_addr.s6_addr, &addr6->addr6, 16);
            sin6.sin6_port = idx->port;
            b->last += ngx_sock_ntop((struct sockaddr *) &sin6,
                                     b->last, 512, 1);
            break;
#endif
        default:
            addr = (ngx_http_in_addr_t *) idx->key;
            sin.sin_family = AF_INET;
            sin.sin_addr.s_addr = addr->addr;
            sin.sin_port = idx->port;
            b->last += ngx_sock_ntop((struct sockaddr *) &sin,
                                     b->last, 512, 1);
            break;
        }

        b->last = ngx_slprintf(b->last, b->end, ",FRONTEND,");

        /* gather all live data */

        ngx_memzero(&total, sizeof(ngx_http_ipstat_vip_t));
        ngx_http_ipstat_init_ts(&total, fields, field_num,
                                smcf->rt_interval, smcf->rt_unit);

        shm_zone = live_cycles->elts;

        for (vip_v = vip_k, j = 0; j < live_cycles->nelts; j++) {

            hdr = (ngx_http_ipstat_zone_hdr_t *) shm_zone[j]->shm.addr;

            for (k = 0; k < hdr->workers; k++) {
                vip_w = VIP_LOCATE(vip_v, k * hdr->block_size, 0, 0);
                ngx_http_ipstat_merge_val(&total, vip_w);
            }

            if (vip_v->prev == NULL) {
                break;
            }

            vip_v = vip_v->prev;
        }

        for (l = 0; l < field_num; l++) {
            src_field = VIP_FIELD(&total, fields[l].offset);
            b->last = ngx_slprintf(b->last, b->end, "%ui,", *src_field);
        }

        *(b->last - 1) = '\n';

        if (ngx_http_output_filter(r, tl) == NGX_ERROR) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        ngx_chain_update_chains(r->pool, &free, &busy, &tl,
                                (ngx_buf_tag_t) &ngx_http_ipstat_module);
    }

    tl = ngx_chain_get_free_buf(r->pool, &free);
    if (tl == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    b = tl->buf;
    b->last_buf = 1;

    return ngx_http_output_filter(r, tl);
}


static void
ngx_http_ipstat_merge_old_cycles(void *data)
{
    ngx_pid_t                     pid;
    ngx_uint_t                    i, j, k, l;
    ngx_array_t                  *live_cycles;
    ngx_shm_zone_t              **shm_zone;
    ngx_http_ipstat_vip_t        *vip_k, *vip_v, *vip_w, total;
    ngx_shm_cycle_cln_ctx_t      *cln_ctx;
    ngx_http_ipstat_zone_hdr_t   *hdr, *ohdr;

    cln_ctx = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat: into ngx_http_ipstat_merge_old_cycles");

    if (!cln_ctx->init || !cln_ctx->latest) {
        return;
    }

    live_cycles = ngx_shm_cycle_get_live_cycles(cln_ctx->pool, &vip_zn);
    if (live_cycles == NULL) {
        return;
    }

    shm_zone = live_cycles->elts;
    hdr = (ngx_http_ipstat_zone_hdr_t *) shm_zone[0]->shm.addr;

    for (k = 0; k < hdr->workers; k++) {

        vip_k = VIP_LOCATE(VIP_CONTENT(hdr), 0, hdr->index_size, 0);
        pid = *VIP_PID(VIP_CONTENT(hdr), k * hdr->block_size);

        for (i = 0; i < hdr->num; i++, vip_k++) {

            ngx_memzero(&total, sizeof(ngx_http_ipstat_vip_t));
            ngx_http_ipstat_init_ts(&total, fields, field_num,
                                    hdr->rt_interval, hdr->rt_unit);

            for (vip_v = vip_k->prev, j = 1;
                 vip_v && j < live_cycles->nelts;
                 vip_v = vip_v->prev, j++)
            {
                ohdr = (ngx_http_ipstat_zone_hdr_t *) shm_zone[j]->shm.addr;

                for (l = k; l < ohdr->workers; l += hdr->workers) {
                    vip_w = VIP_LOCATE(vip_v, l * ohdr->block_size, 0, 0);
                    ngx_http_ipstat_merge_val(&total, vip_w);
                }
            }

            ngx_http_ipstat_notify(pid, &total,
                              VIP_LOCATE(vip_k, k * hdr->block_size, 0, 0));
        }
    }
}


static void
ngx_http_ipstat_notify(ngx_pid_t pid, ngx_http_ipstat_vip_t *src,
    ngx_http_ipstat_vip_t *dst)
{
    ngx_int_t                     i;
    ngx_http_ipstat_channel_t     ch;

    for (i = 0; i < NGX_MAX_PROCESSES; i++) {
        if (ngx_processes[i].pid == -1) {
            continue;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "ipstat_channel_notify: pid=%P, tpid=%P",
                       ngx_processes[i].pid, pid);

        if (ngx_processes[i].pid != pid) {
            continue;
        }

        ngx_memzero(&ch, sizeof(ngx_http_ipstat_channel_t));

        ch.channel.command = NGX_CMD_IPSTAT;
        ch.channel.pid = pid;
        ch.channel.len = sizeof(ngx_http_ipstat_channel_t);
        ch.channel.tag = &ngx_http_ipstat_module;
        ch.dst = (uintptr_t) dst;

        ngx_memcpy(&ch.val, src, sizeof(ngx_http_ipstat_vip_t));

        (void) ngx_write_channel(ngx_processes[i].channel[0],
                                 (ngx_channel_t *) &ch,
                                 sizeof(ngx_http_ipstat_channel_t),
                                 ngx_cycle->log);

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "ipstat_channel_notify: "
                       "pid=%P, dst=%xi", pid, ch.dst);
        break;
    }
}


static void
ngx_http_ipstat_channel_handler(ngx_channel_t *ch, u_char *buf,
    size_t len, ngx_log_t *log)
{
    static size_t                     recv;
    ngx_http_ipstat_vip_t            *vip;
    static ngx_http_ipstat_channel_t  ch_ex;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, log, 0,
                   "ipstat: into ngx_http_ipstat_channel_handler");

    if (ch->tag != &ngx_http_ipstat_module) {
        if (ngx_channel_next_handler) {
            ngx_channel_next_handler(ch, buf, len, log);
        }
        return;
    }

    if (ch->command != NGX_CMD_IPSTAT) {
        return;
    }

    ngx_memcpy((char *) &ch_ex.dst + recv, buf, len);
    recv += len;
    if (recv < channel_len) {
        return;
    }

    recv = 0;
    vip = (ngx_http_ipstat_vip_t *) ch_ex.dst;
    ngx_http_ipstat_merge_val(vip, &ch_ex.val);
}


static void
ngx_http_ipstat_eval_rt_unit(ngx_http_ipstat_main_conf_t *conf)
{
    if (conf->rt_interval <= 60) {
        conf->rt_unit = 1;
    } else if (conf->rt_interval <= 3600) {
        conf->rt_unit = 60;
    } else if (conf->rt_interval <= 86400) {
        conf->rt_unit = 3600;
    } else {
        conf->rt_unit = 86400;
    }
}


void
ngx_http_ipstat_ts_min(void *data, off_t offset, ngx_uint_t val)
{
    time_t                        now;
    ngx_uint_t                    d, i, t;
    ngx_http_ipstat_ts_t         *ts;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_ts_min: %p, %O, %ui",
                    data, offset, val);

    now = ngx_time();

    ts = (ngx_http_ipstat_ts_t *) VIP_FIELD(vip, offset);

    d = ngx_max(now - ts->t, 0) / ts->unit;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_ts_min: d=%ui, ts->slice=%d, ts->index=%d",
                   d, ts->slice, ts->index);

    if (d) {
        t = ngx_min(d, 60);
        for (i = 1; i <= t; i++) {
            ts->slot[(ts->index + i) % 60] = 0;
        }

        ts->index = (ts->index + d) % 60;
        ts->slot[ts->index] = val;
        ts->t += d * ts->unit;
        ts->val = val;

        if (d > ts->slice) {
            return;
        }

        for (i = ts->index + 60 - d;
             i > ts->index + 60 - (ngx_uint_t) ts->slice;
             i--)
        {
            if (ts->slot[i % 60] && ts->val > ts->slot[i % 60]) {
                ts->val = ts->slot[i % 60];
            }
        }
    } else {
        if (val) {
            if (!ts->slot[ts->index] || val < ts->slot[ts->index]) {
                ts->slot[ts->index] = val;
            }

            if (!ts->val || ts->val > val) {
                ts->val = val;
            }
        }
    }

#if (NGX_DEBUG)

    for (i = ts->index; i < (ngx_uint_t) ts->index + 60; i++) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "ipstat_ts_min_result: [%ui]=%ui",
                       i % 60, ts->slot[i % 60]);
    }

#endif

}


void
ngx_http_ipstat_ts_max(void *data, off_t offset, ngx_uint_t val)
{
    time_t                        now;
    ngx_uint_t                    d, i, t;
    ngx_http_ipstat_ts_t         *ts;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_ts_max: %p, %O, %ui",
                    data, offset, val);

    now = ngx_time();

    ts = (ngx_http_ipstat_ts_t *) VIP_FIELD(vip, offset);

    d = ngx_max(now - ts->t, 0) / ts->unit;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_ts_max: d=%ui, ts->slice=%d, ts->index=%d",
                   d, ts->slice, ts->index);

    if (d) {
        t = ngx_min(d, 60);
        for (i = 1; i <= t; i++) {
            ts->slot[(ts->index + i) % 60] = 0;
        }
        ts->index = (ts->index + d) % 60;
        ts->slot[ts->index] = val;
        ts->t += d * ts->unit;
        ts->val = val;

        if (d > ts->slice) {
            return;
        }

        for (i = ts->index + 60 - d;
             i > ts->index + 60 - (ngx_uint_t) ts->slice;
             i--)
        {
            if (ts->val < ts->slot[i % 60]) {
                ts->val = ts->slot[i % 60];
            }
        }
    } else {
        if (val > ts->slot[ts->index]) {
            ts->slot[ts->index] = val;
            if (val > ts->val) {
                ts->val = val;
            }
        }
    }

#if (NGX_DEBUG)

    for (i = ts->index; i < (ngx_uint_t) ts->index + 60; i++) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "ipstat_ts_max_result: [%ui]=%ui",
                       i % 60, ts->slot[i % 60]);
    }

#endif

}


static void ngx_http_ipstat_init_ts(ngx_http_ipstat_vip_t *vip,
    ngx_http_ipstat_field_t *fields, ngx_uint_t num, time_t itv, time_t unit)
{
    ngx_uint_t                    i;
    ngx_http_ipstat_ts_t         *ts;

    for (i = 0; i < num; i++) {
        if (fields[i].type == op_ts_min || fields[i].type == op_ts_max) {
            ts = (ngx_http_ipstat_ts_t *) VIP_FIELD(vip, fields[i].offset);
            ts->t = ngx_time() / unit * unit;
            ts->unit = unit;
            ts->slice = itv / unit;

            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "ipstat_init_ts: %p, %ui, %T, %T",
                            ts, num, itv, unit);
        }
    }
}
