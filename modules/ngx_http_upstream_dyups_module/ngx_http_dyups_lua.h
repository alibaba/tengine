/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_DYUPS_LUA_H_INCLUDE_
#define _NGX_HTTP_DYUPS_LUA_H_INCLUDE_

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http_lua_api.h>
#include <lualib.h>
#include <lauxlib.h>


ngx_int_t ngx_http_dyups_lua_preload(ngx_conf_t *cf);


#endif
