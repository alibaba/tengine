
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
    int                 i;
    u_char              buf[2048], *head, *tail;
    ssize_t             n, len;
    ngx_fd_t            fd;
    ngx_mem_table_t    *found;

    ngx_mem_table_t mem_table[] = {
         {"Buffers",      &meminfo->bufferram},
         {"Cached",       &meminfo->cachedram},
         {"MemFree",      &meminfo->freeram},
         {"MemTotal",     &meminfo->totalram},
         {"SwapFree",     &meminfo->freeswap},
         {"SwapTotal",    &meminfo->totalswap},
    };
    const int mem_table_count = sizeof(mem_table)/sizeof(ngx_mem_table_t);

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

    buf[n] = '\0';

    head = buf;
    for (;;) {

        tail = (u_char *) ngx_strchr(head, ':');
        if (!tail) break;
        *tail = '\0';
        len = tail - head;

        if (len >= NGX_MEMINFO_MAX_NAME_LEN) {
            head = tail + 1;
            goto nextline;
        }

        found = NULL;

        for (i = 0; i < mem_table_count; i++) {
            if (ngx_strcmp(head, mem_table[i].name) == 0) {
               found = &mem_table[i];
            }
        }

        head = tail + 1;

        if (!found) {
            goto nextline;
        }

        *(found->slot) = strtoul((char *) head, (char **) &tail, 10) * 1024;

nextline:
        tail = (u_char *)ngx_strchr(head, '\n');
        if(!tail) break;
        head = tail+1;
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
