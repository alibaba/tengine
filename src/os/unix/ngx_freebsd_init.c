
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>


/* FreeBSD 3.0 at least */
char    ngx_freebsd_kern_ostype[16];
char    ngx_freebsd_kern_osrelease[128];
int     ngx_freebsd_kern_osreldate;
int     ngx_freebsd_hw_ncpu;
int     ngx_freebsd_kern_ipc_somaxconn;
u_long  ngx_freebsd_net_inet_tcp_sendspace;

/* FreeBSD 4.9 */
int     ngx_freebsd_machdep_hlt_logical_cpus;


ngx_uint_t  ngx_freebsd_sendfile_nbytes_bug;
ngx_uint_t  ngx_freebsd_use_tcp_nopush;

ngx_uint_t  ngx_debug_malloc;


static ngx_os_io_t ngx_freebsd_io = {
    ngx_unix_recv,
    ngx_readv_chain,
    ngx_udp_unix_recv,
    ngx_unix_send,
#if (NGX_HAVE_SENDFILE)
    ngx_freebsd_sendfile_chain,
    NGX_IO_SENDFILE
#else
    ngx_writev_chain,
    0
#endif
};


typedef struct {
    char        *name;
    void        *value;
    size_t       size;
    ngx_uint_t   exists;
} sysctl_t;


sysctl_t sysctls[] = {
    { "hw.ncpu",
      &ngx_freebsd_hw_ncpu,
      sizeof(ngx_freebsd_hw_ncpu), 0 },

    { "machdep.hlt_logical_cpus",
      &ngx_freebsd_machdep_hlt_logical_cpus,
      sizeof(ngx_freebsd_machdep_hlt_logical_cpus), 0 },

    { "net.inet.tcp.sendspace",
      &ngx_freebsd_net_inet_tcp_sendspace,
      sizeof(ngx_freebsd_net_inet_tcp_sendspace), 0 },

    { "kern.ipc.somaxconn",
      &ngx_freebsd_kern_ipc_somaxconn,
      sizeof(ngx_freebsd_kern_ipc_somaxconn), 0 },

    { NULL, NULL, 0, 0 }
};


void
ngx_debug_init()
{
#if (NGX_DEBUG_MALLOC)

#if __FreeBSD_version >= 500014 && __FreeBSD_version < 1000011
    _malloc_options = "J";
#elif __FreeBSD_version < 500014
    malloc_options = "J";
#endif

    ngx_debug_malloc = 1;

#else
    char  *mo;

    mo = getenv("MALLOC_OPTIONS");

    if (mo && ngx_strchr(mo, 'J')) {
        ngx_debug_malloc = 1;
    }
#endif
}


ngx_int_t
ngx_os_specific_init(ngx_log_t *log)
{
    int         version;
    size_t      size;
    ngx_err_t   err;
    ngx_uint_t  i;

    size = sizeof(ngx_freebsd_kern_ostype);
    if (sysctlbyname("kern.ostype",
                     ngx_freebsd_kern_ostype, &size, NULL, 0) == -1) {
        ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                      "sysctlbyname(kern.ostype) failed");

        if (ngx_errno != NGX_ENOMEM) {
            return NGX_ERROR;
        }

        ngx_freebsd_kern_ostype[size - 1] = '\0';
    }

    size = sizeof(ngx_freebsd_kern_osrelease);
    if (sysctlbyname("kern.osrelease",
                     ngx_freebsd_kern_osrelease, &size, NULL, 0) == -1) {
        ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                      "sysctlbyname(kern.osrelease) failed");

        if (ngx_errno != NGX_ENOMEM) {
            return NGX_ERROR;
        }

        ngx_freebsd_kern_osrelease[size - 1] = '\0';
    }


    size = sizeof(int);
    if (sysctlbyname("kern.osreldate",
                     &ngx_freebsd_kern_osreldate, &size, NULL, 0) == -1) {
        ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                      "sysctlbyname(kern.osreldate) failed");
        return NGX_ERROR;
    }

    version = ngx_freebsd_kern_osreldate;


#if (NGX_HAVE_SENDFILE)

    /*
     * The determination of the sendfile() "nbytes bug" is complex enough.
     * There are two sendfile() syscalls: a new #393 has no bug while
     * an old #336 has the bug in some versions and has not in others.
     * Besides libc_r wrapper also emulates the bug in some versions.
     * There is no way to say exactly if syscall #336 in FreeBSD circa 4.6
     * has the bug.  We use the algorithm that is correct at least for
     * RELEASEs and for syscalls only (not libc_r wrapper).
     *
     * 4.6.1-RELEASE and below have the bug
     * 4.6.2-RELEASE and above have the new syscall
     *
     * We detect the new sendfile() syscall available at the compile time
     * to allow an old binary to run correctly on an updated FreeBSD system.
     */

#if (__FreeBSD__ == 4 && __FreeBSD_version >= 460102) \
    || __FreeBSD_version == 460002 || __FreeBSD_version >= 500039

    /* a new syscall without the bug */

    ngx_freebsd_sendfile_nbytes_bug = 0;

#else

    /* an old syscall that may have the bug */

    ngx_freebsd_sendfile_nbytes_bug = 1;

#endif

#endif /* NGX_HAVE_SENDFILE */


    if ((version < 500000 && version >= 440003) || version >= 500017) {
        ngx_freebsd_use_tcp_nopush = 1;
    }


    for (i = 0; sysctls[i].name; i++) {
        size = sysctls[i].size;

        if (sysctlbyname(sysctls[i].name, sysctls[i].value, &size, NULL, 0)
            == 0)
        {
            sysctls[i].exists = 1;
            continue;
        }

        err = ngx_errno;

        if (err == NGX_ENOENT) {
            continue;
        }

        ngx_log_error(NGX_LOG_ALERT, log, err,
                      "sysctlbyname(%s) failed", sysctls[i].name);
        return NGX_ERROR;
    }

    if (ngx_freebsd_machdep_hlt_logical_cpus) {
        ngx_ncpu = ngx_freebsd_hw_ncpu / 2;

    } else {
        ngx_ncpu = ngx_freebsd_hw_ncpu;
    }

    if (version < 600008 && ngx_freebsd_kern_ipc_somaxconn > 32767) {
        ngx_log_error(NGX_LOG_ALERT, log, 0,
                      "sysctl kern.ipc.somaxconn must be less than 32768");
        return NGX_ERROR;
    }

    ngx_tcp_nodelay_and_tcp_nopush = 1;

    ngx_os_io = ngx_freebsd_io;

    return NGX_OK;
}


void
ngx_os_specific_status(ngx_log_t *log)
{
    u_long      value;
    ngx_uint_t  i;

    ngx_log_error(NGX_LOG_NOTICE, log, 0, "OS: %s %s",
                  ngx_freebsd_kern_ostype, ngx_freebsd_kern_osrelease);

#ifdef __DragonFly_version
    ngx_log_error(NGX_LOG_NOTICE, log, 0,
                  "kern.osreldate: %d, built on %d",
                  ngx_freebsd_kern_osreldate, __DragonFly_version);
#else
    ngx_log_error(NGX_LOG_NOTICE, log, 0,
                  "kern.osreldate: %d, built on %d",
                  ngx_freebsd_kern_osreldate, __FreeBSD_version);
#endif

    for (i = 0; sysctls[i].name; i++) {
        if (sysctls[i].exists) {
            if (sysctls[i].size == sizeof(long)) {
                value = *(long *) sysctls[i].value;

            } else {
                value = *(int *) sysctls[i].value;
            }

            ngx_log_error(NGX_LOG_NOTICE, log, 0, "%s: %l",
                          sysctls[i].name, value);
        }
    }
}
