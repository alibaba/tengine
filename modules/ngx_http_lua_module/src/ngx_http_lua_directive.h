
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_DIRECTIVE_H_INCLUDED_
#define _NGX_HTTP_LUA_DIRECTIVE_H_INCLUDED_


#include "ngx_http_lua_common.h"


char *ngx_http_lua_shared_dict(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
char *ngx_http_lua_package_cpath(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_package_path(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_content_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_content_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_rewrite_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_rewrite_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_access_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_access_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_log_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_log_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_header_filter_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
char *ngx_http_lua_header_filter_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_body_filter_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
char *ngx_http_lua_body_filter_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_init_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_init_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_init_worker_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
char *ngx_http_lua_init_worker_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_code_cache(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

#if defined(NDK) && NDK

char *ngx_http_lua_set_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_set_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
char *ngx_http_lua_set_by_lua_file(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
ngx_int_t ngx_http_lua_filter_set_by_lua_inline(ngx_http_request_t *r,
    ngx_str_t *val, ngx_http_variable_value_t *v, void *data);
ngx_int_t ngx_http_lua_filter_set_by_lua_file(ngx_http_request_t *r,
    ngx_str_t *val, ngx_http_variable_value_t *v, void *data);

#endif

char *ngx_http_lua_rewrite_no_postpone(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_http_lua_conf_lua_block_parse(ngx_conf_t *cf,
    ngx_command_t *cmd);
char *ngx_http_lua_capture_error_log(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


#endif /* _NGX_HTTP_LUA_DIRECTIVE_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
