
/*
 * Copyright (C) by OpenResty Inc.
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"
#include "ngx_http_lua_input_filters.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_pipe.h"
#if (NGX_HTTP_LUA_HAVE_SIGNALFD)
#include <sys/signalfd.h>
#endif


#ifdef HAVE_NGX_LUA_PIPE
static ngx_rbtree_node_t *ngx_http_lua_pipe_lookup_pid(ngx_rbtree_key_t key);
#if !(NGX_HTTP_LUA_HAVE_SIGNALFD)
static void ngx_http_lua_pipe_sigchld_handler(int signo, siginfo_t *siginfo,
    void *ucontext);
#endif
static void ngx_http_lua_pipe_sigchld_event_handler(ngx_event_t *ev);
static ssize_t ngx_http_lua_pipe_fd_read(ngx_connection_t *c, u_char *buf,
    size_t size);
static ssize_t ngx_http_lua_pipe_fd_write(ngx_connection_t *c, u_char *buf,
    size_t size);
static void ngx_http_lua_pipe_close_helper(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx, ngx_event_t *ev);
static void ngx_http_lua_pipe_close_stdin(ngx_http_lua_pipe_t *pipe);
static void ngx_http_lua_pipe_close_stdout(ngx_http_lua_pipe_t *pipe);
static void ngx_http_lua_pipe_close_stderr(ngx_http_lua_pipe_t *pipe);
static void ngx_http_lua_pipe_proc_finalize(ngx_http_lua_ffi_pipe_proc_t *proc);
static ngx_int_t ngx_http_lua_pipe_get_lua_ctx(ngx_http_request_t *r,
    ngx_http_lua_ctx_t **ctx, u_char *errbuf, size_t *errbuf_size);
static void ngx_http_lua_pipe_put_error(ngx_http_lua_pipe_ctx_t *pipe_ctx,
    u_char *errbuf, size_t *errbuf_size);
static void ngx_http_lua_pipe_put_data(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx, u_char **buf, size_t *buf_size);
static ngx_int_t ngx_http_lua_pipe_add_input_buffer(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx);
static ngx_int_t ngx_http_lua_pipe_read_all(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_pipe_read_bytes(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_pipe_read_line(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_pipe_read_any(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_pipe_read(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx);
static ngx_int_t ngx_http_lua_pipe_init_ctx(
    ngx_http_lua_pipe_ctx_t **pipe_ctx_pt, int fd, ngx_pool_t *pool,
    u_char *errbuf, size_t *errbuf_size);
static ngx_int_t ngx_http_lua_pipe_write(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx);
static int ngx_http_lua_pipe_read_stdout_retval(
    ngx_http_lua_ffi_pipe_proc_t *proc, lua_State *L);
static int ngx_http_lua_pipe_read_stderr_retval(
    ngx_http_lua_ffi_pipe_proc_t *proc, lua_State *L);
static int ngx_http_lua_pipe_read_retval_helper(
    ngx_http_lua_ffi_pipe_proc_t *proc, lua_State *L, int from_stderr);
static int ngx_http_lua_pipe_write_retval(ngx_http_lua_ffi_pipe_proc_t *proc,
    lua_State *L);
static int ngx_http_lua_pipe_wait_retval(ngx_http_lua_ffi_pipe_proc_t *proc,
    lua_State *L);
static void ngx_http_lua_pipe_resume_helper(ngx_event_t *ev,
    ngx_http_lua_co_ctx_t *wait_co_ctx);
static void ngx_http_lua_pipe_resume_read_stdout_handler(ngx_event_t *ev);
static void ngx_http_lua_pipe_resume_read_stderr_handler(ngx_event_t *ev);
static void ngx_http_lua_pipe_resume_write_handler(ngx_event_t *ev);
static void ngx_http_lua_pipe_resume_wait_handler(ngx_event_t *ev);
static ngx_int_t ngx_http_lua_pipe_resume(ngx_http_request_t *r);
static void ngx_http_lua_pipe_dummy_event_handler(ngx_event_t *ev);
static void ngx_http_lua_pipe_clear_event(ngx_event_t *ev);
static void ngx_http_lua_pipe_proc_read_stdout_cleanup(void *data);
static void ngx_http_lua_pipe_proc_read_stderr_cleanup(void *data);
static void ngx_http_lua_pipe_proc_write_cleanup(void *data);
static void ngx_http_lua_pipe_proc_wait_cleanup(void *data);
static void ngx_http_lua_pipe_reap_pids(ngx_event_t *ev);
static void ngx_http_lua_pipe_reap_timer_handler(ngx_event_t *ev);
void ngx_http_lua_ffi_pipe_proc_destroy(
    ngx_http_lua_ffi_pipe_proc_t *proc);


static ngx_rbtree_t       ngx_http_lua_pipe_rbtree;
static ngx_rbtree_node_t  ngx_http_lua_pipe_proc_sentinel;
static ngx_event_t        ngx_reap_pid_event;


#if (NGX_HTTP_LUA_HAVE_SIGNALFD)
static int                                ngx_http_lua_signalfd;
static struct signalfd_siginfo            ngx_http_lua_pipe_notification;

#define ngx_http_lua_read_sigfd           ngx_http_lua_signalfd

#else
static int                                ngx_http_lua_sigchldfd[2];
static u_char                             ngx_http_lua_pipe_notification[1];

#define ngx_http_lua_read_sigfd           ngx_http_lua_sigchldfd[0]
#define ngx_http_lua_write_sigfd          ngx_http_lua_sigchldfd[1]
#endif


static ngx_connection_t                  *ngx_http_lua_sigfd_conn = NULL;


/* The below signals are ignored by Nginx.
 * We need to reset them for the spawned child processes. */
ngx_http_lua_pipe_signal_t ngx_signals[] = {
    { SIGSYS, "SIGSYS" },
    { SIGPIPE, "SIGPIPE" },
    { 0, NULL }
};


enum {
    PIPE_ERR_CLOSED = 1,
    PIPE_ERR_SYSCALL,
    PIPE_ERR_NOMEM,
    PIPE_ERR_TIMEOUT,
    PIPE_ERR_ADD_READ_EV,
    PIPE_ERR_ADD_WRITE_EV,
    PIPE_ERR_ABORTED,
};


enum {
    PIPE_READ_ALL = 0,
    PIPE_READ_BYTES,
    PIPE_READ_LINE,
    PIPE_READ_ANY,
};


#define REASON_EXIT         "exit"
#define REASON_SIGNAL       "signal"
#define REASON_UNKNOWN      "unknown"

#define REASON_RUNNING_CODE  0
#define REASON_EXIT_CODE     1
#define REASON_SIGNAL_CODE   2
#define REASON_UNKNOWN_CODE  3


void
ngx_http_lua_pipe_init(void)
{
    ngx_rbtree_init(&ngx_http_lua_pipe_rbtree,
                    &ngx_http_lua_pipe_proc_sentinel, ngx_rbtree_insert_value);
}


ngx_int_t
ngx_http_lua_pipe_add_signal_handler(ngx_cycle_t *cycle)
{
    ngx_event_t         *rev;
#if (NGX_HTTP_LUA_HAVE_SIGNALFD)
    sigset_t             set;

#else
    int                  rc;
    struct sigaction     sa;
#endif

    ngx_reap_pid_event.handler = ngx_http_lua_pipe_reap_timer_handler;
    ngx_reap_pid_event.log = cycle->log;
    ngx_reap_pid_event.data = cycle;
    ngx_reap_pid_event.cancelable = 1;

    if (!ngx_reap_pid_event.timer_set) {
        ngx_add_timer(&ngx_reap_pid_event, 1000);
    }

#if (NGX_HTTP_LUA_HAVE_SIGNALFD)
    if (sigemptyset(&set) != 0) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno,
                      "lua pipe init signal set failed");
        return NGX_ERROR;
    }

    if (sigaddset(&set, SIGCHLD) != 0) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno,
                      "lua pipe add SIGCHLD to signal set failed");
        return NGX_ERROR;
    }

    if (sigprocmask(SIG_BLOCK, &set, NULL) != 0) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno,
                      "lua pipe block SIGCHLD failed");
        return NGX_ERROR;
    }

    ngx_http_lua_signalfd = signalfd(-1, &set, SFD_NONBLOCK|SFD_CLOEXEC);
    if (ngx_http_lua_signalfd < 0) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno,
                      "lua pipe create signalfd instance failed");
        return NGX_ERROR;
    }

#else /* !(NGX_HTTP_LUA_HAVE_SIGNALFD) */
#   if (NGX_HTTP_LUA_HAVE_PIPE2)
    rc = pipe2(ngx_http_lua_sigchldfd, O_NONBLOCK|O_CLOEXEC);
#   else
    rc = pipe(ngx_http_lua_sigchldfd);
#   endif

    if (rc == -1) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno,
                      "lua pipe init SIGCHLD fd failed");
        return NGX_ERROR;
    }

#   if !(NGX_HTTP_LUA_HAVE_PIPE2)
    if (ngx_nonblocking(ngx_http_lua_read_sigfd) == -1) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno, "lua pipe "
                      ngx_nonblocking_n " SIGCHLD read fd failed");
        goto failed;
    }

    if (ngx_nonblocking(ngx_http_lua_write_sigfd) == -1) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno, "lua pipe "
                      ngx_nonblocking_n " SIGCHLD write fd failed");
        goto failed;
    }

    /* it's ok not to set the pipe fd with O_CLOEXEC. This requires
     * extra syscall */
#   endif /* !(NGX_HTTP_LUA_HAVE_PIPE2) */
#endif /* NGX_HTTP_LUA_HAVE_SIGNALFD */

    ngx_http_lua_sigfd_conn = ngx_get_connection(ngx_http_lua_read_sigfd,
                                                 cycle->log);
    if (ngx_http_lua_sigfd_conn == NULL) {
        goto failed;
    }

    ngx_http_lua_sigfd_conn->log = cycle->log;
    ngx_http_lua_sigfd_conn->recv = ngx_http_lua_pipe_fd_read;
    rev = ngx_http_lua_sigfd_conn->read;
    rev->log = ngx_http_lua_sigfd_conn->log;
    rev->handler = ngx_http_lua_pipe_sigchld_event_handler;

#ifdef HAVE_SOCKET_CLOEXEC_PATCH
    rev->skip_socket_leak_check = 1;
#endif

    if (ngx_handle_read_event(rev, 0) == NGX_ERROR) {
        goto failed;
    }

#if !(NGX_HTTP_LUA_HAVE_SIGNALFD)
    ngx_memzero(&sa, sizeof(struct sigaction));
    sa.sa_sigaction = ngx_http_lua_pipe_sigchld_handler;
    sa.sa_flags = SA_SIGINFO;

    if (sigemptyset(&sa.sa_mask) != 0) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno,
                      "lua pipe init signal mask failed");
        goto failed;
    }

    if (sigaction(SIGCHLD, &sa, NULL) == -1) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, ngx_errno,
                      "lua pipe sigaction(SIGCHLD) failed");
        goto failed;
    }
#endif

    return NGX_OK;

failed:

    if (ngx_http_lua_sigfd_conn != NULL) {
        ngx_close_connection(ngx_http_lua_sigfd_conn);
        ngx_http_lua_sigfd_conn = NULL;
    }

    if (close(ngx_http_lua_read_sigfd) == -1) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                      "lua pipe close the read sigfd failed");
    }

#if !(NGX_HTTP_LUA_HAVE_SIGNALFD)
    if (close(ngx_http_lua_write_sigfd) == -1) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                      "lua pipe close the write sigfd failed");
    }
#endif

    return NGX_ERROR;
}


static ngx_rbtree_node_t *
ngx_http_lua_pipe_lookup_pid(ngx_rbtree_key_t key)
{
    ngx_rbtree_node_t    *node, *sentinel;

    node = ngx_http_lua_pipe_rbtree.root;
    sentinel = ngx_http_lua_pipe_rbtree.sentinel;

    while (node != sentinel) {
        if (key < node->key) {
            node = node->left;
            continue;
        }

        if (key > node->key) {
            node = node->right;
            continue;
        }

        return node;
    }

    return NULL;
}


#if !(NGX_HTTP_LUA_HAVE_SIGNALFD)
static void
ngx_http_lua_pipe_sigchld_handler(int signo, siginfo_t *siginfo,
    void *ucontext)
{
    ngx_err_t                        err, saved_err;
    ngx_int_t                        n;

    saved_err = ngx_errno;

    for ( ;; ) {
        n = write(ngx_http_lua_write_sigfd, ngx_http_lua_pipe_notification,
                  sizeof(ngx_http_lua_pipe_notification));

        ngx_log_debug1(NGX_LOG_DEBUG_EVENT, ngx_cycle->log, 0,
                       "lua pipe SIGCHLD fd write siginfo:%p", siginfo);

        if (n >= 0) {
            break;
        }

        err = ngx_errno;

        if (err != NGX_EINTR) {
            if (err != NGX_EAGAIN) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, err,
                              "lua pipe SIGCHLD fd write failed");
            }

            break;
        }

        ngx_log_debug0(NGX_LOG_DEBUG_EVENT, ngx_cycle->log, err,
                       "lua pipe SIGCHLD fd write was interrupted");
    }

    ngx_set_errno(saved_err);
}
#endif


static void
ngx_http_lua_pipe_sigchld_event_handler(ngx_event_t *ev)
{
    int                              n;
    ngx_connection_t                *c = ev->data;

    ngx_log_debug0(NGX_LOG_DEBUG_EVENT, ngx_cycle->log, 0,
                   "lua pipe reaping children");

    for ( ;; ) {
#if (NGX_HTTP_LUA_HAVE_SIGNALFD)
        n = c->recv(c, (u_char *) &ngx_http_lua_pipe_notification,
#else
        n = c->recv(c, ngx_http_lua_pipe_notification,
#endif
                    sizeof(ngx_http_lua_pipe_notification));

        if (n <= 0) {
            if (n == NGX_ERROR) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe SIGCHLD fd read failed");
            }

            break;
        }

        ngx_http_lua_pipe_reap_pids(ev);
    }
}


static void
ngx_http_lua_pipe_reap_pids(ngx_event_t *ev)
{
    int                              status;
    ngx_pid_t                        pid;
    ngx_rbtree_node_t               *node;
    ngx_http_lua_pipe_node_t        *pipe_node;

    for ( ;; ) {
        pid = waitpid(-1, &status, WNOHANG);

        if (pid == 0) {
            break;
        }

        if (pid < 0) {
            if (ngx_errno != NGX_ECHILD) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe waitpid failed");
            }

            break;
        }

        /* This log is ported from Nginx's signal handler since we override
         * or block it in this implementation. */
        ngx_log_error(NGX_LOG_NOTICE, ngx_cycle->log, 0,
                      "signal %d (SIGCHLD) received from %P",
                      SIGCHLD, pid);

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe SIGCHLD fd read pid:%P status:%d", pid,
                       status);

        node = ngx_http_lua_pipe_lookup_pid(pid);
        if (node != NULL) {
            pipe_node = (ngx_http_lua_pipe_node_t *) &node->color;
            if (pipe_node->wait_co_ctx != NULL) {
                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                               "lua pipe resume process:%p waiting for %P",
                               pipe_node->proc, pid);

                /*
                 * We need the extra parentheses around the first argument
                 * of ngx_post_event() just to work around macro issues in
                 * nginx cores older than 1.7.12 (exclusive).
                 */
                ngx_post_event((&pipe_node->wait_co_ctx->sleep),
                               &ngx_posted_events);
            }

            /* TODO: we should proactively close and free up the pipe after
             * the user consume all the data in the pipe.
             */
            pipe_node->proc->pipe->dead = 1;

            if (WIFSIGNALED(status)) {
                pipe_node->status = WTERMSIG(status);
                pipe_node->reason_code = REASON_SIGNAL_CODE;

            } else if (WIFEXITED(status)) {
                pipe_node->status = WEXITSTATUS(status);
                pipe_node->reason_code = REASON_EXIT_CODE;

            } else {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                              "lua pipe unknown exit status %d from "
                              "process %P", status, pid);
                pipe_node->status = status;
                pipe_node->reason_code = REASON_UNKNOWN_CODE;
            }
        }
    }
}


static void
ngx_http_lua_pipe_reap_timer_handler(ngx_event_t *ev)
{
    ngx_http_lua_pipe_reap_pids(ev);

    if (!ngx_exiting) {
        ngx_add_timer(&ngx_reap_pid_event, 1000);
        ngx_reap_pid_event.timedout = 0;
    }
}


static ssize_t
ngx_http_lua_pipe_fd_read(ngx_connection_t *c, u_char *buf, size_t size)
{
    ssize_t       n;
    ngx_err_t     err;
    ngx_event_t  *rev;

    rev = c->read;

    do {
        n = read(c->fd, buf, size);

        err = ngx_errno;

        ngx_log_debug3(NGX_LOG_DEBUG_EVENT, c->log, 0,
                       "read: fd:%d %z of %uz", c->fd, n, size);

        if (n == 0) {
            rev->ready = 0;
            rev->eof = 1;
            return 0;
        }

        if (n > 0) {
            if ((size_t) n < size
                && !(ngx_event_flags & NGX_USE_GREEDY_EVENT))
            {
                rev->ready = 0;
            }

            return n;
        }

        if (err == NGX_EAGAIN || err == NGX_EINTR) {
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, err,
                           "read() not ready");
            n = NGX_AGAIN;

        } else {
            n = ngx_connection_error(c, err, "read() failed");
            break;
        }

    } while (err == NGX_EINTR);

    rev->ready = 0;

    if (n == NGX_ERROR) {
        rev->error = 1;
    }

    return n;
}


static ssize_t
ngx_http_lua_pipe_fd_write(ngx_connection_t *c, u_char *buf, size_t size)
{
    ssize_t       n;
    ngx_err_t     err;
    ngx_event_t  *wev;

    wev = c->write;

    do {
        n = write(c->fd, buf, size);

        ngx_log_debug3(NGX_LOG_DEBUG_EVENT, c->log, 0,
                       "write: fd:%d %z of %uz", c->fd, n, size);

        if (n >= 0) {
            if ((size_t) n != size) {
                wev->ready = 0;
            }

            return n;
        }

        err = ngx_errno;

        if (err == NGX_EAGAIN || err == NGX_EINTR) {
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, err,
                           "write() not ready");
            n = NGX_AGAIN;

        } else if (err != NGX_EPIPE) {
            n = ngx_connection_error(c, err, "write() failed");
            break;
        }

    } while (err == NGX_EINTR);

    wev->ready = 0;

    if (n == NGX_ERROR) {
        wev->error = 1;
    }

    return n;
}


#if !(NGX_HTTP_LUA_HAVE_EXECVPE)
static int
ngx_http_lua_execvpe(const char *program, char * const argv[],
    char * const envp[])
{
    int    rc;
    char **saved = environ;

    environ = (char **) envp;
    rc = execvp(program, argv);
    environ = saved;
    return rc;
}
#endif


int
ngx_http_lua_ffi_pipe_spawn(ngx_http_request_t *r,
    ngx_http_lua_ffi_pipe_proc_t *proc,
    const char *file, const char **argv, int merge_stderr, size_t buffer_size,
    const char **environ, u_char *errbuf, size_t *errbuf_size)
{
    int                             rc;
    int                             in[2];
    int                             out[2];
    int                             err[2];
    int                             stdin_fd, stdout_fd, stderr_fd;
    int                             errlog_fd, temp_errlog_fd;
    ngx_pid_t                       pid;
    ssize_t                         pool_size;
    ngx_pool_t                     *pool;
    ngx_uint_t                      i;
    ngx_listening_t                *ls;
    ngx_http_lua_pipe_t            *pp;
    ngx_rbtree_node_t              *node;
    ngx_http_lua_pipe_node_t       *pipe_node;
    struct sigaction                sa;
    ngx_http_lua_pipe_signal_t     *sig;
    ngx_pool_cleanup_t             *cln;
    sigset_t                        set;

    pool_size = ngx_align(NGX_MIN_POOL_SIZE + buffer_size * 2,
                          NGX_POOL_ALIGNMENT);

    pool = ngx_create_pool(pool_size, ngx_cycle->log);
    if (pool == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "no memory")
                       - errbuf;
        return NGX_ERROR;
    }

    pp = ngx_pcalloc(pool, sizeof(ngx_http_lua_pipe_t)
                     + offsetof(ngx_rbtree_node_t, color)
                     + sizeof(ngx_http_lua_pipe_node_t));
    if (pp == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "no memory")
                       - errbuf;
        goto free_pool;
    }

    rc = pipe(in);
    if (rc == -1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "pipe failed: %s",
                                    strerror(errno))
                       - errbuf;
        goto free_pool;
    }

    rc = pipe(out);
    if (rc == -1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "pipe failed: %s",
                                    strerror(errno))
                       - errbuf;
        goto close_in_fd;
    }

    if (!merge_stderr) {
        rc = pipe(err);
        if (rc == -1) {
            *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                        "pipe failed: %s", strerror(errno))
                           - errbuf;
            goto close_in_out_fd;
        }
    }

    pid = fork();
    if (pid == -1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "fork failed: %s",
                                    strerror(errno))
                       - errbuf;
        goto close_in_out_err_fd;
    }

    if (pid == 0) {

#if (NGX_HAVE_CPU_AFFINITY)
        /* reset the CPU affinity mask */
        ngx_uint_t     log_level;
        ngx_cpuset_t   child_cpu_affinity;

        if (ngx_process == NGX_PROCESS_WORKER
            && ngx_get_cpu_affinity(ngx_worker) != NULL)
        {
            CPU_ZERO(&child_cpu_affinity);

            for (i = 0; i < (ngx_uint_t) ngx_min(ngx_ncpu, CPU_SETSIZE); i++) {
                CPU_SET(i, &child_cpu_affinity);
            }

            log_level = ngx_cycle->log->log_level;
            ngx_cycle->log->log_level = NGX_LOG_WARN;
            ngx_setaffinity(&child_cpu_affinity, ngx_cycle->log);
            ngx_cycle->log->log_level = log_level;
        }
#endif

        /* reset the handler of ignored signals to the default */
        for (sig = ngx_signals; sig->signo != 0; sig++) {
            ngx_memzero(&sa, sizeof(struct sigaction));
            sa.sa_handler = SIG_DFL;

            if (sigemptyset(&sa.sa_mask) != 0) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe child init signal mask failed");
                exit(EXIT_FAILURE);
            }

            if (sigaction(sig->signo, &sa, NULL) == -1) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe child reset signal handler for %s "
                              "failed", sig->signame);
                exit(EXIT_FAILURE);
            }
        }

        /* reset signal mask */
        if (sigemptyset(&set) != 0) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                          "lua pipe child init signal set failed");
            exit(EXIT_FAILURE);
        }

        if (sigprocmask(SIG_SETMASK, &set, NULL) != 0) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                          "lua pipe child reset signal mask failed");
            exit(EXIT_FAILURE);
        }

        /* close listening socket fd */
        ls = ngx_cycle->listening.elts;
        for (i = 0; i < ngx_cycle->listening.nelts; i++) {
            if (ls[i].fd != (ngx_socket_t) -1 &&
                ngx_close_socket(ls[i].fd) == -1)
            {
                ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, ngx_socket_errno,
                              "lua pipe child " ngx_close_socket_n
                              " %V failed", &ls[i].addr_text);
            }
        }

        /* close and dup pipefd */
        if (close(in[1]) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                          "lua pipe child failed to close the in[1] "
                          "pipe fd");
        }

        if (close(out[0]) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                          "lua pipe child failed to close the out[0] "
                          "pipe fd");
        }

        if (ngx_cycle->log->file && ngx_cycle->log->file->fd == STDERR_FILENO) {
            errlog_fd = ngx_cycle->log->file->fd;
            temp_errlog_fd = dup(errlog_fd);

            if (temp_errlog_fd == -1) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe child dup errlog fd failed");
                exit(EXIT_FAILURE);
            }

            if (ngx_cloexec(temp_errlog_fd) == -1) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe child new errlog fd " ngx_cloexec_n
                              " failed");
            }

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "lua pipe child dup old errlog fd %d to new fd %d",
                           ngx_cycle->log->file->fd, temp_errlog_fd);

            ngx_cycle->log->file->fd = temp_errlog_fd;
        }

        if (dup2(in[0], STDIN_FILENO) == -1) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                          "lua pipe child dup2 stdin failed");
            exit(EXIT_FAILURE);
        }

        if (dup2(out[1], STDOUT_FILENO) == -1) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                          "lua pipe child dup2 stdout failed");
            exit(EXIT_FAILURE);
        }

        if (merge_stderr) {
            if (dup2(STDOUT_FILENO, STDERR_FILENO) == -1) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe child dup2 stderr failed");
                exit(EXIT_FAILURE);
            }

        } else {
            if (close(err[0]) == -1) {
                ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                              "lua pipe child failed to close the err[0] "
                              "pipe fd");
            }

            if (dup2(err[1], STDERR_FILENO) == -1) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe child dup2 stderr failed");
                exit(EXIT_FAILURE);
            }
        }

        if (close(in[0]) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                          "lua pipe failed to close the in[0]");
        }

        if (close(out[1]) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                          "lua pipe failed to close the out[1]");
        }

        if (!merge_stderr) {
            if (close(err[1]) == -1) {
                ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                              "lua pipe failed to close the err[1]");
            }
        }

        if (environ != NULL) {
#if (NGX_HTTP_LUA_HAVE_EXECVPE)
            if (execvpe(file, (char * const *) argv, (char * const *) environ)
#else
            if (ngx_http_lua_execvpe(file, (char * const *) argv,
                                     (char * const *) environ)
#endif
                == -1)
            {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe child execvpe() failed while "
                              "executing %s", file);
            }

        } else {
            if (execvp(file, (char * const *) argv) == -1) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe child execvp() failed while "
                              "executing %s", file);
            }
        }

        exit(EXIT_FAILURE);
    }

    /* parent process */
    if (close(in[0]) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                      "lua pipe: failed to close the in[0] pipe fd");
    }

    stdin_fd = in[1];

    if (ngx_nonblocking(stdin_fd) == -1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    ngx_nonblocking_n " failed: %s",
                                    strerror(errno))
                       - errbuf;
        goto close_in_out_err_fd;
    }

    pp->stdin_fd = stdin_fd;

    if (close(out[1]) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                      "lua pipe: failed to close the out[1] pipe fd");
    }

    stdout_fd = out[0];

    if (ngx_nonblocking(stdout_fd) == -1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    ngx_nonblocking_n " failed: %s",
                                    strerror(errno))
                       - errbuf;
        goto close_in_out_err_fd;
    }

    pp->stdout_fd = stdout_fd;

    if (!merge_stderr) {
        if (close(err[1]) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                          "lua pipe: failed to close the err[1] pipe fd");
        }

        stderr_fd = err[0];

        if (ngx_nonblocking(stderr_fd) == -1) {
            *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                        ngx_nonblocking_n " failed: %s",
                                        strerror(errno))
                           - errbuf;
            goto close_in_out_err_fd;
        }

        pp->stderr_fd = stderr_fd;
    }

    if (pp->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(r->pool, 0);

        if (cln == NULL) {
            *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "no memory")
                           - errbuf;
            goto close_in_out_err_fd;
        }

        cln->handler = (ngx_pool_cleanup_pt) ngx_http_lua_ffi_pipe_proc_destroy;
        cln->data = proc;
        pp->cleanup = &cln->handler;
        pp->r = r;
    }

    node = (ngx_rbtree_node_t *) (pp + 1);
    node->key = pid;
    pipe_node = (ngx_http_lua_pipe_node_t *) &node->color;
    pipe_node->proc = proc;
    ngx_rbtree_insert(&ngx_http_lua_pipe_rbtree, node);

    pp->node = node;
    pp->pool = pool;
    pp->merge_stderr = merge_stderr;
    pp->buffer_size = buffer_size;

    proc->_pid = pid;
    proc->pipe = pp;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe spawn process:%p pid:%P merge_stderr:%d "
                   "buffer_size:%uz", proc, pid, merge_stderr, buffer_size);
    return NGX_OK;

close_in_out_err_fd:

    if (!merge_stderr) {
        if (close(err[0]) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                          "failed to close the err[0] pipe fd");
        }

        if (close(err[1]) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                          "failed to close the err[1] pipe fd");
        }
    }

close_in_out_fd:

    if (close(out[0]) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                      "failed to close the out[0] pipe fd");
    }

    if (close(out[1]) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                      "failed to close the out[1] pipe fd");
    }

close_in_fd:

    if (close(in[0]) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                      "failed to close the in[0] pipe fd");
    }

    if (close(in[1]) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                      "failed to close the in[1] pipe fd");
    }

free_pool:

    ngx_destroy_pool(pool);
    return NGX_ERROR;
}


static void
ngx_http_lua_pipe_close_helper(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx, ngx_event_t *ev)
{
    if (ev->handler != ngx_http_lua_pipe_dummy_event_handler) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe abort blocking operation pipe_ctx:%p ev:%p",
                       pipe_ctx, ev);

        if (pipe->dead) {
            pipe_ctx->err_type = PIPE_ERR_CLOSED;

        } else {
            pipe_ctx->err_type = PIPE_ERR_ABORTED;
        }

        ngx_post_event(ev, &ngx_posted_events);
        return;
    }

    ngx_close_connection(pipe_ctx->c);
    pipe_ctx->c = NULL;
}


static void
ngx_http_lua_pipe_close_stdin(ngx_http_lua_pipe_t *pipe)
{
    ngx_event_t                     *wev;

    if (pipe->stdin_ctx == NULL) {
        if (pipe->stdin_fd != -1) {
            if (close(pipe->stdin_fd) == -1) {
                ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                              "failed to close the stdin pipe fd");
            }

            pipe->stdin_fd = -1;
        }

    } else if (pipe->stdin_ctx->c != NULL) {
        wev = pipe->stdin_ctx->c->write;
        ngx_http_lua_pipe_close_helper(pipe, pipe->stdin_ctx, wev);
    }
}


static void
ngx_http_lua_pipe_close_stdout(ngx_http_lua_pipe_t *pipe)
{
    ngx_event_t                     *rev;

    if (pipe->stdout_ctx == NULL) {
        if (pipe->stdout_fd != -1) {
            if (close(pipe->stdout_fd) == -1) {
                ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                              "failed to close the stdout pipe fd");
            }

            pipe->stdout_fd = -1;
        }

    } else if (pipe->stdout_ctx->c != NULL) {
        rev = pipe->stdout_ctx->c->read;
        ngx_http_lua_pipe_close_helper(pipe, pipe->stdout_ctx, rev);
    }
}


static void
ngx_http_lua_pipe_close_stderr(ngx_http_lua_pipe_t *pipe)
{
    ngx_event_t                     *rev;

    if (pipe->stderr_ctx == NULL) {
        if (pipe->stderr_fd != -1) {
            if (close(pipe->stderr_fd) == -1) {
                ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                              "failed to close the stderr pipe fd");
            }

            pipe->stderr_fd = -1;
        }

    } else if (pipe->stderr_ctx->c != NULL) {
        rev = pipe->stderr_ctx->c->read;
        ngx_http_lua_pipe_close_helper(pipe, pipe->stderr_ctx, rev);
    }
}


int
ngx_http_lua_ffi_pipe_proc_shutdown_stdin(ngx_http_lua_ffi_pipe_proc_t *proc,
    u_char *errbuf, size_t *errbuf_size)
{
    ngx_http_lua_pipe_t             *pipe;

    pipe = proc->pipe;
    if (pipe == NULL || pipe->closed) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        return NGX_ERROR;
    }

    ngx_http_lua_pipe_close_stdin(pipe);

    return NGX_OK;
}


int
ngx_http_lua_ffi_pipe_proc_shutdown_stdout(ngx_http_lua_ffi_pipe_proc_t *proc,
    u_char *errbuf, size_t *errbuf_size)
{
    ngx_http_lua_pipe_t             *pipe;

    pipe = proc->pipe;
    if (pipe == NULL || pipe->closed) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        return NGX_ERROR;
    }

    ngx_http_lua_pipe_close_stdout(pipe);

    return NGX_OK;
}


int
ngx_http_lua_ffi_pipe_proc_shutdown_stderr(ngx_http_lua_ffi_pipe_proc_t *proc,
    u_char *errbuf, size_t *errbuf_size)
{
    ngx_http_lua_pipe_t             *pipe;

    pipe = proc->pipe;
    if (pipe == NULL || pipe->closed) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        return NGX_ERROR;
    }

    if (pipe->merge_stderr) {
        /* stdout is used internally as stderr when merge_stderr is true */
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "merged to stdout")
                       - errbuf;
        return NGX_ERROR;
    }

    ngx_http_lua_pipe_close_stderr(pipe);

    return NGX_OK;
}


static void
ngx_http_lua_pipe_proc_finalize(ngx_http_lua_ffi_pipe_proc_t *proc)
{
    ngx_http_lua_pipe_t          *pipe;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe finalize process:%p pid:%P",
                   proc, proc->_pid);
    pipe = proc->pipe;

    if (pipe->node) {
        ngx_rbtree_delete(&ngx_http_lua_pipe_rbtree, pipe->node);
        pipe->node = NULL;
    }

    pipe->dead = 1;

    ngx_http_lua_pipe_close_stdin(pipe);
    ngx_http_lua_pipe_close_stdout(pipe);

    if (!pipe->merge_stderr) {
        ngx_http_lua_pipe_close_stderr(pipe);
    }

    pipe->closed = 1;
}


void
ngx_http_lua_ffi_pipe_proc_destroy(ngx_http_lua_ffi_pipe_proc_t *proc)
{
    ngx_http_lua_pipe_t          *pipe;

    pipe = proc->pipe;
    if (pipe == NULL) {
        return;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe destroy process:%p pid:%P", proc, proc->_pid);

    if (!pipe->dead) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe kill process:%p pid:%P", proc, proc->_pid);

        if (kill(proc->_pid, SIGKILL) == -1) {
            if (ngx_errno != ESRCH) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, ngx_errno,
                              "lua pipe failed to kill process:%p pid:%P",
                              proc, proc->_pid);
            }
        }
    }

    if (pipe->cleanup != NULL) {
        *pipe->cleanup = NULL;
        ngx_http_lua_cleanup_free(pipe->r, pipe->cleanup);
        pipe->cleanup = NULL;
    }

    ngx_http_lua_pipe_proc_finalize(proc);
    ngx_destroy_pool(pipe->pool);
    proc->pipe = NULL;
}


static ngx_int_t
ngx_http_lua_pipe_get_lua_ctx(ngx_http_request_t *r,
    ngx_http_lua_ctx_t **ctx, u_char *errbuf, size_t *errbuf_size)
{
    int                                 rc;

    *ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (*ctx == NULL) {
        return NGX_HTTP_LUA_FFI_NO_REQ_CTX;
    }

    rc = ngx_http_lua_ffi_check_context(*ctx, NGX_HTTP_LUA_CONTEXT_YIELDABLE,
                                        errbuf, errbuf_size);
    if (rc != NGX_OK) {
        return NGX_HTTP_LUA_FFI_BAD_CONTEXT;
    }

    return NGX_OK;
}


static void
ngx_http_lua_pipe_put_error(ngx_http_lua_pipe_ctx_t *pipe_ctx, u_char *errbuf,
    size_t *errbuf_size)
{
    switch (pipe_ctx->err_type) {

    case PIPE_ERR_CLOSED:
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        break;

    case PIPE_ERR_SYSCALL:
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "%s",
                                    strerror(pipe_ctx->pipe_errno))
                       - errbuf;
        break;

    case PIPE_ERR_NOMEM:
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "no memory")
                       - errbuf;
        break;

    case PIPE_ERR_TIMEOUT:
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "timeout")
                       - errbuf;
        break;

    case PIPE_ERR_ADD_READ_EV:
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "failed to add read event")
                       - errbuf;
        break;

    case PIPE_ERR_ADD_WRITE_EV:
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "failed to add write event")
                       - errbuf;
        break;

    case PIPE_ERR_ABORTED:
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "aborted") - errbuf;
        break;

    default:
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "unexpected err type: %d", pipe_ctx->err_type);
        ngx_http_lua_assert(NULL);
    }
}


static void
ngx_http_lua_pipe_put_data(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx, u_char **buf, size_t *buf_size)
{
    size_t                   size = 0;
    size_t                   chunk_size;
    size_t                   nbufs;
    u_char                  *p;
    ngx_buf_t               *b;
    ngx_chain_t             *cl;
    ngx_chain_t            **ll;

    nbufs = 0;
    ll = NULL;

    for (cl = pipe_ctx->bufs_in; cl; cl = cl->next) {
        b = cl->buf;
        chunk_size = b->last - b->pos;

        if (cl->next) {
            ll = &cl->next;
        }

        size += chunk_size;

        nbufs++;
    }

    if (*buf_size < size) {
        *buf = NULL;
        *buf_size = size;

        return;
    }

    *buf_size = size;

    p = *buf;
    for (cl = pipe_ctx->bufs_in; cl; cl = cl->next) {
        b = cl->buf;
        chunk_size = b->last - b->pos;
        p = ngx_cpymem(p, b->pos, chunk_size);
    }

    if (nbufs > 1 && ll) {
        *ll = pipe->free_bufs;
        pipe->free_bufs = pipe_ctx->bufs_in;
        pipe_ctx->bufs_in = pipe_ctx->buf_in;
    }

    if (pipe_ctx->buffer.pos == pipe_ctx->buffer.last) {
        pipe_ctx->buffer.pos = pipe_ctx->buffer.start;
        pipe_ctx->buffer.last = pipe_ctx->buffer.start;
    }

    if (pipe_ctx->bufs_in) {
        pipe_ctx->buf_in->buf->last = pipe_ctx->buffer.pos;
        pipe_ctx->buf_in->buf->pos = pipe_ctx->buffer.pos;
    }
}


static ngx_int_t
ngx_http_lua_pipe_add_input_buffer(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx)
{
    ngx_chain_t             *cl;

    cl = ngx_http_lua_chain_get_free_buf(ngx_cycle->log, pipe->pool,
                                         &pipe->free_bufs,
                                         pipe->buffer_size);

    if (cl == NULL) {
        pipe_ctx->err_type = PIPE_ERR_NOMEM;
        return NGX_ERROR;
    }

    pipe_ctx->buf_in->next = cl;
    pipe_ctx->buf_in = cl;
    pipe_ctx->buffer = *cl->buf;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_pipe_read_all(void *data, ssize_t bytes)
{
    ngx_http_lua_pipe_ctx_t      *pipe_ctx = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0, "lua pipe read all");
    return ngx_http_lua_read_all(&pipe_ctx->buffer, pipe_ctx->buf_in, bytes,
                                 ngx_cycle->log);
}


static ngx_int_t
ngx_http_lua_pipe_read_bytes(void *data, ssize_t bytes)
{
    ngx_int_t                          rc;
    ngx_http_lua_pipe_ctx_t           *pipe_ctx = data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe read bytes %z", bytes);

    rc = ngx_http_lua_read_bytes(&pipe_ctx->buffer, pipe_ctx->buf_in,
                                 &pipe_ctx->rest, bytes, ngx_cycle->log);
    if (rc == NGX_ERROR) {
        pipe_ctx->err_type = PIPE_ERR_CLOSED;
        return NGX_ERROR;
    }

    return rc;
}


static ngx_int_t
ngx_http_lua_pipe_read_line(void *data, ssize_t bytes)
{
    ngx_int_t                          rc;
    ngx_http_lua_pipe_ctx_t           *pipe_ctx = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe read line");
    rc = ngx_http_lua_read_line(&pipe_ctx->buffer, pipe_ctx->buf_in, bytes,
                                ngx_cycle->log);
    if (rc == NGX_ERROR) {
        pipe_ctx->err_type = PIPE_ERR_CLOSED;
        return NGX_ERROR;
    }

    return rc;
}


static ngx_int_t
ngx_http_lua_pipe_read_any(void *data, ssize_t bytes)
{
    ngx_int_t                          rc;
    ngx_http_lua_pipe_ctx_t           *pipe_ctx = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0, "lua pipe read any");
    rc = ngx_http_lua_read_any(&pipe_ctx->buffer, pipe_ctx->buf_in,
                               &pipe_ctx->rest, bytes, ngx_cycle->log);
    if (rc == NGX_ERROR) {
        pipe_ctx->err_type = PIPE_ERR_CLOSED;
        return NGX_ERROR;
    }

    return rc;
}


static ngx_int_t
ngx_http_lua_pipe_read(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx)
{
    int                                 rc;
    int                                 read;
    size_t                              size;
    ssize_t                             n;
    ngx_buf_t                          *b;
    ngx_event_t                        *rev;
    ngx_connection_t                   *c;

    c = pipe_ctx->c;
    rev = c->read;
    b = &pipe_ctx->buffer;
    read = 0;

    for ( ;; ) {
        size = b->last - b->pos;

        if (size || pipe_ctx->eof) {
            rc = pipe_ctx->input_filter(pipe_ctx->input_filter_ctx, size);
            if (rc == NGX_ERROR) {
                return NGX_ERROR;
            }

            if (rc == NGX_OK) {
                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                               "lua pipe read done pipe:%p", pipe_ctx);
                return NGX_OK;
            }

            /* rc == NGX_AGAIN */
            continue;
        }

        if (read && !rev->ready) {
            break;
        }

        size = b->end - b->last;

        if (size == 0) {
            rc = ngx_http_lua_pipe_add_input_buffer(pipe, pipe_ctx);
            if (rc == NGX_ERROR) {
                return NGX_ERROR;
            }

            b = &pipe_ctx->buffer;
            size = (size_t) (b->end - b->last);
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe try to read data %uz pipe:%p",
                       size, pipe_ctx);

        n = c->recv(c, b->last, size);
        read = 1;

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe read data returned %z pipe:%p", n, pipe_ctx);

        if (n == NGX_AGAIN) {
            break;
        }

        if (n == 0) {
            pipe_ctx->eof = 1;
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                           "lua pipe closed pipe:%p", pipe_ctx);
            continue;
        }

        if (n == NGX_ERROR) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, ngx_errno,
                           "lua pipe read data error pipe:%p", pipe_ctx);

            pipe_ctx->err_type = PIPE_ERR_SYSCALL;
            pipe_ctx->pipe_errno = ngx_errno;
            return NGX_ERROR;
        }

        b->last += n;
    }

    return NGX_AGAIN;
}


static ngx_int_t
ngx_http_lua_pipe_init_ctx(ngx_http_lua_pipe_ctx_t **pipe_ctx_pt, int fd,
    ngx_pool_t *pool, u_char *errbuf, size_t *errbuf_size)
{
    ngx_connection_t                   *c;

    if (fd == -1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        return NGX_ERROR;
    }

    *pipe_ctx_pt = ngx_pcalloc(pool, sizeof(ngx_http_lua_pipe_ctx_t));
    if (*pipe_ctx_pt == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "no memory")
                       - errbuf;
        return NGX_ERROR;
    }

    c = ngx_get_connection(fd, ngx_cycle->log);
    if (c == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "no connection")
                       - errbuf;
        return NGX_ERROR;
    }

    c->log = ngx_cycle->log;
    c->recv = ngx_http_lua_pipe_fd_read;
    c->read->handler = ngx_http_lua_pipe_dummy_event_handler;
    c->read->log = c->log;

#ifdef HAVE_SOCKET_CLOEXEC_PATCH
    c->read->skip_socket_leak_check = 1;
#endif

    c->send = ngx_http_lua_pipe_fd_write;
    c->write->handler = ngx_http_lua_pipe_dummy_event_handler;
    c->write->log = c->log;
    (*pipe_ctx_pt)->c = c;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe init pipe ctx:%p fd:*%d", *pipe_ctx_pt, fd);

    return NGX_OK;
}


int
ngx_http_lua_ffi_pipe_proc_read(ngx_http_request_t *r,
    ngx_http_lua_ffi_pipe_proc_t *proc, int from_stderr, int reader_type,
    size_t length, u_char **buf, size_t *buf_size, u_char *errbuf,
    size_t *errbuf_size)
{
    int                                 rc;
    ngx_msec_t                          timeout;
    ngx_event_t                        *rev;
    ngx_connection_t                   *c;
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_lua_pipe_t                *pipe;
    ngx_http_lua_co_ctx_t              *wait_co_ctx;
    ngx_http_lua_pipe_ctx_t            *pipe_ctx;

    rc = ngx_http_lua_pipe_get_lua_ctx(r, &ctx, errbuf, errbuf_size);
    if (rc != NGX_OK) {
        return rc;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua pipe read process:%p pid:%P", proc, proc->_pid);

    pipe = proc->pipe;
    if (pipe == NULL || pipe->closed) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        return NGX_ERROR;
    }

    if (pipe->merge_stderr && from_stderr) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "merged to stdout")
                       - errbuf;
        return NGX_ERROR;
    }

    if (from_stderr) {
        if (pipe->stderr_ctx == NULL) {
            if (ngx_http_lua_pipe_init_ctx(&pipe->stderr_ctx, pipe->stderr_fd,
                                           pipe->pool, errbuf,
                                           errbuf_size)
                != NGX_OK)
            {
                return NGX_ERROR;
            }

        } else {
            pipe->stderr_ctx->err_type = 0;
        }

        pipe_ctx = pipe->stderr_ctx;

    } else {
        if (pipe->stdout_ctx == NULL) {
            if (ngx_http_lua_pipe_init_ctx(&pipe->stdout_ctx, pipe->stdout_fd,
                                           pipe->pool, errbuf,
                                           errbuf_size)
                != NGX_OK)
            {
                return NGX_ERROR;
            }

        } else {
            pipe->stdout_ctx->err_type = 0;
        }

        pipe_ctx = pipe->stdout_ctx;
    }

    c = pipe_ctx->c;
    if (c == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        return NGX_ERROR;
    }

    rev = c->read;
    if (rev->handler != ngx_http_lua_pipe_dummy_event_handler) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "pipe busy reading")
                       - errbuf;
        return NGX_ERROR;
    }

    pipe_ctx->input_filter_ctx = pipe_ctx;

    switch (reader_type) {

    case PIPE_READ_ALL:
        pipe_ctx->input_filter = ngx_http_lua_pipe_read_all;
        break;

    case PIPE_READ_BYTES:
        pipe_ctx->input_filter = ngx_http_lua_pipe_read_bytes;
        break;

    case PIPE_READ_LINE:
        pipe_ctx->input_filter = ngx_http_lua_pipe_read_line;
        break;

    case PIPE_READ_ANY:
        pipe_ctx->input_filter = ngx_http_lua_pipe_read_any;
        break;

    default:
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "unexpected reader_type: %d", reader_type);
        ngx_http_lua_assert(NULL);
    }

    pipe_ctx->rest = length;

    if (pipe_ctx->bufs_in == NULL) {
        pipe_ctx->bufs_in =
            ngx_http_lua_chain_get_free_buf(ngx_cycle->log, pipe->pool,
                                            &pipe->free_bufs,
                                            pipe->buffer_size);

        if (pipe_ctx->bufs_in == NULL) {
            pipe_ctx->err_type = PIPE_ERR_NOMEM;
            goto error;
        }

        pipe_ctx->buf_in = pipe_ctx->bufs_in;
        pipe_ctx->buffer = *pipe_ctx->buf_in->buf;
    }

    rc = ngx_http_lua_pipe_read(pipe, pipe_ctx);
    if (rc == NGX_ERROR) {
        goto error;
    }

    if (rc == NGX_OK) {
        ngx_http_lua_pipe_put_data(pipe, pipe_ctx, buf, buf_size);
        return NGX_OK;
    }

    /* rc == NGX_AGAIN */
    wait_co_ctx = ctx->cur_co_ctx;

    c->data = wait_co_ctx;
    if (ngx_handle_read_event(rev, 0) != NGX_OK) {
        pipe_ctx->err_type = PIPE_ERR_ADD_READ_EV;
        goto error;
    }

    wait_co_ctx->data = proc;

    if (from_stderr) {
        rev->handler = ngx_http_lua_pipe_resume_read_stderr_handler;
        wait_co_ctx->cleanup = ngx_http_lua_pipe_proc_read_stderr_cleanup;
        timeout = proc->stderr_read_timeout;

    } else {
        rev->handler = ngx_http_lua_pipe_resume_read_stdout_handler;
        wait_co_ctx->cleanup = ngx_http_lua_pipe_proc_read_stdout_cleanup;
        timeout = proc->stdout_read_timeout;
    }

    if (timeout > 0) {
        ngx_add_timer(rev, timeout);
        ngx_log_debug5(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua pipe add timer for reading: %d(ms) process:%p "
                       "pid:%P pipe:%p ev:%p", timeout, proc, proc->_pid, pipe,
                       rev);
    }

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua pipe read yielding process:%p pid:%P pipe:%p", proc,
                   proc->_pid, pipe);

    return NGX_AGAIN;

error:

    if (pipe_ctx->bufs_in) {
        ngx_http_lua_pipe_put_data(pipe, pipe_ctx, buf, buf_size);
        ngx_http_lua_pipe_put_error(pipe_ctx, errbuf, errbuf_size);
        return NGX_DECLINED;
    }

    ngx_http_lua_pipe_put_error(pipe_ctx, errbuf, errbuf_size);

    return NGX_ERROR;
}


/*
 * ngx_http_lua_ffi_pipe_get_read_result should only be called just after
 * ngx_http_lua_ffi_pipe_proc_read, so we omit most of the sanity check already
 * done in ngx_http_lua_ffi_pipe_proc_read.
 */
int
ngx_http_lua_ffi_pipe_get_read_result(ngx_http_request_t *r,
    ngx_http_lua_ffi_pipe_proc_t *proc, int from_stderr, u_char **buf,
    size_t *buf_size, u_char *errbuf, size_t *errbuf_size)
{
    ngx_http_lua_pipe_t                *pipe;
    ngx_http_lua_pipe_ctx_t            *pipe_ctx;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua pipe get read result process:%p pid:%P", proc,
                   proc->_pid);

    pipe = proc->pipe;
    pipe_ctx = from_stderr ? pipe->stderr_ctx : pipe->stdout_ctx;

    if (!pipe_ctx->err_type) {
        ngx_http_lua_pipe_put_data(pipe, pipe_ctx, buf, buf_size);
        return NGX_OK;
    }

    if (pipe_ctx->bufs_in) {
        ngx_http_lua_pipe_put_data(pipe, pipe_ctx, buf, buf_size);
        ngx_http_lua_pipe_put_error(pipe_ctx, errbuf, errbuf_size);
        return NGX_DECLINED;
    }

    ngx_http_lua_pipe_put_error(pipe_ctx, errbuf, errbuf_size);

    return NGX_ERROR;
}


static ngx_int_t
ngx_http_lua_pipe_write(ngx_http_lua_pipe_t *pipe,
    ngx_http_lua_pipe_ctx_t *pipe_ctx)
{
    size_t                       size;
    ngx_int_t                    n;
    ngx_buf_t                   *b;
    ngx_connection_t            *c;

    c = pipe_ctx->c;
    b = pipe_ctx->buf_in->buf;

    for ( ;; ) {
        size = b->last - b->pos;
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe try to write data %uz pipe:%p", size,
                       pipe_ctx);

        n = c->send(c, b->pos, size);
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe write returned %i pipe:%p", n, pipe_ctx);

        if (n >= 0) {
            b->pos += n;

            if (b->pos == b->last) {
                b->pos = b->start;
                b->last = b->start;

                if (!pipe->free_bufs) {
                    pipe->free_bufs = pipe_ctx->buf_in;

                } else {
                    pipe->free_bufs->next = pipe_ctx->buf_in;
                }

                ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                               "lua pipe write done pipe:%p", pipe_ctx);
                return NGX_OK;
            }

            continue;
        }

        /* NGX_ERROR || NGX_AGAIN */
        break;
    }

    if (n == NGX_ERROR) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, ngx_errno,
                       "lua pipe write data error pipe:%p", pipe_ctx);

        if (ngx_errno == NGX_EPIPE) {
            pipe_ctx->err_type = PIPE_ERR_CLOSED;

        } else {
            pipe_ctx->err_type = PIPE_ERR_SYSCALL;
            pipe_ctx->pipe_errno = ngx_errno;
        }

        return NGX_ERROR;
    }

    return NGX_AGAIN;
}


ssize_t
ngx_http_lua_ffi_pipe_proc_write(ngx_http_request_t *r,
    ngx_http_lua_ffi_pipe_proc_t *proc, const u_char *data, size_t len,
    u_char *errbuf, size_t *errbuf_size)
{
    int                                 rc;
    ngx_buf_t                          *b;
    ngx_msec_t                          timeout;
    ngx_chain_t                        *cl;
    ngx_event_t                        *wev;
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_lua_pipe_t                *pipe;
    ngx_http_lua_co_ctx_t              *wait_co_ctx;
    ngx_http_lua_pipe_ctx_t            *pipe_ctx;

    rc = ngx_http_lua_pipe_get_lua_ctx(r, &ctx, errbuf, errbuf_size);
    if (rc != NGX_OK) {
        return rc;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua pipe write process:%p pid:%P", proc, proc->_pid);

    pipe = proc->pipe;
    if (pipe == NULL || pipe->closed) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        return NGX_ERROR;
    }

    if (pipe->stdin_ctx == NULL) {
        if (ngx_http_lua_pipe_init_ctx(&pipe->stdin_ctx, pipe->stdin_fd,
                                       pipe->pool, errbuf,
                                       errbuf_size)
            != NGX_OK)
        {
            return NGX_ERROR;
        }

    } else {
        pipe->stdin_ctx->err_type = 0;
    }

    pipe_ctx = pipe->stdin_ctx;
    if (pipe_ctx->c == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "closed") - errbuf;
        return NGX_ERROR;
    }

    wev = pipe_ctx->c->write;
    if (wev->handler != ngx_http_lua_pipe_dummy_event_handler) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "pipe busy writing")
                       - errbuf;
        return NGX_ERROR;
    }

    pipe_ctx->rest = len;

    cl = ngx_http_lua_chain_get_free_buf(ngx_cycle->log, pipe->pool,
                                         &pipe->free_bufs, len);
    if (cl == NULL) {
        pipe_ctx->err_type = PIPE_ERR_NOMEM;
        goto error;
    }

    pipe_ctx->buf_in = cl;
    b = pipe_ctx->buf_in->buf;
    b->last = ngx_copy(b->last, data, len);

    rc = ngx_http_lua_pipe_write(pipe, pipe_ctx);
    if (rc == NGX_ERROR) {
        goto error;
    }

    if (rc == NGX_OK) {
        return len;
    }

    /* rc == NGX_AGAIN */
    wait_co_ctx = ctx->cur_co_ctx;
    pipe_ctx->c->data = wait_co_ctx;

    wev->handler = ngx_http_lua_pipe_resume_write_handler;
    if (ngx_handle_write_event(wev, 0) != NGX_OK) {
        pipe_ctx->err_type = PIPE_ERR_ADD_WRITE_EV;
        goto error;
    }

    wait_co_ctx->data = proc;
    wait_co_ctx->cleanup = ngx_http_lua_pipe_proc_write_cleanup;
    timeout = proc->write_timeout;

    if (timeout > 0) {
        ngx_add_timer(wev, timeout);
        ngx_log_debug5(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua pipe add timer for writing: %d(ms) process:%p "
                       "pid:%P pipe:%p ev:%p", timeout, proc, proc->_pid, pipe,
                       wev);
    }

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua pipe write yielding process:%p pid:%P pipe:%p", proc,
                   proc->_pid, pipe);

    return NGX_AGAIN;

error:

    ngx_http_lua_pipe_put_error(pipe_ctx, errbuf, errbuf_size);
    return NGX_ERROR;
}


/*
 * ngx_http_lua_ffi_pipe_get_write_result should only be called just after
 * ngx_http_lua_ffi_pipe_proc_write, so we omit most of the sanity check
 * already done in ngx_http_lua_ffi_pipe_proc_write.
 */
ssize_t
ngx_http_lua_ffi_pipe_get_write_result(ngx_http_request_t *r,
    ngx_http_lua_ffi_pipe_proc_t *proc, u_char *errbuf, size_t *errbuf_size)
{
    ngx_http_lua_pipe_t                *pipe;
    ngx_http_lua_pipe_ctx_t            *pipe_ctx;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua pipe get write result process:%p pid:%P", proc,
                   proc->_pid);

    pipe = proc->pipe;
    pipe_ctx = pipe->stdin_ctx;

    if (pipe_ctx->err_type) {
        ngx_http_lua_pipe_put_error(pipe_ctx, errbuf, errbuf_size);
        return NGX_ERROR;
    }

    return pipe_ctx->rest;
}


int
ngx_http_lua_ffi_pipe_proc_wait(ngx_http_request_t *r,
    ngx_http_lua_ffi_pipe_proc_t *proc, char **reason, int *status,
    u_char *errbuf, size_t *errbuf_size)
{
    int                                 rc;
    ngx_rbtree_node_t                  *node;
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_lua_pipe_t                *pipe;
    ngx_http_lua_co_ctx_t              *wait_co_ctx;
    ngx_http_lua_pipe_node_t           *pipe_node;

    rc = ngx_http_lua_pipe_get_lua_ctx(r, &ctx, errbuf, errbuf_size);
    if (rc != NGX_OK) {
        return rc;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua pipe wait process:%p pid:%P", proc, proc->_pid);

    pipe = proc->pipe;
    if (pipe == NULL || pipe->closed) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "exited") - errbuf;
        return NGX_ERROR;
    }

    node = pipe->node;
    pipe_node = (ngx_http_lua_pipe_node_t *) &node->color;
    if (pipe_node->wait_co_ctx) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "pipe busy waiting")
                       - errbuf;
        return NGX_ERROR;
    }

    if (pipe_node->reason_code == REASON_RUNNING_CODE) {
        wait_co_ctx = ctx->cur_co_ctx;
        wait_co_ctx->data = proc;
        ngx_memzero(&wait_co_ctx->sleep, sizeof(ngx_event_t));
        wait_co_ctx->sleep.handler = ngx_http_lua_pipe_resume_wait_handler;
        wait_co_ctx->sleep.data = wait_co_ctx;
        wait_co_ctx->sleep.log = r->connection->log;
        wait_co_ctx->cleanup = ngx_http_lua_pipe_proc_wait_cleanup;

        pipe_node->wait_co_ctx = wait_co_ctx;

        if (proc->wait_timeout > 0) {
            ngx_add_timer(&wait_co_ctx->sleep, proc->wait_timeout);
            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua pipe add timer for waiting: %d(ms) process:%p "
                           "pid:%P ev:%p", proc->wait_timeout, proc,
                           proc->_pid, &wait_co_ctx->sleep);
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua pipe wait yielding process:%p pid:%P", proc,
                       proc->_pid);

        return NGX_AGAIN;
    }

    *status = pipe_node->status;

    switch (pipe_node->reason_code) {

    case REASON_EXIT_CODE:
        *reason = REASON_EXIT;
        break;

    case REASON_SIGNAL_CODE:
        *reason = REASON_SIGNAL;
        break;

    default:
        *reason = REASON_UNKNOWN;
    }

    ngx_http_lua_pipe_proc_finalize(proc);

    if (*status == 0) {
        return NGX_OK;
    }

    return NGX_DECLINED;
}


int
ngx_http_lua_ffi_pipe_proc_kill(ngx_http_lua_ffi_pipe_proc_t *proc, int signal,
    u_char *errbuf, size_t *errbuf_size)
{
    ngx_pid_t                           pid;
    ngx_http_lua_pipe_t                *pipe;

    pipe = proc->pipe;

    if (pipe == NULL || pipe->dead) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "exited") - errbuf;
        return NGX_ERROR;
    }

    pid = proc->_pid;

    if (kill(pid, signal) == -1) {
        switch (ngx_errno) {
        case EINVAL:
            *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "invalid signal")
                           - errbuf;
            break;

        case ESRCH:
            *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "exited")
                           - errbuf;
            break;

        default:
            *errbuf_size = ngx_snprintf(errbuf, *errbuf_size, "%s",
                                        strerror(ngx_errno))
                           - errbuf;
        }

        return NGX_ERROR;
    }

    return NGX_OK;
}


static int
ngx_http_lua_pipe_read_stdout_retval(ngx_http_lua_ffi_pipe_proc_t *proc,
    lua_State *L)
{
    return ngx_http_lua_pipe_read_retval_helper(proc, L, 0);
}


static int
ngx_http_lua_pipe_read_stderr_retval(ngx_http_lua_ffi_pipe_proc_t *proc,
    lua_State *L)
{
    return ngx_http_lua_pipe_read_retval_helper(proc, L, 1);
}


static int
ngx_http_lua_pipe_read_retval_helper(ngx_http_lua_ffi_pipe_proc_t *proc,
    lua_State *L, int from_stderr)
{
    int                              rc;
    ngx_msec_t                       timeout;
    ngx_event_t                     *rev;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_pipe_ctx_t         *pipe_ctx;

    pipe = proc->pipe;
    if (from_stderr) {
        pipe_ctx = pipe->stderr_ctx;

    } else {
        pipe_ctx = pipe->stdout_ctx;
    }

    if (pipe->timeout) {
        pipe->timeout = 0;
        pipe_ctx->err_type = PIPE_ERR_TIMEOUT;
        return 0;
    }

    if (pipe_ctx->err_type == PIPE_ERR_ABORTED) {
        ngx_close_connection(pipe_ctx->c);
        pipe_ctx->c = NULL;
        return 0;
    }

    rc = ngx_http_lua_pipe_read(pipe, pipe_ctx);
    if (rc != NGX_AGAIN) {
        return 0;
    }

    rev = pipe_ctx->c->read;

    if (from_stderr) {
        rev->handler = ngx_http_lua_pipe_resume_read_stderr_handler;
        timeout = proc->stderr_read_timeout;

    } else {
        rev->handler = ngx_http_lua_pipe_resume_read_stdout_handler;
        timeout = proc->stdout_read_timeout;
    }

    if (timeout > 0) {
        ngx_add_timer(rev, timeout);
        ngx_log_debug5(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe add timer for reading: %d(ms) proc:%p "
                       "pid:%P pipe:%p ev:%p", timeout, proc, proc->_pid, pipe,
                       rev);
    }

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe read yielding process:%p pid:%P pipe:%p", proc,
                   proc->_pid, pipe);

    return NGX_AGAIN;
}


static int
ngx_http_lua_pipe_write_retval(ngx_http_lua_ffi_pipe_proc_t *proc,
    lua_State *L)
{
    int                              rc;
    ngx_msec_t                       timeout;
    ngx_event_t                     *wev;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_pipe_ctx_t         *pipe_ctx;

    pipe = proc->pipe;
    pipe_ctx = pipe->stdin_ctx;

    if (pipe->timeout) {
        pipe->timeout = 0;
        pipe_ctx->err_type = PIPE_ERR_TIMEOUT;
        return 0;
    }

    if (pipe_ctx->err_type == PIPE_ERR_ABORTED) {
        ngx_close_connection(pipe_ctx->c);
        pipe_ctx->c = NULL;
        return 0;
    }

    rc = ngx_http_lua_pipe_write(pipe, pipe_ctx);
    if (rc != NGX_AGAIN) {
        return 0;
    }

    wev = pipe_ctx->c->write;
    wev->handler = ngx_http_lua_pipe_resume_write_handler;
    timeout = proc->write_timeout;

    if (timeout > 0) {
        ngx_add_timer(wev, timeout);
        ngx_log_debug5(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua pipe add timer for writing: %d(ms) proc:%p "
                       "pid:%P pipe:%p ev:%p", timeout, proc, proc->_pid, pipe,
                       wev);
    }

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe write yielding process:%p pid:%P pipe:%p", proc,
                   proc->_pid, pipe);

    return NGX_AGAIN;
}


static int
ngx_http_lua_pipe_wait_retval(ngx_http_lua_ffi_pipe_proc_t *proc, lua_State *L)
{
    int                              nret;
    ngx_rbtree_node_t               *node;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_pipe_node_t        *pipe_node;

    pipe = proc->pipe;
    node = pipe->node;
    pipe_node = (ngx_http_lua_pipe_node_t *) &node->color;
    pipe_node->wait_co_ctx = NULL;

    if (pipe->timeout) {
        pipe->timeout = 0;
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        return 2;
    }

    ngx_http_lua_pipe_proc_finalize(pipe_node->proc);

    if (pipe_node->status == 0) {
        lua_pushboolean(L, 1);
        lua_pushliteral(L, REASON_EXIT);
        lua_pushinteger(L, pipe_node->status);
        nret = 3;

    } else {
        lua_pushboolean(L, 0);

        switch (pipe_node->reason_code) {

        case REASON_EXIT_CODE:
            lua_pushliteral(L, REASON_EXIT);
            break;

        case REASON_SIGNAL_CODE:
            lua_pushliteral(L, REASON_SIGNAL);
            break;

        default:
            lua_pushliteral(L, REASON_UNKNOWN);
        }

        lua_pushinteger(L, pipe_node->status);
        nret = 3;
    }

    return nret;
}


static void
ngx_http_lua_pipe_resume_helper(ngx_event_t *ev,
    ngx_http_lua_co_ctx_t *wait_co_ctx)
{
    ngx_connection_t                *c;
    ngx_http_request_t              *r;
    ngx_http_lua_ctx_t              *ctx;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_ffi_pipe_proc_t    *proc;

    if (ev->timedout) {
        proc = wait_co_ctx->data;
        pipe = proc->pipe;
        pipe->timeout = 1;
        ev->timedout = 0;
    }

    ngx_http_lua_pipe_clear_event(ev);

    r = ngx_http_lua_get_req(wait_co_ctx->co);
    c = r->connection;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    ngx_http_lua_assert(ctx != NULL);

    ctx->cur_co_ctx = wait_co_ctx;

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_pipe_resume(r);

    } else {
        ctx->resume_handler = ngx_http_lua_pipe_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
}


static void
ngx_http_lua_pipe_resume_read_stdout_handler(ngx_event_t *ev)
{
    ngx_connection_t                *c = ev->data;
    ngx_http_lua_co_ctx_t           *wait_co_ctx;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_ffi_pipe_proc_t    *proc;

    wait_co_ctx = c->data;
    proc = wait_co_ctx->data;
    pipe = proc->pipe;
    pipe->retval_handler = ngx_http_lua_pipe_read_stdout_retval;
    ngx_http_lua_pipe_resume_helper(ev, wait_co_ctx);
}


static void
ngx_http_lua_pipe_resume_read_stderr_handler(ngx_event_t *ev)
{
    ngx_connection_t                *c = ev->data;
    ngx_http_lua_co_ctx_t           *wait_co_ctx;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_ffi_pipe_proc_t    *proc;

    wait_co_ctx = c->data;
    proc = wait_co_ctx->data;
    pipe = proc->pipe;
    pipe->retval_handler = ngx_http_lua_pipe_read_stderr_retval;
    ngx_http_lua_pipe_resume_helper(ev, wait_co_ctx);
}


static void
ngx_http_lua_pipe_resume_write_handler(ngx_event_t *ev)
{
    ngx_connection_t                *c = ev->data;
    ngx_http_lua_co_ctx_t           *wait_co_ctx;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_ffi_pipe_proc_t    *proc;

    wait_co_ctx = c->data;
    proc = wait_co_ctx->data;
    pipe = proc->pipe;
    pipe->retval_handler = ngx_http_lua_pipe_write_retval;
    ngx_http_lua_pipe_resume_helper(ev, wait_co_ctx);
}


static void
ngx_http_lua_pipe_resume_wait_handler(ngx_event_t *ev)
{
    ngx_http_lua_co_ctx_t           *wait_co_ctx = ev->data;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_ffi_pipe_proc_t    *proc;

    proc = wait_co_ctx->data;
    pipe = proc->pipe;
    pipe->retval_handler = ngx_http_lua_pipe_wait_retval;
    ngx_http_lua_pipe_resume_helper(ev, wait_co_ctx);
}


static ngx_int_t
ngx_http_lua_pipe_resume(ngx_http_request_t *r)
{
    int                              nret;
    lua_State                       *vm;
    ngx_int_t                        rc;
    ngx_uint_t                       nreqs;
    ngx_connection_t                *c;
    ngx_http_lua_ctx_t              *ctx;
    ngx_http_lua_pipe_t             *pipe;
    ngx_http_lua_ffi_pipe_proc_t    *proc;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;
    ctx->cur_co_ctx->cleanup = NULL;

    proc = ctx->cur_co_ctx->data;
    pipe = proc->pipe;
    nret = pipe->retval_handler(proc, ctx->cur_co_ctx->co);
    if (nret == NGX_AGAIN) {
        return NGX_DONE;
    }

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(vm, r, ctx, nret);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    /* rc == NGX_ERROR || rc >= NGX_OK */

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static void
ngx_http_lua_pipe_dummy_event_handler(ngx_event_t *ev)
{
    /* do nothing */
}


static void
ngx_http_lua_pipe_clear_event(ngx_event_t *ev)
{
    ev->handler = ngx_http_lua_pipe_dummy_event_handler;

    if (ev->timer_set) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                       "lua pipe del timer for ev:%p", ev);
        ngx_del_timer(ev);
    }

    if (ev->posted) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                       "lua pipe del posted event for ev:%p", ev);
        ngx_delete_posted_event(ev);
    }
}


static void
ngx_http_lua_pipe_proc_read_stdout_cleanup(void *data)
{
    ngx_event_t                    *rev;
    ngx_connection_t               *c;
    ngx_http_lua_co_ctx_t          *wait_co_ctx = data;
    ngx_http_lua_ffi_pipe_proc_t   *proc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe proc read stdout cleanup");

    proc = wait_co_ctx->data;
    c = proc->pipe->stdout_ctx->c;
    if (c) {
        rev = c->read;
        ngx_http_lua_pipe_clear_event(rev);
    }

    wait_co_ctx->cleanup = NULL;
}


static void
ngx_http_lua_pipe_proc_read_stderr_cleanup(void *data)
{
    ngx_event_t                    *rev;
    ngx_connection_t               *c;
    ngx_http_lua_co_ctx_t          *wait_co_ctx = data;
    ngx_http_lua_ffi_pipe_proc_t   *proc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe proc read stderr cleanup");

    proc = wait_co_ctx->data;
    c = proc->pipe->stderr_ctx->c;
    if (c) {
        rev = c->read;
        ngx_http_lua_pipe_clear_event(rev);
    }

    wait_co_ctx->cleanup = NULL;
}


static void
ngx_http_lua_pipe_proc_write_cleanup(void *data)
{
    ngx_event_t                    *wev;
    ngx_connection_t               *c;
    ngx_http_lua_co_ctx_t          *wait_co_ctx = data;
    ngx_http_lua_ffi_pipe_proc_t   *proc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe proc write cleanup");

    proc = wait_co_ctx->data;
    c = proc->pipe->stdin_ctx->c;
    if (c) {
        wev = c->write;
        ngx_http_lua_pipe_clear_event(wev);
    }

    wait_co_ctx->cleanup = NULL;
}


static void
ngx_http_lua_pipe_proc_wait_cleanup(void *data)
{
    ngx_rbtree_node_t              *node;
    ngx_http_lua_co_ctx_t          *wait_co_ctx = data;
    ngx_http_lua_pipe_node_t       *pipe_node;
    ngx_http_lua_ffi_pipe_proc_t   *proc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua pipe proc wait cleanup");

    proc = wait_co_ctx->data;
    node = proc->pipe->node;
    pipe_node = (ngx_http_lua_pipe_node_t *) &node->color;
    pipe_node->wait_co_ctx = NULL;

    ngx_http_lua_pipe_clear_event(&wait_co_ctx->sleep);

    wait_co_ctx->cleanup = NULL;
}


#endif /* HAVE_NGX_LUA_PIPE */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
