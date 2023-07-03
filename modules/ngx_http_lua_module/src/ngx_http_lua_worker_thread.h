/*
 * Copyright (C) Yichun Zhang (agentzh)
 * Copyright (C) Jinhua Luo (kingluo)
 * I hereby assign copyright in this code to the lua-nginx-module project,
 * to be licensed under the same terms as the rest of the code.
 */

#ifndef _NGX_HTTP_LUA_WORKER_THREAD_H_INCLUDED_
#define _NGX_HTTP_LUA_WORKER_THREAD_H_INCLUDED_


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_worker_thread_api(ngx_log_t *log, lua_State *L);
void ngx_http_lua_thread_exit_process(void);


#endif /* _NGX_HTTP_LUA_WORKER_THREAD_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
