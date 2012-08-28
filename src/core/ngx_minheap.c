
/* CopyRight (C) www.taobao.com
 */

#include <ngx_config.h>
#include <ngx_core.h>


void
ngx_minheap_insert(ngx_minheap_t *h, ngx_minheap_node_t *node)
{
    ngx_uint_t            parent, index;
    ngx_minheap_node_t  **p;

    if (h->nelts >= h->n) {
        h->elts = ngx_prealloc(h->pool,
                               h->elts, h->n * sizeof(ngx_minheap_node_t *),
                               h->n * 2 * sizeof(ngx_minheap_node_t *));
        if (h->elts == NULL) {
            ngx_log_error(NGX_LOG_EMERG, h->pool->log, 0,
                          "minheap realloc failed %d", h->n * 2);
            return;
        }
        h->n *= 2;
    }

    index = h->nelts++;
    parent = minheap_parent(index);

    p = (ngx_minheap_node_t **)h->elts;
    while (index && p[parent]->key > node->key) {
        (p[index] = p[parent])->index = index;
        index = parent;
        parent = minheap_parent(index);
    }
    (p[index] = node)->index = index;

    return;
}


void
ngx_minheap_delete(ngx_minheap_t *h, ngx_uint_t index)
{
    ngx_uint_t            son, parent;
    ngx_minheap_node_t  **p, *node;

    p = (ngx_minheap_node_t **) h->elts;
    node = p[--h->nelts];
    parent = minheap_parent(index);

    if (node->key < p[parent]->key) {
        while (parent && p[parent]->key > node->key) {
            (p[index] = p[parent])->index = index;
            index = parent;
            parent = minheap_parent(index);
        }

        (p[index] = node)->index = index;
    } else {
        son = minheap_right(index);
        while (son <= h->nelts) {
            son -= son == h->nelts || p[son] > p[son - 1];
            if (p[son]->key > node->key) {
                break;
            }

            (p[index] = p[son])->index = index;
            son = minheap_right(index = son);
        }

        (p[index] = node)->index = index;
    }
    return;
}
