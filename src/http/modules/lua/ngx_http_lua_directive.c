
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
#include "ngx_http_lua_rewriteby.h"
#include "ngx_http_lua_logby.h"
#include "ngx_http_lua_headerfilterby.h"
#include "ngx_http_lua_bodyfilterby.h"
#include "ngx_http_lua_initby.h"
#include "ngx_http_lua_shdict.h"


#if defined(NDK) && NDK
#include "ngx_http_lua_setby.h"


static ngx_int_t ngx_http_lua_set_by_lua_init(ngx_http_request_t *r);
#endif


char *
ngx_http_lua_shared_dict(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_lua_main_conf_t   *lmcf = conf;

    ngx_str_t                  *value, name;
    ngx_shm_zone_t             *zone;
    ngx_shm_zone_t            **zp;
    ngx_http_lua_shdict_ctx_t  *ctx;
    ssize_t                     size;

    if (lmcf->shm_zones == NULL) {
        lmcf->shm_zones = ngx_palloc(cf->pool, sizeof(ngx_array_t));
        if (lmcf->shm_zones == NULL) {
            return NGX_CONF_ERROR;
        }

        ngx_array_init(lmcf->shm_zones, cf->pool, 2, sizeof(ngx_shm_zone_t *));
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

    zone = ngx_shared_memory_add(cf, &name, (size_t) size,
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

    zp = ngx_array_push(lmcf->shm_zones);
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


#if defined(NDK) && NDK
char *
ngx_http_lua_set_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char              *p;
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

    filter_data->size = filter.size;

    p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
    if (p == NULL) {
        return NGX_CONF_ERROR;
    }

    filter_data->key = p;

    p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
    p = ngx_http_lua_digest_hex(p, value[2].data, value[2].len);
    *p = '\0';

    filter_data->script = value[2];

    filter.data = filter_data;

    return ndk_set_var_multi_value_core(cf, &target, &value[3], &filter);
}


char *
ngx_http_lua_set_by_lua_file(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char              *p;
    ngx_str_t           *value;
    ngx_str_t            target;
    ndk_set_var_t        filter;

    ngx_http_lua_set_var_data_t     *filter_data;

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

    filter_data->size = filter.size;

    p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
    if (p == NULL) {
        return NGX_CONF_ERROR;
    }

    filter_data->key = p;

    p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
    p = ngx_http_lua_digest_hex(p, value[2].data, value[2].len);
    *p = '\0';

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
    rc = ngx_http_lua_cache_loadbuffer(L, filter_data->script.data,
                                       filter_data->script.len,
                                       filter_data->key, "set_by_lua");
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
    rc = ngx_http_lua_cache_loadfile(L, script_path, filter_data->key);
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
ngx_http_lua_rewrite_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char                      *p;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

#if defined(nginx_version) && nginx_version >= 8042 && nginx_version <= 8053
    return "does not work with " NGINX_VER;
#endif

    /*  must specifiy a content handler */
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
        /* Don't eval nginx variables for inline lua code */
        llcf->rewrite_src.value = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        llcf->rewrite_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

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
            p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
            if (p == NULL) {
                return NGX_CONF_ERROR;
            }

            llcf->rewrite_src_key = p;

            p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
            p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
            *p = '\0';
        }
    }

    llcf->rewrite_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_rewrite = 1;
    lmcf->requires_capture_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_access_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char                      *p;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specifiy a content handler */
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
        /* Don't eval nginx variables for inline lua code */
        llcf->access_src.value = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        llcf->access_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

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
            p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
            if (p == NULL) {
                return NGX_CONF_ERROR;
            }

            llcf->access_src_key = p;

            p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
            p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
            *p = '\0';
        }
    }

    llcf->access_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_access = 1;
    lmcf->requires_capture_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_content_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char                      *p;
    ngx_str_t                   *value;
    ngx_http_core_loc_conf_t    *clcf;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specifiy a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->content_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");
        return NGX_CONF_ERROR;
    }

    if (cmd->post == ngx_http_lua_content_handler_inline) {
        /* Don't eval nginx variables for inline lua code */
        llcf->content_src.value = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        llcf->content_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

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
            p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
            if (p == NULL) {
                return NGX_CONF_ERROR;
            }

            llcf->content_src_key = p;

            p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
            p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
            *p = '\0';
        }
    }

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
ngx_http_lua_log_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char                      *p;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specifiy a content handler */
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
        /* Don't eval nginx variables for inline lua code */
        llcf->log_src.value = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        llcf->log_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

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
            p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
            if (p == NULL) {
                return NGX_CONF_ERROR;
            }

            llcf->log_src_key = p;

            p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
            p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
            *p = '\0';
        }
    }

    llcf->log_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_log = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_header_filter_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *p;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specifiy a content handler */
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
        /* Don't eval nginx variables for inline lua code */
        llcf->header_filter_src.value = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        llcf->header_filter_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

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
            p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
            if (p == NULL) {
                return NGX_CONF_ERROR;
            }

            llcf->header_filter_src_key = p;

            p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
            p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
            *p = '\0';
        }
    }

    llcf->header_filter_handler = (ngx_http_handler_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_header_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_body_filter_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *p;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    ngx_http_compile_complex_value_t         ccv;

    dd("enter");

    /*  must specifiy a content handler */
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
        /* Don't eval nginx variables for inline lua code */
        llcf->body_filter_src.value = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        llcf->body_filter_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

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
            p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
            if (p == NULL) {
                return NGX_CONF_ERROR;
            }

            llcf->body_filter_src_key = p;

            p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
            p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
            *p = '\0';
        }
    }

    llcf->body_filter_handler = (ngx_http_output_body_filter_pt) cmd->post;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->requires_body_filter = 1;
    lmcf->requires_header_filter = 1;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_init_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf = conf;

    dd("enter");

    /*  must specifiy a content handler */
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

    lmcf->init_handler = (ngx_http_lua_conf_handler_pt) cmd->post;

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
    }

    return NGX_CONF_OK;
}


#if defined(NDK) && NDK
static ngx_int_t
ngx_http_lua_set_by_lua_init(ngx_http_request_t *r)
{
    lua_State                   *L;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_cleanup_t          *cln;

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
        cln = ngx_http_cleanup_add(r, 0);
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

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
