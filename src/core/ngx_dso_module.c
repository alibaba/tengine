
/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <nginx.h>
#include <dlfcn.h>


#define NGX_DSO_MODULE_PREFIX   "ngx_"


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
} ngx_dso_conf_t;


static void *ngx_dso_create_conf(ngx_cycle_t *cycle);
static char *ngx_dso_init_conf(ngx_cycle_t *cycle, void *conf);

static char *ngx_dso_load(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_dso_check_duplicated(ngx_cycle_t *cycle, ngx_array_t *modules,
    ngx_str_t *name, ngx_str_t *path);
static char *ngx_dso_order(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_dso_order_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

static ngx_int_t ngx_dso_get_position(ngx_str_t *module_entry);

static ngx_int_t ngx_dso_find_postion(ngx_dso_conf_t *dcf, ngx_str_t module_name);


static ngx_command_t  ngx_dso_module_commands[] = {

    { ngx_string("dso_order"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_dso_order_block,
      0,
      0,
      NULL },

    { ngx_string("dso_path"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      0,
      offsetof(ngx_dso_conf_t, path),
      NULL },

    { ngx_string("dso_load"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE2,
      ngx_dso_load,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_core_module_t  ngx_dso_module_ctx = {
    ngx_string("dso"),
    ngx_dso_create_conf,
    ngx_dso_init_conf
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


extern ngx_uint_t ngx_max_module;
static ngx_str_t ngx_default_modules_prefix = ngx_string(NGX_DSO_PATH);


static ngx_dso_flagpole_t module_flagpole[] = {

    { ngx_string("filter"), ngx_string("ngx_http_copy_filter_module")},
    {ngx_null_string, ngx_null_string}
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


static ngx_int_t
ngx_dso_check_duplicated(ngx_cycle_t *cycle, ngx_array_t *modules,
    ngx_str_t *name, ngx_str_t *path)
{
    size_t                               len;
    ngx_uint_t                           i, j;
    ngx_dso_module_t                    *m;
    ngx_dso_conf_t                      *old_dcf;
    ngx_dso_module_t                    *old_dl_m;

    if (cycle->old_cycle->conf_ctx != NULL) {
        old_dcf = (ngx_dso_conf_t *) ngx_get_conf(cycle->old_cycle->conf_ctx,
            ngx_dso_module);
        if (old_dcf != NULL) {
            old_dl_m = old_dcf->modules->elts;

            for (i = 0; i < old_dcf->modules->nelts; i++) {
                if (old_dl_m[i].name.len == 0) {
                    continue;
                }

                if ((name->len == old_dl_m[i].name.len
                    && ngx_strncmp(name->data, old_dl_m[i].name.data, old_dl_m[i].name.len) == 0)
                   || (path->len == old_dl_m[i].path.len
                      && ngx_strncmp(path->data, old_dl_m[i].path.data, old_dl_m[i].path.len) == 0))
                {
                    return NGX_DECLINED;
                }
            }
        }
    }

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
ngx_dso_full_name(ngx_cycle_t *cycle, ngx_dso_conf_t *dcf, ngx_str_t *name)
{
    size_t      len, size;
    u_char     *p, *n, *prefix;

    if (name->data[0] == '/') {
        return NGX_OK;
    }

    if (dcf->path.data == NULL) {
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
        if (dcf->path.data[0] != '/') {
            return NGX_ERROR;
        }

        len = dcf->path.len;
        prefix = dcf->path.data;
        size = len + name->len + 1;
    }

    n = ngx_pnalloc(cycle->pool, size + 1);
    if (n == NULL) {
        return NGX_ERROR;
    }

    p = ngx_cpymem(n, prefix, len);

    if (dcf->path.data == NULL
       && ngx_default_modules_prefix.data[0] != '/') {
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
ngx_dso_order_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                                *rv;
    ngx_conf_t                           save;
    ngx_dso_conf_t                      *dcf;

    dcf = conf;

    if (dcf->order != NULL) {
        return "is duplicate";
    }

    if (dcf->modules->nelts > 0) {
        return "order block must appear to before load derective";
    }

    dcf->order = ngx_array_create(cf->pool, 10, sizeof(ngx_str_t));
    if (dcf->order == NULL) {
        return NGX_CONF_ERROR;
    }

    save = *cf;
    cf->module_type = NGX_CORE_MODULE;

    cf->handler = ngx_dso_order;
    cf->handler_conf = (void *) dcf;

    rv = ngx_conf_parse(cf, NULL);

    *cf = save;

    return rv;
}


static char *
ngx_dso_order(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_dso_conf_t *dcf = conf;

    ngx_str_t                            *value, *module_name;

    value = cf->args->elts;

    if (cf->args->nelts != 1
       || ngx_strncasecmp(value[0].data, (u_char *) NGX_DSO_MODULE_PREFIX,
           sizeof(NGX_DSO_MODULE_PREFIX) - 1) != 0)
    {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                "unknown directive \"%s\"", value[0].data);
        return NGX_CONF_ERROR;
    }

    module_name = ngx_array_push(dcf->order);
    if (module_name == NULL) {
        return NGX_CONF_ERROR;
    }

    *module_name = value[0];

    return NGX_CONF_OK;
}


static char *
ngx_dso_load(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_dso_conf_t *dcf = conf;

    char                                 *rv;
    ngx_int_t                             postion;
    ngx_str_t                            *value, module_path, module_name;
    ngx_dso_module_t                     *dl_m;

    value = cf->args->elts;

    if (dcf->modules->nelts >= NGX_DSO_MAX) {
        ngx_log_stderr(0, "Module \"%V\" could not be loaded, "
            "because the dso module limit(%ui) was reached.",
                      &value[1], NGX_DSO_MAX);
        return NGX_CONF_ERROR;
    }

    module_name = value[1];
    module_path = value[2];

    if (ngx_dso_check_duplicated(cf->cycle, dcf->modules,
                                &module_name, &module_path) == NGX_DECLINED)
    {
        return NGX_CONF_OK;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_CORE, cf->log, 0, "load module(%V)", module_path);

    dl_m = ngx_array_push(dcf->modules);

    if (ngx_dso_full_name(cf->cycle, dcf, &module_path) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    dl_m->name = module_name;
    dl_m->path = module_path;

    if (ngx_dso_open(dl_m) == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    if (dl_m->module->type == NGX_CORE_MODULE) {
        ngx_log_stderr(0,"dso module not support core module");
        return NGX_CONF_ERROR;
    }

    if (dl_m->module->major_version != NGX_NUMBER_MAJOR
       || dl_m->module->minor_version > NGX_NUMBER_MINOR)
    {
        ngx_log_stderr(0,"Module \"%V\" is not compatible with this "
            "version of Tengine (found %d.%d, need %d.%d). Please "
            "contact the vendor for the correct version.",
                      &module_name, dl_m->module->major_version,
            dl_m->module->minor_version, NGX_NUMBER_MAJOR, NGX_NUMBER_MINOR);
        return NGX_CONF_ERROR;
    }

    postion = ngx_dso_find_postion(dcf, module_name);

    ngx_log_debug1(NGX_LOG_DEBUG_CORE, cf->log, 0, "dso find postion(%i)", postion);

    rv = ngx_dso_insert_module(dl_m->module, postion);
    if (rv == NGX_CONF_ERROR) {
        return rv;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_dso_find_postion(ngx_dso_conf_t *dcf, ngx_str_t module_name)
{
    size_t                   len1, len2, len3;
    ngx_int_t                near;
    ngx_uint_t               i, k;
    ngx_str_t               *name;

    near = dcf->flag_postion;

    if (dcf->order == NULL || dcf->order->nelts == 0) {

        for (i = 0; ngx_all_module_names[i]; i++) {
            len1 = ngx_strlen(ngx_all_module_names[i]);
            if (len1 == module_name.len
               && ngx_strncmp(ngx_all_module_names[i], module_name.data, len1) == 0)
            {
                return near;
            }

            if (i == 0) {
                continue;
            }

            len2 = ngx_strlen(ngx_all_module_names[i - 1]);
            for (k = 0; ngx_module_names[k]; k++) {
                len3 = ngx_strlen(ngx_module_names[k]);

                if (len2 == len3
                   && ngx_strncmp(ngx_all_module_names[i - 1], ngx_module_names[k], len2) == 0)
                {
                    near = k + 1;
                    break;
                }
            }
        }

        if (ngx_all_module_names[i] == NULL) {
            return ++dcf->flag_postion;
        }
    }

    name = dcf->order->elts;
    near = dcf->flag_postion;

    for (i = 0; i < dcf->order->nelts; i++) {
        if (name[i].len == module_name.len
           && ngx_strncmp(name[i].data, module_name.data, name[i].len) == 0)
        {
            return near;
        }

        if (i == 0) {
            continue;
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

    return ++dcf->flag_postion;
}


void
ngx_show_dso_modules(ngx_conf_t *cf)
{
    ngx_str_t                                 module_name;
    ngx_uint_t                                i;
    ngx_module_t                             *module;
    ngx_dso_conf_t                           *dcf;
    ngx_dso_module_t                         *dl_m;

    dcf = (ngx_dso_conf_t *) ngx_get_conf(cf->cycle->conf_ctx,
                                           ngx_dso_module);

    if (dcf == NULL) {
        return;
    }

    dl_m = dcf->modules->elts;

    for (i = 0; i < dcf->modules->nelts; i++) {
        if (dl_m[i].name.len == 0) {
            continue;
        }

        module_name = dl_m[i].name;
        module = dl_m[i].module;

        ngx_log_stderr(0, "    %V (shared), require nginx version (%d.%d)",
                       &module_name, module->major_version, module->minor_version);
    }
}


static char *
ngx_dso_init_conf(ngx_cycle_t *cycle, void *conf)
{
    return NGX_CONF_OK;
}


static void *
ngx_dso_create_conf(ngx_cycle_t *cycle)
{
    ngx_dso_conf_t                 *conf;

    conf = ngx_pcalloc(cycle->pool, sizeof(ngx_dso_conf_t));
    if (conf == NULL) {
        return NGX_CONF_ERROR;
    }

    conf->flag_postion = ngx_dso_get_position(&module_flagpole[0].entry);
    if (conf->flag_postion == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    conf->modules = ngx_array_create(cycle->pool, 10, sizeof(ngx_dso_module_t));
    if (conf->modules == NULL) {
        return NGX_CONF_ERROR;
    }
    
    return conf;
}
