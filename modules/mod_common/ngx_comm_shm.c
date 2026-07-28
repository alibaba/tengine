

#include "ngx_comm_shm.h"
#include "ngx_comm_string.h"


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

/* 共享内存散列表 */
typedef struct {
    struct hlist_node  hash_node;
    void *data;
} ngx_shm_hash_node_t;


ngx_shm_hash_t *ngx_shm_hash_create(ngx_shm_pool_t * pool,
    ngx_int_t bucket_size,
    ngx_shm_hash_calc_func hash_func,
    ngx_shm_compar_func compar_func)
{
    ngx_shm_hash_t * table = NULL;
    u_char * addr;
    ngx_int_t table_size;

    if (hash_func == NULL || compar_func == NULL) {
        return NULL;
    }

    table_size = sizeof(ngx_shm_hash_t) + bucket_size * sizeof(struct hlist_head);

    addr = ngx_shm_pool_calloc(pool, table_size);
    if (addr == NULL) {
        return NULL;
    }

    table = (ngx_shm_hash_t*)addr;

    table->bucket_size = bucket_size;
    table->hash_func = hash_func;
    table->compar_func = compar_func;
    table->pool = pool;

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

    hlist_add_head(&node->hash_node, &table->buckets[hash % table->bucket_size]);

    return NGX_OK;
}

ngx_int_t
ngx_shm_hash_del(ngx_shm_hash_t * table, void * elem)
{
    ngx_uint_t             hash;
    struct hlist_head     *slot;
    struct hlist_node     *q;
    ngx_shm_hash_node_t   *node;

    if (table == NULL) {
        return NGX_ERROR;
    }
    hash = table->hash_func(elem);

    slot = &table->buckets[hash % table->bucket_size];

    hlist_for_each(q, slot) {
        node = hlist_entry(q, ngx_shm_hash_node_t, hash_node);

        if (table->compar_func(node->data, elem) == 0) {
            hlist_del(&node->hash_node);
            break;
        }
    }

    return NGX_OK;
}

void * ngx_shm_hash_get(ngx_shm_hash_t * table, void * elem)
{
    ngx_uint_t             hash;
    struct hlist_head     *slot;
    struct hlist_node     *q;
    ngx_shm_hash_node_t   *node;

    if (table == NULL) {
        return NULL;
    }
    hash = table->hash_func(elem);

    slot = &table->buckets[hash % table->bucket_size];

    if (!slot) {
        return NULL;
    }

    hlist_for_each(q, slot) {
        node = hlist_entry(q, ngx_shm_hash_node_t, hash_node);

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



/*****************************/

ngx_shm_lockless_hash_t *ngx_shm_lockless_hash_create(ngx_shm_pool_t * pool,
    ngx_int_t bucket_size,
    ngx_int_t max_n,
    ngx_shm_hash_calc_func hash_func,
    ngx_shm_compar_func compar_func)
{
    ngx_shm_lockless_hash_t * table = NULL;
    u_char * addr;
    ngx_int_t table_size;
    ngx_int_t pool_size;

    if (max_n <= 0) {
        return NULL;
    }

    if (hash_func == NULL || compar_func == NULL) {
        return NULL;
    }

    table_size = sizeof(ngx_shm_lockless_hash_t) + bucket_size * sizeof(ngx_shm_lockless_hash_bucket_t);
    pool_size = sizeof(ngx_shm_pool_t) + max_n * sizeof(ngx_shm_lockless_hash_node_t);

    addr = ngx_shm_pool_calloc(pool, table_size + pool_size);
    if (addr == NULL) {
        return NULL;
    }

    table = (ngx_shm_lockless_hash_t*)addr;

    table->bucket_size = bucket_size;
    table->hash_func = hash_func;
    table->compar_func = compar_func;
    table->pool = ngx_shm_create_pool(addr + table_size, pool_size);
    table->max_n = max_n;
    table->used_n = 0;

    if (table->pool == NULL) {
        return NULL;
    }

    return table;
}

ngx_int_t ngx_shm_lockless_hash_add(ngx_shm_lockless_hash_t * table, void * elem)
{
    ngx_shm_lockless_hash_node_t * node = NULL;
    ngx_uint_t hash = 0;
    ngx_shm_lockless_hash_bucket_t *bucket = NULL;

    ngx_shm_lockless_hash_node_t **p;

    hash = table->hash_func(elem);

    bucket = &table->buckets[hash % table->bucket_size];
    
    p = &bucket->head;
    while (*p != NULL) {
        if (table->compar_func((*p)->data, elem) == 0) {
            return NGX_DONE;
        }
        p = &(*p)->next;
    }

    node = ngx_shm_pool_calloc(table->pool, sizeof(ngx_shm_lockless_hash_node_t));
    if (node == NULL) {
        return NGX_ERROR;
    }

    node->data = elem;

    *p = node;

    ngx_atomic_fetch_add(&bucket->count, 1);

    table->used_n ++;

    return NGX_OK;
}

void * ngx_shm_lockless_hash_get(ngx_shm_lockless_hash_t * table, void * elem)
{
    ngx_uint_t             hash;
    ngx_shm_lockless_hash_node_t   *node;
    ngx_shm_lockless_hash_bucket_t * bucket = NULL;
    ngx_int_t               i;

    if (table == NULL) {
        return NULL;
    }
    hash = table->hash_func(elem);

    bucket = &table->buckets[hash % table->bucket_size];

    node = bucket->head;
    for (i = 0; i < bucket->count; i++) {
        if (node == NULL) {
            return NULL;
        }
        if (table->compar_func(node->data, elem) == 0) {
            return node->data;
        }
        node = node->next;
    }

    return NULL;
}

void ngx_shm_lockless_hash_capacity(ngx_shm_lockless_hash_t * table,
                        ngx_int_t *elem_rate)
{
    if (table->max_n != 0) {
        *elem_rate = table->used_n * 100 / table->max_n;
    } else {
        *elem_rate = 100;
    }
}


void *
ngx_shm_hash_get_by_node(struct hlist_node *node)
{
    if (node == NULL) {
        return NULL;
    }
    
    ngx_shm_hash_node_t* hnode = hlist_entry(node, ngx_shm_hash_node_t, hash_node);

    return hnode->data;
}

#define MAX_PATH_TRIE_SEGMENT   64

int ngx_shm_trie_node_compar_func(const void * p1, const void* p2) {
    ngx_shm_path_trie_node_t * n1 = p1;
    ngx_shm_path_trie_node_t * n2 = p2;
    return ngx_comm_strcasecmp(&n1->segment, &n2->segment);
}

ngx_uint_t ngx_shm_trie_node_hash_func(const void * p) {
    ngx_shm_path_trie_node_t * n = p;
    return ngx_hash_key_lc(n->segment.data, n->segment.len);
}

ngx_shm_path_trie_t*
ngx_shm_trie_create(ngx_shm_pool_t * pool, ngx_int_t bucket_size)
{
    ngx_shm_path_trie_t *trie;
    trie = ngx_shm_pool_calloc(pool, sizeof(ngx_shm_path_trie_t));
    if (trie == NULL) {
        return NULL;
    }

    trie->pool = pool;
    trie->bucket_size = bucket_size;
    trie->nodes = ngx_shm_pool_calloc(trie->pool, sizeof(ngx_shm_path_trie_node_t));
    if (trie->nodes == NULL) {
        return NULL;
    }

    return trie;
}

ngx_int_t
ngx_shm_trie_add(ngx_shm_path_trie_t *trie, ngx_str_t *path, void *data)
{
    ngx_int_t   i, segment_n, rc;
    ngx_str_t   segments[MAX_PATH_TRIE_SEGMENT];

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                  "|ingress|shm tries add path|%V|", path);

    if (trie == NULL) {
        return NGX_ERROR;
    }

    ngx_str_t prefix = *path;

    /* remove start '/' */
    if (prefix.len > 0 && prefix.data[0] == '/') {
        prefix.data ++;
        prefix.len --;
    }
    /* remove end '/' */
    if (prefix.len > 0 && prefix.data[prefix.len - 1] == '/') {
        prefix.len --;
    }

    segment_n = ngx_comm_split_string(segments, MAX_PATH_TRIE_SEGMENT, prefix.data, prefix.data + prefix.len, '/');
    
    if (segment_n == 0) {
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                      "|ingress|shm tries add root|");
        trie->nodes->data = data;
        return NGX_OK;
    }

    ngx_shm_path_trie_node_t *p = trie->nodes;
    for (i = 0; i < segment_n; i++) {
        /* 对每一个前缀，创建一个 hash 表 */
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                      "|ingress|shm tries add path|segment|%V|", &segments[i]);

        if (p->hs == NULL) {
            p->hs = ngx_shm_hash_create(trie->pool, trie->bucket_size, ngx_shm_trie_node_hash_func, ngx_shm_trie_node_compar_func);
            if (p->hs == NULL) {
                return NGX_ERROR;
            }
        }

        ngx_shm_path_trie_node_t *node = ngx_shm_hash_get(p->hs, &segments[i]);
        if (node == NULL) {
            node = ngx_shm_pool_calloc(trie->pool, sizeof(ngx_shm_path_trie_node_t));
            if (node == NULL) {
                return NGX_ERROR;
            }

            node->segment.data = ngx_shm_pool_calloc(trie->pool, segments[i].len);
            if (node->segment.data == NULL) {
                return NGX_ERROR;
            }
            ngx_memcpy(node->segment.data, segments[i].data, segments[i].len);
            node->segment.len = segments[i].len;

            rc = ngx_shm_hash_add(p->hs, node);
            if (rc == NGX_ERROR) {
                return NGX_ERROR;
            }
        }

        p = node;
    }

    if (p == NULL) {
        return NGX_ERROR;
    }

    p->data = data;
    
    return NGX_OK;
}

void*
ngx_shm_trie_search(ngx_shm_path_trie_t *trie, ngx_str_t *path)
{
    ngx_int_t   i, segment_n, rc;
    ngx_str_t   segments[MAX_PATH_TRIE_SEGMENT];

    if (trie == NULL) {
        return NULL;
    }

    ngx_str_t prefix = *path;

    /* remove start '/' */
    if (prefix.len > 0 && prefix.data[0] == '/') {
        prefix.data ++;
        prefix.len --;
    }
    /* remove end '/' */
    if (prefix.len > 0 && prefix.data[prefix.len - 1] == '/') {
        prefix.len --;
    }

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                  "|ingress|search tries path|%V|", path);

    void *res_data = NULL;
    
    segment_n = ngx_comm_split_string(segments, MAX_PATH_TRIE_SEGMENT, prefix.data, prefix.data + prefix.len, '/');

    ngx_shm_path_trie_node_t *p = trie->nodes;
    for (i = 0; i < segment_n; i++) {
        if (p == NULL) {
            ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                          "|ingress|search tries path|p is NULL|%V|", &segments[i]);
            goto ret;
        }

        if (p->hs == NULL) {
            ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                          "|ingress|search tries path|hs is NULL|%V|", &segments[i]);
            goto ret;
        }

        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                      "|ingress|search tries path|segment|%V|", &segments[i]);

        ngx_shm_path_trie_node_t *node = ngx_shm_hash_get(p->hs, &segments[i]);
        if (node == NULL) {
            goto ret;
        }

        if (node->data != NULL) {
            ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                          "|ingress|search tries path hit|segment|%V|", &segments[i]);
            res_data = node->data;
        }

        p = node;
    }

ret:
    if (res_data == NULL) {
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                      "|ingress|search tries path use root|");
        return trie->nodes->data;
    }
    
    return res_data;
}
