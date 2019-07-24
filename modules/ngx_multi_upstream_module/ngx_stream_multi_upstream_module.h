
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2018 Alibaba Group Holding Limited
 */

#ifndef _NGX_STREAM_MULTI_UPSTREAM_H_
#define _NGX_STREAM_MULTI_UPSTREAM_H_

#include "ngx_stream.h"
#include "ngx_multi_upstream_module.h"

ngx_stream_session_t* ngx_stream_multi_get_session(ngx_connection_t *c);

ngx_int_t ngx_stream_multi_upstream_connection_detach(ngx_connection_t *c);
ngx_int_t ngx_stream_multi_upstream_connection_close(ngx_connection_t *c);

ngx_flag_t ngx_stream_multi_connection_fake(ngx_stream_session_t *s);

#endif
