#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_channel.h>

#include <ngx_http_ipstat_module.h>


#define NGX_CMD_IPSTAT     10000


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
    op_count = 0,          /* general op */
    op_min,
    op_max,
    op_avg,
    op_rate,
    op_incr,               /* specific op */
    op_decr
} ngx_http_ipstat_op_t;


typedef struct {
    off_t                  offset;
    ngx_http_ipstat_op_t   type;
} ngx_http_ipstat_field_t;


typedef struct {
    ngx_channel_t          channel;
    uintptr_t              vip;
    off_t                  offset;
    ngx_uint_t             val;
    ngx_http_ipstat_op_t   op;
} ngx_http_ipstat_channel_t;


typedef struct ngx_http_ipstat_zone_hdr_s ngx_http_ipstat_zone_hdr_t;


struct ngx_http_ipstat_zone_hdr_s {
    ngx_shmtx_sh_t              shmtx;
    ngx_uint_t                  workers;
    ngx_uint_t                  num;
    size_t                      index_size;
    size_t                      block_size;
    ngx_http_ipstat_zone_hdr_t *prev;
};


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
    { NGX_HTTP_IPSTAT_CONN_CURRENT, op_count },
    { NGX_HTTP_IPSTAT_CONN_TOTAL, op_count },
    { NGX_HTTP_IPSTAT_REQ_CURRENT, op_count },
    { NGX_HTTP_IPSTAT_REQ_TOTAL, op_count },
    { NGX_HTTP_IPSTAT_BYTES_IN, op_count },
    { NGX_HTTP_IPSTAT_BYTES_OUT, op_count },
    { NGX_HTTP_IPSTAT_RT_MIN, op_min },
    { NGX_HTTP_IPSTAT_RT_MAX, op_max },
    { NGX_HTTP_IPSTAT_RT_AVG, op_avg },
    { NGX_HTTP_IPSTAT_CONN_RATE, op_rate },
    { NGX_HTTP_IPSTAT_REQ_RATE, op_rate }
};


static void (*ngx_http_ipstat_op_handler[])
                    (void *vip, off_t offset, ngx_uint_t val) = {
    NULL,
    ngx_http_ipstat_min,
    ngx_http_ipstat_max,
    ngx_http_ipstat_avg,
    ngx_http_ipstat_rate,
    ngx_http_ipstat_incr,
    ngx_http_ipstat_decr
};


static const ngx_uint_t field_num = sizeof(fields)
                                  / sizeof(ngx_http_ipstat_field_t);

static const size_t channel_len = sizeof(ngx_http_ipstat_channel_t)
                                - offsetof(ngx_http_ipstat_channel_t, vip);


static void *ngx_http_ipstat_create_main_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_ipstat_init(ngx_conf_t *cf);
static ngx_int_t ngx_http_ipstat_init_vip_zone(ngx_shm_zone_t *shm_zone,
    void *data);
static ngx_int_t ngx_http_ipstat_init_process(ngx_cycle_t *cycle);
static ngx_int_t ngx_http_ipstat_log_handler(ngx_http_request_t *r);


static void
    ngx_http_ipstat_insert_vip_index(ngx_http_ipstat_vip_index_t *start,
    ngx_http_ipstat_vip_index_t *end, ngx_http_ipstat_vip_index_t *insert);
static ngx_http_ipstat_vip_index_t *
    ngx_http_ipstat_lookup_vip_index(ngx_uint_t key,
    ngx_http_ipstat_vip_index_t *start, ngx_http_ipstat_vip_index_t *end);
static ngx_uint_t
    ngx_http_ipstat_distinguish_same_vip(ngx_http_ipstat_vip_index_t *key,
    ngx_cycle_t *old_cycle);

static void ngx_http_ipstat_notify(ngx_http_ipstat_vip_t *vip, off_t offset,
    ngx_uint_t val, ngx_http_ipstat_op_t op);
static void ngx_http_ipstat_channel_handler(ngx_channel_t *ch, u_char *buf,
    ngx_log_t *log);

static char *ngx_http_ipstat_show(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_ipstat_show_handler(ngx_http_request_t *r);


static ngx_command_t   ngx_http_ipstat_commands[] = {

    { ngx_string("vip_status_show"),
      NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
      ngx_http_ipstat_show,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
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
    return ngx_pcalloc(cf->pool, sizeof(ngx_http_ipstat_main_conf_t));
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
                     + sizeof(ngx_pid_t);          /* for init process */
    size = sizeof(ngx_http_ipstat_vip_t) * n + smcf->index_size;
    smcf->block_size = ngx_align(size, 128);
    size = ngx_align(sizeof(ngx_http_ipstat_zone_hdr_t), 128)
         + smcf->block_size * smcf->workers;

    ngx_log_debug6(NGX_LOG_DEBUG_HTTP, cf->log, 0,
                   "ipstat_init: cycle=%p, workers=%d, num=%d, "
                   "index_size=%z, block_size=%z, size=%z",
                   cf->cycle, smcf->workers, smcf->num,
                   smcf->index_size, smcf->block_size, size);

    shm_zone = ngx_shared_memory_lc_add(cf, &vip_zn, size,
                                        &ngx_http_ipstat_module, 0);
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
 * Each worker uses a piece independantly, so no mutax is needed.
 * Each piece aligns at 128 byte address so that when cpu affinity is set,
 * no cpu cache line overlap occurs. Finally, we copy data from last cycle.
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

    if (ngx_shmtx_create(&smcf->mutex, &hdr->shmtx, ctx->cycle->lock_file.data)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    hdr->workers = smcf->workers;
    hdr->num = smcf->num;
    hdr->index_size = smcf->index_size;
    hdr->block_size = smcf->block_size;

    ngx_log_debug5(NGX_LOG_DEBUG_HTTP, shm_zone->shm.log, 0,
                   "ipstat_init_zone(current hdr %p): "
                   "workers=%d, num=%d, index_size=%z, block_size=%z",
                   hdr, hdr->workers, hdr->num,
                   hdr->index_size, hdr->block_size);

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

    for (i = 1; i < (ngx_uint_t) smcf->workers; i++) {
        ngx_memcpy((char *) ctx->data + i * smcf->block_size, ctx->data,
                   smcf->index_size);
    }

    /* build vip chain */

    if (data == NULL) {
        return NGX_OK;
    }

    octx = data;
    hdr->prev = VIP_HEADER(octx->data);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, shm_zone->shm.log, 0,
                   "ipstat_init_zone_cp(current hdr %p): prev=%p",
                   hdr, hdr->prev);

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
    ngx_pid_t                    *ppid, t;
    ngx_uint_t                    i, j, k, l, workers, *field, *ofield;
    ngx_http_ipstat_vip_t        *vip_base, *vip, *ovip;
    ngx_http_ipstat_rate_t       *rate, *orate;
    ngx_http_ipstat_zone_ctx_t   *ctx;
    ngx_http_ipstat_zone_hdr_t   *hdr;
    ngx_http_ipstat_main_conf_t  *smcf;

    ppid = NULL;
    smcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_ipstat_module);
    ctx = (ngx_http_ipstat_zone_ctx_t *) smcf->vip_zone->data;

    for (i = 0; i < smcf->workers; i++) {

        ppid = VIP_PID(ctx->data, i * smcf->block_size);

        ngx_shmtx_lock(&smcf->mutex);

        /* when it is a new cycle, rewrite pid fields of last cycle */

        if (*ppid == 0) {
            goto found;
        }

        /* when a worker is down, the new one will take place its position */

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

        ngx_shmtx_unlock(&smcf->mutex);
    }

    /* never reach this point */

    ngx_log_error(NGX_LOG_WARN, cycle->log, 0,
                  "ipstat: any worker fails to attach a block is impossible");

    return NGX_OK;

found:

    t = *ppid;
    *ppid = ngx_pid;

    ngx_shmtx_unlock(&smcf->mutex);

    smcf->data = (void *) ppid;

    /* case 1: respawn a worker for current cycle */

    if (t) {
        return NGX_OK;
    }

    /* case 2: respawn a worker for new cycle */

    /* rewrite pid field in the last cycle */

    hdr = VIP_HEADER(ctx->data);
    hdr = hdr->prev;

    /* set pid in last cycle */

    if (hdr) {
        for (k = i; k < hdr->workers; k += smcf->workers) {
            for (j = 0; j < hdr->num; j++) {
                vip = VIP_LOCATE(VIP_CONTENT(hdr), k * hdr->block_size,
                                 hdr->index_size, j);
                vip->pid = ngx_pid;
            }
        }
    }

    if (hdr == NULL) {
        return NGX_OK;
    }

    workers = ngx_min(smcf->workers, hdr->workers);

    vip_base = VIP_LOCATE(ctx->data, 0, smcf->index_size, 0);

    /* set next ptr in last cycle */

    for (l = 0; l < hdr->num; ++l, ++vip_base) {
        if (!vip_base->prev) {
            continue;
        }

        vip = VIP_LOCATE(vip_base, i * smcf->block_size, 0, 0);
        ovip = VIP_LOCATE(vip_base->prev, i * hdr->block_size, 0, 0);
        ovip->next = vip;

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, cycle->log, 0,
                       "ipstat_init_process: vip=%p, ovip=%p", vip, ovip);

        if (workers >= hdr->workers) {
            continue;
        }

        /* reduce number of workers in current cycle */

        for (j = i + workers; j < hdr->workers; j += workers) {
            vip = VIP_LOCATE(vip_base, j * smcf->block_size, 0, 0);
            ovip = VIP_LOCATE(vip_base->prev, j * hdr->block_size, 0, 0);
            ovip->next = vip;

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, cycle->log, 0,
                           "ipstat_init_process: vip=%p, ovip=%p", vip, ovip);
        }
    }

    /* allow last cycle notice the change, and send msg to this worker */

    ngx_msleep(20);

    /* copy data from last cycle */

    vip_base = VIP_LOCATE(ctx->data, 0, smcf->index_size, 0);

    for (l = 0; l < hdr->num; ++l, ++vip_base) {
        if (!vip_base->prev) {
            continue;
        }

        vip = VIP_LOCATE(vip_base, i * smcf->block_size, 0, 0);
        ovip = VIP_LOCATE(vip_base->prev, i * hdr->block_size, 0, 0);
        ngx_memcpy((char *) vip + NGX_HTTP_IPSTAT_CONN_CURRENT,
                   (char *) ovip + NGX_HTTP_IPSTAT_CONN_CURRENT,
                   sizeof(ngx_http_ipstat_vip_t)
                                   - NGX_HTTP_IPSTAT_CONN_CURRENT);

        if (workers >= hdr->workers) {
            continue;
        }

        /* reduce number of workers in current cycle */

        for (j = i + workers; j < hdr->workers; j += workers) {
            vip = VIP_LOCATE(vip_base, j * smcf->block_size, 0, 0);
            ovip = VIP_LOCATE(vip_base->prev, j * hdr->block_size, 0, 0);

            for (k = 0; k < field_num; ++k) {

                field = VIP_FIELD(vip, fields[k].offset);
                ofield = VIP_FIELD(ovip, fields[k].offset);

                switch (fields[k].type) {

                case op_count:
                    *field += *ofield;
                    break;

                case op_min:
                    if (ngx_min(*field, *ofield)) {
                        *field = ngx_min(*field, *ofield);
                    }
                    break;

                case op_max:
                    *field = ngx_max(*field, *ofield);
                    break;

                case op_avg:
                    if (*VIP_FIELD(vip, NGX_HTTP_IPSTAT_REQ_TOTAL)) {
                        *field += (*ofield - *field)
                                / *VIP_FIELD(vip, NGX_HTTP_IPSTAT_REQ_TOTAL);
                    }
                    break;

                default:
                    rate = (ngx_http_ipstat_rate_t *) field;
                    orate = (ngx_http_ipstat_rate_t *) ofield;
                    if (rate->t == orate->t) {
                        rate->last_rate += orate->last_rate;
                        rate->curr_rate += orate->curr_rate;
                    } else if (rate->t + 1 == orate->t) {
                        rate->t = orate->t;
                        rate->last_rate = rate->curr_rate + orate->last_rate;
                        rate->curr_rate = orate->curr_rate;
                    } else if (rate->t + 1 < orate->t) {
                        *rate = *orate;
                    } else if (rate->t == orate->t + 1) {
                        rate->last_rate += orate->curr_rate;
                    }
                    break;
                }
            }
        }
    }

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


static ngx_int_t
ngx_http_ipstat_show_handler(ngx_http_request_t *r)
{
    time_t                        now;
    ngx_int_t                     rc;
    ngx_buf_t                    *b;
    ngx_uint_t                   *f, i, j, k, n, result;
    struct sockaddr_in            sin;
    ngx_http_in_addr_t           *addr;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6           sin6;
    ngx_http_in6_addr_t          *addr6;
#endif
    ngx_chain_t                  *tl, *free, *busy;
    ngx_http_ipstat_vip_t        *vip;
    ngx_http_ipstat_rate_t       *rate;
    ngx_http_ipstat_zone_ctx_t   *ctx;
    ngx_http_ipstat_main_conf_t  *smcf;
    ngx_http_ipstat_vip_index_t  *idx;

    smcf = ngx_http_get_module_main_conf(r, ngx_http_ipstat_module);
    ctx = (ngx_http_ipstat_zone_ctx_t *) smcf->vip_zone->data;
    idx = VIP_INDEX_START(ctx->data);
    vip = VIP_LOCATE(ctx->data, 0, smcf->index_size, 0);
    free = busy = NULL;
    now = ngx_time();

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
    b->last = ngx_slprintf(b->pos, b->end, "%d\n", smcf->workers);

    if (ngx_http_output_filter(r, tl) == NGX_ERROR) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ngx_chain_update_chains(r->pool, &free, &busy, &tl,
                            (ngx_buf_tag_t) &ngx_http_ipstat_module);

    for (i = 0; i < smcf->num; i++, vip++, idx++) {
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

        *b->last++ = ',';

        for (n = 0, k = 0; k < smcf->workers; k++) {
            n += *VIP_FIELD(vip, NGX_HTTP_IPSTAT_REQ_TOTAL
                                                    + k * smcf->block_size);
        }

        for (j = 0; j < field_num; j++) {
            for (result = 0, k = 0; k < smcf->workers; k++) {

                f = VIP_FIELD(vip, fields[j].offset + k * smcf->block_size);

                switch (fields[j].type) {

                case op_count:
                    result += *f;
                    break;

                case op_min:
                    result = ngx_min(result, *f) ? ngx_min(result, *f) : result;
                    break;

                case op_max:
                    result = ngx_max(result, *f);
                    break;

                case op_avg:
                    if (n) {
                        result += (*f - result) / n;
                    }
                    break;

                default:
                    rate = (ngx_http_ipstat_rate_t *) f;
                    if (now == rate->t) {
                        result += rate->last_rate;
                    } else if (now == rate->t + 1) {
                        result += rate->curr_rate;
                    }
                    break;
                }
            }

            b->last = ngx_slprintf(b->last, b->end, "%ud,", result);
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


void
ngx_http_ipstat_close_request(void *data)
{
    ngx_connection_t             *c;

    c = data;

    ngx_http_ipstat_decr(c->status, NGX_HTTP_IPSTAT_REQ_CURRENT, 1);
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

    ngx_http_ipstat_incr(r->connection->status, NGX_HTTP_IPSTAT_BYTES_IN,
                         r->connection->received);
    ngx_http_ipstat_incr(r->connection->status, NGX_HTTP_IPSTAT_BYTES_OUT,
                         r->connection->sent);
    ngx_http_ipstat_min(r->connection->status, NGX_HTTP_IPSTAT_RT_MIN,
                        (ngx_uint_t) ms);
    ngx_http_ipstat_max(r->connection->status, NGX_HTTP_IPSTAT_RT_MAX,
                        (ngx_uint_t) ms);
    ngx_http_ipstat_avg(r->connection->status, NGX_HTTP_IPSTAT_RT_AVG,
                        (ngx_uint_t) ms);

    return NGX_OK;
}


void
ngx_http_ipstat_incr(void *data, off_t offset, ngx_uint_t incr)
{
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_incr: %p, %p, %O, %d",
                   data, vip->next, offset, incr);

    if (vip->next) {
        ngx_http_ipstat_notify(vip, offset, incr, op_incr);
    } else {
        *VIP_FIELD(vip, offset) += incr;
    }
}


void
ngx_http_ipstat_decr(void *data, off_t offset, ngx_uint_t decr)
{
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_decr: %p, %p, %O, %d",
                   data, vip->next, offset, decr);

    if (vip->next) {
        ngx_http_ipstat_notify(vip, offset, decr, op_decr);
    } else {
        *VIP_FIELD(vip, offset) -= decr;
    }
}


void
ngx_http_ipstat_min(void *data, off_t offset, ngx_uint_t val)
{
    ngx_uint_t                   *f, v;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_min: %p, %p, %O, %d",
                   data, vip->next, offset, val);

    if (vip->next) {
        ngx_http_ipstat_notify(vip, offset, val, op_min);
    } else {
        f = VIP_FIELD(vip, offset);
        v = ngx_min(*f, val);
        if (v) {
            *f = v;
        }
    }
}


void
ngx_http_ipstat_max(void *data, off_t offset, ngx_uint_t val)
{
    ngx_uint_t                   *f;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_max: %p, %p, %O, %d",
                   data, vip->next, offset, val);

    if (vip->next) {
        ngx_http_ipstat_notify(vip, offset, val, op_max);
    } else {
        f = VIP_FIELD(vip, offset);
        if (*f < val) {
            *f = val;
        }
    }
}


void
ngx_http_ipstat_avg(void *data, off_t offset, ngx_uint_t val)
{
    ngx_uint_t                   *f, *n;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_avg: %p, %p, %O, %d",
                   data, vip->next, offset, val);

    if (vip->next) {
        ngx_http_ipstat_notify(vip, offset, val, op_avg);
    } else {
        f = VIP_FIELD(vip, offset);
        n = VIP_FIELD(vip, NGX_HTTP_IPSTAT_REQ_TOTAL);
        *f += (val - *f) / *n;
    }
}


void
ngx_http_ipstat_rate(void *data, off_t offset, ngx_uint_t val)
{
    time_t                        now;
    ngx_http_ipstat_rate_t       *rate;
    ngx_http_ipstat_vip_t        *vip = data;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ipstat_rate: %p, %p, %O, %d",
                    data, vip->next, offset, val);

    if (vip->next) {
        ngx_http_ipstat_notify(vip, offset, val, op_rate);
    } else {
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
}


static void
ngx_http_ipstat_notify(ngx_http_ipstat_vip_t *vip, off_t offset,
    ngx_uint_t val, ngx_http_ipstat_op_t op)
{
    ngx_int_t                     i;
    ngx_http_ipstat_channel_t     ch;

    for (i = 0; i < NGX_MAX_PROCESSES; i++) {
        if (ngx_processes[i].pid == -1) {
            continue;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "ipstat_channel_notify: pid=%P, tpid=%P",
                       ngx_processes[i].pid, vip->pid);

        if (ngx_processes[i].pid != vip->pid) {
            continue;
        }

        ch.channel.command = NGX_CMD_IPSTAT;
        ch.channel.pid = vip->pid;
        ch.channel.len = sizeof(ngx_http_ipstat_channel_t);
        ch.vip = (uintptr_t) vip->next;
        ch.offset = offset;
        ch.val = val;
        ch.op = op;

        (void) ngx_write_channel(ngx_processes[i].channel[0],
                                 (ngx_channel_t *) &ch,
                                 sizeof(ngx_http_ipstat_channel_t),
                                 ngx_cycle->log);

        ngx_log_debug5(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "ipstat_channel_notify: "
                       "pid=%P, op=%d, vip=%xd, offset=%O, val=%d",
                       vip->pid, ch.op, ch.vip, ch.offset, ch.val);
        break;
    }
}


static void
ngx_http_ipstat_channel_handler(ngx_channel_t *ch, u_char *buf,
    ngx_log_t *log)
{
    ngx_http_ipstat_channel_t     ch_ex;

    if (ch->command != NGX_CMD_IPSTAT) {
        if (ngx_channel_next_handler) {
            ngx_channel_next_handler(ch, buf, log);
        }
        return;
    }

    ngx_memcpy(&ch_ex.vip, buf, channel_len);

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, log, 0,
                   "ipstat_channel_handler: "
                   "op=%d, vip=%xd, offset=%O, val=%d",
                   ch_ex.op, ch_ex.vip, ch_ex.offset, ch_ex.val);

    ngx_http_ipstat_op_handler[ch_ex.op]((void *) ch_ex.vip,
                                         ch_ex.offset,
                                         ch_ex.val);
}
