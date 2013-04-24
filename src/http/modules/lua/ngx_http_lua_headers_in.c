
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <nginx.h>
#include "ngx_http_lua_headers_in.h"
#include "ngx_http_lua_util.h"
#include <ctype.h>


static ngx_int_t ngx_http_set_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_header_helper(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value,
    ngx_table_elt_t **output_header, unsigned no_create);
static ngx_int_t ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_clear_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_clear_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_host_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_lua_rm_header_helper(ngx_list_t *l,
    ngx_list_part_t *cur, ngx_uint_t i);


static ngx_http_lua_set_header_t  ngx_http_lua_set_handlers[] = {

#if (NGX_HTTP_GZIP)
    { ngx_string("Accept-Encoding"),
                 offsetof(ngx_http_headers_in_t, accept_encoding),
                 ngx_http_set_builtin_header },
#endif

    { ngx_string("Host"),
                 offsetof(ngx_http_headers_in_t, host),
                 ngx_http_set_host_header },

    { ngx_string("Connection"),
                 offsetof(ngx_http_headers_in_t, connection),
                 ngx_http_set_builtin_header },

    { ngx_string("If-Modified-Since"),
                 offsetof(ngx_http_headers_in_t, if_modified_since),
                 ngx_http_set_builtin_header },

    { ngx_string("User-Agent"),
                 offsetof(ngx_http_headers_in_t, user_agent),
                 ngx_http_set_builtin_header },

    { ngx_string("Referer"),
                 offsetof(ngx_http_headers_in_t, referer),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Type"),
                 offsetof(ngx_http_headers_in_t, content_type),
                 ngx_http_set_builtin_header },

    { ngx_string("Range"),
                 offsetof(ngx_http_headers_in_t, range),
                 ngx_http_set_builtin_header },

    { ngx_string("If-Range"),
                 offsetof(ngx_http_headers_in_t, if_range),
                 ngx_http_set_builtin_header },

    { ngx_string("Transfer-Encoding"),
                 offsetof(ngx_http_headers_in_t, transfer_encoding),
                 ngx_http_set_builtin_header },

    { ngx_string("Expect"),
                 offsetof(ngx_http_headers_in_t, expect),
                 ngx_http_set_builtin_header },

    { ngx_string("Authorization"),
                 offsetof(ngx_http_headers_in_t, authorization),
                 ngx_http_set_builtin_header },

    { ngx_string("Keep-Alive"),
                 offsetof(ngx_http_headers_in_t, keep_alive),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Length"),
                 offsetof(ngx_http_headers_in_t, content_length),
                 ngx_http_set_content_length_header },

    { ngx_null_string, 0, ngx_http_set_header }
};


/* request time implementation */

static ngx_int_t
ngx_http_set_header(ngx_http_request_t *r, ngx_http_lua_header_val_t *hv,
    ngx_str_t *value)
{
    return ngx_http_set_header_helper(r, hv, value, NULL, 0);
}


static ngx_int_t
ngx_http_set_header_helper(ngx_http_request_t *r, ngx_http_lua_header_val_t *hv,
    ngx_str_t *value, ngx_table_elt_t **output_header,
    unsigned no_create)
{
    ngx_table_elt_t             *h;
    ngx_list_part_t             *part;
    ngx_uint_t                   i;
    ngx_uint_t                   rc;

    if (hv->no_override) {
        goto new_header;
    }

retry:
    part = &r->headers_in.headers.part;
    h = part->elts;

    for (i = 0; /* void */; i++) {
        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            h = part->elts;
            i = 0;
        }

        dd("i: %d, part: %p", (int) i, part);

        if (h[i].key.len == hv->key.len
            && ngx_strncasecmp(h[i].key.data, hv->key.data, h[i].key.len)
               == 0)
        {
            if (value->len == 0) {
                h[i].hash = 0;

                rc = ngx_http_lua_rm_header_helper(&r->headers_in.headers,
                                                   part, i);

                if (rc == NGX_OK) {
                    if (output_header) {
                        *output_header = NULL;
                    }

                    goto retry;
                }
            }

            h[i].value = *value;

            if (output_header) {
                *output_header = &h[i];
                dd("setting existing builtin input header");
            }

            return NGX_OK;
        }
    }

    if (value->len == 0) {
        return NGX_OK;
    }

new_header:
    h = ngx_list_push(&r->headers_in.headers);

    if (h == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    dd("created new header for %.*s", (int) hv->key.len, hv->key.data);

    if (value->len == 0) {
        h->hash = 0;

    } else {
        h->hash = hv->hash;
    }

    h->key = hv->key;
    h->value = *value;

    h->lowcase_key = ngx_pnalloc(r->pool, h->key.len);
    if (h->lowcase_key == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ngx_strlow(h->lowcase_key, h->key.data, h->key.len);

    if (output_header) {
        *output_header = h;

        while (r != r->main) {
            r->parent->headers_in = r->headers_in;
            r = r->parent;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    ngx_table_elt_t             *h, **old;

    dd("entered set_builtin_header (input)");

    if (hv->offset) {
        old = (ngx_table_elt_t **) ((char *) &r->headers_in + hv->offset);

    } else {
        old = NULL;
    }

    dd("old builtin ptr ptr: %p", old);
    if (old) {
        dd("old builtin ptr: %p", *old);
    }

    if (old == NULL || *old == NULL) {
        dd("set normal header");
        return ngx_http_set_header_helper(r, hv, value, old, 0);
    }

    h = *old;

    if (value->len == 0) {
        h->hash = 0;
        h->value = *value;

        return ngx_http_set_header_helper(r, hv, value, old, 0);
    }

    h->hash = hv->hash;
    h->value = *value;

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_host_header(ngx_http_request_t *r, ngx_http_lua_header_val_t *hv,
    ngx_str_t *value)
{
    dd("server new value len: %d", (int) value->len);

    r->headers_in.server = *value;

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_set_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    off_t           len;

    if (value->len == 0) {
        return ngx_http_clear_content_length_header(r, hv, value);
    }

    len = ngx_atosz(value->data, value->len);
    if (len == NGX_ERROR) {
        return NGX_ERROR;
    }

    dd("reset headers_in.content_length_n to %d", (int)len);

    r->headers_in.content_length_n = len;

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_clear_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    r->headers_in.content_length_n = -1;

    return ngx_http_clear_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_clear_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    value->len = 0;
    return ngx_http_set_builtin_header(r, hv, value);
}


ngx_int_t
ngx_http_lua_set_input_header(ngx_http_request_t *r, ngx_str_t key,
    ngx_str_t value, unsigned override)
{
    ngx_http_lua_header_val_t         hv;
    ngx_http_lua_set_header_t        *handlers = ngx_http_lua_set_handlers;

    ngx_uint_t                        i;

    dd("set header value: %.*s", (int) value.len, value.data);

    hv.hash = ngx_hash_key_lc(key.data, key.len);
    hv.key = key;

    hv.offset = 0;
    hv.no_override = ! override;
    hv.handler = NULL;

    for (i = 0; handlers[i].name.len; i++) {
        if (hv.key.len != handlers[i].name.len
            || ngx_strncasecmp(hv.key.data, handlers[i].name.data,
                               handlers[i].name.len) != 0)
        {
            dd("hv key comparison: %s <> %s", handlers[i].name.data,
               hv.key.data);

            continue;
        }

        dd("Matched handler: %s %s", handlers[i].name.data, hv.key.data);

        hv.offset = handlers[i].offset;
        hv.handler = handlers[i].handler;

        break;
    }

    if (handlers[i].name.len == 0 && handlers[i].handler) {
        hv.offset = handlers[i].offset;
        hv.handler = handlers[i].handler;
    }

#if 1
    if (hv.handler == NULL) {
        return NGX_ERROR;
    }
#endif

    return hv.handler(r, &hv, &value);
}


static ngx_int_t
ngx_http_lua_rm_header_helper(ngx_list_t *l, ngx_list_part_t *cur,
    ngx_uint_t i)
{
    ngx_table_elt_t             *data;
    ngx_list_part_t             *new, *part;

    dd("list rm item: part %p, i %d, nalloc %d", cur, (int) i,
       (int) l->nalloc);

    data = cur->elts;

    dd("cur: nelts %d, nalloc %d", (int) cur->nelts,
       (int) l->nalloc);

    dd("removing: \"%.*s:%.*s\"", (int) data[i].key.len, data[i].key.data,
       (int) data[i].value.len, data[i].value.data);

    if (i == 0) {
        cur->elts = (char *) cur->elts + l->size;
        cur->nelts--;

        if (cur == l->last) {
            if (cur->nelts == 0) {
#if 1
                part = &l->part;
                while (part->next != cur) {
                    if (part->next == NULL) {
                        return NGX_ERROR;
                    }
                    part = part->next;
                }

                l->last = part;
                part->next = NULL;
                l->nalloc = part->nelts;
#endif

            } else {
                l->nalloc = cur->nelts;
            }

            return NGX_OK;
        }

        if (cur->nelts == 0) {
            part = &l->part;
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
        dd("last entry in the part");

        cur->nelts--;

        if (cur == l->last) {
            l->nalloc = cur->nelts;
        }

        return NGX_OK;
    }

    dd("the middle entry in the part");

    new = ngx_palloc(l->pool, sizeof(ngx_list_part_t));
    if (new == NULL) {
        return NGX_ERROR;
    }

    new->elts = &data[i + 1];
    new->nelts = cur->nelts - i - 1;
    new->next = cur->next;

    cur->nelts = i;
    cur->next = new;

    if (cur == l->last) {
        l->last = new;
        l->nalloc = new->nelts;
    }

    return NGX_OK;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
