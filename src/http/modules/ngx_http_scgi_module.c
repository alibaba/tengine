
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 * Copyright (C) Manlio Perillo (manlio.perillo@gmail.com)
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_http_upstream_conf_t   upstream;

    ngx_array_t               *flushes;
    ngx_array_t               *params_len;
    ngx_array_t               *params;
    ngx_array_t               *params_source;

    ngx_hash_t                 headers_hash;
    ngx_uint_t                 header_params;

    ngx_array_t               *scgi_lengths;
    ngx_array_t               *scgi_values;

#if (NGX_HTTP_CACHE)
    ngx_http_complex_value_t   cache_key;
#endif
} ngx_http_scgi_loc_conf_t;


static ngx_int_t ngx_http_scgi_eval(ngx_http_request_t *r,
    ngx_http_scgi_loc_conf_t *scf);
static ngx_int_t ngx_http_scgi_create_request(ngx_http_request_t *r);
static ngx_int_t ngx_http_scgi_reinit_request(ngx_http_request_t *r);
static ngx_int_t ngx_http_scgi_process_status_line(ngx_http_request_t *r);
static ngx_int_t ngx_http_scgi_process_header(ngx_http_request_t *r);
static void ngx_http_scgi_abort_request(ngx_http_request_t *r);
static void ngx_http_scgi_finalize_request(ngx_http_request_t *r, ngx_int_t rc);

static void *ngx_http_scgi_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_scgi_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static ngx_int_t ngx_http_scgi_merge_params(ngx_conf_t *cf,
    ngx_http_scgi_loc_conf_t *conf, ngx_http_scgi_loc_conf_t *prev);

static char *ngx_http_scgi_pass(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_http_scgi_store(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

#if (NGX_HTTP_CACHE)
static ngx_int_t ngx_http_scgi_create_key(ngx_http_request_t *r);
static char *ngx_http_scgi_cache(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_scgi_cache_key(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
#endif


static ngx_conf_bitmask_t ngx_http_scgi_next_upstream_masks[] = {
    { ngx_string("error"), NGX_HTTP_UPSTREAM_FT_ERROR },
    { ngx_string("timeout"), NGX_HTTP_UPSTREAM_FT_TIMEOUT },
    { ngx_string("invalid_header"), NGX_HTTP_UPSTREAM_FT_INVALID_HEADER },
    { ngx_string("http_500"), NGX_HTTP_UPSTREAM_FT_HTTP_500 },
    { ngx_string("http_503"), NGX_HTTP_UPSTREAM_FT_HTTP_503 },
    { ngx_string("http_404"), NGX_HTTP_UPSTREAM_FT_HTTP_404 },
    { ngx_string("updating"), NGX_HTTP_UPSTREAM_FT_UPDATING },
    { ngx_string("off"), NGX_HTTP_UPSTREAM_FT_OFF },
    { ngx_null_string, 0 }
};


ngx_module_t  ngx_http_scgi_module;


static ngx_command_t ngx_http_scgi_commands[] = {

    { ngx_string("scgi_pass"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_http_scgi_pass,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("scgi_store"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_scgi_store,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("scgi_store_access"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE123,
      ngx_conf_set_access_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.store_access),
      NULL },

    { ngx_string("scgi_buffering"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.buffering),
      NULL },

    { ngx_string("scgi_ignore_client_abort"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.ignore_client_abort),
      NULL },

    { ngx_string("scgi_bind"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_upstream_bind_set_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.local),
      NULL },

    { ngx_string("scgi_connect_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.connect_timeout),
      NULL },

    { ngx_string("scgi_send_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.send_timeout),
      NULL },

    { ngx_string("scgi_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.buffer_size),
      NULL },

    { ngx_string("scgi_pass_request_headers"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.pass_request_headers),
      NULL },

    { ngx_string("scgi_pass_request_body"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.pass_request_body),
      NULL },

    { ngx_string("scgi_intercept_errors"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.intercept_errors),
      NULL },

    { ngx_string("scgi_read_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.read_timeout),
      NULL },

    { ngx_string("scgi_buffers"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_conf_set_bufs_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.bufs),
      NULL },

    { ngx_string("scgi_busy_buffers_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.busy_buffers_size_conf),
      NULL },

#if (NGX_HTTP_CACHE)

    { ngx_string("scgi_cache"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_scgi_cache,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("scgi_cache_key"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_scgi_cache_key,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("scgi_cache_path"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_2MORE,
      ngx_http_file_cache_set_slot,
      0,
      0,
      &ngx_http_scgi_module },

    { ngx_string("scgi_cache_bypass"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_set_predicate_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.cache_bypass),
      NULL },

    { ngx_string("scgi_no_cache"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_set_predicate_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.no_cache),
      NULL },

    { ngx_string("scgi_cache_valid"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_file_cache_valid_set_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.cache_valid),
      NULL },

    { ngx_string("scgi_cache_min_uses"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.cache_min_uses),
      NULL },

    { ngx_string("scgi_cache_use_stale"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.cache_use_stale),
      &ngx_http_scgi_next_upstream_masks },

    { ngx_string("scgi_cache_methods"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.cache_methods),
      &ngx_http_upstream_cache_method_mask },

    { ngx_string("scgi_cache_lock"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.cache_lock),
      NULL },

    { ngx_string("scgi_cache_lock_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.cache_lock_timeout),
      NULL },

#endif

    { ngx_string("scgi_temp_path"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1234,
      ngx_conf_set_path_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.temp_path),
      NULL },

    { ngx_string("scgi_max_temp_file_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.max_temp_file_size_conf),
      NULL },

    { ngx_string("scgi_temp_file_write_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.temp_file_write_size_conf),
      NULL },

    { ngx_string("scgi_next_upstream"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.next_upstream),
      &ngx_http_scgi_next_upstream_masks },

    { ngx_string("scgi_param"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE23,
      ngx_http_upstream_param_set_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, params_source),
      NULL },

    { ngx_string("scgi_pass_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_array_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.pass_headers),
      NULL },

    { ngx_string("scgi_hide_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_array_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.hide_headers),
      NULL },

    { ngx_string("scgi_ignore_headers"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_scgi_loc_conf_t, upstream.ignore_headers),
      &ngx_http_upstream_ignore_headers_masks },

      ngx_null_command
};


static ngx_http_module_t ngx_http_scgi_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_scgi_create_loc_conf,         /* create location configuration */
    ngx_http_scgi_merge_loc_conf           /* merge location configuration */
};


ngx_module_t ngx_http_scgi_module = {
    NGX_MODULE_V1,
    &ngx_http_scgi_module_ctx,             /* module context */
    ngx_http_scgi_commands,                /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_str_t ngx_http_scgi_hide_headers[] = {
    ngx_string("Status"),
    ngx_string("X-Accel-Expires"),
    ngx_string("X-Accel-Redirect"),
    ngx_string("X-Accel-Limit-Rate"),
    ngx_string("X-Accel-Buffering"),
    ngx_string("X-Accel-Charset"),
    ngx_null_string
};


#if (NGX_HTTP_CACHE)

static ngx_keyval_t  ngx_http_scgi_cache_headers[] = {
    { ngx_string("HTTP_IF_MODIFIED_SINCE"), ngx_string("") },
    { ngx_string("HTTP_IF_UNMODIFIED_SINCE"), ngx_string("") },
    { ngx_string("HTTP_IF_NONE_MATCH"), ngx_string("") },
    { ngx_string("HTTP_IF_MATCH"), ngx_string("") },
    { ngx_string("HTTP_RANGE"), ngx_string("") },
    { ngx_string("HTTP_IF_RANGE"), ngx_string("") },
    { ngx_null_string, ngx_null_string }
};

#endif


static ngx_path_init_t ngx_http_scgi_temp_path = {
    ngx_string(NGX_HTTP_SCGI_TEMP_PATH), { 1, 2, 0 }
};


static ngx_int_t
ngx_http_scgi_handler(ngx_http_request_t *r)
{
    ngx_int_t                  rc;
    ngx_http_status_t         *status;
    ngx_http_upstream_t       *u;
    ngx_http_scgi_loc_conf_t  *scf;

    if (r->subrequest_in_memory) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                      "ngx_http_scgi_module does not support "
                      "subrequests in memory");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (ngx_http_upstream_create(r) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    status = ngx_pcalloc(r->pool, sizeof(ngx_http_status_t));
    if (status == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ngx_http_set_ctx(r, status, ngx_http_scgi_module);

    scf = ngx_http_get_module_loc_conf(r, ngx_http_scgi_module);

    if (scf->scgi_lengths) {
        if (ngx_http_scgi_eval(r, scf) != NGX_OK) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }
    }

    u = r->upstream;

    ngx_str_set(&u->schema, "scgi://");
    u->output.tag = (ngx_buf_tag_t) &ngx_http_scgi_module;

    u->conf = &scf->upstream;

#if (NGX_HTTP_CACHE)
    u->create_key = ngx_http_scgi_create_key;
#endif
    u->create_request = ngx_http_scgi_create_request;
    u->reinit_request = ngx_http_scgi_reinit_request;
    u->process_header = ngx_http_scgi_process_status_line;
    u->abort_request = ngx_http_scgi_abort_request;
    u->finalize_request = ngx_http_scgi_finalize_request;

    u->buffering = scf->upstream.buffering;

    u->pipe = ngx_pcalloc(r->pool, sizeof(ngx_event_pipe_t));
    if (u->pipe == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    u->pipe->input_filter = ngx_event_pipe_copy_input_filter;
    u->pipe->input_ctx = r;

    rc = ngx_http_read_client_request_body(r, ngx_http_upstream_init);

    if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return rc;
    }

    return NGX_DONE;
}


static ngx_int_t
ngx_http_scgi_eval(ngx_http_request_t *r, ngx_http_scgi_loc_conf_t * scf)
{
    ngx_url_t             url;
    ngx_http_upstream_t  *u;

    ngx_memzero(&url, sizeof(ngx_url_t));

    if (ngx_http_script_run(r, &url.url, scf->scgi_lengths->elts, 0,
                            scf->scgi_values->elts)
        == NULL)
    {
        return NGX_ERROR;
    }

    url.no_resolve = 1;

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        if (url.err) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "%s in upstream \"%V\"", url.err, &url.url);
        }

        return NGX_ERROR;
    }

    u = r->upstream;

    u->resolved = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_resolved_t));
    if (u->resolved == NULL) {
        return NGX_ERROR;
    }

    if (url.addrs && url.addrs[0].sockaddr) {
        u->resolved->sockaddr = url.addrs[0].sockaddr;
        u->resolved->socklen = url.addrs[0].socklen;
        u->resolved->naddrs = 1;
        u->resolved->host = url.addrs[0].name;

    } else {
        u->resolved->host = url.host;
        u->resolved->port = url.port;
        u->resolved->no_port = url.no_port;
    }

    return NGX_OK;
}


#if (NGX_HTTP_CACHE)

static ngx_int_t
ngx_http_scgi_create_key(ngx_http_request_t *r)
{
    ngx_str_t                 *key;
    ngx_http_scgi_loc_conf_t  *scf;

    key = ngx_array_push(&r->cache->keys);
    if (key == NULL) {
        return NGX_ERROR;
    }

    scf = ngx_http_get_module_loc_conf(r, ngx_http_scgi_module);

    if (ngx_http_complex_value(r, &scf->cache_key, key) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}

#endif


static ngx_int_t
ngx_http_scgi_create_request(ngx_http_request_t *r)
{
    u_char                        ch, *key, *val, *lowcase_key;
    size_t                        len, key_len, val_len, allocated;
    ngx_buf_t                    *b;
    ngx_str_t                    *content_length;
    ngx_uint_t                    i, n, hash, skip_empty, header_params;
    ngx_chain_t                  *cl, *body;
    ngx_list_part_t              *part;
    ngx_table_elt_t              *header, **ignored;
    ngx_http_script_code_pt       code;
    ngx_http_script_engine_t      e, le;
    ngx_http_scgi_loc_conf_t     *scf;
    ngx_http_script_len_code_pt   lcode;
    static ngx_str_t              zero = ngx_string("0");

    content_length = r->headers_in.content_length ?
                         &r->headers_in.content_length->value : &zero;

    len = sizeof("CONTENT_LENGTH") + content_length->len + 1;

    header_params = 0;
    ignored = NULL;

    scf = ngx_http_get_module_loc_conf(r, ngx_http_scgi_module);

    if (scf->params_len) {
        ngx_memzero(&le, sizeof(ngx_http_script_engine_t));

        ngx_http_script_flush_no_cacheable_variables(r, scf->flushes);
        le.flushed = 1;

        le.ip = scf->params_len->elts;
        le.request = r;

        while (*(uintptr_t *) le.ip) {

            lcode = *(ngx_http_script_len_code_pt *) le.ip;
            key_len = lcode(&le);

            lcode = *(ngx_http_script_len_code_pt *) le.ip;
            skip_empty = lcode(&le);

            for (val_len = 0; *(uintptr_t *) le.ip; val_len += lcode(&le)) {
                lcode = *(ngx_http_script_len_code_pt *) le.ip;
            }
            le.ip += sizeof(uintptr_t);

            if (skip_empty && val_len == 0) {
                continue;
            }

            len += key_len + val_len + 1;
        }
    }

    if (scf->upstream.pass_request_headers) {

        allocated = 0;
        lowcase_key = NULL;

        if (scf->header_params) {
            n = 0;
            part = &r->headers_in.headers.part;

            while (part) {
                n += part->nelts;
                part = part->next;
            }

            ignored = ngx_palloc(r->pool, n * sizeof(void *));
            if (ignored == NULL) {
                return NGX_ERROR;
            }
        }

        part = &r->headers_in.headers.part;
        header = part->elts;

        for (i = 0; /* void */; i++) {

            if (i >= part->nelts) {
                if (part->next == NULL) {
                    break;
                }

                part = part->next;
                header = part->elts;
                i = 0;
            }

            if (scf->header_params) {
                if (allocated < header[i].key.len) {
                    allocated = header[i].key.len + 16;
                    lowcase_key = ngx_pnalloc(r->pool, allocated);
                    if (lowcase_key == NULL) {
                        return NGX_ERROR;
                    }
                }

                hash = 0;

                for (n = 0; n < header[i].key.len; n++) {
                    ch = header[i].key.data[n];

                    if (ch >= 'A' && ch <= 'Z') {
                        ch |= 0x20;

                    } else if (ch == '-') {
                        ch = '_';
                    }

                    hash = ngx_hash(hash, ch);
                    lowcase_key[n] = ch;
                }

                if (ngx_hash_find(&scf->headers_hash, hash, lowcase_key, n)) {
                    ignored[header_params++] = &header[i];
                    continue;
                }
            }

            len += sizeof("HTTP_") - 1 + header[i].key.len + 1
                + header[i].value.len + 1;
        }
    }

    /* netstring: "length:" + packet + "," */

    b = ngx_create_temp_buf(r->pool, NGX_SIZE_T_LEN + 1 + len + 1);
    if (b == NULL) {
        return NGX_ERROR;
    }

    cl = ngx_alloc_chain_link(r->pool);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    cl->buf = b;

    b->last = ngx_snprintf(b->last,
                           NGX_SIZE_T_LEN + 1 + sizeof("CONTENT_LENGTH")
                           + NGX_OFF_T_LEN + 1,
                           "%ui:CONTENT_LENGTH%Z%V%Z",
                           len, content_length);

    if (scf->params_len) {
        ngx_memzero(&e, sizeof(ngx_http_script_engine_t));

        e.ip = scf->params->elts;
        e.pos = b->last;
        e.request = r;
        e.flushed = 1;

        le.ip = scf->params_len->elts;

        while (*(uintptr_t *) le.ip) {

            lcode = *(ngx_http_script_len_code_pt *) le.ip;
            lcode(&le); /* key length */

            lcode = *(ngx_http_script_len_code_pt *) le.ip;
            skip_empty = lcode(&le);

            for (val_len = 0; *(uintptr_t *) le.ip; val_len += lcode(&le)) {
                lcode = *(ngx_http_script_len_code_pt *) le.ip;
            }
            le.ip += sizeof(uintptr_t);

            if (skip_empty && val_len == 0) {
                e.skip = 1;

                while (*(uintptr_t *) e.ip) {
                    code = *(ngx_http_script_code_pt *) e.ip;
                    code((ngx_http_script_engine_t *) &e);
                }
                e.ip += sizeof(uintptr_t);

                e.skip = 0;

                continue;
            }

#if (NGX_DEBUG)
            key = e.pos;
#endif
            code = *(ngx_http_script_code_pt *) e.ip;
            code((ngx_http_script_engine_t *) & e);

#if (NGX_DEBUG)
            val = e.pos;
#endif
            while (*(uintptr_t *) e.ip) {
                code = *(ngx_http_script_code_pt *) e.ip;
                code((ngx_http_script_engine_t *) &e);
            }
            *e.pos++ = '\0';
            e.ip += sizeof(uintptr_t);

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "scgi param: \"%s: %s\"", key, val);
        }

        b->last = e.pos;
    }

    if (scf->upstream.pass_request_headers) {

        part = &r->headers_in.headers.part;
        header = part->elts;

        for (i = 0; /* void */; i++) {

            if (i >= part->nelts) {
                if (part->next == NULL) {
                    break;
                }

                part = part->next;
                header = part->elts;
                i = 0;
            }

            for (n = 0; n < header_params; n++) {
                if (&header[i] == ignored[n]) {
                    goto next;
                }
            }

            key = b->last;
            b->last = ngx_cpymem(key, "HTTP_", sizeof("HTTP_") - 1);

            for (n = 0; n < header[i].key.len; n++) {
                ch = header[i].key.data[n];

                if (ch >= 'a' && ch <= 'z') {
                    ch &= ~0x20;

                } else if (ch == '-') {
                    ch = '_';
                }

                *b->last++ = ch;
            }

            *b->last++ = (u_char) 0;

            val = b->last;
            b->last = ngx_copy(val, header[i].value.data, header[i].value.len);
            *b->last++ = (u_char) 0;

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "scgi param: \"%s: %s\"", key, val);

        next:

            continue;
         }
    }

    *b->last++ = (u_char) ',';

    if (scf->upstream.pass_request_body) {
        body = r->upstream->request_bufs;
        r->upstream->request_bufs = cl;

        while (body) {
            b = ngx_alloc_buf(r->pool);
            if (b == NULL) {
                return NGX_ERROR;
            }

            ngx_memcpy(b, body->buf, sizeof(ngx_buf_t));

            cl->next = ngx_alloc_chain_link(r->pool);
            if (cl->next == NULL) {
                return NGX_ERROR;
            }

            cl = cl->next;
            cl->buf = b;

            body = body->next;
        }

    } else {
        r->upstream->request_bufs = cl;
    }

    cl->next = NULL;

    return NGX_OK;
}


static ngx_int_t
ngx_http_scgi_reinit_request(ngx_http_request_t *r)
{
    ngx_http_status_t  *status;

    status = ngx_http_get_module_ctx(r, ngx_http_scgi_module);

    if (status == NULL) {
        return NGX_OK;
    }

    status->code = 0;
    status->count = 0;
    status->start = NULL;
    status->end = NULL;

    r->upstream->process_header = ngx_http_scgi_process_status_line;

    return NGX_OK;
}


static ngx_int_t
ngx_http_scgi_process_status_line(ngx_http_request_t *r)
{
    size_t                len;
    ngx_int_t             rc;
    ngx_http_status_t    *status;
    ngx_http_upstream_t  *u;

    status = ngx_http_get_module_ctx(r, ngx_http_scgi_module);

    if (status == NULL) {
        return NGX_ERROR;
    }

    u = r->upstream;

    rc = ngx_http_parse_status_line(r, &u->buffer, status);

    if (rc == NGX_AGAIN) {
        return rc;
    }

    if (rc == NGX_ERROR) {
        u->process_header = ngx_http_scgi_process_header;
        return ngx_http_scgi_process_header(r);
    }

    if (u->state) {
        u->state->status = status->code;
    }

    u->headers_in.status_n = status->code;

    len = status->end - status->start;
    u->headers_in.status_line.len = len;

    u->headers_in.status_line.data = ngx_pnalloc(r->pool, len);
    if (u->headers_in.status_line.data == NULL) {
        return NGX_ERROR;
    }

    ngx_memcpy(u->headers_in.status_line.data, status->start, len);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http scgi status %ui \"%V\"",
                   u->headers_in.status_n, &u->headers_in.status_line);

    u->process_header = ngx_http_scgi_process_header;

    return ngx_http_scgi_process_header(r);
}


static ngx_int_t
ngx_http_scgi_process_header(ngx_http_request_t *r)
{
    ngx_str_t                      *status_line;
    ngx_int_t                       rc, status;
    ngx_table_elt_t                *h;
    ngx_http_upstream_t            *u;
    ngx_http_upstream_header_t     *hh;
    ngx_http_upstream_main_conf_t  *umcf;

    umcf = ngx_http_get_module_main_conf(r, ngx_http_upstream_module);

    for ( ;; ) {

        rc = ngx_http_parse_header_line(r, &r->upstream->buffer, 1);

        if (rc == NGX_OK) {

            /* a header line has been parsed successfully */

            h = ngx_list_push(&r->upstream->headers_in.headers);
            if (h == NULL) {
                return NGX_ERROR;
            }

            h->hash = r->header_hash;

            h->key.len = r->header_name_end - r->header_name_start;
            h->value.len = r->header_end - r->header_start;

            h->key.data = ngx_pnalloc(r->pool,
                                      h->key.len + 1 + h->value.len + 1
                                      + h->key.len);
            if (h->key.data == NULL) {
                return NGX_ERROR;
            }

            h->value.data = h->key.data + h->key.len + 1;
            h->lowcase_key = h->key.data + h->key.len + 1 + h->value.len + 1;

            ngx_memcpy(h->key.data, r->header_name_start, h->key.len);
            h->key.data[h->key.len] = '\0';
            ngx_memcpy(h->value.data, r->header_start, h->value.len);
            h->value.data[h->value.len] = '\0';

            if (h->key.len == r->lowcase_index) {
                ngx_memcpy(h->lowcase_key, r->lowcase_header, h->key.len);

            } else {
                ngx_strlow(h->lowcase_key, h->key.data, h->key.len);
            }

            hh = ngx_hash_find(&umcf->headers_in_hash, h->hash,
                               h->lowcase_key, h->key.len);

            if (hh && hh->handler(r, h, hh->offset) != NGX_OK) {
                return NGX_ERROR;
            }

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "http scgi header: \"%V: %V\"", &h->key, &h->value);

            continue;
        }

        if (rc == NGX_HTTP_PARSE_HEADER_DONE) {

            /* a whole header has been parsed successfully */

            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "http scgi header done");

            u = r->upstream;

            if (u->headers_in.status_n) {
                return NGX_OK;
            }

            if (u->headers_in.status) {
                status_line = &u->headers_in.status->value;

                status = ngx_atoi(status_line->data, 3);
                if (status == NGX_ERROR) {
                    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                                  "upstream sent invalid status \"%V\"",
                                  status_line);
                    return NGX_HTTP_UPSTREAM_INVALID_HEADER;
                }

                u->headers_in.status_n = status;
                u->headers_in.status_line = *status_line;

            } else if (u->headers_in.location) {
                u->headers_in.status_n = 302;
                ngx_str_set(&u->headers_in.status_line,
                            "302 Moved Temporarily");

            } else {
                u->headers_in.status_n = 200;
                ngx_str_set(&u->headers_in.status_line, "200 OK");
            }

            if (u->state) {
                u->state->status = u->headers_in.status_n;
            }

            return NGX_OK;
        }

        if (rc == NGX_AGAIN) {
            return NGX_AGAIN;
        }

        /* there was error while a header line parsing */

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "upstream sent invalid header");

        return NGX_HTTP_UPSTREAM_INVALID_HEADER;
    }
}


static void
ngx_http_scgi_abort_request(ngx_http_request_t *r)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "abort http scgi request");

    return;
}


static void
ngx_http_scgi_finalize_request(ngx_http_request_t *r, ngx_int_t rc)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "finalize http scgi request");

    return;
}


static void *
ngx_http_scgi_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_scgi_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_scgi_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    conf->upstream.store = NGX_CONF_UNSET;
    conf->upstream.store_access = NGX_CONF_UNSET_UINT;
    conf->upstream.buffering = NGX_CONF_UNSET;
    conf->upstream.ignore_client_abort = NGX_CONF_UNSET;

    conf->upstream.connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->upstream.send_timeout = NGX_CONF_UNSET_MSEC;
    conf->upstream.read_timeout = NGX_CONF_UNSET_MSEC;

    conf->upstream.send_lowat = NGX_CONF_UNSET_SIZE;
    conf->upstream.buffer_size = NGX_CONF_UNSET_SIZE;

    conf->upstream.busy_buffers_size_conf = NGX_CONF_UNSET_SIZE;
    conf->upstream.max_temp_file_size_conf = NGX_CONF_UNSET_SIZE;
    conf->upstream.temp_file_write_size_conf = NGX_CONF_UNSET_SIZE;

    conf->upstream.pass_request_headers = NGX_CONF_UNSET;
    conf->upstream.pass_request_body = NGX_CONF_UNSET;

#if (NGX_HTTP_CACHE)
    conf->upstream.cache = NGX_CONF_UNSET_PTR;
    conf->upstream.cache_min_uses = NGX_CONF_UNSET_UINT;
    conf->upstream.cache_bypass = NGX_CONF_UNSET_PTR;
    conf->upstream.no_cache = NGX_CONF_UNSET_PTR;
    conf->upstream.cache_valid = NGX_CONF_UNSET_PTR;
    conf->upstream.cache_lock = NGX_CONF_UNSET;
    conf->upstream.cache_lock_timeout = NGX_CONF_UNSET_MSEC;
#endif

    conf->upstream.hide_headers = NGX_CONF_UNSET_PTR;
    conf->upstream.pass_headers = NGX_CONF_UNSET_PTR;

    conf->upstream.intercept_errors = NGX_CONF_UNSET;

    /* "scgi_cyclic_temp_file" is disabled */
    conf->upstream.cyclic_temp_file = 0;

    conf->upstream.change_buffering = 1;

    ngx_str_set(&conf->upstream.module, "scgi");

    return conf;
}


static char *
ngx_http_scgi_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_scgi_loc_conf_t *prev = parent;
    ngx_http_scgi_loc_conf_t *conf = child;

    size_t                        size;
    ngx_hash_init_t               hash;
    ngx_http_core_loc_conf_t     *clcf;

    if (conf->upstream.store != 0) {
        ngx_conf_merge_value(conf->upstream.store, prev->upstream.store, 0);

        if (conf->upstream.store_lengths == NULL) {
            conf->upstream.store_lengths = prev->upstream.store_lengths;
            conf->upstream.store_values = prev->upstream.store_values;
        }
    }

    ngx_conf_merge_uint_value(conf->upstream.store_access,
                              prev->upstream.store_access, 0600);

    ngx_conf_merge_value(conf->upstream.buffering,
                              prev->upstream.buffering, 1);

    ngx_conf_merge_value(conf->upstream.ignore_client_abort,
                              prev->upstream.ignore_client_abort, 0);

    ngx_conf_merge_msec_value(conf->upstream.connect_timeout,
                              prev->upstream.connect_timeout, 60000);

    ngx_conf_merge_msec_value(conf->upstream.send_timeout,
                              prev->upstream.send_timeout, 60000);

    ngx_conf_merge_msec_value(conf->upstream.read_timeout,
                              prev->upstream.read_timeout, 60000);

    ngx_conf_merge_size_value(conf->upstream.send_lowat,
                              prev->upstream.send_lowat, 0);

    ngx_conf_merge_size_value(conf->upstream.buffer_size,
                              prev->upstream.buffer_size,
                              (size_t) ngx_pagesize);


    ngx_conf_merge_bufs_value(conf->upstream.bufs, prev->upstream.bufs,
                              8, ngx_pagesize);

    if (conf->upstream.bufs.num < 2) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "there must be at least 2 \"scgi_buffers\"");
        return NGX_CONF_ERROR;
    }


    size = conf->upstream.buffer_size;
    if (size < conf->upstream.bufs.size) {
        size = conf->upstream.bufs.size;
    }


    ngx_conf_merge_size_value(conf->upstream.busy_buffers_size_conf,
                              prev->upstream.busy_buffers_size_conf,
                              NGX_CONF_UNSET_SIZE);

    if (conf->upstream.busy_buffers_size_conf == NGX_CONF_UNSET_SIZE) {
        conf->upstream.busy_buffers_size = 2 * size;
    } else {
        conf->upstream.busy_buffers_size =
            conf->upstream.busy_buffers_size_conf;
    }

    if (conf->upstream.busy_buffers_size < size) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
            "\"scgi_busy_buffers_size\" must be equal to or greater "
            "than the maximum of the value of \"scgi_buffer_size\" and "
            "one of the \"scgi_buffers\"");

        return NGX_CONF_ERROR;
    }

    if (conf->upstream.busy_buffers_size
        > (conf->upstream.bufs.num - 1) * conf->upstream.bufs.size)
    {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
            "\"scgi_busy_buffers_size\" must be less than "
            "the size of all \"scgi_buffers\" minus one buffer");

        return NGX_CONF_ERROR;
    }


    ngx_conf_merge_size_value(conf->upstream.temp_file_write_size_conf,
                              prev->upstream.temp_file_write_size_conf,
                              NGX_CONF_UNSET_SIZE);

    if (conf->upstream.temp_file_write_size_conf == NGX_CONF_UNSET_SIZE) {
        conf->upstream.temp_file_write_size = 2 * size;
    } else {
        conf->upstream.temp_file_write_size =
            conf->upstream.temp_file_write_size_conf;
    }

    if (conf->upstream.temp_file_write_size < size) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
            "\"scgi_temp_file_write_size\" must be equal to or greater than "
            "the maximum of the value of \"scgi_buffer_size\" and "
            "one of the \"scgi_buffers\"");

        return NGX_CONF_ERROR;
    }


    ngx_conf_merge_size_value(conf->upstream.max_temp_file_size_conf,
                              prev->upstream.max_temp_file_size_conf,
                              NGX_CONF_UNSET_SIZE);

    if (conf->upstream.max_temp_file_size_conf == NGX_CONF_UNSET_SIZE) {
        conf->upstream.max_temp_file_size = 1024 * 1024 * 1024;
    } else {
        conf->upstream.max_temp_file_size =
            conf->upstream.max_temp_file_size_conf;
    }

    if (conf->upstream.max_temp_file_size != 0
        && conf->upstream.max_temp_file_size < size) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
            "\"scgi_max_temp_file_size\" must be equal to zero to disable "
            "temporary files usage or must be equal to or greater than "
            "the maximum of the value of \"scgi_buffer_size\" and "
            "one of the \"scgi_buffers\"");

        return NGX_CONF_ERROR;
    }


    ngx_conf_merge_bitmask_value(conf->upstream.ignore_headers,
                                 prev->upstream.ignore_headers,
                                 NGX_CONF_BITMASK_SET);


    ngx_conf_merge_bitmask_value(conf->upstream.next_upstream,
                                 prev->upstream.next_upstream,
                                 (NGX_CONF_BITMASK_SET
                                  |NGX_HTTP_UPSTREAM_FT_ERROR
                                  |NGX_HTTP_UPSTREAM_FT_TIMEOUT));

    if (conf->upstream.next_upstream & NGX_HTTP_UPSTREAM_FT_OFF) {
        conf->upstream.next_upstream = NGX_CONF_BITMASK_SET
                                       |NGX_HTTP_UPSTREAM_FT_OFF;
    }

    if (ngx_conf_merge_path_value(cf, &conf->upstream.temp_path,
                                  prev->upstream.temp_path,
                                  &ngx_http_scgi_temp_path)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

#if (NGX_HTTP_CACHE)

    ngx_conf_merge_ptr_value(conf->upstream.cache,
                              prev->upstream.cache, NULL);

    if (conf->upstream.cache && conf->upstream.cache->data == NULL) {
        ngx_shm_zone_t  *shm_zone;

        shm_zone = conf->upstream.cache;

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"scgi_cache\" zone \"%V\" is unknown",
                           &shm_zone->shm.name);

        return NGX_CONF_ERROR;
    }

    ngx_conf_merge_uint_value(conf->upstream.cache_min_uses,
                              prev->upstream.cache_min_uses, 1);

    ngx_conf_merge_bitmask_value(conf->upstream.cache_use_stale,
                              prev->upstream.cache_use_stale,
                              (NGX_CONF_BITMASK_SET
                               |NGX_HTTP_UPSTREAM_FT_OFF));

    if (conf->upstream.cache_use_stale & NGX_HTTP_UPSTREAM_FT_OFF) {
        conf->upstream.cache_use_stale = NGX_CONF_BITMASK_SET
                                         |NGX_HTTP_UPSTREAM_FT_OFF;
    }

    if (conf->upstream.cache_use_stale & NGX_HTTP_UPSTREAM_FT_ERROR) {
        conf->upstream.cache_use_stale |= NGX_HTTP_UPSTREAM_FT_NOLIVE;
    }

    if (conf->upstream.cache_methods == 0) {
        conf->upstream.cache_methods = prev->upstream.cache_methods;
    }

    conf->upstream.cache_methods |= NGX_HTTP_GET|NGX_HTTP_HEAD;

    ngx_conf_merge_ptr_value(conf->upstream.cache_bypass,
                             prev->upstream.cache_bypass, NULL);

    ngx_conf_merge_ptr_value(conf->upstream.no_cache,
                             prev->upstream.no_cache, NULL);

    ngx_conf_merge_ptr_value(conf->upstream.cache_valid,
                             prev->upstream.cache_valid, NULL);

    if (conf->cache_key.value.data == NULL) {
        conf->cache_key = prev->cache_key;
    }

    ngx_conf_merge_value(conf->upstream.cache_lock,
                              prev->upstream.cache_lock, 0);

    ngx_conf_merge_msec_value(conf->upstream.cache_lock_timeout,
                              prev->upstream.cache_lock_timeout, 5000);

#endif

    ngx_conf_merge_value(conf->upstream.pass_request_headers,
                         prev->upstream.pass_request_headers, 1);
    ngx_conf_merge_value(conf->upstream.pass_request_body,
                         prev->upstream.pass_request_body, 1);

    ngx_conf_merge_value(conf->upstream.intercept_errors,
                         prev->upstream.intercept_errors, 0);

    hash.max_size = 512;
    hash.bucket_size = ngx_align(64, ngx_cacheline_size);
    hash.name = "scgi_hide_headers_hash";

    if (ngx_http_upstream_hide_headers_hash(cf, &conf->upstream,
            &prev->upstream, ngx_http_scgi_hide_headers, &hash)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    if (conf->upstream.upstream == NULL) {
        conf->upstream.upstream = prev->upstream.upstream;
    }

    if (conf->scgi_lengths == NULL) {
        conf->scgi_lengths = prev->scgi_lengths;
        conf->scgi_values = prev->scgi_values;
    }

    if (conf->upstream.upstream || conf->scgi_lengths) {
        clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
        if (clcf->handler == NULL && clcf->lmt_excpt) {
            clcf->handler = ngx_http_scgi_handler;
        }
    }

    if (ngx_http_scgi_merge_params(cf, conf, prev) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_scgi_merge_params(ngx_conf_t *cf, ngx_http_scgi_loc_conf_t *conf,
    ngx_http_scgi_loc_conf_t *prev)
{
    u_char                       *p;
    size_t                        size;
    uintptr_t                    *code;
    ngx_uint_t                    i, nsrc;
    ngx_array_t                   headers_names;
#if (NGX_HTTP_CACHE)
    ngx_array_t                   params_merged;
#endif
    ngx_hash_key_t               *hk;
    ngx_hash_init_t               hash;
    ngx_http_upstream_param_t    *src;
    ngx_http_script_compile_t     sc;
    ngx_http_script_copy_code_t  *copy;

    if (conf->params_source == NULL) {
        conf->params_source = prev->params_source;

        if (prev->headers_hash.buckets
#if (NGX_HTTP_CACHE)
            && ((conf->upstream.cache == NULL)
                == (prev->upstream.cache == NULL))
#endif
           )
        {
            conf->flushes = prev->flushes;
            conf->params_len = prev->params_len;
            conf->params = prev->params;
            conf->headers_hash = prev->headers_hash;
            conf->header_params = prev->header_params;

            return NGX_OK;
        }
    }

    if (conf->params_source == NULL
#if (NGX_HTTP_CACHE)
        && (conf->upstream.cache == NULL)
#endif
       )
    {
        conf->headers_hash.buckets = (void *) 1;
        return NGX_OK;
    }

    conf->params_len = ngx_array_create(cf->pool, 64, 1);
    if (conf->params_len == NULL) {
        return NGX_ERROR;
    }

    conf->params = ngx_array_create(cf->pool, 512, 1);
    if (conf->params == NULL) {
        return NGX_ERROR;
    }

    if (ngx_array_init(&headers_names, cf->temp_pool, 4, sizeof(ngx_hash_key_t))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    if (conf->params_source) {
        src = conf->params_source->elts;
        nsrc = conf->params_source->nelts;

    } else {
        src = NULL;
        nsrc = 0;
    }

#if (NGX_HTTP_CACHE)

    if (conf->upstream.cache) {
        ngx_keyval_t               *h;
        ngx_http_upstream_param_t  *s;

        if (ngx_array_init(&params_merged, cf->temp_pool, 4,
                           sizeof(ngx_http_upstream_param_t))
            != NGX_OK)
        {
            return NGX_ERROR;
        }

        for (i = 0; i < nsrc; i++) {

            s = ngx_array_push(&params_merged);
            if (s == NULL) {
                return NGX_ERROR;
            }

            *s = src[i];
        }

        h = ngx_http_scgi_cache_headers;

        while (h->key.len) {

            src = params_merged.elts;
            nsrc = params_merged.nelts;

            for (i = 0; i < nsrc; i++) {
                if (ngx_strcasecmp(h->key.data, src[i].key.data) == 0) {
                    goto next;
                }
            }

            s = ngx_array_push(&params_merged);
            if (s == NULL) {
                return NGX_ERROR;
            }

            s->key = h->key;
            s->value = h->value;
            s->skip_empty = 0;

        next:

            h++;
        }

        src = params_merged.elts;
        nsrc = params_merged.nelts;
    }

#endif

    for (i = 0; i < nsrc; i++) {

        if (src[i].key.len > sizeof("HTTP_") - 1
            && ngx_strncmp(src[i].key.data, "HTTP_", sizeof("HTTP_") - 1) == 0)
        {
            hk = ngx_array_push(&headers_names);
            if (hk == NULL) {
                return NGX_ERROR;
            }

            hk->key.len = src[i].key.len - 5;
            hk->key.data = src[i].key.data + 5;
            hk->key_hash = ngx_hash_key_lc(hk->key.data, hk->key.len);
            hk->value = (void *) 1;

            if (src[i].value.len == 0) {
                continue;
            }
        }

        copy = ngx_array_push_n(conf->params_len,
                                sizeof(ngx_http_script_copy_code_t));
        if (copy == NULL) {
            return NGX_ERROR;
        }

        copy->code = (ngx_http_script_code_pt) ngx_http_script_copy_len_code;
        copy->len = src[i].key.len + 1;

        copy = ngx_array_push_n(conf->params_len,
                                sizeof(ngx_http_script_copy_code_t));
        if (copy == NULL) {
            return NGX_ERROR;
        }

        copy->code = (ngx_http_script_code_pt) ngx_http_script_copy_len_code;
        copy->len = src[i].skip_empty;


        size = (sizeof(ngx_http_script_copy_code_t)
                + src[i].key.len + 1 + sizeof(uintptr_t) - 1)
               & ~(sizeof(uintptr_t) - 1);

        copy = ngx_array_push_n(conf->params, size);
        if (copy == NULL) {
            return NGX_ERROR;
        }

        copy->code = ngx_http_script_copy_code;
        copy->len = src[i].key.len + 1;

        p = (u_char *) copy + sizeof(ngx_http_script_copy_code_t);
        (void) ngx_cpystrn(p, src[i].key.data, src[i].key.len + 1);


        ngx_memzero(&sc, sizeof(ngx_http_script_compile_t));

        sc.cf = cf;
        sc.source = &src[i].value;
        sc.flushes = &conf->flushes;
        sc.lengths = &conf->params_len;
        sc.values = &conf->params;

        if (ngx_http_script_compile(&sc) != NGX_OK) {
            return NGX_ERROR;
        }

        code = ngx_array_push_n(conf->params_len, sizeof(uintptr_t));
        if (code == NULL) {
            return NGX_ERROR;
        }

        *code = (uintptr_t) NULL;


        code = ngx_array_push_n(conf->params, sizeof(uintptr_t));
        if (code == NULL) {
            return NGX_ERROR;
        }

        *code = (uintptr_t) NULL;
    }

    code = ngx_array_push_n(conf->params_len, sizeof(uintptr_t));
    if (code == NULL) {
        return NGX_ERROR;
    }

    *code = (uintptr_t) NULL;

    code = ngx_array_push_n(conf->params, sizeof(uintptr_t));
    if (code == NULL) {
        return NGX_ERROR;
    }

    *code = (uintptr_t) NULL;

    conf->header_params = headers_names.nelts;

    hash.hash = &conf->headers_hash;
    hash.key = ngx_hash_key_lc;
    hash.max_size = 512;
    hash.bucket_size = 64;
    hash.name = "scgi_params_hash";
    hash.pool = cf->pool;
    hash.temp_pool = NULL;

    return ngx_hash_init(&hash, headers_names.elts, headers_names.nelts);
}


static char *
ngx_http_scgi_pass(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_scgi_loc_conf_t *scf = conf;

    ngx_url_t                   u;
    ngx_str_t                  *value, *url;
    ngx_uint_t                  n;
    ngx_http_core_loc_conf_t   *clcf;
    ngx_http_script_compile_t   sc;

    if (scf->upstream.upstream || scf->scgi_lengths) {
        return "is duplicate";
    }

    clcf = ngx_http_conf_get_module_loc_conf (cf, ngx_http_core_module);
    clcf->handler = ngx_http_scgi_handler;

    value = cf->args->elts;

    url = &value[1];

    n = ngx_http_script_variables_count(url);

    if (n) {

        ngx_memzero(&sc, sizeof(ngx_http_script_compile_t));

        sc.cf = cf;
        sc.source = url;
        sc.lengths = &scf->scgi_lengths;
        sc.values = &scf->scgi_values;
        sc.variables = n;
        sc.complete_lengths = 1;
        sc.complete_values = 1;

        if (ngx_http_script_compile(&sc) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        return NGX_CONF_OK;
    }

    ngx_memzero(&u, sizeof(ngx_url_t));

    u.url = value[1];
    u.no_resolve = 1;

    scf->upstream.upstream = ngx_http_upstream_add(cf, &u, 0);
    if (scf->upstream.upstream == NULL) {
        return NGX_CONF_ERROR;
    }

    if (clcf->name.data[clcf->name.len - 1] == '/') {
        clcf->auto_redirect = 1;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_scgi_store(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_scgi_loc_conf_t *scf = conf;

    ngx_str_t                  *value;
    ngx_http_script_compile_t   sc;

    if (scf->upstream.store != NGX_CONF_UNSET || scf->upstream.store_lengths) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (ngx_strcmp(value[1].data, "off") == 0) {
        scf->upstream.store = 0;
        return NGX_CONF_OK;
    }

#if (NGX_HTTP_CACHE)

    if (scf->upstream.cache != NGX_CONF_UNSET_PTR
        && scf->upstream.cache != NULL)
    {
        return "is incompatible with \"scgi_cache\"";
    }

#endif

    if (ngx_strcmp(value[1].data, "on") == 0) {
        scf->upstream.store = 1;
        return NGX_CONF_OK;
    }

    /* include the terminating '\0' into script */
    value[1].len++;

    ngx_memzero(&sc, sizeof(ngx_http_script_compile_t));

    sc.cf = cf;
    sc.source = &value[1];
    sc.lengths = &scf->upstream.store_lengths;
    sc.values = &scf->upstream.store_values;
    sc.variables = ngx_http_script_variables_count(&value[1]);;
    sc.complete_lengths = 1;
    sc.complete_values = 1;

    if (ngx_http_script_compile(&sc) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


#if (NGX_HTTP_CACHE)

static char *
ngx_http_scgi_cache(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_scgi_loc_conf_t *scf = conf;

    ngx_str_t  *value;

    value = cf->args->elts;

    if (scf->upstream.cache != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    if (ngx_strcmp(value[1].data, "off") == 0) {
        scf->upstream.cache = NULL;
        return NGX_CONF_OK;
    }

    if (scf->upstream.store > 0 || scf->upstream.store_lengths) {
        return "is incompatible with \"scgi_store\"";
    }

    scf->upstream.cache = ngx_shared_memory_add(cf, &value[1], 0,
                                                &ngx_http_scgi_module);
    if (scf->upstream.cache == NULL) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_scgi_cache_key(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_scgi_loc_conf_t *scf = conf;

    ngx_str_t                         *value;
    ngx_http_compile_complex_value_t   ccv;

    value = cf->args->elts;

    if (scf->cache_key.value.len) {
        return "is duplicate";
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    ccv.cf = cf;
    ccv.value = &value[1];
    ccv.complex_value = &scf->cache_key;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}

#endif
