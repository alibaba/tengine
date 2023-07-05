
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_COMMON_H_INCLUDED_
#define _NGX_HTTP_LUA_COMMON_H_INCLUDED_


#include "ngx_http_lua_autoconf.h"

#include <nginx.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_md5.h>

#include <setjmp.h>
#include <stdint.h>

#include <luajit.h>
#include <lualib.h>
#include <lauxlib.h>


#if defined(NDK) && NDK
#include <ndk.h>

typedef struct {
    size_t       size;
    int          ref;
    u_char      *key;
    u_char      *chunkname;
    ngx_str_t    script;
} ngx_http_lua_set_var_data_t;
#endif


#ifdef NGX_LUA_USE_ASSERT
#include <assert.h>
#   define ngx_http_lua_assert(a)  assert(a)
#else
#   define ngx_http_lua_assert(a)
#endif


/**
 * max positive +1.7976931348623158e+308
 * min positive +2.2250738585072014e-308
 */
#ifndef NGX_DOUBLE_LEN
#define NGX_DOUBLE_LEN  25
#endif


#if (NGX_PCRE)
#include <pcre.h>
#   if (PCRE_MAJOR > 8) || (PCRE_MAJOR == 8 && PCRE_MINOR >= 21)
#       define LUA_HAVE_PCRE_JIT 1
#   else
#       define LUA_HAVE_PCRE_JIT 0
#   endif
#endif


#if (nginx_version < 1006000)
#   error at least nginx 1.6.0 is required but found an older version
#endif

#if LUA_VERSION_NUM != 501
#   error unsupported Lua language version
#endif

#if !defined(LUAJIT_VERSION_NUM) || (LUAJIT_VERSION_NUM < 20000)
#   error unsupported LuaJIT version
#endif


#if (!defined OPENSSL_NO_OCSP && defined SSL_CTRL_SET_TLSEXT_STATUS_REQ_CB)
#   define NGX_HTTP_LUA_USE_OCSP 1
#endif

#ifndef NGX_HTTP_PERMANENT_REDIRECT
#   define NGX_HTTP_PERMANENT_REDIRECT 308
#endif

#ifndef NGX_HAVE_SHA1
#   if (nginx_version >= 1011002)
#       define NGX_HAVE_SHA1 1
#   endif
#endif

#ifndef MD5_DIGEST_LENGTH
#   define MD5_DIGEST_LENGTH 16
#endif

#ifndef NGX_HTTP_LUA_MAX_ARGS
#   define NGX_HTTP_LUA_MAX_ARGS 100
#endif

#ifndef NGX_HTTP_LUA_MAX_HEADERS
#   define NGX_HTTP_LUA_MAX_HEADERS 100
#endif


/* Nginx HTTP Lua Inline tag prefix */

#define NGX_HTTP_LUA_INLINE_TAG "nhli_"

#define NGX_HTTP_LUA_INLINE_TAG_LEN                                          \
    (sizeof(NGX_HTTP_LUA_INLINE_TAG) - 1)

#define NGX_HTTP_LUA_INLINE_KEY_LEN                                          \
    (NGX_HTTP_LUA_INLINE_TAG_LEN + 2 * MD5_DIGEST_LENGTH)

/* Nginx HTTP Lua File tag prefix */

#define NGX_HTTP_LUA_FILE_TAG "nhlf_"

#define NGX_HTTP_LUA_FILE_TAG_LEN                                            \
    (sizeof(NGX_HTTP_LUA_FILE_TAG) - 1)

#define NGX_HTTP_LUA_FILE_KEY_LEN                                            \
    (NGX_HTTP_LUA_FILE_TAG_LEN + 2 * MD5_DIGEST_LENGTH)


/* must be within 16 bit */
#define NGX_HTTP_LUA_CONTEXT_SET                0x0001
#define NGX_HTTP_LUA_CONTEXT_REWRITE            0x0002
#define NGX_HTTP_LUA_CONTEXT_ACCESS             0x0004
#define NGX_HTTP_LUA_CONTEXT_CONTENT            0x0008
#define NGX_HTTP_LUA_CONTEXT_LOG                0x0010
#define NGX_HTTP_LUA_CONTEXT_HEADER_FILTER      0x0020
#define NGX_HTTP_LUA_CONTEXT_BODY_FILTER        0x0040
#define NGX_HTTP_LUA_CONTEXT_TIMER              0x0080
#define NGX_HTTP_LUA_CONTEXT_INIT_WORKER        0x0100
#define NGX_HTTP_LUA_CONTEXT_BALANCER           0x0200
#define NGX_HTTP_LUA_CONTEXT_SSL_CERT           0x0400
#define NGX_HTTP_LUA_CONTEXT_SSL_SESS_STORE     0x0800
#define NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH     0x1000
#define NGX_HTTP_LUA_CONTEXT_EXIT_WORKER        0x2000
#define NGX_HTTP_LUA_CONTEXT_SSL_CLIENT_HELLO   0x4000
#define NGX_HTTP_LUA_CONTEXT_SERVER_REWRITE     0x8000


#define NGX_HTTP_LUA_FFI_NO_REQ_CTX         -100
#define NGX_HTTP_LUA_FFI_BAD_CONTEXT        -101


#if (NGX_PTR_SIZE >= 8 && !defined(_WIN64))
#   define ngx_http_lua_lightudata_mask(ludata)                              \
        ((void *) ((uintptr_t) (&ngx_http_lua_##ludata) & ((1UL << 47) - 1)))
#else
#   define ngx_http_lua_lightudata_mask(ludata)                              \
        (&ngx_http_lua_##ludata)
#endif


typedef struct ngx_http_lua_co_ctx_s  ngx_http_lua_co_ctx_t;

typedef struct ngx_http_lua_sema_mm_s  ngx_http_lua_sema_mm_t;

typedef union ngx_http_lua_srv_conf_u  ngx_http_lua_srv_conf_t;

typedef struct ngx_http_lua_main_conf_s  ngx_http_lua_main_conf_t;

typedef struct ngx_http_lua_header_val_s  ngx_http_lua_header_val_t;

typedef struct ngx_http_lua_posted_thread_s  ngx_http_lua_posted_thread_t;

typedef struct ngx_http_lua_balancer_peer_data_s
    ngx_http_lua_balancer_peer_data_t;

typedef ngx_int_t (*ngx_http_lua_main_conf_handler_pt)(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L);

typedef ngx_int_t (*ngx_http_lua_srv_conf_handler_pt)(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

typedef ngx_int_t (*ngx_http_lua_set_header_pt)(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);


typedef struct {
    u_char              *package;
    lua_CFunction        loader;
} ngx_http_lua_preload_hook_t;


typedef struct {
    int             ref;
    lua_State      *co;
    ngx_queue_t     queue;
} ngx_http_lua_thread_ref_t;


struct ngx_http_lua_main_conf_s {
    lua_State           *lua;
    ngx_pool_cleanup_t  *vm_cleanup;

    ngx_str_t            lua_path;
    ngx_str_t            lua_cpath;

    ngx_cycle_t         *cycle;
    ngx_pool_t          *pool;

    ngx_int_t            max_pending_timers;
    ngx_int_t            pending_timers;

    ngx_int_t            max_running_timers;
    ngx_int_t            running_timers;

    ngx_connection_t    *watcher;  /* for watching the process exit event */

    ngx_int_t            lua_thread_cache_max_entries;

    ngx_hash_t           builtin_headers_out;

#if (NGX_PCRE)
    ngx_int_t            regex_cache_entries;
    ngx_int_t            regex_cache_max_entries;
    ngx_int_t            regex_match_limit;
#   if (LUA_HAVE_PCRE_JIT)
    pcre_jit_stack      *jit_stack;
#   endif
#endif

    ngx_array_t         *shm_zones;  /* of ngx_shm_zone_t* */

    ngx_array_t         *shdict_zones; /* shm zones of "shdict" */

    ngx_array_t         *preload_hooks; /* of ngx_http_lua_preload_hook_t */

    ngx_flag_t           postponed_to_rewrite_phase_end;
    ngx_flag_t           postponed_to_access_phase_end;

    ngx_http_lua_main_conf_handler_pt    init_handler;
    ngx_str_t                            init_src;
    u_char                              *init_chunkname;

    ngx_http_lua_main_conf_handler_pt    init_worker_handler;
    ngx_str_t                            init_worker_src;
    u_char                              *init_worker_chunkname;

    ngx_http_lua_main_conf_handler_pt    exit_worker_handler;
    ngx_str_t                            exit_worker_src;
    u_char                              *exit_worker_chunkname;

    ngx_http_lua_balancer_peer_data_t      *balancer_peer_data;
                    /* neither yielding nor recursion is possible in
                     * balancer_by_lua*, so there cannot be any races among
                     * concurrent requests and it is safe to store the peer
                     * data pointer in the main conf.
                     */

    ngx_chain_t                            *body_filter_chain;
                    /* neither yielding nor recursion is possible in
                     * body_filter_by_lua*, so there cannot be any races among
                     * concurrent requests when storing the chain
                     * data pointer in the main conf.
                     */

    ngx_http_variable_value_t              *setby_args;
                    /* neither yielding nor recursion is possible in
                     * set_by_lua*, so there cannot be any races among
                     * concurrent requests when storing the args pointer
                     * in the main conf.
                     */

    size_t                                  setby_nargs;
                    /* neither yielding nor recursion is possible in
                     * set_by_lua*, so there cannot be any races among
                     * concurrent requests when storing the nargs in the
                     * main conf.
                     */

    ngx_uint_t                      shm_zones_inited;

    ngx_http_lua_sema_mm_t         *sema_mm;

    ngx_uint_t           malloc_trim_cycle;  /* a cycle is defined as the number
                                                of requests */
    ngx_uint_t           malloc_trim_req_count;

    ngx_uint_t           directive_line;

#if (nginx_version >= 1011011)
    /* the following 2 fields are only used by ngx.req.raw_headers() for now */
    ngx_buf_t          **busy_buf_ptrs;
    ngx_int_t            busy_buf_ptr_count;
#endif

    ngx_int_t            host_var_index;

    ngx_flag_t           set_sa_restart;

    ngx_queue_t          free_lua_threads;  /* of ngx_http_lua_thread_ref_t */
    ngx_queue_t          cached_lua_threads;  /* of ngx_http_lua_thread_ref_t */

    ngx_uint_t           worker_thread_vm_pool_size;

    unsigned             requires_header_filter:1;
    unsigned             requires_body_filter:1;
    unsigned             requires_capture_filter:1;
    unsigned             requires_rewrite:1;
    unsigned             requires_access:1;
    unsigned             requires_log:1;
    unsigned             requires_shm:1;
    unsigned             requires_capture_log:1;
    unsigned             requires_server_rewrite:1;
};


union ngx_http_lua_srv_conf_u {
    struct {
#if (NGX_HTTP_SSL)
        ngx_http_lua_srv_conf_handler_pt     ssl_cert_handler;
        ngx_str_t                            ssl_cert_src;
        u_char                              *ssl_cert_src_key;
        u_char                              *ssl_cert_chunkname;
        int                                  ssl_cert_src_ref;

        ngx_http_lua_srv_conf_handler_pt     ssl_sess_store_handler;
        ngx_str_t                            ssl_sess_store_src;
        u_char                              *ssl_sess_store_src_key;
        u_char                              *ssl_sess_store_chunkname;
        int                                  ssl_sess_store_src_ref;

        ngx_http_lua_srv_conf_handler_pt     ssl_sess_fetch_handler;
        ngx_str_t                            ssl_sess_fetch_src;
        u_char                              *ssl_sess_fetch_src_key;
        u_char                              *ssl_sess_fetch_chunkname;
        int                                  ssl_sess_fetch_src_ref;

        ngx_http_lua_srv_conf_handler_pt     ssl_client_hello_handler;
        ngx_str_t                            ssl_client_hello_src;
        u_char                              *ssl_client_hello_src_key;
        u_char                              *ssl_client_hello_chunkname;
        int                                  ssl_client_hello_src_ref;
#endif

        ngx_http_lua_srv_conf_handler_pt     server_rewrite_handler;
        ngx_http_complex_value_t             server_rewrite_src;
        u_char                              *server_rewrite_src_key;
        u_char                              *server_rewrite_chunkname;
        int                                  server_rewrite_src_ref;
    } srv;

    struct {
        ngx_http_lua_srv_conf_handler_pt     handler;
        ngx_str_t                            src;
        u_char                              *src_key;
        u_char                              *chunkname;
        int                                  src_ref;
    } balancer;
};


typedef struct {
#if (NGX_HTTP_SSL)
    ngx_ssl_t              *ssl;  /* shared by SSL cosockets */
    ngx_uint_t              ssl_protocols;
    ngx_str_t               ssl_ciphers;
    ngx_uint_t              ssl_verify_depth;
    ngx_str_t               ssl_trusted_certificate;
    ngx_str_t               ssl_crl;
#if (nginx_version >= 1019004)
    ngx_array_t            *ssl_conf_commands;
#endif
#endif

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



    u_char                  *rewrite_chunkname;
    ngx_http_complex_value_t rewrite_src;    /*  rewrite_by_lua
                                                inline script/script
                                                file path */

    u_char                  *rewrite_src_key; /* cached key for rewrite_src */
    int                      rewrite_src_ref;

    u_char                  *access_chunkname;
    ngx_http_complex_value_t access_src;     /*  access_by_lua
                                                inline script/script
                                                file path */

    u_char                  *access_src_key; /* cached key for access_src */
    int                      access_src_ref;

    u_char                  *content_chunkname;
    ngx_http_complex_value_t content_src;    /*  content_by_lua
                                                inline script/script
                                                file path */

    u_char                 *content_src_key; /* cached key for content_src */
    int                     content_src_ref;


    u_char                      *log_chunkname;
    ngx_http_complex_value_t     log_src;     /* log_by_lua inline script/script
                                                 file path */

    u_char                      *log_src_key; /* cached key for log_src */
    int                          log_src_ref;

    ngx_http_complex_value_t header_filter_src;  /*  header_filter_by_lua
                                                     inline script/script
                                                     file path */

    u_char                 *header_filter_chunkname;
    u_char                 *header_filter_src_key;
                                    /* cached key for header_filter_src */
    int                     header_filter_src_ref;


    ngx_http_complex_value_t         body_filter_src;
    u_char                          *body_filter_src_key;
    u_char                          *body_filter_chunkname;
    int                              body_filter_src_ref;

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
    NGX_HTTP_LUA_USER_THREAD_RESUME = 3,
} ngx_http_lua_user_coro_op_t;


typedef enum {
    NGX_HTTP_LUA_CO_RUNNING   = 0, /* coroutine running */
    NGX_HTTP_LUA_CO_SUSPENDED = 1, /* coroutine suspended */
    NGX_HTTP_LUA_CO_NORMAL    = 2, /* coroutine normal */
    NGX_HTTP_LUA_CO_DEAD      = 3, /* coroutine dead */
    NGX_HTTP_LUA_CO_ZOMBIE    = 4, /* coroutine zombie */
} ngx_http_lua_co_status_t;


struct ngx_http_lua_posted_thread_s {
    ngx_http_lua_co_ctx_t               *co_ctx;
    ngx_http_lua_posted_thread_t        *next;
};


struct ngx_http_lua_co_ctx_s {
    void                    *data;      /* user state for cosockets */

    lua_State               *co;
    ngx_http_lua_co_ctx_t   *parent_co_ctx;

    ngx_http_lua_posted_thread_t    *zombie_child_threads;
    ngx_http_lua_posted_thread_t   **next_zombie_child_thread;

    ngx_http_cleanup_pt      cleanup;

    ngx_int_t               *sr_statuses; /* all capture subrequest statuses */

    ngx_http_headers_out_t **sr_headers;

    ngx_str_t               *sr_bodies;   /* all captured subrequest bodies */

    uint8_t                 *sr_flags;

    unsigned                 nresults_from_worker_thread;  /* number of results
                                                            * from worker
                                                            * thread callback */
    unsigned                 nrets;     /* ngx_http_lua_run_thread nrets arg. */

    unsigned                 nsubreqs;  /* number of subrequests of the
                                         * current request */

    unsigned                 pending_subreqs; /* number of subrequests being
                                                 waited */

    ngx_event_t              sleep;  /* used for ngx.sleep */

    ngx_queue_t              sem_wait_queue;

#ifdef NGX_LUA_USE_ASSERT
    int                      co_top; /* stack top after yielding/creation,
                                        only for sanity checks */
#endif

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
    unsigned                 sem_resume_status:1;

    unsigned                 is_wrap:1; /* set when creating coroutines via
                                           coroutine.wrap */

    unsigned                 propagate_error:1; /* set when propagating an error
                                                   from a coroutine to its
                                                   parent */
};


typedef struct {
    lua_State       *vm;
    ngx_int_t        count;
} ngx_http_lua_vm_state_t;


typedef struct ngx_http_lua_ctx_s {
    /* for lua_code_cache off: */
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

    ngx_chain_t             *out;  /* buffered output chain for HTTP 1.0 */
    ngx_chain_t             *free_bufs;
    ngx_chain_t             *busy_bufs;
    ngx_chain_t             *free_recv_bufs;

    ngx_chain_t             *filter_in_bufs;  /* for the body filter */
    ngx_chain_t             *filter_busy_bufs;  /* for the body filter */

    ngx_pool_cleanup_pt     *cleanup;

    ngx_http_cleanup_t      *free_cleanup; /* free list of cleanup records */

    ngx_chain_t             *body; /* buffered subrequest response body
                                      chains */

    ngx_chain_t            **last_body; /* for the "body" field */

    ngx_str_t                exec_uri;
    ngx_str_t                exec_args;

    ngx_int_t                exit_code;

    void                    *downstream;  /* can be either
                                             ngx_http_lua_socket_tcp_upstream_t
                                             or ngx_http_lua_co_ctx_t */

    ngx_uint_t               index;              /* index of the current
                                                    subrequest in its parent
                                                    request */

    ngx_http_lua_posted_thread_t   *posted_threads;

    int                      uthreads; /* number of active user threads */

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
    unsigned         mime_set:1;    /* whether the user has set Content-Type
                                       response header */
    unsigned         entered_server_rewrite_phase:1;
    unsigned         entered_rewrite_phase:1;
    unsigned         entered_access_phase:1;
    unsigned         entered_content_phase:1;

    unsigned         buffering:1; /* HTTP 1.0 response body buffering flag */

    unsigned         no_abort:1; /* prohibit "world abortion" via ngx.exit()
                                    and etc */

    unsigned         header_sent:1; /* r->header_sent is not sufficient for
                                     * this because special header filters
                                     * like ngx_image_filter may intercept
                                     * the header. so we should always test
                                     * both flags. see the test case in
                                     * t/020-subrequest.t */

    unsigned         seen_last_in_filter:1;  /* used by body_filter_by_lua* */
    unsigned         seen_last_for_subreq:1; /* used by body capture filter */
    unsigned         writing_raw_req_socket:1; /* used by raw downstream
                                                  socket */
    unsigned         acquired_raw_req_socket:1;  /* whether a raw req socket
                                                    is acquired */
    unsigned         seen_body_data:1;
} ngx_http_lua_ctx_t;


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
