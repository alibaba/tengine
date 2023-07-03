
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <nginx.h>
#include "ngx_http_lua_headers_out.h"
#include "ngx_http_lua_util.h"
#include <ctype.h>


static ngx_int_t ngx_http_set_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_header_helper(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value,
    ngx_table_elt_t **output_header, unsigned no_create);
static ngx_int_t ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_builtin_multi_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_last_modified_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_content_type_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_clear_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_clear_last_modified_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_clear_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_location_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);


static ngx_http_lua_set_header_t  ngx_http_lua_set_handlers[] = {

    { ngx_string("Server"),
                 offsetof(ngx_http_headers_out_t, server),
                 ngx_http_set_builtin_header },

    { ngx_string("Date"),
                 offsetof(ngx_http_headers_out_t, date),
                 ngx_http_set_builtin_header },

#if 1
    { ngx_string("Content-Encoding"),
                 offsetof(ngx_http_headers_out_t, content_encoding),
                 ngx_http_set_builtin_header },
#endif

    { ngx_string("Location"),
                 offsetof(ngx_http_headers_out_t, location),
                 ngx_http_set_location_header },

    { ngx_string("Refresh"),
                 offsetof(ngx_http_headers_out_t, refresh),
                 ngx_http_set_builtin_header },

    { ngx_string("Last-Modified"),
                 offsetof(ngx_http_headers_out_t, last_modified),
                 ngx_http_set_last_modified_header },

    { ngx_string("Content-Range"),
                 offsetof(ngx_http_headers_out_t, content_range),
                 ngx_http_set_builtin_header },

    { ngx_string("Accept-Ranges"),
                 offsetof(ngx_http_headers_out_t, accept_ranges),
                 ngx_http_set_builtin_header },

    { ngx_string("WWW-Authenticate"),
                 offsetof(ngx_http_headers_out_t, www_authenticate),
                 ngx_http_set_builtin_header },

    { ngx_string("Expires"),
                 offsetof(ngx_http_headers_out_t, expires),
                 ngx_http_set_builtin_header },

    { ngx_string("E-Tag"),
                 offsetof(ngx_http_headers_out_t, etag),
                 ngx_http_set_builtin_header },

    { ngx_string("ETag"),
                 offsetof(ngx_http_headers_out_t, etag),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Length"),
                 offsetof(ngx_http_headers_out_t, content_length),
                 ngx_http_set_content_length_header },

    { ngx_string("Content-Type"),
                 offsetof(ngx_http_headers_out_t, content_type),
                 ngx_http_set_content_type_header },

    { ngx_string("Cache-Control"),
                 offsetof(ngx_http_headers_out_t, cache_control),
                 ngx_http_set_builtin_multi_header },

#if (nginx_version >= 1013009)
    { ngx_string("Link"),
                 offsetof(ngx_http_headers_out_t, link),
                 ngx_http_set_builtin_multi_header },
#endif

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
    unsigned                     matched = 0;

    if (hv->no_override) {
        goto new_header;
    }

#if 1
    if (r->headers_out.location
        && r->headers_out.location->value.len
        && r->headers_out.location->value.data[0] == '/')
    {
        /* XXX ngx_http_core_find_config_phase, for example,
         * may not initialize the "key" and "hash" fields
         * for a nasty optimization purpose, and
         * we have to work-around it here */

        r->headers_out.location->hash = ngx_http_lua_location_hash;
        ngx_str_set(&r->headers_out.location->key, "Location");
    }
#endif

    part = &r->headers_out.headers.part;
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

        if (h[i].hash != 0
            && h[i].key.len == hv->key.len
            && ngx_strncasecmp(hv->key.data, h[i].key.data, h[i].key.len) == 0)
        {
            dd("found out header %.*s", (int) h[i].key.len, h[i].key.data);

            if (value->len == 0 || matched) {
                dd("clearing normal header for %.*s", (int) hv->key.len,
                   hv->key.data);

                h[i].value.len = 0;
                h[i].hash = 0;

            } else {
                dd("setting header to value %.*s", (int) value->len,
                   value->data);

                h[i].value = *value;
                h[i].hash = hv->hash;
            }

            if (output_header) {
                *output_header = &h[i];
            }

            /* return NGX_OK; */
            matched = 1;
        }
    }

    if (matched){
        return NGX_OK;
    }

    if (no_create && value->len == 0) {
        return NGX_OK;
    }

new_header:

    /* XXX we still need to create header slot even if the value
     * is empty because some builtin headers like Last-Modified
     * relies on this to get cleared */

    h = ngx_list_push(&r->headers_out.headers);

    if (h == NULL) {
        return NGX_ERROR;
    }

    if (value->len == 0) {
        h->hash = 0;

    } else {
        h->hash = hv->hash;
    }

    h->key = hv->key;
    h->value = *value;

    h->lowcase_key = ngx_pnalloc(r->pool, h->key.len);
    if (h->lowcase_key == NULL) {
        return NGX_ERROR;
    }

    ngx_strlow(h->lowcase_key, h->key.data, h->key.len);

    if (output_header) {
        *output_header = h;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_location_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    ngx_int_t         rc;
    ngx_table_elt_t  *h;

    rc = ngx_http_set_builtin_header(r, hv, value);
    if (rc != NGX_OK) {
        return rc;
    }

    /*
     * we do not set r->headers_out.location here to avoid the handling
     * the local redirects without a host name by ngx_http_header_filter()
     */

    h = r->headers_out.location;
    if (h && h->value.len && h->value.data[0] == '/') {
        r->headers_out.location = NULL;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    ngx_table_elt_t  *h, **old;

    if (hv->offset) {
        old = (ngx_table_elt_t **) ((char *) &r->headers_out + hv->offset);

    } else {
        old = NULL;
    }

    if (old == NULL || *old == NULL) {
        return ngx_http_set_header_helper(r, hv, value, old, 0);
    }

    h = *old;

    if (value->len == 0) {
        dd("clearing the builtin header");

        h->hash = 0;
        h->value = *value;

        return NGX_OK;
    }

    h->hash = hv->hash;
    h->key = hv->key;
    h->value = *value;

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_builtin_multi_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
#if defined(nginx_version) && nginx_version >= 1023000
    ngx_table_elt_t  **headers, *h, *ho, **ph;

    headers = (ngx_table_elt_t **) ((char *) &r->headers_out + hv->offset);

    if (hv->no_override) {
        for (h = *headers; h; h = h->next) {
            if (!h->hash) {
                h->value = *value;
                h->hash = hv->hash;
                return NGX_OK;
            }
        }

        goto create;
    }

    /* override old values (if any) */

    if (*headers) {
        for (h = (*headers)->next; h; h = h->next) {
            h->hash = 0;
            h->value.len = 0;
        }

        h = *headers;

        h->value = *value;

        if (value->len == 0) {
            h->hash = 0;

        } else {
            h->hash = hv->hash;
        }

        return NGX_OK;
    }

create:

    for (ph = headers; *ph; ph = &(*ph)->next) { /* void */ }

    ho = ngx_list_push(&r->headers_out.headers);
    if (ho == NULL) {
        return NGX_ERROR;
    }

    ho->value = *value;

    if (value->len == 0) {
        ho->hash = 0;

    } else {
        ho->hash = hv->hash;
    }

    ho->key = hv->key;
    ho->next = NULL;
    *ph = ho;

    return NGX_OK;
#else
    ngx_array_t      *pa;
    ngx_table_elt_t  *ho, **ph;
    ngx_uint_t        i;

    pa = (ngx_array_t *) ((char *) &r->headers_out + hv->offset);

    if (pa->elts == NULL) {
        if (ngx_array_init(pa, r->pool, 2, sizeof(ngx_table_elt_t *))
            != NGX_OK)
        {
            return NGX_ERROR;
        }
    }

    if (hv->no_override) {
        ph = pa->elts;
        for (i = 0; i < pa->nelts; i++) {
            if (!ph[i]->hash) {
                ph[i]->value = *value;
                ph[i]->hash = hv->hash;
                return NGX_OK;
            }
        }

        goto create;
    }

    /* override old values (if any) */

    if (pa->nelts > 0) {
        ph = pa->elts;
        for (i = 1; i < pa->nelts; i++) {
            ph[i]->hash = 0;
            ph[i]->value.len = 0;
        }

        ph[0]->value = *value;

        if (value->len == 0) {
            ph[0]->hash = 0;

        } else {
            ph[0]->hash = hv->hash;
        }

        return NGX_OK;
    }

create:

    ph = ngx_array_push(pa);
    if (ph == NULL) {
        return NGX_ERROR;
    }

    ho = ngx_list_push(&r->headers_out.headers);
    if (ho == NULL) {
        return NGX_ERROR;
    }

    ho->value = *value;

    if (value->len == 0) {
        ho->hash = 0;

    } else {
        ho->hash = hv->hash;
    }

    ho->key = hv->key;
    *ph = ho;

    return NGX_OK;
#endif
}


static ngx_int_t
ngx_http_set_content_type_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    ngx_uint_t          i;

    r->headers_out.content_type_len = value->len;

#if 1
    for (i = 0; i < value->len; i++) {
        if (value->data[i] == ';') {
            r->headers_out.content_type_len = i;
            break;
        }
    }
#endif

    r->headers_out.content_type = *value;
    r->headers_out.content_type_hash = hv->hash;
    r->headers_out.content_type_lowcase = NULL;

    value->len = 0;

    return ngx_http_set_header_helper(r, hv, value, NULL, 1);
}


static ngx_int_t ngx_http_set_last_modified_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    if (value->len == 0) {
        return ngx_http_clear_last_modified_header(r, hv, value);
    }

    r->headers_out.last_modified_time = ngx_http_parse_time(value->data,
                                                            value->len);

    dd("last modified time: %d", (int) r->headers_out.last_modified_time);

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_clear_last_modified_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    r->headers_out.last_modified_time = -1;

    return ngx_http_clear_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_set_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    off_t           len;

    if (value->len == 0) {
        return ngx_http_clear_content_length_header(r, hv, value);
    }

    len = ngx_atoof(value->data, value->len);
    if (len == NGX_ERROR) {
        return NGX_ERROR;
    }

    r->headers_out.content_length_n = len;

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_clear_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    r->headers_out.content_length_n = -1;

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
ngx_http_lua_set_output_header(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx,
    ngx_str_t key, ngx_str_t value, unsigned override)
{
    ngx_http_lua_header_val_t         hv;
    ngx_http_lua_main_conf_t         *lmcf;
    ngx_http_lua_set_header_t        *lsh;
    ngx_hash_t                       *hash;

    dd("set header value: %.*s", (int) value.len, value.data);

    if (ngx_http_lua_copy_escaped_header(r, &key, 1) != NGX_OK) {
        return NGX_ERROR;
    }

    if (ngx_http_lua_copy_escaped_header(r, &value, 0) != NGX_OK) {
        return NGX_ERROR;
    }

    hv.hash = ngx_hash_key_lc(key.data, key.len);
    hv.key = key;

    hv.offset = 0;
    hv.no_override = !override;
    hv.handler = ngx_http_set_header;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    hash = &lmcf->builtin_headers_out;
    lsh = ngx_http_lua_hash_find_lc(hash, hv.hash, hv.key.data, hv.key.len);
    if (lsh) {
        dd("Matched handler: %s %s", lsh->name.data, hv.key.data);
        hv.offset = lsh->offset;
        hv.handler = lsh->handler;
        if (hv.handler == ngx_http_set_content_type_header) {
            ctx->mime_set = 1;
        }
    }

    return hv.handler(r, &hv, &value);
}


int
ngx_http_lua_get_output_header(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_str_t *key)
{
    ngx_table_elt_t            *h;
    ngx_list_part_t            *part;
    ngx_uint_t                  i;
    unsigned                    found;

    dd("looking for response header \"%.*s\"", (int) key->len, key->data);

    switch (key->len) {
    case 14:
        if (r->headers_out.content_length == NULL
            && r->headers_out.content_length_n >= 0
            && ngx_strncasecmp(key->data, (u_char *) "Content-Length", 14) == 0)
        {
            lua_pushinteger(L, (lua_Integer) r->headers_out.content_length_n);
            return 1;
        }

        break;

    case 12:
        if (ngx_strncasecmp(key->data, (u_char *) "Content-Type", 12) == 0
            && r->headers_out.content_type.len)
        {
            lua_pushlstring(L, (char *) r->headers_out.content_type.data,
                            r->headers_out.content_type.len);
            return 1;
        }

        break;

    default:
        break;
    }

    dd("not a built-in output header");

    found = 0;

#if 1
    if (r->headers_out.location
        && r->headers_out.location->value.len
        && r->headers_out.location->value.data[0] == '/')
    {
        /* XXX ngx_http_core_find_config_phase, for example,
         * may not initialize the "key" and "hash" fields
         * for a nasty optimization purpose, and
         * we have to work-around it here */

        r->headers_out.location->hash = ngx_http_lua_location_hash;
        ngx_str_set(&r->headers_out.location->key, "Location");
    }
#endif

    part = &r->headers_out.headers.part;
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

        if (h[i].hash == 0) {
            continue;
        }

        if (h[i].hash != 0
            && h[i].key.len == key->len
            && ngx_strncasecmp(key->data, h[i].key.data, h[i].key.len) == 0)
         {
             if (!found) {
                 found = 1;

                 lua_pushlstring(L, (char *) h[i].value.data, h[i].value.len);
                 continue;
             }

             if (found == 1) {
                 lua_createtable(L, 4 /* narr */, 0);
                 lua_insert(L, -2);
                 lua_rawseti(L, -2, found);
             }

             found++;

             lua_pushlstring(L, (char *) h[i].value.data, h[i].value.len);
             lua_rawseti(L, -2, found);
         }
    }

    if (found) {
        return 1;
    }

    lua_pushnil(L);
    return 1;
}


ngx_int_t
ngx_http_lua_init_builtin_headers_out(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf)
{
    ngx_array_t                   headers;
    ngx_hash_key_t               *hk;
    ngx_hash_init_t               hash;
    ngx_http_lua_set_header_t    *handlers = ngx_http_lua_set_handlers;
    ngx_uint_t                    count;

    count = sizeof(ngx_http_lua_set_handlers)
            / sizeof(ngx_http_lua_set_header_t);

    if (ngx_array_init(&headers, cf->temp_pool, count, sizeof(ngx_hash_key_t))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    while (handlers->name.data) {
        hk = ngx_array_push(&headers);
        if (hk == NULL) {
            return NGX_ERROR;
        }

        hk->key = handlers->name;
        hk->key_hash = ngx_hash_key_lc(handlers->name.data, handlers->name.len);
        hk->value = (void *) handlers;

        handlers++;
    }

    hash.hash = &lmcf->builtin_headers_out;
    hash.key = ngx_hash_key_lc;
    hash.max_size = 512;
    hash.bucket_size = ngx_align(64, ngx_cacheline_size);
    hash.name = "builtin_headers_out_hash";
    hash.pool = cf->pool;
    hash.temp_pool = NULL;

    return ngx_hash_init(&hash, headers.elts, headers.nelts);
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
