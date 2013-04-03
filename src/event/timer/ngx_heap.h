
/*
 * the heap is not miniman heap or maximum heap, only used for timer.
 */

#ifndef _NGX_HEAP_INCLUDE_
#define _NGX_HEAP_INCLUDE_

#include <ngx_core.h>

typedef ngx_uint_t  ngx_heap_key_t;

#define NGX_HEAP_ROOT           1
/* same as ngx_timer_before */
#define NGX_HEAP_CMP_KEY(x, y)  ((ngx_int_t) (x - y) < 0)
#define NGX_HEAP_CMP(n1, n2)    NGX_HEAP_CMP_KEY((n1)->key, (n2)->key )


typedef struct ngx_heap_node_s {
    ngx_heap_key_t   key;
    ngx_uint_t       index;
    u_char           data;
} ngx_heap_node_t;

typedef struct ngx_heap_s {
    ngx_heap_node_t **array;
    ngx_uint_t        last;
    ngx_uint_t        max;
} ngx_heap_t;

static inline ngx_int_t
ngx_heap_init(ngx_heap_t *heap, ngx_pool_t *pool, ngx_uint_t max_size)
{
    heap->array = ngx_palloc(pool, (max_size + NGX_HEAP_ROOT) * sizeof(ngx_heap_node_t *));
    if (heap->array == NULL) {
        return NGX_ERROR;
    }
    heap->last = 0;
    heap->max = max_size;
    return NGX_OK;
}

static inline ngx_heap_node_t *
ngx_heap_min(ngx_heap_t *heap)
{
    if (heap->last) {
        return heap->array[NGX_HEAP_ROOT];
    }
    return NULL;
}

static inline ngx_int_t
ngx_heap_empty(ngx_heap_t *heap)
{
    return heap->last == 0;
}

void ngx_heap_insert(ngx_heap_t *heap, ngx_heap_node_t *node);
void ngx_heap_delete(ngx_heap_t *heap, ngx_heap_node_t *node);
void ngx_heap_adjust(ngx_heap_t *heap, ngx_heap_node_t *node);

/*
 * quad heap
 */

typedef ngx_heap_t      ngx_heap4_t;
typedef ngx_heap_node_t ngx_heap4_node_t;

#define ngx_heap4_init      ngx_heap_init
#define ngx_heap4_min       ngx_heap_min
#define ngx_heap4_empty     ngx_heap_empty

void ngx_heap4_insert(ngx_heap_t *heap, ngx_heap_node_t *node);
void ngx_heap4_delete(ngx_heap_t *heap, ngx_heap_node_t *node);
void ngx_heap4_adjust(ngx_heap_t *heap, ngx_heap_node_t *node);


#endif /* _NGX_HEAP_INCLUDE_ */
