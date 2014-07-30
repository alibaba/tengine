

#ifndef NGX_HEAP_PREFIX
#error "this file should only be used in ngx_heap.c or ngx_heap4.c"
#endif

#define NGX_HEAP_CAT(A, B)           NGX_HEAP_CAT_I(A, B)
#define NGX_HEAP_CAT_I(A, B)         A ## B

#define NGX_HEAP_UP         NGX_HEAP_CAT(NGX_HEAP_PREFIX, _up)
#define NGX_HEAP_DOWN       NGX_HEAP_CAT(NGX_HEAP_PREFIX, _down)
#define NGX_HEAP_INSERT     NGX_HEAP_CAT(NGX_HEAP_PREFIX, _insert)
#define NGX_HEAP_DELETE     NGX_HEAP_CAT(NGX_HEAP_PREFIX, _delete)
#define NGX_HEAP_ADJUST     NGX_HEAP_CAT(NGX_HEAP_PREFIX, _adjust)

#ifndef NGX_HEAP_PARENT
/*
 * CHILD = PARENT * DEGREE - OFFSET
 * PARENT = (CHILD + OFFSET) / DEGREE
 * ROOT + 1 = ROOT * DEGREE - OFFSET
 */
#define NGX_HEAP_OFFSET     (NGX_HEAP_ROOT * (NGX_HEAP_DEGREE - 1) - 1)

#define NGX_HEAP_PARENT(c)  (((c) + NGX_HEAP_OFFSET) / NGX_HEAP_DEGREE)
#define NGX_HEAP_CHILD(p)   ((p) * NGX_HEAP_DEGREE - NGX_HEAP_OFFSET)

#endif

#ifndef NGX_HEAP_ARRAY_MIN_FAST

#define NGX_HEAP_ARRAY_MIN_FAST(heap, child0)  ngx_heap_array_min((heap)->array, child0, child0 + NGX_HEAP_DEGREE)
#define NGX_HEAP_ARRAY_MIN_SLOW(heap, child0)  ngx_heap_array_min((heap)->array, child0, (heap)->last + 1)

static inline ngx_uint_t
ngx_heap_array_min(ngx_heap_node_t **array, ngx_uint_t begin, ngx_uint_t end)
{
    ngx_uint_t min = begin;

    while (++begin < end) {
        if (NGX_HEAP_CMP(array[begin], array[min])) {
            min = begin;
        }
    }

    return min;
}

#endif

/* percolate up */
static inline void
NGX_HEAP_UP (ngx_heap_t *heap, ngx_heap_node_t *node)
{
    ngx_uint_t          index, parent;
    ngx_heap_node_t   **array = heap->array;

    index = node->index;
    parent = NGX_HEAP_PARENT(index);

    while (parent
            && NGX_HEAP_CMP(node,array[parent])) {

        array[index] = array [parent];
        array[index]->index = index;

        index = parent;
        parent = NGX_HEAP_PARENT(index);
    }

    array [index] = node;
    node->index = index;
}

/* percolate down */
static inline void
NGX_HEAP_DOWN (ngx_heap_t *heap, ngx_heap_node_t *node)
{
    ngx_uint_t index, child;
    ngx_heap_node_t **array = heap->array;

    index = node->index;
    child = NGX_HEAP_CHILD(index);

    while (child + NGX_HEAP_DEGREE - 1 <= heap->last) {

        child = NGX_HEAP_ARRAY_MIN_FAST(heap, child);

        if (NGX_HEAP_CMP(array[child], node) ) {
            array[index] = array[child];
            array[index]->index = index;
            index = child;
            child = NGX_HEAP_CHILD(index);
            continue;

        }

        array[index] = node;
        node->index = index;
        return;
    }

    if ( child <= heap->last) {

        child = NGX_HEAP_ARRAY_MIN_SLOW(heap, child);

        if (NGX_HEAP_CMP(array[child], node)) {
            array[index] = array[child];
            array[index]->index = index;
            index = child;
        }
    }

    array[index] = node;
    node->index = index;
}

void
NGX_HEAP_INSERT(ngx_heap_t *heap, ngx_heap_node_t *node)
{
    heap->last++;
    /* TODO ASSERT(heap->last < heap->max) */
    heap->array[heap->last] = node;
    node->index = heap->last;
    NGX_HEAP_UP(heap, node);
}

void
NGX_HEAP_DELETE(ngx_heap_t *heap, ngx_heap_node_t *node)
{
    ngx_uint_t index = node->index;

    heap->last --;

    if (index == heap->last + 1) {
        return;
    }

    heap->array[index] = heap->array[heap->last + 1];
    heap->array[index]->index = index;

    if (node->index > NGX_HEAP_ROOT
            && NGX_HEAP_CMP(node, heap->array[NGX_HEAP_PARENT(node->index)])) {
        NGX_HEAP_UP(heap, heap->array[index]);
    } else {
        NGX_HEAP_DOWN(heap, heap->array[index]);
    }
}

void
NGX_HEAP_ADJUST(ngx_heap_t *heap, ngx_heap_node_t *node)
{

    if (node->index > NGX_HEAP_ROOT
            && NGX_HEAP_CMP(node, heap->array[NGX_HEAP_PARENT(node->index)])) {
        NGX_HEAP_UP(heap, node);
    } else {
        NGX_HEAP_DOWN(heap, node);
    }
}


