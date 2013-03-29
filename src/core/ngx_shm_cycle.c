
/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_channel.h>


#define NGX_CMD_SHM_CYCLE         (NGX_CMD_USER + 1)
#define NGX_MAX_SHM_CYCLES        40000
#define NGX_SHM_CYCLE_POOL_SIZE   2048


typedef struct {
    ngx_queue_t        queue;
    ngx_list_t         shared_memory;
    ngx_uint_t         generation;
    ngx_pool_t        *pool;
    unsigned           init:1;
} ngx_shm_cycle_t;


typedef struct {
    ngx_channel_t      channel;
    ngx_uint_t         latest_dead;
} ngx_shm_cycle_channel_t;


static ngx_queue_t     ngx_shm_cycle_free;
static ngx_queue_t     ngx_shm_cycle_busy;
static ngx_uint_t      ngx_shm_cycle_generation;
static ngx_uint_t      ngx_shm_cycle_latest_dead_generation;
static ngx_shm_cycle_t ngx_shm_cycles[NGX_MAX_SHM_CYCLES];


static void ngx_shm_cycle_cleanup(void *data);
static ngx_shm_cycle_t *ngx_shm_cycle_get_last_cycle(ngx_shm_cycle_t *shcyc);
static void ngx_shm_cycle_notify(void);
static void ngx_shm_cycle_channel_handler(ngx_channel_t *ch, u_char *buf,
    ngx_log_t *log);
static ngx_int_t ngx_init_zone_pool(ngx_cycle_t *cycle, ngx_shm_zone_t *zn);


void
ngx_shm_cycle_init(void)
{
    ngx_uint_t         i;

    ngx_queue_init(&ngx_shm_cycle_free);
    ngx_queue_init(&ngx_shm_cycle_busy);

    for (i = 0; i < NGX_MAX_SHM_CYCLES; i++) {
        ngx_queue_insert_head(&ngx_shm_cycle_free, &ngx_shm_cycles[i].queue);
    }
}


void
ngx_shm_cycle_increase_generation(void)
{
    ngx_shm_cycle_generation++;
    ngx_channel_top_handler = ngx_shm_cycle_channel_handler;
}


ngx_shm_zone_t *
ngx_shm_cycle_add(ngx_conf_t *cf, ngx_str_t *name, size_t size, void *tag,
    int slab)
{
    ngx_uint_t         i, init_pool, n;
    ngx_shm_zone_t     *shm_zone;
    ngx_list_part_t    *part;
    ngx_shm_cycle_t    *shcyc, *last_shcyc;
    ngx_pool_cleanup_t *cln;

    init_pool = 0;

    if (ngx_queue_empty(&ngx_shm_cycle_busy)) {
        last_shcyc = NULL;

        init_pool = 1;

        shcyc = (ngx_shm_cycle_t *) ngx_queue_head(&ngx_shm_cycle_free);
        ngx_queue_remove(&shcyc->queue);
        ngx_queue_insert_head(&ngx_shm_cycle_busy, &shcyc->queue);

    } else {
        shcyc = (ngx_shm_cycle_t *) ngx_queue_head(&ngx_shm_cycle_busy);
        if (shcyc->generation != ngx_shm_cycle_generation) {
            if (ngx_queue_empty(&ngx_shm_cycle_free)) {
                return NULL;
            }

            init_pool = 1;

            shcyc = (ngx_shm_cycle_t *) ngx_queue_head(&ngx_shm_cycle_free);
            ngx_queue_remove(&shcyc->queue);
            ngx_queue_insert_head(&ngx_shm_cycle_busy, &shcyc->queue);
        }

        last_shcyc = ngx_shm_cycle_get_last_cycle(shcyc);
    }

    if (init_pool) {
        shcyc->pool = ngx_create_pool(NGX_SHM_CYCLE_POOL_SIZE, cf->log);
        if (shcyc->pool == NULL) {
            goto error;
        }

        cln = ngx_pool_cleanup_add(shcyc->pool, 0);
        if (cln == NULL) {
            ngx_destroy_pool(shcyc->pool);
            goto error;
        }

        cln->handler = ngx_shm_cycle_cleanup;
        cln->data = shcyc;

        if (last_shcyc && last_shcyc->shared_memory.part.nelts) {
            n = last_shcyc->shared_memory.part.nelts;
            for (part = last_shcyc->shared_memory.part.next;
                 part;
                 part = part->next)
            {
                n += part->nelts;
            }

        } else {
            n = 1;
        }

        if (ngx_list_init(&shcyc->shared_memory,
                          shcyc->pool, n, sizeof(ngx_shm_zone_t))
            != NGX_OK)
        {
            ngx_destroy_pool(shcyc->pool);
            goto error;
        }

        shcyc->generation = ngx_shm_cycle_generation;
    }

    part = &shcyc->shared_memory.part;
    shm_zone = part->elts;

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            shm_zone = part->elts;
            i = 0;
        }

        if (name->len != shm_zone[i].shm.name.len) {
            continue;
        }

        if (ngx_strncmp(name->data, shm_zone[i].shm.name.data, name->len)
            != 0)
        {
            continue;
        }

        if (tag != shm_zone[i].tag) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                            "the shared memory zone \"%V\" is "
                            "already declared for a different use",
                            &shm_zone[i].shm.name);
            return NULL;
        }

        if (size && size != shm_zone[i].shm.size) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "the size %uz of shared memory zone \"%V\" "
                               "conflicts with already declared size %uz",
                               size, &shm_zone[i].shm.name,
                               shm_zone[i].shm.size);
            return NULL;
        }

        return &shm_zone[i];
    }

    shm_zone = ngx_list_push(&shcyc->shared_memory);
    if (shm_zone == NULL) {
        return NULL;
    }

    shm_zone->data = NULL;
    shm_zone->shm.addr = NULL;
    shm_zone->shm.log = cf->log;
    shm_zone->shm.size = size;
    shm_zone->shm.name = *name;
    shm_zone->shm.exists = slab ? 0 : 1;
    shm_zone->init = NULL;
    shm_zone->tag = tag;

    return shm_zone;

error:

    ngx_queue_remove(&shcyc->queue);
    ngx_queue_insert_head(&ngx_shm_cycle_free, &shcyc->queue);

    return NULL;
}


ngx_int_t
ngx_shm_cycle_init_cycle(ngx_cycle_t *cycle)
{
    ngx_queue_t       *queue;
    ngx_shm_cycle_t   *shcyc, *last_shcyc;
    ngx_uint_t         i, n;
    ngx_shm_zone_t    *shm_zone, *oshm_zone;
    ngx_list_part_t   *part, *opart;

    if (ngx_queue_empty(&ngx_shm_cycle_busy)) {
        return NGX_OK;
    } 

    for (queue = ngx_queue_head(&ngx_shm_cycle_busy);
         queue != ngx_queue_sentinel(&ngx_shm_cycle_busy);
         queue = ngx_queue_next(queue))
    {
        shcyc = (ngx_shm_cycle_t *) queue;
        shcyc->pool->log = cycle->log;
    }

    shcyc = (ngx_shm_cycle_t *) ngx_queue_head(&ngx_shm_cycle_busy);
    last_shcyc = ngx_shm_cycle_get_last_cycle(shcyc);

    /* reinit prevention */

    if (shcyc->init) {
        return NGX_OK;
    }

    part = &shcyc->shared_memory.part;
    shm_zone = part->elts;

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            shm_zone = part->elts;
            i = 0;
        }

        if (shm_zone[i].shm.size == 0) {
            ngx_log_error(NGX_LOG_EMERG, cycle->old_cycle->log, 0,
                          "zero size shared memory zone \"%V\"",
                          &shm_zone[i].shm.name);
            return NGX_ERROR;
        }

        shm_zone[i].shm.log = cycle->log;

        if (ngx_shm_alloc(&shm_zone[i].shm) != NGX_OK) {
            return NGX_ERROR;
        }

        if (!shm_zone[i].shm.exists
            && ngx_init_zone_pool(cycle, &shm_zone[i]) != NGX_OK)
        {
            return NGX_ERROR;
        }

        shm_zone[i].shm.exists = 0;

        if (last_shcyc == NULL) {
            if (shm_zone[i].init(&shm_zone[i], NULL) != NGX_OK) {
                return NGX_ERROR;
            }

            continue;
        }

        opart = &last_shcyc->shared_memory.part;
        oshm_zone = opart->elts;

        for (n = 0; /* void */ ; n++) {

            if (n >= opart->nelts) {
                if (opart->next == NULL) {
                    break;
                }
                opart = opart->next;
                oshm_zone = opart->elts;
                n = 0;
            }

            if (shm_zone[i].shm.name.len != oshm_zone[n].shm.name.len) {
                continue;
            }

            if (ngx_strncmp(shm_zone[i].shm.name.data,
                            oshm_zone[n].shm.name.data,
                            shm_zone[i].shm.name.len)
                != 0)
            {
                continue;
            }

            if (shm_zone[i].init(&shm_zone[i], oshm_zone[n].data)
                != NGX_OK)
            {
                return NGX_ERROR;
            }

            goto found;
        }

        if (shm_zone[i].init(&shm_zone[i], NULL) != NGX_OK) {
            return NGX_ERROR;
        }

found:

        continue;
    }

    shcyc->init = 1;

    return NGX_OK;
}


ngx_array_t *
ngx_shm_cycle_get_live_cycles(ngx_pool_t *pool, ngx_str_t *name)
{
    ngx_uint_t         i, n;
    ngx_array_t       *live_cycles;
    ngx_queue_t       *queue;
    ngx_shm_zone_t    *shm_zone, **store;
    ngx_list_part_t   *part;
    ngx_shm_cycle_t   *shcyc;

    for (n = 0, queue = ngx_queue_head(&ngx_shm_cycle_busy);
         queue != ngx_queue_sentinel(&ngx_shm_cycle_busy);
         queue = ngx_queue_next(queue))
    {
        shcyc = (ngx_shm_cycle_t *) queue;

        if (shcyc->generation <= ngx_shm_cycle_latest_dead_generation) {
            break;
        }

        if (shcyc->init) {
            ++n;
        }
    }

    n = ngx_max(n, 1);
    live_cycles = ngx_array_create(pool, n, sizeof(ngx_shm_zone_t *));
    if (live_cycles == NULL) {
        return NULL;
    }

    for (queue = ngx_queue_head(&ngx_shm_cycle_busy);
         queue != ngx_queue_sentinel(&ngx_shm_cycle_busy);
         queue = ngx_queue_next(queue))
    {
        shcyc = (ngx_shm_cycle_t *) queue;

        if (shcyc->generation <= ngx_shm_cycle_latest_dead_generation) {
            break;
        }

        if (!shcyc->init) {
            continue;
        }

        part = &shcyc->shared_memory.part;
        shm_zone = part->elts;

        for (i = 0; /* void */ ; i++) {

            if (i >= part->nelts) {
                if (part->next == NULL) {
                    break;
                }
                part = part->next;
                shm_zone = part->elts;
                i = 0;
            }

            if (name->len != shm_zone[i].shm.name.len) {
                continue;
            }

            if (ngx_strncmp(name->data, shm_zone[i].shm.name.data,
                            name->len)
                != 0)
            {
                continue;
            }

            store = ngx_array_push(live_cycles);
            *store = &shm_zone[i];
        }
    }

    return live_cycles;
}


void
ngx_shm_cycle_free_old_cycles(void)
{
    ngx_queue_t             *start, *queue, *tmp;
    ngx_shm_cycle_t         *shcyc;
    ngx_pool_cleanup_t      *cln;
    ngx_shm_cycle_cln_ctx_t *cln_ctx;

    start = queue = ngx_queue_next(ngx_queue_head(&ngx_shm_cycle_busy));

    while (queue != ngx_queue_sentinel(&ngx_shm_cycle_busy)) {

        shcyc = (ngx_shm_cycle_t *) queue;

        shcyc->pool->log = ngx_cycle->log;

        /**
         * set flags in context of user-defined cleanup handlers,
         * the last one is added by shm_cycle and mustn't do this.
         */

        for (cln = shcyc->pool->cleanup; cln->next; cln = cln->next) {
            cln_ctx = cln->data;
            if (cln_ctx) {
                cln_ctx->init = shcyc->init;
                cln_ctx->latest = (queue == start);
            }
        }

        ngx_destroy_pool(shcyc->pool);
        shcyc->init = 0;

        /**
         * when the master process frees the latest cycle,
         * it notifies all the workers the generation of this cycle
         */

        if (queue == start) {
            ngx_shm_cycle_latest_dead_generation = shcyc->generation;
            ngx_shm_cycle_notify();
        }

        tmp = ngx_queue_next(queue);
        ngx_queue_remove(queue);
        ngx_queue_insert_head(&ngx_shm_cycle_free, queue);
        queue = tmp;
    }
}


ngx_int_t
ngx_shm_cycle_add_cleanup(ngx_str_t *zn, ngx_shm_cycle_cleanup_pt cln)
{
    ngx_uint_t               i;
    ngx_shm_zone_t          *shm_zone;
    ngx_list_part_t         *part;
    ngx_shm_cycle_t         *shcyc;
    ngx_pool_cleanup_t      *pcln;
    ngx_shm_cycle_cln_ctx_t *pcln_ctx;

    if (ngx_queue_empty(&ngx_shm_cycle_busy)) {
        return NGX_ERROR;
    }

    shcyc = (ngx_shm_cycle_t *) ngx_queue_head(&ngx_shm_cycle_busy);

    part = &shcyc->shared_memory.part;
    shm_zone = part->elts;

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            shm_zone = part->elts;
            i = 0;
        }

        if (zn->len != shm_zone[i].shm.name.len) {
            continue;
        }

        if (ngx_strncmp(zn->data, shm_zone[i].shm.name.data, zn->len)
            != 0)
        {
            continue;
        }

        pcln = ngx_pool_cleanup_add(shcyc->pool,
                                    sizeof(ngx_shm_cycle_cln_ctx_t));
        if (pcln == NULL) {
            return NGX_ERROR;
        }

        pcln_ctx = pcln->data;
        pcln_ctx->shm_zone = &shm_zone[i];
        pcln_ctx->pool = shcyc->pool;
        pcln->handler = cln;

        return NGX_OK;
    }

    ngx_log_error(NGX_LOG_EMERG, shcyc->pool->log, 0,
                  "shm zone \"%V\" is not found", zn);

    return NGX_ERROR;
}


static void
ngx_shm_cycle_cleanup(void *data)
{
    ngx_uint_t         i;
    ngx_shm_zone_t    *shm_zone;
    ngx_list_part_t   *part;
    ngx_shm_cycle_t   *shcyc;

    shcyc = data;
    part = &shcyc->shared_memory.part;
    shm_zone = part->elts;

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            shm_zone = part->elts;
            i = 0;
        }

        if (shm_zone[i].shm.addr != NULL) {
            shm_zone[i].shm.log = ngx_cycle->log;
            ngx_shm_free(&shm_zone[i].shm);
        }
    }
}


static ngx_shm_cycle_t *
ngx_shm_cycle_get_last_cycle(ngx_shm_cycle_t *shcyc)
{
    ngx_queue_t       *queue;

    for (queue = ngx_queue_next(&shcyc->queue);
         queue != ngx_queue_sentinel(&ngx_shm_cycle_busy);
         queue = ngx_queue_next(queue))
    {
        shcyc = (ngx_shm_cycle_t *) queue;
        if (shcyc->init) {
            return shcyc;
        }
    }

    return NULL;
}


/**
 * The master calls this function when it frees the old cycles.
 */ 

static void
ngx_shm_cycle_notify(void)
{
    ngx_int_t               i;
    ngx_shm_cycle_channel_t ch;

    ch.channel.command = NGX_CMD_SHM_CYCLE;
    ch.channel.fd = 0;
    ch.channel.len = sizeof(ngx_shm_cycle_channel_t);
    ch.channel.tag = ngx_shm_cycles;
    ch.latest_dead = ngx_shm_cycle_latest_dead_generation;

    for (i = 0; i < ngx_last_process; i++) {
        if (ngx_processes[i].pid == -1) {
            continue;
        }

        if (ngx_processes[i].exited) {
            continue;
        }

        ch.channel.pid = ngx_processes[i].pid;

        (void) ngx_write_channel(ngx_processes[i].channel[0],
                                 (ngx_channel_t *) &ch,
                                 sizeof(ngx_shm_cycle_channel_t),
                                 ngx_cycle->log);

        ngx_log_debug3(NGX_LOG_DEBUG_CORE, ngx_cycle->log, 0,
                       "shm_cycle_notify: fd=%d, pid=%P, latest_dead=%i",
                       ngx_processes[i].channel[0],
                       ngx_processes[i].pid,
                       ngx_shm_cycle_latest_dead_generation);
    }
}


static void
ngx_shm_cycle_channel_handler(ngx_channel_t *ch, u_char *buf, ngx_log_t *log)
{
    if (ch->tag != ngx_shm_cycles) {
        return;
    }

    if (ch->command != NGX_CMD_SHM_CYCLE) {
        return;
    }

    ngx_shm_cycle_latest_dead_generation = *((ngx_uint_t *) buf);
}


static ngx_int_t
ngx_init_zone_pool(ngx_cycle_t *cycle, ngx_shm_zone_t *zn)
{
    u_char            *file;
    ngx_slab_pool_t   *sp;

    sp = (ngx_slab_pool_t *) zn->shm.addr;

    if (zn->shm.exists) {

        if (sp == sp->addr) {
            return NGX_OK;
        }

        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "shared zone \"%V\" has no equal addresses: %p vs %p",
                      &zn->shm.name, sp->addr, sp);
        return NGX_ERROR;
    }

    sp->end = zn->shm.addr + zn->shm.size;
    sp->min_shift = 3;
    sp->addr = zn->shm.addr;

#if (NGX_HAVE_ATOMIC_OPS)

    file = NULL;

#else

    file = ngx_pnalloc(cycle->pool, cycle->lock_file.len + zn->shm.name.len);
    if (file == NULL) {
        return NGX_ERROR;
    }

    (void) ngx_sprintf(file, "%V%V%Z", &cycle->lock_file, &zn->shm.name);

#endif

    if (ngx_shmtx_create(&sp->mutex, &sp->lock, file) != NGX_OK) {
        return NGX_ERROR;
    }

    ngx_slab_init(sp);

    return NGX_OK;
}
