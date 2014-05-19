
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_core.h>
#include <ngx_config.h>


#define ngx_segment_node_copy(s,t)  \
    (s)->key = (t)->key;            \
    (s)->data = (t)->data


static ngx_int_t
ngx_segment_tree_min(ngx_segment_node_t *one, ngx_segment_node_t *two)
{
    return two->key - one->key;
}


ngx_int_t
ngx_segment_tree_init(ngx_segment_tree_t *tree, ngx_uint_t num,
    ngx_pool_t *pool)
{
    tree->segments = ngx_pcalloc(pool,
                                ((num + 1) << 2) * sizeof(ngx_segment_node_t));
    if (tree->segments == NULL) {
        return NGX_ERROR;
    }

    tree->extreme = NGX_MAX_UINT32_VALUE;
    tree->pool = pool;
    tree->num = num;

    tree->cmp = ngx_segment_tree_min;
    tree->build = ngx_segment_tree_build;
    tree->insert = ngx_segment_tree_insert;
    tree->query = ngx_segment_tree_query;
    tree->del = ngx_segment_tree_delete;

    tree->segments[0].key = tree->extreme;
    return NGX_OK;
}


void
ngx_segment_tree_build(ngx_segment_tree_t *tree, ngx_int_t index, ngx_int_t l,
    ngx_int_t r)
{
    ngx_int_t   child, mid;
    if (l == r) {
        tree->segments[index].key = l;
        return;
    }

    child = index << 1;
    mid = (l + r) >> 1;

    ngx_segment_tree_build(tree, child, l, mid);
    ngx_segment_tree_build(tree, child + 1, mid + 1, r);

    if (tree->cmp(&tree->segments[child], &tree->segments[child + 1]) > 0) {
        ngx_segment_node_copy(&tree->segments[index], &tree->segments[child]);

    } else {
        ngx_segment_node_copy(&tree->segments[index],
                              &tree->segments[child + 1]);
    }
}


void
ngx_segment_tree_insert(ngx_segment_tree_t *tree, ngx_int_t index, ngx_int_t l,
    ngx_int_t r, ngx_int_t pos, ngx_segment_node_t *node)
{
    ngx_int_t   child, mid;
    if (l == r && l == pos) {
        ngx_segment_node_copy(&tree->segments[index], node);
        return;
    }

    child = index << 1;
    mid = (l + r) >> 1;

    if (pos <= mid) {
        ngx_segment_tree_insert(tree, child, l, mid, pos, node);

    } else {
        ngx_segment_tree_insert(tree, child + 1, mid + 1, r, pos, node);
    }

    if (tree->cmp(&tree->segments[child], &tree->segments[child + 1]) > 0) {
        ngx_segment_node_copy(&tree->segments[index], &tree->segments[child]);

    } else {
        ngx_segment_node_copy(&tree->segments[index],
                              &tree->segments[child + 1]);
    }
}


ngx_segment_node_t *
ngx_segment_tree_query(ngx_segment_tree_t *tree, ngx_int_t index, ngx_int_t l,
    ngx_int_t r, ngx_int_t ll, ngx_int_t rr)
{
    ngx_int_t  child, mid;
    ngx_segment_node_t *l_node, *r_node;

    if (ll > rr) {
        return &tree->segments[0];
    }

    if (l == ll && r == rr) {
        return &tree->segments[index];
    }

    child = index << 1;
    mid = (l + r) >> 1;

    if (rr <= mid) {
        return ngx_segment_tree_query(tree, child, l, mid, ll, rr);

    } else if (ll > mid) {
        return ngx_segment_tree_query(tree, child + 1, mid + 1, r, ll, rr);
    }

    l_node = ngx_segment_tree_query(tree, child, l, mid, ll, mid);
    r_node = ngx_segment_tree_query(tree, child + 1, mid + 1, r, mid + 1, rr);

    if (tree->cmp(l_node, r_node) > 0) {
        return l_node;
    }

    return r_node;
}


void
ngx_segment_tree_delete(ngx_segment_tree_t *tree, ngx_int_t index,
    ngx_int_t l, ngx_int_t r, ngx_int_t pos)
{
    ngx_int_t  child, mid;

    if (l == r && l == pos) {
        tree->segments[index].key = tree->extreme;
        return;
    }

    child = index << 1;
    mid = (l + r) >> 1;

    if (pos <= mid) {
        ngx_segment_tree_delete(tree, child, l, mid, pos);

    } else {
        ngx_segment_tree_delete(tree, child + 1, mid + 1, r, pos);
    }

    if (tree->cmp(&tree->segments[child], &tree->segments[child + 1]) > 0) {
        ngx_segment_node_copy(&tree->segments[index], &tree->segments[child]);

    } else {
        ngx_segment_node_copy(&tree->segments[index],
                              &tree->segments[child + 1]);
    }
}
