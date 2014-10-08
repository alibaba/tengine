
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_COMMON_H_INCLUDED_
#define _NGX_HTTP_LUA_COMMON_H_INCLUDED_


#include <nginx.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_md5.h>

#include <assert.h>
#include <setjmp.h>
#include <stdint.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#if defined(NDK) && NDK
#include <ndk.h>
#endif

#ifndef MD5_DIGEST_LENGTH
#define MD5_DIGEST_LENGTH 16
#endif

#define ngx_http_lua_assert(a)  assert(a)

/* Nginx HTTP Lua Inline tag prefix */

#define NGX_HTTP_LUA_INLINE_TAG "nhli_"

#define NGX_HTTP_LUA_INLINE_TAG_LEN \
    (sizeof(NGX_HTTP_LUA_INLINE_TAG) - 1)

#define NGX_HTTP_LUA_INLINE_KEY_LEN \
    (NGX_HTTP_LUA_INLINE_TAG_LEN + 2 * MD5_DIGEST_LENGTH)

/* Nginx HTTP Lua File tag prefix */

#define NGX_HTTP_LUA_FILE_TAG "nhlf_"

#define NGX_HTTP_LUA_FILE_TAG_LEN \
    (sizeof(NGX_HTTP_LUA_FILE_TAG) - 1)

#define NGX_HTTP_LUA_FILE_KEY_LEN \
    (NGX_HTTP_LUA_FILE_TAG_LEN + 2 * MD5_DIGEST_LENGTH)


#if defined(NDK) && NDK
typedef struct {
    size_t       size;
    u_char      *key;
    ngx_str_t    script;
} ngx_http_lua_set_var_data_t;
#endif


#ifndef NGX_HTTP_LUA_MAX_ARGS
#define NGX_HTTP_LUA_MAX_ARGS 100
#endif


#ifndef NGX_HTTP_LUA_MAX_HEADERS
#define NGX_HTTP_LUA_MAX_HEADERS 100
#endif


#define NGX_HTTP_LUA_CONTEXT_SET            0x01
#define NGX_HTTP_LUA_CONTEXT_REWRITE        0x02
#define NGX_HTTP_LUA_CONTEXT_ACCESS         0x04
#define NGX_HTTP_LUA_CONTEXT_CONTENT        0x08
#define NGX_HTTP_LUA_CONTEXT_LOG            0x10
#define NGX_HTTP_LUA_CONTEXT_HEADER_FILTER  0x20
#define NGX_HTTP_LUA_CONTEXT_BODY_FILTER    0x40
#define NGX_HTTP_LUA_CONTEXT_TIMER          0x80


#ifndef NGX_HTTP_LUA_NO_FFI_API
#define NGX_HTTP_LUA_FFI_NO_REQ_CTX         -100
#define NGX_HTTP_LUA_FFI_BAD_CONTEXT        -101
#endif


typedef struct ngx_http_lua_main_conf_s ngx_http_lua_main_conf_t;


typedef ngx_int_t (*ngx_http_lua_conf_handler_pt)(ngx_log_t *log,
        ngx_http_lua_main_conf_t *lmcf, lua_State *L);


typedef struct {
    u_char              *package;
    lua_CFunction        loader;
} ngx_http_lua_preload_hook_t;


struct ngx_http_lua_main_conf_s {
    lua_State           *lua;

    ngx_str_t            lua_path;
    ngx_str_t            lua_cpath;

    ngx_cycle_t         *cycle;
    ngx_pool_t          *pool;

    ngx_int_t            max_pending_timers;
    ngx_int_t            pending_timers;

    ngx_int_t            max_running_timers;
    ngx_int_t            running_timers;

    ngx_connection_t    *watcher;  /* for watching the process exit event */

#if (NGX_PCRE)
    ngx_int_t            regex_cache_entries;
    ngx_int_t            regex_cache_max_entries;
    ngx_int_t            regex_match_limit;
#endif

    ngx_array_t         *shm_zones;  /* of ngx_shm_zone_t* */

    ngx_array_t         *preload_hooks; /* of ngx_http_lua_preload_hook_t */

    ngx_flag_t           postponed_to_rewrite_phase_end;
    ngx_flag_t           postponed_to_access_phase_end;

    ngx_http_lua_conf_handler_pt    init_handler;
    ngx_str_t                       init_src;
    ngx_uint_t                      shm_zones_inited;

    unsigned             requires_header_filter:1;
    unsigned             requires_body_filter:1;
    unsigned             requires_capture_filter:1;
    unsigned             requires_rewrite:1;
    unsigned             requires_access:1;
    unsigned             requires_log:1;
    unsigned             requires_shm:1;
};


typedef struct {
    ngx_flag_t              force_read_body; /* whether force request body to
                                                be read */

    ngx_flag_t              enable_code_cache; /* whether to enable
                                                  code cache */

    ngx_flag_t              http10_buffering;

    ngx_http_handler_pt     rewrite_handler;
    ngx_http_handler_pt     access_handler;
    ngx_http_handler_pt     content_handler;
    ngx_http_handler_pt     log_handler;
    ngx_http_handler_pt     header_filter_handler;

    ngx_http_output_body_filter_pt         body_filter_handler;

    ngx_http_complex_value_t rewrite_src;    /*  rewrite_by_lua
                                                inline script/script
                                                file path */

    u_char                 *rewrite_src_key; /* cached key for rewrite_src */

    ngx_http_complex_value_t access_src;     /*  access_by_lua
                                                inline script/script
                                                file path */

    u_char                  *access_src_key; /* cached key for access_src */

    ngx_http_complex_value_t content_src;    /*  content_by_lua
                                                inline script/script
                                                file path */

    u_char                 *content_src_key; /* cached key for content_src */


    ngx_http_complex_value_t     log_src;     /* log_by_lua inline script/script
                                                 file path */

    u_char                      *log_src_key; /* cached key for log_src */

    ngx_http_complex_value_t header_filter_src;  /*  header_filter_by_lua
                                                     inline script/script
                                                     file path */

    u_char                 *header_filter_src_key;
                                    /* cached key for header_filter_src */


    ngx_http_complex_value_t         body_filter_src;
    u_char                          *body_filter_src_key;

    ngx_msec_t                       keepalive_timeout;
    ngx_msec_t                       connect_timeout;
    ngx_msec_t                       send_timeout;
    ngx_msec_t                       read_timeout;

    size_t                           send_lowat;
    size_t                           buffer_size;

    ngx_uint_t                       pool_size;

    ngx_flag_t                       transform_underscores_in_resp_headers;
    ngx_flag_t                       log_socket_errors;
    ngx_flag_t                       check_client_abort;
    ngx_flag_t                       use_default_type;
} ngx_http_lua_loc_conf_t;


typedef enum {
    NGX_HTTP_LUA_USER_CORO_NOP      = 0,
    NGX_HTTP_LUA_USER_CORO_RESUME   = 1,
    NGX_HTTP_LUA_USER_CORO_YIELD    = 2,
    NGX_HTTP_LUA_USER_THREAD_RESUME = 3
} ngx_http_lua_user_coro_op_t;


typedef enum {
    NGX_HTTP_LUA_CO_RUNNING   = 0, /* coroutine running */
    NGX_HTTP_LUA_CO_SUSPENDED = 1, /* coroutine suspended */
    NGX_HTTP_LUA_CO_NORMAL    = 2, /* coroutine normal */
    NGX_HTTP_LUA_CO_DEAD      = 3, /* coroutine dead */
    NGX_HTTP_LUA_CO_ZOMBIE    = 4, /* coroutine zombie */
} ngx_http_lua_co_status_t;


typedef struct ngx_http_lua_co_ctx_s  ngx_http_lua_co_ctx_t;

typedef struct ngx_http_lua_posted_thread_s  ngx_http_lua_posted_thread_t;

struct ngx_http_lua_posted_thread_s {
    ngx_http_lua_co_ctx_t               *co_ctx;
    ngx_http_lua_posted_thread_t        *next;
};


enum {
    NGX_HTTP_LUA_SUBREQ_TRUNCATED = 1
};


struct ngx_http_lua_co_ctx_s {
    void                    *data;      /* user state for cosockets */

    lua_State               *co;
    ngx_http_lua_co_ctx_t   *parent_co_ctx;

    ngx_http_lua_posted_thread_t    *zombie_child_threads;

    ngx_http_cleanup_pt      cleanup;

    unsigned                 nsubreqs;  /* number of subrequests of the
                                         * current request */

    ngx_int_t               *sr_statuses; /* all capture subrequest statuses */

    ngx_http_headers_out_t **sr_headers;

    ngx_str_t               *sr_bodies;   /* all captured subrequest bodies */

    uint8_t                 *sr_flags;

    unsigned                 pending_subreqs; /* number of subrequests being
                                                 waited */

    ngx_event_t              sleep;  /* used for ngx.sleep */

    int                      co_ref; /*  reference to anchor the thread
                                         coroutines (entry coroutine and user
                                         threads) in the Lua registry,
                                         preventing the thread coroutine
                                         from beging collected by the
                                         Lua GC */

    unsigned                 waited_by_parent:1;  /* whether being waited by
                                                     a parent coroutine */

    unsigned                 co_status:3;  /* the current coroutine's status */

    unsigned                 flushing:1; /* indicates whether the current
                                            coroutine is waiting for
                                            ngx.flush(true) */

    unsigned                 is_uthread:1; /* whether the current coroutine is
                                              a user thread */

    unsigned                 thread_spawn_yielded:1; /* yielded from
                                                        the ngx.thread.spawn()
                                                        call */
};


typedef struct {
    lua_State       *vm;
    ngx_int_t        count;
} ngx_http_lua_vm_state_t;


typedef struct ngx_http_lua_ctx_s {
    /* for lua_coce_cache off: */
    ngx_http_lua_vm_state_t  *vm_state;

    ngx_http_request_t      *request;
    ngx_http_handler_pt      resume_handler;

    ngx_http_lua_co_ctx_t   *cur_co_ctx; /* co ctx for the current coroutine */

    /* FIXME: we should use rbtree here to prevent O(n) lookup overhead */
    ngx_list_t              *user_co_ctx; /* coroutine contexts for user
                                             coroutines */

    ngx_http_lua_co_ctx_t    entry_co_ctx; /* coroutine context for the
                                              entry coroutine */

    ngx_http_lua_co_ctx_t   *on_abort_co_ctx; /* coroutine context for the
                                                 on_abort thread */

    int                      ctx_ref;  /*  reference to anchor
                                           request ctx data in lua
                                           registry */

    unsigned                 flushing_coros; /* number of coroutines waiting on
                                                ngx.flush(true) */

    unsigned                 uthreads; /* number of active user threads */

    ngx_chain_t             *out;  /* buffered output chain for HTTP 1.0 */
    ngx_chain_t             *free_bufs;
    ngx_chain_t             *busy_bufs;
    ngx_chain_t             *free_recv_bufs;
    ngx_chain_t             *flush_buf;

    ngx_http_cleanup_pt     *cleanup;

    ngx_chain_t             *body; /* buffered subrequest response body
                                      chains */

    ngx_chain_t            **last_body; /* for the "body" field */

    ngx_str_t                exec_uri;
    ngx_str_t                exec_args;

    ngx_int_t                exit_code;

    ngx_http_lua_co_ctx_t   *downstream_co_ctx; /* co ctx for the coroutine
                                                   reading the request body */

    ngx_uint_t               index;              /* index of the current
                                                    subrequest in its parent
                                                    request */

    ngx_http_lua_posted_thread_t   *posted_threads;

    uint16_t                 context;   /* the current running directive context
                                           (or running phase) for the current
                                           Lua chunk */

    unsigned                 run_post_subrequest:1; /* whether it has run
                                                       post_subrequest
                                                       (for subrequests only) */

    unsigned                 waiting_more_body:1;   /* 1: waiting for more
                                                       request body data;
                                                       0: no need to wait */

    unsigned         co_op:2; /*  coroutine API operation */

    unsigned         exited:1;

    unsigned         eof:1;             /*  1: last_buf has been sent;
                                            0: last_buf not sent yet */

    unsigned         capture:1;  /*  1: response body of current request
                                        is to be captured by the lua
                                        capture filter,
                                     0: not to be captured */


    unsigned         read_body_done:1;      /* 1: request body has been all
                                               read; 0: body has not been
                                               all read */

    unsigned         headers_set:1; /* whether the user has set custom
                                       response headers */

    unsigned         entered_rewrite_phase:1;
    unsigned         entered_access_phase:1;
    unsigned         entered_content_phase:1;

    unsigned         buffering:1; /* HTTP 1.0 response body buffering flag */

    unsigned         no_abort:1; /* prohibit "world abortion" via ngx.exit()
                                    and etc */

    unsigned         seen_last_in_filter:1;  /* used by body_filter_by_lua* */
    unsigned         seen_last_for_subreq:1; /* used by body capture filter */
    unsigned         writing_raw_req_socket:1; /* used by raw downstream
                                                  socket */
    unsigned         acquired_raw_req_socket:1;  /* whether a raw req socket
                                                    is acquired */
} ngx_http_lua_ctx_t;


typedef struct ngx_http_lua_header_val_s ngx_http_lua_header_val_t;


typedef ngx_int_t (*ngx_http_lua_set_header_pt)(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);


struct ngx_http_lua_header_val_s {
    ngx_http_complex_value_t                value;
    ngx_uint_t                              hash;
    ngx_str_t                               key;
    ngx_http_lua_set_header_pt              handler;
    ngx_uint_t                              offset;
    unsigned                                no_override;
};


typedef struct {
    ngx_str_t                               name;
    ngx_uint_t                              offset;
    ngx_http_lua_set_header_pt              handler;

} ngx_http_lua_set_header_t;


extern ngx_module_t ngx_http_lua_module;
extern ngx_http_output_header_filter_pt ngx_http_lua_next_header_filter;
extern ngx_http_output_body_filter_pt ngx_http_lua_next_body_filter;


#endif /* _NGX_HTTP_LUA_COMMON_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
