
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_accessby.h"
#include "ngx_http_lua_server_rewriteby.h"
#include "ngx_http_lua_rewriteby.h"
#include "ngx_http_lua_logby.h"
#include "ngx_http_lua_headerfilterby.h"
#include "ngx_http_lua_bodyfilterby.h"
#include "ngx_http_lua_initby.h"
#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_exitworkerby.h"
#include "ngx_http_lua_shdict.h"
#include "ngx_http_lua_ssl_certby.h"
#include "ngx_http_lua_lex.h"
#include "api/ngx_http_lua_api.h"
#include "ngx_http_lua_log_ringbuf.h"
#include "ngx_http_lua_log.h"


/* the max length is 60, after deducting the fixed four characters "=(:)"
 * only 56 left.
 */
#define LJ_CHUNKNAME_MAX_LEN 56


typedef struct ngx_http_lua_block_parser_ctx_s
    ngx_http_lua_block_parser_ctx_t;


#if defined(NDK) && NDK
#include "ngx_http_lua_setby.h"


static ngx_int_t ngx_http_lua_set_by_lua_init(ngx_http_request_t *r);
#endif

static ngx_int_t ngx_http_lua_conf_read_lua_token(ngx_conf_t *cf,
    ngx_http_lua_block_parser_ctx_t *ctx);
static u_char *ngx_http_lua_strlstrn(u_char *s1, u_char *last, u_char *s2,
    size_t n);


struct ngx_http_lua_block_parser_ctx_s {
    ngx_uint_t  start_line;
    int         token_len;
};


enum {
    FOUND_LEFT_CURLY = 0,
    FOUND_RIGHT_CURLY,
    FOUND_LEFT_LBRACKET_STR,
    FOUND_LBRACKET_STR = FOUND_LEFT_LBRACKET_STR,
    FOUND_LEFT_LBRACKET_CMT,
    FOUND_LBRACKET_CMT = FOUND_LEFT_LBRACKET_CMT,
    FOUND_RIGHT_LBRACKET,
    FOUND_COMMENT_LINE,
    FOUND_DOUBLE_QUOTED,
    FOUND_SINGLE_QUOTED,
};


char *
ngx_http_lua_shared_dict(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_lua_main_conf_t   *lmcf = conf;

    ngx_str_t                  *value, name;
    ngx_shm_zone_t             *zone;
    ngx_shm_zone_t            **zp;
    ngx_http_lua_shdict_ctx_t  *ctx;
    ssize_t                     size;

    if (lmcf->shdict_zones == NULL) {
        lmcf->shdict_zones = ngx_palloc(cf->pool, sizeof(ngx_array_t));
        if (lmcf->shdict_zones == NULL) {
            return NGX_CONF_ERROR;
        }

        if (ngx_array_init(lmcf->shdict_zones, cf->pool, 2,
                           sizeof(ngx_shm_zone_t *))
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }
    }

    value = cf->args->elts;

    ctx = NULL;

    if (value[1].len == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid lua shared dict name \"%V\"", &value[1]);
        return NGX_CONF_ERROR;
    }

    name = value[1];

    size = ngx_parse_size(&value[2]);

    if (size <= 8191) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid lua shared dict size \"%V\"", &value[2]);
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_shdict_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->name = name;
    ctx->main_conf = lmcf;
    ctx->log = &cf->cycle->new_log;

    zone = ngx_http_lua_shared_memory_add(cf, &name, (size_t) size,
                                          &ngx_http_lua_module);
    if (zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (zone->data) {
        ctx = zone->data;

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "lua_shared_dict \"%V\" is already defined as "
                           "\"%V\"", &name, &ctx->name);
        return NGX_CONF_ERROR;
    }

    zone->init = ngx_http_lua_shdict_init_zone;
    zone->data = ctx;

    zp = ngx_array_push(lmcf->shdict_zones);
    if (zp == NULL) {
        return NGX_CONF_ERROR;
    }

    *zp = zone;

    lmcf->requires_shm = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_code_cache(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char             *p = conf;
    ngx_flag_t       *fp;
    char             *ret;

    ret = ngx_conf_set_flag_slot(cf, cmd, conf);
    if (ret != NGX_CONF_OK) {
        return ret;
    }

    fp = (ngx_flag_t *) (p + cmd->offset);

    if (!*fp) {
        ngx_conf_log_error(NGX_LOG_ALERT, cf, 0,
                           "lua_code_cache is off; this will hurt "
                           "performance");
    }

    return NGX_CONF_OK;
}


char *
ngx_http_lua_load_resty_core(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                       "lua_load_resty_core is deprecated (the lua-resty-core "
                       "library is required since ngx_lua v0.10.16)");

    return NGX_CONF_OK;
}


char *
ngx_http_lua_package_cpath(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_lua_main_conf_t *lmcf = conf;
    ngx_str_t                *value;

    if (lmcf->lua_cpath.len != 0) {
        return "is duplicate";
    }

    dd("enter");

    value = cf->args->elts;

    lmcf->lua_cpath.len = value[1].len;
    lmcf->lua_cpath.data = value[1].data;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_package_path(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_lua_main_conf_t *lmcf = conf;
    ngx_str_t                *value;

    if (lmcf->lua_path.len != 0) {
        return "is duplicate";
    }

    dd("enter");

    value = cf->args->elts;

    lmcf->lua_path.len = value[1].len;
    lmcf->lua_path.data = value[1].data;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_regex_cache_max_entries(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
#if (NGX_PCRE)
    return ngx_conf_set_num_slot(cf, cmd, conf);
#else
    return NGX_CONF_OK;
#endif
}


char *
ngx_http_lua_regex_match_limit(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
#if (NGX_PCRE)
    return ngx_conf_set_num_slot(cf, cmd, conf);
#else
    return NGX_CONF_OK;
#endif
}


#if defined(NDK) && NDK
char *
ngx_http_lua_set_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_set_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_set_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    size_t               chunkname_len;
    u_char              *chunkname;
    u_char              *cache_key;
    ngx_str_t           *value;
    ngx_str_t            target;
    ndk_set_var_t        filter;

    ngx_http_lua_set_var_data_t     *filter_data;

    /*
     * value[0] = "set_by_lua"
     * value[1] = target variable name
     * value[2] = lua script source to be executed
     * value[3..] = real params
     * */
    value = cf->args->elts;
    target = value[1];

    filter.type = NDK_SET_VAR_MULTI_VALUE_DATA;
    filter.func = cmd->post;
    filter.size = cf->args->nelts - 3;    /*  get number of real params */

    filter_data = ngx_palloc(cf->pool, sizeof(ngx_http_lua_set_var_data_t));
    if (filter_data == NULL) {
        return NGX_CONF_ERROR;
    }

    cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "set_by_lua",
                                                 value[2].data,
                                                 value[2].len);
    if (cache_key == NULL) {
        return NGX_CONF_ERROR;
    }

    chunkname = ngx_http_lua_gen_chunk_name(cf, "set_by_lua",
                                            sizeof("set_by_lua") - 1,
                                            &chunkname_len);
    if (chunkname == NULL) {
        return NGX_CONF_ERROR;
    }

    filter_data->key = cache_key;
    filter_data->chunkname = chunkname;
    filter_data->ref = LUA_REFNIL;
    filter_data->script = value[2];
    filter_data->size = filter.size;

    filter.data = filter_data;

    return ndk_set_var_multi_value_core(cf, &target, &value[3], &filter);
}


char *
ngx_http_lua_set_by_lua_file(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char              *cache_key = NULL;
    ngx_str_t           *value;
    ngx_str_t            target;
    ndk_set_var_t        filter;

    ngx_http_lua_set_var_data_t           *filter_data;
    ngx_http_complex_value_t               cv;
    ngx_http_compile_complex_value_t       ccv;

    /*
     * value[0] = "set_by_lua_file"
     * value[1] = target variable name
     * value[2] = lua script file path to be executed
     * value[3..] = real params
     * */
    value = cf->args->elts;
    target = value[1];

    filter.type = NDK_SET_VAR_MULTI_VALUE_DATA;
    filter.func = cmd->post;
    filter.size = cf->args->nelts - 2;    /*  get number of real params and
                                              lua script */

    filter_data = ngx_palloc(cf->pool, sizeof(ngx_http_lua_set_var_data_t));
    if (filter_data == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
    ccv.cf = cf;
    ccv.value = &value[2];
    ccv.complex_value = &cv;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    if (cv.lengths == NULL) {
        /* no variable found */
        cache_key = ngx_http_lua_gen_file_cache_key(cf, value[2].data,
                                                    value[2].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    filter_data->key = cache_key;
    filter_data->ref = LUA_REFNIL;
    filter_data->size = filter.size;
    filter_data->chunkname = NULL;

    ngx_str_null(&filter_data->script);

    filter.data = filter_data;

    return ndk_set_var_multi_value_core(cf, &target, &value[2], &filter);
}


ngx_int_t
ngx_http_lua_filter_set_by_lua_inline(ngx_http_request_t *r, ngx_str_t *val,
    ngx_http_variable_value_t *v, void *data)
{
    lua_State                   *L;
    ngx_int_t                    rc;

    ngx_http_lua_set_var_data_t     *filter_data = data;

    if (ngx_http_lua_set_by_lua_init(r) != NGX_OK) {
        return NGX_ERROR;
    }

    L = ngx_http_lua_get_lua_vm(r, NULL);

    /*  load Lua inline script (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       filter_data->script.data,
                                       filter_data->script.len,
                                       &filter_data->ref,
                                       filter_data->key,
                                       (const char *) filter_data->chunkname);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    rc = ngx_http_lua_set_by_chunk(L, r, val, v, filter_data->size,
                                   &filter_data->script);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_filter_set_by_lua_file(ngx_http_request_t *r, ngx_str_t *val,
    ngx_http_variable_value_t *v, void *data)
{
    lua_State                   *L;
    ngx_int_t                    rc;
    u_char                      *script_path;
    size_t                       nargs;

    ngx_http_lua_set_var_data_t     *filter_data = data;

    dd("set by lua file");

    if (ngx_http_lua_set_by_lua_init(r) != NGX_OK) {
        return NGX_ERROR;
    }

    filter_data->script.data = v[0].data;
    filter_data->script.len = v[0].len;

    /* skip the lua file path argument */
    v++;
    nargs = filter_data->size - 1;

    dd("script: %.*s", (int) filter_data->script.len, filter_data->script.data);
    dd("nargs: %d", (int) nargs);

    script_path = ngx_http_lua_rebase_path(r->pool, filter_data->script.data,
                                           filter_data->script.len);
    if (script_path == NULL) {
        return NGX_ERROR;
    }

    L = ngx_http_lua_get_lua_vm(r, NULL);

    /*  load Lua script file (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadfile(r->connection->log, L, script_path,
                                     &filter_data->ref,
                                     filter_data->key);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    rc = ngx_http_lua_set_by_chunk(L, r, val, v, nargs, &filter_data->script);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}
#endif /* defined(NDK) && NDK */


char *
ngx_http_lua_rewrite_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_rewrite_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_rewrite_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    size_t                       chunkname_len;
    u_char                      *cache_key = NULL, *chunkname;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->rewrite_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");

        return NGX_CONF_ERROR;
    }

    if (cmd->post == ngx_http_lua_rewrite_handler_inline) {
        chunkname = ngx_http_lua_gen_chunk_name(cf, "rewrite_by_lua",
                                                sizeof("rewrite_by_lua") - 1,
                                                &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "rewrite_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        llcf->rewrite_src.value = value[1];
        llcf->rewrite_chunkname = chunkname;

    } else {
        ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &value[1];
        ccv.complex_value = &llcf->rewrite_src;

        if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (llcf->rewrite_src.lengths == NULL) {
            /* no variable found */
            cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                        value[1].len);
            if (cache_key == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }

    llcf->rewrite_src_key = cache_key;
    llcf->rewrite_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_rewrite = 1;
    lmcf->requires_capture_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_server_rewrite_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf)
{
    char        *rv;
    ngx_conf_t   save;
    save = *cf;
    cf->handler = ngx_http_lua_server_rewrite_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_server_rewrite_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    size_t                       chunkname_len;
    u_char                      *cache_key = NULL, *chunkname;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_srv_conf_t     *lscf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lscf->srv.server_rewrite_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");

        return NGX_CONF_ERROR;
    }

    if (cmd->post == ngx_http_lua_server_rewrite_handler_inline) {
        chunkname =
            ngx_http_lua_gen_chunk_name(cf, "server_rewrite_by_lua",
                                        sizeof("server_rewrite_by_lua") - 1,
                                        &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        cache_key =
            ngx_http_lua_gen_chunk_cache_key(cf, "server_rewrite_by_lua",
                                             value[1].data,
                                             value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        lscf->srv.server_rewrite_src.value = value[1];
        lscf->srv.server_rewrite_chunkname = chunkname;

    } else {
        ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &value[1];
        ccv.complex_value = &lscf->srv.server_rewrite_src;

        if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (lscf->srv.server_rewrite_src.lengths == NULL) {
            /* no variable found */
            cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                        value[1].len);
            if (cache_key == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }

    lscf->srv.server_rewrite_src_key = cache_key;
    lscf->srv.server_rewrite_handler =
                                  (ngx_http_lua_srv_conf_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_server_rewrite = 1;
    lmcf->requires_capture_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_access_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_access_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_access_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    size_t                       chunkname_len;
    u_char                      *cache_key = NULL, *chunkname;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->access_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");

        return NGX_CONF_ERROR;
    }

    if (cmd->post == ngx_http_lua_access_handler_inline) {
        chunkname = ngx_http_lua_gen_chunk_name(cf, "access_by_lua",
                                                sizeof("access_by_lua") - 1,
                                                &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "access_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        llcf->access_src.value = value[1];
        llcf->access_chunkname = chunkname;

    } else {
        ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &value[1];
        ccv.complex_value = &llcf->access_src;

        if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (llcf->access_src.lengths == NULL) {
            /* no variable found */
            cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                        value[1].len);
            if (cache_key == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }

    llcf->access_src_key = cache_key;
    llcf->access_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_access = 1;
    lmcf->requires_capture_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_content_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_content_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_content_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    size_t                       chunkname_len;
    u_char                      *cache_key = NULL, *chunkname;
    ngx_str_t                   *value;
    ngx_http_core_loc_conf_t    *clcf;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->content_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    dd("value[0]: %.*s", (int) value[0].len, value[0].data);
    dd("value[1]: %.*s", (int) value[1].len, value[1].data);

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");
        return NGX_CONF_ERROR;
    }

    if (cmd->post == ngx_http_lua_content_handler_inline) {
        chunkname = ngx_http_lua_gen_chunk_name(cf, "content_by_lua",
                                                sizeof("content_by_lua") - 1,
                                                &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "content_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        llcf->content_src.value = value[1];
        llcf->content_chunkname = chunkname;

    } else {
        ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &value[1];
        ccv.complex_value = &llcf->content_src;

        if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (llcf->content_src.lengths == NULL) {
            /* no variable found */
            cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                        value[1].len);
            if (cache_key == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }

    llcf->content_src_key = cache_key;
    llcf->content_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_capture_filter = 1;

    /*  register location content handler */
    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    if (clcf == NULL) {
        return NGX_CONF_ERROR;
    }

    clcf->handler = ngx_http_lua_content_handler;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_log_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_log_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_log_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    size_t                       chunkname_len;
    u_char                      *cache_key = NULL, *chunkname;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->log_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");

        return NGX_CONF_ERROR;
    }

    if (cmd->post == ngx_http_lua_log_handler_inline) {
        chunkname = ngx_http_lua_gen_chunk_name(cf, "log_by_lua",
                                                sizeof("log_by_lua") - 1,
                                                &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "log_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        llcf->log_src.value = value[1];
        llcf->log_chunkname = chunkname;

    } else {
        ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &value[1];
        ccv.complex_value = &llcf->log_src;

        if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (llcf->log_src.lengths == NULL) {
            /* no variable found */
            cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                        value[1].len);
            if (cache_key == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }

    llcf->log_src_key = cache_key;
    llcf->log_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_log = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_header_filter_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_header_filter_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_header_filter_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    size_t                       chunkname_len;
    u_char                      *cache_key = NULL, *chunkname;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->header_filter_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");
        return NGX_CONF_ERROR;
    }

    if (cmd->post == ngx_http_lua_header_filter_inline) {
        cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "header_filter_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        chunkname = ngx_http_lua_gen_chunk_name(cf, "header_filter_by_lua",
                            sizeof("header_filter_by_lua") - 1, &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        llcf->header_filter_src.value = value[1];
        llcf->header_filter_chunkname = chunkname;

    } else {
        ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &value[1];
        ccv.complex_value = &llcf->header_filter_src;

        if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (llcf->header_filter_src.lengths == NULL) {
            /* no variable found */
            cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                        value[1].len);
            if (cache_key == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }

    llcf->header_filter_src_key = cache_key;
    llcf->header_filter_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_header_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_body_filter_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_body_filter_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_body_filter_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    size_t                       chunkname_len;
    u_char                      *cache_key = NULL, *chunkname;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->body_filter_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");
        return NGX_CONF_ERROR;
    }

    if (cmd->post == ngx_http_lua_body_filter_inline) {
        cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "body_filter_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        chunkname = ngx_http_lua_gen_chunk_name(cf, "body_filter_by_lua",
                              sizeof("body_filter_by_lua") - 1, &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }


        /* Don't eval nginx variables for inline lua code */
        llcf->body_filter_src.value = value[1];
        llcf->body_filter_chunkname = chunkname;

    } else {
        ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &value[1];
        ccv.complex_value = &llcf->body_filter_src;

        if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (llcf->body_filter_src.lengths == NULL) {
            /* no variable found */
            cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                        value[1].len);
            if (cache_key == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }

    llcf->body_filter_src_key = cache_key;
    llcf->body_filter_handler = (ngx_http_output_body_filter_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_body_filter = 1;
    lmcf->requires_header_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_init_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_init_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_init_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf = conf;
    size_t                       chunkname_len;
    u_char                      *chunkname;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lmcf->init_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");
        return NGX_CONF_ERROR;
    }

    lmcf->init_handler = (ngx_http_lua_main_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_init_by_file) {
        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lmcf->init_src.data = name;
        lmcf->init_src.len = ngx_strlen(name);

    } else {
        lmcf->init_src = value[1];

        chunkname = ngx_http_lua_gen_chunk_name(cf, "init_by_lua",
                                                sizeof("init_by_lua") - 1,
                                                &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        lmcf->init_chunkname = chunkname;
    }

    return NGX_CONF_OK;
}


char *
ngx_http_lua_init_worker_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_init_worker_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_init_worker_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf = conf;
    size_t                       chunkname_len;
    u_char                      *chunkname;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lmcf->init_worker_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    lmcf->init_worker_handler = (ngx_http_lua_main_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_init_worker_by_file) {
        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lmcf->init_worker_src.data = name;
        lmcf->init_worker_src.len = ngx_strlen(name);

    } else {
        lmcf->init_worker_src = value[1];

        chunkname = ngx_http_lua_gen_chunk_name(cf, "init_worker_by_lua",
                              sizeof("init_worker_by_lua") - 1, &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        lmcf->init_worker_chunkname = chunkname;
    }

    return NGX_CONF_OK;
}


char *
ngx_http_lua_exit_worker_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_exit_worker_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_exit_worker_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf = conf;
    size_t                       chunkname_len;
    u_char                      *chunkname;

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lmcf->exit_worker_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    lmcf->exit_worker_handler = (ngx_http_lua_main_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_exit_worker_by_file) {
        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lmcf->exit_worker_src.data = name;
        lmcf->exit_worker_src.len = ngx_strlen(name);

    } else {
        lmcf->exit_worker_src = value[1];

        chunkname = ngx_http_lua_gen_chunk_name(cf, "exit_worker_by_lua",
                                                sizeof("exit_worker_by_lua")- 1,
                                                &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        lmcf->exit_worker_chunkname = chunkname;
    }

    return NGX_CONF_OK;
}


#if defined(NDK) && NDK
static ngx_int_t
ngx_http_lua_set_by_lua_init(ngx_http_request_t *r)
{
    lua_State                   *L;
    ngx_http_lua_ctx_t          *ctx;
    ngx_pool_cleanup_t          *cln;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_ERROR;
        }

    } else {
        L = ngx_http_lua_get_lua_vm(r, ctx);
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    if (ctx->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(r->pool, 0);
        if (cln == NULL) {
            return NGX_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup_handler;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_SET;
    return NGX_OK;
}
#endif


u_char *
ngx_http_lua_gen_chunk_name(ngx_conf_t *cf, const char *tag, size_t tag_len,
    size_t *chunkname_len)
{
    u_char      *p, *out;
    size_t       len;
    ngx_uint_t   start_line;
    ngx_str_t   *conf_prefix;
    ngx_str_t   *filename;
    u_char      *filename_end;
    const char  *pre_str = "";
    ngx_uint_t   reserve_len;

    ngx_http_lua_main_conf_t    *lmcf;

    len = sizeof("=(:)") - 1 + tag_len + cf->conf_file->file.name.len
          + NGX_INT64_LEN + 1;

    out = ngx_palloc(cf->pool, len);
    if (out == NULL) {
        return NULL;
    }

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);
    start_line = lmcf->directive_line > 0
        ? lmcf->directive_line : cf->conf_file->line;
    p = ngx_snprintf(out, len, "%d", start_line);
    reserve_len = tag_len + p - out;

    filename = &cf->conf_file->file.name;
    filename_end = filename->data + filename->len;
    if (filename->len > 0) {
        if (filename->len >= 11) {
            p = filename_end - 11;
            if ((*p == '/' || *p == '\\')
                && ngx_memcmp(p, "/nginx.conf", 11) == 0)
            {
                p++; /* now p is nginx.conf */
                goto found;
            }
        }

        conf_prefix = &cf->cycle->conf_prefix;
        p = filename->data + conf_prefix->len;
        if ((conf_prefix->len < filename->len)
            && ngx_memcmp(conf_prefix->data,
                          filename->data, conf_prefix->len) == 0)
        {
            /* files in conf_prefix directory, use the relative path */
            if (filename_end - p + reserve_len > LJ_CHUNKNAME_MAX_LEN) {
                p = filename_end - LJ_CHUNKNAME_MAX_LEN + reserve_len + 3;
                pre_str = "...";
            }

            goto found;
        }
    }

    p = filename->data;

    if (filename->len + reserve_len <= LJ_CHUNKNAME_MAX_LEN) {
        goto found;
    }

    p = filename_end - LJ_CHUNKNAME_MAX_LEN + reserve_len + 3;
    pre_str = "...";

found:


    p = ngx_snprintf(out, len, "=%*s(%s%*s:%d)%Z",
                     tag_len, tag, pre_str, filename_end - p,
                     p, start_line);

    *chunkname_len = p - out - 1;  /* exclude the trailing '\0' byte */

    return out;
}


/* a specialized version of the standard ngx_conf_parse() function */
char *
ngx_http_lua_conf_lua_block_parse(ngx_conf_t *cf, ngx_command_t *cmd)
{
    ngx_http_lua_main_conf_t           *lmcf;
    ngx_http_lua_block_parser_ctx_t     ctx;

    int               level = 1;
    char             *rv;
    u_char           *p;
    size_t            len;
    ngx_str_t        *src, *dst;
    ngx_int_t         rc;
    ngx_uint_t        i, start_line;
    ngx_array_t      *saved;
    enum {
        parse_block = 0,
        parse_param,
    } type;

    if (cf->conf_file->file.fd != NGX_INVALID_FILE) {

        type = parse_block;

    } else {
        type = parse_param;
    }

    saved = cf->args;

    cf->args = ngx_array_create(cf->temp_pool, 4, sizeof(ngx_str_t));
    if (cf->args == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx.token_len = 0;
    start_line = cf->conf_file->line;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);
    lmcf->directive_line = start_line;

    dd("init start line: %d", (int) start_line);

    ctx.start_line = start_line;

    for ( ;; ) {
        rc = ngx_http_lua_conf_read_lua_token(cf, &ctx);

        dd("parser start line: %d", (int) start_line);

        switch (rc) {

        case NGX_ERROR:
            goto done;

        case FOUND_LEFT_CURLY:

            ctx.start_line = cf->conf_file->line;

            if (type == parse_param) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "block directives are not supported "
                                   "in -g option");
                goto failed;
            }

            level++;
            dd("seen block start: level=%d", (int) level);
            break;

        case FOUND_RIGHT_CURLY:

            level--;
            dd("seen block done: level=%d", (int) level);

            if (type != parse_block || level < 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "unexpected \"}\": level %d, "
                                   "starting at line %ui", level,
                                   start_line);
                goto failed;
            }

            if (level == 0) {
                ngx_http_lua_assert(cf->handler);

                src = cf->args->elts;

                for (len = 0, i = 0; i < cf->args->nelts; i++) {
                    len += src[i].len;
                }

                dd("saved nelts: %d", (int) saved->nelts);
                dd("temp nelts: %d", (int) cf->args->nelts);
#if 0
                ngx_http_lua_assert(saved->nelts == 1);
#endif

                dst = ngx_array_push(saved);
                if (dst == NULL) {
                    return NGX_CONF_ERROR;
                }

                dst->len = len;
                dst->len--;  /* skip the trailing '}' block terminator */

                p = ngx_palloc(cf->pool, len);
                if (p == NULL) {
                    return NGX_CONF_ERROR;
                }

                dst->data = p;

                for (i = 0; i < cf->args->nelts; i++) {
                    p = ngx_copy(p, src[i].data, src[i].len);
                }

                p[-1] = '\0';  /* override the last '}' char to null */

                cf->args = saved;

                rv = (*cf->handler)(cf, cmd, cf->handler_conf);
                if (rv == NGX_CONF_OK) {
                    goto done;
                }

                if (rv == NGX_CONF_ERROR) {
                    goto failed;
                }

                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, rv);

                goto failed;
            }

            break;

        case FOUND_LBRACKET_STR:
        case FOUND_LBRACKET_CMT:
        case FOUND_RIGHT_LBRACKET:
        case FOUND_COMMENT_LINE:
        case FOUND_DOUBLE_QUOTED:
        case FOUND_SINGLE_QUOTED:
            break;

        default:

            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "unknown return value from the lexer: %i", rc);
            goto failed;
        }
    }

failed:

    rc = NGX_ERROR;

done:

    lmcf->directive_line = 0;

    if (rc == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_lua_conf_read_lua_token(ngx_conf_t *cf,
    ngx_http_lua_block_parser_ctx_t *ctx)
{
    enum {
        OVEC_SIZE = 2,
    };
    int          i, rc;
    int          ovec[OVEC_SIZE];
    u_char      *start, *p, *q, ch;
    off_t        file_size;
    size_t       len, buf_size;
    ssize_t      n, size;
    ngx_uint_t   start_line;
    ngx_str_t   *word;
    ngx_buf_t   *b;
#if (nginx_version >= 1009002)
    ngx_buf_t   *dump;
#endif

    b = cf->conf_file->buffer;
#if (nginx_version >= 1009002)
    dump = cf->conf_file->dump;
#endif
    start = b->pos;
    start_line = cf->conf_file->line;
    buf_size = b->end - b->start;

    dd("lexer start line: %d", (int) start_line);

    file_size = ngx_file_size(&cf->conf_file->file.info);

    for ( ;; ) {

        if (b->pos >= b->last
            || (b->last - b->pos < (b->end - b->start) / 2
                && cf->conf_file->file.offset < file_size))
        {

            if (cf->conf_file->file.offset >= file_size) {

                cf->conf_file->line = ctx->start_line;

                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "unexpected end of file, expecting "
                                   "terminating characters for lua code "
                                   "block");
                return NGX_ERROR;
            }

            len = b->last - start;

            if (len == buf_size) {

                cf->conf_file->line = start_line;

                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "too long lua code block, probably "
                                   "missing terminating characters");

                return NGX_ERROR;
            }

            if (len) {
                ngx_memmove(b->start, start, len);
            }

            size = (ssize_t) (file_size - cf->conf_file->file.offset);

            if (size > b->end - (b->start + len)) {
                size = b->end - (b->start + len);
            }

            n = ngx_read_file(&cf->conf_file->file, b->start + len, size,
                              cf->conf_file->file.offset);

            if (n == NGX_ERROR) {
                return NGX_ERROR;
            }

            if (n != size) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   ngx_read_file_n " returned "
                                   "only %z bytes instead of %z",
                                   n, size);
                return NGX_ERROR;
            }

            b->pos = b->start + (b->pos - start);
            b->last = b->start + len + n;
            start = b->start;

#if (nginx_version >= 1009002)
            if (dump) {
                dump->last = ngx_cpymem(dump->last, b->start + len, size);
            }
#endif
        }

        rc = ngx_http_lua_lex(b->pos, b->last - b->pos, ovec);

        if (rc < 0) {  /* no match */
            /* alas. the lexer does not yet support streaming processing. need
             * more work below */

            if (cf->conf_file->file.offset >= file_size) {

                cf->conf_file->line = ctx->start_line;

                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "unexpected end of file, expecting "
                                   "terminating characters for lua code "
                                   "block");
                return NGX_ERROR;
            }

            len = b->last - b->pos;

            if (len == buf_size) {

                cf->conf_file->line = start_line;

                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "too long lua code block, probably "
                                   "missing terminating characters");

                return NGX_ERROR;
            }

            if (len) {
                ngx_memmove(b->start, b->pos, len);
            }

            size = (ssize_t) (file_size - cf->conf_file->file.offset);

            if (size > b->end - (b->start + len)) {
                size = b->end - (b->start + len);
            }

            n = ngx_read_file(&cf->conf_file->file, b->start + len, size,
                              cf->conf_file->file.offset);

            if (n == NGX_ERROR) {
                return NGX_ERROR;
            }

            if (n != size) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   ngx_read_file_n " returned "
                                   "only %z bytes instead of %z",
                                   n, size);
                return NGX_ERROR;
            }

            b->pos = b->start + len;
            b->last = b->pos + n;
            start = b->start;

            continue;
        }

        if (rc == FOUND_LEFT_LBRACKET_STR || rc == FOUND_LEFT_LBRACKET_CMT) {

            /* we update the line numbers for best error messages when the
             * closing long bracket is missing */

            for (i = 0; i < ovec[0]; i++) {
                ch = b->pos[i];
                if (ch == LF) {
                    cf->conf_file->line++;
                }
            }

            b->pos += ovec[0];
            ovec[1] -= ovec[0];
            ovec[0] = 0;

            if (rc == FOUND_LEFT_LBRACKET_CMT) {
                p = &b->pos[2];     /* we skip the leading "--" prefix */
                rc = FOUND_LBRACKET_CMT;

            } else {
                p = b->pos;
                rc = FOUND_LBRACKET_STR;
            }

            /* we temporarily rewrite [=*[ in the input buffer to ]=*] to
             * construct the pattern for the corresponding closing long
             * bracket without additional buffers. */

            ngx_http_lua_assert(p[0] == '[');
            p[0] = ']';

            ngx_http_lua_assert(b->pos[ovec[1] - 1] == '[');
            b->pos[ovec[1] - 1] = ']';

            /* search for the corresponding closing bracket */

            dd("search pattern for the closing long bracket: \"%.*s\" (len=%d)",
               (int) (b->pos + ovec[1] - p), p, (int) (b->pos + ovec[1] - p));

            q = ngx_http_lua_strlstrn(b->pos + ovec[1], b->last, p,
                                      b->pos + ovec[1] - p - 1);

            if (q == NULL) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "Lua code block missing the closing "
                                   "long bracket \"%*s\", "
                                   "the inlined Lua code may be too long",
                                   b->pos + ovec[1] - p, p);
                return NGX_ERROR;
            }

            /* restore the original opening long bracket */

            p[0] = '[';
            b->pos[ovec[1] - 1] = '[';

            ovec[1] = q - b->pos + b->pos + ovec[1] - p;

            dd("found long bracket token: \"%.*s\"",
               (int) (ovec[1] - ovec[0]), b->pos + ovec[0]);
        }

        for (i = 0; i < ovec[1]; i++) {
            ch = b->pos[i];
            if (ch == LF) {
                cf->conf_file->line++;
            }
        }

        b->pos += ovec[1];
        ctx->token_len = ovec[1] - ovec[0];

        break;
    }

    word = ngx_array_push(cf->args);
    if (word == NULL) {
        return NGX_ERROR;
    }

    word->data = ngx_pnalloc(cf->temp_pool, b->pos - start);
    if (word->data == NULL) {
        return NGX_ERROR;
    }

    len = b->pos - start;
    ngx_memcpy(word->data, start, len);
    word->len = len;

    return rc;
}


char *
ngx_http_lua_capture_error_log(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
#ifndef HAVE_INTERCEPT_ERROR_LOG_PATCH
    return "not found: missing the capture error log patch for nginx";
#else
    ngx_str_t                     *value;
    ssize_t                        size;
    u_char                        *data;
    ngx_cycle_t                   *cycle;
    ngx_http_lua_main_conf_t      *lmcf = conf;
    ngx_http_lua_log_ringbuf_t    *ringbuf;

    value = cf->args->elts;
    cycle = cf->cycle;

    if (lmcf->requires_capture_log) {
        return "is duplicate";
    }

    if (value[1].len == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid capture error log size \"%V\"",
                           &value[1]);
        return NGX_CONF_ERROR;
    }

    size = ngx_parse_size(&value[1]);

    if (size < NGX_MAX_ERROR_STR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid capture error log size \"%V\", "
                           "minimum size is %d", &value[1],
                           NGX_MAX_ERROR_STR);
        return NGX_CONF_ERROR;
    }

    if (cycle->intercept_error_log_handler) {
        return "capture error log handler has been hooked";
    }

    ringbuf = (ngx_http_lua_log_ringbuf_t *)
              ngx_palloc(cf->pool, sizeof(ngx_http_lua_log_ringbuf_t));
    if (ringbuf == NULL) {
        return NGX_CONF_ERROR;
    }

    data = ngx_palloc(cf->pool, size);
    if (data == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_http_lua_log_ringbuf_init(ringbuf, data, size);

    lmcf->requires_capture_log = 1;
    cycle->intercept_error_log_handler = (ngx_log_intercept_pt)
                                         ngx_http_lua_capture_log_handler;
    cycle->intercept_error_log_data = ringbuf;

    return NGX_CONF_OK;
#endif
}


/*
 * ngx_http_lua_strlstrn() is intended to search for static substring
 * with known length in string until the argument last. The argument n
 * must be length of the second substring - 1.
 */

static u_char *
ngx_http_lua_strlstrn(u_char *s1, u_char *last, u_char *s2, size_t n)
{
    ngx_uint_t  c1, c2;

    c2 = (ngx_uint_t) *s2++;
    last -= n;

    do {
        do {
            if (s1 >= last) {
                return NULL;
            }

            c1 = (ngx_uint_t) *s1++;

            dd("testing char '%c' vs '%c'", (int) c1, (int) c2);

        } while (c1 != c2);

        dd("testing against pattern \"%.*s\"", (int) n, s2);

    } while (ngx_strncmp(s1, s2, n) != 0);

    return --s1;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
