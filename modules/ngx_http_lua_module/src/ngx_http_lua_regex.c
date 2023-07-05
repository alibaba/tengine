
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#if (NGX_PCRE)

#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_script.h"
#include "ngx_http_lua_util.h"


#if (PCRE_MAJOR >= 6)
#   define LUA_HAVE_PCRE_DFA 1
#else
#   define LUA_HAVE_PCRE_DFA 0
#endif


#define NGX_LUA_RE_MODE_DFA          (1<<1)
#define NGX_LUA_RE_MODE_JIT          (1<<2)
#define NGX_LUA_RE_NO_UTF8_CHECK     (1<<4)

#define NGX_LUA_RE_DFA_MODE_WORKSPACE_COUNT (100)

#define NGX_LUA_RE_MIN_JIT_STACK_SIZE 32 * 1024


typedef struct {
    ngx_pool_t                   *pool;
    u_char                       *name_table;
    int                           name_count;
    int                           name_entry_size;

    int                           ncaptures;
    int                          *captures;

    pcre                         *regex;
    pcre_extra                   *regex_sd;

    ngx_http_lua_complex_value_t *replace;

    /* only for (stap) debugging, and may be an invalid pointer */
    const u_char                 *pattern;
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
    ngx_http_request_t      *request;
    pcre                    *regex;
    pcre_extra              *regex_sd;
    int                      ncaptures;
    int                     *captures;
    int                      captures_len;
    uint8_t                  flags;
} ngx_http_lua_regex_ctx_t;


static void ngx_http_lua_regex_free_study_data(ngx_pool_t *pool,
    pcre_extra *sd);
static ngx_int_t ngx_http_lua_regex_compile(ngx_http_lua_regex_compile_t *rc);


#define ngx_http_lua_regex_exec(re, e, s, start, captures, size, opts)       \
    pcre_exec(re, e, (const char *) (s)->data, (s)->len, start, opts,        \
              captures, size)


#define ngx_http_lua_regex_dfa_exec(re, e, s, start, captures, size, ws,     \
                                    wscount, opts)                           \
    pcre_dfa_exec(re, e, (const char *) (s)->data, (s)->len, start, opts,    \
                  captures, size, ws, wscount)


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


ngx_int_t
ngx_http_lua_ffi_set_jit_stack_size(int size, u_char *errstr,
    size_t *errstr_size)
{
#if LUA_HAVE_PCRE_JIT

    ngx_http_lua_main_conf_t    *lmcf;
    ngx_pool_t                  *pool, *old_pool;

    lmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle,
                                               ngx_http_lua_module);

    ngx_http_lua_assert(lmcf != NULL);

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
                                "no pcre jit support found")
                   - errstr;
    return NGX_ERROR;

#endif /* LUA_HAVE_PCRE_JIT */
}


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

    ngx_http_lua_assert(lmcf != NULL);

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

    if (sd
        && lmcf && lmcf->regex_match_limit > 0
        && !(flags & NGX_LUA_RE_MODE_DFA))
    {
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


const char *
ngx_http_lua_ffi_pcre_version(void)
{
    return pcre_version();
}


#endif /* NGX_PCRE */


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
