
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_util.h"


int
ngx_http_lua_ffi_var_get(ngx_http_request_t *r, u_char *name_data,
    size_t name_len, u_char *lowcase_buf, int capture_id, u_char **value,
    size_t *value_len, char **err)
{
    ngx_uint_t                   hash;
    ngx_str_t                    name;
    ngx_http_variable_value_t   *vv;

#if (NGX_PCRE)
    u_char                      *p;
    ngx_uint_t                   n;
    int                         *cap;
#endif

    if (r == NULL) {
        *err = "no request object found";
        return NGX_ERROR;
    }

    if ((r)->connection->fd == (ngx_socket_t) -1) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

#if (NGX_PCRE)
    if (name_data == 0) {
        if (capture_id <= 0) {
            return NGX_DECLINED;
        }

        /* it is a regex capturing variable */

        n = (ngx_uint_t) capture_id * 2;

        dd("n = %d, ncaptures = %d", (int) n, (int) r->ncaptures);

        if (r->captures == NULL
            || r->captures_data == NULL
            || n >= r->ncaptures)
        {
            return NGX_DECLINED;
        }

        /* n >= 0 && n < r->ncaptures */

        cap = r->captures;
        p = r->captures_data;

        *value = &p[cap[n]];
        *value_len = (size_t) (cap[n + 1] - cap[n]);

        return NGX_OK;
    }
#endif

    hash = ngx_hash_strlow(lowcase_buf, name_data, name_len);

    name.data = lowcase_buf;
    name.len = name_len;

    dd("variable name: %.*s", (int) name_len, lowcase_buf);

    vv = ngx_http_get_variable(r, &name, hash);
    if (vv == NULL || vv->not_found) {
        return NGX_DECLINED;
    }

    *value = vv->data;
    *value_len = vv->len;
    return NGX_OK;
}


int
ngx_http_lua_ffi_var_set(ngx_http_request_t *r, u_char *name_data,
    size_t name_len, u_char *lowcase_buf, u_char *value, size_t value_len,
    u_char *errbuf, size_t *errlen)
{
    u_char                      *p;
    ngx_uint_t                   hash;
    ngx_http_variable_t         *v;
    ngx_http_variable_value_t   *vv;
    ngx_http_core_main_conf_t   *cmcf;

    if (r == NULL) {
        *errlen = ngx_snprintf(errbuf, *errlen, "no request object found")
                  - errbuf;
        return NGX_ERROR;
    }

    if ((r)->connection->fd == (ngx_socket_t) -1) {
        *errlen = ngx_snprintf(errbuf, *errlen,
                               "API disabled in the current context")
                  - errbuf;
        return NGX_ERROR;
    }

    hash = ngx_hash_strlow(lowcase_buf, name_data, name_len);

    dd("variable name: %.*s", (int) name_len, lowcase_buf);

    /* we fetch the variable itself */

    cmcf = ngx_http_get_module_main_conf(r, ngx_http_core_module);

    v = ngx_hash_find(&cmcf->variables_hash, hash, lowcase_buf, name_len);

    if (v) {
        if (!(v->flags & NGX_HTTP_VAR_CHANGEABLE)) {
            dd("variable not changeable");
            *errlen = ngx_snprintf(errbuf, *errlen,
                                   "variable \"%*s\" not changeable",
                                   name_len, lowcase_buf)
                      - errbuf;
            return NGX_ERROR;
        }

        if (v->set_handler) {

            dd("set variables with set_handler");

            if (value != NULL && value_len) {
                vv = ngx_palloc(r->pool, sizeof(ngx_http_variable_value_t)
                                + value_len);
                if (vv == NULL) {
                    goto nomem;
                }

                p = (u_char *) vv + sizeof(ngx_http_variable_value_t);
                ngx_memcpy(p, value, value_len);
                value = p;

            } else {
                vv = ngx_palloc(r->pool, sizeof(ngx_http_variable_value_t));
                if (vv == NULL) {
                    goto nomem;
                }
            }

            if (value == NULL) {
                vv->valid = 0;
                vv->not_found = 1;
                vv->no_cacheable = 0;
                vv->data = NULL;
                vv->len = 0;

            } else {
                vv->valid = 1;
                vv->not_found = 0;
                vv->no_cacheable = 0;

                vv->data = value;
                vv->len = value_len;
            }

            v->set_handler(r, vv, v->data);
            return NGX_OK;
        }

        if (v->flags & NGX_HTTP_VAR_INDEXED) {
            vv = &r->variables[v->index];

            dd("set indexed variable");

            if (value == NULL) {
                vv->valid = 0;
                vv->not_found = 1;
                vv->no_cacheable = 0;

                vv->data = NULL;
                vv->len = 0;

            } else {
                p = ngx_palloc(r->pool, value_len);
                if (p == NULL) {
                    goto nomem;
                }

                ngx_memcpy(p, value, value_len);
                value = p;

                vv->valid = 1;
                vv->not_found = 0;
                vv->no_cacheable = 0;

                vv->data = value;
                vv->len = value_len;
            }

            return NGX_OK;
        }

        *errlen = ngx_snprintf(errbuf, *errlen,
                               "variable \"%*s\" cannot be assigned "
                               "a value", name_len, lowcase_buf)
                  - errbuf;
        return NGX_ERROR;
    }

    /* variable not found */

    *errlen = ngx_snprintf(errbuf, *errlen,
                           "variable \"%*s\" not found for writing; "
                           "maybe it is a built-in variable that is not "
                           "changeable or you forgot to use \"set $%*s '';\" "
                           "in the config file to define it first",
                           name_len, lowcase_buf, name_len, lowcase_buf)
              - errbuf;
    return NGX_ERROR;

nomem:

    *errlen = ngx_snprintf(errbuf, *errlen, "no memory") - errbuf;
    return NGX_ERROR;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
