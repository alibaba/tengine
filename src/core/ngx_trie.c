
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>


#define NGX_TRIE_MAX_QUEUE_SIZE     300
#define NGX_TRIE_KIND               256


ngx_trie_t *
ngx_trie_create(ngx_pool_t *pool)
{
    ngx_trie_t *trie;

    trie = ngx_palloc(pool, sizeof(ngx_trie_t));
    if (trie == NULL) {
        return NULL;
    }

    trie->root = ngx_trie_node_create(pool);
    if (trie->root == NULL) {
        return NULL;
    }

    trie->pool = pool;
    trie->insert = ngx_trie_insert;
    trie->query = ngx_trie_query;
    trie->build_clue = ngx_trie_build_clue;

    return trie;
}


ngx_trie_node_t *
ngx_trie_node_create(ngx_pool_t *pool)
{
    ngx_trie_node_t *node;

    node = ngx_pcalloc(pool, sizeof(ngx_trie_node_t));
    if (node == NULL) {
        return NULL;
    }

    return node;
}


ngx_trie_node_t *
ngx_trie_insert(ngx_trie_t *trie, ngx_str_t *str, ngx_uint_t mode)
{
    size_t           i;
    ngx_int_t        pos, step, index;
    ngx_trie_node_t *p, *root;

    root = trie->root;
    i = 0;

    if (mode & NGX_TRIE_REVERSE) {
        pos = str->len;
        step = -1;
    } else {
        pos = -1;
        step = 1;
    }

    p = root;

    while (i < str->len) {
        pos = pos + step;
        index = str->data[pos];

        if (index < 0 || index >= NGX_TRIE_KIND) {
            continue;
        }

        if (p->next == NULL) {
            p->next = ngx_pcalloc(trie->pool,
                                  NGX_TRIE_KIND * sizeof(ngx_trie_node_t *));

            if (p->next == NULL) {
                return NULL;
            }
        }

        if (p->next[index] == NULL) {
            p->next[index] = ngx_trie_node_create(trie->pool);
            if (p->next[index] == NULL) {
                return NULL;
            }
        }

        p = p->next[index];
        i++;
    }

    p->key = str->len;
    if (mode & NGX_TRIE_CONTINUE) {
        p->greedy = 1;
    }

    return p;
}


ngx_int_t
ngx_trie_build_clue(ngx_trie_t *trie)
{
    ngx_int_t        i, head, tail;
    ngx_trie_node_t *q[NGX_TRIE_MAX_QUEUE_SIZE], *p, *t, *root;

    head = tail = 0;
    root = trie->root;
    q[head++] = root;
    root->search_clue = NULL;

    while (head != tail) {
        t = q[tail++];
        tail %= NGX_TRIE_MAX_QUEUE_SIZE;

        if (t->next == NULL) {
            continue;
        }

        p = NULL;

        for (i = 0; i< NGX_TRIE_KIND; i++) {
            if (t->next[i] == NULL) {
                continue;
            }

            if (t == root) {
                t->next[i]->search_clue = root;

                q[head++] = t->next[i];
                head %= NGX_TRIE_MAX_QUEUE_SIZE;

                continue;
            }

            p = t->search_clue;

            while (p != NULL) {
                if (p->next !=NULL && p->next[i] != NULL) {
                    t->next[i]->search_clue = p->next[i];
                    break;
                }
                p = p->search_clue;
            }

            if (p == NULL) {
                t->next[i]->search_clue = root;
            }

            q[head++] = t->next[i];
            head %= NGX_TRIE_MAX_QUEUE_SIZE;
        }
    }

    return NGX_OK;
}


void *
ngx_trie_query(ngx_trie_t *trie, ngx_str_t *str, ngx_int_t *version_pos,
    ngx_uint_t mode)
{
    void            *value;
    size_t           i;
    ngx_int_t        step, pos, index;
    ngx_trie_node_t *p, *root;

    value = NULL;
    root = trie->root;
    p = root;
    i = 0;

    if (mode & NGX_TRIE_REVERSE) {
        pos = str->len;
        step = -1;
    } else {
        pos = -1;
        step = 1;
    }

    if (p->next == NULL) {
        return NULL;
    }

    while (i < str->len) {
        pos += step;
        index = str->data[pos];
        if (index < 0 || index >= NGX_TRIE_KIND) {
            index = 0;
        }

        while (p->next[index] == NULL) {
            if (p == root) {
                break;
            }
            p = p->search_clue;
        }

        p = p->next[index];
        p = p == NULL ? root : p;
        if (p->key) {
            value = p->value;
            *version_pos = pos + p->key;
            if (!p->greedy) {
                return value;
            }
            p = root;
        }

        i++;
    }

    return value;
}
