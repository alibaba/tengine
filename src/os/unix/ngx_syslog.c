
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <nginx.h>


/**
 * syslog message is 2048 max length
 * http://tools.ietf.org/html/rfc5424#section-6.1
 */
#define  NGX_SYSLOG_MAX_LENGTH                 2048


static ngx_syslog_code ngx_syslog_priorities[] = {
    { "alert",   NGX_SYSLOG_ALERT },
    { "crit",    NGX_SYSLOG_CRIT },
    { "debug",   NGX_SYSLOG_DEBUG },
    { "emerg",   NGX_SYSLOG_EMERG },
    { "err",     NGX_SYSLOG_ERR },
    { "error",   NGX_SYSLOG_ERR },             /* DEPRECATED */
    { "info",    NGX_SYSLOG_INFO },
    { "none",    NGX_SYSLOG_INTERNAL_NOPRI },  /* INTERNAL */
    { "notice",  NGX_SYSLOG_NOTICE },
    { "panic",   NGX_SYSLOG_EMERG },           /* DEPRECATED */
    { "warn",    NGX_SYSLOG_WARNING },         /* DEPRECATED */
    { "warning", NGX_SYSLOG_WARNING },
    { NULL,      -1 }
};


static ngx_syslog_code ngx_syslog_facilities[] = {
    { "auth",     NGX_SYSLOG_AUTH },
    { "authpriv", NGX_SYSLOG_AUTHPRIV },
    { "cron",     NGX_SYSLOG_CRON },
    { "daemon",   NGX_SYSLOG_DAEMON },
    { "ftp",      NGX_SYSLOG_FTP },
    { "kern",     NGX_SYSLOG_KERN },
    { "lpr",      NGX_SYSLOG_LPR },
    { "mail",     NGX_SYSLOG_MAIL },
    { "mark",     NGX_SYSLOG_INTERNAL_MARK },  /* INTERNAL */
    { "news",     NGX_SYSLOG_NEWS },
    { "security", NGX_SYSLOG_AUTH },           /* DEPRECATED */
    { "syslog",   NGX_SYSLOG_SYSLOG },
    { "user",     NGX_SYSLOG_USER },
    { "uucp",     NGX_SYSLOG_UUCP },
    { "local0",   NGX_SYSLOG_LOCAL0 },
    { "local1",   NGX_SYSLOG_LOCAL1 },
    { "local2",   NGX_SYSLOG_LOCAL2 },
    { "local3",   NGX_SYSLOG_LOCAL3 },
    { "local4",   NGX_SYSLOG_LOCAL4 },
    { "local5",   NGX_SYSLOG_LOCAL5 },
    { "local6",   NGX_SYSLOG_LOCAL6 },
    { "local7",   NGX_SYSLOG_LOCAL7 },
    { NULL, -1 }
};


static time_t        ngx_syslog_retry_interval = 1800; /* half an hour */
static ngx_str_t     ngx_syslog_hostname;
static u_char        ngx_syslog_host_buf[NGX_MAXHOSTNAMELEN];


static char *ngx_syslog_init_conf(ngx_cycle_t *cycle, void *conf);
static void ngx_syslog_prebuild_header(ngx_syslog_t *task);
static ngx_int_t ngx_open_log_connection(ngx_syslog_t *task);

static char *ngx_syslog_set_retry_interval(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_set_unix_domain(ngx_pool_t *pool, ngx_addr_t *addr,
    u_char *text, size_t len);


static ngx_command_t  ngx_syslog_commands[] = {

    { ngx_string("syslog_retry_interval"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE1,
      ngx_syslog_set_retry_interval,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_core_module_t  ngx_syslog_module_ctx = {
    ngx_string("syslog"),
    NULL,
    ngx_syslog_init_conf,
};


ngx_module_t  ngx_syslog_module = {
    NGX_MODULE_V1,
    &ngx_syslog_module_ctx,                /* module context */
    ngx_syslog_commands,                   /* module directives */
    NGX_CORE_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static char *
ngx_syslog_set_retry_interval(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_syslog_retry_interval = NGX_CONF_UNSET;
    return ngx_conf_set_sec_slot(cf, cmd, &ngx_syslog_retry_interval);
}


static char *
ngx_syslog_init_conf(ngx_cycle_t *cycle, void *conf)
{
    ngx_syslog_hostname.len = cycle->hostname.len;
    ngx_memcpy(ngx_syslog_host_buf, cycle->hostname.data, cycle->hostname.len);
    ngx_syslog_hostname.data = ngx_syslog_host_buf;

    return NGX_OK;
}


ngx_int_t
ngx_log_set_syslog(ngx_pool_t *pool, ngx_str_t *value, ngx_log_t *log)
{
    size_t                 len;
    u_char                *p, *p_bak, pri[5];
    ngx_int_t              rc, port, facility, loglevel;
    ngx_str_t              ident;
    ngx_url_t              u;
    ngx_addr_t             addr;
    ngx_uint_t             i;
    enum {
        sw_facility = 0,
        sw_loglevel,
        sw_address,
        sw_port,
        sw_ident,
        sw_done
    } state;

    p = value->data;
    facility = -1;
    loglevel = -1;
    ident.len = 0;
    ident.data = NULL;
    state = sw_facility;
    ngx_memset(&addr, 0, sizeof(ngx_addr_t));

    /**
     * format example:
     *     syslog:user:info:127.0.0.1:514:ident
     *     syslog:user:info:/dev/log:ident
     *     syslog:user:info:127.0.0.1::ident
     *         is short for syslog:user:info:127.0.0.1:514:ident
     *     syslog:user:info:/dev/log
     *         is short for syslog:user:info:/dev/log:NGINX
     *     syslog:user:info:127.0.0.1
     *         is short for syslog:user:info:127.0.0.1:514:NGINX
     *     syslog:user::/dev/log:ident
     *         is short for syslog:user:info:/dev/log:ident
     *     syslog:user:info::ident
     *         is short for syslog:user:info:/dev/log:ident
     *     syslog:user:info
     *         is short for syslog:user:info:/dev/log:NGINX
     *     syslog:user
     *         is short for syslog:user:info:/dev/log:NGINX
     */
    while (state != sw_done) {
        p_bak = p;
        while (*p != ':' && (size_t) (p - value->data) < value->len) p++;

        switch (state) {
        case sw_facility:
            len = p - p_bak;

            for (i = 0; ngx_syslog_facilities[i].name != NULL; i++) {
                if (len == strlen(ngx_syslog_facilities[i].name)
                    && ngx_strncmp(ngx_syslog_facilities[i].name, p_bak, len)
                    == 0)
                {
                    facility = ngx_syslog_facilities[i].val;
                    break;
                }
            }

            if (facility == -1) {
                return NGX_ERROR;
            }

            state = sw_loglevel;

            break;

        case sw_loglevel:
            len = p - p_bak;

            if (len == 0) {
                loglevel = NGX_SYSLOG_INFO;
            } else {
                for (i = 0; ngx_syslog_priorities[i].name != NULL; i++) {
                    if (len == strlen(ngx_syslog_priorities[i].name)
                        && ngx_strncmp(ngx_syslog_priorities[i].name,
                                       p_bak, len)
                        == 0)
                    {
                        loglevel = ngx_syslog_priorities[i].val;
                        break;
                    }
                }

                if (loglevel == -1) {
                    return NGX_ERROR;
                }
            }

            state = sw_address;

            break;

        case sw_address:
            len = p - p_bak;

            if (len == 0) {
                addr.name.data = (u_char *) "/dev/log";
                addr.name.len = sizeof("/dev/log") - 1;

                rc = ngx_set_unix_domain(pool, &addr,
                         (u_char *) "/dev/log", sizeof("/dev/log") - 1);

                state = sw_ident;

            } else {
                addr.name.data = p_bak;
                addr.name.len = len;

                ngx_memzero(&u, sizeof(ngx_url_t));
                u.url.data = p_bak;
                u.url.len = len;
                u.one_addr = 1;

                rc = ngx_parse_url(pool, &u);
                if (rc != NGX_OK) {
                    rc = ngx_set_unix_domain(pool, &addr, p_bak, len);
                    state = sw_ident;
                } else {
                    state = sw_port;
                    addr.socklen = u.addrs[0].socklen;
                    addr.sockaddr = u.addrs[0].sockaddr;
                }
            }

            if (rc != NGX_OK) {
                return NGX_ERROR;
            }

            break;

        case sw_port:
            len = p - p_bak;

            port = ngx_atoi(p_bak, len);
            if (port < 1) {
                port = 514;
            } else if (port > 65535) {
                return NGX_ERROR;
            } else {
                addr.name.len += 1 + len;
            }

            switch (addr.sockaddr->sa_family) {

#if (NGX_HAVE_INET6)
            case AF_INET6:
                ((struct sockaddr_in6 *) addr.sockaddr)->sin6_port =
                                         htons((in_port_t) port);
                break;
#endif

            case AF_INET:
                ((struct sockaddr_in *) addr.sockaddr)->sin_port =
                                        htons((in_port_t) port);
                break;

            default: /* AF_UNIX */
                break;
            }

            state = sw_ident;

            break;

        case sw_ident:
            len = p - p_bak;

            ident.len = len;
            ident.data = p_bak;

            state = sw_done;

            break;

        default:

            break;
        }

        if (p < value->data + value->len) {
            p++;
        }
    }

    log->syslog = ngx_pcalloc(pool, sizeof(ngx_syslog_t));
    if (log->syslog == NULL) {
        return NGX_ERROR;
    }

    p = ngx_snprintf(pri, 5, "<%i>", facility + loglevel);
    log->syslog->syslog_pri.len = p - pri;
    log->syslog->syslog_pri.data = ngx_pcalloc(pool, p - pri);
    if (log->syslog->syslog_pri.data == NULL) {
        return NGX_ERROR;
    }
    ngx_memcpy(log->syslog->syslog_pri.data, pri, p - pri);

    log->syslog->addr = addr;
    log->syslog->ident = ident;
    log->syslog->fd = -1;
    log->syslog->header.data = log->syslog->header_buf;

    return NGX_OK;
}


static ngx_int_t
ngx_set_unix_domain(ngx_pool_t *pool, ngx_addr_t *addr, u_char *text,
    size_t len)
{
    struct sockaddr_un *sockaddr;

    sockaddr = ngx_palloc(pool, sizeof(struct sockaddr_un));
    if (sockaddr == NULL) {
        return NGX_ERROR;
    }

    if (len > sizeof(sockaddr->sun_path)) {
        return NGX_ERROR;
    }

    sockaddr->sun_family = AF_UNIX;
    ngx_cpystrn((u_char *) sockaddr->sun_path, text, ++len);

    addr->sockaddr = (struct sockaddr *) sockaddr;
    addr->socklen = sizeof(struct sockaddr_un);

    return NGX_OK;
}


static ngx_int_t
ngx_open_log_connection(ngx_syslog_t *task)
{
    size_t          len;
    ngx_socket_t    fd;

    fd = ngx_socket(task->addr.sockaddr->sa_family, SOCK_DGRAM, 0);
    if (fd == -1) {
        goto err;
    }

    len = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &len, sizeof(len));

    if (ngx_nonblocking(fd) == -1) {
        goto err;
    }

    if (connect(fd, task->addr.sockaddr, task->addr.socklen) == -1) {
        goto err;
    }

    shutdown(fd, SHUT_RD);

    task->fd = fd;

    return NGX_OK;

err:

    if (fd != -1) {
        ngx_close_socket(fd);
    }

    task->next_try = ngx_cached_time->sec + ngx_syslog_retry_interval;

    return NGX_DECLINED;
}


int
ngx_write_syslog(ngx_syslog_t *task, u_char *buf, size_t len)
{
    size_t        l;
    ngx_int_t     n;
    struct iovec  iovs[4];

    if (task->fd == -1 && ngx_cached_time->sec >= task->next_try) {
        ngx_open_log_connection(task);
    }

    if (task->fd == -1) {
        return NGX_ERROR;
    }

    if (task->header.len == 0) {
        ngx_syslog_prebuild_header(task);
    }

    iovs[0].iov_base = (void *) task->syslog_pri.data;
    iovs[0].iov_len = task->syslog_pri.len;
    l = task->syslog_pri.len;

    iovs[1].iov_base = (void *) ngx_cached_syslog_time.data;
    iovs[1].iov_len = ngx_cached_syslog_time.len;
    l += ngx_cached_syslog_time.len;

    iovs[2].iov_base = (void *) task->header.data;
    iovs[2].iov_len = task->header.len;
    l += task->header.len;

    iovs[3].iov_base = (void *) buf;
    iovs[3].iov_len = ngx_min(len, NGX_SYSLOG_MAX_LENGTH - l);

    n = writev(task->fd, iovs, 4);

    if (n < 0) {
        return NGX_ERROR;
    }

    return NGX_OK;
}

static void
ngx_syslog_prebuild_header(ngx_syslog_t *task)
{
    size_t        len;
    u_char       *p, pid[NGX_INT64_LEN], *appname;
    ngx_int_t     ident_len;

    appname = (u_char *) NGINX_VAR;

    p = ngx_snprintf(pid, NGX_INT64_LEN, "%P", ngx_log_pid);

    len = sizeof(" ") - 1
        + ngx_syslog_hostname.len
        + (task->ident.len == 0
            ? (ident_len = sizeof(NGINX_VAR) - 1)
            : (ident_len = task->ident.len))
        + sizeof(" [") - 1
        + p - pid
        + sizeof("]: ") - 1;

    task->header.len = ngx_min(NGX_SYSLOG_HEADER_LEN, len);
    ident_len -= ngx_max((ngx_int_t) (len - task->header.len), 0);

    ngx_snprintf(task->header.data,
                 task->header.len,
                 " %V %*s[%*s]: ",
                 &ngx_syslog_hostname,
                 ident_len,
                 (task->ident.len == 0 ? appname : task->ident.data),
                 p - pid,
                 pid);
}
