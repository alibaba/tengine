/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef NGX_HTTP_LUA_UTIL_H
#define NGX_HTTP_LUA_UTIL_H

#include "ngx_http_lua_common.h"


#ifndef NGX_UNESCAPE_URI_COMPONENT
#define NGX_UNESCAPE_URI_COMPONENT  0
#endif

/* char whose address we'll use as key in Lua vm registry for
 * user code cache table */
extern char ngx_http_lua_code_cache_key;

/* char whose address we'll use as key in Lua vm registry for
 * all the "ngx.ctx" tables */
extern char ngx_http_lua_ctx_tables_key;

/* char whose address we'll use as key in Lua vm registry for
 * regex cache table  */
extern char ngx_http_lua_regex_cache_key;

/* char whose address we'll use as key in Lua vm registry for
 * socket connection pool table */
extern char ngx_http_lua_socket_pool_key;

/* char whose address we'll use as key for the nginx request pointer */
extern char ngx_http_lua_request_key;

/* char whose address we'll use as key for the nginx config logger */
extern char ngx_http_lua_cf_log_key;


#ifndef ngx_str_set
#define ngx_str_set(str, text)                                               \
    (str)->len = sizeof(text) - 1; (str)->data = (u_char *) text
#endif


#define ngx_http_lua_context_name(c)                                         \
    ((c) == NGX_HTTP_LUA_CONTEXT_SET ? "set_by_lua*"                         \
     : (c) == NGX_HTTP_LUA_CONTEXT_REWRITE ? "rewrite_by_lua*"               \
     : (c) == NGX_HTTP_LUA_CONTEXT_ACCESS ? "access_by_lua*"                 \
     : (c) == NGX_HTTP_LUA_CONTEXT_CONTENT ? "content_by_lua*"               \
     : (c) == NGX_HTTP_LUA_CONTEXT_LOG ? "log_by_lua*"                       \
     : (c) == NGX_HTTP_LUA_CONTEXT_HEADER_FILTER ? "header_filter_by_lua*"   \
     : "(unknown)")

#define ngx_http_lua_check_context(L, ctx, flags)                            \
    if (!((ctx)->context & (flags))) {                                       \
        return luaL_error(L, "API disabled in the context of %s",            \
                          ngx_http_lua_context_name((ctx)->context));        \
    }


lua_State * ngx_http_lua_new_state(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf);

lua_State * ngx_http_lua_new_thread(ngx_http_request_t *r, lua_State *l,
    int *ref);

void ngx_http_lua_del_thread(ngx_http_request_t *r, lua_State *l, int ref);

ngx_int_t ngx_http_lua_has_inline_var(ngx_str_t *s);

u_char * ngx_http_lua_rebase_path(ngx_pool_t *pool, u_char *src, size_t len);

ngx_int_t ngx_http_lua_send_header_if_needed(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx);

ngx_int_t ngx_http_lua_send_chain_link(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_chain_t *cl);

void ngx_http_lua_discard_bufs(ngx_pool_t *pool, ngx_chain_t *in);

ngx_int_t ngx_http_lua_add_copy_chain(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_chain_t **chain, ngx_chain_t *in);

void ngx_http_lua_reset_ctx(ngx_http_request_t *r, lua_State *L,
    ngx_http_lua_ctx_t *ctx);

void ngx_http_lua_generic_phase_post_read(ngx_http_request_t *r);

void ngx_http_lua_request_cleanup(void *data);

ngx_int_t ngx_http_lua_run_thread(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, int nret);

ngx_int_t ngx_http_lua_wev_handler(ngx_http_request_t *r);

u_char * ngx_http_lua_digest_hex(u_char *dest, const u_char *buf,
    int buf_len);

void ngx_http_lua_dump_postponed(ngx_http_request_t *r);

ngx_int_t ngx_http_lua_flush_postponed_outputs(ngx_http_request_t *r);

void ngx_http_lua_set_multi_value_table(lua_State *L, int index);

void ngx_http_lua_unescape_uri(u_char **dst, u_char **src, size_t size,
    ngx_uint_t type);

uintptr_t ngx_http_lua_escape_uri(u_char *dst, u_char *src,
    size_t size, ngx_uint_t type);

void ngx_http_lua_inject_req_api(ngx_log_t *log, lua_State *L);

void ngx_http_lua_process_args_option(ngx_http_request_t *r,
    lua_State *L, int table, ngx_str_t *args);

ngx_int_t ngx_http_lua_open_and_stat_file(u_char *name,
    ngx_open_file_info_t *of, ngx_log_t *log);

void ngx_http_lua_inject_internal_utils(ngx_log_t *log, lua_State *L);

ngx_chain_t * ngx_http_lua_chains_get_free_buf(ngx_log_t *log, ngx_pool_t *p,
    ngx_chain_t **free, size_t len, ngx_buf_tag_t tag);

void ngx_http_lua_create_new_global_table(lua_State *L, int narr, int nrec);

int ngx_http_lua_traceback(lua_State *L);


#endif /* NGX_HTTP_LUA_UTIL_H */

