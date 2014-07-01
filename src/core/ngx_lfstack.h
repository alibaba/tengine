
/*
 * Copyright (C) Yunkai Zhang
 * Copyright (C) Taobao, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>


#ifndef _NGX_LFSTACK_H_INCLUDED_
#define _NGX_LFSTACK_H_INCLUDED_


/* TODO: Support 32bit system */

/*
 * In x86-64 architecture, linux virtual adderss
 * comply with AMD Canonical form:
 *
 * *) Kernal virtual address space:
 *    FFFF8000 00000000 - FFFFFFFF FFFFFFFF
 *
 * *) User virtual address space:
 *    00007FFF FFFFFFFF - 00000000 00000000
 *
 * For more detail, please read this link:
 * http://en.wikipedia.org/wiki/X86-64
 */
#define ngx_ptr_addr_get(ptr) \
    (((uint64_t)(ptr) << 16) >> 16)

#define ngx_ptr_ver_get(ptr) \
    ((uint64_t)(ptr) >> 48)

#define ngx_ptr_ver_set(ptr, ver) \
    (((uint64_t)(ver) << 48) \
     | ngx_ptr_addr_get(ptr))

#define ngx_offset_addr(ptr, offset) \
    (void *)((char *)(ptr) + (offset));

typedef struct {
    ngx_atomic_t    head;
    size_t          offset;
} ngx_lfstack_t;


void ngx_lfstack_init(ngx_lfstack_t *l, size_t offset);
void ngx_lfstack_push(ngx_lfstack_t *l, void *item);
void *ngx_lfstack_pop(ngx_lfstack_t *l);
void *ngx_lfstack_popall(ngx_lfstack_t *l);
void *ngx_lfstack_remove(ngx_lfstack_t *l, void *item);


#endif /* _NGX_LFSTACK_H_INCLUDED_ */
