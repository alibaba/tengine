
/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
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

typedef struct {
    char    *name;
    size_t  *slot;
} ngx_mem_table_t;


static ngx_file_t                   ngx_meminfo_file;

#define NGX_MEMINFO_FILE            "/proc/meminfo"
#define NGX_MEMINFO_MAX_NAME_LEN    16


ngx_int_t
ngx_getmeminfo(ngx_meminfo_t *meminfo, ngx_log_t *log)
{
    u_char              buf[2048];
    u_char             *p, *start, *last;
    ssize_t             n, len;
    ngx_fd_t            fd;
    ngx_int_t           i;
    ngx_mem_table_t    *found = NULL;
    enum {
        sw_name = 0,
        sw_value_start,
        sw_value,
        sw_skipline,
        sw_newline,
    } state;

    ngx_mem_table_t mem_table[] = {
         {"Buffers",      &meminfo->bufferram},
         {"Cached",       &meminfo->cachedram},
         {"MemFree",      &meminfo->freeram},
         {"MemTotal",     &meminfo->totalram},
         {"SwapFree",     &meminfo->freeswap},
         {"SwapTotal",    &meminfo->totalswap},
    };
    const ngx_int_t mem_table_count = sizeof(mem_table)/sizeof(ngx_mem_table_t);

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

            if (len >= NGX_MEMINFO_MAX_NAME_LEN) {
                state = sw_skipline;
                continue;
            }

            found = NULL;

            for (i = 0; i < mem_table_count; i++) {
                if (ngx_strncmp(start, mem_table[i].name, len) == 0) {
                    found = &mem_table[i];
                }
            }

            if (!found) {
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

            *(found->slot) =  ngx_atosz(start, p - start) * 1024;

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
