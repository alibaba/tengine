
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
#include "ngx_http_lua_server_rewriteby.h"
#include "ngx_http_lua_rewriteby.h"
#include "ngx_http_lua_accessby.h"
#include "ngx_http_lua_logby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_headerfilterby.h"
#include "ngx_http_lua_bodyfilterby.h"
#include "ngx_http_lua_initby.h"
#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_exitworkerby.h"
#include "ngx_http_lua_probe.h"
#include "ngx_http_lua_semaphore.h"
#include "ngx_http_lua_balancer.h"
#include "ngx_http_lua_ssl_client_helloby.h"
#include "ngx_http_lua_ssl_certby.h"
#include "ngx_http_lua_ssl_session_storeby.h"
#include "ngx_http_lua_ssl_session_fetchby.h"
#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_headers_out.h"
#include "ngx_http_lua_pipe.h"


static void *ngx_http_lua_create_main_conf(ngx_conf_t *cf);
static char *ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf);
static void *ngx_http_lua_create_srv_conf(ngx_conf_t *cf);
static char *ngx_http_lua_merge_srv_conf(ngx_conf_t *cf, void *parent,
    void *child);
static void *ngx_http_lua_create_loc_conf(ngx_conf_t *cf);

static char *ngx_http_lua_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static ngx_int_t ngx_http_lua_init(ngx_conf_t *cf);
static char *ngx_http_lua_lowat_check(ngx_conf_t *cf, void *post, void *data);
#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_lua_set_ssl(ngx_conf_t *cf,
    ngx_http_lua_loc_conf_t *llcf);
#if (nginx_version >= 1019004)
static char *ngx_http_lua_ssl_conf_command_check(ngx_conf_t *cf, void *post,
    void *data);
#endif
#endif
static char *ngx_http_lua_malloc_trim(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


static ngx_conf_post_t  ngx_http_lua_lowat_post =
    { ngx_http_lua_lowat_check };


static volatile ngx_cycle_t  *ngx_http_lua_prev_cycle = NULL;


#if (NGX_HTTP_SSL)

static ngx_conf_bitmask_t  ngx_http_lua_ssl_protocols[] = {
    { ngx_string("SSLv2"), NGX_SSL_SSLv2 },
    { ngx_string("SSLv3"), NGX_SSL_SSLv3 },
    { ngx_string("TLSv1"), NGX_SSL_TLSv1 },
    { ngx_string("TLSv1.1"), NGX_SSL_TLSv1_1 },
    { ngx_string("TLSv1.2"), NGX_SSL_TLSv1_2 },
#ifdef NGX_SSL_TLSv1_3
    { ngx_string("TLSv1.3"), NGX_SSL_TLSv1_3 },
#endif
    { ngx_null_string, 0 }
};

#if (nginx_version >= 1019004)
static ngx_conf_post_t  ngx_http_lua_ssl_conf_command_post =
    { ngx_http_lua_ssl_conf_command_check };
#endif

#endif


static ngx_command_t ngx_http_lua_cmds[] = {

    { ngx_string("lua_load_resty_core"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_FLAG,
      ngx_http_lua_load_resty_core,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("lua_thread_cache_max_entries"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_lua_main_conf_t, lua_thread_cache_max_entries),
      NULL },

    { ngx_string("lua_max_running_timers"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_lua_main_conf_t, max_running_timers),
      NULL },

    { ngx_string("lua_max_pending_timers"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_lua_main_conf_t, max_pending_timers),
      NULL },

    { ngx_string("lua_shared_dict"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE2,
      ngx_http_lua_shared_dict,
      0,
      0,
      NULL },

    { ngx_string("lua_capture_error_log"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_capture_error_log,
      0,
      0,
      NULL },

    { ngx_string("lua_sa_restart"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_lua_main_conf_t, set_sa_restart),
      NULL },

    { ngx_string("lua_regex_cache_max_entries"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_regex_cache_max_entries,
      NGX_HTTP_MAIN_CONF_OFFSET,
#if (NGX_PCRE)
      offsetof(ngx_http_lua_main_conf_t, regex_cache_max_entries),
#else
      0,
#endif
      NULL },

    { ngx_string("lua_regex_match_limit"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_regex_match_limit,
      NGX_HTTP_MAIN_CONF_OFFSET,
#if (NGX_PCRE)
      offsetof(ngx_http_lua_main_conf_t, regex_match_limit),
#else
      0,
#endif
      NULL },

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

    { ngx_string("init_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_init_by_lua_block,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_init_by_inline },

    { ngx_string("init_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_init_by_lua,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_init_by_inline },

    { ngx_string("init_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_init_by_lua,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_init_by_file },

    { ngx_string("init_worker_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_init_worker_by_lua_block,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_init_worker_by_inline },

    { ngx_string("init_worker_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_init_worker_by_lua,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_init_worker_by_inline },

    { ngx_string("init_worker_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_init_worker_by_lua,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_init_worker_by_file },

    { ngx_string("exit_worker_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_exit_worker_by_lua_block,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_exit_worker_by_inline },

    { ngx_string("exit_worker_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_exit_worker_by_lua,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_exit_worker_by_file },

#if defined(NDK) && NDK
    /* set_by_lua_block $res { inline Lua code } */
    { ngx_string("set_by_lua_block"),
      NGX_HTTP_SRV_CONF|NGX_HTTP_SIF_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                       |NGX_CONF_TAKE1|NGX_CONF_BLOCK,
      ngx_http_lua_set_by_lua_block,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_filter_set_by_lua_inline },

    /* set_by_lua $res <inline script> [$arg1 [$arg2 [...]]] */
    { ngx_string("set_by_lua"),
      NGX_HTTP_SRV_CONF|NGX_HTTP_SIF_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                       |NGX_CONF_2MORE,
      ngx_http_lua_set_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_filter_set_by_lua_inline },

    /* set_by_lua_file $res rel/or/abs/path/to/script [$arg1 [$arg2 [..]]] */
    { ngx_string("set_by_lua_file"),
      NGX_HTTP_SRV_CONF|NGX_HTTP_SIF_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                       |NGX_CONF_2MORE,
      ngx_http_lua_set_by_lua_file,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_filter_set_by_lua_file },
#endif

    /* server_rewrite_by_lua_block { <inline script> } */
    { ngx_string("server_rewrite_by_lua_block"),
        NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
        ngx_http_lua_server_rewrite_by_lua_block,
        NGX_HTTP_SRV_CONF_OFFSET,
        0,
        (void *) ngx_http_lua_server_rewrite_handler_inline },

    /* server_rewrite_by_lua_file filename; */
    { ngx_string("server_rewrite_by_lua_file"),
        NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
        ngx_http_lua_server_rewrite_by_lua,
        NGX_HTTP_SRV_CONF_OFFSET,
        0,
        (void *) ngx_http_lua_server_rewrite_handler_file },

    /* rewrite_by_lua "<inline script>" */
    { ngx_string("rewrite_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_rewrite_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_rewrite_handler_inline },

    /* rewrite_by_lua_block { <inline script> } */
    { ngx_string("rewrite_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_rewrite_by_lua_block,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_rewrite_handler_inline },

    /* access_by_lua "<inline script>" */
    { ngx_string("access_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_access_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_access_handler_inline },

    /* access_by_lua_block { <inline script> } */
    { ngx_string("access_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_access_by_lua_block,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_access_handler_inline },

    /* content_by_lua "<inline script>" */
    { ngx_string("content_by_lua"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_content_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_content_handler_inline },

    /* content_by_lua_block { <inline script> } */
    { ngx_string("content_by_lua_block"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_content_by_lua_block,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_content_handler_inline },

    /* log_by_lua <inline script> */
    { ngx_string("log_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_log_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_log_handler_inline },

    /* log_by_lua_block { <inline script> } */
    { ngx_string("log_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_log_by_lua_block,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_log_handler_inline },

    { ngx_string("rewrite_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_rewrite_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_rewrite_handler_file },

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
      (void *) ngx_http_lua_access_handler_file },

    { ngx_string("access_by_lua_no_postpone"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_lua_main_conf_t, postponed_to_access_phase_end),
      NULL },

    /* content_by_lua_file rel/or/abs/path/to/script */
    { ngx_string("content_by_lua_file"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_content_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_content_handler_file },

    { ngx_string("log_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_log_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_log_handler_file },

    /* header_filter_by_lua <inline script> */
    { ngx_string("header_filter_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_header_filter_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_header_filter_inline },

    /* header_filter_by_lua_block { <inline script> } */
    { ngx_string("header_filter_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_header_filter_by_lua_block,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_header_filter_inline },

    { ngx_string("header_filter_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_header_filter_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_header_filter_file },

    { ngx_string("body_filter_by_lua"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_body_filter_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_body_filter_inline },

    /* body_filter_by_lua_block { <inline script> } */
    { ngx_string("body_filter_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_body_filter_by_lua_block,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_body_filter_inline },

    { ngx_string("body_filter_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_TAKE1,
      ngx_http_lua_body_filter_by_lua,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_body_filter_file },

    { ngx_string("balancer_by_lua_block"),
      NGX_HTTP_UPS_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_balancer_by_lua_block,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_balancer_handler_inline },

    { ngx_string("balancer_by_lua_file"),
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_balancer_by_lua,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_balancer_handler_file },

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

    { ngx_string("lua_use_default_type"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, use_default_type),
      NULL },

#if (NGX_HTTP_SSL)

    { ngx_string("lua_ssl_protocols"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, ssl_protocols),
      &ngx_http_lua_ssl_protocols },

    { ngx_string("lua_ssl_ciphers"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, ssl_ciphers),
      NULL },

    { ngx_string("ssl_client_hello_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_ssl_client_hello_by_lua_block,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_ssl_client_hello_handler_inline },

    { ngx_string("ssl_client_hello_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_ssl_client_hello_by_lua,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_ssl_client_hello_handler_file },

    { ngx_string("ssl_certificate_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_ssl_cert_by_lua_block,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_ssl_cert_handler_inline },

    { ngx_string("ssl_certificate_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_ssl_cert_by_lua,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_ssl_cert_handler_file },

    { ngx_string("ssl_session_store_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_ssl_sess_store_by_lua_block,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_ssl_sess_store_handler_inline },

    { ngx_string("ssl_session_store_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_ssl_sess_store_by_lua,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_ssl_sess_store_handler_file },

    { ngx_string("ssl_session_fetch_by_lua_block"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_lua_ssl_sess_fetch_by_lua_block,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_ssl_sess_fetch_handler_inline },

    { ngx_string("ssl_session_fetch_by_lua_file"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_ssl_sess_fetch_by_lua,
      NGX_HTTP_SRV_CONF_OFFSET,
      0,
      (void *) ngx_http_lua_ssl_sess_fetch_handler_file },

    { ngx_string("lua_ssl_verify_depth"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, ssl_verify_depth),
      NULL },

    { ngx_string("lua_ssl_trusted_certificate"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, ssl_trusted_certificate),
      NULL },

    { ngx_string("lua_ssl_crl"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, ssl_crl),
      NULL },

#if (nginx_version >= 1019004)
    { ngx_string("lua_ssl_conf_command"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_conf_set_keyval_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_loc_conf_t, ssl_conf_commands),
      &ngx_http_lua_ssl_conf_command_post },
#endif
#endif  /* NGX_HTTP_SSL */

     { ngx_string("lua_malloc_trim"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_http_lua_malloc_trim,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("lua_worker_thread_vm_pool_size"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_http_lua_main_conf_t, worker_thread_vm_pool_size),
      NULL },

    ngx_null_command
};


static ngx_http_module_t ngx_http_lua_module_ctx = {
    NULL,                             /*  preconfiguration */
    ngx_http_lua_init,                /*  postconfiguration */

    ngx_http_lua_create_main_conf,    /*  create main configuration */
    ngx_http_lua_init_main_conf,      /*  init main configuration */

    ngx_http_lua_create_srv_conf,     /*  create server configuration */
    ngx_http_lua_merge_srv_conf,      /*  merge server configuration */

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
    ngx_http_lua_init_worker,   /*  init process */
    NULL,                       /*  init thread */
    NULL,                       /*  exit thread */
    ngx_http_lua_exit_worker,   /*  exit process */
    NULL,                       /*  exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_lua_init(ngx_conf_t *cf)
{
    int                         multi_http_blocks;
    ngx_int_t                   rc;
    ngx_array_t                *arr;
    ngx_http_handler_pt        *h;
    volatile ngx_cycle_t       *saved_cycle;
    ngx_http_core_main_conf_t  *cmcf;
    ngx_http_lua_main_conf_t   *lmcf;
    ngx_pool_cleanup_t         *cln;
    ngx_str_t                   name = ngx_string("host");

    if (ngx_process == NGX_PROCESS_SIGNALLER || ngx_test_config) {
        return NGX_OK;
    }

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->host_var_index = ngx_http_get_variable_index(cf, &name);
    if (lmcf->host_var_index == NGX_ERROR) {
        return NGX_ERROR;
    }

    if (ngx_http_lua_prev_cycle != ngx_cycle) {
        ngx_http_lua_prev_cycle = ngx_cycle;
        multi_http_blocks = 0;

    } else {
        multi_http_blocks = 1;
    }

    if (multi_http_blocks || lmcf->requires_capture_filter) {
        rc = ngx_http_lua_capture_filter_init(cf);
        if (rc != NGX_OK) {
            return rc;
        }
    }

    if (lmcf->postponed_to_rewrite_phase_end == NGX_CONF_UNSET) {
        lmcf->postponed_to_rewrite_phase_end = 0;
    }

    if (lmcf->postponed_to_access_phase_end == NGX_CONF_UNSET) {
        lmcf->postponed_to_access_phase_end = 0;
    }

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    if (lmcf->requires_server_rewrite) {
        h = ngx_array_push(
          &cmcf->phases[NGX_HTTP_SERVER_REWRITE_PHASE].handlers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        *h = ngx_http_lua_server_rewrite_handler;
    }

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
        arr = &cmcf->phases[NGX_HTTP_LOG_PHASE].handlers;
        h = ngx_array_push(arr);
        if (h == NULL) {
            return NGX_ERROR;
        }

        if (arr->nelts > 1) {
            h = arr->elts;
            ngx_memmove(&h[1], h,
                        (arr->nelts - 1) * sizeof(ngx_http_handler_pt));
        }

        *h = ngx_http_lua_log_handler;
    }

    if (multi_http_blocks || lmcf->requires_header_filter) {
        rc = ngx_http_lua_header_filter_init();
        if (rc != NGX_OK) {
            return rc;
        }
    }

    if (multi_http_blocks || lmcf->requires_body_filter) {
        rc = ngx_http_lua_body_filter_init();
        if (rc != NGX_OK) {
            return rc;
        }
    }

    /* add the cleanup of semaphores after the lua_close */
    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {
        return NGX_ERROR;
    }

    cln->data = lmcf;
    cln->handler = ngx_http_lua_sema_mm_cleanup;

#ifdef HAVE_NGX_LUA_PIPE
    ngx_http_lua_pipe_init();
#endif

#if (nginx_version >= 1011011)
    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {
        return NGX_ERROR;
    }

    cln->data = lmcf;
    cln->handler = ngx_http_lua_ngx_raw_header_cleanup;
#endif

    if (lmcf->lua == NULL) {
        dd("initializing lua vm");

#ifndef OPENRESTY_LUAJIT
        if (ngx_process != NGX_PROCESS_SIGNALLER && !ngx_test_config) {
            ngx_log_error(NGX_LOG_ALERT, cf->log, 0,
                          "detected a LuaJIT version which is not OpenResty's"
                          "; many optimizations will be disabled and "
                          "performance will be compromised (see "
                          "https://github.com/openresty/luajit2 for "
                          "OpenResty's LuaJIT or, even better, consider using "
                          "the OpenResty releases from https://openresty.org/"
                          "en/download.html)");
        }
#else
#   if !defined(HAVE_LUA_RESETTHREAD)
        ngx_log_error(NGX_LOG_ALERT, cf->log, 0,
                      "detected an old version of OpenResty's LuaJIT missing "
                      "the lua_resetthread API and thus the "
                      "performance will be compromised; please upgrade to the "
                      "latest version of OpenResty's LuaJIT: "
                      "https://github.com/openresty/luajit2");
#   endif
#   if !defined(HAVE_LUA_EXDATA2)
        ngx_log_error(NGX_LOG_ALERT, cf->log, 0,
                      "detected an old version of OpenResty's LuaJIT missing "
                      "the exdata2 API and thus the "
                      "performance will be compromised; please upgrade to the "
                      "latest version of OpenResty's LuaJIT: "
                      "https://github.com/openresty/luajit2");
#   endif
#endif

        ngx_http_lua_content_length_hash =
                                  ngx_http_lua_hash_literal("content-length");
        ngx_http_lua_location_hash = ngx_http_lua_hash_literal("location");

        rc = ngx_http_lua_init_vm(&lmcf->lua, NULL, cf->cycle, cf->pool,
                                  lmcf, cf->log, NULL);
        if (rc != NGX_OK) {
            if (rc == NGX_DECLINED) {
                ngx_http_lua_assert(lmcf->lua != NULL);

                ngx_conf_log_error(NGX_LOG_ALERT, cf, 0,
                                   "failed to load the 'resty.core' module "
                                   "(https://github.com/openresty/lua-resty"
                                   "-core); ensure you are using an OpenResty "
                                   "release from https://openresty.org/en/"
                                   "download.html (reason: %s)",
                                   lua_tostring(lmcf->lua, -1));

            } else {
                /* rc == NGX_ERROR */
                ngx_conf_log_error(NGX_LOG_ALERT, cf, 0,
                                   "failed to initialize Lua VM");
            }

            return NGX_ERROR;
        }

        /* rc == NGX_OK */

        ngx_http_lua_assert(lmcf->lua != NULL);

        if (!lmcf->requires_shm && lmcf->init_handler) {
            saved_cycle = ngx_cycle;
            ngx_cycle = cf->cycle;

            rc = lmcf->init_handler(cf->log, lmcf, lmcf->lua);

            ngx_cycle = saved_cycle;

            if (rc != NGX_OK) {
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
                           "\"lua_send_lowat\" must be less than %d "
                           "(sysctl net.inet.tcp.sendspace)",
                           ngx_freebsd_net_inet_tcp_sendspace);

        return NGX_CONF_ERROR;
    }

#elif !(NGX_HAVE_SO_SNDLOWAT)
    ssize_t *np = data;

    ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                       "\"lua_send_lowat\" is not supported, ignored");

    *np = 0;

#endif

    return NGX_CONF_OK;
}


static void *
ngx_http_lua_create_main_conf(ngx_conf_t *cf)
{
    ngx_int_t       rc;

    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_main_conf_t));
    if (lmcf == NULL) {
        return NULL;
    }

    /* set by ngx_pcalloc:
     *      lmcf->lua = NULL;
     *      lmcf->lua_path = { 0, NULL };
     *      lmcf->lua_cpath = { 0, NULL };
     *      lmcf->pending_timers = 0;
     *      lmcf->running_timers = 0;
     *      lmcf->watcher = NULL;
     *      lmcf->regex_cache_entries = 0;
     *      lmcf->jit_stack = NULL;
     *      lmcf->shm_zones = NULL;
     *      lmcf->init_handler = NULL;
     *      lmcf->init_src = { 0, NULL };
     *      lmcf->shm_zones_inited = 0;
     *      lmcf->shdict_zones = NULL;
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
    lmcf->max_pending_timers = NGX_CONF_UNSET;
    lmcf->max_running_timers = NGX_CONF_UNSET;
    lmcf->lua_thread_cache_max_entries = NGX_CONF_UNSET;
#if (NGX_PCRE)
    lmcf->regex_cache_max_entries = NGX_CONF_UNSET;
    lmcf->regex_match_limit = NGX_CONF_UNSET;
#endif
    lmcf->postponed_to_rewrite_phase_end = NGX_CONF_UNSET;
    lmcf->postponed_to_access_phase_end = NGX_CONF_UNSET;

    lmcf->set_sa_restart = NGX_CONF_UNSET;

#if (NGX_HTTP_LUA_HAVE_MALLOC_TRIM)
    lmcf->malloc_trim_cycle = NGX_CONF_UNSET_UINT;
#endif

    rc = ngx_http_lua_sema_mm_init(cf, lmcf);
    if (rc != NGX_OK) {
        return NULL;
    }

    lmcf->worker_thread_vm_pool_size = NGX_CONF_UNSET;

    dd("nginx Lua module main config structure initialized!");

    return lmcf;
}


static char *
ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf)
{
#ifdef HAVE_LUA_RESETTHREAD
    ngx_int_t                    i, n;
    ngx_http_lua_thread_ref_t   *trefs;
#endif

    ngx_http_lua_main_conf_t     *lmcf = conf;

    if (lmcf->lua_thread_cache_max_entries < 0) {
        lmcf->lua_thread_cache_max_entries = 1024;

#ifndef HAVE_LUA_RESETTHREAD

    } else if (lmcf->lua_thread_cache_max_entries > 0) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "lua_thread_cache_max_entries has no effect when "
                      "LuaJIT has no support for the lua_resetthread API "
                      "(you forgot to use OpenResty's LuaJIT?)");
        return NGX_CONF_ERROR;

#endif
    }

#if (NGX_PCRE)
    if (lmcf->regex_cache_max_entries == NGX_CONF_UNSET) {
        lmcf->regex_cache_max_entries = 1024;
    }

    if (lmcf->regex_match_limit == NGX_CONF_UNSET) {
        lmcf->regex_match_limit = 0;
    }
#endif

    if (lmcf->max_pending_timers == NGX_CONF_UNSET) {
        lmcf->max_pending_timers = 1024;
    }

    if (lmcf->max_running_timers == NGX_CONF_UNSET) {
        lmcf->max_running_timers = 256;
    }

#if (NGX_HTTP_LUA_HAVE_SA_RESTART)
    if (lmcf->set_sa_restart == NGX_CONF_UNSET) {
        lmcf->set_sa_restart = 1;
    }
#endif

#if (NGX_HTTP_LUA_HAVE_MALLOC_TRIM)
    if (lmcf->malloc_trim_cycle == NGX_CONF_UNSET_UINT) {
        lmcf->malloc_trim_cycle = 1000;  /* number of reqs */
    }
#endif

    lmcf->cycle = cf->cycle;

    ngx_queue_init(&lmcf->free_lua_threads);
    ngx_queue_init(&lmcf->cached_lua_threads);

#ifdef HAVE_LUA_RESETTHREAD
    n = lmcf->lua_thread_cache_max_entries;

    if (n > 0) {
        trefs = ngx_palloc(cf->pool, n * sizeof(ngx_http_lua_thread_ref_t));
        if (trefs == NULL) {
            return NGX_CONF_ERROR;
        }

        for (i = 0; i < n; i++) {
            trefs[i].ref = LUA_NOREF;
            trefs[i].co = NULL;
            ngx_queue_insert_head(&lmcf->free_lua_threads, &trefs[i].queue);
        }
    }
#endif

    if (lmcf->worker_thread_vm_pool_size == NGX_CONF_UNSET_UINT) {
        lmcf->worker_thread_vm_pool_size = 100;
    }

    if (ngx_http_lua_init_builtin_headers_out(cf, lmcf) != NGX_OK) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "init header out error");

        return NGX_CONF_ERROR;
    }

    dd("init built in headers out hash size: %ld",
       lmcf->builtin_headers_out.size);

    return NGX_CONF_OK;
}


static void *
ngx_http_lua_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_lua_srv_conf_t     *lscf;

    lscf = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_srv_conf_t));
    if (lscf == NULL) {
        return NULL;
    }

    /* set by ngx_pcalloc:
     *      lscf->srv.ssl_client_hello_handler = NULL;
     *      lscf->srv.ssl_client_hello_src = { 0, NULL };
     *      lscf->srv.ssl_client_hello_chunkname = NULL;
     *      lscf->srv.ssl_client_hello_src_key = NULL;
     *
     *      lscf->srv.ssl_cert_handler = NULL;
     *      lscf->srv.ssl_cert_src = { 0, NULL };
     *      lscf->srv.ssl_cert_chunkname = NULL;
     *      lscf->srv.ssl_cert_src_key = NULL;
     *
     *      lscf->srv.ssl_session_store_handler = NULL;
     *      lscf->srv.ssl_session_store_src = { 0, NULL };
     *      lscf->srv.ssl_session_store_chunkname = NULL;
     *      lscf->srv.ssl_session_store_src_key = NULL;
     *
     *      lscf->srv.ssl_session_fetch_handler = NULL;
     *      lscf->srv.ssl_session_fetch_src = { 0, NULL };
     *      lscf->srv.ssl_session_fetch_chunkname = NULL;
     *      lscf->srv.ssl_session_fetch_src_key = NULL;
     *
     *      lscf->balancer.handler = NULL;
     *      lscf->balancer.src = { 0, NULL };
     *      lscf->balancer.chunkname = NULL;
     *      lscf->balancer.src_key = NULL;
     */

#if (NGX_HTTP_SSL)
    lscf->srv.ssl_client_hello_src_ref = LUA_REFNIL;
    lscf->srv.ssl_cert_src_ref = LUA_REFNIL;
    lscf->srv.ssl_sess_store_src_ref = LUA_REFNIL;
    lscf->srv.ssl_sess_fetch_src_ref = LUA_REFNIL;
#endif

    lscf->balancer.src_ref = LUA_REFNIL;

    return lscf;
}


static char *
ngx_http_lua_merge_srv_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_lua_srv_conf_t *conf = child;
    ngx_http_lua_srv_conf_t *prev = parent;

#if (NGX_HTTP_SSL)

    ngx_http_ssl_srv_conf_t *sscf;

    dd("merge srv conf");

    if (conf->srv.ssl_client_hello_src.len == 0) {
        conf->srv.ssl_client_hello_src = prev->srv.ssl_client_hello_src;
        conf->srv.ssl_client_hello_src_ref = prev->srv.ssl_client_hello_src_ref;
        conf->srv.ssl_client_hello_src_key = prev->srv.ssl_client_hello_src_key;
        conf->srv.ssl_client_hello_handler = prev->srv.ssl_client_hello_handler;
        conf->srv.ssl_client_hello_chunkname
            = prev->srv.ssl_client_hello_chunkname;
    }

    if (conf->srv.ssl_client_hello_src.len) {
        sscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_ssl_module);
        if (sscf == NULL || sscf->ssl.ctx == NULL) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "no ssl configured for the server");

            return NGX_CONF_ERROR;
        }
#ifdef LIBRESSL_VERSION_NUMBER
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "LibreSSL does not support by ssl_client_hello_by_lua*");
        return NGX_CONF_ERROR;

#else

#ifdef SSL_ERROR_WANT_CLIENT_HELLO_CB

        SSL_CTX_set_client_hello_cb(sscf->ssl.ctx,
                                    ngx_http_lua_ssl_client_hello_handler,
                                    NULL);

#else

        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "OpenSSL too old to support "
                      "ssl_client_hello_by_lua*");
        return NGX_CONF_ERROR;

#endif
#endif
    }

    if (conf->srv.ssl_cert_src.len == 0) {
        conf->srv.ssl_cert_src = prev->srv.ssl_cert_src;
        conf->srv.ssl_cert_src_ref = prev->srv.ssl_cert_src_ref;
        conf->srv.ssl_cert_src_key = prev->srv.ssl_cert_src_key;
        conf->srv.ssl_cert_handler = prev->srv.ssl_cert_handler;
        conf->srv.ssl_cert_chunkname = prev->srv.ssl_cert_chunkname;
    }

    if (conf->srv.ssl_cert_src.len) {
        sscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_ssl_module);
        if (sscf == NULL || sscf->ssl.ctx == NULL) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "no ssl configured for the server");

            return NGX_CONF_ERROR;
        }

#ifdef LIBRESSL_VERSION_NUMBER

        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "LibreSSL is not supported by ssl_certificate_by_lua*");
        return NGX_CONF_ERROR;

#else

#   if OPENSSL_VERSION_NUMBER >= 0x1000205fL

        SSL_CTX_set_cert_cb(sscf->ssl.ctx, ngx_http_lua_ssl_cert_handler, NULL);

#   else

        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "OpenSSL too old to support ssl_certificate_by_lua*");
        return NGX_CONF_ERROR;

#   endif

#endif
    }

    if (conf->srv.ssl_sess_store_src.len == 0) {
        conf->srv.ssl_sess_store_src = prev->srv.ssl_sess_store_src;
        conf->srv.ssl_sess_store_src_ref = prev->srv.ssl_sess_store_src_ref;
        conf->srv.ssl_sess_store_src_key = prev->srv.ssl_sess_store_src_key;
        conf->srv.ssl_sess_store_handler = prev->srv.ssl_sess_store_handler;
        conf->srv.ssl_sess_store_chunkname = prev->srv.ssl_sess_store_chunkname;
    }

    if (conf->srv.ssl_sess_store_src.len) {
        sscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_ssl_module);
        if (sscf && sscf->ssl.ctx) {
#ifdef LIBRESSL_VERSION_NUMBER
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "LibreSSL is not supported by "
                          "ssl_session_store_by_lua*");

            return NGX_CONF_ERROR;
#else
            SSL_CTX_sess_set_new_cb(sscf->ssl.ctx,
                                    ngx_http_lua_ssl_sess_store_handler);
#endif
        }
    }

    if (conf->srv.ssl_sess_fetch_src.len == 0) {
        conf->srv.ssl_sess_fetch_src = prev->srv.ssl_sess_fetch_src;
        conf->srv.ssl_sess_fetch_src_ref = prev->srv.ssl_sess_fetch_src_ref;
        conf->srv.ssl_sess_fetch_src_key = prev->srv.ssl_sess_fetch_src_key;
        conf->srv.ssl_sess_fetch_handler = prev->srv.ssl_sess_fetch_handler;
        conf->srv.ssl_sess_fetch_chunkname = prev->srv.ssl_sess_fetch_chunkname;
    }

    if (conf->srv.ssl_sess_fetch_src.len) {
        sscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_ssl_module);
        if (sscf && sscf->ssl.ctx) {
#ifdef LIBRESSL_VERSION_NUMBER
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                          "LibreSSL is not supported by "
                          "ssl_session_fetch_by_lua*");

            return NGX_CONF_ERROR;
#else
            SSL_CTX_sess_set_get_cb(sscf->ssl.ctx,
                                    ngx_http_lua_ssl_sess_fetch_handler);
#endif
        }
    }

#endif  /* NGX_HTTP_SSL */

    if (conf->srv.server_rewrite_src.value.len == 0) {
        conf->srv.server_rewrite_src = prev->srv.server_rewrite_src;
        conf->srv.server_rewrite_src_ref = prev->srv.server_rewrite_src_ref;
        conf->srv.server_rewrite_src_key = prev->srv.server_rewrite_src_key;
        conf->srv.server_rewrite_handler = prev->srv.server_rewrite_handler;
        conf->srv.server_rewrite_chunkname
            = prev->srv.server_rewrite_chunkname;
    }

    return NGX_CONF_OK;
}


static void *
ngx_http_lua_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_lua_loc_conf_t *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /* set by ngx_pcalloc:
     *      conf->access_src  = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->access_src_key = NULL
     *      conf->rewrite_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->rewrite_src_key = NULL;
     *      conf->rewrite_handler = NULL;
     *
     *      conf->content_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->content_src_key = NULL;
     *      conf->content_handler = NULL;
     *
     *      conf->log_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->log_src_key = NULL;
     *      conf->log_handler = NULL;
     *
     *      conf->header_filter_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->header_filter_src_key = NULL;
     *      conf->header_filter_handler = NULL;
     *
     *      conf->body_filter_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->body_filter_src_key = NULL;
     *      conf->body_filter_handler = NULL;
     *
     *      conf->ssl = 0;
     *      conf->ssl_protocols = 0;
     *      conf->ssl_ciphers = { 0, NULL };
     *      conf->ssl_trusted_certificate = { 0, NULL };
     *      conf->ssl_crl = { 0, NULL };
     */

    conf->force_read_body    = NGX_CONF_UNSET;
    conf->enable_code_cache  = NGX_CONF_UNSET;
    conf->http10_buffering   = NGX_CONF_UNSET;
    conf->check_client_abort = NGX_CONF_UNSET;
    conf->use_default_type   = NGX_CONF_UNSET;

    conf->keepalive_timeout = NGX_CONF_UNSET_MSEC;
    conf->connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->send_timeout = NGX_CONF_UNSET_MSEC;
    conf->read_timeout = NGX_CONF_UNSET_MSEC;
    conf->send_lowat = NGX_CONF_UNSET_SIZE;
    conf->buffer_size = NGX_CONF_UNSET_SIZE;
    conf->pool_size = NGX_CONF_UNSET_UINT;

    conf->transform_underscores_in_resp_headers = NGX_CONF_UNSET;
    conf->log_socket_errors = NGX_CONF_UNSET;

    conf->rewrite_src_ref = LUA_REFNIL;
    conf->access_src_ref = LUA_REFNIL;
    conf->content_src_ref = LUA_REFNIL;
    conf->header_filter_src_ref = LUA_REFNIL;
    conf->body_filter_src_ref = LUA_REFNIL;
    conf->log_src_ref = LUA_REFNIL;

#if (NGX_HTTP_SSL)
    conf->ssl_verify_depth = NGX_CONF_UNSET_UINT;
#if (nginx_version >= 1019004)
    conf->ssl_conf_commands = NGX_CONF_UNSET_PTR;
#endif
#endif

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
        conf->rewrite_src_ref = prev->rewrite_src_ref;
        conf->rewrite_src_key = prev->rewrite_src_key;
        conf->rewrite_chunkname = prev->rewrite_chunkname;
    }

    if (conf->access_src.value.len == 0) {
        conf->access_src = prev->access_src;
        conf->access_handler = prev->access_handler;
        conf->access_src_ref = prev->access_src_ref;
        conf->access_src_key = prev->access_src_key;
        conf->access_chunkname = prev->access_chunkname;
    }

    if (conf->content_src.value.len == 0) {
        conf->content_src = prev->content_src;
        conf->content_handler = prev->content_handler;
        conf->content_src_ref = prev->content_src_ref;
        conf->content_src_key = prev->content_src_key;
        conf->content_chunkname = prev->content_chunkname;
    }

    if (conf->log_src.value.len == 0) {
        conf->log_src = prev->log_src;
        conf->log_handler = prev->log_handler;
        conf->log_src_ref = prev->log_src_ref;
        conf->log_src_key = prev->log_src_key;
        conf->log_chunkname = prev->log_chunkname;
    }

    if (conf->header_filter_src.value.len == 0) {
        conf->header_filter_src = prev->header_filter_src;
        conf->header_filter_handler = prev->header_filter_handler;
        conf->header_filter_src_ref = prev->header_filter_src_ref;
        conf->header_filter_src_key = prev->header_filter_src_key;
        conf->header_filter_chunkname = prev->header_filter_chunkname;
    }

    if (conf->body_filter_src.value.len == 0) {
        conf->body_filter_src = prev->body_filter_src;
        conf->body_filter_handler = prev->body_filter_handler;
        conf->body_filter_src_ref = prev->body_filter_src_ref;
        conf->body_filter_src_key = prev->body_filter_src_key;
        conf->body_filter_chunkname = prev->body_filter_chunkname;
    }

#if (NGX_HTTP_SSL)

    ngx_conf_merge_bitmask_value(conf->ssl_protocols, prev->ssl_protocols,
                                 (NGX_CONF_BITMASK_SET|NGX_SSL_SSLv3
                                  |NGX_SSL_TLSv1|NGX_SSL_TLSv1_1
                                  |NGX_SSL_TLSv1_2));

    ngx_conf_merge_str_value(conf->ssl_ciphers, prev->ssl_ciphers,
                             "DEFAULT");

    ngx_conf_merge_uint_value(conf->ssl_verify_depth,
                              prev->ssl_verify_depth, 1);
    ngx_conf_merge_str_value(conf->ssl_trusted_certificate,
                             prev->ssl_trusted_certificate, "");
    ngx_conf_merge_str_value(conf->ssl_crl, prev->ssl_crl, "");

#if (nginx_version >= 1019004)
    ngx_conf_merge_ptr_value(conf->ssl_conf_commands, prev->ssl_conf_commands,
                             NULL);
#endif

    if (ngx_http_lua_set_ssl(cf, conf) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

#endif

    ngx_conf_merge_value(conf->force_read_body, prev->force_read_body, 0);
    ngx_conf_merge_value(conf->enable_code_cache, prev->enable_code_cache, 1);
    ngx_conf_merge_value(conf->http10_buffering, prev->http10_buffering, 1);
    ngx_conf_merge_value(conf->check_client_abort, prev->check_client_abort, 0);
    ngx_conf_merge_value(conf->use_default_type, prev->use_default_type, 1);

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


#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_lua_set_ssl(ngx_conf_t *cf, ngx_http_lua_loc_conf_t *llcf)
{
    ngx_pool_cleanup_t  *cln;

    llcf->ssl = ngx_pcalloc(cf->pool, sizeof(ngx_ssl_t));
    if (llcf->ssl == NULL) {
        return NGX_ERROR;
    }

    llcf->ssl->log = cf->log;

    if (ngx_ssl_create(llcf->ssl, llcf->ssl_protocols, NULL) != NGX_OK) {
        return NGX_ERROR;
    }

    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {
        ngx_ssl_cleanup_ctx(llcf->ssl);
        return NGX_ERROR;
    }

    cln->handler = ngx_ssl_cleanup_ctx;
    cln->data = llcf->ssl;

    if (SSL_CTX_set_cipher_list(llcf->ssl->ctx,
                                (const char *) llcf->ssl_ciphers.data)
        == 0)
    {
        ngx_ssl_error(NGX_LOG_EMERG, cf->log, 0,
                      "SSL_CTX_set_cipher_list(\"%V\") failed",
                      &llcf->ssl_ciphers);
        return NGX_ERROR;
    }

    if (llcf->ssl_trusted_certificate.len
        && ngx_ssl_trusted_certificate(cf, llcf->ssl,
                                       &llcf->ssl_trusted_certificate,
                                       llcf->ssl_verify_depth)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    dd("ssl crl: %.*s", (int) llcf->ssl_crl.len, llcf->ssl_crl.data);

    if (ngx_ssl_crl(cf, llcf->ssl, &llcf->ssl_crl) != NGX_OK) {
        return NGX_ERROR;
    }

#if (nginx_version >= 1019004)
    if (ngx_ssl_conf_commands(cf, llcf->ssl, llcf->ssl_conf_commands)
        != NGX_OK)
    {
        return NGX_ERROR;
    }
#endif

    return NGX_OK;
}

#if (nginx_version >= 1019004)
static char *
ngx_http_lua_ssl_conf_command_check(ngx_conf_t *cf, void *post, void *data)
{
#ifndef SSL_CONF_FLAG_FILE
    return "is not supported on this platform";
#endif

    return NGX_CONF_OK;
}
#endif

#endif  /* NGX_HTTP_SSL */


static char *
ngx_http_lua_malloc_trim(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
#if (NGX_HTTP_LUA_HAVE_MALLOC_TRIM)

    ngx_int_t       nreqs;
    ngx_str_t      *value;

    ngx_http_lua_main_conf_t    *lmcf = conf;

    value = cf->args->elts;

    nreqs = ngx_atoi(value[1].data, value[1].len);
    if (nreqs == NGX_ERROR) {
        return "invalid number in the 1st argument";
    }

    lmcf->malloc_trim_cycle = (ngx_uint_t) nreqs;

    if (nreqs == 0) {
        return NGX_CONF_OK;
    }

    lmcf->requires_log = 1;

#else

    ngx_conf_log_error(NGX_LOG_WARN, cf, 0, "lua_malloc_trim is not supported "
                       "on this platform, ignored");

#endif
    return NGX_CONF_OK;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
