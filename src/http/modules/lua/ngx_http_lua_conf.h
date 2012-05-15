/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef NGX_HTTP_LUA_CONF_H
#define NGX_HTTP_LUA_CONF_H

#include "ngx_http_lua_common.h"

void * ngx_http_lua_create_main_conf(ngx_conf_t *cf);
char * ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf);

void * ngx_http_lua_create_loc_conf(ngx_conf_t *cf);
char * ngx_http_lua_merge_loc_conf(ngx_conf_t *cf, void *parent,
        void *child);

#endif /* NGX_HTTP_LUA_CONF_H */
