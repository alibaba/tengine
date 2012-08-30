
/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>


#define NGX_MAX_SHM_CYCLES        20
#define NGX_SHM_CYCLE_POOL_SIZE   1024


typedef struct {
    ngx_list_t        shared_memory;
    ngx_uint_t        generation;
    ngx_pool_t       *pool;
    unsigned          used:1;
    unsigned          ready:1;
} ngx_shm_cycle_t;


static ngx_uint_t       ngx_shm_cycle_generation;
static ngx_uint_t       ngx_last_shm_cycle;
static ngx_shm_cycle_t  ngx_shm_cycles[NGX_MAX_SHM_CYCLES];


static void ngx_close_shm_cycle(ngx_shm_cycle_t *shm_cycle);
static ngx_int_t ngx_init_zone_pool(ngx_cycle_t *cycle, ngx_shm_zone_t *zn);


void
ngx_increase_shm_cycle_generation(void)
{
    ++ngx_shm_cycle_generation;
}


ngx_shm_zone_t *
ngx_shared_memory_lc_add(ngx_conf_t *cf, ngx_str_t *name, size_t size,
    void *tag, int slab)
{
    ngx_int_t         use, last_use;
    ngx_uint_t        i, n;
    ngx_shm_zone_t   *shm_zone;
    ngx_list_part_t  *part;

    for (i = 0, use = -1, last_use = -1; i < ngx_last_shm_cycle; i++) {
        if (!ngx_shm_cycles[i].used) {
            if (use == -1) {
                use = i;
            }

            continue;
        }

        if (ngx_shm_cycles[i].generation == ngx_shm_cycle_generation) {
            use = i;
            continue;
        }

        if (ngx_shm_cycles[i].ready
            && (last_use == -1 || ngx_shm_cycles[i].generation
                                        > ngx_shm_cycles[last_use].generation))
        {
            last_use = i;
        }
    }

    if (use == -1) {
        if (ngx_last_shm_cycle < NGX_MAX_SHM_CYCLES) {
            use = ngx_last_shm_cycle++;
        } else {
            return NULL;
        }
    }

    if (!ngx_shm_cycles[use].used) {
        ngx_shm_cycles[use].pool = ngx_create_pool(NGX_SHM_CYCLE_POOL_SIZE,
                                                   cf->log);
        if (ngx_shm_cycles[use].pool == NULL) {
            return NULL;
        }

        if (last_use != -1
            && ngx_shm_cycles[last_use].shared_memory.part.nelts)
        {
            n = ngx_shm_cycles[last_use].shared_memory.part.nelts;
            for (part = ngx_shm_cycles[last_use].shared_memory.part.next;
                 part; part = part->next)
            {
                n += part->nelts;
            }

        } else {
            n = 1;
        }

        if (ngx_list_init(&ngx_shm_cycles[use].shared_memory,
                          ngx_shm_cycles[use].pool, n,
                          sizeof(ngx_shm_zone_t))
            != NGX_OK)
        {
            ngx_destroy_pool(ngx_shm_cycles[use].pool);
            return NULL;
        }

        ngx_shm_cycles[use].used = 1;
        ngx_shm_cycles[use].generation = ngx_shm_cycle_generation;
    }

    part = &ngx_shm_cycles[use].shared_memory.part;
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

        if (size && size != shm_zone[i].shm.size) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "the size %uz of shared memory zone \"%V\" "
                               "conflicts with already declared size %uz",
                               size, &shm_zone[i].shm.name,
                               shm_zone[i].shm.size);
            return NULL;
        }

        if (tag != shm_zone[i].tag) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                            "the shared memory zone \"%V\" is "
                            "already declared for a different use",
                            &shm_zone[i].shm.name);
            return NULL;
        }

        return &shm_zone[i];
    }

    shm_zone = ngx_list_push(&ngx_shm_cycles[use].shared_memory);

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
}


ngx_int_t
ngx_shm_cycle_init(ngx_cycle_t *cycle)
{
    ngx_int_t         use, last_use;
    ngx_uint_t        i, n;
    ngx_shm_zone_t   *shm_zone, *oshm_zone;
    ngx_list_part_t  *part, *opart;
    
    for (i = 0, use = last_use = -1; i < ngx_last_shm_cycle; i++) {

        ngx_shm_cycles[i].pool->log = cycle->log;

        if (!ngx_shm_cycles[i].used) {
            continue;
        }

        if (ngx_shm_cycles[i].generation == ngx_shm_cycle_generation) {
            use = i;
            continue;
        }

        if (ngx_shm_cycles[i].ready
            && (last_use == -1 || ngx_shm_cycles[i].generation
                                        > ngx_shm_cycles[last_use].generation))
        {
            last_use = i;
        }
    }

    if (use == -1) {
        return NGX_OK;
    }

    part = &ngx_shm_cycles[use].shared_memory.part;
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

        if (last_use == -1) {
            if (shm_zone[i].init(&shm_zone[i], NULL) != NGX_OK) {
                return NGX_ERROR;
            }

            continue;
        }

        opart = &ngx_shm_cycles[last_use].shared_memory.part;
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

    ngx_shm_cycles[use].ready = 1;

    return NGX_OK;
}


void ngx_free_old_shm_cycles(void)
{
    ngx_uint_t i, last;

    for (i = 0, last = -1; i < ngx_last_shm_cycle; i++) {

        if (!ngx_shm_cycles[i].used) {
            continue;
        }

        if (ngx_shm_cycles[i].generation < ngx_shm_cycle_generation) {
            ngx_close_shm_cycle(&ngx_shm_cycles[i]);
        } else {
            last = i;
        }
    }

    ngx_last_shm_cycle = last + 1;
}


static void
ngx_close_shm_cycle(ngx_shm_cycle_t *shm_cycle)
{
    ngx_uint_t        i;
    ngx_shm_zone_t   *shm_zone;
    ngx_list_part_t  *part;

    part = &shm_cycle->shared_memory.part;
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
            ngx_shm_free(&shm_zone[i].shm);
        }
    }

    ngx_destroy_pool(shm_cycle->pool);
    shm_cycle->ready = 0;
    shm_cycle->used = 0;
}


static ngx_int_t
ngx_init_zone_pool(ngx_cycle_t *cycle, ngx_shm_zone_t *zn)
{
    u_char           *file;
    ngx_slab_pool_t  *sp;

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
