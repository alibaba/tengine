
/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>

#if (NGX_HAVE_SYSINFO)
#include <sys/sysinfo.h>
#endif


ngx_int_t
ngx_getloadavg(ngx_int_t avg[], ngx_int_t nelem, ngx_log_t *log)
{
#if (NGX_HAVE_GETLOADAVG)
    double      loadavg[3];
    ngx_int_t   i;

    if (getloadavg(loadavg, nelem) == -1) {
        return NGX_ERROR;
    }

    for (i = 0; i < nelem; i ++) {
        avg[i] = loadavg[i] * 1000;
    }

    return NGX_OK;

#elif (NGX_HAVE_SYSINFO)

    struct sysinfo s;
    ngx_int_t   i;

    if (sysinfo(&s)) {
        return NGX_ERROR;
    }

    for (i = 0; i < nelem; i ++) {
        avg[i] = s.loads[i] * 1000 / 65536;
    }

    return NGX_OK;

#else

    ngx_log_error(NGX_LOG_EMERG, log, 0,
                  "getloadavg is unsurpported under current os");

    return NGX_ERROR;
#endif
}


ngx_int_t
ngx_getmeminfo(ngx_meminfo_t *meminfo, ngx_log_t *log)
{
#if (NGX_HAVE_SYSINFO)
    struct sysinfo s;

    if (sysinfo(&s)) {
        return NGX_ERROR;
    }

    meminfo->totalram = s.totalram;
    meminfo->freeram = s.freeram;
    meminfo->sharedram = s.sharedram;
    meminfo->bufferram = s.bufferram;
    meminfo->totalswap = s.totalswap;
    meminfo->freeswap = s.freeswap;

    return NGX_OK;
#else
    ngx_log_error(NGX_LOG_EMERG, log, 0,
                  "getmeminfo is unsurpported under current os");
    return NGX_ERROR;
#endif
}
