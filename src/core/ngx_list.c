
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>


ngx_list_t *
ngx_list_create(ngx_pool_t *pool, ngx_uint_t n, size_t size)
{
    ngx_list_t  *list;

    list = ngx_palloc(pool, sizeof(ngx_list_t));
    if (list == NULL) {
        return NULL;
    }

    if (ngx_list_init(list, pool, n, size) != NGX_OK) {
        return NULL;
    }

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


static ngx_int_t
ngx_list_delete_elt(ngx_list_t *list, ngx_list_part_t *cur, ngx_uint_t i)
{
    u_char *s, *d, *last;

    s = (u_char *) cur->elts + i * list->size;
    d = s + list->size;
    last = (u_char *) cur->elts + cur->nelts * list->size;

    while (d < last) {
        *s++ = *d++;
    }

    cur->nelts--;

    return NGX_OK;
}


ngx_int_t
ngx_list_delete(ngx_list_t *list, void *elt)
{
    u_char          *data;
    ngx_uint_t       i;
    ngx_list_part_t *part, *pre;

    part = &list->part;
    pre = part;
    data = part->elts;

    for (i = 0; /* void */; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            i = 0;
            pre = part;
            part = part->next;
            data = part->elts;
        }

        if ((data + i * list->size)  == (u_char *) elt) {
            if (&list->part != part && part->nelts == 1) {
                pre->next = part->next;
                if (part == list->last) {
                    list->last = pre;
                }

                return NGX_OK;
            }

            return ngx_list_delete_elt(list, part, i);
        }
    }

    return NGX_ERROR;
}
