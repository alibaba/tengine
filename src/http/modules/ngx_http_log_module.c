
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#define NGX_HTTP_LOG_ESCAPE_ON      1
#define NGX_HTTP_LOG_ESCAPE_OFF     2
#define NGX_HTTP_LOG_ESCAPE_ASCII   3

#define NGX_HTTP_SCRIPT_ROP_AND     1
#define NGX_HTTP_SCRIPT_ROP_OR      2


typedef struct ngx_http_log_op_s  ngx_http_log_op_t;

typedef u_char *(*ngx_http_log_op_run_pt) (ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);

typedef size_t (*ngx_http_log_op_getlen_pt) (ngx_http_request_t *r,
    uintptr_t data);


struct ngx_http_log_op_s {
    size_t                      len;
    ngx_http_log_op_getlen_pt   getlen;
    ngx_http_log_op_run_pt      run;
    uintptr_t                   data;
};


typedef struct {
    ngx_str_t                   name;
    ngx_array_t                *flushes;
    ngx_array_t                *ops;        /* array of ngx_http_log_op_t */
} ngx_http_log_fmt_t;


typedef struct {
    ngx_array_t                 formats;    /* array of ngx_http_log_fmt_t */
    ngx_uint_t                  combined_used; /* unsigned  combined_used:1 */
    ngx_uint_t                  seq;        /* conditional log sequence */
} ngx_http_log_main_conf_t;


typedef struct {
    ngx_array_t                *lengths;
    ngx_array_t                *values;
} ngx_http_log_script_t;


typedef struct {
    ngx_array_t                *codes;
    ngx_flag_t                  log;
    ngx_flag_t                  is_and;
} ngx_http_log_condition_t;


/*
 * variables for sampled_log
 * ratio = sample/scope, 10's multiple
 * scatter = ceil(scope/sample)
 * (inflexion-1)*scatter + (sample-inflxion)*(scatter-1) - scope < 0
 * scope - (inflexion-1)*scatter - (sample-inflxion)*(scatter-1) <= scatter - 1
 *
 * for example:
 * ratio = 0.3, then scope = 10, sample = 3, scatter = 4, inflexion = 2
 * ratio = 0.35, then scope = 100, sample = 35, scatter = 3, inflexion = 31
 */

typedef struct {
    ngx_uint_t                  scope;
    ngx_uint_t                  sample;
    ngx_uint_t                  scatter;
    ngx_uint_t                  inflexion;
    ngx_uint_t                  scope_count;
    ngx_uint_t                  sample_count;
    ngx_uint_t                  scatter_count;
} ngx_http_log_sample_t;


typedef struct {
    ngx_array_t                *conditions;
    ngx_http_log_sample_t      *sample;
} ngx_http_log_env_t;


typedef struct {
#if (NGX_SYSLOG)
    ngx_syslog_t               *syslog;
#endif
    ngx_open_file_t            *file;
    ngx_http_log_script_t      *script;
    time_t                      disk_full_time;
    time_t                      error_log_time;
    ngx_http_log_fmt_t         *format;
    ngx_http_log_sample_t      *sample;
    ngx_int_t                   var_index;  /* for conditional log */
} ngx_http_log_t;


typedef struct {
    ngx_array_t                *logs;       /* array of ngx_http_log_t */
    ngx_http_log_env_t         *env;

    ngx_open_file_cache_t      *open_file_cache;
    time_t                      open_file_cache_valid;
    ngx_uint_t                  open_file_cache_min_uses;

    ngx_uint_t                  escape;

    ngx_flag_t                  log_empty_request;

    ngx_uint_t                  off;        /* unsigned  off:1 */
} ngx_http_log_loc_conf_t;


typedef struct {
    ngx_str_t                   name;
    size_t                      len;
    ngx_http_log_op_run_pt      run;
} ngx_http_log_var_t;


static void ngx_http_log_write(ngx_http_request_t *r, ngx_http_log_t *log,
    u_char *buf, size_t len);
static ssize_t ngx_http_log_script_write(ngx_http_request_t *r,
    ngx_http_log_script_t *script, u_char **name, u_char *buf, size_t len);

static u_char *ngx_http_log_connection(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_connection_requests(ngx_http_request_t *r,
    u_char *buf, ngx_http_log_op_t *op);
static u_char *ngx_http_log_pipe(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_time(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_iso8601(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_sec(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_msec(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_request_time(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_request_time_msec(ngx_http_request_t *r,
    u_char *buf, ngx_http_log_op_t *op);
static u_char *ngx_http_log_request_time_usec(ngx_http_request_t *r,
    u_char *buf, ngx_http_log_op_t *op);
static u_char *ngx_http_log_status(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_bytes_sent(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static u_char *ngx_http_log_body_bytes_sent(ngx_http_request_t *r,
    u_char *buf, ngx_http_log_op_t *op);
static u_char *ngx_http_log_request_length(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);

static ngx_int_t ngx_http_log_variable_compile(ngx_conf_t *cf,
    ngx_http_log_op_t *op, ngx_str_t *value);
static size_t ngx_http_log_variable_getlen(ngx_http_request_t *r,
    uintptr_t data);
static u_char *ngx_http_log_variable(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op);
static uintptr_t ngx_http_log_escape(u_char *dst, u_char *src, size_t size,
    ngx_uint_t flag);

static char *ngx_http_log_condition_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_log_env_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_log_block_if(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_log_block_sample(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static ngx_int_t ngx_http_log_condition_value(ngx_conf_t *cf,
    ngx_http_log_condition_t *lc, ngx_str_t *value);
static ngx_int_t ngx_http_log_condition_element(ngx_conf_t *cf,
    ngx_http_log_condition_t *lc, ngx_int_t cur);
static ngx_int_t ngx_http_log_condition(ngx_conf_t *cf,
    ngx_http_log_condition_t *lc, ngx_int_t cur, ngx_int_t *count);
static char *ngx_http_log_sample_rate(ngx_conf_t *cf, ngx_str_t *value,
    ngx_http_log_sample_t **sample);
static ngx_http_variable_t *ngx_http_log_copy_var(ngx_conf_t *cf,
    ngx_http_variable_t *var, ngx_uint_t seq);

static ngx_int_t ngx_http_log_variable_value(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_log_do_if(ngx_http_request_t *r,
    ngx_array_t *conditions);
static ngx_int_t ngx_http_log_do_sample(ngx_http_log_sample_t *sample);

static void *ngx_http_log_create_main_conf(ngx_conf_t *cf);
static void *ngx_http_log_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_log_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_log_set_log(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_log_set_format(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_log_compile_format(ngx_conf_t *cf,
    ngx_array_t *flushes, ngx_array_t *ops, ngx_array_t *args, ngx_uint_t s);
static char *ngx_http_log_open_file_cache(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_log_init(ngx_conf_t *cf);


static ngx_conf_enum_t ngx_http_log_var_escape_types[] = {
    { ngx_string("on"), NGX_HTTP_LOG_ESCAPE_ON },
    { ngx_string("off"), NGX_HTTP_LOG_ESCAPE_OFF },
    { ngx_string("ascii"), NGX_HTTP_LOG_ESCAPE_ASCII },
    { ngx_null_string, 0 }
};


static ngx_command_t  ngx_http_log_commands[] = {

    { ngx_string("log_format"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_2MORE,
      ngx_http_log_set_format,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("access_log"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_HTTP_LMT_CONF|NGX_CONF_1MORE,
      ngx_http_log_set_log,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("open_log_file_cache"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1234,
      ngx_http_log_open_file_cache,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("log_escape"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_enum_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_log_loc_conf_t, escape),
      &ngx_http_log_var_escape_types },

    { ngx_string("log_empty_request"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_log_loc_conf_t, log_empty_request),
      NULL },

    { ngx_string("log_condition"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_BLOCK
                        |NGX_CONF_NOARGS,
      ngx_http_log_condition_block,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("log_env"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_BLOCK
                        |NGX_CONF_TAKE1,
      ngx_http_log_env_block,
      0,
      0,
      NULL },

    { ngx_string("if"),
      NGX_HTTP_LOG_CONF|NGX_CONF_1MORE,
      ngx_http_log_block_if,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("sample"),
      NGX_HTTP_LOG_CONF|NGX_CONF_1MORE,
      ngx_http_log_block_sample,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_log_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_http_log_init,                     /* postconfiguration */

    ngx_http_log_create_main_conf,         /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_log_create_loc_conf,          /* create location configuration */
    ngx_http_log_merge_loc_conf            /* merge location configuration */
};


ngx_module_t  ngx_http_log_module = {
    NGX_MODULE_V1,
    &ngx_http_log_module_ctx,              /* module context */
    ngx_http_log_commands,                 /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_str_t  ngx_http_access_log = ngx_string(NGX_HTTP_LOG_PATH);


static ngx_str_t  ngx_http_combined_fmt =
    ngx_string("$remote_addr - $remote_user [$time_local] "
               "\"$request\" $status $body_bytes_sent "
               "\"$http_referer\" \"$http_user_agent\"");


static ngx_http_log_var_t  ngx_http_log_vars[] = {
    { ngx_string("connection"), NGX_ATOMIC_T_LEN, ngx_http_log_connection },
    { ngx_string("connection_requests"), NGX_INT_T_LEN,
                          ngx_http_log_connection_requests },
    { ngx_string("pipe"), 1, ngx_http_log_pipe },
    { ngx_string("time_local"), sizeof("28/Sep/1970:12:00:00 +0600") - 1,
                          ngx_http_log_time },
    { ngx_string("time_iso8601"), sizeof("1970-09-28T12:00:00+06:00") - 1,
                          ngx_http_log_iso8601 },
    { ngx_string("sec"), NGX_TIME_T_LEN, ngx_http_log_sec },
    { ngx_string("msec"), NGX_TIME_T_LEN + 4, ngx_http_log_msec },
    { ngx_string("request_time"), NGX_TIME_T_LEN + 4,
                          ngx_http_log_request_time },
    { ngx_string("request_time_msec"), NGX_TIME_T_LEN,
                          ngx_http_log_request_time_msec },
    { ngx_string("request_time_usec"), NGX_TIME_T_LEN,
                          ngx_http_log_request_time_usec },
    { ngx_string("status"), NGX_INT_T_LEN, ngx_http_log_status },
    { ngx_string("bytes_sent"), NGX_OFF_T_LEN, ngx_http_log_bytes_sent },
    { ngx_string("body_bytes_sent"), NGX_OFF_T_LEN,
                          ngx_http_log_body_bytes_sent },
    { ngx_string("apache_bytes_sent"), NGX_OFF_T_LEN,
                          ngx_http_log_body_bytes_sent },
    { ngx_string("request_length"), NGX_SIZE_T_LEN,
                          ngx_http_log_request_length },

    { ngx_null_string, 0, NULL }
};


static ngx_int_t
ngx_http_log_handler(ngx_http_request_t *r)
{
    u_char                    *line, *p;
    size_t                     len;
    ngx_uint_t                 i, l, bypass;
    ngx_http_log_t            *log;
    ngx_open_file_t           *file;
    ngx_http_log_op_t         *op;
    ngx_http_log_loc_conf_t   *lcf;
    ngx_http_variable_value_t *vv;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http log handler");

    lcf = ngx_http_get_module_loc_conf(r, ngx_http_log_module);

    if (lcf->off) {
        return NGX_OK;
    }

    bypass = 0;

    if (lcf->env && lcf->env->conditions
        && ngx_http_log_do_if(r, lcf->env->conditions) == NGX_DECLINED)
    {
        bypass = 1;
    }

    if (bypass == 0 && lcf->env && lcf->env->sample
        && ngx_http_log_do_sample(lcf->env->sample) == NGX_DECLINED)
    {
        bypass = 1;
    }

    if (r->headers_out.status == NGX_HTTP_BAD_REQUEST && !lcf->log_empty_request
        && (r->header_in && r->header_in->last == r->header_in->start))
    {
        return NGX_OK;
    }

    log = lcf->logs->elts;
    for (l = 0; l < lcf->logs->nelts; l++) {
        if (log[l].var_index == NGX_ERROR && log[l].sample == NULL && bypass) {
            continue;
        }

        if (log[l].var_index != NGX_ERROR) {
            vv = ngx_http_get_indexed_variable(r, log[l].var_index);
            if (vv != NULL && !vv->not_found
                && (vv->len == 0 || (vv->len == 1 && vv->data[0] == '0')))
            {
                continue;
            }
        }

        if (log[l].sample
            && ngx_http_log_do_sample(log[l].sample) == NGX_DECLINED)
        {
            continue;
        }

        if (ngx_time() == log[l].disk_full_time) {

            /*
             * on FreeBSD writing to a full filesystem with enabled softupdates
             * may block process for much longer time than writing to non-full
             * filesystem, so we skip writing to a log for one second
             */

            continue;
        }

        ngx_http_script_flush_no_cacheable_variables(r, log[l].format->flushes);

        len = 0;
        op = log[l].format->ops->elts;
        for (i = 0; i < log[l].format->ops->nelts; i++) {
            if (op[i].len == 0) {
                len += op[i].getlen(r, op[i].data);

            } else {
                len += op[i].len;
            }
        }

        len += NGX_LINEFEED_SIZE;

        file = log[l].file;

        if (file && file->buffer) {

            if (len > (size_t) (file->last - file->pos)) {

                ngx_http_log_write(r, &log[l], file->buffer,
                                   file->pos - file->buffer);

                file->pos = file->buffer;
            }

            if (len <= (size_t) (file->last - file->pos)) {

                p = file->pos;

                for (i = 0; i < log[l].format->ops->nelts; i++) {
                    p = op[i].run(r, p, &op[i]);
                }

                ngx_linefeed(p);

                file->pos = p;

                continue;
            }
        }

        line = ngx_pnalloc(r->pool, len);
        if (line == NULL) {
            return NGX_ERROR;
        }

        p = line;

        for (i = 0; i < log[l].format->ops->nelts; i++) {
            p = op[i].run(r, p, &op[i]);
        }

        ngx_linefeed(p);

#if (NGX_SYSLOG)
        if (log[l].syslog != NULL) {
            if (!(log[l].syslog->fd == NGX_INVALID_FILE
                && ngx_cached_time->sec < log[l].syslog->next_try))
            {
                (void) ngx_write_syslog(log[l].syslog, line, p - line);
            }

            continue;
        }
#endif

        ngx_http_log_write(r, &log[l], line, p - line);
    }

    return NGX_OK;
}


static void
ngx_http_log_write(ngx_http_request_t *r, ngx_http_log_t *log, u_char *buf,
    size_t len)
{
    u_char     *name;
    time_t      now;
    ssize_t     n;
    ngx_err_t   err;

    if (log->script == NULL) {
        name = log->file->name.data;
        if (name == NULL) {
            name = (u_char *) "The pipe";
        }
        n = ngx_write_fd(log->file->fd, buf, len);

    } else {
        name = NULL;
        n = ngx_http_log_script_write(r, log->script, &name, buf, len);
    }

    if (n == (ssize_t) len) {
        return;
    }

    now = ngx_time();

    if (n == -1) {
        err = ngx_errno;

        if (err == NGX_ENOSPC) {
            log->disk_full_time = now;
        }

        if (now - log->error_log_time > 59) {
            ngx_log_error(NGX_LOG_ALERT, r->connection->log, err,
                          ngx_write_fd_n " to \"%s\" failed", name);

            log->error_log_time = now;
        }

        return;
    }

    if (now - log->error_log_time > 59) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                      ngx_write_fd_n " to \"%s\" was incomplete: %z of %uz",
                      name, n, len);

        log->error_log_time = now;
    }
}


static ssize_t
ngx_http_log_script_write(ngx_http_request_t *r, ngx_http_log_script_t *script,
    u_char **name, u_char *buf, size_t len)
{
    size_t                     root;
    ssize_t                    n;
    ngx_str_t                  log, path;
    ngx_open_file_info_t       of;
    ngx_http_log_loc_conf_t   *llcf;
    ngx_http_core_loc_conf_t  *clcf;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (!r->root_tested) {

        /* test root directory existence */

        if (ngx_http_map_uri_to_path(r, &path, &root, 0) == NULL) {
            /* simulate successful logging */
            return len;
        }

        path.data[root] = '\0';

        ngx_memzero(&of, sizeof(ngx_open_file_info_t));

        of.valid = clcf->open_file_cache_valid;
        of.min_uses = clcf->open_file_cache_min_uses;
        of.test_dir = 1;
        of.test_only = 1;
        of.errors = clcf->open_file_cache_errors;
        of.events = clcf->open_file_cache_events;

        if (ngx_http_set_disable_symlinks(r, clcf, &path, &of) != NGX_OK) {
            /* simulate successful logging */
            return len;
        }

        if (ngx_open_cached_file(clcf->open_file_cache, &path, &of, r->pool)
            != NGX_OK)
        {
            if (of.err == 0) {
                /* simulate successful logging */
                return len;
            }

            ngx_log_error(NGX_LOG_ERR, r->connection->log, of.err,
                          "testing \"%s\" existence failed", path.data);

            /* simulate successful logging */
            return len;
        }

        if (!of.is_dir) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, NGX_ENOTDIR,
                          "testing \"%s\" existence failed", path.data);

            /* simulate successful logging */
            return len;
        }
    }

    if (ngx_http_script_run(r, &log, script->lengths->elts, 1,
                            script->values->elts)
        == NULL)
    {
        /* simulate successful logging */
        return len;
    }

    log.data[log.len - 1] = '\0';
    *name = log.data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http log \"%s\"", log.data);

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_log_module);

    ngx_memzero(&of, sizeof(ngx_open_file_info_t));

    of.log = 1;
    of.valid = llcf->open_file_cache_valid;
    of.min_uses = llcf->open_file_cache_min_uses;
    of.directio = NGX_OPEN_FILE_DIRECTIO_OFF;

    if (ngx_http_set_disable_symlinks(r, clcf, &log, &of) != NGX_OK) {
        /* simulate successful logging */
        return len;
    }

    if (ngx_open_cached_file(llcf->open_file_cache, &log, &of, r->pool)
        != NGX_OK)
    {
        ngx_log_error(NGX_LOG_CRIT, r->connection->log, ngx_errno,
                      "%s \"%s\" failed", of.failed, log.data);
        /* simulate successful logging */
        return len;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http log #%d", of.fd);

    n = ngx_write_fd(of.fd, buf, len);

    return n;
}


static u_char *
ngx_http_log_copy_short(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    size_t     len;
    uintptr_t  data;

    len = op->len;
    data = op->data;

    while (len--) {
        *buf++ = (u_char) (data & 0xff);
        data >>= 8;
    }

    return buf;
}


static u_char *
ngx_http_log_copy_long(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    return ngx_cpymem(buf, (u_char *) op->data, op->len);
}


static u_char *
ngx_http_log_connection(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    return ngx_sprintf(buf, "%uA", r->connection->number);
}


static u_char *
ngx_http_log_connection_requests(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    return ngx_sprintf(buf, "%ui", r->connection->requests);
}


static u_char *
ngx_http_log_pipe(ngx_http_request_t *r, u_char *buf, ngx_http_log_op_t *op)
{
    if (r->pipeline) {
        *buf = 'p';
    } else {
        *buf = '.';
    }

    return buf + 1;
}


static u_char *
ngx_http_log_time(ngx_http_request_t *r, u_char *buf, ngx_http_log_op_t *op)
{
    return ngx_cpymem(buf, ngx_cached_http_log_time.data,
                      ngx_cached_http_log_time.len);
}

static u_char *
ngx_http_log_iso8601(ngx_http_request_t *r, u_char *buf, ngx_http_log_op_t *op)
{
    return ngx_cpymem(buf, ngx_cached_http_log_iso8601.data,
                      ngx_cached_http_log_iso8601.len);
}

static u_char *
ngx_http_log_sec(ngx_http_request_t *r, u_char *buf, ngx_http_log_op_t *op)
{
    ngx_time_t  *tp;

    tp = ngx_timeofday();

    return ngx_sprintf(buf, "%T", tp->sec);
}


static u_char *
ngx_http_log_msec(ngx_http_request_t *r, u_char *buf, ngx_http_log_op_t *op)
{
    ngx_time_t  *tp;

    tp = ngx_timeofday();

    return ngx_sprintf(buf, "%T.%03M", tp->sec, tp->msec);
}


static u_char *
ngx_http_log_request_time(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    ngx_time_t                *tp;
    ngx_msec_int_t             ms;
    struct timeval             tv;
    ngx_http_core_loc_conf_t  *clcf;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    if (clcf->request_time_cache) {
        tp = ngx_timeofday();
        ms = (ngx_msec_int_t)
                 ((tp->sec - r->start_sec) * 1000 + (tp->msec - r->start_msec));
    } else {
        ngx_gettimeofday(&tv);
        ms = (tv.tv_sec - r->start_sec) * 1000
                 + (tv.tv_usec / 1000 - r->start_msec);
    }

    ms = ngx_max(ms, 0);

    return ngx_sprintf(buf, "%T.%03M", ms / 1000, ms % 1000);
}


static u_char *
ngx_http_log_request_time_msec(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    ngx_time_t                *tp;
    ngx_msec_int_t             ms;
    struct timeval             tv;
    ngx_http_core_loc_conf_t  *clcf;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    if (clcf->request_time_cache) {
        tp = ngx_timeofday();
        ms = (ngx_msec_int_t)
                 ((tp->sec - r->start_sec) * 1000 + (tp->msec - r->start_msec));
    } else {
        ngx_gettimeofday(&tv);
        ms = (tv.tv_sec - r->start_sec) * 1000
                 + (tv.tv_usec / 1000 - r->start_msec);
    }

    ms = ngx_max(ms, 0);

    return ngx_sprintf(buf, "%T", ms);
}


static u_char *
ngx_http_log_request_time_usec(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    ngx_time_t                *tp;
    ngx_usec_int_t             us;
    struct timeval             tv;
    ngx_http_core_loc_conf_t  *clcf;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    if (clcf->request_time_cache) {
        tp = ngx_timeofday();

        us = (ngx_usec_int_t) (1000 *
                 ((tp->sec - r->start_sec) * 1000 + (tp->msec - r->start_msec)))
                 + tp->usec - r->start_usec;
    } else {
        ngx_gettimeofday(&tv);
        us = (ngx_usec_int_t) (1000 * ((tv.tv_sec - r->start_sec) * 1000
                 + (tv.tv_usec / 1000 - r->start_msec)))
                 + tv.tv_usec % 1000 - r->start_usec;
    }

    us = ngx_max(us, 0);

    return ngx_sprintf(buf, "%T", us);
}


static u_char *
ngx_http_log_status(ngx_http_request_t *r, u_char *buf, ngx_http_log_op_t *op)
{
    ngx_uint_t  status;

    if (r->err_status) {
        status = r->err_status;

    } else if (r->headers_out.status) {
        status = r->headers_out.status;

    } else if (r->http_version == NGX_HTTP_VERSION_9) {
        status = 9;

    } else {
        status = 0;
    }

    return ngx_sprintf(buf, "%03ui", status);
}


static u_char *
ngx_http_log_bytes_sent(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    return ngx_sprintf(buf, "%O", r->connection->sent);
}


/*
 * although there is a real $body_bytes_sent variable,
 * this log operation code function is more optimized for logging
 */

static u_char *
ngx_http_log_body_bytes_sent(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    off_t  length;

    length = r->connection->sent - r->header_size;

    if (length > 0) {
        return ngx_sprintf(buf, "%O", length);
    }

    *buf = '0';

    return buf + 1;
}


static u_char *
ngx_http_log_request_length(ngx_http_request_t *r, u_char *buf,
    ngx_http_log_op_t *op)
{
    return ngx_sprintf(buf, "%O", r->request_length);
}


static ngx_int_t
ngx_http_log_variable_compile(ngx_conf_t *cf, ngx_http_log_op_t *op,
    ngx_str_t *value)
{
    ngx_int_t  index;

    index = ngx_http_get_variable_index(cf, value);
    if (index == NGX_ERROR) {
        return NGX_ERROR;
    }

    op->len = 0;
    op->getlen = ngx_http_log_variable_getlen;
    op->run = ngx_http_log_variable;
    op->data = index;

    return NGX_OK;
}


static size_t
ngx_http_log_variable_getlen(ngx_http_request_t *r, uintptr_t data)
{
    uintptr_t                   len;
    ngx_http_log_loc_conf_t    *llcf;
    ngx_http_variable_value_t  *value;

    value = ngx_http_get_indexed_variable(r, data);

    if (value == NULL || value->not_found) {
        return 1;
    }

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_log_module);

    len = ngx_http_log_escape(NULL, value->data, value->len, llcf->escape);

    value->escape = len ? 1 : 0;

    return value->len + len * 3;
}


static u_char *
ngx_http_log_variable(ngx_http_request_t *r, u_char *buf, ngx_http_log_op_t *op)
{
    ngx_http_log_loc_conf_t    *llcf;
    ngx_http_variable_value_t  *value;

    value = ngx_http_get_indexed_variable(r, op->data);

    if (value == NULL || value->not_found) {
        *buf = '-';
        return buf + 1;
    }

    if (value->escape == 0) {
        return ngx_cpymem(buf, value->data, value->len);

    } else {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_log_module);

        return (u_char *) ngx_http_log_escape(buf, value->data, value->len,
                                              llcf->escape);
    }
}


static uintptr_t
ngx_http_log_escape(u_char *dst, u_char *src, size_t size, ngx_uint_t flag)
{
    ngx_uint_t       n;
    uint32_t        *escape;
    static u_char    hex[] = "0123456789ABCDEF";

    static uint32_t   table[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x00000004, /* 0000 0000 0000 0000  0000 0000 0000 0100 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x10000000, /* 0001 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

    static uint32_t   ascii_table[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x00000004, /* 0000 0000 0000 0000  0000 0000 0000 0100 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x10000000, /* 0001 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    };

    escape = (flag == NGX_HTTP_LOG_ESCAPE_ON) ? table : ascii_table;

    if (dst == NULL) {

        /* find the number of the characters to be escaped */

        n = 0;

        if (flag != NGX_HTTP_LOG_ESCAPE_OFF) {

            while (size) {
                if (escape[*src >> 5] & (1 << (*src & 0x1f))) {
                    n++;
                }
                src++;
                size--;
            }
        }

        return (uintptr_t) n;
    }

    while (size) {
        if (escape[*src >> 5] & (1 << (*src & 0x1f))) {
            *dst++ = '\\';
            *dst++ = 'x';
            *dst++ = hex[*src >> 4];
            *dst++ = hex[*src & 0xf];
            src++;

        } else {
            *dst++ = *src++;
        }
        size--;
    }

    return (uintptr_t) dst;
}


static void *
ngx_http_log_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_log_main_conf_t  *conf;

    ngx_http_log_fmt_t  *fmt;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_log_main_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    if (ngx_array_init(&conf->formats, cf->pool, 4, sizeof(ngx_http_log_fmt_t))
        != NGX_OK)
    {
        return NULL;
    }

    fmt = ngx_array_push(&conf->formats);
    if (fmt == NULL) {
        return NULL;
    }

    ngx_str_set(&fmt->name, "combined");

    fmt->flushes = NULL;

    fmt->ops = ngx_array_create(cf->pool, 16, sizeof(ngx_http_log_op_t));
    if (fmt->ops == NULL) {
        return NULL;
    }

    return conf;
}


static void *
ngx_http_log_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_log_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_log_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    conf->open_file_cache = NGX_CONF_UNSET_PTR;
    conf->escape = NGX_CONF_UNSET_UINT;
    conf->log_empty_request = NGX_CONF_UNSET;

    return conf;
}


static char *
ngx_http_log_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_log_loc_conf_t *prev = parent;
    ngx_http_log_loc_conf_t *conf = child;

    ngx_http_log_t            *log;
    ngx_http_log_fmt_t        *fmt;
    ngx_http_log_main_conf_t  *lmcf;

    ngx_conf_merge_uint_value(conf->escape, prev->escape,
                              NGX_HTTP_LOG_ESCAPE_ON);
    ngx_conf_merge_value(conf->log_empty_request, prev->log_empty_request, 1);

    if (conf->open_file_cache == NGX_CONF_UNSET_PTR) {

        conf->open_file_cache = prev->open_file_cache;
        conf->open_file_cache_valid = prev->open_file_cache_valid;
        conf->open_file_cache_min_uses = prev->open_file_cache_min_uses;

        if (conf->open_file_cache == NGX_CONF_UNSET_PTR) {
            conf->open_file_cache = NULL;
        }
    }

    if (conf->env == NULL) {
        conf->env = prev->env;
    }

    if (conf->logs || conf->off) {
        return NGX_CONF_OK;
    }

    conf->logs = prev->logs;
    conf->off = prev->off;

    if (conf->logs || conf->off) {
        return NGX_CONF_OK;
    }

    conf->logs = ngx_array_create(cf->pool, 2, sizeof(ngx_http_log_t));
    if (conf->logs == NULL) {
        return NGX_CONF_ERROR;
    }

    log = ngx_array_push(conf->logs);
    if (log == NULL) {
        return NGX_CONF_ERROR;
    }

    log->file = ngx_conf_open_file(cf->cycle, &ngx_http_access_log);
    if (log->file == NULL) {
        return NGX_CONF_ERROR;
    }

    log->script = NULL;
    log->disk_full_time = 0;
    log->error_log_time = 0;
    log->sample = NULL;
    log->var_index = NGX_ERROR;
#if NGX_SYSLOG
    log->syslog = NULL;
#endif

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_log_module);
    fmt = lmcf->formats.elts;

    /* the default "combined" format */
    log->format = &fmt[0];
    lmcf->combined_used = 1;

    return NGX_CONF_OK;
}


static char *
ngx_http_log_set_log(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_log_loc_conf_t *llcf = conf;

    ssize_t                     buf;
    ngx_int_t                   rc;
    ngx_str_t                  *value, name;
    ngx_uint_t                  i, n;
    ngx_http_log_t             *log;
    ngx_http_log_fmt_t         *fmt;
    ngx_http_variable_t        *var;
    ngx_http_log_sample_t      *sample;
    ngx_http_log_main_conf_t   *lmcf;
    ngx_http_script_compile_t   sc;
    ngx_uint_t                  skip_file = 0;

    value = cf->args->elts;

    if (ngx_strcmp(value[1].data, "off") == 0) {
        llcf->off = 1;
        if (cf->args->nelts == 2) {
            return NGX_CONF_OK;
        }

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[2]);
        return NGX_CONF_ERROR;
    }

    if (llcf->logs == NULL) {
        llcf->logs = ngx_array_create(cf->pool, 2, sizeof(ngx_http_log_t));
        if (llcf->logs == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_log_module);

    log = ngx_array_push(llcf->logs);
    if (log == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_memzero(log, sizeof(ngx_http_log_t));
    log->var_index = NGX_ERROR;

    rc = ngx_log_target(cf->cycle, &value[1], (ngx_log_t *) log);

    if (rc == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid parameter \"%V\"", &value[1]);
        return NGX_CONF_ERROR;
    } else if (rc == NGX_OK) {
        skip_file = 1;

        if (log->file != NULL) {
            name = ngx_log_access_backup;
            if (ngx_conf_full_name(cf->cycle, &name, 0) != NGX_OK) {
                return "fail to set bakup";
            }

            log->file->name = name;
        }
    } else {
        n = ngx_http_script_variables_count(&value[1]);

        if (n == 0) {
            log->file = ngx_conf_open_file(cf->cycle, &value[1]);
            if (log->file == NULL) {
                return NGX_CONF_ERROR;
            }

        } else {
            if (ngx_conf_full_name(cf->cycle, &value[1], 0) != NGX_OK) {
                return NGX_CONF_ERROR;
            }

            log->script = ngx_pcalloc(cf->pool, sizeof(ngx_http_log_script_t));
            if (log->script == NULL) {
                return NGX_CONF_ERROR;
            }

            ngx_memzero(&sc, sizeof(ngx_http_script_compile_t));

            sc.cf = cf;
            sc.source = &value[1];
            sc.lengths = &log->script->lengths;
            sc.values = &log->script->values;
            sc.variables = n;
            sc.complete_lengths = 1;
            sc.complete_values = 1;

            if (ngx_http_script_compile(&sc) != NGX_OK) {
                return NGX_CONF_ERROR;
            }
        }
    }

    if (cf->args->nelts >= 3) {
        name = value[2];

        if (ngx_strcmp(name.data, "combined") == 0) {
            lmcf->combined_used = 1;
        }

    } else {
        ngx_str_set(&name, "combined");
        lmcf->combined_used = 1;
    }

    fmt = lmcf->formats.elts;
    for (i = 0; i < lmcf->formats.nelts; i++) {
        if (fmt[i].name.len == name.len
            && ngx_strcasecmp(fmt[i].name.data, name.data) == 0)
        {
            log->format = &fmt[i];
            goto rest;
        }
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "unknown log format \"%V\"", &name);
    return NGX_CONF_ERROR;

rest:

    if (cf->args->nelts == 3) {
        return NGX_CONF_OK;
    }

    sample = NULL;
    var = NULL;

    for (i = 3; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data, "ratio=", 6) == 0) {
            value[i].data += 6;
            value[i].len -= 6;

            if (ngx_http_log_sample_rate(cf, &value[i], &sample)
                != NGX_CONF_OK)
            {
                return NGX_CONF_ERROR;
            }

        } else if (ngx_strncmp(value[i].data, "buffer=", 7) == 0) {
            if (skip_file == 0) {
                continue;
            }

            if (log->script) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "buffered logs cannot have variables in name");
                return NGX_CONF_ERROR;
            }

            name.len = value[i].len - 7;
            name.data = value[i].data + 7;

            buf = ngx_parse_size(&name);

            if (buf == NGX_ERROR) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid parameter \"%V\"", &value[i]);
                return NGX_CONF_ERROR;
            }

            if (log->file->buffer && log->file->last - log->file->pos != buf) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "access_log \"%V\" already defined "
                                   "with different buffer size", &value[1]);
                return NGX_CONF_ERROR;
            }

            log->file->buffer = ngx_palloc(cf->pool, buf);
            if (log->file->buffer == NULL) {
                return NGX_CONF_ERROR;
            }

            log->file->pos = log->file->buffer;
            log->file->last = log->file->buffer + buf;

        } else if (ngx_strncmp(value[i].data, "env=", 4) == 0) {
            value[i].data += 5;
            value[i].len -= 5;

            var = ngx_http_add_variable(cf, &value[i], NGX_HTTP_VAR_CHANGEABLE);
            if (var == NULL) {
                return NGX_CONF_ERROR;
            }

        } else {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid buffer value \"%V\"", &name);
            return NGX_CONF_ERROR;
        }
    }

    if (var == NULL) {
        log->sample = sample;
        return NGX_CONF_OK;
    }

    if (var->get_handler == NULL && var->set_handler == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "variable for log env is not defined");
        return NGX_CONF_ERROR;
    }

    if (var->get_handler != ngx_http_log_variable_value) {
        log->sample = sample;
    } else if (sample) {
        var = ngx_http_log_copy_var(cf, var, ++lmcf->seq);
        if (var == NULL) {
            return NGX_CONF_ERROR;
        }

        ((ngx_http_log_env_t *) var->data)->sample = sample;
    }

    log->var_index = ngx_http_get_variable_index(cf, &var->name);
    if (log->var_index == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_log_set_format(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_log_main_conf_t *lmcf = conf;

    ngx_str_t           *value;
    ngx_uint_t           i;
    ngx_http_log_fmt_t  *fmt;

    value = cf->args->elts;

    fmt = lmcf->formats.elts;
    for (i = 0; i < lmcf->formats.nelts; i++) {
        if (fmt[i].name.len == value[1].len
            && ngx_strcmp(fmt[i].name.data, value[1].data) == 0)
        {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "duplicate \"log_format\" name \"%V\"",
                               &value[1]);
            return NGX_CONF_ERROR;
        }
    }

    fmt = ngx_array_push(&lmcf->formats);
    if (fmt == NULL) {
        return NGX_CONF_ERROR;
    }

    fmt->name = value[1];

    fmt->flushes = ngx_array_create(cf->pool, 4, sizeof(ngx_int_t));
    if (fmt->flushes == NULL) {
        return NGX_CONF_ERROR;
    }

    fmt->ops = ngx_array_create(cf->pool, 16, sizeof(ngx_http_log_op_t));
    if (fmt->ops == NULL) {
        return NGX_CONF_ERROR;
    }

    return ngx_http_log_compile_format(cf, fmt->flushes, fmt->ops, cf->args, 2);
}


static char *
ngx_http_log_compile_format(ngx_conf_t *cf, ngx_array_t *flushes,
    ngx_array_t *ops, ngx_array_t *args, ngx_uint_t s)
{
    u_char              *data, *p, ch;
    size_t               i, len;
    ngx_str_t           *value, var;
    ngx_int_t           *flush;
    ngx_uint_t           bracket;
    ngx_http_log_op_t   *op;
    ngx_http_log_var_t  *v;

    value = args->elts;

    for ( /* void */ ; s < args->nelts; s++) {

        i = 0;

        while (i < value[s].len) {

            op = ngx_array_push(ops);
            if (op == NULL) {
                return NGX_CONF_ERROR;
            }

            data = &value[s].data[i];

            if (value[s].data[i] == '$') {

                if (++i == value[s].len) {
                    goto invalid;
                }

                if (value[s].data[i] == '{') {
                    bracket = 1;

                    if (++i == value[s].len) {
                        goto invalid;
                    }

                    var.data = &value[s].data[i];

                } else {
                    bracket = 0;
                    var.data = &value[s].data[i];
                }

                for (var.len = 0; i < value[s].len; i++, var.len++) {
                    ch = value[s].data[i];

                    if (ch == '}' && bracket) {
                        i++;
                        bracket = 0;
                        break;
                    }

                    if ((ch >= 'A' && ch <= 'Z')
                        || (ch >= 'a' && ch <= 'z')
                        || (ch >= '0' && ch <= '9')
                        || ch == '_')
                    {
                        continue;
                    }

                    break;
                }

                if (bracket) {
                    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                       "the closing bracket in \"%V\" "
                                       "variable is missing", &var);
                    return NGX_CONF_ERROR;
                }

                if (var.len == 0) {
                    goto invalid;
                }

                if (ngx_strncmp(var.data, "apache_bytes_sent", 17) == 0) {
                    ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                        "use \"$body_bytes_sent\" instead of "
                        "\"$apache_bytes_sent\"");
                }

                for (v = ngx_http_log_vars; v->name.len; v++) {

                    if (v->name.len == var.len
                        && ngx_strncmp(v->name.data, var.data, var.len) == 0)
                    {
                        op->len = v->len;
                        op->getlen = NULL;
                        op->run = v->run;
                        op->data = 0;

                        goto found;
                    }
                }

                if (ngx_http_log_variable_compile(cf, op, &var) != NGX_OK) {
                    return NGX_CONF_ERROR;
                }

                if (flushes) {

                    flush = ngx_array_push(flushes);
                    if (flush == NULL) {
                        return NGX_CONF_ERROR;
                    }

                    *flush = op->data; /* variable index */
                }

            found:

                continue;
            }

            i++;

            while (i < value[s].len && value[s].data[i] != '$') {
                i++;
            }

            len = &value[s].data[i] - data;

            if (len) {

                op->len = len;
                op->getlen = NULL;

                if (len <= sizeof(uintptr_t)) {
                    op->run = ngx_http_log_copy_short;
                    op->data = 0;

                    while (len--) {
                        op->data <<= 8;
                        op->data |= data[len];
                    }

                } else {
                    op->run = ngx_http_log_copy_long;

                    p = ngx_pnalloc(cf->pool, len);
                    if (p == NULL) {
                        return NGX_CONF_ERROR;
                    }

                    ngx_memcpy(p, data, len);
                    op->data = (uintptr_t) p;
                }
            }
        }
    }

    return NGX_CONF_OK;

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "invalid parameter \"%s\"", data);

    return NGX_CONF_ERROR;
}


static char *
ngx_http_log_open_file_cache(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_log_loc_conf_t *llcf = conf;

    time_t       inactive, valid;
    ngx_str_t   *value, s;
    ngx_int_t    max, min_uses;
    ngx_uint_t   i;

    if (llcf->open_file_cache != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    value = cf->args->elts;

    max = 0;
    inactive = 10;
    valid = 60;
    min_uses = 1;

    for (i = 1; i < cf->args->nelts; i++) {

        if (ngx_strncmp(value[i].data, "max=", 4) == 0) {

            max = ngx_atoi(value[i].data + 4, value[i].len - 4);
            if (max == NGX_ERROR) {
                goto failed;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "inactive=", 9) == 0) {

            s.len = value[i].len - 9;
            s.data = value[i].data + 9;

            inactive = ngx_parse_time(&s, 1);
            if (inactive == (time_t) NGX_ERROR) {
                goto failed;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "min_uses=", 9) == 0) {

            min_uses = ngx_atoi(value[i].data + 9, value[i].len - 9);
            if (min_uses == NGX_ERROR) {
                goto failed;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "valid=", 6) == 0) {

            s.len = value[i].len - 6;
            s.data = value[i].data + 6;

            valid = ngx_parse_time(&s, 1);
            if (valid == (time_t) NGX_ERROR) {
                goto failed;
            }

            continue;
        }

        if (ngx_strcmp(value[i].data, "off") == 0) {

            llcf->open_file_cache = NULL;

            continue;
        }

    failed:

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid \"open_log_file_cache\" parameter \"%V\"",
                           &value[i]);
        return NGX_CONF_ERROR;
    }

    if (llcf->open_file_cache == NULL) {
        return NGX_CONF_OK;
    }

    if (max == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                        "\"open_log_file_cache\" must have \"max\" parameter");
        return NGX_CONF_ERROR;
    }

    llcf->open_file_cache = ngx_open_file_cache_init(cf->pool, max, inactive);

    if (llcf->open_file_cache) {

        llcf->open_file_cache_valid = valid;
        llcf->open_file_cache_min_uses = min_uses;

        return NGX_CONF_OK;
    }

    return NGX_CONF_ERROR;
}


static ngx_int_t
ngx_http_log_init(ngx_conf_t *cf)
{
    ngx_str_t                  *value;
    ngx_array_t                 a;
    ngx_http_handler_pt        *h;
    ngx_http_log_fmt_t         *fmt;
    ngx_http_log_main_conf_t   *lmcf;
    ngx_http_core_main_conf_t  *cmcf;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_log_module);

    if (lmcf->combined_used) {
        if (ngx_array_init(&a, cf->pool, 1, sizeof(ngx_str_t)) != NGX_OK) {
            return NGX_ERROR;
        }

        value = ngx_array_push(&a);
        if (value == NULL) {
            return NGX_ERROR;
        }

        *value = ngx_http_combined_fmt;
        fmt = lmcf->formats.elts;

        if (ngx_http_log_compile_format(cf, NULL, fmt->ops, &a, 0)
            != NGX_CONF_OK)
        {
            return NGX_ERROR;
        }
    }

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_LOG_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_log_handler;

    return NGX_OK;
}


static char *
ngx_http_log_condition_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                         *rv;
    ngx_conf_t                    pcf;
    ngx_http_conf_ctx_t          *ctx, *pctx;
    ngx_http_log_condition_t     *condition;

    ngx_http_log_loc_conf_t      *llcf = conf;

    llcf->env = ngx_pcalloc(cf->pool, sizeof(ngx_http_log_env_t));
    if (llcf->env == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_conf_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    pctx = cf->ctx;
    ctx->main_conf = pctx->main_conf;
    ctx->srv_conf = pctx->srv_conf;
    ctx->loc_conf = ngx_pcalloc(cf->pool, sizeof(void *) * ngx_http_max_module);
    if (ctx->loc_conf == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->loc_conf[ngx_http_log_module.ctx_index] = llcf->env;

    pcf = *cf;
    cf->cmd_type = NGX_HTTP_LOG_CONF;
    cf->ctx = ctx;
    rv = ngx_conf_parse(cf, NULL);
    *cf = pcf;

    if (rv != NGX_CONF_OK) {
        return rv;
    }

    if (llcf->env->conditions) {
        condition = llcf->env->conditions->elts;
        if (condition[llcf->env->conditions->nelts - 1].is_and) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                              "can not use \"and\" flag on the last condition");
            return NGX_CONF_ERROR;
        }
    }

    return NGX_CONF_OK;
}

static char *
ngx_http_log_env_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                         *rv;
    ngx_str_t                    *value;
    ngx_conf_t                    pcf;
    ngx_http_log_env_t           *env;
    ngx_http_conf_ctx_t          *ctx, *pctx;
    ngx_http_variable_t          *var;
    ngx_http_log_condition_t     *condition;

    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_http_conf_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    pctx = cf->ctx;
    ctx->main_conf = pctx->main_conf;
    ctx->srv_conf = pctx->srv_conf;
    ctx->loc_conf = ngx_pcalloc(cf->pool, sizeof(void *) * ngx_http_max_module);
    if (ctx->loc_conf == NULL) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;
    value[1].len--;
    value[1].data++;

    var = ngx_http_add_variable(cf, &value[1], NGX_HTTP_VAR_CHANGEABLE);
    if (var == NULL) {
        return NGX_CONF_ERROR;
    }

    if (var->data) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "duplicate access log var: \"%V\"",
                           &value[1]);
        return NGX_CONF_ERROR;
    }

    env = ngx_pcalloc(cf->pool, sizeof(ngx_http_log_env_t));
    if (env == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->loc_conf[ngx_http_log_module.ctx_index] = env;

    var->get_handler = ngx_http_log_variable_value;
    var->data = (uintptr_t) env;

    pcf = *cf;
    cf->cmd_type = NGX_HTTP_LOG_CONF;
    cf->ctx = ctx;
    rv = ngx_conf_parse(cf, NULL);
    *cf = pcf;

    if (rv != NGX_CONF_OK) {
        return rv;
    }

    if (env->conditions) {
        condition = env->conditions->elts;
        if (condition[env->conditions->nelts - 1].is_and) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                              "can not use \"and\" flag on the last condition");
            return NGX_CONF_ERROR;
        }
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_log_block_if(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    uintptr_t                     *code;
    ngx_int_t                      rc;
    ngx_int_t                      count;
    ngx_str_t                     *value;
    ngx_http_log_condition_t      *lc;

    ngx_http_log_env_t            *env = conf;

    if (env->conditions == NULL) {
        env->conditions = ngx_array_create(cf->pool, 7,
                                           sizeof(ngx_http_log_condition_t));
        if (env->conditions == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    lc = ngx_array_push(env->conditions);
    if (lc == NULL) {
        return NGX_CONF_ERROR;
    }
    ngx_memzero(lc, sizeof(ngx_http_log_condition_t));

    value = cf->args->elts;
    if (ngx_strcmp(value[cf->args->nelts - 1].data, "and") == 0) {
        cf->args->nelts--;
        lc->is_and = 1;
    }

    count = 0;
    rc = ngx_http_log_condition(cf, lc, 1, &count);
    if (rc == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    if (count > 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "the parentheses are not enclosed");
        return NGX_CONF_ERROR;
    }

    code = ngx_array_push_n(lc->codes, sizeof(uintptr_t));
    if (code == NULL) {
        return NGX_CONF_ERROR;
    }

    *code = (uintptr_t) NULL;

    return NGX_CONF_OK;
}


static char *
ngx_http_log_block_sample(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                  *value;
    ngx_http_log_env_t         *env = conf;

    value = cf->args->elts;

    return ngx_http_log_sample_rate(cf, &value[1], &env->sample);
}


static ngx_int_t
ngx_http_log_condition_value(ngx_conf_t *cf,
    ngx_http_log_condition_t *lc, ngx_str_t *value)
{
    ngx_int_t                              n;
    ngx_http_script_compile_t              sc;
    ngx_http_script_value_code_t          *val;
    ngx_http_script_complex_value_code_t  *complex;

    n = ngx_http_script_variables_count(value);

    if (n == 0) {
        val = ngx_http_script_start_code(cf->pool, &lc->codes,
                                         sizeof(ngx_http_script_value_code_t));
        if (val == NULL) {
            return NGX_ERROR;
        }

        n = ngx_atoi(value->data, value->len);

        if (n == NGX_ERROR) {
            n = 0;
        }

        val->code = ngx_http_script_value_code;
        val->value = (uintptr_t) n;
        val->text_len = (uintptr_t) value->len;
        val->text_data = (uintptr_t) value->data;

        return NGX_OK;
    }

    complex = ngx_http_script_start_code(cf->pool, &lc->codes,
                                 sizeof(ngx_http_script_complex_value_code_t));
    if (complex == NULL) {
        return NGX_ERROR;
    }

    complex->code = ngx_http_script_complex_value_code;
    complex->lengths = NULL;

    ngx_memzero(&sc, sizeof(ngx_http_script_compile_t));

    sc.cf = cf;
    sc.source = value;
    sc.lengths = &complex->lengths;
    sc.values = &lc->codes;
    sc.variables = n;
    sc.complete_lengths = 1;

    if (ngx_http_script_compile(&sc) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_log_condition_element(ngx_conf_t *cf, ngx_http_log_condition_t *lc,
    ngx_int_t cur)
{
    u_char                        *p;
    size_t                         len;
    ngx_str_t                     *value;
    ngx_regex_compile_t            rc;
    ngx_http_script_code_pt       *pcode, code;
    ngx_http_script_file_code_t   *fop;
    ngx_http_script_regex_code_t  *regex;
    u_char                         errstr[NGX_MAX_CONF_ERRSTR];

    value = cf->args->elts;

    len = value[cur].len;
    p = value[cur].data;

    if (len > 1 && p[0] == '$') {

        if (ngx_http_log_condition_value(cf, lc, &value[cur]) != NGX_OK) {
            return NGX_ERROR;
        }

        cur++;
        code = NULL;

        len = value[cur].len;
        p = value[cur].data;

        if (len == 1 && p[0] == '=') {
            code = ngx_http_script_equal_code;

        } else if (len == 2 && p[0] == '!' && p[1] == '=') {
            code = ngx_http_script_not_equal_code;

        } else if (len == 1 && p[0] == '>') {
            code = ngx_http_script_more_than_code;

        } else if (len == 1 && p[0] == '<') {
            code = ngx_http_script_less_than_code;

        } else if (len == 2 && p[0] == '>' && p[1] == '=') {
            code = ngx_http_script_no_less_than_code;

        } else if (len == 2 && p[0] == '<' && p[1] == '=') {
            code = ngx_http_script_no_more_than_code;

        } else if ((len == 1 && p[0] == '~')
            || (len == 2 && p[0] == '~' && p[1] == '*')
            || (len == 2 && p[0] == '!' && p[1] == '~')
            || (len == 3 && p[0] == '!' && p[1] == '~' && p[2] == '*'))
        {
            regex = ngx_http_script_start_code(cf->pool, &lc->codes,
                                         sizeof(ngx_http_script_regex_code_t));
            if (regex == NULL) {
                return NGX_ERROR;
            }

            ngx_memzero(regex, sizeof(ngx_http_script_regex_code_t));

            ngx_memzero(&rc, sizeof(ngx_regex_compile_t));

            cur++;
            rc.pattern = value[cur];
            rc.options = (p[len - 1] == '*') ? NGX_REGEX_CASELESS : 0;
            rc.err.len = NGX_MAX_CONF_ERRSTR;
            rc.err.data = errstr;

            regex->regex = ngx_http_regex_compile(cf, &rc);
            if (regex->regex == NULL) {
                return NGX_ERROR;
            }

            regex->code = ngx_http_script_regex_start_code;
            regex->next = sizeof(ngx_http_script_regex_code_t);
            regex->test = 1;
            if (p[0] == '!') {
                regex->negative_test = 1;
            }
            regex->name = value[cur];

            return cur + 1;
        }

        if (code) {
            cur++;

            if (ngx_http_log_condition_value(cf, lc, &value[cur])
                != NGX_OK)
            {
                return NGX_ERROR;
            }

            pcode = ngx_http_script_start_code(cf->pool, &lc->codes,
                                               sizeof(uintptr_t));
            if (pcode == NULL) {
                return NGX_ERROR;
            }

            *pcode = code;

            return cur + 1;
        }

        return cur;

    } else if ((len == 2 && p[0] == '-')
               || (len == 3 && p[0] == '!' && p[1] == '-'))
    {
        cur++;

        if (ngx_http_log_condition_value(cf, lc, &value[cur])
            != NGX_OK)
        {
            return NGX_ERROR;
        }

        fop = ngx_http_script_start_code(cf->pool, &lc->codes,
                                         sizeof(ngx_http_script_file_code_t));
        if (fop == NULL) {
            return NGX_ERROR;
        }

        fop->code = ngx_http_script_file_code;

        if (p[1] == 'f') {
            fop->op = ngx_http_script_file_plain;
            return cur + 1;
        }

        if (p[1] == 'd') {
            fop->op = ngx_http_script_file_dir;
            return cur + 1;
        }

        if (p[1] == 'e') {
            fop->op = ngx_http_script_file_exists;
            return cur + 1;
        }

        if (p[1] == 'x') {
            fop->op = ngx_http_script_file_exec;
            return cur + 1;
        }

        if (p[0] == '!') {
            if (p[2] == 'f') {
                fop->op = ngx_http_script_file_not_plain;
                return cur + 1;
            }

            if (p[2] == 'd') {
                fop->op = ngx_http_script_file_not_dir;
                return cur + 1;
            }

            if (p[2] == 'e') {
                fop->op = ngx_http_script_file_not_exists;
                return cur + 1;
            }

            if (p[2] == 'x') {
                fop->op = ngx_http_script_file_not_exec;
                return cur + 1;
            }
        }
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid condition element \"%V\"", &value[cur]);

    return NGX_ERROR;
}


static ngx_int_t
ngx_http_log_condition(ngx_conf_t *cf, ngx_http_log_condition_t *lc,
    ngx_int_t cur, ngx_int_t *count)
{
    off_t                        *poff;
    ngx_str_t                    *value;
    ngx_int_t                     rb, ret;
    ngx_uint_t                   *p, op, i;
    ngx_array_t                   nstack, fstack;
    ngx_http_script_code_pt      *code;
    ngx_http_script_if_code_t    *fastcode;

    struct {
        ngx_http_script_code_pt   code;
        ngx_http_script_code_pt   fastcode;
        ngx_uint_t                prior;
    } op_arr[3] = {
        { NULL, NULL, 0 },
        { ngx_http_script_and_code, ngx_http_script_test_code, 5 },
        { ngx_http_script_or_code, ngx_http_script_test_not_code, 4 }
    };

    value = cf->args->elts;
    rb = -1;
    ret = -1;
    i = 0;
    code = NULL;
    ngx_array_init(&nstack, cf->pool, 10, sizeof(ngx_uint_t));
    ngx_array_init(&fstack, cf->pool, 10, sizeof(off_t));

    while (cur < (ngx_int_t) cf->args->nelts && (rb == -1 || cur <= rb)) {

        if (value[cur].data[0] == '(') {

            if (value[cur].len == 1) {
                cur++;

            } else {
                value[cur].len--;
                value[cur].data++;
            }

            (*count)++;
            cur = ngx_http_log_condition(cf, lc, cur, count);

            if (cur == NGX_ERROR) {
                return NGX_ERROR;
            }

            if (cur >= (ngx_int_t) cf->args->nelts) {
                return cur;
            }
        }

        if (ret < 0) {
            if (value[cur].data[value[cur].len - 1] == ')') {
                rb = cur;

            } else if (cur + 1 < (ngx_int_t) cf->args->nelts
                && value[cur + 1].data[value[cur + 1].len - 1] == ')')
            {
                rb = cur + 1;

            } else if (cur + 2 < (ngx_int_t) cf->args->nelts
                && value[cur + 2].data[value[cur + 2].len - 1] == ')')
            {
                rb = cur + 2;
            }

            if (rb >= 0) {

                (*count)--;
                if (*count < 0) {
                    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                       "unexpected end of parentheses");
                    return NGX_ERROR;
                }

                for (i = 0;
                     value[rb].len > 0
                         && value[rb].data[value[rb].len - 1] == ')';
                     i++)
                {
                    value[rb].len--;
                    value[rb].data[value[rb].len] = '\0';
                }

                ret = i > 1 ? rb : rb + 1;

                if (value[rb].len == 0) {
                    if (rb == cur) {
                        break;
                    }

                    rb--;
                }
            }
        }

        op = 0;

        if (value[cur].len == 2 && value[cur].data[0] == '|'
            && value[cur].data[1] == '|')
        {
            op = NGX_HTTP_SCRIPT_ROP_OR;
            
        } else if (value[cur].len == 2 && value[cur].data[0] == '&'
                   && value[cur].data[1] == '&')
        {
            op = NGX_HTTP_SCRIPT_ROP_AND;

        } else {
            cur = ngx_http_log_condition_element(cf, lc, cur);
            if (cur == NGX_ERROR) {
                return NGX_ERROR;
            }
        }

        /*
         * a && b && c ==> a ifn b ifn c ifn && && NULL
         *                    Y     Y     Y         A
         *                    |     |     |         |
         *                    \---------------------/
         *
         * a && b || c ==> a ifn b && if c || NULL
         *                    Y       Y  A      A
         *                    |       |  |      |
         *                    \-------+--/      |
         *                            \---------/
         *
         * a || b && c ==> a if b ifn c && || NULL
         *                    Y    Y            A
         *                    |    |            |
         *                    \-----------------/
         *
         * a || b || c ==> a if b if c if || || NULL
         *                    Y    Y    Y         A
         *                    |    |    |         |
         *                    \-------------------/
         *
         * Conclusion:
         *     Whenever a logical operator is buffered in stack, add a
         * 'if' or 'if_not' operator next to the operand in the op list,
         * otherwise, add a 'if' or 'if_not' operator next to the logical
         * operator in the op list. Update the 'next' field of all the
         * 'if' or 'if_not' operators to point to the current position
         * in the op list, after a logical operator is put into the op
         * list or at the end of the whole process.
         */

        if (op) {

            if (nstack.nelts == 0) {
                p = (ngx_uint_t *) ngx_array_push(&nstack);
                if (p == NULL) {
                    return NGX_ERROR;
                }

            } else {
                p = ((ngx_uint_t *) nstack.elts) + nstack.nelts - 1;

                if (op_arr[*p].prior > op_arr[op].prior) {
                    code = ngx_http_script_start_code(cf->pool,
                                                      &lc->codes,
                                                      sizeof(uintptr_t));
                    if (code == NULL) {
                        return NGX_ERROR;
                    }

                    *code = op_arr[*p].code;

                    while (fstack.nelts) {
                        poff = (off_t *) fstack.elts + fstack.nelts - 1;
                        fastcode = (ngx_http_script_if_code_t *)
                                      (*poff + (u_char *) lc->codes->elts);
                        fastcode->next = (u_char *) code + sizeof(uintptr_t)
                                       + sizeof(ngx_http_script_if_code_t)
                                       - (u_char *) lc->codes->elts
                                       - *poff;
                        fstack.nelts--;
                    }

                } else {
                    p = (ngx_uint_t *) ngx_array_push(&nstack);
                    if (p == NULL) {
                        return NGX_ERROR;
                    }

                }
            }

            fastcode = ngx_http_script_start_code(cf->pool, &lc->codes,
                                            sizeof(ngx_http_script_if_code_t));
            if (fastcode == NULL) {
                return NGX_ERROR;
            }

            fastcode->code = op_arr[op].fastcode;
            fastcode->loc_conf = NULL;

            poff = (off_t *) ngx_array_push(&fstack);
            if (poff == NULL) {
                return NGX_ERROR;
            }

            *p = op;
            *poff = (u_char *) fastcode - (u_char *) lc->codes->elts;
            cur++;
        }
    }

    while (nstack.nelts) {
        p = ((ngx_uint_t *) nstack.elts) + nstack.nelts - 1;
        code = ngx_http_script_start_code(cf->pool, &lc->codes,
                                          sizeof(uintptr_t));
        if (code == NULL) {
            return NGX_ERROR;
        }

        *code = op_arr[*p].code;
        nstack.nelts--;
    }

    while (fstack.nelts) {
        poff = (off_t *) fstack.elts + fstack.nelts - 1;
        fastcode = (ngx_http_script_if_code_t *)
                             (*poff + (u_char *) lc->codes->elts);
        fastcode->next = (u_char *) code + sizeof(uintptr_t)
                       - (u_char *) lc->codes->elts
                       - *poff;
        fstack.nelts--;
    }

    if (i > 1) {
        value[ret].data += value[ret].len;
        value[ret].len = i - 1;
        ngx_memset(value[ret].data, ')', i - 1);
    }

    return ret;
}


static char *
ngx_http_log_sample_rate(ngx_conf_t *cf, ngx_str_t *value,
    ngx_http_log_sample_t **sample)
{
    u_char                 *p, *last;
    uint64_t                scope;
    ngx_uint_t              rp;

    if (*sample) {
        return "is duplicate";
    }

    rp = 0;
    scope = 0;

    for (last = value->data + value->len - 1;
         last >= value->data && *last == '0';
         last--) /* void */ ;

    if (last == value->data && *last == '1') {
        return NGX_CONF_OK;
    }

    *sample = ngx_pcalloc(cf->pool, sizeof(ngx_http_log_sample_t));
    if (*sample == NULL) {
        return NGX_CONF_ERROR;
    }

    for (p = value->data; p <= last; p++) {
        if (*p == '.') {
            if (rp == 0) {
                rp = 1;
                scope = 1;
                continue;
            } else {
                goto invalid;
            }
        }

        if (*p < '0' && *p > '9') {
            goto invalid;
        }

        if (rp == 0 && *p != '0') {
            goto invalid;
        }

        (*sample)->sample *= 10;
        (*sample)->sample += *p - '0';

        scope *= 10;

        if (scope > NGX_MAX_UINT32_VALUE) {
            goto invalid;
        }
    }

    if ((*sample)->sample == 0) {
        goto invalid;
    }

    (*sample)->scope = scope;

    (*sample)->scatter = (*sample)->scope / (*sample)->sample;
    if ((*sample)->scatter * (*sample)->sample != (*sample)->scope) {
        (*sample)->scatter++;
    }

    (*sample)->inflexion = (*sample)->scope
                         - (*sample)->sample * (*sample)->scatter
                         + (*sample)->sample + 1;

    return NGX_CONF_OK;

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", value);

    return NGX_CONF_ERROR;
}


static ngx_http_variable_t *
ngx_http_log_copy_var(ngx_conf_t *cf, ngx_http_variable_t *var, ngx_uint_t seq)
{
    ngx_str_t             *var_name;
    ngx_uint_t             i, n;
    ngx_http_log_env_t    *env;
    ngx_http_variable_t   *new_var;

    for (i = 1, n = seq / 10; n; n /= 10, i++) /* void */;

    var_name = ngx_palloc(cf->pool, sizeof(ngx_str_t));
    if (var_name == NULL) {
        return NULL;
    }

    var_name->len = var->name.len + i + sizeof("anonymous");
    var_name->data = ngx_palloc(cf->pool, var_name->len + 1);
    if (var_name->data == NULL) {
        return NULL;
    }

    ngx_sprintf(var_name->data, "anonymous_%V%d%Z", &var->name, seq);

    new_var = ngx_http_add_variable(cf, var_name, NGX_HTTP_VAR_CHANGEABLE);
    if (new_var == NULL) {
        return NULL;
    }

    env = ngx_palloc(cf->pool, sizeof(ngx_http_log_env_t));
    if (env == NULL) {
        return NULL;
    }

    ngx_memcpy(env, (char *) var->data, sizeof(ngx_http_log_env_t));

    new_var->get_handler = ngx_http_log_variable_value;
    new_var->data = (uintptr_t) env;

    return new_var;
}


static ngx_int_t
ngx_http_log_variable_value(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_http_log_env_t *env = (ngx_http_log_env_t *) data;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                  "env->sample=%p, env->conditions=%p",
                  env->sample, env->conditions);

    if (env->conditions
        && ngx_http_log_do_if(r, env->conditions) == NGX_DECLINED)
    {
        goto bypass;
    }

    if (env->sample
        && ngx_http_log_do_sample(env->sample) == NGX_DECLINED)
    {
        goto bypass;
    }

    v->len = 1;
    v->data = (u_char *) "1";
    v->valid = 1;
    v->no_cacheable = 1;
    v->not_found = 0;

    return NGX_OK;

bypass:

    v->len = 0;
    v->valid = 1;
    v->no_cacheable = 1;
    v->not_found = 0;

    return NGX_OK;
}


static ngx_int_t
ngx_http_log_do_if(ngx_http_request_t *r, ngx_array_t *conditions)
{
    ngx_uint_t                 i;
    ngx_http_script_code_pt    code;
    ngx_http_log_condition_t  *condition;
    ngx_http_script_engine_t   e;
    ngx_http_variable_value_t  stack[10];

    condition = conditions->elts;
    for (i = 0; i < conditions->nelts; i++) {
        ngx_memzero(&e, sizeof(ngx_http_script_engine_t));
        ngx_memzero(&stack, sizeof(stack));
        e.ip = condition[i].codes->elts;
        e.request = r;
        e.quote = 1;
        e.log = condition[i].log;
        e.status = NGX_DECLINED;
        e.sp = stack;

        while (*(uintptr_t *) e.ip) {
            code = *(ngx_http_script_code_pt *) e.ip;
            code(&e);
        }

        e.sp--;
        if (e.sp->len && (e.sp->len != 1 || e.sp->data[0] != '0')) {
            if (!condition[i].is_and) {

                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "ngx http log condition: true");

                return NGX_OK;
            }
        } else {
            while (condition[i].is_and) {
                i++;
            }
        }
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "ngx http log condition: false");

    return NGX_DECLINED;
}


static ngx_int_t
ngx_http_log_do_sample(ngx_http_log_sample_t *sample)
{
    ngx_uint_t    bypass, threshold;

    bypass = 1;

    if (sample->sample_count < sample->sample) {
        if (sample->scatter_count++ == 0) {
            bypass = 0;
            sample->sample_count++;
        }

        threshold = sample->scatter;
        if (sample->sample_count >= sample->inflexion) {
            threshold--;
        }

        if (sample->scatter_count == threshold) {
            sample->scatter_count = 0;
        }
    }

    if (++sample->scope_count == sample->scope) {
        sample->scope_count = 0;
        sample->sample_count = 0;
        sample->scatter_count = 0;
    }

    if (bypass) {
        return NGX_DECLINED;
    }

    return NGX_OK;
}
