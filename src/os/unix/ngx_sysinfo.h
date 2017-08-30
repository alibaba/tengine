/*
 * Copyright (C) 2010-2017 Alibaba Group Holding Limited
 */


#ifndef _NGX_SYSINFO_H_INCLUDED_
#define _NGX_SYSINFO_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>


/* in bytes */
typedef struct {
    size_t totalram;
    size_t freeram;
    size_t bufferram;
    size_t cachedram;
    size_t totalswap;
    size_t freeswap;
} ngx_meminfo_t;


typedef struct {
    time_t usr;
    time_t nice;
    time_t sys;
    time_t idle;
    time_t iowait;
    time_t irq;
    time_t softirq;    
}ngx_cpuinfo_t;


ngx_int_t ngx_getloadavg(ngx_int_t avg[], ngx_int_t nelem, ngx_log_t *log);
ngx_int_t ngx_getmeminfo(ngx_meminfo_t *meminfo, ngx_log_t *log);
ngx_int_t ngx_getcpuinfo(ngx_str_t *cpunumber, ngx_cpuinfo_t *cpuinfo,
    ngx_log_t *log);

#endif /* _NGX_SYSINFO_H_INCLUDED_ */

