
/*
 * Copyright (C) Yunkai Zhang
 * Copyright (C) Taobao, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>


void
ngx_lfstack_init(ngx_lfstack_t *l, size_t offset)
{
    l->head = 0;
    l->offset = offset;
}


void
ngx_lfstack_push(ngx_lfstack_t *l, void *item)
{
    ngx_int_t       rc;
    ngx_atomic_t    prev, curr, addr, ver, *target;

    target = ngx_offset_addr(item, l->offset);

    do {
        prev = l->head;

        addr = ngx_ptr_addr_get(prev);
        ver = ngx_ptr_ver_get(prev);

        *target = addr;

        curr = ngx_ptr_ver_set(item, ver);

        rc = ngx_atomic_cmp_set(&l->head, prev, curr);
    } while (rc == 0);

    return;
}


void *
ngx_lfstack_pop(ngx_lfstack_t *l)
{
    ngx_int_t       rc;
    ngx_atomic_t    prev, next, addr, ver, *target;

    do {
        prev = l->head;

        addr = ngx_ptr_addr_get(prev);

        if (addr == 0) {
            return NULL;
        }

        ver = ngx_ptr_ver_get(prev);

        target = ngx_offset_addr(addr, l->offset);

        next = ngx_ptr_ver_set(*target, ver + 1);

        rc = ngx_atomic_cmp_set(&l->head, prev, next);
    } while (rc == 0);

    *target = 0;
    return (void *)addr;
}


void *
ngx_lfstack_popall(ngx_lfstack_t *l)
{
    ngx_int_t       rc;
    ngx_atomic_t    prev, next, addr, ver;

    do {
        prev = l->head;

        addr = ngx_ptr_addr_get(prev);

        if (addr == 0) {
            return NULL;
        }

        ver = ngx_ptr_addr_get(prev);

        next = ngx_ptr_ver_set(0, ver + 1);

        rc = ngx_atomic_cmp_set(&l->head, prev, next);
    } while (rc == 0);

    return (void *)addr;
}


void *
ngx_lfstack_remove(ngx_lfstack_t *l, void *item)
{
    ngx_int_t       rc;
    ngx_atomic_t    prev, next, addr, ver, *target, *target_next;

    prev = l->head;

    addr = ngx_ptr_addr_get(prev);

    target = ngx_offset_addr(item, l->offset);

    /* at top */
    while ((void *)addr == item) {
        ver = ngx_ptr_ver_get(prev);

        next = ngx_ptr_ver_set(*target, ver + 1);

        rc = ngx_atomic_cmp_set(&l->head, prev, next);
        if (rc) {
            *target = 0;
            return item;
        }

        prev = l->head;

        addr = ngx_ptr_addr_get(prev);
    }

    /* doesn't at top */
    while (addr) {
        target_next = ngx_offset_addr(addr, l->offset);

        if ((void *)*target_next == item) {
            *target_next = *target;
            *target = 0;
            return item;
        }

        addr = *target_next;
    }

    return NULL;
}
