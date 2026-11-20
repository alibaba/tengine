/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-in for the generated ngx_config.h, used only by the stand-alone
 * hessian2 unit tests. utils.h includes it for the byte order helpers
 * (ntohs/ntohl/htonl/htons); nothing else from nginx is needed to build the
 * hessian2 codec.
 */

#ifndef _NGX_CONFIG_H_INCLUDED_
#define _NGX_CONFIG_H_INCLUDED_

#include <sys/types.h>
#include <arpa/inet.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#endif /* _NGX_CONFIG_H_INCLUDED_ */
