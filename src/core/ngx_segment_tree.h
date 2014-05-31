
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_SEGMENT_TREE_H_INCLUDE_
#define _NGX_SEGMENT_TREE_H_INCLUDE_


#include <ngx_config.h>
#include <ngx_core.h>


typedef struct ngx_segment_node_s ngx_segment_node_t;
typedef struct ngx_segment_tree_s ngx_segment_tree_t;


typedef ngx_int_t (*ngx_segment_cmp_pt)(ngx_segment_node_t *one,
    ngx_segment_node_t *two);
typedef void (*ngx_segment_build_pt)(ngx_segment_tree_t *tree, ngx_int_t index,
    ngx_int_t l, ngx_int_t r);
typedef void (*ngx_segment_insert_pt)(ngx_segment_tree_t *tree, ngx_int_t index,
    ngx_int_t l, ngx_int_t r, ngx_int_t pos, ngx_segment_node_t *node);
typedef ngx_segment_node_t *(*ngx_segment_query_pt)(ngx_segment_tree_t *tree,
    ngx_int_t index, ngx_int_t l, ngx_int_t r, ngx_int_t ll, ngx_int_t rr);
typedef void (*ngx_segment_delete_pt)(ngx_segment_tree_t *tree, ngx_int_t index,
    ngx_int_t l, ngx_int_t r, ngx_int_t pos);

struct ngx_segment_node_s {
    ngx_int_t             key;
    void                 *data;
};

struct ngx_segment_tree_s {
    uint32_t              extreme;
    ngx_pool_t           *pool;
    ngx_uint_t            num;
    ngx_segment_node_t   *segments;

    ngx_segment_cmp_pt    cmp;
    ngx_segment_build_pt  build;
    ngx_segment_insert_pt insert;
    ngx_segment_query_pt  query;
    ngx_segment_delete_pt del;
};


void ngx_segment_tree_build(ngx_segment_tree_t *tree, ngx_int_t index,
    ngx_int_t l, ngx_int_t r);
void ngx_segment_tree_insert(ngx_segment_tree_t *tree, ngx_int_t index,
    ngx_int_t l, ngx_int_t r, ngx_int_t pos, ngx_segment_node_t *node);
ngx_segment_node_t *ngx_segment_tree_query(ngx_segment_tree_t *tree,
    ngx_int_t index, ngx_int_t l, ngx_int_t r, ngx_int_t ll, ngx_int_t rr);
void ngx_segment_tree_delete(ngx_segment_tree_t *tree, ngx_int_t index,
    ngx_int_t l, ngx_int_t r, ngx_int_t pos);
ngx_int_t ngx_segment_tree_init(ngx_segment_tree_t *tree, ngx_uint_t num,
    ngx_pool_t *pool);


#endif
