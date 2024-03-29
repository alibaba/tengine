
/*
 * Copyright (C) 2010-2017 Alibaba Group Holding Limited
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
                  "getloadavg is unsupported under current os");

    return NGX_ERROR;
#endif
}

#if (NGX_HAVE_PROC_MEMINFO)

static ngx_file_t                   ngx_meminfo_file;

#define NGX_MEMINFO_FILE            "/proc/meminfo"
#define NGX_MEMINFO_MAX_NAME_LEN    16


ngx_int_t
ngx_getmeminfo(ngx_meminfo_t *meminfo, ngx_log_t *log)
{
    u_char              buf[2048];
    u_char             *p, *start, *last;
    size_t             *sz = NULL;
    ssize_t             n, len;
    ngx_fd_t            fd;
    enum {
        sw_name = 0,
        sw_value_start,
        sw_value,
        sw_skipline,
        sw_newline,
    } state;

    ngx_memzero(meminfo, sizeof(ngx_meminfo_t));

    if (ngx_meminfo_file.fd == 0) {

        fd = ngx_open_file(NGX_MEMINFO_FILE, NGX_FILE_RDONLY,
                           NGX_FILE_OPEN,
                           NGX_FILE_DEFAULT_ACCESS);

        if (fd == NGX_INVALID_FILE) {
            ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                          ngx_open_file_n " \"%s\" failed",
                          NGX_MEMINFO_FILE);

            return NGX_ERROR;
        }

        ngx_meminfo_file.name.data = (u_char *) NGX_MEMINFO_FILE;
        ngx_meminfo_file.name.len = ngx_strlen(NGX_MEMINFO_FILE);

        ngx_meminfo_file.fd = fd;
    }

    ngx_meminfo_file.log = log;
    n = ngx_read_file(&ngx_meminfo_file, buf, sizeof(buf) - 1, 0);
    if (n == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                      ngx_read_file_n " \"%s\" failed",
                      NGX_MEMINFO_FILE);

        return NGX_ERROR;
    }

    p = buf;
    start = buf;
    last = buf + n;
    state = sw_name;

    for (; p < last; p++) {

        if (*p == '\n') {
            state = sw_newline;
        }

        switch (state) {

        case sw_name:
            if (*p != ':') {
                continue;
            }

            len = p - start;
            sz = NULL;

            switch (len) {
            case 6:
                /* Cached */
                if (meminfo->cachedram == 0 &&
                    ngx_strncmp(start, "Cached", len) == 0)
                {
                    sz = &meminfo->cachedram;
                }
                break;
            case 7:
                /* Buffers MemFree */
                if (meminfo->bufferram == 0 &&
                    ngx_strncmp(start, "Buffers", len) == 0)
                {
                    sz = &meminfo->bufferram;
                } else if (meminfo->freeram == 0 &&
                           ngx_strncmp(start, "MemFree", len) == 0)
                {
                    sz = &meminfo->freeram;
                }
                break;
            case 8:
                /* MemTotal SwapFree */
                if (meminfo->totalram == 0 &&
                    ngx_strncmp(start, "MemTotal", len) == 0)
                {
                    sz = &meminfo->totalram;
                } else if (meminfo->freeswap == 0 &&
                           ngx_strncmp(start, "SwapFree", len) == 0)
                {
                    sz = &meminfo->freeswap;
                }
                break;
            case 9:
                /* SwapTotal */
                if (meminfo->totalswap == 0 &&
                    ngx_strncmp(start, "SwapTotal", len) == 0)
                {
                    sz = &meminfo->totalswap;
                }
                break;
            }

            if (sz == NULL) {
                state = sw_skipline;
                continue;
            }

            state = sw_value_start;

            continue;

        case sw_value_start:

            if (*p == ' ') {
                continue;
            }

            start = p;
            state = sw_value;

            continue;

        case sw_value:

            if (*p >= '0' && *p <= '9') {
                continue;
            }

            *(sz) =  ngx_atosz(start, p - start) * 1024;

            state = sw_skipline;

            continue;

        case sw_skipline:

            continue;

        case sw_newline:

            state = sw_name;
            start = p + 1;

            continue;
        }
    }

    return NGX_OK;
}

#else

ngx_int_t
ngx_getmeminfo(ngx_meminfo_t *meminfo, ngx_log_t *log)
{
    ngx_log_error(NGX_LOG_EMERG, log, 0,
                  "getmeminfo is unsupported under current os");

    return NGX_ERROR;
}

#endif

#if (NGX_HAVE_PROC_STAT)

static ngx_file_t                   ngx_cpuinfo_file;

#define NGX_CPUINFO_FILE            "/proc/stat"


ngx_int_t
ngx_getcpuinfo(ngx_str_t *cpunumber, ngx_cpuinfo_t *cpuinfo, ngx_log_t *log)
{
    u_char              buf[1024 * 1024];
    u_char             *p, *q, *last;
    ssize_t             n;
    ngx_fd_t            fd;
    time_t              cputime;
    enum {
        sw_user = 0,
        sw_nice,
        sw_sys,
        sw_idle,
        sw_iowait,
        sw_irq,
        sw_softirq ,        
    } state;

    ngx_memzero(cpuinfo, sizeof(ngx_cpuinfo_t));

    if (ngx_cpuinfo_file.fd == 0) {

        fd = ngx_open_file(NGX_CPUINFO_FILE, NGX_FILE_RDONLY,
                           NGX_FILE_OPEN,
                           NGX_FILE_DEFAULT_ACCESS);

        if (fd == NGX_INVALID_FILE) {
            ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                          ngx_open_file_n " \"%s\" failed",
                          NGX_CPUINFO_FILE);

            return NGX_ERROR;
        }

        ngx_cpuinfo_file.name.data = (u_char *) NGX_CPUINFO_FILE;
        ngx_cpuinfo_file.name.len = ngx_strlen(NGX_CPUINFO_FILE);

        ngx_cpuinfo_file.fd = fd;
    }

    ngx_cpuinfo_file.log = log;
    n = ngx_read_file(&ngx_cpuinfo_file, buf, sizeof(buf) - 1, 0);
    if (n == NGX_ERROR) {
        ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                      ngx_read_file_n " \"%s\" failed",
                      NGX_CPUINFO_FILE);

        return NGX_ERROR;
    }

    p = buf;
    last = buf + n;
    
    for (; p < last; p++) {
        while(*p == ' ' || *p == '\n') {
            p++;
        }
        
        if (ngx_strncasecmp((u_char *) cpunumber->data,
                            (u_char *) p, cpunumber->len) == 0) 
        {
            
            for (state = 0, p += cpunumber->len, 
                 q = (u_char *) strtok((char *) p, " "); q; state++) 
            {
                cputime = ngx_atotm(q, strlen((char *) q));
                        
                switch (state) {
                case sw_user:
                    cpuinfo->usr = cputime;
                    break;
                case sw_nice:
                    cpuinfo->nice = cputime;
                    break;
                case sw_sys:
                    cpuinfo->sys = cputime;
                    break;
                case sw_idle:
                    cpuinfo->idle = cputime;
                    break;
                case sw_iowait:
                    cpuinfo->iowait = cputime;
                    break;
                case sw_irq:
                    cpuinfo->irq = cputime;
                    break;  
                case sw_softirq:
                    cpuinfo->softirq = cputime;
                    break;                    
                }    
                
                q = (u_char *) strtok(NULL, " ");
            }
        }
        
        break;
        
    }

    return NGX_OK;
}

#else

ngx_int_t
ngx_getcpuinfo(ngx_str_t *cpunumber, ngx_cpuinfo_t *cpuinfo, ngx_log_t *log)
{
    ngx_log_error(NGX_LOG_EMERG, log, 0,
                  "ngx_getcpuinfo is unsupported under current os");

    return NGX_ERROR;
}

#endif
