
/*
 * Copyright (C) 2010-2012 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <nginx.h>


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
static ngx_str_t     ngx_syslog_line;


static char *ngx_syslog_init_conf(ngx_cycle_t *cycle, void *conf);
static ngx_int_t ngx_syslog_init_process(ngx_cycle_t *cycle);
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
    ngx_syslog_init_process,               /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_syslog_init_process(ngx_cycle_t *cycle)
{
    u_char       *p, pid[20];

    p = ngx_snprintf(pid, 20, "%P", ngx_log_pid);

    ngx_syslog_line.len = sizeof(" ") - 1
                        + ngx_syslog_hostname.len
                        + sizeof(" " NGINX_VAR "[") - 1
                        + p - pid
                        + sizeof("]: ") - 1;

    ngx_syslog_line.data = ngx_alloc(ngx_syslog_line.len, cycle->log);
    if (ngx_syslog_line.data == NULL) {
        return NGX_ERROR;
    }

    ngx_snprintf(ngx_syslog_line.data,
                 ngx_syslog_line.len,
                 " %V " NGINX_VAR "[%*s]: ",
                 &ngx_syslog_hostname,
                 p - pid,
                 pid);

    return NGX_OK;
}

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
    u_char                *p = value->data, *p_bak;
    ngx_int_t              rc, t, port;
    ngx_int_t              facility = -1, loglevel = -1;
    ngx_addr_t             addr;
    ngx_uint_t             i;

    /* syslog:user::127.0.0.1:514 --> 4 paragraphs */
    for (t = 3; t > 0; t--) {
        p_bak = p;
        while (*p != ':' && (size_t) (p - value->data) < value->len) p++;

        switch (t) {
        case 3:
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

            break;

        case 2:
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

            break;

        case 1:
            len = p - p_bak;

            if (len == 0) {
                addr.name.data = (u_char *) "/dev/log";
                addr.name.len = sizeof("/dev/log") - 1;

                rc = ngx_set_unix_domain(pool, &addr,
                         (u_char *) "/dev/log", sizeof("/dev/log") - 1);
            } else {
                addr.name.data = p_bak;
                addr.name.len = value->data + value->len - p_bak;

                rc = ngx_parse_addr(pool, &addr, p_bak, len);
                if (rc == NGX_DECLINED) {
                    rc = ngx_set_unix_domain(pool, &addr, p_bak, len);
                }
            }

            if (rc != NGX_OK) {
                return NGX_ERROR;
            }

            break;
        }

        if (p < value->data + value->len) {
            p++;
        }
    }

    len = value->data + value->len - p;

    port = ngx_atoi(p, len);
    if (port < 1) {
        port = 514;
    } else if (port > 65535) {
        return NGX_ERROR;
    }

    switch (addr.sockaddr->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:
        ((struct sockaddr_in6 *) addr.sockaddr)->sin6_port =
                                 htons((in_port6_t) port);
        break;
#endif

    case AF_INET:
        ((struct sockaddr_in *) addr.sockaddr)->sin_port =
                                htons((in_port_t) port);
        break;

    default: /* AF_UNIX */
        break;
    }

    log->syslog = ngx_pcalloc(pool, sizeof(ngx_syslog_t));
    if (log->syslog == NULL) {
        return NGX_ERROR;
    }

    log->syslog->syslog_pri = facility + loglevel;
    log->syslog->addr = addr;
    log->syslog->fd = -1;

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
    u_char       *p, pri[5];
    size_t        l;
    ngx_int_t     n;
    struct iovec  iovs[4];

    if (task->fd == -1 && ngx_cached_time->sec >= task->next_try) {
        ngx_open_log_connection(task);
    }

    if (task->fd == -1) {
        return NGX_ERROR;
    }

    l = 0;

    p = ngx_snprintf(pri, 5, "<%d>", task->syslog_pri);
    iovs[0].iov_base = (void *) pri;
    iovs[0].iov_len = p - pri;
    l += p - pri;

    iovs[1].iov_base = (void *) ngx_cached_syslog_time.data;
    iovs[1].iov_len = ngx_cached_syslog_time.len;
    l += ngx_cached_syslog_time.len;

    iovs[2].iov_base = (void *) ngx_syslog_line.data;
    iovs[2].iov_len = ngx_syslog_line.len;
    l += ngx_syslog_line.len;

    /* syslog message is 1024 max length */
    iovs[3].iov_base = (void *) buf;
    iovs[3].iov_len = 1024 - l > len ? len : 1024 - l;

    n = writev(task->fd, iovs, 4);

    if (n < 0) {
        return NGX_ERROR;
    }

    return NGX_OK;
}
