
#include <ngx_core.h>
#include <ngx_heap.h>

#define NGX_HEAP_DEGREE     2

#define NGX_HEAP_PARENT(c)  ((c) >> 1)
#define NGX_HEAP_CHILD(p)   ((p) << 1)

#define NGX_HEAP_ARRAY_MIN_FAST                ngx_heap_array_min_fast
#define NGX_HEAP_ARRAY_MIN_SLOW(heap, child0)  child0


static inline ngx_uint_t
ngx_heap_array_min_fast(ngx_heap_t *heap, ngx_uint_t child0)
{

    if (NGX_HEAP_CMP(heap->array[child0],
                     heap->array[child0 + 1])) {
        return child0;
    }
    return child0 + 1;
}

#define NGX_HEAP_PREFIX     ngx_heap
#include <ngx_heap_template.h>


