
/*
 *  Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_TRIE_H_INCLUDE_
#define _NGX_TRIE_H_INCLUDE_


#include <ngx_config.h>
#include <ngx_core.h>


#define NGX_TRIE_REVERSE            1
#define NGX_TRIE_CONTINUE           2


typedef struct ngx_trie_s           ngx_trie_t;
typedef struct ngx_trie_node_s      ngx_trie_node_t;

typedef ngx_trie_node_t *(*ngx_trie_insert_pt)(ngx_trie_t *trie,
    ngx_str_t *str, ngx_uint_t mode);
typedef ngx_int_t (*ngx_trie_build_clue_pt)(ngx_trie_t *trie);
typedef void *(*ngx_trie_query_pt)(ngx_trie_t *trie,
    ngx_str_t *str, ngx_int_t *pos, ngx_uint_t mode);


struct ngx_trie_node_s {
    void                           *value;
    ngx_trie_node_t                *search_clue;
    ngx_trie_node_t               **next;

    unsigned                        key:31;
    unsigned                        greedy:1;
};


struct ngx_trie_s {
    ngx_trie_node_t                *root;
    ngx_pool_t                     *pool;
    ngx_trie_insert_pt              insert;
    ngx_trie_query_pt               query;
    ngx_trie_build_clue_pt          build_clue;
};


ngx_trie_t *ngx_trie_create(ngx_pool_t *pool);
ngx_trie_node_t *ngx_trie_node_create(ngx_pool_t *pool);
ngx_trie_node_t *ngx_trie_insert(ngx_trie_t *trie, ngx_str_t *str,
    ngx_uint_t mode);
void *ngx_trie_query(ngx_trie_t *trie, ngx_str_t *str, ngx_int_t *pos,
    ngx_uint_t mode);
ngx_int_t ngx_trie_build_clue(ngx_trie_t *trie);


#endif /* _NGX_TRIE_H_INCLUDE_ */
