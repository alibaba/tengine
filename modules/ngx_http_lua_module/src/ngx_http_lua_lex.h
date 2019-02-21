
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_LEX_H_INCLUDED_
#define _NGX_HTTP_LUA_LEX_H_INCLUDED_


#include "ngx_http_lua_common.h"


int ngx_http_lua_lex(const u_char *const s, size_t len, int *const ovec);


#endif
