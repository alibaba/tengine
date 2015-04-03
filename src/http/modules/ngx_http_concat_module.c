
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_flag_t   enable;
    ngx_uint_t   max_files;
    ngx_flag_t   unique;
    ngx_str_t    delimiter;
    ngx_flag_t   ignore_file_error;

    ngx_hash_t   types;
    ngx_array_t *types_keys;
} ngx_http_concat_loc_conf_t;


static ngx_int_t ngx_http_concat_add_path(ngx_http_request_t *r,
    ngx_array_t *uris, size_t max, ngx_str_t *path, u_char *p, u_char *v);
static ngx_int_t ngx_http_concat_init(ngx_conf_t *cf);
static void *ngx_http_concat_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_concat_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);


static ngx_str_t  ngx_http_concat_default_types[] = {
    ngx_string("application/x-javascript"),
    ngx_string("text/css"),
    ngx_null_string
};


static ngx_command_t  ngx_http_concat_commands[] = {

    { ngx_string("concat"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_concat_loc_conf_t, enable),
      NULL },

    { ngx_string("concat_max_files"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_concat_loc_conf_t, max_files),
      NULL },

    { ngx_string("concat_unique"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_concat_loc_conf_t, unique),
      NULL },

    { ngx_string("concat_types"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_types_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_concat_loc_conf_t, types_keys),
      &ngx_http_concat_default_types[0] },

    { ngx_string("concat_delimiter"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_concat_loc_conf_t, delimiter),
      NULL },

    { ngx_string("concat_ignore_file_error"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_concat_loc_conf_t, ignore_file_error),
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_concat_module_ctx = {
    NULL,                                /* preconfiguration */
    ngx_http_concat_init,                /* postconfiguration */

    NULL,                                /* create main configuration */
    NULL,                                /* init main configuration */

    NULL,                                /* create server configuration */
    NULL,                                /* merge server configuration */

    ngx_http_concat_create_loc_conf,     /* create location configuration */
    ngx_http_concat_merge_loc_conf       /* merge location configuration */
};


ngx_module_t  ngx_http_concat_module = {
    NGX_MODULE_V1,
    &ngx_http_concat_module_ctx,         /* module context */
    ngx_http_concat_commands,            /* module directives */
    NGX_HTTP_MODULE,                     /* module type */
    NULL,                                /* init master */
    NULL,                                /* init module */
    NULL,                                /* init process */
    NULL,                                /* init thread */
    NULL,                                /* exit thread */
    NULL,                                /* exit process */
    NULL,                                /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_concat_handler(ngx_http_request_t *r)
{
    off_t                       length;
    size_t                      root, last_len;
    time_t                      last_modified;
    u_char                     *p, *v, *e, *last, *last_type;
    ngx_int_t                   rc;
    ngx_str_t                  *uri, *filename, path;
    ngx_buf_t                  *b;
    ngx_uint_t                  i, j, level;
    ngx_flag_t                  timestamp;
    ngx_array_t                 uris;
    ngx_chain_t                 out, **last_out, *cl;
    ngx_open_file_info_t        of;
    ngx_http_core_loc_conf_t   *ccf;
    ngx_http_concat_loc_conf_t *clcf;

    if (r->uri.data[r->uri.len - 1] != '/') {
        return NGX_DECLINED;
    }

    if (!(r->method & (NGX_HTTP_GET|NGX_HTTP_HEAD))) {
        return NGX_DECLINED;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_concat_module);

    if (!clcf->enable) {
        return NGX_DECLINED;
    }

    /* the length of args must be greater than or equal to 2 */
    if (r->args.len < 2 || r->args.data[0] != '?') {
        return NGX_DECLINED;
    }

    rc = ngx_http_discard_request_body(r);

    if (rc != NGX_OK) {
        return rc;
    }

    last = ngx_http_map_uri_to_path(r, &path, &root, 0);
    if (last == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    path.len = last - path.data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http concat root: \"%V\"", &path);

    ccf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

#if (NGX_SUPPRESS_WARN)
    ngx_memzero(&uris, sizeof(ngx_array_t));
#endif

    if (ngx_array_init(&uris, r->pool, 8, sizeof(ngx_str_t)) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    e = r->args.data + r->args.len;
    for (p = r->args.data + 1, v = p, timestamp = 0; p != e; p++) {

        if (*p == ',') {
            if (p == v || timestamp == 1) {
                v = p + 1;
                timestamp = 0;
                continue;
            }

            rc = ngx_http_concat_add_path(r, &uris, clcf->max_files, &path,
                                          p, v);
            if (rc != NGX_OK) {
                return rc;
            }

            v = p + 1;

        } else if (*p == '?') {
            if (timestamp == 1) {
                v = p;
                continue;
            }

            rc = ngx_http_concat_add_path(r, &uris, clcf->max_files, &path,
                                          p, v);
            if (rc != NGX_OK) {
                return rc;
            }

            v = p;
            timestamp = 1;
        }
    }

    if (p - v > 0 && timestamp == 0) {
        rc = ngx_http_concat_add_path(r, &uris, clcf->max_files, &path, p, v);
        if (rc != NGX_OK) {
            return rc;
        }
    }

    last_modified = 0;
    last_len = 0;
    last_out = NULL;
    b = NULL;
    last_type = NULL;
    length = 0;
    uri = uris.elts;
    for (i = 0; i < uris.nelts; i++) {
        filename = uri + i;

        for (j = filename->len - 1; j > 1; j--) {
            if (filename->data[j] == '.' && filename->data[j - 1] != '/') {

                r->exten.len = filename->len - j - 1;
                r->exten.data = &filename->data[j + 1];
                break;

            } else if (filename->data[j] == '/') {
                break;
            }
        }

        r->headers_out.content_type.len = 0;
        if (ngx_http_set_content_type(r) != NGX_OK) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        r->headers_out.content_type_lowcase = NULL;
        if (ngx_http_test_content_type(r, &clcf->types) == NULL) {
            return NGX_HTTP_BAD_REQUEST;
        }

        if (clcf->unique) { /* test if all the content types are the same */
            if ((i > 0)
                && (last_len != r->headers_out.content_type_len
                    || (last_type != NULL
                        && r->headers_out.content_type_lowcase != NULL
                        && ngx_memcmp(last_type,
                                      r->headers_out.content_type_lowcase,
                                      last_len) != 0)))
            {
                return NGX_HTTP_BAD_REQUEST;
            }

            last_len = r->headers_out.content_type_len;
            last_type = r->headers_out.content_type_lowcase;
        }

        ngx_memzero(&of, sizeof(ngx_open_file_info_t));

        of.read_ahead = ccf->read_ahead;
        of.directio = ccf->directio;
        of.valid = ccf->open_file_cache_valid;
        of.min_uses = ccf->open_file_cache_min_uses;
        of.errors = ccf->open_file_cache_errors;
        of.events = ccf->open_file_cache_events;

        if (ngx_open_cached_file(ccf->open_file_cache, filename, &of, r->pool)
            != NGX_OK)
        {
            switch (of.err) {

            case 0:
                return NGX_HTTP_INTERNAL_SERVER_ERROR;

            case NGX_ENOENT:
            case NGX_ENOTDIR:
            case NGX_ENAMETOOLONG:

                level = NGX_LOG_ERR;
                rc = NGX_HTTP_NOT_FOUND;
                break;

            case NGX_EACCES:

                level = NGX_LOG_ERR;
                rc = NGX_HTTP_FORBIDDEN;
                break;

            default:

                level = NGX_LOG_CRIT;
                rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
                break;
            }

            if (rc != NGX_HTTP_NOT_FOUND || ccf->log_not_found) {
                ngx_log_error(level, r->connection->log, of.err,
                              "%s \"%V\" failed", of.failed, filename);
            }

            if (clcf->ignore_file_error
                && (rc == NGX_HTTP_NOT_FOUND || rc == NGX_HTTP_FORBIDDEN))
            {
                continue;
            }

            return rc;
        }

        if (!of.is_file) {
            ngx_log_error(NGX_LOG_CRIT, r->connection->log, ngx_errno,
                          "\"%V\" is not a regular file", filename);
            if (clcf->ignore_file_error) {
                continue;
            }

            return NGX_HTTP_NOT_FOUND;
        }

        if (of.size == 0) {
            continue;
        }

        length += of.size;
        if (last_out == NULL) {
            last_modified = of.mtime;

        } else {
            if (of.mtime > last_modified) {
                last_modified = of.mtime;
            }
        }

        b = ngx_pcalloc(r->pool, sizeof(ngx_buf_t));
        if (b == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        b->file = ngx_pcalloc(r->pool, sizeof(ngx_file_t));
        if (b->file == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        b->file_pos = 0;
        b->file_last = of.size;

        b->in_file = b->file_last ? 1 : 0;

        b->file->fd = of.fd;
        b->file->name = *filename;
        b->file->log = r->connection->log;

        b->file->directio = of.is_directio;

        if (last_out == NULL) {
            out.buf = b;
            last_out = &out.next;
            out.next = NULL;

        } else {
            cl = ngx_alloc_chain_link(r->pool);
            if (cl == NULL) {
                return NGX_HTTP_INTERNAL_SERVER_ERROR;
            }

            cl->buf = b;

            *last_out = cl;
            last_out = &cl->next;
            cl->next = NULL;
        }

        if (i + 1 == uris.nelts || clcf->delimiter.len == 0) {
            continue;
        }

        b = ngx_pcalloc(r->pool, sizeof(ngx_buf_t));
        if (b == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        b->pos = clcf->delimiter.data;
        b->last = b->pos + clcf->delimiter.len;
        b->memory = 1;
        length += clcf->delimiter.len;

        cl = ngx_alloc_chain_link(r->pool);
        if (cl == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        cl->buf = b;
        *last_out = cl;
        last_out = &cl->next;
        cl->next = NULL;
    }

    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = length;
    r->headers_out.last_modified_time = last_modified;

    if (b == NULL) {
        r->header_only = 1;
    }

    rc = ngx_http_send_header(r);
    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    if (b != NULL) {
        b->last_in_chain = 1;
        b->last_buf = 1;
    }

    return ngx_http_output_filter(r, &out);
}


static ngx_int_t
ngx_http_concat_add_path(ngx_http_request_t *r, ngx_array_t *uris,
    size_t max, ngx_str_t *path, u_char *p, u_char *v)
{
    u_char     *d;
    ngx_str_t  *uri, args;
    ngx_uint_t  flags;

    if (p == v) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "client sent zero concat filename");
        return NGX_HTTP_BAD_REQUEST;
    }

    if (uris->nelts >= max) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "client sent too many concat filenames");
        return NGX_HTTP_BAD_REQUEST;
    }

    uri = ngx_array_push(uris);
    if (uri == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    uri->len = path->len + p - v;
    uri->data = ngx_pnalloc(r->pool, uri->len + 1);  /* + '\0' */
    if (uri->data == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    d = ngx_cpymem(uri->data, path->data, path->len);
    d = ngx_cpymem(d, v, p - v);
    *d = '\0';

    args.len = 0;
    args.data = NULL;
    flags = NGX_HTTP_LOG_UNSAFE;

    if (ngx_http_parse_unsafe_uri(r, uri, &args, &flags) != NGX_OK) {
        return NGX_HTTP_BAD_REQUEST;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http concat add file: \"%s\"", uri->data);

    return NGX_OK;
}


static void *
ngx_http_concat_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_concat_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_concat_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->types = { NULL };
     *     conf->types_keys = NULL;
     */

    conf->enable = NGX_CONF_UNSET;
    conf->ignore_file_error = NGX_CONF_UNSET;
    conf->max_files = NGX_CONF_UNSET_UINT;
    conf->unique = NGX_CONF_UNSET;

    return conf;
}


static char *
ngx_http_concat_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_concat_loc_conf_t *prev = parent;
    ngx_http_concat_loc_conf_t *conf = child;

    ngx_conf_merge_value(conf->enable, prev->enable, 0);
    ngx_conf_merge_str_value(conf->delimiter, prev->delimiter, "");
    ngx_conf_merge_value(conf->ignore_file_error, prev->ignore_file_error, 0);
    ngx_conf_merge_uint_value(conf->max_files, prev->max_files, 10);
    ngx_conf_merge_value(conf->unique, prev->unique, 1);

    if (ngx_http_merge_types(cf, &conf->types_keys, &conf->types,
                             &prev->types_keys, &prev->types,
                             ngx_http_concat_default_types)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_concat_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt       *h;
    ngx_http_core_main_conf_t *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_CONTENT_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_concat_handler;

    return NGX_OK;
}
