
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#if (NGX_PCRE)

#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_script.h"
#include "ngx_http_lua_util.h"


#if (PCRE_MAJOR >= 6)
#   define LUA_HAVE_PCRE_DFA 1
#else
#   define LUA_HAVE_PCRE_DFA 0
#endif


#define NGX_LUA_RE_COMPILE_ONCE      (1<<0)
#define NGX_LUA_RE_MODE_DFA          (1<<1)
#define NGX_LUA_RE_MODE_JIT          (1<<2)
#define NGX_LUA_RE_MODE_DUPNAMES     (1<<3)
#define NGX_LUA_RE_NO_UTF8_CHECK     (1<<4)

#define NGX_LUA_RE_DFA_MODE_WORKSPACE_COUNT (100)

#define NGX_LUA_RE_MIN_JIT_STACK_SIZE 32 * 1024


typedef struct {
#ifndef NGX_LUA_NO_FFI_API
    ngx_pool_t                   *pool;
    u_char                       *name_table;
    int                           name_count;
    int                           name_entry_size;
#endif

    int                           ncaptures;
    int                          *captures;

    pcre                         *regex;
    pcre_extra                   *regex_sd;

    ngx_http_lua_complex_value_t    *replace;

#ifndef NGX_LUA_NO_FFI_API
    /* only for (stap) debugging, and may be an invalid pointer */
    const u_char                 *pattern;
#endif
} ngx_http_lua_regex_t;


typedef struct {
    ngx_str_t     pattern;
    ngx_pool_t   *pool;
    ngx_int_t     options;

    pcre         *regex;
    int           captures;
    ngx_str_t     err;
} ngx_http_lua_regex_compile_t;


typedef struct {
    ngx_http_cleanup_pt     *cleanup;
    ngx_http_request_t      *request;
    pcre                    *regex;
    pcre_extra              *regex_sd;
    int                      ncaptures;
    int                     *captures;
    int                      captures_len;
    uint8_t                  flags;
} ngx_http_lua_regex_ctx_t;


static int ngx_http_lua_ngx_re_gmatch_iterator(lua_State *L);
static ngx_uint_t ngx_http_lua_ngx_re_parse_opts(lua_State *L,
    ngx_http_lua_regex_compile_t *re, ngx_str_t *opts, int narg);
static int ngx_http_lua_ngx_re_sub_helper(lua_State *L, unsigned global);
static int ngx_http_lua_ngx_re_match_helper(lua_State *L, int wantcaps);
static int ngx_http_lua_ngx_re_find(lua_State *L);
static int ngx_http_lua_ngx_re_match(lua_State *L);
static int ngx_http_lua_ngx_re_gmatch(lua_State *L);
static int ngx_http_lua_ngx_re_sub(lua_State *L);
static int ngx_http_lua_ngx_re_gsub(lua_State *L);
static void ngx_http_lua_regex_free_study_data(ngx_pool_t *pool,
    pcre_extra *sd);
static ngx_int_t ngx_http_lua_regex_compile(ngx_http_lua_regex_compile_t *rc);
static void ngx_http_lua_ngx_re_gmatch_cleanup(void *data);
static int ngx_http_lua_ngx_re_gmatch_gc(lua_State *L);
static void ngx_http_lua_re_collect_named_captures(lua_State *L,
    int res_tb_idx, u_char *name_table, int name_count, int name_entry_size,
    unsigned flags, ngx_str_t *subj);


#define ngx_http_lua_regex_exec(re, e, s, start, captures, size, opts)       \
    pcre_exec(re, e, (const char *) (s)->data, (s)->len, start, opts,        \
              captures, size)


#define ngx_http_lua_regex_dfa_exec(re, e, s, start, captures, size, ws,     \
                                    wscount, opts)                           \
    pcre_dfa_exec(re, e, (const char *) (s)->data, (s)->len, start, opts,    \
                  captures, size, ws, wscount)


static int
ngx_http_lua_ngx_re_match(lua_State *L)
{
    return ngx_http_lua_ngx_re_match_helper(L, 1 /* want captures */);
}


static int
ngx_http_lua_ngx_re_find(lua_State *L)
{
    return ngx_http_lua_ngx_re_match_helper(L, 0 /* want captures */);
}


static int
ngx_http_lua_ngx_re_match_helper(lua_State *L, int wantcaps)
{
    /* u_char                      *p; */
    int                          res_tb_idx = 0;
    ngx_http_request_t          *r;
    ngx_str_t                    subj;
    ngx_str_t                    pat;
    ngx_str_t                    opts;
    ngx_http_lua_regex_t        *re;
    const char                  *msg;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    int                          i;
    ngx_int_t                    pos = 0;
    int                          nargs;
    int                         *cap = NULL;
    int                          ovecsize;
    int                          has_ctx = 0;
    ngx_uint_t                   flags;
    ngx_pool_t                  *pool, *old_pool;
    ngx_http_lua_main_conf_t    *lmcf;
    u_char                       errstr[NGX_MAX_CONF_ERRSTR + 1];
    pcre_extra                  *sd = NULL;
    int                          name_entry_size = 0, name_count;
    u_char                      *name_table = NULL;
    int                          exec_opts;
    int                          group_id = 0;

    ngx_http_lua_regex_compile_t      re_comp;

    nargs = lua_gettop(L);

    if (nargs != 2 && nargs != 3 && nargs != 4 && nargs != 5) {
        return luaL_error(L, "expecting 2, 3, 4 or 5 arguments, "
                          "but got %d", nargs);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    subj.data = (u_char *) luaL_checklstring(L, 1, &subj.len);
    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);

    ngx_memzero(&re_comp, sizeof(ngx_http_lua_regex_compile_t));

    if (nargs >= 3) {
        opts.data = (u_char *) luaL_checklstring(L, 3, &opts.len);

        if (nargs >= 4) {
            if (!lua_isnil(L, 4)) {
                luaL_checktype(L, 4, LUA_TTABLE);
                has_ctx = 1;

                lua_getfield(L, 4, "pos");
                if (lua_isnumber(L, -1)) {
                    pos = (ngx_int_t) lua_tointeger(L, -1);
                    if (pos <= 0) {
                        pos = 0;

                    } else {
                        pos--;  /* 1-based on the Lua land */
                    }

                } else if (lua_isnil(L, -1)) {
                    pos = 0;

                } else {
                    msg = lua_pushfstring(L, "bad pos field type in the ctx "
                                          "table argument: %s",
                                          luaL_typename(L, -1));

                    return luaL_argerror(L, 4, msg);
                }

                lua_pop(L, 1);
            }
        }

    } else {
        opts.data = (u_char *) "";
        opts.len = 0;
    }

    if (nargs == 5) {
        if (wantcaps) {
            luaL_checktype(L, 5, LUA_TTABLE);
            res_tb_idx = 5;

#if 0
            /* clear the Lua table */
            lua_pushnil(L);
            while (lua_next(L, res_tb_idx) != 0) {
                lua_pop(L, 1);
                lua_pushvalue(L, -1);
                lua_pushnil(L);
                lua_rawset(L, res_tb_idx);
            }
#endif

        } else {
            group_id =  luaL_checkint(L, 5);
            if (group_id < 0) {
                group_id = 0;
            }
        }
    }

    re_comp.options = 0;

    flags = ngx_http_lua_ngx_re_parse_opts(L, &re_comp, &opts, 3);

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    if (flags & NGX_LUA_RE_COMPILE_ONCE) {
        pool = lmcf->pool;

        dd("server pool %p", lmcf->pool);

        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              regex_cache_key));
        lua_rawget(L, LUA_REGISTRYINDEX); /* table */

        lua_pushliteral(L, "m");
        lua_pushvalue(L, 2); /* table regex */

        dd("options size: %d", (int) sizeof(re_comp.options));

        lua_pushlstring(L, (char *) &re_comp.options, sizeof(re_comp.options));
                /* table regex opts */

        lua_concat(L, 3); /* table key */
        lua_pushvalue(L, -1); /* table key key */

        dd("regex cache key: %.*s", (int) (pat.len + sizeof(re_comp.options)),
           lua_tostring(L, -1));

        lua_rawget(L, -3); /* table key re */
        re = lua_touserdata(L, -1);

        lua_pop(L, 1); /* table key */

        if (re) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua regex cache hit for match regex \"%s\" with "
                           "options \"%s\"", pat.data, opts.data);

            lua_pop(L, 2);

            dd("restoring regex %p, ncaptures %d,  captures %p", re->regex,
               re->ncaptures, re->captures);

            re_comp.regex = re->regex;
            sd = re->regex_sd;
            re_comp.captures = re->ncaptures;
            cap = re->captures;

            if (flags & NGX_LUA_RE_MODE_DFA) {
                ovecsize = 2;

            } else {
                ovecsize = (re->ncaptures + 1) * 3;
            }

            goto exec;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua regex cache miss for match regex \"%s\" "
                       "with options \"%s\"", pat.data, opts.data);

        if (lmcf->regex_cache_entries >= lmcf->regex_cache_max_entries) {

            if (lmcf->regex_cache_entries == lmcf->regex_cache_max_entries) {
                ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                              "lua exceeding regex cache max entries (%i)",
                              lmcf->regex_cache_max_entries);

                lmcf->regex_cache_entries++;
            }

            pool = r->pool;
            flags &= ~NGX_LUA_RE_COMPILE_ONCE;
        }

    } else {
        pool = r->pool;
    }

    dd("pool %p, r pool %p", pool, r->pool);

    re_comp.pattern = pat;
    re_comp.err.len = NGX_MAX_CONF_ERRSTR;
    re_comp.err.data = errstr;
    re_comp.pool = pool;

    ngx_log_debug5(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua compiling match regex \"%s\" with options \"%s\" "
                   "(compile once: %d) (dfa mode: %d) (jit mode: %d)",
                   pat.data, opts.data,
                   (flags & NGX_LUA_RE_COMPILE_ONCE) != 0,
                   (flags & NGX_LUA_RE_MODE_DFA) != 0,
                   (flags & NGX_LUA_RE_MODE_JIT) != 0);

    old_pool = ngx_http_lua_pcre_malloc_init(pool);

    rc = ngx_http_lua_regex_compile(&re_comp);

    ngx_http_lua_pcre_malloc_done(old_pool);

    if (rc != NGX_OK) {
        dd("compile failed");

        lua_pushnil(L);
        if (!wantcaps) {
            lua_pushnil(L);
        }
        lua_pushlstring(L, (char *) re_comp.err.data, re_comp.err.len);
        return wantcaps ? 2 : 3;
    }

#if (LUA_HAVE_PCRE_JIT)

    if (flags & NGX_LUA_RE_MODE_JIT) {

        old_pool = ngx_http_lua_pcre_malloc_init(pool);

        sd = pcre_study(re_comp.regex, PCRE_STUDY_JIT_COMPILE, &msg);

        if (sd && lmcf->jit_stack) {
            pcre_assign_jit_stack(sd, NULL, lmcf->jit_stack);
        }

        ngx_http_lua_pcre_malloc_done(old_pool);

#   if (NGX_DEBUG)
        dd("sd = %p", sd);

        if (msg != NULL) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre study failed with PCRE_STUDY_JIT_COMPILE: "
                           "%s (%p)", msg, sd);
        }

        if (sd != NULL) {
            int         jitted;

            old_pool = ngx_http_lua_pcre_malloc_init(pool);

            pcre_fullinfo(re_comp.regex, sd, PCRE_INFO_JIT, &jitted);

            ngx_http_lua_pcre_malloc_done(old_pool);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre JIT compiling result: %d", jitted);
        }
#   endif /* !(NGX_DEBUG) */

    } else {
        old_pool = ngx_http_lua_pcre_malloc_init(pool);

        sd = pcre_study(re_comp.regex, 0, &msg);

        ngx_http_lua_pcre_malloc_done(old_pool);

#   if (NGX_DEBUG)
        dd("sd = %p", sd);

        if (msg != NULL) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre_study failed with PCRE_STUDY_JIT_COMPILE: "
                           "%s (%p)", msg, sd);
        }
#   endif /* NGX_DEBUG */
    }

#else  /* !(LUA_HAVE_PCRE_JIT) */

    if (flags & NGX_LUA_RE_MODE_JIT) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "your pcre build does not have JIT support and "
                       "the \"j\" regex option is ignored");
    }

#endif /* LUA_HAVE_PCRE_JIT */

    if (sd && lmcf->regex_match_limit > 0) {
        sd->flags |= PCRE_EXTRA_MATCH_LIMIT;
        sd->match_limit = lmcf->regex_match_limit;
    }

    dd("compile done, captures %d", (int) re_comp.captures);

    if (flags & NGX_LUA_RE_MODE_DFA) {
        ovecsize = 2;
        re_comp.captures = 0;

    } else {
        ovecsize = (re_comp.captures + 1) * 3;
    }

    dd("allocating cap with size: %d", (int) ovecsize);

    cap = ngx_palloc(pool, ovecsize * sizeof(int));

    if (cap == NULL) {
        flags &= ~NGX_LUA_RE_COMPILE_ONCE;
        msg = "no memory";
        goto error;
    }

    if (flags & NGX_LUA_RE_COMPILE_ONCE) {

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua saving compiled regex (%d captures) into the cache "
                       "(entries %i)", re_comp.captures,
                       lmcf->regex_cache_entries);

        re = ngx_palloc(pool, sizeof(ngx_http_lua_regex_t));
        if (re == NULL) {
            msg = "no memory";
            goto error;
        }

        dd("saving regex %p, ncaptures %d,  captures %p", re_comp.regex,
           re_comp.captures, cap);

        re->regex = re_comp.regex;
        re->regex_sd = sd;
        re->ncaptures = re_comp.captures;
        re->captures = cap;
        re->replace = NULL;

        lua_pushlightuserdata(L, re); /* table key value */
        lua_rawset(L, -3); /* table */
        lua_pop(L, 1);

        if (lmcf) {
            lmcf->regex_cache_entries++;
        }
    }

exec:

    if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMECOUNT,
                      &name_count) != 0)
    {
        msg = "cannot acquire named subpattern count";
        goto error;
    }

    if (name_count > 0) {
        if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMEENTRYSIZE,
                          &name_entry_size) != 0)
        {
            msg = "cannot acquire named subpattern entry size";
            goto error;
        }

        if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMETABLE,
                          &name_table) != 0)
        {
            msg = "cannot acquire named subpattern table";
            goto error;
        }
    }

    if (flags & NGX_LUA_RE_NO_UTF8_CHECK) {
        exec_opts = PCRE_NO_UTF8_CHECK;

    } else {
        exec_opts = 0;
    }

    if (flags & NGX_LUA_RE_MODE_DFA) {

#if LUA_HAVE_PCRE_DFA

        int ws[NGX_LUA_RE_DFA_MODE_WORKSPACE_COUNT];
        rc = ngx_http_lua_regex_dfa_exec(re_comp.regex, sd, &subj,
                                         (int) pos, cap, ovecsize, ws,
                                         sizeof(ws)/sizeof(ws[0]), exec_opts);

#else /* LUA_HAVE_PCRE_DFA */

        msg = "at least pcre 6.0 is required for the DFA mode";
        goto error;

#endif /* LUA_HAVE_PCRE_DFA */

    } else {
        rc = ngx_http_lua_regex_exec(re_comp.regex, sd, &subj, (int) pos, cap,
                                     ovecsize, exec_opts);
    }

    if (rc == NGX_REGEX_NO_MATCHED) {
        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "regex \"%V\" not matched on string \"%V\" starting "
                       "from %i", &pat, &subj, pos);

        if (!(flags & NGX_LUA_RE_COMPILE_ONCE)) {
            if (sd) {
                ngx_http_lua_regex_free_study_data(pool, sd);
            }

            ngx_pfree(pool, re_comp.regex);
            ngx_pfree(pool, cap);
        }

        lua_pushnil(L);
        return 1;
    }

    if (rc < 0) {
        msg = lua_pushfstring(L, ngx_regex_exec_n " failed: %d", (int) rc);
        goto error;
    }

    if (rc == 0) {
        if (flags & NGX_LUA_RE_MODE_DFA) {
            rc = 1;

        } else {
            msg = "capture size too small";
            goto error;
        }
    }

    dd("rc = %d", (int) rc);

    if (has_ctx) { /* having ctx table */
        pos = cap[1];
        lua_pushinteger(L, (lua_Integer) (pos + 1));
        lua_setfield(L, 4, "pos");
    }

    if (!wantcaps) {
        if (group_id > re_comp.captures) {
            lua_pushnil(L);
            lua_pushnil(L);
            lua_pushliteral(L, "nth out of bound");
            return 3;
        }

        if (group_id >= rc) {
            lua_pushnil(L);
            lua_pushnil(L);
            return 2;
        }

        {
            int     from, to;

            from = cap[group_id * 2] + 1;
            to = cap[group_id * 2 + 1];
            if (from < 0 || to < 0) {
                lua_pushnil(L);
                lua_pushnil(L);
                return 2;
            }

            lua_pushinteger(L, from);
            lua_pushinteger(L, to);
            return 2;
        }
    }

    if (res_tb_idx == 0) {
        lua_createtable(L, re_comp.captures || 1 /* narr */,
                        name_count /* nrec */);
        res_tb_idx = lua_gettop(L);
    }

    for (i = 0, n = 0; i <= re_comp.captures; i++, n += 2) {
        dd("capture %d: %d %d", i, cap[n], cap[n + 1]);
        if (i >= rc || cap[n] < 0) {
            lua_pushboolean(L, 0);

        } else {
            lua_pushlstring(L, (char *) &subj.data[cap[n]],
                            cap[n + 1] - cap[n]);

            dd("pushing capture %s at %d", lua_tostring(L, -1), (int) i);
        }

        lua_rawseti(L, res_tb_idx, (int) i);
    }

    if (name_count > 0) {
        ngx_http_lua_re_collect_named_captures(L, res_tb_idx, name_table,
                                               name_count, name_entry_size,
                                               flags, &subj);
    }

    if (!(flags & NGX_LUA_RE_COMPILE_ONCE)) {

        if (sd) {
            ngx_http_lua_regex_free_study_data(pool, sd);
        }

        ngx_pfree(pool, re_comp.regex);
        ngx_pfree(pool, cap);
    }

    return 1;

error:

    if (!(flags & NGX_LUA_RE_COMPILE_ONCE)) {
        if (sd) {
            ngx_http_lua_regex_free_study_data(pool, sd);
        }

        if (re_comp.regex) {
            ngx_pfree(pool, re_comp.regex);
        }

        if (cap) {
            ngx_pfree(pool, cap);
        }
    }

    lua_pushnil(L);
    if (!wantcaps) {
        lua_pushnil(L);
    }
    lua_pushstring(L, msg);
    return wantcaps ? 2 : 3;
}


static int
ngx_http_lua_ngx_re_gmatch(lua_State *L)
{
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_request_t          *r;
    ngx_str_t                    subj;
    ngx_str_t                    pat;
    ngx_str_t                    opts;
    int                          ovecsize;
    ngx_http_lua_regex_t        *re;
    ngx_http_lua_regex_ctx_t    *ctx;
    const char                  *msg;
    int                          nargs;
    ngx_int_t                    flags;
    int                         *cap = NULL;
    ngx_int_t                    rc;
    ngx_pool_t                  *pool, *old_pool;
    u_char                       errstr[NGX_MAX_CONF_ERRSTR + 1];
    pcre_extra                  *sd = NULL;
    ngx_http_cleanup_t          *cln;

    ngx_http_lua_regex_compile_t      re_comp;

    nargs = lua_gettop(L);

    if (nargs != 2 && nargs != 3) {
        return luaL_error(L, "expecting two or three arguments, but got %d",
                          nargs);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    subj.data = (u_char *) luaL_checklstring(L, 1, &subj.len);
    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);

    if (nargs == 3) {
        opts.data = (u_char *) luaL_checklstring(L, 3, &opts.len);
        lua_pop(L, 1);

    } else {
        opts.data = (u_char *) "";
        opts.len = 0;
    }

    /* stack: subj regex */

    re_comp.options = 0;

    flags = ngx_http_lua_ngx_re_parse_opts(L, &re_comp, &opts, 3);

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    if (flags & NGX_LUA_RE_COMPILE_ONCE) {
        pool = lmcf->pool;

        dd("server pool %p", lmcf->pool);

        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              regex_cache_key));
        lua_rawget(L, LUA_REGISTRYINDEX); /* table */

        lua_pushliteral(L, "m");
        lua_pushvalue(L, 2); /* table regex */

        dd("options size: %d", (int) sizeof(re_comp.options));

        lua_pushlstring(L, (char *) &re_comp.options,
                        sizeof(re_comp.options)); /* table regex opts */

        lua_concat(L, 3); /* table key */
        lua_pushvalue(L, -1); /* table key key */

        dd("regex cache key: %.*s", (int) (pat.len + sizeof(re_comp.options)),
           lua_tostring(L, -1));

        lua_rawget(L, -3); /* table key re */
        re = lua_touserdata(L, -1);

        lua_pop(L, 1); /* table key */

        if (re) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua regex cache hit for match regex \"%s\" "
                           "with options \"%s\"", pat.data, opts.data);

            lua_pop(L, 2);

            dd("restoring regex %p, ncaptures %d,  captures %p", re->regex,
               re->ncaptures, re->captures);

            re_comp.regex = re->regex;
            sd = re->regex_sd;
            re_comp.captures = re->ncaptures;
            cap = re->captures;

            if (flags & NGX_LUA_RE_MODE_DFA) {
                ovecsize = 2;

            } else {
                ovecsize = (re->ncaptures + 1) * 3;
            }

            goto compiled;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua regex cache miss for match regex \"%s\" "
                       "with options \"%s\"", pat.data, opts.data);

        if (lmcf->regex_cache_entries >= lmcf->regex_cache_max_entries) {

            if (lmcf->regex_cache_entries == lmcf->regex_cache_max_entries) {
                ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                              "lua exceeding regex cache max entries (%i)",
                              lmcf->regex_cache_max_entries);

                lmcf->regex_cache_entries++;
            }

            pool = r->pool;
            flags &= ~NGX_LUA_RE_COMPILE_ONCE;
        }

    } else {
        pool = r->pool;
    }

    re_comp.pattern = pat;
    re_comp.err.len = NGX_MAX_CONF_ERRSTR;
    re_comp.err.data = errstr;
    re_comp.pool = pool;

    ngx_log_debug5(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua compiling gmatch regex \"%s\" with options \"%s\" "
                   "(compile once: %d) (dfa mode: %d) (jit mode: %d)",
                   pat.data, opts.data,
                   (flags & NGX_LUA_RE_COMPILE_ONCE) != 0,
                   (flags & NGX_LUA_RE_MODE_DFA) != 0,
                   (flags & NGX_LUA_RE_MODE_JIT) != 0);

    old_pool = ngx_http_lua_pcre_malloc_init(pool);

    rc = ngx_http_lua_regex_compile(&re_comp);

    ngx_http_lua_pcre_malloc_done(old_pool);

    if (rc != NGX_OK) {
        dd("compile failed");

        lua_pushnil(L);
        lua_pushlstring(L, (char *) re_comp.err.data, re_comp.err.len);
        return 2;
    }

#if LUA_HAVE_PCRE_JIT

    if (flags & NGX_LUA_RE_MODE_JIT) {

        old_pool = ngx_http_lua_pcre_malloc_init(pool);

        sd = pcre_study(re_comp.regex, PCRE_STUDY_JIT_COMPILE, &msg);

        if (sd && lmcf->jit_stack) {
            pcre_assign_jit_stack(sd, NULL, lmcf->jit_stack);
        }

        ngx_http_lua_pcre_malloc_done(old_pool);

#   if (NGX_DEBUG)
        dd("sd = %p", sd);

        if (msg != NULL) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre_study failed with PCRE_STUDY_JIT_COMPILE: "
                           "%s (%p)", msg, sd);
        }

        if (sd != NULL) {
            int         jitted;

            old_pool = ngx_http_lua_pcre_malloc_init(pool);

            pcre_fullinfo(re_comp.regex, sd, PCRE_INFO_JIT, &jitted);

            ngx_http_lua_pcre_malloc_done(old_pool);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre JIT compiling result: %d", jitted);
        }
#   endif /* NGX_DEBUG */

    } else {

        old_pool = ngx_http_lua_pcre_malloc_init(pool);

        sd = pcre_study(re_comp.regex, 0, &msg);

        ngx_http_lua_pcre_malloc_done(old_pool);

#   if (NGX_DEBUG)
        dd("sd = %p", sd);

        if (msg != NULL) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre study failed with PCRE_STUDY_JIT_COMPILE: "
                           "%s (%p)", msg, sd);
        }
#   endif /* NGX_DEBUG */
    }

#else  /* LUA_HAVE_PCRE_JIT */

    if (flags & NGX_LUA_RE_MODE_JIT) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "your pcre build does not have JIT support and "
                       "the \"j\" regex option is ignored");
    }

#endif /* LUA_HAVE_PCRE_JIT */

    if (sd && lmcf->regex_match_limit > 0) {
        sd->flags |= PCRE_EXTRA_MATCH_LIMIT;
        sd->match_limit = lmcf->regex_match_limit;
    }

    dd("compile done, captures %d", re_comp.captures);

    if (flags & NGX_LUA_RE_MODE_DFA) {
        ovecsize = 2;
        re_comp.captures = 0;

    } else {
        ovecsize = (re_comp.captures + 1) * 3;
    }

    cap = ngx_palloc(pool, ovecsize * sizeof(int));
    if (cap == NULL) {
        flags &= ~NGX_LUA_RE_COMPILE_ONCE;
        msg = "no memory";
        goto error;
    }

    if (flags & NGX_LUA_RE_COMPILE_ONCE) {

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua saving compiled regex (%d captures) into the cache "
                       "(entries %i)", re_comp.captures,
                       lmcf->regex_cache_entries);

        re = ngx_palloc(pool, sizeof(ngx_http_lua_regex_t));
        if (re == NULL) {
            msg = "no memory";
            goto error;
        }

        dd("saving regex %p, ncaptures %d,  captures %p", re_comp.regex,
           re_comp.captures, cap);

        re->regex = re_comp.regex;
        re->regex_sd = sd;
        re->ncaptures = re_comp.captures;
        re->captures = cap;
        re->replace = NULL;

        lua_pushlightuserdata(L, re); /* table key value */
        lua_rawset(L, -3); /* table */
        lua_pop(L, 1);

        if (lmcf) {
            lmcf->regex_cache_entries++;
        }
    }

compiled:

    lua_settop(L, 1);

    ctx = lua_newuserdata(L, sizeof(ngx_http_lua_regex_ctx_t));

    ctx->request = r;
    ctx->regex = re_comp.regex;
    ctx->regex_sd = sd;
    ctx->ncaptures = re_comp.captures;
    ctx->captures = cap;
    ctx->captures_len = ovecsize;
    ctx->flags = (uint8_t) flags;

    if (!(flags & NGX_LUA_RE_COMPILE_ONCE)) {
        lua_createtable(L, 0 /* narr */, 1 /* nrec */); /* metatable */
        lua_pushcfunction(L, ngx_http_lua_ngx_re_gmatch_gc);
        lua_setfield(L, -2, "__gc");
        lua_setmetatable(L, -2);

        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            msg = "no memory";
            goto error;
        }

        cln->handler = ngx_http_lua_ngx_re_gmatch_cleanup;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;

    } else {
        ctx->cleanup = NULL;
    }

    lua_pushinteger(L, 0);

    /* upvalues in order: subj ctx offset */
    lua_pushcclosure(L, ngx_http_lua_ngx_re_gmatch_iterator, 3);

    return 1;

error:

    if (!(flags & NGX_LUA_RE_COMPILE_ONCE)) {
        if (sd) {
            ngx_http_lua_regex_free_study_data(pool, sd);
        }

        if (re_comp.regex) {
            ngx_pfree(pool, re_comp.regex);
        }

        if (cap) {
            ngx_pfree(pool, cap);
        }
    }

    lua_pushnil(L);
    lua_pushstring(L, msg);
    return 2;
}


static int
ngx_http_lua_ngx_re_gmatch_iterator(lua_State *L)
{
    ngx_http_lua_regex_ctx_t    *ctx;
    ngx_http_request_t          *r;
    int                         *cap;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    int                          i;
    ngx_str_t                    subj;
    int                          offset;
    const char                  *msg = NULL;
    int                          name_entry_size = 0, name_count;
    u_char                      *name_table = NULL;
    int                          exec_opts;

    /* upvalues in order: subj ctx offset */

    subj.data = (u_char *) lua_tolstring(L, lua_upvalueindex(1), &subj.len);
    ctx = (ngx_http_lua_regex_ctx_t *) lua_touserdata(L, lua_upvalueindex(2));
    offset = (int) lua_tointeger(L, lua_upvalueindex(3));

    if (offset < 0) {
        lua_pushnil(L);
        return 1;
    }

    cap = ctx->captures;

    dd("offset %d, r %p, subj %s", (int) offset, ctx->request, subj.data);

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (r != ctx->request || r->pool != ctx->request->pool) {
        return luaL_error(L, "attempt to use ngx.re.gmatch iterator in a "
                          "request that did not create it");
    }

    dd("regex exec...");

    if (pcre_fullinfo(ctx->regex, NULL, PCRE_INFO_NAMECOUNT,
                      &name_count) != 0)
    {
        msg = "cannot acquire named subpattern count";
        goto error;
    }

    if (name_count > 0) {
        if (pcre_fullinfo(ctx->regex, NULL, PCRE_INFO_NAMEENTRYSIZE,
                          &name_entry_size) != 0)
        {
            msg = "cannot acquire named subpattern entry size";
            goto error;
        }

        if (pcre_fullinfo(ctx->regex, NULL, PCRE_INFO_NAMETABLE,
                          &name_table) != 0)
        {
            msg = "cannot acquire named subpattern table";
            goto error;
        }
    }

    if (ctx->flags & NGX_LUA_RE_NO_UTF8_CHECK) {
        exec_opts = PCRE_NO_UTF8_CHECK;

    } else {
        exec_opts = 0;
    }

    if (ctx->flags & NGX_LUA_RE_MODE_DFA) {

#if LUA_HAVE_PCRE_DFA

        int ws[NGX_LUA_RE_DFA_MODE_WORKSPACE_COUNT];

        rc = ngx_http_lua_regex_dfa_exec(ctx->regex, ctx->regex_sd, &subj,
                                         offset, cap, ctx->captures_len, ws,
                                         sizeof(ws)/sizeof(ws[0]), exec_opts);

#else /* LUA_HAVE_PCRE_DFA */
        msg = "at least pcre 6.0 is required for the DFA mode";
        goto error;

#endif /* LUA_HAVE_PCRE_DFA */

    } else {
        rc = ngx_http_lua_regex_exec(ctx->regex, ctx->regex_sd, &subj,
                                     offset, cap, ctx->captures_len,
                                     exec_opts);
    }

    if (rc == NGX_REGEX_NO_MATCHED) {
        /* set upvalue "offset" to -1 */
        lua_pushinteger(L, -1);
        lua_replace(L, lua_upvalueindex(3));

        if (!(ctx->flags & NGX_LUA_RE_COMPILE_ONCE)) {
            if (ctx->regex_sd) {
                ngx_http_lua_regex_free_study_data(r->pool, ctx->regex_sd);
                ctx->regex_sd = NULL;
            }

            ngx_pfree(r->pool, cap);
        }

        lua_pushnil(L);
        return 1;
    }

    if (rc < 0) {
        msg = lua_pushfstring(L, ngx_regex_exec_n " failed: %d", (int) rc);
        goto error;
    }

    if (rc == 0) {
        if (ctx->flags & NGX_LUA_RE_MODE_DFA) {
            rc = 1;

        } else {
            goto error;
        }
    }

    dd("rc = %d", (int) rc);

    lua_createtable(L, ctx->ncaptures || 1 /* narr */, name_count /* nrec */);

    for (i = 0, n = 0; i <= ctx->ncaptures; i++, n += 2) {
        dd("capture %d: %d %d", i, cap[n], cap[n + 1]);
        if (i >= rc || cap[n] < 0) {
            lua_pushboolean(L, 0);

        } else {
            lua_pushlstring(L, (char *) &subj.data[cap[n]],
                            cap[n + 1] - cap[n]);

            dd("pushing capture %s at %d", lua_tostring(L, -1), (int) i);
        }

        lua_rawseti(L, -2, (int) i);
    }

    if (name_count > 0) {
        ngx_http_lua_re_collect_named_captures(L, lua_gettop(L), name_table,
                                               name_count, name_entry_size,
                                               ctx->flags, &subj);
    }

    offset = cap[1];
    if (offset == cap[0]) {
        offset++;
    }

    if (offset > (ssize_t) subj.len) {
        offset = -1;

        if (!(ctx->flags & NGX_LUA_RE_COMPILE_ONCE)) {
            if (ctx->regex_sd) {
                ngx_http_lua_regex_free_study_data(r->pool, ctx->regex_sd);
                ctx->regex_sd = NULL;
            }

            ngx_pfree(r->pool, cap);
        }
    }

    lua_pushinteger(L, offset);
    lua_replace(L, lua_upvalueindex(3));

    return 1;

error:

    lua_pushinteger(L, -1);
    lua_replace(L, lua_upvalueindex(3));

    if (!(ctx->flags & NGX_LUA_RE_COMPILE_ONCE)) {
        if (ctx->regex_sd) {
            ngx_http_lua_regex_free_study_data(r->pool, ctx->regex_sd);
            ctx->regex_sd = NULL;
        }

        ngx_pfree(r->pool, cap);
    }

    lua_pushnil(L);
    lua_pushstring(L, msg);
    return 2;
}


static ngx_uint_t
ngx_http_lua_ngx_re_parse_opts(lua_State *L, ngx_http_lua_regex_compile_t *re,
    ngx_str_t *opts, int narg)
{
    u_char          *p;
    const char      *msg;
    ngx_uint_t       flags;

    flags = 0;
    p = opts->data;

    while (*p != '\0') {
        switch (*p) {
            case 'i':
                re->options |= NGX_REGEX_CASELESS;
                break;

            case 's':
                re->options |= PCRE_DOTALL;
                break;

            case 'm':
                re->options |= PCRE_MULTILINE;
                break;

            case 'u':
                re->options |= PCRE_UTF8;
                break;

            case 'U':
                re->options |= PCRE_UTF8;
                flags |= NGX_LUA_RE_NO_UTF8_CHECK;
                break;

            case 'x':
                re->options |= PCRE_EXTENDED;
                break;

            case 'o':
                flags |= NGX_LUA_RE_COMPILE_ONCE;
                break;

            case 'j':
                flags |= NGX_LUA_RE_MODE_JIT;
                break;

            case 'd':
                flags |= NGX_LUA_RE_MODE_DFA;
                break;

            case 'a':
                re->options |= PCRE_ANCHORED;
                break;

#if (PCRE_MAJOR > 8) || (PCRE_MAJOR == 8 && PCRE_MINOR >= 12)
            case 'D':
                re->options |= PCRE_DUPNAMES;
                flags |= NGX_LUA_RE_MODE_DUPNAMES;
                break;

            case 'J':
                re->options |= PCRE_JAVASCRIPT_COMPAT;
                break;
#endif

            default:
                msg = lua_pushfstring(L, "unknown flag \"%c\" (flags \"%s\")",
                                      *p, opts->data);
                return luaL_argerror(L, narg, msg);
        }

        p++;
    }

    /* pcre does not support JIT for DFA mode yet,
     * so if DFA mode is specified, we turn off JIT automatically
     * */
    if ((flags & NGX_LUA_RE_MODE_JIT) && (flags & NGX_LUA_RE_MODE_DFA)) {
        flags &= ~NGX_LUA_RE_MODE_JIT;
    }

    return flags;
}


static int
ngx_http_lua_ngx_re_sub(lua_State *L)
{
    return ngx_http_lua_ngx_re_sub_helper(L, 0 /* global */);
}


static int
ngx_http_lua_ngx_re_gsub(lua_State *L)
{
    return ngx_http_lua_ngx_re_sub_helper(L, 1 /* global */);
}


static int
ngx_http_lua_ngx_re_sub_helper(lua_State *L, unsigned global)
{
    ngx_http_lua_regex_t        *re;
    ngx_http_request_t          *r;
    ngx_str_t                    subj;
    ngx_str_t                    pat;
    ngx_str_t                    opts;
    ngx_str_t                    tpl;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_pool_t                  *pool, *old_pool;
    const char                  *msg;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    ngx_int_t                    i;
    int                          nargs;
    int                         *cap = NULL;
    int                          ovecsize;
    int                          type;
    unsigned                     func;
    int                          offset;
    int                          cp_offset;
    size_t                       count;
    luaL_Buffer                  luabuf;
    ngx_int_t                    flags;
    u_char                      *p;
    u_char                       errstr[NGX_MAX_CONF_ERRSTR + 1];
    pcre_extra                  *sd = NULL;
    int                          name_entry_size = 0, name_count;
    u_char                      *name_table = NULL;
    int                          exec_opts;

    ngx_http_lua_regex_compile_t               re_comp;
    ngx_http_lua_complex_value_t              *ctpl = NULL;
    ngx_http_lua_compile_complex_value_t       ccv;

    nargs = lua_gettop(L);

    if (nargs != 3 && nargs != 4) {
        return luaL_error(L, "expecting three or four arguments, but got %d",
                          nargs);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    subj.data = (u_char *) luaL_checklstring(L, 1, &subj.len);
    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);

    func = 0;

    type = lua_type(L, 3);
    switch (type) {
        case LUA_TFUNCTION:
            func = 1;
            tpl.len = 0;
            tpl.data = (u_char *) "";
            break;

        case LUA_TNUMBER:
        case LUA_TSTRING:
            tpl.data = (u_char *) lua_tolstring(L, 3, &tpl.len);
            break;

        default:
            msg = lua_pushfstring(L, "string, number, or function expected, "
                                  "got %s", lua_typename(L, type));
            return luaL_argerror(L, 3, msg);
    }

    ngx_memzero(&re_comp, sizeof(ngx_http_lua_regex_compile_t));

    if (nargs == 4) {
        opts.data = (u_char *) luaL_checklstring(L, 4, &opts.len);
        lua_pop(L, 1);

    } else { /* nargs == 3 */
        opts.data = (u_char *) "";
        opts.len = 0;
    }

    /* stack: subj regex repl */

    re_comp.options = 0;

    flags = ngx_http_lua_ngx_re_parse_opts(L, &re_comp, &opts, 4);

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    if (flags & NGX_LUA_RE_COMPILE_ONCE) {
        pool = lmcf->pool;

        dd("server pool %p", lmcf->pool);

        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              regex_cache_key));
        lua_rawget(L, LUA_REGISTRYINDEX); /* table */

        lua_pushliteral(L, "s");
        lua_pushinteger(L, tpl.len);
        lua_pushliteral(L, ":");
        lua_pushvalue(L, 2);

        if (tpl.len != 0) {
            lua_pushvalue(L, 3);
        }

        dd("options size: %d", (int) sizeof(re_comp.options));

        lua_pushlstring(L, (char *) &re_comp.options, sizeof(re_comp.options));
                /* table regex opts */

        if (tpl.len == 0) {
            lua_concat(L, 5); /* table key */

        } else {
            lua_concat(L, 6); /* table key */
        }

        lua_pushvalue(L, -1); /* table key key */

        dd("regex cache key: %.*s", (int) (pat.len + sizeof(re_comp.options)),
           lua_tostring(L, -1));

        lua_rawget(L, -3); /* table key re */
        re = lua_touserdata(L, -1);

        lua_pop(L, 1); /* table key */

        if (re) {
            ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua regex cache hit for sub regex \"%s\" with "
                           "options \"%s\" and replace \"%s\"",
                           pat.data, opts.data,
                           func ? (u_char *) "<func>" : tpl.data);

            lua_pop(L, 2);

            dd("restoring regex %p, ncaptures %d,  captures %p", re->regex,
               re->ncaptures, re->captures);

            re_comp.regex = re->regex;
            sd = re->regex_sd;
            re_comp.captures = re->ncaptures;
            cap = re->captures;
            ctpl = re->replace;

            if (flags & NGX_LUA_RE_MODE_DFA) {
                ovecsize = 2;

            } else {
                ovecsize = (re->ncaptures + 1) * 3;
            }

            goto exec;
        }

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua regex cache miss for %ssub regex \"%s\" with "
                       "options \"%s\" and replace \"%s\"",
                       global ? "g" : "", pat.data, opts.data,
                       func ? (u_char *) "<func>" : tpl.data);

        if (lmcf->regex_cache_entries >= lmcf->regex_cache_max_entries) {

            if (lmcf->regex_cache_entries == lmcf->regex_cache_max_entries) {
                ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                              "lua exceeding regex cache max entries (%i)",
                              lmcf->regex_cache_max_entries);

                lmcf->regex_cache_entries++;
            }

            pool = r->pool;
            flags &= ~NGX_LUA_RE_COMPILE_ONCE;
        }

    } else {
        pool = r->pool;
    }

    re_comp.pattern = pat;
    re_comp.err.len = NGX_MAX_CONF_ERRSTR;
    re_comp.err.data = errstr;
    re_comp.pool = pool;

    dd("compiling regex");

    ngx_log_debug6(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua compiling %ssub regex \"%s\" with options \"%s\" "
                   "(compile once: %d) (dfa mode: %d) (jit mode: %d)",
                   global ? "g" : "", pat.data, opts.data,
                   (flags & NGX_LUA_RE_COMPILE_ONCE) != 0,
                   (flags & NGX_LUA_RE_MODE_DFA) != 0,
                   (flags & NGX_LUA_RE_MODE_JIT) != 0);

    old_pool = ngx_http_lua_pcre_malloc_init(pool);

    rc = ngx_http_lua_regex_compile(&re_comp);

    ngx_http_lua_pcre_malloc_done(old_pool);

    if (rc != NGX_OK) {
        dd("compile failed");

        lua_pushnil(L);
        lua_pushnil(L);
        lua_pushlstring(L, (char *) re_comp.err.data, re_comp.err.len);
        return 3;
    }

#if LUA_HAVE_PCRE_JIT

    if (flags & NGX_LUA_RE_MODE_JIT) {

        old_pool = ngx_http_lua_pcre_malloc_init(pool);

        sd = pcre_study(re_comp.regex, PCRE_STUDY_JIT_COMPILE, &msg);

        ngx_http_lua_pcre_malloc_done(old_pool);

#   if (NGX_DEBUG)
        dd("sd = %p", sd);

        if (msg != NULL) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre study failed with PCRE_STUDY_JIT_COMPILE: "
                           "%s (%p)", msg, sd);
        }

        if (sd != NULL) {
            int         jitted;

            old_pool = ngx_http_lua_pcre_malloc_init(pool);

            pcre_fullinfo(re_comp.regex, sd, PCRE_INFO_JIT, &jitted);

            ngx_http_lua_pcre_malloc_done(old_pool);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre JIT compiling result: %d", jitted);
        }
#   endif /* NGX_DEBUG */

    } else {

        old_pool = ngx_http_lua_pcre_malloc_init(pool);

        sd = pcre_study(re_comp.regex, 0, &msg);

        ngx_http_lua_pcre_malloc_done(old_pool);

#   if (NGX_DEBUG)
        dd("sd = %p", sd);

        if (msg != NULL) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "pcre_study failed with PCRE_STUDY_JIT_COMPILE: "
                           "%s (%p)", msg, sd);
        }
#   endif /* NGX_DEBUG */
    }

#else  /* LUA_HAVE_PCRE_JIT */

    if (flags & NGX_LUA_RE_MODE_JIT) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "your pcre build does not have JIT support and "
                       "the \"j\" regex option is ignored");
    }

#endif /* LUA_HAVE_PCRE_JIT */

    if (sd && lmcf->regex_match_limit > 0) {
        sd->flags |= PCRE_EXTRA_MATCH_LIMIT;
        sd->match_limit = lmcf->regex_match_limit;
    }

    dd("compile done, captures %d", re_comp.captures);

    if (flags & NGX_LUA_RE_MODE_DFA) {
        ovecsize = 2;
        re_comp.captures = 0;

    } else {
        ovecsize = (re_comp.captures + 1) * 3;
    }

    cap = ngx_palloc(pool, ovecsize * sizeof(int));
    if (cap == NULL) {
        flags &= ~NGX_LUA_RE_COMPILE_ONCE;
        msg = "no memory";
        goto error;
    }

    if (func) {
        ctpl = NULL;

    } else {
        ctpl = ngx_palloc(pool, sizeof(ngx_http_lua_complex_value_t));
        if (ctpl == NULL) {
            flags &= ~NGX_LUA_RE_COMPILE_ONCE;
            msg = "no memory";
            goto error;
        }

        if ((flags & NGX_LUA_RE_COMPILE_ONCE) && tpl.len != 0) {
            /* copy the string buffer pointed to by tpl.data from Lua VM */
            p = ngx_palloc(pool, tpl.len + 1);
            if (p == NULL) {
                flags &= ~NGX_LUA_RE_COMPILE_ONCE;
                msg = "no memory";
                goto error;
            }

            ngx_memcpy(p, tpl.data, tpl.len);
            p[tpl.len] = '\0';

            tpl.data = p;
        }

        ngx_memzero(&ccv, sizeof(ngx_http_lua_compile_complex_value_t));
        ccv.pool = pool;
        ccv.log = r->connection->log;
        ccv.value = &tpl;
        ccv.complex_value = ctpl;

        if (ngx_http_lua_compile_complex_value(&ccv) != NGX_OK) {
            ngx_pfree(pool, cap);
            ngx_pfree(pool, ctpl);

            if ((flags & NGX_LUA_RE_COMPILE_ONCE) && tpl.len != 0) {
                ngx_pfree(pool, tpl.data);
            }

            if (sd) {
                ngx_http_lua_regex_free_study_data(pool, sd);
            }

            ngx_pfree(pool, re_comp.regex);

            lua_pushnil(L);
            lua_pushnil(L);
            lua_pushliteral(L, "failed to compile the replacement template");
            return 3;
        }
    }

    if (flags & NGX_LUA_RE_COMPILE_ONCE) {

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua saving compiled sub regex (%d captures) into "
                       "the cache (entries %i)", re_comp.captures,
                       lmcf->regex_cache_entries);

        re = ngx_palloc(pool, sizeof(ngx_http_lua_regex_t));
        if (re == NULL) {
            msg = "no memory";
            goto error;
        }

        dd("saving regex %p, ncaptures %d,  captures %p", re_comp.regex,
           re_comp.captures, cap);

        re->regex = re_comp.regex;
        re->regex_sd = sd;
        re->ncaptures = re_comp.captures;
        re->captures = cap;
        re->replace = ctpl;

        lua_pushlightuserdata(L, re); /* table key value */
        lua_rawset(L, -3); /* table */
        lua_pop(L, 1);

        if (lmcf) {
            lmcf->regex_cache_entries++;
        }
    }

exec:

    count = 0;
    offset = 0;
    cp_offset = 0;

    if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMECOUNT,
                      &name_count) != 0)
    {
        msg = "cannot acquire named subpattern count";
        goto error;
    }

    if (name_count > 0) {
        if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMEENTRYSIZE,
                          &name_entry_size) != 0)
        {
            msg = "cannot acquire named subpattern entry size";
            goto error;
        }

        if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMETABLE,
                          &name_table) != 0)
        {
            msg = "cannot acquire named subpattern table";
            goto error;
        }
    }

    if (flags & NGX_LUA_RE_NO_UTF8_CHECK) {
        exec_opts = PCRE_NO_UTF8_CHECK;

    } else {
        exec_opts = 0;
    }

    for (;;) {
        if (flags & NGX_LUA_RE_MODE_DFA) {

#if LUA_HAVE_PCRE_DFA

            int ws[NGX_LUA_RE_DFA_MODE_WORKSPACE_COUNT];
            rc = ngx_http_lua_regex_dfa_exec(re_comp.regex, sd, &subj,
                                             offset, cap, ovecsize, ws,
                                             sizeof(ws)/sizeof(ws[0]),
                                             exec_opts);

#else /* LUA_HAVE_PCRE_DFA */

            msg = "at least pcre 6.0 is required for the DFA mode";
            goto error;

#endif /* LUA_HAVE_PCRE_DFA */

        } else {
            rc = ngx_http_lua_regex_exec(re_comp.regex, sd, &subj, offset, cap,
                                         ovecsize, exec_opts);
        }

        if (rc == NGX_REGEX_NO_MATCHED) {
            break;
        }

        if (rc < 0) {
            msg = lua_pushfstring(L, ngx_regex_exec_n " failed: %d",
                                  (int) rc);
            goto error;
        }

        if (rc == 0) {
            if (flags & NGX_LUA_RE_MODE_DFA) {
                rc = 1;

            } else {
                msg = "capture size too small";
                goto error;
            }
        }

        dd("rc = %d", (int) rc);

        count++;

        if (count == 1) {
            luaL_buffinit(L, &luabuf);
        }

        if (func) {
            lua_pushvalue(L, 3);

            lua_createtable(L, re_comp.captures || 1 /* narr */,
                            name_count /* nrec */);

            for (i = 0, n = 0; i <= re_comp.captures; i++, n += 2) {
                dd("capture %d: %d %d", (int) i, cap[n], cap[n + 1]);
                if (i >= rc || cap[n] < 0) {
                    lua_pushboolean(L, 0);

                } else {
                    lua_pushlstring(L, (char *) &subj.data[cap[n]],
                                    cap[n + 1] - cap[n]);

                    dd("pushing capture %s at %d", lua_tostring(L, -1),
                       (int) i);
                }

                lua_rawseti(L, -2, (int) i);
            }

            if (name_count > 0) {
                ngx_http_lua_re_collect_named_captures(L, lua_gettop(L),
                                                       name_table,
                                                       name_count,
                                                       name_entry_size,
                                                       flags, &subj);
            }

            dd("stack size at call: %d", lua_gettop(L));

            lua_call(L, 1 /* nargs */, 1 /* nresults */);
            type = lua_type(L, -1);
            switch (type) {
                case LUA_TNUMBER:
                case LUA_TSTRING:
                    tpl.data = (u_char *) lua_tolstring(L, -1, &tpl.len);
                    break;

                default:
                    msg = lua_pushfstring(L, "string or number expected to be "
                                          "returned by the replace "
                                          "function, got %s",
                                          lua_typename(L, type));
                    return luaL_argerror(L, 3, msg);
            }

            lua_insert(L, 1);

            luaL_addlstring(&luabuf, (char *) &subj.data[cp_offset],
                            cap[0] - cp_offset);

            luaL_addlstring(&luabuf, (char *) tpl.data, tpl.len);

            lua_remove(L, 1);

            cp_offset = cap[1];
            offset = cp_offset;
            if (offset == cap[0]) {
                offset++;
                if (offset > (ssize_t) subj.len) {
                    break;
                }
            }

            if (global) {
                continue;
            }

            break;
        }

        rc = ngx_http_lua_complex_value(r, &subj, cp_offset, rc, cap, ctpl,
                                        &luabuf);

        if (rc != NGX_OK) {
            msg = lua_pushfstring(L, "failed to eval the template for "
                                  "replacement: \"%s\"", tpl.data);
            goto error;
        }

        cp_offset = cap[1];
        offset = cp_offset;
        if (offset == cap[0]) {
            offset++;
            if (offset > (ssize_t) subj.len) {
                break;
            }
        }

        if (global) {
            continue;
        }

        break;
    }

    if (count == 0) {
        dd("no match, just the original subject");
        lua_settop(L, 1);

    } else {
        if (offset < (int) subj.len) {
            dd("adding trailer: %s (len %d)", &subj.data[cp_offset],
               (int) (subj.len - cp_offset));


            luaL_addlstring(&luabuf, (char *) &subj.data[cp_offset],
                            subj.len - cp_offset);
        }

        luaL_pushresult(&luabuf);

        dd("the dst string: %s", lua_tostring(L, -1));
    }

    if (!(flags & NGX_LUA_RE_COMPILE_ONCE)) {
        if (sd) {
            ngx_http_lua_regex_free_study_data(pool, sd);
        }

        if (re_comp.regex) {
            ngx_pfree(pool, re_comp.regex);
        }

        if (ctpl) {
            ngx_pfree(pool, ctpl);
        }

        if (cap) {
            ngx_pfree(pool, cap);
        }
    }

    lua_pushinteger(L, count);
    return 2;

error:

    if (!(flags & NGX_LUA_RE_COMPILE_ONCE)) {
        if (sd) {
            ngx_http_lua_regex_free_study_data(pool, sd);
        }

        if (re_comp.regex) {
            ngx_pfree(pool, re_comp.regex);
        }

        if (ctpl) {
            ngx_pfree(pool, ctpl);
        }

        if (cap) {
            ngx_pfree(pool, cap);
        }
    }

    lua_pushnil(L);
    lua_pushnil(L);
    lua_pushstring(L, msg);
    return 3;
}


ngx_int_t
ngx_http_lua_ffi_set_jit_stack_size(int size, u_char *errstr,
    size_t *errstr_size)
{
#if LUA_HAVE_PCRE_JIT

    ngx_http_lua_main_conf_t    *lmcf;
    ngx_pool_t                  *pool, *old_pool;

    lmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle,
                                               ngx_http_lua_module);

    if (size < NGX_LUA_RE_MIN_JIT_STACK_SIZE) {
        size = NGX_LUA_RE_MIN_JIT_STACK_SIZE;
    }

    pool = lmcf->pool;

    dd("server pool %p", lmcf->pool);

    if (lmcf->jit_stack) {
        old_pool = ngx_http_lua_pcre_malloc_init(pool);

        pcre_jit_stack_free(lmcf->jit_stack);

        ngx_http_lua_pcre_malloc_done(old_pool);
    }

    old_pool = ngx_http_lua_pcre_malloc_init(pool);

    lmcf->jit_stack = pcre_jit_stack_alloc(NGX_LUA_RE_MIN_JIT_STACK_SIZE,
                                           size);

    ngx_http_lua_pcre_malloc_done(old_pool);

    if (lmcf->jit_stack == NULL) {
        *errstr_size = ngx_snprintf(errstr, *errstr_size,
                                    "pcre jit stack allocation failed")
                       - errstr;
        return NGX_ERROR;
    }

    return NGX_OK;

#else  /* LUA_HAVE_PCRE_JIT */

    *errstr_size = ngx_snprintf(errstr, *errstr_size,
                                "no pcre jit support found") - errstr;
    return NGX_ERROR;

#endif /* LUA_HAVE_PCRE_JIT */
}


void
ngx_http_lua_inject_regex_api(lua_State *L)
{
    /* ngx.re */

    lua_createtable(L, 0, 5 /* nrec */);    /* .re */

    lua_pushcfunction(L, ngx_http_lua_ngx_re_find);
    lua_setfield(L, -2, "find");

    lua_pushcfunction(L, ngx_http_lua_ngx_re_match);
    lua_setfield(L, -2, "match");

    lua_pushcfunction(L, ngx_http_lua_ngx_re_gmatch);
    lua_setfield(L, -2, "gmatch");

    lua_pushcfunction(L, ngx_http_lua_ngx_re_sub);
    lua_setfield(L, -2, "sub");

    lua_pushcfunction(L, ngx_http_lua_ngx_re_gsub);
    lua_setfield(L, -2, "gsub");

    lua_setfield(L, -2, "re");
}


static void
ngx_http_lua_regex_free_study_data(ngx_pool_t *pool, pcre_extra *sd)
{
    ngx_pool_t              *old_pool;

    old_pool = ngx_http_lua_pcre_malloc_init(pool);

#if LUA_HAVE_PCRE_JIT
    pcre_free_study(sd);
#else
    pcre_free(sd);
#endif

    ngx_http_lua_pcre_malloc_done(old_pool);
}


static ngx_int_t
ngx_http_lua_regex_compile(ngx_http_lua_regex_compile_t *rc)
{
    int           n, erroff;
    char         *p;
    const char   *errstr;
    pcre         *re;
    ngx_pool_t   *old_pool;

    old_pool = ngx_http_lua_pcre_malloc_init(rc->pool);

    re = pcre_compile((const char *) rc->pattern.data, (int) rc->options,
                      &errstr, &erroff, NULL);

    ngx_http_lua_pcre_malloc_done(old_pool);

    if (re == NULL) {
        if ((size_t) erroff == rc->pattern.len) {
            rc->err.len = ngx_snprintf(rc->err.data, rc->err.len,
                                       "pcre_compile() failed: %s in \"%V\"",
                                      errstr, &rc->pattern)
                         - rc->err.data;

        } else {
            rc->err.len = ngx_snprintf(rc->err.data, rc->err.len,
                                       "pcre_compile() failed: %s in \"%V\" "
                                       "at \"%s\"", errstr, &rc->pattern,
                                       rc->pattern.data + erroff)
                         - rc->err.data;
        }

        return NGX_ERROR;
    }

    rc->regex = re;

#if 1
    n = pcre_fullinfo(re, NULL, PCRE_INFO_CAPTURECOUNT, &rc->captures);
    if (n < 0) {
        p = "pcre_fullinfo(\"%V\", PCRE_INFO_CAPTURECOUNT) failed: %d";
        goto failed;
    }
#endif

    return NGX_OK;

failed:

    rc->err.len = ngx_snprintf(rc->err.data, rc->err.len, p, &rc->pattern, n)
                  - rc->err.data;
    return NGX_OK;
}


static void
ngx_http_lua_ngx_re_gmatch_cleanup(void *data)
{
    ngx_http_lua_regex_ctx_t    *ctx = data;

    if (ctx) {
        if (ctx->regex_sd) {
            ngx_http_lua_regex_free_study_data(ctx->request->pool,
                                               ctx->regex_sd);
            ctx->regex_sd = NULL;
        }

        if (ctx->cleanup) {
            *ctx->cleanup = NULL;
            ctx->cleanup = NULL;
        }

        ctx->request = NULL;
    }

    return;
}


static int
ngx_http_lua_ngx_re_gmatch_gc(lua_State *L)
{
    ngx_http_lua_regex_ctx_t    *ctx;

    ctx = lua_touserdata(L, 1);

    if (ctx && ctx->cleanup) {
        ngx_http_lua_ngx_re_gmatch_cleanup(ctx);
    }

    return 0;
}


static void
ngx_http_lua_re_collect_named_captures(lua_State *L, int res_tb_idx,
    u_char *name_table, int name_count, int name_entry_size, unsigned flags,
    ngx_str_t *subj)
{
    int              i, n;
    size_t           len;
    u_char          *name_entry;
    char            *name;

    for (i = 0; i < name_count; i++) {
        dd("top: %d", lua_gettop(L));

        name_entry = &name_table[i * name_entry_size];
        n = (name_entry[0] << 8) | name_entry[1];
        name = (char *) &name_entry[2];

        lua_rawgeti(L, -1, n);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            continue;
        }

        if (flags & NGX_LUA_RE_MODE_DUPNAMES) {
            /* unmatched groups are not stored in tables in DUPNAMES mode */
            if (!lua_toboolean(L, -1)) {
                lua_pop(L, 1);
                continue;
            }

            lua_getfield(L, -2, name); /* big_tb cap small_tb */

            if (lua_isnil(L, -1)) {
                lua_pop(L, 1);

                /* assuming named submatches are usually unique */
                lua_createtable(L, 1 /* narr */, 0 /* nrec */);
                lua_pushstring(L, name);
                lua_pushvalue(L, -2); /* big_tb cap small_tb key small_tb */
                lua_rawset(L, res_tb_idx); /* big_tb cap small_tb */
                len = 0;

            } else {
                len = lua_objlen(L, -1);
            }

            lua_pushvalue(L, -2); /* big_tb cap small_tb cap */
            lua_rawseti(L, -2, (int) len + 1); /* big_tb cap small_tb */
            lua_pop(L, 2);

        } else {
            lua_pushstring(L, name); /* big_tb cap key */
            lua_pushvalue(L, -2); /* big_tb cap key cap */
            lua_rawset(L, res_tb_idx); /* big_tb cap */
            lua_pop(L, 1);
        }

        dd("top 2: %d", lua_gettop(L));
    }
}


#ifndef NGX_LUA_NO_FFI_API
ngx_http_lua_regex_t *
ngx_http_lua_ffi_compile_regex(const unsigned char *pat, size_t pat_len,
    int flags, int pcre_opts, u_char *errstr,
    size_t errstr_size)
{
    int                     *cap = NULL, ovecsize;
    u_char                  *p;
    ngx_int_t                rc;
    const char              *msg;
    ngx_pool_t              *pool, *old_pool;
    pcre_extra              *sd = NULL;
    ngx_http_lua_regex_t    *re;

    ngx_http_lua_main_conf_t         *lmcf;
    ngx_http_lua_regex_compile_t      re_comp;

    pool = ngx_create_pool(512, ngx_cycle->log);
    if (pool == NULL) {
        msg = "no memory";
        goto error;
    }

    pool->log = (ngx_log_t *) &ngx_cycle->new_log;

    re = ngx_palloc(pool, sizeof(ngx_http_lua_regex_t));
    if (re == NULL) {
        ngx_destroy_pool(pool);
        pool = NULL;
        msg = "no memory";
        goto error;
    }

    re->pool = pool;

    re_comp.options      = pcre_opts;
    re_comp.pattern.data = (u_char *) pat;
    re_comp.pattern.len  = pat_len;
    re_comp.err.len      = errstr_size - 1;
    re_comp.err.data     = errstr;
    re_comp.pool         = pool;

    old_pool = ngx_http_lua_pcre_malloc_init(pool);
    rc = ngx_http_lua_regex_compile(&re_comp);
    ngx_http_lua_pcre_malloc_done(old_pool);

    if (rc != NGX_OK) {
        re_comp.err.data[re_comp.err.len] = '\0';
        msg = (char *) re_comp.err.data;
        goto error;
    }

    lmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle,
                                               ngx_http_lua_module);

#if (LUA_HAVE_PCRE_JIT)

    if (flags & NGX_LUA_RE_MODE_JIT) {

        old_pool = ngx_http_lua_pcre_malloc_init(pool);
        sd = pcre_study(re_comp.regex, PCRE_STUDY_JIT_COMPILE, &msg);
        ngx_http_lua_pcre_malloc_done(old_pool);

#   if (NGX_DEBUG)
        if (msg != NULL) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "pcre study failed with PCRE_STUDY_JIT_COMPILE: "
                           "%s (%p)", msg, sd);
        }

        if (sd != NULL) {
            int         jitted;

            old_pool = ngx_http_lua_pcre_malloc_init(pool);

            pcre_fullinfo(re_comp.regex, sd, PCRE_INFO_JIT, &jitted);

            ngx_http_lua_pcre_malloc_done(old_pool);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "pcre JIT compiling result: %d", jitted);
        }
#   endif /* !(NGX_DEBUG) */

    } else {
        old_pool = ngx_http_lua_pcre_malloc_init(pool);
        sd = pcre_study(re_comp.regex, 0, &msg);
        ngx_http_lua_pcre_malloc_done(old_pool);
    }

    if (sd && lmcf->jit_stack) {
        pcre_assign_jit_stack(sd, NULL, lmcf->jit_stack);
    }

#endif /* LUA_HAVE_PCRE_JIT */

    if (sd && lmcf && lmcf->regex_match_limit > 0) {
        sd->flags |= PCRE_EXTRA_MATCH_LIMIT;
        sd->match_limit = lmcf->regex_match_limit;
    }

    if (flags & NGX_LUA_RE_MODE_DFA) {
        ovecsize = 2;
        re_comp.captures = 0;

    } else {
        ovecsize = (re_comp.captures + 1) * 3;
    }

    dd("allocating cap with size: %d", (int) ovecsize);

    cap = ngx_palloc(pool, ovecsize * sizeof(int));
    if (cap == NULL) {
        msg = "no memory";
        goto error;
    }

    if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMECOUNT,
                      &re->name_count) != 0)
    {
        msg = "cannot acquire named subpattern count";
        goto error;
    }

    if (re->name_count > 0) {
        if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMEENTRYSIZE,
                          &re->name_entry_size) != 0)
        {
            msg = "cannot acquire named subpattern entry size";
            goto error;
        }

        if (pcre_fullinfo(re_comp.regex, NULL, PCRE_INFO_NAMETABLE,
                          &re->name_table) != 0)
        {
            msg = "cannot acquire named subpattern table";
            goto error;
        }
    }

    re->regex = re_comp.regex;
    re->regex_sd = sd;
    re->ncaptures = re_comp.captures;
    re->captures = cap;
    re->replace = NULL;

    /* only for (stap) debugging, the pointer might be invalid when the
     * string is collected later on.... */
    re->pattern = pat;

    return re;

error:

    p = ngx_snprintf(errstr, errstr_size - 1, "%s", msg);
    *p = '\0';

    if (sd) {
        ngx_http_lua_regex_free_study_data(pool, sd);
    }

    if (pool) {
        ngx_destroy_pool(pool);
    }

    return NULL;
}


int
ngx_http_lua_ffi_exec_regex(ngx_http_lua_regex_t *re, int flags,
    const u_char *s, size_t len, int pos)
{
    int             rc, ovecsize, exec_opts, *cap;
    ngx_str_t       subj;
    pcre_extra     *sd;

    cap = re->captures;
    sd = re->regex_sd;

    if (flags & NGX_LUA_RE_MODE_DFA) {
        ovecsize = 2;
        re->ncaptures = 0;

    } else {
        ovecsize = (re->ncaptures + 1) * 3;
    }

    if (flags & NGX_LUA_RE_NO_UTF8_CHECK) {
        exec_opts = PCRE_NO_UTF8_CHECK;

    } else {
        exec_opts = 0;
    }

    subj.data = (u_char *) s;
    subj.len = len;

    if (flags & NGX_LUA_RE_MODE_DFA) {

#if LUA_HAVE_PCRE_DFA

        int ws[NGX_LUA_RE_DFA_MODE_WORKSPACE_COUNT];
        rc = ngx_http_lua_regex_dfa_exec(re->regex, sd, &subj,
                                         (int) pos, cap, ovecsize, ws,
                                         sizeof(ws)/sizeof(ws[0]), exec_opts);

#else

        return PCRE_ERROR_BADOPTION;

#endif /* LUA_HAVE_PCRE_DFA */

    } else {
        rc = ngx_http_lua_regex_exec(re->regex, sd, &subj, (int) pos, cap,
                                     ovecsize, exec_opts);
    }

    return rc;
}


void
ngx_http_lua_ffi_destroy_regex(ngx_http_lua_regex_t *re)
{
    ngx_pool_t                  *old_pool;

    dd("destroy regex called");

    if (re == NULL || re->pool == NULL) {
        return;
    }

    if (re->regex_sd) {
        old_pool = ngx_http_lua_pcre_malloc_init(re->pool);
#if LUA_HAVE_PCRE_JIT
        pcre_free_study(re->regex_sd);
#else
        pcre_free(re->regex_sd);
#endif
        ngx_http_lua_pcre_malloc_done(old_pool);
        re->regex_sd = NULL;
    }

    ngx_destroy_pool(re->pool);
}


int
ngx_http_lua_ffi_compile_replace_template(ngx_http_lua_regex_t *re,
    const u_char *replace_data, size_t replace_len)
{
    ngx_int_t                                rc;
    ngx_str_t                                tpl;
    ngx_http_lua_complex_value_t            *ctpl;
    ngx_http_lua_compile_complex_value_t     ccv;

    ctpl = ngx_palloc(re->pool, sizeof(ngx_http_lua_complex_value_t));
    if (ctpl == NULL) {
        return NGX_ERROR;
    }

    if (replace_len != 0) {
        /* copy the string buffer pointed to by tpl.data from Lua VM */
        tpl.data = ngx_palloc(re->pool, replace_len + 1);
        if (tpl.data == NULL) {
            return NGX_ERROR;
        }

        ngx_memcpy(tpl.data, replace_data, replace_len);
        tpl.data[replace_len] = '\0';

    } else {
        tpl.data = (u_char *) replace_data;
    }

    tpl.len = replace_len;

    ngx_memzero(&ccv, sizeof(ngx_http_lua_compile_complex_value_t));
    ccv.pool = re->pool;
    ccv.log = ngx_cycle->log;
    ccv.value = &tpl;
    ccv.complex_value = ctpl;

    rc = ngx_http_lua_compile_complex_value(&ccv);

    re->replace = ctpl;

    return rc;
}


ngx_http_lua_script_engine_t *
ngx_http_lua_ffi_create_script_engine(void)
{
    return ngx_calloc(sizeof(ngx_http_lua_script_engine_t), ngx_cycle->log);
}


void
ngx_http_lua_ffi_init_script_engine(ngx_http_lua_script_engine_t *e,
    const unsigned char *subj, ngx_http_lua_regex_t *compiled, int count)
{
    e->log = ngx_cycle->log;
    e->ncaptures = count * 2;
    e->captures = compiled->captures;
    e->captures_data = (u_char *) subj;
}


void
ngx_http_lua_ffi_destroy_script_engine(ngx_http_lua_script_engine_t *e)
{
    ngx_free(e);
}


size_t
ngx_http_lua_ffi_script_eval_len(ngx_http_lua_script_engine_t *e,
    ngx_http_lua_complex_value_t *val)
{
    size_t          len;

    ngx_http_lua_script_len_code_pt   lcode;

    e->ip = val->lengths;
    len = 0;

    while (*(uintptr_t *) e->ip) {
        lcode = *(ngx_http_lua_script_len_code_pt *) e->ip;
        len += lcode(e);
    }

    return len;
}


void
ngx_http_lua_ffi_script_eval_data(ngx_http_lua_script_engine_t *e,
    ngx_http_lua_complex_value_t *val, u_char *dst)
{
    ngx_http_lua_script_code_pt       code;

    e->ip = val->values;
    e->pos = dst;

    while (*(uintptr_t *) e->ip) {
        code = *(ngx_http_lua_script_code_pt *) e->ip;
        code(e);
    }
}


uint32_t
ngx_http_lua_ffi_max_regex_cache_size(void)
{
    ngx_http_lua_main_conf_t    *lmcf;
    lmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle,
                                               ngx_http_lua_module);
    if (lmcf == NULL) {
        return 0;
    }
    return (uint32_t) lmcf->regex_cache_max_entries;
}
#endif /* NGX_LUA_NO_FFI_API */


#endif /* NGX_PCRE */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
