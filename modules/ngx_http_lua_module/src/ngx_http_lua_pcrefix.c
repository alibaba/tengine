
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_pcrefix.h"
#include "stdio.h"

#if (NGX_PCRE)

static ngx_pool_t *ngx_http_lua_pcre_pool = NULL;

static void *(*old_pcre_malloc)(size_t);
static void (*old_pcre_free)(void *ptr);


/* XXX: work-around to nginx regex subsystem, must init a memory pool
 * to use PCRE functions. As PCRE still has memory-leaking problems,
 * and nginx overwrote pcre_malloc/free hooks with its own static
 * functions, so nobody else can reuse nginx regex subsystem... */
static void *
ngx_http_lua_pcre_malloc(size_t size)
{
    dd("lua pcre pool is %p", ngx_http_lua_pcre_pool);

    if (ngx_http_lua_pcre_pool) {
        return ngx_palloc(ngx_http_lua_pcre_pool, size);
    }

    fprintf(stderr, "error: lua pcre malloc failed due to empty pcre pool");

    return NULL;
}


static void
ngx_http_lua_pcre_free(void *ptr)
{
    dd("lua pcre pool is %p", ngx_http_lua_pcre_pool);

    if (ngx_http_lua_pcre_pool) {
        ngx_pfree(ngx_http_lua_pcre_pool, ptr);
        return;
    }

    fprintf(stderr, "error: lua pcre free failed due to empty pcre pool");
}


ngx_pool_t *
ngx_http_lua_pcre_malloc_init(ngx_pool_t *pool)
{
    ngx_pool_t          *old_pool;

    if (pcre_malloc != ngx_http_lua_pcre_malloc) {

        dd("overriding nginx pcre malloc and free");

        ngx_http_lua_pcre_pool = pool;

        old_pcre_malloc = pcre_malloc;
        old_pcre_free = pcre_free;

        pcre_malloc = ngx_http_lua_pcre_malloc;
        pcre_free = ngx_http_lua_pcre_free;

        return NULL;
    }

    dd("lua pcre pool was %p", ngx_http_lua_pcre_pool);

    old_pool = ngx_http_lua_pcre_pool;
    ngx_http_lua_pcre_pool = pool;

    dd("lua pcre pool is %p", ngx_http_lua_pcre_pool);

    return old_pool;
}


void
ngx_http_lua_pcre_malloc_done(ngx_pool_t *old_pool)
{
    dd("lua pcre pool was %p", ngx_http_lua_pcre_pool);

    ngx_http_lua_pcre_pool = old_pool;

    dd("lua pcre pool is %p", ngx_http_lua_pcre_pool);

    if (old_pool == NULL) {
        pcre_malloc = old_pcre_malloc;
        pcre_free = old_pcre_free;
    }
}

#endif /* NGX_PCRE */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
