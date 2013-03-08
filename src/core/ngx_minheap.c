
/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>


void
ngx_minheap_insert(ngx_minheap_t *h, ngx_minheap_node_t *node)
{
    ngx_uint_t            parent, index;
    ngx_minheap_node_t  **p;

    if (h->nelts >= h->nalloc) {
        h->elts = ngx_prealloc(h->pool,
                               h->elts,
                               h->nalloc * sizeof(ngx_minheap_node_t *),
                               h->nalloc * 2 * sizeof(ngx_minheap_node_t *));
        if (h->elts == NULL) {
            ngx_log_error(NGX_LOG_EMERG, h->pool->log, 0,
                          "minheap2 realloc failed %d", h->nalloc * 2);
            return;
        }
        h->nalloc *= 2;
    }

    index = h->nelts++;
    parent = ngx_minheap_parent(index);

    p = (ngx_minheap_node_t **)h->elts;
    while (index && ngx_minheap_less(node->key, p[parent]->key)) {
        (p[index] = p[parent])->index = index;
        index = parent;
        parent = ngx_minheap_parent(index);
    }

    p[index] = node;
    p[index]->index = index;

    return;
}


void
ngx_minheap_delete(ngx_minheap_t *h, ngx_uint_t index)
{
    ngx_uint_t            child, parent;
    ngx_minheap_node_t  **p, *node;

    p = (ngx_minheap_node_t **) h->elts;
    node = p[--h->nelts];
    parent = ngx_minheap_parent(index);

    if (ngx_minheap_less(node->key, p[parent]->key)) {
        while (parent && ngx_minheap_less(node->key, p[parent]->key)) {
            p[index] = p[parent];
            p[index]->index = index;

            index = parent;
            parent = ngx_minheap_parent(index);
        }

        p[index] = node;
        p[index]->index = index;

    } else {
        child = ngx_minheap_child(index);
        while (child <= h->nelts) {
            child -= child == h->nelts
					 || ngx_minheap_less(p[child - 1], p[child]);
            if (ngx_minheap_less(node->key, p[child]->key)) {
                break;
            }

            p[index] = p[child];
            p[child]->index = index;

            index = child;
            child = ngx_minheap_child(index);
        }

        p[index] = node;
        p[index]->index = index;
    }
    return;
}


void
ngx_minheap4_insert(ngx_minheap_t *h, ngx_minheap_node_t *node)
{
    ngx_uint_t            parent, index;
    ngx_minheap_node_t  **p;

    if (h->nelts >= h->nalloc) {
        h->elts = ngx_prealloc(h->pool,
                               h->elts,
                               h->nalloc * sizeof(ngx_minheap_node_t*),
                               h->nalloc * 2 * sizeof(ngx_minheap_node_t *));
        if (h->elts == NULL) {
            ngx_log_error(NGX_LOG_EMERG, h->pool->log, 0,
                          "minheap4 realloc failed %d", h->nalloc * 2);
        }
    }

    index = h->nelts++;
    parent = ngx_minheap4_parent(index);

    p = (ngx_minheap_node_t **) h->elts;
    while (index && ngx_minheap_less(node->key, p[parent]->key)) {
        p[index] = p[parent];
        p[index]->index = index;
        index = parent;
        parent = ngx_minheap4_parent(index);
    }

    node->index = index;
    p[index] = node;
}


void
ngx_minheap4_delete(ngx_minheap_t *h, ngx_uint_t index)
{
    ngx_uint_t           child, parent, minpos;
    ngx_minheap_node_t **p, *node;

    p = (ngx_minheap_node_t **) h->elts;
    node = p[--h->nelts];
    parent = ngx_minheap4_parent(index);

    if (ngx_minheap_less(node->key, p[parent]->key)) {
        while (parent && ngx_minheap_less(node->key, p[parent]->key)) {
            p[index] = p[parent];
            p[index]->index = index;

            index = parent;
            parent = ngx_minheap4_parent(index);
        }

        p[index] = node;
        p[index]->index = index;

    } else {
        child = ngx_minheap4_child(index);

        while (child < h->nelts) {
            minpos = child;
            if (child + 1 < h->nelts
				&& ngx_minheap_less(p[child + 1]->key, p[minpos]->key)) {
                minpos = child + 1;
            }

            if (child + 2 < h->nelts
				&& ngx_minheap_less(p[child + 2]->key, p[minpos]->key)) {
                minpos = child + 2;
            }

            if (child + 3 < h->nelts
				&& ngx_minheap_less(p[child + 3]->key, p[minpos]->key)) {
                minpos = child + 3;
            }

            if (ngx_minheap_less(node->key, p[minpos]->key)) {
                break;
            }

            p[index] = p[minpos];
            p[index]->index = index;

            index = minpos;
            child = ngx_minheap4_child(index);
        }

        p[index] = node;
        p[index]->index = index;
    }

    return;
}
