
#include <ngx_core.h>
#include <ngx_heap.h>


#define NGX_HEAP_DEGREE           4
#define NGX_HEAP_PREFIX           ngx_heap4

#define NGX_HEAP_ARRAY_MIN_FAST   ngx_heap4_array_min_fast
#define NGX_HEAP_ARRAY_MIN_SLOW   ngx_heap4_array_min_slow

static inline ngx_uint_t
ngx_heap4_array_min_fast(ngx_heap_t *heap, ngx_uint_t child)
{
    ngx_uint_t min = child;

    if (NGX_HEAP_CMP(heap->array[++child], heap->array[min])) {
        min = child;
    }
    if (NGX_HEAP_CMP(heap->array[++child], heap->array[min])) {
        min = child;
    }
    if (NGX_HEAP_CMP(heap->array[++child], heap->array[min])) {
        min = child;
    }

    return min;
}

static inline ngx_uint_t
ngx_heap4_array_min_slow(ngx_heap_t *heap, ngx_uint_t child)
{
    ngx_uint_t min;

    min = child;

    if (++child <= heap->last && NGX_HEAP_CMP(heap->array[child], heap->array[min])) {
        min = child;
    }
    if (++child <= heap->last && NGX_HEAP_CMP(heap->array[child], heap->array[min])) {
        min = child;
    }

    /* skip the last child */

    return min;
}

#include <ngx_heap_template.h>

