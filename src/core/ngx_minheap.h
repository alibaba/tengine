
/* CopyRight (C) www.taobao.com
 */

#ifndef _NGX_MINHEAP_H_INCLUDE_
#define _NGX_MINHEAP_H_INCLUDE_


#include <ngx_config.h>
#include <ngx_core.h>


#define minheap_left(i)   ((i << 1) + 1)
#define minheap_right(i)  ((i << 1) + 2)
#define minheap_parent(i) (i > 0 ? (i - 1) >> 1: 0)


typedef ngx_uint_t  ngx_minheap_key_t;
typedef ngx_int_t   ngx_minheap_key_int_t;
typedef struct ngx_minheap_s ngx_minheap_t;
typedef struct ngx_minheap_node_s ngx_minheap_node_t;

struct ngx_minheap_s {
    void                  **elts;
    ngx_uint_t              n, nelts;

    ngx_pool_t             *pool;
};


struct ngx_minheap_node_s {
    ngx_uint_t              index;
    ngx_minheap_key_t       key;
};

void ngx_minheap_insert(ngx_minheap_t *h, ngx_minheap_node_t *node);
void ngx_minheap_delete(ngx_minheap_t *h, ngx_uint_t index);

#define ngx_minheap_init(h, n, pool)                      \
    (h)->n = n;                                           \
    (h)->nelts = 0;                                       \
    (h)->pool = pool

#define ngx_minheap_min(h) ((h)->elts[0])

#endif
