
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>


static ngx_int_t ngx_list_delete_elt(ngx_list_t *l, ngx_list_part_t *cur,
    ngx_uint_t i);


ngx_list_t *
ngx_list_create(ngx_pool_t *pool, ngx_uint_t n, size_t size)
{
    ngx_list_t  *list;

    list = ngx_palloc(pool, sizeof(ngx_list_t));
    if (list == NULL) {
        return NULL;
    }

    list->part.elts = ngx_palloc(pool, n * size);
    if (list->part.elts == NULL) {
        return NULL;
    }

    list->part.nelts = 0;
    list->part.next = NULL;
    list->last = &list->part;
    list->size = size;
    list->nalloc = n;
    list->pool = pool;

    return list;
}


void *
ngx_list_push(ngx_list_t *l)
{
    void             *elt;
    ngx_list_part_t  *last;

    last = l->last;

    if (last->nelts == l->nalloc) {

        /* the last part is full, allocate a new list part */

        last = ngx_palloc(l->pool, sizeof(ngx_list_part_t));
        if (last == NULL) {
            return NULL;
        }

        last->elts = ngx_palloc(l->pool, l->nalloc * l->size);
        if (last->elts == NULL) {
            return NULL;
        }

        last->nelts = 0;
        last->next = NULL;

        l->last->next = last;
        l->last = last;
    }

    elt = (char *) last->elts + l->size * last->nelts;
    last->nelts++;

    return elt;
}


ngx_int_t
ngx_list_delete(ngx_list_t *list, void *elt)
{
    char                         *data;
    ngx_uint_t                   i;
    ngx_list_part_t             *part;

    part = &list->part;
    data = part->elts;

    for (i = 0; /* void */; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            i = 0;
            part = part->next;
            data = part->elts;
        }

        if ((data + i * list->size)  == (char *) elt) {
            return ngx_list_delete_elt(list, part, i);
        }
    }

    return NGX_ERROR;
}


static ngx_int_t
ngx_list_delete_elt(ngx_list_t *list, ngx_list_part_t *cur, ngx_uint_t i)
{
    char                        *data;
    ngx_list_part_t             *new, *part;

    data = cur->elts;

    if (i == 0) {
        cur->elts = (char *) cur->elts + list->size;
        cur->nelts--;

        if (cur == list->last) {
            if (list->nalloc > 1) {
                list->nalloc--;
                return NGX_OK;
            }

            part = &list->part;
            while (part->next != cur) {
                if (part->next == NULL) {
                    return NGX_ERROR;
                }
                part = part->next;
            }

            part->next = NULL;
            list->last = part;

            return NGX_OK;
        }

        if (cur->nelts == 0) {
            part = &list->part;
            while (part->next != cur) {
                if (part->next == NULL) {
                    return NGX_ERROR;
                }
                part = part->next;
            }

            part->next = cur->next;

            return NGX_OK;
        }

        return NGX_OK;
    }

    if (i == cur->nelts - 1) {
        cur->nelts--;

        if (cur == list->last) {
            list->nalloc--;
        }

        return NGX_OK;
    }

    new = ngx_palloc(list->pool, sizeof(ngx_list_part_t));
    if (new == NULL) {
        return NGX_ERROR;
    }

    new->elts = data + list->size * (i + 1);
    new->nelts = cur->nelts - i - 1;
    new->next = cur->next;

    list->nalloc = new->nelts;

    cur->nelts = i;
    cur->next = new;
    if (cur == list->last) {
        list->last = new;
    }

    return NGX_OK;
}
