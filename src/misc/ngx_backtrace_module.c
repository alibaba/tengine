
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>

#include <execinfo.h>


#define NGX_BACKTRACE_DEFAULT_STACK_MAX_SIZE 30


typedef struct {
    int     signo;
    char   *signame;
    char   *name;
    void  (*handler)(int signo);
} ngx_signal_t;


static char *ngx_backtrace_files(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static void ngx_error_signal_handler(int signo);
static ngx_int_t ngx_backtrace_init_worker(ngx_cycle_t *cycle);
static void *ngx_backtrace_create_conf(ngx_cycle_t *cycle);


typedef struct {
    ngx_log_t              *log;
    ngx_int_t               max_stack_size;
} ngx_backtrace_conf_t;


static ngx_signal_t  ngx_backtrace_signals[] = {
    { SIGABRT, "SIGABRT", "", ngx_error_signal_handler },

#ifdef SIGBUS
    { SIGBUS, "SIGBUS", "", ngx_error_signal_handler },
#endif

    { SIGFPE, "SIGFPE", "", ngx_error_signal_handler },

    { SIGILL, "SIGILL", "", ngx_error_signal_handler },

    { SIGIOT, "SIGIOT", "", ngx_error_signal_handler },

    { SIGSEGV, "SIGSEGV", "", ngx_error_signal_handler },

    { 0, NULL, "", NULL }
};


static ngx_command_t  ngx_backtrace_commands[] = {

    { ngx_string("backtrace_log"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE1,
      ngx_backtrace_files,
      0,
      0,
      NULL },

    { ngx_string("backtrace_max_stack_size"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      0,
      offsetof(ngx_backtrace_conf_t, max_stack_size),
      NULL },

      ngx_null_command
};


static ngx_core_module_t  ngx_backtrace_module_ctx = {
    ngx_string("backtrace"),
    ngx_backtrace_create_conf,
    NULL
};


ngx_module_t  ngx_backtrace_module = {
    NGX_MODULE_V1,
    &ngx_backtrace_module_ctx,             /* module context */
    ngx_backtrace_commands,                /* module directives */
    NGX_CORE_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    ngx_backtrace_init_worker,             /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_init_error_signals(ngx_log_t *log)
{
    ngx_signal_t      *sig;
    struct sigaction   sa;

    for (sig = ngx_backtrace_signals; sig->signo != 0; sig++) {
        ngx_memzero(&sa, sizeof(struct sigaction));
        sa.sa_handler = sig->handler;
        sigemptyset(&sa.sa_mask);
        if (sigaction(sig->signo, &sa, NULL) == -1) {
            ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                          "sigaction(%s) failed", sig->signame);
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static void
ngx_error_signal_handler(int signo)
{
    void                 *buffer;
    size_t                size;
    ngx_log_t            *log;
    ngx_signal_t         *sig;
    struct sigaction      sa;
    ngx_backtrace_conf_t *bcf;

    for (sig = ngx_backtrace_signals; sig->signo != 0; sig++) {
        if (sig->signo == signo) {
            break;
        }
    }

    bcf = (ngx_backtrace_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx,
                                                ngx_backtrace_module);

    log = bcf->log ? bcf->log : ngx_cycle->log;
    ngx_log_error(NGX_LOG_ERR, log, 0,
                  "nginx coredump by signal %d (%s)", signo, sig->signame);

    ngx_memzero(&sa, sizeof(struct sigaction));
    sa.sa_handler = SIG_DFL;
    sigemptyset(&sa.sa_mask);
    if (sigaction(signo, &sa, NULL) == -1) {
        ngx_log_error(NGX_LOG_ERR, log, ngx_errno,
                      "sigaction(%s) failed", sig->signame);
    }

    if (bcf->max_stack_size == NGX_CONF_UNSET) {
        bcf->max_stack_size = NGX_BACKTRACE_DEFAULT_STACK_MAX_SIZE;
    }

    buffer = ngx_pcalloc(ngx_cycle->pool, sizeof(void *) * bcf->max_stack_size);
    if (buffer == NULL) {
        goto invalid;
    }

    size = backtrace(buffer, bcf->max_stack_size);
    backtrace_symbols_fd(buffer, size, log->file->fd);

invalid:

    kill(ngx_getpid(), signo);
}


static char *
ngx_backtrace_files(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_backtrace_conf_t *bcf;

    bcf = (ngx_backtrace_conf_t *) ngx_get_conf(cf->cycle->conf_ctx,
                                                ngx_backtrace_module);

    return ngx_log_set_log(cf, &bcf->log);
}


static ngx_int_t
ngx_backtrace_init_worker(ngx_cycle_t *cycle)
{
    if (ngx_init_error_signals(cycle->log) == NGX_ERROR) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static void *
ngx_backtrace_create_conf(ngx_cycle_t *cycle)
{
    ngx_backtrace_conf_t  *bcf;

    bcf = ngx_pcalloc(cycle->pool, sizeof(ngx_backtrace_conf_t));
    if (bcf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc()
     *
     *     bcf->log = NULL;
     */

    bcf->max_stack_size = NGX_CONF_UNSET;

    return bcf;
}
