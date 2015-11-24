
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct {
    ngx_str_t                      begin;
    ngx_str_t                      end;

    ngx_str_t                      header;
    ngx_flag_t                     header_first;

    ngx_str_t                      footer;
    ngx_flag_t                     footer_last;
} ngx_http_slice_loc_conf_t;


static void *ngx_http_slice_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_slice_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_slice(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);


static ngx_command_t  ngx_http_slice_commands[] = {

    { ngx_string("slice"),
      NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
      ngx_http_slice,
      0,
      0,
      NULL },

    { ngx_string("slice_arg_begin"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_slice_loc_conf_t, begin),
      NULL },

    { ngx_string("slice_arg_end"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_slice_loc_conf_t, end),
      NULL },

    { ngx_string("slice_header"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_slice_loc_conf_t, header),
      NULL },

    { ngx_string("slice_footer"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_slice_loc_conf_t, footer),
      NULL },

    { ngx_string("slice_header_first"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_slice_loc_conf_t, header_first),
      NULL },

    { ngx_string("slice_footer_last"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_slice_loc_conf_t, footer_last),
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_slice_module_ctx = {
    NULL,                          /* preconfiguration */
    NULL,                          /* postconfiguration */

    NULL,                          /* create main configuration */
    NULL,                          /* init main configuration */

    NULL,                          /* create server configuration */
    NULL,                          /* merge server configuration */

    ngx_http_slice_create_loc_conf,/* create location configuration */
    ngx_http_slice_merge_loc_conf  /* merge location configuration */
};


ngx_module_t  ngx_http_slice_module = {
    NGX_MODULE_V1,
    &ngx_http_slice_module_ctx,    /* module context */
    ngx_http_slice_commands,       /* module directives */
    NGX_HTTP_MODULE,               /* module type */
    NULL,                          /* init master */
    NULL,                          /* init module */
    NULL,                          /* init process */
    NULL,                          /* init thread */
    NULL,                          /* exit thread */
    NULL,                          /* exit process */
    NULL,                          /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_slice_handler(ngx_http_request_t *r)
{
    u_char                    *last;
    off_t                      begin, end, len;
    size_t                     root;
    ngx_int_t                  rc;
    ngx_uint_t                 level, i;
    ngx_str_t                  path, value;
    ngx_log_t                 *log;
    ngx_buf_t                 *b;
    ngx_chain_t                out[3];
    ngx_open_file_info_t       of;
    ngx_http_core_loc_conf_t  *clcf;
    ngx_http_slice_loc_conf_t *slcf;

    if (!(r->method & (NGX_HTTP_GET|NGX_HTTP_HEAD))) {
        return NGX_HTTP_NOT_ALLOWED;
    }

    if (r->uri.data[r->uri.len - 1] == '/') {
        return NGX_DECLINED;
    }

    slcf = ngx_http_get_module_loc_conf(r, ngx_http_slice_module);

    rc = ngx_http_discard_request_body(r);

    if (rc != NGX_OK) {
        return rc;
    }

    last = ngx_http_map_uri_to_path(r, &path, &root, 0);
    if (last == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    log = r->connection->log;

    path.len = last - path.data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                   "http slice filename: \"%V\"", &path);

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    ngx_memzero(&of, sizeof(ngx_open_file_info_t));

    of.read_ahead = clcf->read_ahead;
    of.directio = clcf->directio;
    of.valid = clcf->open_file_cache_valid;
    of.min_uses = clcf->open_file_cache_min_uses;
    of.errors = clcf->open_file_cache_errors;
    of.events = clcf->open_file_cache_events;

    if (ngx_open_cached_file(clcf->open_file_cache, &path, &of, r->pool)
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

        if (rc != NGX_HTTP_NOT_FOUND || clcf->log_not_found) {
            ngx_log_error(level, log, of.err,
                          "%s \"%s\" failed", of.failed, path.data);
        }

        return rc;
    }

    if (!of.is_file) {

        if (ngx_close_file(of.fd) == NGX_FILE_ERROR) {
            ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                          ngx_close_file_n " \"%s\" failed", path.data);
        }

        return NGX_DECLINED;
    }

    r->root_tested = !r->error_page;

    begin = 0;
    end = of.size;

    if (r->args.len) {

        if (ngx_http_arg(r, slcf->begin.data, slcf->begin.len, &value)
            == NGX_OK)
        {
            begin = ngx_atoof(value.data, value.len);

            if (begin == NGX_ERROR || begin >= of.size) {
                begin = 0;
            }
        }

        if (ngx_http_arg(r, slcf->end.data, slcf->end.len, &value) == NGX_OK) {

            end = ngx_atoof(value.data, value.len);

            if (end == NGX_ERROR || end >= of.size) {
                end = of.size;
            }
        }
    }

    end = end < begin ? of.size : end;

    len = (end == begin) ? 0 : ((end - begin)
            + ((begin == 0 && slcf->header_first) ? slcf->header.len : 0)
            + ((end == of.size && slcf->footer_last) ? slcf->footer.len : 0));

    log->action = "sending slice to client";

    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = len;
    r->headers_out.last_modified_time = of.mtime;

    if (ngx_http_set_content_type(r) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (len == 0) {
        r->header_only = 1;
        return ngx_http_send_header(r);
    }

    /*
     * add header when the first header is not denied
     */
    if (slcf->header.len
        && !(begin == 0 && !slcf->header_first))
    {
        b = ngx_pcalloc(r->pool, sizeof(ngx_buf_t));
        if (b == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        b->pos = slcf->header.data;
        b->last = slcf->header.data + slcf->header.len;
        b->memory = 1;

        out[0].buf = b;
        out[0].next = &out[1];

        i = 0;
    } else {
        i = 1;
    }

    b = ngx_pcalloc(r->pool, sizeof(ngx_buf_t));
    if (b == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    b->file = ngx_pcalloc(r->pool, sizeof(ngx_file_t));
    if (b->file == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    r->allow_ranges = 1;

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    b->file_pos = begin;
    b->file_last = end;

    b->in_file = b->file_last ? 1: 0;
    b->last_buf = 1;
    b->last_in_chain = 1;

    b->file->fd = of.fd;
    b->file->name = path;
    b->file->log = log;
    b->file->directio = of.is_directio;

    out[1].buf = b;
    out[1].next = NULL;

    /*
     * add footer when the last footer is not denied
     */
    if (slcf->footer.len
        && !(end == of.size && !slcf->footer_last))
    {
        b = ngx_pcalloc(r->pool, sizeof(ngx_buf_t));
        if (b == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        b->pos = slcf->footer.data;
        b->last = slcf->footer.data + slcf->footer.len;
        b->memory = 1;
        b->last_buf = 1;
        b->last_in_chain = 1;

        out[2].buf = b;
        out[2].next = NULL;

        out[1].buf->last_buf = 0;
        out[1].buf->last_in_chain = 0;
        out[1].next = &out[2];
    }

    return ngx_http_output_filter(r, &out[i]);
}


static void *
ngx_http_slice_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_slice_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_slice_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc() :
     *
     *     conf->begin = { 0, NULL }
     *     conf->end = { 0, NULL }
     *     conf->header = { 0, NULL }
     *     conf->footer = { 0, NULL }
     */

    conf->header_first = NGX_CONF_UNSET;
    conf->footer_last = NGX_CONF_UNSET;

    return conf;
}


static char *
ngx_http_slice_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_slice_loc_conf_t  *prev = parent;
    ngx_http_slice_loc_conf_t  *conf = child;

    ngx_conf_merge_str_value(conf->begin, prev->begin, "begin");
    ngx_conf_merge_str_value(conf->end, prev->end, "end");
    ngx_conf_merge_str_value(conf->header, prev->header, "");
    ngx_conf_merge_str_value(conf->footer, prev->footer, "");
    ngx_conf_merge_value(conf->header_first, prev->header_first, 1);
    ngx_conf_merge_value(conf->footer_last, prev->footer_last, 1);

    return NGX_CONF_OK;
}


static char *
ngx_http_slice(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_core_loc_conf_t  *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_slice_handler;

    return NGX_CONF_OK;
}
