
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_capturefilter.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_rewriteby.h"
#include "ngx_http_lua_accessby.h"
#include "ngx_http_lua_logby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_headerfilterby.h"
#include "ngx_http_lua_bodyfilterby.h"
#include "ngx_http_lua_initby.h"
#include "ngx_http_lua_probe.h"


#if !defined(nginx_version) || nginx_version < 8054
#error "at least nginx 0.8.54 is required"
#endif


static void *ngx_http_lua_create_main_conf(ngx_conf_t *cf);
static char *ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf);
static void *ngx_http_lua_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_lua_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_lua_init_vm(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf);
static void ngx_http_lua_cleanup_vm(void *data);
static ngx_int_t ngx_http_lua_init(ngx_conf_t *cf);
static char *ngx_http_lua_lowat_check(ngx_conf_t *cf, void *post, void *data);


static ngx_conf_post_t  ngx_http_lua_lowat_post =
    { ngx_http_lua_lowat_check };


static ngx_command_t ngx_http_lua_cmds[] = {

    { ngx_string("lua_shared_dict"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE2,
      ngx_http_lua_shared_dict,
      0,
      0,
      NULL },

#if (NGX_PCRE)
    { ngx_string("lua_regex_cache_max_entries"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_lua_main_conf_t, regex_cache_max_entries),
      NULL },
#endif

    { ngx_string("lua_package_cpath"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_package_cpath,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("lua_package_path"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_package_path,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("lua_code_cache"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_FLAG,
      ngx_http_lua_code_cache,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, enable_code_cache),
      NULL },

    { ngx_string("lua_need_request_body"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, force_read_body),
      NULL },

    { ngx_string("lua_transform_underscores_in_response_headers"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, transform_underscores_in_resp_headers),
      NULL },

     { ngx_string("lua_socket_log_errors"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, log_socket_errors),
      NULL },

    { ngx_string("init_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_init_by_lua,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      ngx_http_lua_init_by_inline },

    { ngx_string("init_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_init_by_lua,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      ngx_http_lua_init_by_file },

#if defined(NDK) && NDK
    /* set_by_lua $res <inline script> [$arg1 [$arg2 [...]]] */
    { ngx_string("set_by_lua"),
      NGX_HTTP_SRV_CONF|NGX_HTTP_SIF_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                       |NGX_CONF_2MORE,
      ngx_http_lua_set_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_filter_set_by_lua_inline },

    /* set_by_lua_file $res rel/or/abs/path/to/script [$arg1 [$arg2 [..]]] */
    { ngx_string("set_by_lua_file"),
      NGX_HTTP_SRV_CONF|NGX_HTTP_SIF_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                       |NGX_CONF_2MORE,
      ngx_http_lua_set_by_lua_file,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_filter_set_by_lua_file },
#endif

    /* rewrite_by_lua <inline script> */
    { ngx_string("rewrite_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_rewrite_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_rewrite_handler_inline },

    /* access_by_lua <inline script> */
    { ngx_string("access_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_access_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_access_handler_inline },

    /* content_by_lua <inline script> */
    { ngx_string("content_by_lua"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_content_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_content_handler_inline },

    /* log_by_lua <inline script> */
    { ngx_string("log_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_log_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_log_handler_inline },

    { ngx_string("rewrite_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_rewrite_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_rewrite_handler_file },

    { ngx_string("rewrite_by_lua_no_postpone"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_lua_main_conf_t, postponed_to_rewrite_phase_end),
      NULL },

    { ngx_string("access_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_access_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_access_handler_file },

    /* content_by_lua_file rel/or/abs/path/to/script */
    { ngx_string("content_by_lua_file"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_content_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_content_handler_file },

    { ngx_string("log_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_log_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_log_handler_file },

    /* header_filter_by_lua <inline script> */
    { ngx_string("header_filter_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_header_filter_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_header_filter_inline },

    { ngx_string("header_filter_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_header_filter_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_header_filter_file },

    { ngx_string("body_filter_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_body_filter_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_body_filter_inline },

    { ngx_string("body_filter_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_body_filter_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      ngx_http_lua_body_filter_file },

    { ngx_string("lua_socket_keepalive_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
          |NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, keepalive_timeout),
      NULL },

    { ngx_string("lua_socket_connect_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
          |NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, connect_timeout),
      NULL },

    { ngx_string("lua_socket_send_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
          |NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, send_timeout),
      NULL },

    { ngx_string("lua_socket_send_lowat"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
          |NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, send_lowat),
      &ngx_http_lua_lowat_post },

    { ngx_string("lua_socket_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
          |NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, buffer_size),
      NULL },

    { ngx_string("lua_socket_pool_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
                        |NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, pool_size),
      NULL },

    { ngx_string("lua_socket_read_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
          |NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, read_timeout),
      NULL },

    { ngx_string("lua_http10_buffering"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, http10_buffering),
      NULL },

    { ngx_string("lua_check_client_abort"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, check_client_abort),
      NULL },

    ngx_null_command
};


ngx_http_module_t ngx_http_lua_module_ctx = {
    NULL,                             /*  preconfiguration */
    ngx_http_lua_init,                /*  postconfiguration */

    ngx_http_lua_create_main_conf,    /*  create main configuration */
    ngx_http_lua_init_main_conf,      /*  init main configuration */

    NULL,                             /*  create server configuration */
    NULL,                             /*  merge server configuration */

    ngx_http_lua_create_loc_conf,     /*  create location configuration */
    ngx_http_lua_merge_loc_conf       /*  merge location configuration */
};


ngx_module_t ngx_http_lua_module = {
    NGX_MODULE_V1,
    &ngx_http_lua_module_ctx,   /*  module context */
    ngx_http_lua_cmds,          /*  module directives */
    NGX_HTTP_MODULE,            /*  module type */
    NULL,                       /*  init master */
    NULL,                       /*  init module */
    NULL,                       /*  init process */
    NULL,                       /*  init thread */
    NULL,                       /*  exit thread */
    NULL,                       /*  exit process */
    NULL,                       /*  exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_lua_init(ngx_conf_t *cf)
{
    ngx_int_t                   rc;
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;
    ngx_http_lua_main_conf_t   *lmcf;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    if (lmcf->requires_capture_filter) {
        rc = ngx_http_lua_capture_filter_init(cf);
        if (rc != NGX_OK) {
            return rc;
        }
    }

    if (lmcf->postponed_to_rewrite_phase_end == NGX_CONF_UNSET) {
        lmcf->postponed_to_rewrite_phase_end = 0;
    }

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    if (lmcf->requires_rewrite) {
        h = ngx_array_push(&cmcf->phases[NGX_HTTP_REWRITE_PHASE].handlers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        *h = ngx_http_lua_rewrite_handler;
    }

    if (lmcf->requires_access) {
        h = ngx_array_push(&cmcf->phases[NGX_HTTP_ACCESS_PHASE].handlers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        *h = ngx_http_lua_access_handler;
    }

    dd("requires log: %d", (int) lmcf->requires_log);

    if (lmcf->requires_log) {
        h = ngx_array_push(&cmcf->phases[NGX_HTTP_LOG_PHASE].handlers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        *h = ngx_http_lua_log_handler;
    }

    if (lmcf->requires_header_filter) {
        rc = ngx_http_lua_header_filter_init();
        if (rc != NGX_OK) {
            return rc;
        }
    }

    if (lmcf->requires_body_filter) {
        rc = ngx_http_lua_body_filter_init();
        if (rc != NGX_OK) {
            return rc;
        }
    }

    if (lmcf->lua == NULL) {
        dd("initializing lua vm");

        if (ngx_http_lua_init_vm(cf, lmcf) != NGX_CONF_OK) {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                               "failed to initialize Lua VM");
            return NGX_ERROR;
        }

        if (!lmcf->requires_shm && lmcf->init_handler) {
            if (lmcf->init_handler(cf->log, lmcf, lmcf->lua) != 0) {
                /* an error happened */
                return NGX_ERROR;
            }
        }

        dd("Lua VM initialized!");
    }

    return NGX_OK;
}


static char *
ngx_http_lua_lowat_check(ngx_conf_t *cf, void *post, void *data)
{
#if (NGX_FREEBSD)
    ssize_t *np = data;

    if ((u_long) *np >= ngx_freebsd_net_inet_tcp_sendspace) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "\"fastcgi_send_lowat\" must be less than %d "
                           "(sysctl net.inet.tcp.sendspace)",
                           ngx_freebsd_net_inet_tcp_sendspace);

        return NGX_CONF_ERROR;
    }

#elif !(NGX_HAVE_SO_SNDLOWAT)
    ssize_t *np = data;

    ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                       "\"fastcgi_send_lowat\" is not supported, ignored");

    *np = 0;

#endif

    return NGX_CONF_OK;
}


static void *
ngx_http_lua_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_main_conf_t));
    if (lmcf == NULL) {
        return NULL;
    }

    /* set by ngx_pcalloc:
     *      lmcf->lua = NULL;
     *      lmcf->lua_path = { 0, NULL };
     *      lmcf->lua_cpath = { 0, NULL };
     *      lmcf->regex_cache_entries = 0;
     *      lmcf->shm_zones = NULL;
     *      lmcf->init_handler = NULL;
     *      lmcf->init_src = { 0, NULL };
     *      lmcf->shm_zones_inited = 0;
     *      lmcf->preload_hooks = NULL;
     *      lmcf->requires_header_filter = 0;
     *      lmcf->requires_body_filter = 0;
     *      lmcf->requires_capture_filter = 0;
     *      lmcf->requires_rewrite = 0;
     *      lmcf->requires_access = 0;
     *      lmcf->requires_log = 0;
     *      lmcf->requires_shm = 0;
     */

    lmcf->pool = cf->pool;
#if (NGX_PCRE)
    lmcf->regex_cache_max_entries = NGX_CONF_UNSET;
#endif
    lmcf->postponed_to_rewrite_phase_end = NGX_CONF_UNSET;

    dd("nginx Lua module main config structure initialized!");

    return lmcf;
}


static char *
ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf)
{
#if (NGX_PCRE)
    ngx_http_lua_main_conf_t *lmcf = conf;

    if (lmcf->regex_cache_max_entries == NGX_CONF_UNSET) {
        lmcf->regex_cache_max_entries = 1024;
    }
#endif

    return NGX_CONF_OK;
}


static void *
ngx_http_lua_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_lua_loc_conf_t *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_loc_conf_t));
    if (conf == NULL) {
        return NGX_CONF_ERROR;
    }

    /* set by ngx_pcalloc:
     *      conf->access_src  = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->access_src_key = NULL
     *      conf->rewrite_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->rewrite_src_key = NULL
     *      conf->rewrite_handler = NULL;
     *
     *      conf->content_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->content_src_key = NULL
     *      conf->content_handler = NULL;
     *
     *      conf->log_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->log_src_key = NULL
     *      conf->log_handler = NULL;
     *
     *      conf->header_filter_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->header_filter_src_key = NULL
     *      conf->header_filter_handler = NULL;
     *
     *      conf->body_filter_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->body_filter_src_key = NULL
     *      conf->body_filter_handler = NULL;
     */

    conf->force_read_body    = NGX_CONF_UNSET;
    conf->enable_code_cache  = NGX_CONF_UNSET;
    conf->http10_buffering   = NGX_CONF_UNSET;
    conf->check_client_abort = NGX_CONF_UNSET;

    conf->keepalive_timeout = NGX_CONF_UNSET_MSEC;
    conf->connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->send_timeout = NGX_CONF_UNSET_MSEC;
    conf->read_timeout = NGX_CONF_UNSET_MSEC;
    conf->send_lowat = NGX_CONF_UNSET_SIZE;
    conf->buffer_size = NGX_CONF_UNSET_SIZE;
    conf->pool_size = NGX_CONF_UNSET_UINT;

    conf->transform_underscores_in_resp_headers = NGX_CONF_UNSET;
    conf->log_socket_errors = NGX_CONF_UNSET;


    return conf;
}


static char *
ngx_http_lua_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_lua_loc_conf_t *prev = parent;
    ngx_http_lua_loc_conf_t *conf = child;

    if (conf->rewrite_src.value.len == 0) {
        conf->rewrite_src = prev->rewrite_src;
        conf->rewrite_handler = prev->rewrite_handler;
        conf->rewrite_src_key = prev->rewrite_src_key;
    }

    if (conf->access_src.value.len == 0) {
        conf->access_src = prev->access_src;
        conf->access_handler = prev->access_handler;
        conf->access_src_key = prev->access_src_key;
    }

    if (conf->content_src.value.len == 0) {
        conf->content_src = prev->content_src;
        conf->content_handler = prev->content_handler;
        conf->content_src_key = prev->content_src_key;
    }

    if (conf->log_src.value.len == 0) {
        conf->log_src = prev->log_src;
        conf->log_handler = prev->log_handler;
        conf->log_src_key = prev->log_src_key;
    }

    if (conf->header_filter_src.value.len == 0) {
        conf->header_filter_src = prev->header_filter_src;
        conf->header_filter_handler = prev->header_filter_handler;
        conf->header_filter_src_key = prev->header_filter_src_key;
    }

    if (conf->body_filter_src.value.len == 0) {
        conf->body_filter_src = prev->body_filter_src;
        conf->body_filter_handler = prev->body_filter_handler;
        conf->body_filter_src_key = prev->body_filter_src_key;
    }

    ngx_conf_merge_value(conf->force_read_body, prev->force_read_body, 0);
    ngx_conf_merge_value(conf->enable_code_cache, prev->enable_code_cache, 1);
    ngx_conf_merge_value(conf->http10_buffering, prev->http10_buffering, 1);
    ngx_conf_merge_value(conf->check_client_abort, prev->check_client_abort, 0);

    ngx_conf_merge_msec_value(conf->keepalive_timeout,
                              prev->keepalive_timeout, 60000);

    ngx_conf_merge_msec_value(conf->connect_timeout,
                              prev->connect_timeout, 60000);

    ngx_conf_merge_msec_value(conf->send_timeout,
                              prev->send_timeout, 60000);

    ngx_conf_merge_msec_value(conf->read_timeout,
                              prev->read_timeout, 60000);

    ngx_conf_merge_size_value(conf->send_lowat,
                              prev->send_lowat, 0);

    ngx_conf_merge_size_value(conf->buffer_size,
                              prev->buffer_size,
                              (size_t) ngx_pagesize);

    ngx_conf_merge_uint_value(conf->pool_size, prev->pool_size, 30);

    ngx_conf_merge_value(conf->transform_underscores_in_resp_headers,
                         prev->transform_underscores_in_resp_headers, 1);

    ngx_conf_merge_value(conf->log_socket_errors, prev->log_socket_errors, 1);

    return NGX_CONF_OK;
}


static void
ngx_http_lua_cleanup_vm(void *data)
{
    lua_State *L = data;

    if (L != NULL) {
        lua_close(L);

        dd("Lua VM closed!");
    }
}


static char *
ngx_http_lua_init_vm(ngx_conf_t *cf, ngx_http_lua_main_conf_t *lmcf)
{
    ngx_pool_cleanup_t              *cln;
    ngx_http_lua_preload_hook_t     *hook;
    lua_State                       *L;
    ngx_uint_t                       i;

    /* add new cleanup handler to config mem pool */
    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {
        return NGX_CONF_ERROR;
    }

    /* create new Lua VM instance */
    lmcf->lua = ngx_http_lua_new_state(cf, lmcf);
    if (lmcf->lua == NULL) {
        return NGX_CONF_ERROR;
    }

    /* register cleanup handler for Lua VM */
    cln->handler = ngx_http_lua_cleanup_vm;
    cln->data = lmcf->lua;

    if (lmcf->preload_hooks) {

        /* register the 3rd-party module's preload hooks */

        L = lmcf->lua;

        lua_getglobal(L, "package");
        lua_getfield(L, -1, "preload");

        hook = lmcf->preload_hooks->elts;

        for (i = 0; i < lmcf->preload_hooks->nelts; i++) {

            ngx_http_lua_probe_register_preload_package(L, hook[i].package);

            lua_pushcfunction(L, hook[i].loader);
            lua_setfield(L, -2, (char *) hook[i].package);
        }

        lua_pop(L, 2);
    }

    return NGX_CONF_OK;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
