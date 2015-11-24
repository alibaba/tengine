
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <nginx.h>
#include <dlfcn.h>


typedef struct {
    ngx_str_t     type;
    ngx_str_t     entry;
} ngx_dso_flagpole_t;


typedef struct {
    ngx_str_t     name;
    ngx_str_t     path;
    void         *handle;
    ngx_module_t *module;
} ngx_dso_module_t;


typedef struct {
    ngx_str_t     path;
    ngx_int_t     flag_postion;

    ngx_array_t  *stubs;
    ngx_array_t  *modules;
} ngx_dso_conf_ctx_t;


static void *ngx_dso_create_conf(ngx_cycle_t *cycle);
static char *ngx_dso_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_dso_parse(ngx_conf_t *cf, ngx_command_t *dummy, void *conf);
static char *ngx_dso_include(ngx_conf_t *cf, ngx_dso_conf_ctx_t *ctx,
    ngx_str_t *name);
static char *ngx_dso_load(ngx_conf_t *cf);
static void ngx_dso_cleanup(void *data);

static ngx_int_t ngx_dso_check_duplicated(ngx_conf_t *cf,
    ngx_array_t *modules, ngx_str_t *name, ngx_str_t *path);
static char *ngx_dso_stub(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

static ngx_int_t ngx_dso_get_position(ngx_str_t *module_entry);

static ngx_int_t ngx_dso_find_postion(ngx_dso_conf_ctx_t *ctx,
    ngx_str_t module_name);

ngx_int_t ngx_is_dynamic_module(ngx_conf_t *cf, u_char *name,
    ngx_uint_t *major_version, ngx_uint_t *minor_version);


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
    ngx_dso_create_conf,
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
static u_char *ngx_old_module_names[NGX_DSO_MAX];
static u_char *ngx_static_module_names[NGX_DSO_MAX];
static ngx_str_t ngx_default_module_prefix = ngx_string(NGX_DSO_PATH);


static ngx_dso_flagpole_t module_flagpole[] = {
    { ngx_string("filter"), ngx_string("ngx_http_copy_filter_module")},
    { ngx_null_string, ngx_null_string}
};

extern const char *ngx_dso_abi_all_tags[];


static void *
ngx_dso_create_conf(ngx_cycle_t *cycle)
{
    ngx_dso_conf_ctx_t  *ctx;
    ngx_pool_cleanup_t  *cln;

    ctx = ngx_pcalloc(cycle->pool, sizeof(ngx_dso_conf_ctx_t));

    if (ctx == NULL) {
        return NULL;
    }

    if (NGX_DSO_MAX < ngx_max_module) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log,
                      0, "please set max dso module"
                      "(use configure with --dso-max-modules),"
                      "current is %ud, expect %ud",
                      NGX_DSO_MAX, ngx_max_module + 1);
        return NULL;
    }

    if (ngx_is_init_cycle(cycle->old_cycle)) {
        ngx_memcpy(ngx_static_modules, ngx_modules,
                   sizeof(ngx_module_t *) * ngx_max_module);
        ngx_memcpy(ngx_static_module_names, ngx_module_names,
                   sizeof(u_char *) * ngx_max_module);

    } else {
        ngx_memcpy(ngx_old_modules, ngx_modules,
                   sizeof(ngx_module_t *) * NGX_DSO_MAX);
        ngx_memcpy(ngx_modules, ngx_static_modules,
                   sizeof(ngx_module_t *) * NGX_DSO_MAX);

        ngx_memcpy(ngx_old_module_names, ngx_module_names,
                   sizeof(u_char *) * NGX_DSO_MAX);
        ngx_memcpy(ngx_module_names, ngx_static_module_names,
                   sizeof(u_char *) * NGX_DSO_MAX);
    }

    cln = ngx_pool_cleanup_add(cycle->pool, 0);
    if (cln == NULL) {
        return NULL;
    }

    cln->handler = ngx_dso_cleanup;
    cln->data = cycle;

    return ctx;
}


static char *
ngx_dso_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                *rv;
    ngx_conf_t           pcf;
    ngx_dso_conf_ctx_t  *ctx;

    ctx = (ngx_dso_conf_ctx_t *) ngx_get_conf(cf->cycle->conf_ctx,
                                              ngx_dso_module);

    if (ctx->modules != NULL) {
        return "is duplicate";
    }

    ctx->modules = ngx_array_create(cf->pool, 50, sizeof(ngx_dso_module_t));
    if (ctx->modules == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->stubs = ngx_array_create(cf->pool, 50, sizeof(ngx_str_t));
    if (ctx->stubs == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->flag_postion = ngx_dso_get_position(&module_flagpole[0].entry);
    if (ctx->flag_postion == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    *(ngx_dso_conf_ctx_t **) conf = ctx;

    ngx_log_debug1(NGX_LOG_DEBUG_CORE, cf->log, 0,
                   "dso flag postion (%i)", ctx->flag_postion);

    pcf = *cf;
    cf->ctx = ctx;
    cf->module_type = NGX_CORE_MODULE;
    cf->handler = ngx_dso_parse;
    cf->handler_conf = conf;

    rv = ngx_conf_parse(cf, NULL);
    if (rv != NGX_CONF_OK) {
        goto failed;
    }

    rv = ngx_dso_load(cf);

    if (rv == NGX_CONF_ERROR) {
        goto failed;
    }

    *cf = pcf;

    return NGX_CONF_OK;

failed:

    *cf = pcf;
    return rv;
}


static ngx_int_t
ngx_dso_get_position(ngx_str_t *entry)
{
    size_t     len;
    ngx_int_t  i;

    for (i = 0; ngx_module_names[i]; i++) {

        len = ngx_strlen(ngx_module_names[i]);

        if (len != entry->len) {
            continue;
        }

        if (ngx_strncasecmp((u_char *) ngx_module_names[i],
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

    ngx_uint_t           i;
    ngx_dso_module_t    *dm;
    ngx_dso_conf_ctx_t  *ctx;

    if (cycle != ngx_cycle) {
        ngx_memcpy(ngx_modules, ngx_old_modules,
                   sizeof(ngx_module_t *) * NGX_DSO_MAX);
        ngx_memcpy(ngx_module_names, ngx_old_module_names,
                   sizeof(u_char *) * NGX_DSO_MAX);
    }

    if (cycle->conf_ctx) {

        ctx = (ngx_dso_conf_ctx_t *) ngx_get_conf(cycle->conf_ctx,
                                                  ngx_dso_module);

        if (ctx != NULL && ctx->modules != NULL) {
            dm = ctx->modules->elts;

            for (i = 0; i < ctx->modules->nelts; i++) {
                if (dm[i].name.len == 0 || dm[i].handle == NULL) {
                    continue;
                }

                dlclose(dm[i].handle);
            }
        }
    }
}


static ngx_int_t
ngx_dso_check_duplicated(ngx_conf_t *cf, ngx_array_t *modules,
    ngx_str_t *name, ngx_str_t *path)
{
    size_t             len;
    ngx_uint_t         i, major_version, minor_version;

    for (i = 0; ngx_module_names[i]; i++) {
        len = ngx_strlen(ngx_module_names[i]);

        if (len == name->len
           && ngx_strncmp(ngx_module_names[i], name->data, name->len) == 0)
        {
            if (ngx_is_dynamic_module(cf, ngx_module_names[i],
                                      &major_version, &minor_version) == NGX_OK)
            {
                ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                                   "module \"%V/%V\" is already dynamically "
                                   "loaded, skipping", path, name);
            } else {

                ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                                   "module %V is already statically loaded, "
                                   "skipping", name);
            }

            return NGX_DECLINED;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_dso_full_name(ngx_conf_t *cf, ngx_dso_conf_ctx_t *ctx,
    ngx_str_t *name)
{
    size_t       len, size;
    u_char      *p, *n, *prefix;
    ngx_cycle_t *cycle;

    cycle = cf->cycle;

    if (name->data[0] == '/') {
        return NGX_OK;
    }

    if (ctx->path.data == NULL) {
        if (ngx_default_module_prefix.data[0] != '/') {
            prefix = cycle->prefix.data;
            len = cycle->prefix.len;
            size = len + ngx_default_module_prefix.len + name->len + 1;

        } else {
            prefix = ngx_default_module_prefix.data;
            len = ngx_default_module_prefix.len;
            size = len + name->len + 1;
        }

    } else {
        if (ctx->path.data[0] != '/') {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "the path (\"%V\") of dso module "
                               "should be an absolute path", &ctx->path);
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
       && ngx_default_module_prefix.data[0] != '/')
    {
        p = ngx_cpymem(p, ngx_default_module_prefix.data,
                       ngx_default_module_prefix.len);
    }

    p = ngx_cpymem(p, "/", 1);
    ngx_cpystrn(p, name->data, name->len + 1);

    name->len = size;
    name->data = n;

    return NGX_OK;
}


static ngx_int_t
ngx_dso_open(ngx_conf_t *cf, ngx_dso_module_t *dm)
{
    ngx_str_t name, path;

    name = dm->name;
    path = dm->path;

    dm->handle = dlopen((char *) path.data, RTLD_NOW | RTLD_GLOBAL);
    if (dm->handle == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, errno,
                           "load module \"%V\" failed (%s)",
                           &path, dlerror());
        return NGX_ERROR;
    }

    dm->module = dlsym(dm->handle, (const char *) name.data);
    if (dm->module == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, errno,
                           "can't locate symbol in module \"%V\"", &name);
        return NGX_ERROR;
    }

    return NGX_OK;
}


static char *
ngx_dso_insert_module(ngx_dso_module_t *dm, ngx_int_t flag_postion)
{
    u_char        *n, *name;
    ngx_uint_t     i;
    ngx_module_t  *m, *module;

    m = NULL;
    n = NULL;
    module = dm->module;
    name = dm->name.data;

    /* start to insert */
    for (i = flag_postion; ngx_modules[i]; i++) {
        m = ngx_modules[i];
        n = ngx_module_names[i];

        ngx_modules[i] = module;
        ngx_module_names[i] = name;

        module = m;
        name = n;
    }

    if (m == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_modules[i] = module;
    ngx_module_names[i] = name;

    return NGX_CONF_OK;
}


static char *
ngx_dso_save(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    u_char              *p;
    ngx_int_t            rc;
    ngx_str_t           *value, path, name;
    ngx_dso_module_t    *dm;
    ngx_dso_conf_ctx_t  *ctx;

    ctx = cf->ctx;
    value = cf->args->elts;

    if (ctx->modules->nelts >= NGX_DSO_MAX) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "module \"%V\" can not be loaded, "
                           "because the dso module limit (%ui) is reached.",
                           &value[1], NGX_DSO_MAX);
        return NGX_CONF_ERROR;
    }

    if (cf->args->nelts == 3) {
        name = value[1];
        path = value[2];

    } else {
        /* cf->args->nelts == 2 */
        if (value[1].len > 3 &&
            value[1].data[value[1].len - 3] == '.' &&
            value[1].data[value[1].len - 2] == 's' &&
            value[1].data[value[1].len - 1] == 'o')
        {
            path = value[1];
            name.data = ngx_pcalloc(cf->pool, value[1].len - 2);
            if (path.data == NULL) {
                return NGX_CONF_ERROR;
            }

            name.len = value[1].len - 3;
            ngx_memcpy(name.data, path.data, name.len);

        } else {
            path.len = value[1].len + sizeof(NGX_SOEXT);
            path.data = ngx_pcalloc(cf->pool, path.len);
            if (path.data == NULL) {
                return NGX_CONF_ERROR;
            }

            p = ngx_cpymem(path.data, value[1].data, value[1].len);
            ngx_memcpy(p, NGX_SOEXT, sizeof(NGX_SOEXT) - 1);
            name = value[1];
        }
    }

    rc = ngx_dso_check_duplicated(cf, ctx->modules,
                                  &name, &path);
    if (rc == NGX_DECLINED) {
        return NGX_CONF_OK;
    }

    dm = ngx_array_push(ctx->modules);
    if (dm == NULL) {
        return NGX_CONF_ERROR;
    }

    dm->name = name;
    dm->path = path;
    dm->handle = NULL;

    return NGX_CONF_OK;
}


static void
ngx_dso_show_abi_compatibility(ngx_uint_t abi_compatibility)
{
    ngx_uint_t  i;

    for (i = 0; i < sizeof(ngx_uint_t) * 8; i++) {

        if (ngx_dso_abi_all_tags[i] == NULL) {
            break;
        }

        if (abi_compatibility & 0x1) {
            ngx_log_stderr(0, "    %s", ngx_dso_abi_all_tags[i]);
        }

        abi_compatibility >>= 1;
    }
}


static char *
ngx_dso_load(ngx_conf_t *cf)
{
    char                *rv;
    ngx_int_t            postion;
    ngx_uint_t           i;
    ngx_dso_module_t    *dm;
    ngx_dso_conf_ctx_t  *ctx;

    ctx = cf->ctx;
    dm = ctx->modules->elts;

    for (i = 0; i < ctx->modules->nelts; i++) {
        if (ngx_dso_full_name(cf, ctx, &dm[i].path) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        if (ngx_dso_open(cf, &dm[i]) == NGX_ERROR) {
            return NGX_CONF_ERROR;
        }

        if (dm[i].module->type == NGX_CORE_MODULE) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "core modules can not be dynamically loaded");
            return NGX_CONF_ERROR;
        }

        if (dm[i].module->major_version != NGX_NUMBER_MAJOR
           || dm[i].module->minor_version > NGX_NUMBER_MINOR)
        {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "module \"%V\" is not compatible with this "
                               "version of tengine "
                               "(require %ui.%ui, found %ui.%ui).",
                               &dm[i].name, NGX_NUMBER_MAJOR, NGX_NUMBER_MINOR,
                               dm[i].module->major_version,
                               dm[i].module->minor_version);
            return NGX_CONF_ERROR;
        }

        if (dm[i].module->abi_compatibility != NGX_DSO_ABI_COMPATIBILITY) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "module \"%V\" is not compatible with this "
                               "ABI of tengine, you need recomplie module",
                               &dm[i].name);

            ngx_log_stderr(0, "Tengine config option: ");
            ngx_dso_show_abi_compatibility(NGX_DSO_ABI_COMPATIBILITY);
            ngx_log_stderr(0, "module \"%V\" config option: ", &dm[i].name);
            ngx_dso_show_abi_compatibility(dm[i].module->abi_compatibility);
            return NGX_CONF_ERROR;
        }

        postion = ngx_dso_find_postion(ctx, dm[i].name);

        ngx_log_debug2(NGX_LOG_DEBUG_CORE, cf->log, 0,
                       "dso find postion (%i, %i)", postion, ctx->flag_postion);

        rv = ngx_dso_insert_module(&dm[i], postion);
        if (rv == NGX_CONF_ERROR) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "dso failed to find position (%i)", postion);
            return rv;
        }
    }

    return NGX_CONF_OK;
}


static char *
ngx_dso_parse(ngx_conf_t *cf, ngx_command_t *dummy, void *conf)
{
    ngx_str_t           *value;
    ngx_dso_conf_ctx_t  *ctx;

    value = cf->args->elts;
    ctx = cf->ctx;

    if (ngx_strcmp(value[0].data, "load") == 0) {

        if (cf->args->nelts != 2 && cf->args->nelts != 3) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid number of arguments "
                               "in \"load\" directive");
            return NGX_CONF_ERROR;
        }

        return ngx_dso_save(cf, dummy, conf);
    }

    if (ngx_strcmp(value[0].data, "path") == 0) {
        if (cf->args->nelts != 2) {

            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid number of arguments "
                               "in \"path\" directive");
            return NGX_CONF_ERROR;
        }

        if (ctx->path.data != NULL) {
            return "is duplicate";
        }

        ctx->path = value[1];
        return NGX_CONF_OK;
    }

    if (ngx_strcmp(value[0].data, "module_stub") == 0) {

        if (cf->args->nelts != 2) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid number of arguments "
                               "in \"sequence\" directive");
            return NGX_CONF_ERROR;
        }

        return ngx_dso_stub(cf, dummy, conf);
    }

    if (ngx_strcmp(value[0].data, "include") == 0) {

        if (cf->args->nelts != 2) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid number of arguments "
                               "in \"sequence\" directive");
            return NGX_CONF_ERROR;
        }

        return ngx_dso_include(cf, ctx, &value[1]);
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "unknown directive \"%V\"", &value[0]);
    return NGX_CONF_ERROR;
}


static char *
ngx_dso_include(ngx_conf_t *cf, ngx_dso_conf_ctx_t *ctx,
    ngx_str_t *name)
{
    char        *rv;
    ngx_int_t    n;
    ngx_str_t    file, glob_name;
    ngx_glob_t   gl;
    ngx_conf_t   pcf;

    file.len = name->len;
    file.data = ngx_pnalloc(cf->temp_pool, name->len + 1);
    if (file.data == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_sprintf(file.data, "%V%Z", name);
    ngx_log_debug1(NGX_LOG_DEBUG_CORE, cf->log, 0, "dso include %s", file.data);

    if (ngx_conf_full_name(cf->cycle, &file, 1) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    if (strpbrk((char *) file.data, "*?[") == NULL) {

        ngx_log_debug1(NGX_LOG_DEBUG_CORE, cf->log, 0, "dso include %s", file.data);

        pcf = *cf;

        cf->ctx = ctx;
        cf->module_type = NGX_CORE_MODULE;

        rv = ngx_conf_parse(cf, &file);

        *cf = pcf;

        return rv;
    }

    ngx_memzero(&gl, sizeof(ngx_glob_t));

    gl.pattern = file.data;
    gl.log = cf->log;
    gl.test = 1;

    if (ngx_open_glob(&gl) != NGX_OK) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, ngx_errno,
                           ngx_open_glob_n " \"%s\" failed", file.data);
        return NGX_CONF_ERROR;
    }

    rv = NGX_CONF_OK;

    pcf = *cf;
    cf->ctx = ctx;
    cf->module_type = NGX_CORE_MODULE;

    for ( ;; ) {
        n = ngx_read_glob(&gl, &glob_name);

        if (n != NGX_OK) {
            break;
        }

        file.len = glob_name.len++;
        file.data = ngx_pstrdup(cf->pool, &glob_name);

        ngx_log_debug1(NGX_LOG_DEBUG_CORE, cf->log, 0, "dso include %V", &glob_name);

        cf->ctx = ctx;
        cf->module_type = NGX_CORE_MODULE;

        rv = ngx_conf_parse(cf, &file);

        if (rv != NGX_CONF_OK) {
            break;
        }
    }

    *cf = pcf;

    ngx_close_glob(&gl);

    return rv;
}


static char *
ngx_dso_stub(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t           *value, *name;
    ngx_dso_conf_ctx_t  *ctx;

    value = cf->args->elts;
    ctx = cf->ctx;

    if (cf->args->nelts != 2) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "unknown directive \"%V\"", &value[0]);
        return NGX_CONF_ERROR;
    }

    name = ngx_array_push(ctx->stubs);
    if (name == NULL) {
        return NGX_CONF_ERROR;
    }

    *name = value[1];

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_dso_find_postion(ngx_dso_conf_ctx_t *ctx, ngx_str_t module_name)
{
    size_t      len1, len2, len3;
    ngx_int_t   near;
    ngx_str_t  *name;
    ngx_uint_t  i, k;

    near = ctx->flag_postion;

    if (ctx->stubs == NULL || ctx->stubs->nelts == 0) {

        for (i = 1; ngx_all_module_names[i]; i++) {
            len1 = ngx_strlen(ngx_all_module_names[i]);
            if (len1 == module_name.len
               && ngx_strncmp(ngx_all_module_names[i],
                              module_name.data, len1) == 0)
            {
                if (near <= ctx->flag_postion) {
                    ctx->flag_postion++;
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
            return ctx->flag_postion++;
        }
    }

    name = ctx->stubs->elts;
    near = ctx->flag_postion;

    for (i = 1; i < ctx->stubs->nelts; i++) {
        if (name[i].len == module_name.len
           && ngx_strncmp(name[i].data, module_name.data, name[i].len) == 0)
        {
            if (near <= ctx->flag_postion) {
                ctx->flag_postion++;
            }

            return near;
        }

        for (k = 0; ngx_module_names[k]; k++) {
            len1 = ngx_strlen(ngx_module_names[k]);

            if (len1 == name[i - 1].len
               && ngx_strncmp(name[i - 1].data, ngx_module_names[k],
                              name[i - 1].len) == 0)
            {
                near = k + 1;
                break;
            }
        }
    }

    return ctx->flag_postion++;
}


ngx_int_t
ngx_is_dynamic_module(ngx_conf_t *cf, u_char *name,
    ngx_uint_t *major_version, ngx_uint_t *minor_version)
{
    size_t               len;
    ngx_uint_t           i;
    ngx_dso_module_t    *dm;
    ngx_dso_conf_ctx_t  *ctx;

    ctx = (ngx_dso_conf_ctx_t *) ngx_get_conf(cf->cycle->conf_ctx,
                                              ngx_dso_module);

    if (ctx == NULL || ctx->modules == NULL) {
        return NGX_DECLINED;
    }

    dm = ctx->modules->elts;
    len = ngx_strlen(name);

    for (i = 0; i < ctx->modules->nelts; i++) {
        if (dm[i].name.len == 0) {
            continue;
        }

        if (len == dm[i].name.len &&
            ngx_strncmp(dm[i].name.data, name, dm[i].name.len) == 0)
        {
            *major_version = dm[i].module->major_version;
            *minor_version = dm[i].module->minor_version;
            return NGX_OK;
        }
    }

    return NGX_DECLINED;
}


void
ngx_show_dso_directives(ngx_conf_t *cf)
{
    ngx_str_t            name;
    ngx_uint_t           i;
    ngx_module_t        *module;
    ngx_command_t       *cmd;
    ngx_dso_module_t    *dm;
    ngx_dso_conf_ctx_t  *ctx;

    ctx = (ngx_dso_conf_ctx_t *) ngx_get_conf(cf->cycle->conf_ctx,
                                              ngx_dso_module);

    if (ctx == NULL || ctx->modules == NULL) {
        return;
    }

    dm = ctx->modules->elts;

    for (i = 0; i < ctx->modules->nelts; i++) {
        if (dm[i].name.len == 0) {
            continue;
        }

        name = dm[i].name;
        module = dm[i].module;

        ngx_log_stderr(0, "%V (shared):", &name);

        cmd = module->commands;
        if(cmd == NULL) {
            continue;
        }

        for ( /* void */ ; cmd->name.len; cmd++) {
            ngx_log_stderr(0, "    %V", &cmd->name);
        }
    }
}
