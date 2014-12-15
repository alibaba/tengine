/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>

#if (NGX_PROCS_LUA)
#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_util.h"
#endif


#if (NGX_PROCS_LUA)
char *
ngx_proc_set_lua_file_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_proc_conf_t  *pcf = conf;

    u_char     *name;
    ngx_str_t  *value;

    value = cf->args->elts;
    name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                    value[1].len);
    if (name == NULL) {
        return "lua file path error";
    }

    pcf->lua_file.data = name;
    pcf->lua_file.len = ngx_strlen(name);

    return NGX_CONF_OK;
}


ngx_int_t
ngx_procs_process_lua_init(ngx_cycle_t *cycle, ngx_proc_conf_t *pcf)
{
    ngx_http_lua_main_conf_t  *lmcf;

    lmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_lua_module);

    if (pcf->lua_src.len) {
        lmcf->init_worker_src = pcf->lua_src;
        lmcf->init_worker_handler = ngx_http_lua_init_worker_by_inline;
    } else if (pcf->lua_file.len) {
        lmcf->init_worker_src = pcf->lua_file;
        lmcf->init_worker_handler = ngx_http_lua_init_worker_by_file;
    } else {
        return NGX_OK;
    }

    return ngx_http_lua_init_worker(cycle);
}
#endif
