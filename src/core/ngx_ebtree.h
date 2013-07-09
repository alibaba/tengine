
/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */

#ifndef _NGX_EBTREE_H_INCLUDE_
#define _NGX_EBTREE_H_INCLUDE_


#include <ngx_config.h>
#include <ngx_core.h>


#define ngx_ebtree_flsnz(a) ({                                                \
    register uint32_t x, bits = 0;                                            \
    x = (a);                                                                  \
    if (x & 0xffff0000) { x &= 0xffff0000; bits += 16;}                       \
    if (x & 0xff00ff00) { x &= 0xff00ff00; bits += 8;}                        \
    if (x & 0xf0f0f0f0) { x &= 0xf0f0f0f0; bits += 4;}                        \
    if (x & 0xcccccccc) { x &= 0xcccccccc; bits += 2;}                        \
    if (x & 0xaaaaaaaa) { x &= 0xaaaaaaaa; bits += 1;}                        \
    bits + 1;                                                                 \
    })                                                                        \


#define NGX_EB_NODE_BITS       1
#define NGX_EB_NODE_BRANCHES   (1 << NGX_EB_NODE_BITS)
#define NGX_EB_NODE_BRACH_MASK (NGX_EB_NODE_BRANCHES - 1)


#define NGX_EB_LEFT   0
#define NGX_EB_RIGHT  1
#define NGX_EB_LEAF   0
#define NGX_EB_NODE   1
#define NGX_EB_NORMAL 0
#define NGX_EB_UNIQUE 1


typedef struct ngx_ebtree_node_s ngx_ebtree_node_t;
typedef struct ngx_ebtree_s ngx_ebtree_t;


struct ngx_ebtree_node_s {
    ngx_ebtree_node_t   *branches[NGX_EB_NODE_BRANCHES];
    ngx_ebtree_node_t   *node;
    ngx_ebtree_node_t   *leaf;
    char                 bit;
    uint32_t             key;
    void                *data;
};


struct ngx_ebtree_s {
    ngx_pool_t        *pool;
    ngx_ebtree_node_t *root[NGX_EB_NODE_BRANCHES];
};


#define ngx_alloc_ebtree_node(tree)                                           \
    ngx_palloc((tree)->pool, sizeof(ngx_ebtree_node_t))


static ngx_inline ngx_ebtree_t *
ngx_ebtree_create(ngx_pool_t *pool)
{
    ngx_ebtree_t *tree;
    tree = ngx_pcalloc(pool, sizeof(ngx_ebtree_t));
    if (tree == NULL) {
        return NULL;
    }

    tree->root[NGX_EB_LEFT] = ngx_pcalloc(pool, sizeof(ngx_ebtree_node_t));
    if (tree->root[NGX_EB_LEFT] == NULL) {
        return NULL;
    }

    tree->pool = pool;
    return tree;
}


void ngx_ebtree_delete(ngx_ebtree_node_t *node);
ngx_ebtree_node_t *ngx_ebtree_insert(ngx_ebtree_t *root,
    ngx_ebtree_node_t *node);
ngx_ebtree_node_t *ngx_ebtree_lookup(ngx_ebtree_t *root, uint32_t key);
ngx_ebtree_node_t *ngx_ebtree_le(ngx_ebtree_t *root, uint32_t key);
ngx_ebtree_node_t *ngx_ebtree_ge(ngx_ebtree_t *root, uint32_t key);


static ngx_inline ngx_ebtree_node_t *
ngx_eb_dotag(ngx_ebtree_node_t *root, ngx_int_t tag)
{
    return (ngx_ebtree_node_t *) ((char *) root + tag);
}


static ngx_inline ngx_ebtree_node_t *
ngx_eb_untag(ngx_ebtree_node_t *root, ngx_int_t tag)
{
    return (ngx_ebtree_node_t *) ((char *) root - tag);
}


static ngx_inline ngx_int_t
ngx_eb_gettag(ngx_ebtree_node_t *root)
{
    return (uintptr_t)root & 1;
}

static ngx_inline ngx_ebtree_node_t *
ngx_eb_clrtag(ngx_ebtree_node_t *root)
{
    return (ngx_ebtree_node_t *) ((uintptr_t)root & ~1UL);
}

#endif /* _NGX_EBTREE_H_INCLUDE_ */
