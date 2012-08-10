/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <nginx.h>
#include "ngx_http_lua_conf.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_probe.h"


static void ngx_http_lua_cleanup_vm(void *data);


void *
ngx_http_lua_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_main_conf_t));
    if (lmcf == NULL) {
        return NULL;
    }

    /* set by ngx_pcalloc:
     *      lmcf->lua = NULL;
     *      lmcf->lua_path = { 0, NULL };
     *      lmcf->lua_cpath = { 0, NULL };
     *      lmcf->regex_cache_entries = 0;
     *      lmcf->shm_zones = NULL;
     *      lmcf->init_handler = NULL;
     *      lmcf->init_src = { 0, NULL };
     *      lmcf->shm_zones_inited = 0;
     *      lmcf->preload_hooks = NULL;
     *      lmcf->requires_header_filter = 0;
     *      lmcf->requires_body_filter = 0;
     *      lmcf->requires_capture_filter = 0;
     *      lmcf->requires_rewrite = 0;
     *      lmcf->requires_access = 0;
     *      lmcf->requires_log = 0;
     *      lmcf->requires_shm = 0;
     */

    lmcf->pool = cf->pool;
#if (NGX_PCRE)
    lmcf->regex_cache_max_entries = NGX_CONF_UNSET;
#endif
    lmcf->postponed_to_rewrite_phase_end = NGX_CONF_UNSET;

    dd("nginx Lua module main config structure initialized!");

    return lmcf;
}


char *
ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf)
{
#if (NGX_PCRE)
    ngx_http_lua_main_conf_t *lmcf = conf;

    if (lmcf->regex_cache_max_entries == NGX_CONF_UNSET) {
        lmcf->regex_cache_max_entries = 1024;
    }
#endif

    return NGX_CONF_OK;
}


void *
ngx_http_lua_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_lua_loc_conf_t *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_loc_conf_t));
    if (conf == NULL) {
        return NGX_CONF_ERROR;
    }

    /* set by ngx_pcalloc:
     *      conf->access_src  = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->access_src_key = NULL
     *      conf->rewrite_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->rewrite_src_key = NULL
     *      conf->rewrite_handler = NULL;
     *
     *      conf->content_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->content_src_key = NULL
     *      conf->content_handler = NULL;
     *
     *      conf->log_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->log_src_key = NULL
     *      conf->log_handler = NULL;
     *
     *      conf->header_filter_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->header_filter_src_key = NULL
     *      conf->header_filter_handler = NULL;
     *
     *      conf->body_filter_src = {{ 0, NULL }, NULL, NULL, NULL};
     *      conf->body_filter_src_key = NULL
     *      conf->body_filter_handler = NULL;
     */

    conf->force_read_body   = NGX_CONF_UNSET;
    conf->enable_code_cache = NGX_CONF_UNSET;
    conf->http10_buffering  = NGX_CONF_UNSET;

    conf->keepalive_timeout = NGX_CONF_UNSET_MSEC;
    conf->connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->send_timeout = NGX_CONF_UNSET_MSEC;
    conf->read_timeout = NGX_CONF_UNSET_MSEC;
    conf->send_lowat = NGX_CONF_UNSET_SIZE;
    conf->buffer_size = NGX_CONF_UNSET_SIZE;
    conf->pool_size = NGX_CONF_UNSET_UINT;

    conf->transform_underscores_in_resp_headers = NGX_CONF_UNSET;

    return conf;
}


char *
ngx_http_lua_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_lua_loc_conf_t *prev = parent;
    ngx_http_lua_loc_conf_t *conf = child;

    if (conf->rewrite_src.value.len == 0) {
        conf->rewrite_src = prev->rewrite_src;
        conf->rewrite_handler = prev->rewrite_handler;
        conf->rewrite_src_key = prev->rewrite_src_key;
    }

    if (conf->access_src.value.len == 0) {
        conf->access_src = prev->access_src;
        conf->access_handler = prev->access_handler;
        conf->access_src_key = prev->access_src_key;
    }

    if (conf->content_src.value.len == 0) {
        conf->content_src = prev->content_src;
        conf->content_handler = prev->content_handler;
        conf->content_src_key = prev->content_src_key;
    }

    if (conf->log_src.value.len == 0) {
        conf->log_src = prev->log_src;
        conf->log_handler = prev->log_handler;
        conf->log_src_key = prev->log_src_key;
    }

    if (conf->header_filter_src.value.len == 0) {
        conf->header_filter_src = prev->header_filter_src;
        conf->header_filter_handler = prev->header_filter_handler;
        conf->header_filter_src_key = prev->header_filter_src_key;
    }

    if (conf->body_filter_src.value.len == 0) {
        conf->body_filter_src = prev->body_filter_src;
        conf->body_filter_handler = prev->body_filter_handler;
        conf->body_filter_src_key = prev->body_filter_src_key;
    }

    ngx_conf_merge_value(conf->force_read_body, prev->force_read_body, 0);
    ngx_conf_merge_value(conf->enable_code_cache, prev->enable_code_cache, 1);
    ngx_conf_merge_value(conf->http10_buffering, prev->http10_buffering, 1);

    ngx_conf_merge_msec_value(conf->keepalive_timeout,
                              prev->keepalive_timeout, 60000);

    ngx_conf_merge_msec_value(conf->connect_timeout,
                              prev->connect_timeout, 60000);

    ngx_conf_merge_msec_value(conf->send_timeout,
                              prev->send_timeout, 60000);

    ngx_conf_merge_msec_value(conf->read_timeout,
                              prev->read_timeout, 60000);

    ngx_conf_merge_size_value(conf->send_lowat,
                              prev->send_lowat, 0);

    ngx_conf_merge_size_value(conf->buffer_size,
                              prev->buffer_size,
                              (size_t) ngx_pagesize);

    ngx_conf_merge_uint_value(conf->pool_size, prev->pool_size, 30);

    ngx_conf_merge_value(conf->transform_underscores_in_resp_headers,
                         prev->transform_underscores_in_resp_headers, 1);

    return NGX_CONF_OK;
}


static void
ngx_http_lua_cleanup_vm(void *data)
{
    lua_State *L = data;

    if (L != NULL) {
        lua_close(L);

        dd("Lua VM closed!");
    }
}


char *
ngx_http_lua_init_vm(ngx_conf_t *cf, ngx_http_lua_main_conf_t *lmcf)
{
    ngx_pool_cleanup_t              *cln;
    ngx_http_lua_preload_hook_t     *hook;
    lua_State                       *L;
    ngx_uint_t                       i;

    /* add new cleanup handler to config mem pool */
    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {
        return NGX_CONF_ERROR;
    }

    /* create new Lua VM instance */
    lmcf->lua = ngx_http_lua_new_state(cf, lmcf);
    if (lmcf->lua == NULL) {
        return NGX_CONF_ERROR;
    }

    /* register cleanup handler for Lua VM */
    cln->handler = ngx_http_lua_cleanup_vm;
    cln->data = lmcf->lua;

    if (lmcf->preload_hooks) {

        /* register the 3rd-party module's preload hooks */

        L = lmcf->lua;

        lua_getglobal(L, "package");
        lua_getfield(L, -1, "preload");

        hook = lmcf->preload_hooks->elts;

        for (i = 0; i < lmcf->preload_hooks->nelts; i++) {

            ngx_http_lua_probe_register_preload_package(L, hook[i].package);

            lua_pushcfunction(L, hook[i].loader);
            lua_setfield(L, -2, hook[i].package);
        }

        lua_pop(L, 2);
    }

    return NGX_CONF_OK;
}

