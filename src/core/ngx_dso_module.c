
/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <nginx.h>
#include <dlfcn.h>


#define NGX_DSO_EXT ".so"


typedef struct {
    ngx_str_t     type;
    ngx_str_t     entry;
} ngx_dso_flagpole_t;


typedef struct {
    ngx_str_t     name;
    ngx_str_t     path;
    void         *dl_handle;
    ngx_module_t *module;
} ngx_dso_module_t;


typedef struct {
    ngx_str_t     path;
    ngx_int_t     flag_postion;

    ngx_array_t  *order;
    ngx_array_t  *modules;
} ngx_dso_conf_ctx_t;


static char *ngx_dso_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_dso_load(ngx_conf_t *cf);
static ngx_int_t ngx_dso_check_duplicated(ngx_cycle_t *cycle, ngx_array_t *modules,
    ngx_str_t *name, ngx_str_t *path);
static char *ngx_dso_order(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

static ngx_int_t ngx_dso_get_position(ngx_str_t *module_entry);

static ngx_int_t ngx_dso_find_postion(ngx_dso_conf_ctx_t *ctx,
    ngx_str_t module_name);


static ngx_command_t  ngx_dso_module_commands[] = {

    { ngx_string("dso"),
      NGX_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_dso_block,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_core_module_t  ngx_dso_module_ctx = {
    ngx_string("dso"),
    NULL,
    NULL,
};


ngx_module_t  ngx_dso_module = {
    NGX_MODULE_V1,
    &ngx_dso_module_ctx,                   /* module context */
    ngx_dso_module_commands,               /* module directives */
    NGX_CORE_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_module_t *ngx_old_modules[NGX_DSO_MAX];
static ngx_module_t *ngx_static_modules[NGX_DSO_MAX];
static ngx_str_t ngx_default_modules_prefix = ngx_string(NGX_DSO_PATH);


static ngx_dso_flagpole_t module_flagpole[] = {

    { ngx_string("filter"), ngx_string("ngx_http_copy_filter_module")},
    { ngx_null_string, ngx_null_string}
};


static ngx_int_t
ngx_dso_get_position(ngx_str_t *entry)
{
    size_t                    len;
    ngx_int_t                 i;

    /* start insert filter list */
    for (i = 0; ngx_module_names[i]; i++) {

        len = ngx_strlen(ngx_module_names[i]);

        if (len == entry->len
            && ngx_strncasecmp((u_char *) ngx_module_names[i],
                entry->data, len) == 0)
        {
            return i;
        }
    }

    return NGX_ERROR;
}


static void
ngx_dso_cleanup(void *data)
{
    ngx_cycle_t       *cycle = data;

    ngx_uint_t                           i;
    ngx_dso_module_t                    *dl_m;
    ngx_dso_conf_ctx_t                  *ctx;

    if (cycle != ngx_cycle) {

        if (cycle->conf_ctx) {
            ctx = (ngx_dso_conf_ctx_t *)
                   cycle->conf_ctx[ngx_dso_module.index];

            if (ctx != NULL) {
                dl_m = ctx->modules->elts;

                for (i = 0; i < ctx->modules->nelts; i++) {
                    if (dl_m[i].name.len == 0) {
                        continue;
                    }

                    dlclose(dl_m[i].dl_handle);
                }
            }
        }

        ngx_memzero(ngx_modules, sizeof(ngx_module_t *) * NGX_DSO_MAX);
        ngx_memcpy(ngx_modules, ngx_old_modules,
                   sizeof(ngx_module_t *) * NGX_DSO_MAX);
    }
}


static ngx_int_t
ngx_dso_check_duplicated(ngx_cycle_t *cycle, ngx_array_t *modules,
    ngx_str_t *name, ngx_str_t *path)
{
    size_t                               len;
    ngx_uint_t                           j;
    ngx_dso_module_t                    *m;

    for (j = 0; ngx_module_names[j]; j++) {
        len = ngx_strlen(ngx_module_names[j]);

        if (len == name->len && ngx_strncmp(ngx_module_names[j],
                name->data, name->len) == 0)
        {
            ngx_log_stderr(0, "module %V is already static loaded, skipping",
                name);
            return NGX_DECLINED;
        }
    }

    m = modules->elts;
    for (j = 0; j < modules->nelts; j++) {
        if ((m[j].name.len == name->len
            && ngx_strncmp(m[j].name.data, name->data, name->len) == 0)
           || (m[j].path.len == path->len
              && ngx_strncmp(m[j].path.data, path->data, path->len) == 0))
        {
            ngx_log_stderr(0, "module %V/%V is already dynamic loaded, skipping",
                path, name);
            m[j].name.len = 0;
            return NGX_DECLINED;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_dso_full_name(ngx_cycle_t *cycle, ngx_dso_conf_ctx_t *ctx, ngx_str_t *name)
{
    size_t      len, size;
    u_char     *p, *n, *prefix;

    if (name->data[0] == '/') {
        return NGX_OK;
    }

    if (ctx->path.data == NULL) {
        if (ngx_default_modules_prefix.data[0] != '/') {
            prefix = cycle->prefix.data;
            len = cycle->prefix.len;
            size = len + ngx_default_modules_prefix.len + name->len + 1;
        } else {
            prefix = ngx_default_modules_prefix.data;
            len = ngx_default_modules_prefix.len;
            size = len + name->len + 1;
        }
    } else {
        if (ctx->path.data[0] != '/') {
            ngx_log_stderr(0, "the path(%V) of dso module should be absolute path",
                           &ctx->path);
            return NGX_ERROR;
        }

        len = ctx->path.len;
        prefix = ctx->path.data;
        size = len + name->len + 1;
    }

    n = ngx_pnalloc(cycle->pool, size + 1);
    if (n == NULL) {
        return NGX_ERROR;
    }

    p = ngx_cpymem(n, prefix, len);

    if (ctx->path.data == NULL
       && ngx_default_modules_prefix.data[0] != '/')
    {
        p = ngx_cpymem(p, ngx_default_modules_prefix.data,
                       ngx_default_modules_prefix.len);
    }

    p = ngx_cpymem(p, "/", 1);
    ngx_cpystrn(p, name->data, name->len + 1);

    name->len = size;
    name->data = n;

    return NGX_OK;
}


static ngx_int_t
ngx_dso_open(ngx_dso_module_t *dl_m)
{
    void                                *dl_handle;
    ngx_str_t                            module_name, module_path;
    ngx_module_t                        *module;

    module_name = dl_m->name;
    module_path = dl_m->path;

    dl_handle = dlopen((char *) module_path.data, RTLD_NOW | RTLD_GLOBAL);
    if (dl_handle == NULL) {
        ngx_log_stderr(errno, "load module failed %s", dlerror());
        return NGX_ERROR;
    }

    module = dlsym(dl_handle, (const char *) module_name.data);
    if (module == NULL) {
        ngx_log_stderr(errno, "Can't locate sym in module(%V)", &module_name);
        return NGX_ERROR;
    }

    dl_m->dl_handle = dl_handle;
    dl_m->module = module;

    return NGX_OK;
}


static char *
ngx_dso_insert_module(ngx_module_t *module, ngx_int_t flag_postion)
{
    ngx_uint_t                j;
    ngx_module_t             *m;

    m = NULL;
    /* start insert filter list */
    for (j = flag_postion; ngx_modules[j]; j++) {
        m = ngx_modules[j];

        ngx_modules[j] = module;

        module = m;
    }

    if (m == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_modules[j] = module;

    return NGX_CONF_OK;
}


	
static char *
ngx_dso_save(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char                              *p;
    ngx_int_t                            rc;
    ngx_str_t                           *value, module_path;
    ngx_dso_module_t                    *dl_m;
    ngx_dso_conf_ctx_t                  *ctx;

    ctx = cf->ctx;
    value = cf->args->elts;

    if (ctx->modules->nelts >= NGX_DSO_MAX) {
        ngx_log_stderr(0, "Module \"%V\" could not be loaded, "
            "because the dso module limit(%ui) was reached.",
                      &value[1], NGX_DSO_MAX);
        return NGX_CONF_ERROR;
    }

    if (cf->args->nelts == 3) {
        rc = ngx_dso_check_duplicated(cf->cycle, ctx->modules,
                                      &value[1], &value[2]);
        module_path = value[2];
    } else {
        /* cf->args->nelts == 2 */
        module_path.len = value[1].len + sizeof(NGX_DSO_EXT);
        module_path.data = ngx_pcalloc(cf->pool, module_path.len);
        if (module_path.data == NULL) {
            return NGX_CONF_ERROR;
        }

        p = ngx_cpymem(module_path.data, value[1].data, value[1].len);
        ngx_memcpy(p, NGX_DSO_EXT, sizeof(NGX_DSO_EXT) - 1);
        rc = ngx_dso_check_duplicated(cf->cycle, ctx->modules,
                                      &value[1], &module_path);
    }

    if (rc == NGX_DECLINED) {
        return NGX_CONF_OK;
    }

    dl_m = ngx_array_push(ctx->modules);
    if (dl_m == NULL) {
        return NGX_CONF_ERROR;
    }

    dl_m->name = value[1];
    dl_m->path = module_path;

    return NGX_CONF_OK;
}


static char *
ngx_dso_load(ngx_conf_t *cf)
{
    char                                *rv;
    ngx_int_t                            postion;
    ngx_uint_t                           i;
    ngx_dso_module_t                    *dl_m;
    ngx_dso_conf_ctx_t                  *ctx;

    ctx = cf->ctx;
    dl_m = ctx->modules->elts;

    for (i = 0; i < ctx->modules->nelts; i++) {
        if (ngx_dso_full_name(cf->cycle, ctx, &dl_m[i].path) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (ngx_dso_open(&dl_m[i]) == NGX_ERROR) {
            return NGX_CONF_ERROR;
        }

        if (dl_m[i].module->type == NGX_CORE_MODULE) {
            ngx_log_stderr(0,"dso module not support core module");
            return NGX_CONF_ERROR;
        }

        if (dl_m[i].module->major_version != NGX_NUMBER_MAJOR
           || dl_m[i].module->minor_version > NGX_NUMBER_MINOR)
        {
            ngx_log_stderr(0,"Module \"%V\" is not compatible with this "
                           "version of Tengine (found %d.%d, need %d.%d)."
                           " Please contact the vendor for the correct version.",
                           &dl_m[i].name, dl_m[i].module->major_version,
                           dl_m[i].module->minor_version, NGX_NUMBER_MAJOR,
                           NGX_NUMBER_MINOR);
            return NGX_CONF_ERROR;
        }

        postion = ngx_dso_find_postion(ctx, dl_m[i].name);

        ngx_log_debug1(NGX_LOG_DEBUG_CORE, cf->log, 0, "dso find postion(%i)", postion);

        rv = ngx_dso_insert_module(dl_m[i].module, postion);
        if (rv == NGX_CONF_ERROR) {
            ngx_log_stderr(0, "dso find error postion(%i)", postion);
            return rv;
        }
    }

    return NGX_CONF_OK;
}


static char *
ngx_dso_template(ngx_conf_t *cf, ngx_dso_conf_ctx_t *ctx,
    ngx_str_t *name)
{
    char                      *rv;
    ngx_str_t                  file;
    ngx_conf_t                 pcf;

    file.len = name->len;
    file.data = ngx_pnalloc(cf->temp_pool, name->len + 1);

    if (file.data == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_sprintf(file.data, "%V", name);

    if (ngx_conf_full_name(cf->cycle, &file, 1) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    pcf = *cf;
    cf->ctx = ctx;
    cf->module_type = NGX_CORE_MODULE;
    cf->handler = ngx_dso_order;

    rv = ngx_conf_parse(cf, &file);

    *cf = pcf;

    return rv;
}


static char *
ngx_dso_parse(ngx_conf_t *cf, ngx_command_t *dummy, void *conf)
{
    ngx_str_t                           *value;
    ngx_dso_conf_ctx_t                  *ctx;

    value = cf->args->elts;
    ctx = cf->ctx;

    if (ngx_strcmp(value[0].data, "load") == 0) {

        if (cf->args->nelts != 2 && cf->args->nelts != 3) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                "invalid number of arguments in \"load\" directive");
            return NGX_CONF_ERROR;
        }

        return ngx_dso_save(cf, dummy, conf);
    }

    if (ngx_strcmp(value[0].data, "path") == 0) {
        if (cf->args->nelts != 2) {

            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                "invalid number of arguments in \"path\" directive");
            return NGX_CONF_ERROR;
        }

        if (ctx->path.data != NULL) {
            return "is duplicate";
        }

        ctx->path = value[1];
        return NGX_CONF_OK;
    }

    if (ngx_strcmp(value[0].data, "order") == 0) {

        if (cf->args->nelts != 2) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                "invalid number of arguments in \"sequence\" directive");
            return NGX_CONF_ERROR;
        }

        if (ctx->order->nelts != 0) {
            return "is duplicate";
        }

        return ngx_dso_template(cf, ctx, &value[1]);
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "unknown directive \"%s\"", value[0].data);
    return NGX_CONF_ERROR;
}


static char *
ngx_dso_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                                *rv;
    ngx_conf_t                           pcf;
    ngx_dso_conf_ctx_t                  *ctx;
    ngx_pool_cleanup_t                  *cln;

    ctx = ((void **) cf->ctx)[ngx_dso_module.index];
    if (ctx != NULL) {
        return "is duplicate";
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_dso_conf_ctx_t));

    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    *(ngx_dso_conf_ctx_t **) conf = ctx;

    ctx->modules = ngx_array_create(cf->pool, 10, sizeof(ngx_dso_module_t));
    if (ctx->modules == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->flag_postion = ngx_dso_get_position(&module_flagpole[0].entry);
    if (ctx->flag_postion == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    ctx->order = ngx_array_create(cf->pool, 10, sizeof(ngx_str_t));
    if (ctx->order == NULL) {
        return NGX_CONF_ERROR;
    }

    if (ngx_is_init_cycle(cf->cycle->old_cycle)) {
        ngx_memzero(ngx_static_modules, sizeof(ngx_module_t *) * ngx_max_module);
        ngx_memcpy(ngx_static_modules, ngx_modules,
                   sizeof(ngx_module_t *) * ngx_max_module);
    } else {
        ngx_memzero(ngx_old_modules, sizeof(ngx_module_t *) * NGX_DSO_MAX);

        ngx_memcpy(ngx_old_modules, ngx_modules,
                   sizeof(ngx_module_t *) * NGX_DSO_MAX);
        ngx_memcpy(ngx_modules, ngx_static_modules,
                   sizeof(ngx_module_t *) * NGX_DSO_MAX);
    }

    pcf = *cf;
    cf->ctx = ctx;
    cf->module_type = NGX_CORE_MODULE;
    cf->handler = ngx_dso_parse;
    cf->handler_conf = conf;

    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {
        *cf = pcf;
        return NGX_CONF_ERROR;
    }

    cln->handler = ngx_dso_cleanup;
    cln->data = cf->cycle;

    rv = ngx_conf_parse(cf, NULL);
    if (rv != NGX_CONF_OK) {
        *cf = pcf;
        return rv;
    }

    rv = ngx_dso_load(cf);

    if (rv == NGX_CONF_ERROR) {
        return rv;
    }

    *cf = pcf;

    return NGX_CONF_OK;
}


static char *
ngx_dso_order(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                                *value, *module_name;
    ngx_dso_conf_ctx_t                       *ctx;

    value = cf->args->elts;
    ctx = cf->ctx;

    if (cf->args->nelts != 1) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                "unknown directive \"%s\"", value[0].data);
        return NGX_CONF_ERROR;
    }

    module_name = ngx_array_push(ctx->order);
    if (module_name == NULL) {
        return NGX_CONF_ERROR;
    }

    *module_name = value[0];

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_dso_find_postion(ngx_dso_conf_ctx_t *ctx, ngx_str_t module_name)
{
    size_t                   len1, len2, len3;
    ngx_int_t                near;
    ngx_uint_t               i, k;
    ngx_str_t               *name;

    near = ctx->flag_postion;

    if (ctx->order == NULL || ctx->order->nelts == 0) {

        for (i = 1; ngx_all_module_names[i]; i++) {
            len1 = ngx_strlen(ngx_all_module_names[i]);
            if (len1 == module_name.len
               && ngx_strncmp(ngx_all_module_names[i], module_name.data, len1) == 0)
            {
                if (near <= ctx->flag_postion) {
                    ++ctx->flag_postion;
                }

                return near;
            }

            len2 = ngx_strlen(ngx_all_module_names[i - 1]);
            for (k = 0; ngx_module_names[k]; k++) {
                len3 = ngx_strlen(ngx_module_names[k]);

                if (len2 == len3
                   && ngx_strncmp(ngx_all_module_names[i - 1],
                                  ngx_module_names[k], len2) == 0)
                {
                    near = k + 1;
                    break;
                }
            }
        }

        if (ngx_all_module_names[i] == NULL) {
            return ++ctx->flag_postion;
        }
    }

    name = ctx->order->elts;
    near = ctx->flag_postion;

    for (i = 1; i < ctx->order->nelts; i++) {
        if (name[i].len == module_name.len
           && ngx_strncmp(name[i].data, module_name.data, name[i].len) == 0)
        {
            if (near <= ctx->flag_postion) {
                ++ctx->flag_postion;
            }

            return near;
        }

        for (k = 0; ngx_module_names[k]; k++) {
            len1 = ngx_strlen(ngx_module_names[k]);

            if (len1 == name[i].len
               && ngx_strncmp(name[i].data, ngx_module_names[k], name[i].len) == 0)
            {
                near = k + 1;
                break;
            }
        }
    }

    return ++ctx->flag_postion;
}


void
ngx_show_dso_modules(ngx_conf_t *cf)
{
    ngx_str_t                                 module_name;
    ngx_uint_t                                i;
    ngx_module_t                             *module;
    ngx_dso_module_t                         *dl_m;
    ngx_dso_conf_ctx_t                       *ctx;

    ctx = (ngx_dso_conf_ctx_t *) ngx_get_conf(cf->cycle->conf_ctx,
                                           ngx_dso_module);

    if (ctx == NULL) {
        return;
    }

    dl_m = ctx->modules->elts;

    for (i = 0; i < ctx->modules->nelts; i++) {
        if (dl_m[i].name.len == 0) {
            continue;
        }

        module_name = dl_m[i].name;
        module = dl_m[i].module;

        ngx_log_stderr(0, "    %V (shared), require nginx version (%d.%d)",
                       &module_name, module->major_version, module->minor_version);
    }
}
