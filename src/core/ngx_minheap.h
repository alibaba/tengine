
/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#ifndef _NGX_MINHEAP_H_INCLUDE_
#define _NGX_MINHEAP_H_INCLUDE_


#include <ngx_config.h>
#include <ngx_core.h>


#define ngx_minheap_less(x, y) ((ngx_minheap_key_int_t) ((x) - (y)) <= 0)
#define ngx_minheap_child(i)   ((i << 1) + 2)
#define ngx_minheap_parent(i)  (i > 0 ? (i - 1) >> 1 : 0)
#define ngx_minheap4_child(i)  ((i << 2) + 1)
#define ngx_minheap4_parent(i) (i > 0 ? (i - 1) >> 2 : 0)


typedef ngx_uint_t  ngx_minheap_key_t;
typedef ngx_int_t   ngx_minheap_key_int_t;
typedef struct ngx_minheap_s ngx_minheap_t;
typedef struct ngx_minheap_node_s ngx_minheap_node_t;

struct ngx_minheap_s {
    void                  **elts;
    ngx_uint_t              nelts;
    ngx_uint_t              nalloc;

    ngx_pool_t             *pool;
};


struct ngx_minheap_node_s {
    ngx_uint_t              index;
    ngx_minheap_key_t       key;
};

void ngx_minheap_insert(ngx_minheap_t *h, ngx_minheap_node_t *node);
void ngx_minheap_delete(ngx_minheap_t *h, ngx_uint_t index);
void ngx_minheap4_insert(ngx_minheap_t *h, ngx_minheap_node_t *node);
void ngx_minheap4_delete(ngx_minheap_t *h, ngx_uint_t index);

#define ngx_minheap_min(h) ((h)->elts[0])

#endif
