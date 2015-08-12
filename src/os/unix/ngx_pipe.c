
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_channel.h>


#if !(NGX_WIN32)

static ngx_uint_t       ngx_pipe_generation;
static ngx_uint_t       ngx_last_pipe;
static ngx_open_pipe_t  ngx_pipes[NGX_MAX_PROCESSES];


static void ngx_signal_pipe_broken(ngx_log_t *log, ngx_pid_t pid);
static ngx_int_t ngx_open_pipe(ngx_cycle_t *cycle, ngx_open_pipe_t *op);
static void ngx_close_pipe(ngx_open_pipe_t *pipe);


ngx_str_t ngx_log_error_backup = ngx_string(NGX_ERROR_LOG_PATH);
ngx_str_t ngx_log_access_backup = ngx_string(NGX_HTTP_LOG_PATH);


ngx_open_pipe_t *
ngx_conf_open_pipe(ngx_cycle_t *cycle, ngx_str_t *cmd, const char *type)
{
    u_char           *cp, *ct, *dup, **argi, **c1, **c2;
    ngx_int_t         same, ti, use;
    ngx_uint_t        i, j, numargs = 0;
    ngx_array_t      *argv_out;

    dup = ngx_pnalloc(cycle->pool, cmd->len + 1);
    (void) ngx_cpystrn(dup, cmd->data, cmd->len + 1);

    for (cp = cmd->data; *cp == ' ' || *cp == '\t'; cp++);
    ct = cp;

    if (ngx_strcmp(type, "r") == 0) {
        ti = NGX_PIPE_READ;
    } else if (ngx_strcmp(type, "w") == 0) {
        ti = NGX_PIPE_WRITE;
    } else {
        return NULL;
    }

    numargs = 1;
    while (*ct != '\0') {
        for ( /* void */ ; *ct != '\0'; ct++) {
            if (*ct == ' ' || *ct == '\t') {
                break;
            }
        }

        if (*ct != '\0') {
            ct++;
        }

        numargs++;

        for ( /* void */ ; *ct == ' ' || *ct == '\t'; ct++);
    }

    argv_out = ngx_array_create(cycle->pool, numargs, sizeof(u_char *));
    if (argv_out == NULL) {
        return NULL;
    }

    for (i = 0; i < (numargs - 1); i++) {
        for ( /* void */ ; *cp == ' ' || *cp == '\t'; cp++);

        for (ct = cp; *cp != '\0'; cp++) {
            if (*cp == ' ' || *cp == '\t') {
                break;
            }
        }

        *cp = '\0';
        argi = (u_char **) ngx_array_push(argv_out);
        *argi = ct;
        cp++;
    }

    argi = (u_char **) ngx_array_push(argv_out);
    *argi = NULL;

    for (i = 0, use = -1; i < ngx_last_pipe; i++) {

        if (!ngx_pipes[i].configured) {
            if (use == -1) {
                use = i;
            }
            continue;
        }

        if (ngx_pipes[i].generation != ngx_pipe_generation) {
            continue;
        }

        if (argv_out->nelts != ngx_pipes[i].argv->nelts) {
            continue;
        }

        if (ti != ngx_pipes[i].type) {
            continue;
        }

        same = 1;
        c1 = argv_out->elts;
        c2 = ngx_pipes[i].argv->elts;
        for (j = 0; j < argv_out->nelts - 1; j++) {
            if (ngx_strcmp(c1[j], c2[j]) != 0) {
                same = 0;
                break;
            }
        }
        if (same) {
            return &ngx_pipes[i];
        }
    }

    if (use == -1) {
        if (ngx_last_pipe < NGX_MAX_PROCESSES) {
            use = ngx_last_pipe++;
        } else {
            return NULL;
        }
    }

    ngx_memzero(&ngx_pipes[use], sizeof(ngx_open_pipe_t));

    ngx_pipes[use].open_fd = ngx_list_push(&cycle->open_files);
    if (ngx_pipes[use].open_fd == NULL) {
        return NULL;
    }

    ngx_memzero(ngx_pipes[use].open_fd, sizeof(ngx_open_file_t));
    ngx_pipes[use].open_fd->fd = NGX_INVALID_FILE;

    ngx_pipes[use].pid = -1;
    ngx_pipes[use].cmd = dup;
    ngx_pipes[use].argv = argv_out;
    ngx_pipes[use].type = ti;
    ngx_pipes[use].generation = ngx_pipe_generation;
    ngx_pipes[use].configured = 1;

    return &ngx_pipes[use];
}


static void
ngx_close_pipe(ngx_open_pipe_t *pipe)
{
    /*
     * No waitpid at this place, because it is called at
     * ngx_process_get_status first.
     */

    if (pipe->pid != -1) {
        kill(pipe->pid, SIGTERM);
    }

    pipe->configured = 0;
}


void
ngx_increase_pipe_generation(void)
{
    ngx_pipe_generation++;
}


ngx_int_t
ngx_open_pipes(ngx_cycle_t *cycle)
{
    ngx_int_t          stat;
    ngx_uint_t         i;
    ngx_core_conf_t   *ccf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);

    for (i = 0; i < ngx_last_pipe; i++) {

        if (!ngx_pipes[i].configured) {
            continue;
        }

        if (ngx_pipes[i].generation != ngx_pipe_generation) {
            continue;
        }

        ngx_pipes[i].backup = ngx_pipes[i].open_fd->name;
        ngx_pipes[i].user = ccf->user;

        stat = ngx_open_pipe(cycle, &ngx_pipes[i]);

        ngx_log_debug4(NGX_LOG_DEBUG_CORE, cycle->log, 0,
                       "pipe: %ui(%d, %d) \"%s\"",
                       i, ngx_pipes[i].pfd[0],
                       ngx_pipes[i].pfd[1], ngx_pipes[i].cmd);

        if (stat == NGX_ERROR) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "open pipe \"%s\" failed",
                          ngx_pipes[i].cmd);
            return NGX_ERROR;
        }

        if (fcntl(ngx_pipes[i].open_fd->fd, F_SETFD, FD_CLOEXEC) == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "fcntl(FD_CLOEXEC) \"%s\" failed",
                          ngx_pipes[i].cmd);
            return NGX_ERROR;
        }

        if (ngx_nonblocking(ngx_pipes[i].open_fd->fd) == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "nonblock \"%s\" failed",
                          ngx_pipes[i].cmd);
            return NGX_ERROR;
        }

        ngx_pipes[i].open_fd->name.len = 0;
        ngx_pipes[i].open_fd->name.data = NULL;
    }

    return NGX_OK;
}


void
ngx_close_old_pipes(void)
{
    ngx_uint_t i, last;

    for (i = 0, last = -1; i < ngx_last_pipe; i++) {

        if (!ngx_pipes[i].configured) {
            continue;
        }

        if (ngx_pipes[i].generation < ngx_pipe_generation) {
            ngx_close_pipe(&ngx_pipes[i]);
        } else {
            last = i;
        }
    }

    ngx_last_pipe = last + 1;
}


void
ngx_close_pipes(void)
{
    ngx_uint_t i, last;

    for (i = 0, last = -1; i < ngx_last_pipe; i++) {

        if (!ngx_pipes[i].configured) {
            continue;
        }

        if (ngx_pipes[i].generation == ngx_pipe_generation) {
            ngx_close_pipe(&ngx_pipes[i]);
        } else {
            last = i;
        }
    }

    ngx_last_pipe = last + 1;
}


void
ngx_pipe_broken_action(ngx_log_t *log, ngx_pid_t pid, ngx_int_t master)
{
    ngx_uint_t i, is_stderr;

    for (i = 0, is_stderr = 0; i < ngx_last_pipe; i++) {

        if (!ngx_pipes[i].configured) {
            continue;
        }

        if (ngx_pipes[i].generation != ngx_pipe_generation) {
            continue;
        }

        if (ngx_pipes[i].pid == pid) {

            if (close(ngx_pipes[i].open_fd->fd) == NGX_FILE_ERROR) {
                ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                              "close \"%s\" failed",
                              ngx_pipes[i].cmd);
            }

            if (ngx_pipes[i].open_fd == ngx_cycle->log->file) {
                is_stderr = 1;
            }

            ngx_pipes[i].open_fd->name.len = ngx_pipes[i].backup.len;
            ngx_pipes[i].open_fd->name.data = ngx_pipes[i].backup.data;

            ngx_pipes[i].open_fd->fd = ngx_open_file(ngx_pipes[i].backup.data,
                                                     NGX_FILE_APPEND,
                                                     NGX_FILE_CREATE_OR_OPEN,
                                                     NGX_FILE_DEFAULT_ACCESS);

            if (ngx_pipes[i].open_fd->fd == NGX_INVALID_FILE) {
                ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                              ngx_open_file_n " \"%s\" failed",
                              ngx_pipes[i].backup.data);
            }

            if (fcntl(ngx_pipes[i].open_fd->fd, F_SETFD, FD_CLOEXEC) == -1) {
                ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                              "fcntl(FD_CLOEXEC) \"%s\" failed",
                              ngx_pipes[i].backup.data);
            }

            if (is_stderr) {
                ngx_set_stderr(ngx_cycle->log->file->fd);
            }

            if (master) {
                if (chown((const char *) ngx_pipes[i].backup.data,
                          ngx_pipes[i].user, -1)
                    == -1)
                {
                    ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                                  "chown() \"%s\" failed",
                                  ngx_pipes[i].backup.data);
                }

                ngx_signal_pipe_broken(log, pid);
            }
        }
    }
}


static void
ngx_signal_pipe_broken(ngx_log_t *log, ngx_pid_t pid)
{
    ngx_int_t      i;
    ngx_channel_t  ch;

    ch.fd = -1;
    ch.pid = pid;
    ch.command = NGX_CMD_PIPE_BROKEN;

    for (i = 0; i < ngx_last_process; i++) {

        if (ngx_processes[i].detached || ngx_processes[i].pid == -1) {
            continue;
        }

        ngx_write_channel(ngx_processes[i].channel[0],
                          &ch, sizeof(ngx_channel_t), log);
    }
}


static ngx_int_t
ngx_open_pipe(ngx_cycle_t *cycle, ngx_open_pipe_t *op)
{
    int               fd;
    u_char          **argv;
    ngx_pid_t         pid;
    sigset_t          set;
    ngx_core_conf_t  *ccf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);

    if (pipe(op->pfd) < 0) {
        return NGX_ERROR;
    }

    argv = op->argv->elts;

    if ((pid = fork()) < 0) {
        goto err;
    } else if (pid > 0) {
        op->pid = pid;

        if (op->open_fd->fd != NGX_INVALID_FILE) {
            if (close(op->open_fd->fd) == NGX_FILE_ERROR) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                              "close \"%s\" failed",
                              op->open_fd->name.data);
            }
        }

        if (op->type == NGX_PIPE_WRITE) {
            op->open_fd->fd = op->pfd[1];
            close(op->pfd[0]);
        } else {
            op->open_fd->fd = op->pfd[0];
            close(op->pfd[1]);
        }
    } else {
        if (op->type == 1) {
            close(op->pfd[1]);
            if (op->pfd[0] != STDIN_FILENO) {
                dup2(op->pfd[0], STDIN_FILENO);
                close(op->pfd[0]);
            }
        } else {
            close(op->pfd[0]);
            if (op->pfd[1] != STDOUT_FILENO) {
                dup2(op->pfd[1], STDOUT_FILENO);
                close(op->pfd[1]);
            }
        }

        if (geteuid() == 0) {
            if (setgid(ccf->group) == -1) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                              "setgid(%d) failed", ccf->group);
                exit(2);
            }

            if (initgroups(ccf->username, ccf->group) == -1) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                              "initgroups(%s, %d) failed",
                              ccf->username, ccf->group);
            }

            if (setuid(ccf->user) == -1) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                              "setuid(%d) failed", ccf->user);
                exit(2);
            }
        }

        /*
         * redirect stderr to /dev/null, because stderr will be connected with
         * fd used by the last pipe when error log is configured using pipe,
         * that will cause it no close
         */

        fd = open("/dev/null", O_WRONLY);
        if (fd == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "open(\"/dev/null\") failed");
            exit(2);
        }

        if (dup2(fd, STDERR_FILENO) == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "dup2(STDERR) failed");
            exit(2);
        }

        if (fd > STDERR_FILENO && close(fd) == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "close() failed");
            exit(2);
        }

        sigemptyset(&set);

        if (sigprocmask(SIG_SETMASK, &set, NULL) == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "sigprocmask() failed");
            exit(2);
        }

        execv((const char *) argv[0], (char *const *) op->argv->elts);
        exit(0);
    }

    return NGX_OK;

err:

    close(op->pfd[0]);
    close(op->pfd[1]);

    return NGX_ERROR;
}

#endif

