/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include "ngx_comm_shm.h"


ngx_shm_pool_t * ngx_shm_create_pool(u_char * addr, size_t size)
{
    ngx_shm_pool_t * pool = (ngx_shm_pool_t *)addr;

    if (size < sizeof(ngx_shm_pool_t)) {
        return NULL;
    }

    pool->base = addr + sizeof(ngx_shm_pool_t);
    pool->pos = pool->base;
    pool->last = addr + size;

    pool->out_of_memory = 0;

    return pool;
}

void ngx_shm_pool_reset(ngx_shm_pool_t * pool)
{
    pool->pos = pool->base;
    pool->out_of_memory = 0;
}

ngx_int_t ngx_shm_pool_size(ngx_shm_pool_t * pool)
{
    return pool->last - pool->base;
}

ngx_int_t ngx_shm_pool_free_size(ngx_shm_pool_t * pool)
{
    return pool->last - pool->pos;
}

ngx_int_t ngx_shm_pool_used_rate(ngx_shm_pool_t * pool)
{
    ngx_int_t used = pool->pos - pool->base;
    ngx_int_t total = pool->last - pool->base;

    return used * 100 / total;
}

void *ngx_shm_pool_calloc(ngx_shm_pool_t * pool, size_t size)
{
    void * p = NULL;

    if (pool->last - pool->pos >= (ngx_int_t)size) {
        p = pool->pos;
        pool->pos += size;
        memset(p, 0, size);
    } else {
        pool->out_of_memory = 1;
    }

    return p;
}

ngx_int_t ngx_shm_pool_out_of_memory(ngx_shm_pool_t * pool)
{
    return pool->out_of_memory;
}

ngx_str_t *ngx_shm_pool_calloc_str(ngx_shm_pool_t * pool, size_t str_size)
{
    ngx_str_t * str;
    ngx_int_t buf_len = sizeof(ngx_str_t) + str_size;

    u_char * p = ngx_shm_pool_calloc(pool, buf_len);
    if (p == NULL) {
        return NULL;
    }

    str = (ngx_str_t*)p;
    str->data = p + sizeof(ngx_str_t);
    str->len = 0;

    return str;
}


ngx_shm_array_t* ngx_shm_array_create(ngx_shm_pool_t * pool,
    ngx_int_t max_n,
    ngx_int_t size)
{
    u_char * addr;
    
    addr = ngx_shm_pool_calloc(pool, sizeof(ngx_shm_array_t) + max_n * size);
    if (addr == NULL) {
        return NULL;
    }

    ngx_shm_array_t * a = (ngx_shm_array_t *)addr;

    a->elts = addr + sizeof(ngx_shm_array_t);
    a->size = size;
    a->nelts = 0;
    a->nalloc = max_n;

    return a;
}

void *ngx_shm_array_push(ngx_shm_array_t *a)
{
    void * p = NULL;

    if (a == NULL) {
        return NULL;
    }
    if (a->nelts == a->nalloc) {
        return NULL;
    }

    p = (u_char*)a->elts + a->nelts * a->size;

    a->nelts ++;

    return p;
}

void *ngx_shm_array_push_n(ngx_shm_array_t *a, ngx_uint_t n)
{
    void * p = NULL;

    if (a == NULL) {
        return NULL;
    }
    if (a->nelts + n > a->nalloc) {
        return NULL;
    }

    p = (u_char*)a->elts + a->nelts * a->size;

    a->nelts += n;

    return p;
}

void ngx_shm_sort_array(ngx_shm_array_t *a, ngx_shm_compar_func c)
{
    if (a == NULL) {
        return;
    }
    qsort(a->elts, a->nelts, a->size, c);
}

void * ngx_shm_search_array(ngx_shm_array_t *a, const void * key, ngx_shm_compar_func c)
{
    void * res = NULL;
    if (a == NULL || key == NULL) {
        return NULL;
    }
    res = bsearch(key, a->elts, a->nelts, a->size, c);
    return res;
}

typedef struct {
    ngx_queue_t  hash_node;
    void        *data;
} ngx_shm_hash_node_t;


ngx_shm_hash_t *ngx_shm_hash_create(ngx_shm_pool_t * pool,
    ngx_int_t bucket_size,
    ngx_shm_hash_calc_func hash_func,
    ngx_shm_compar_func compar_func)
{
    ngx_shm_hash_t      *table = NULL;
    u_char              *addr;
    ngx_int_t            table_size;
    ngx_int_t            i;

    if (hash_func == NULL || compar_func == NULL) {
        return NULL;
    }

    table_size = sizeof(ngx_shm_hash_t) + bucket_size * sizeof(ngx_queue_t);

    addr = ngx_shm_pool_calloc(pool, table_size);
    if (addr == NULL) {
        return NULL;
    }

    table = (ngx_shm_hash_t*)addr;

    table->bucket_size = bucket_size;
    table->hash_func = hash_func;
    table->compar_func = compar_func;
    table->pool = pool;

    for (i = 0; i < bucket_size; i++) {
        ngx_queue_init(&table->buckets[i]);
    }

    return table;
}

ngx_int_t ngx_shm_hash_add(ngx_shm_hash_t * table, void * elem)
{
    ngx_shm_hash_node_t * node = NULL;
    ngx_uint_t hash = 0;

    node = ngx_shm_pool_calloc(table->pool, sizeof(ngx_shm_hash_node_t));
    if (node == NULL) {
        return NGX_ERROR;
    }

    node->data = elem;
    hash = table->hash_func(elem);

    ngx_queue_insert_head(&table->buckets[hash % table->bucket_size], &node->hash_node);

    return NGX_OK;
}

ngx_int_t
ngx_shm_hash_del(ngx_shm_hash_t * table, void * elem)
{
    ngx_uint_t             hash;
    ngx_queue_t           *slot;
    ngx_queue_t           *q;
    ngx_shm_hash_node_t   *node;

    if (table == NULL) {
        return NGX_ERROR;
    }
    hash = table->hash_func(elem);

    slot = &table->buckets[hash % table->bucket_size];

    for (q = ngx_queue_head(slot);
         q != ngx_queue_sentinel(slot);
         q = ngx_queue_next(q))
    {
        node = ngx_queue_data(q, ngx_shm_hash_node_t, hash_node);
        
        if (table->compar_func(node->data, elem) == 0) {
            ngx_queue_remove(&node->hash_node);
            break;
        }
    }

    return NGX_OK;
}

void * ngx_shm_hash_get(ngx_shm_hash_t * table, void * elem)
{
    ngx_uint_t               hash;
    ngx_queue_t             *slot;
    ngx_queue_t             *q;
    ngx_shm_hash_node_t     *node;

    if (table == NULL) {
        return NULL;
    }
    hash = table->hash_func(elem);

    slot = &table->buckets[hash % table->bucket_size];

    if (ngx_queue_empty(slot)) {
        return NULL;
    }

    for (q = ngx_queue_head(slot);
         q != ngx_queue_sentinel(slot);
         q = ngx_queue_next(q))
    {
        node = ngx_queue_data(q, ngx_shm_hash_node_t, hash_node);
        
        if (table->compar_func(node->data, elem) == 0) {
            return node->data;
        }
    }

    return NULL;
}


ngx_int_t ngx_shm_str_copy(ngx_shm_pool_t * pool, ngx_str_t * dst, ngx_str_t * src)
{
    dst->data = ngx_shm_pool_calloc(pool, src->len);
    if (dst->data == NULL) {
        return NGX_ERROR;
    }

    dst->len = src->len;
    memcpy(dst->data, src->data, dst->len);

    return NGX_OK;
}


