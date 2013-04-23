/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef NGX_HTTP_LUA_COMMON_H
#define NGX_HTTP_LUA_COMMON_H

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

#define NGX_HTTP_LUA_CHECK_ABORTED(L, ctx) \
        if (ctx && ctx->aborted) { \
            return luaL_error(L, "coroutine aborted"); \
        }

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


typedef struct ngx_http_lua_main_conf_s ngx_http_lua_main_conf_t;


typedef ngx_int_t (*ngx_http_lua_conf_handler_pt)(ngx_log_t *log,
        ngx_http_lua_main_conf_t *lmcf, lua_State *L);


typedef struct {
    const char          *package;
    lua_CFunction        loader;
} ngx_http_lua_preload_hook_t;


struct ngx_http_lua_main_conf_s {
    lua_State       *lua;

    ngx_str_t        lua_path;
    ngx_str_t        lua_cpath;

    ngx_pool_t      *pool;

#if (NGX_PCRE)
    ngx_int_t        regex_cache_entries;
    ngx_int_t        regex_cache_max_entries;
#endif

    ngx_array_t     *shm_zones;  /* of ngx_shm_zone_t* */

    ngx_array_t     *preload_hooks; /* of ngx_http_lua_preload_hook_t */

    ngx_flag_t       postponed_to_rewrite_phase_end;
    ngx_flag_t       postponed_to_access_phase_end;

    ngx_http_lua_conf_handler_pt    init_handler;
    ngx_str_t                       init_src;
    ngx_uint_t                      shm_zones_inited;

    unsigned         requires_header_filter:1;
    unsigned         requires_body_filter:1;
    unsigned         requires_capture_filter:1;
    unsigned         requires_rewrite:1;
    unsigned         requires_access:1;
    unsigned         requires_log:1;
    unsigned         requires_shm:1;
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

} ngx_http_lua_loc_conf_t;


typedef struct {
    void                    *data;

    uint8_t                  context;

    lua_State               *cc;  /*  coroutine to handle request */

    int                      cc_ref;  /*  reference to anchor coroutine in
                                          the lua registry */

    int                      ctx_ref;  /*  reference to anchor
                                           request ctx data in lua
                                           registry */

    ngx_chain_t             *out;  /* buffered output chain for HTTP 1.0 */
    ngx_chain_t             *free_bufs;
    ngx_chain_t             *busy_bufs;
    ngx_chain_t             *free_recv_bufs;
    ngx_chain_t             *flush_buf;

    ngx_http_cleanup_pt     *cleanup;

    ngx_chain_t             *body; /* buffered response body chains */

    unsigned                 nsubreqs;  /* number of subrequests of the
                                         * current request */

    ngx_int_t               *sr_statuses; /* all capture subrequest statuses */

    ngx_http_headers_out_t **sr_headers;

    ngx_str_t               *sr_bodies;   /* all captured subrequest bodies */

    ngx_uint_t               index;              /* index of the current
                                                    subrequest in its parent
                                                    request */

    unsigned                 waiting;     /* number of subrequests being
                                             waited */

    ngx_str_t        exec_uri;
    ngx_str_t        exec_args;

    ngx_int_t        exit_code;

    ngx_event_t      sleep;      /* used for ngx.sleep */

    unsigned         exited:1;

    unsigned         headers_sent:1;    /*  1: response header has been sent;
                                            0: header not sent yet */

    unsigned         eof:1;             /*  1: last_buf has been sent;
                                            0: last_buf not sent yet */

    unsigned         done:1;            /*  1: subrequest is just done;
                                            0: subrequest is not done
                                            yet or has already done */

    unsigned         capture:1;         /*  1: body of current request is
                                            to be captured;
                                            0: not captured */

    unsigned         read_body_done:1;      /* 1: request body has been all
                                               read; 0: body has not been
                                               all read */

    unsigned         waiting_more_body:1;   /* 1: waiting for more data;
                                               0: no need to wait */
    unsigned         req_read_body_done:1;  /* used by ngx.req.read_body */

    unsigned         headers_set:1;
    unsigned         entered_rewrite_phase:1;
    unsigned         entered_access_phase:1;
    unsigned         entered_content_phase:1;

    /* whether it has run post_subrequest */
    unsigned         run_post_subrequest:1;
    unsigned         req_header_cached:1;

    unsigned         waiting_flush:1;

    unsigned         socket_busy:1;  /* for TCP */
    unsigned         socket_ready:1; /* for TCP */

    unsigned         udp_socket_busy:1;  /* for UDP */
    unsigned         udp_socket_ready:1; /* for UDP */

    unsigned         aborted:1;
    unsigned         buffering:1;

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
    ngx_http_lua_set_header_pt     handler;

} ngx_http_lua_set_header_t;


extern ngx_module_t ngx_http_lua_module;
extern ngx_http_output_header_filter_pt ngx_http_lua_next_header_filter;
extern ngx_http_output_body_filter_pt ngx_http_lua_next_body_filter;


#endif /* NGX_HTTP_LUA_COMMON_H */

