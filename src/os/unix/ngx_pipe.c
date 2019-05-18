
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

#define MAX_BACKUP_NUM          128
#define NGX_PIPE_DIR_ACCESS     S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH
#define NGX_PIPE_FILE_ACCESS    S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH

typedef struct {
    ngx_int_t       time_now;
    ngx_int_t       last_open_time;
    ngx_int_t       log_size;
    ngx_int_t       last_suit_time;

    char           *logname;
    char           *backup[MAX_BACKUP_NUM];

    ngx_int_t       backup_num;
    ngx_int_t       log_max_size;
    ngx_int_t       interval;
    char           *suitpath;
    ngx_int_t       adjust_time;
    ngx_int_t       adjust_time_raw;
} ngx_pipe_rollback_conf_t;

static void ngx_signal_pipe_broken(ngx_log_t *log, ngx_pid_t pid);
static ngx_int_t ngx_open_pipe(ngx_cycle_t *cycle, ngx_open_pipe_t *op);
static void ngx_close_pipe(ngx_open_pipe_t *pipe);

static void ngx_pipe_log(ngx_cycle_t *cycle, ngx_open_pipe_t *op);
void ngx_pipe_get_last_rollback_time(ngx_pipe_rollback_conf_t *rbcf);
static void ngx_pipe_do_rollback(ngx_cycle_t *cycle, ngx_pipe_rollback_conf_t *rbcf);
static ngx_int_t ngx_pipe_rollback_parse_args(ngx_cycle_t *cycle,
    ngx_open_pipe_t *op, ngx_pipe_rollback_conf_t *rbcf);

ngx_str_t ngx_log_error_backup = ngx_string(NGX_ERROR_LOG_PATH);
ngx_str_t ngx_log_access_backup = ngx_string(NGX_HTTP_LOG_PATH);

ngx_str_t ngx_pipe_dev_null_file = ngx_string("/dev/null");

ngx_open_pipe_t *
ngx_conf_open_pipe(ngx_cycle_t *cycle, ngx_str_t *cmd, const char *type)
{
    u_char           *cp, *ct, *dup, **argi, **c1, **c2;
    ngx_int_t         same, ti, use;
    ngx_uint_t        i, j, numargs = 0;
    ngx_array_t      *argv_out;

    dup = ngx_pnalloc(cycle->pool, cmd->len + 1);
    if (dup == NULL) {
        return NULL;
    }

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
    if (argi == NULL) {
        return NULL;
    }

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
    ngx_uint_t i;
#ifdef T_PIPES_OUTPUT_ON_BROKEN
    ngx_uint_t is_stderr = 0;
#endif

    for (i = 0; i < ngx_last_pipe; i++) {

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

#ifdef T_PIPES_OUTPUT_ON_BROKEN
            if (ngx_pipes[i].open_fd == ngx_cycle->log->file) {
                is_stderr = 1;
            }
#endif

            ngx_pipes[i].open_fd->fd = NGX_INVALID_FILE;

#ifdef T_PIPES_OUTPUT_ON_BROKEN
            if (ngx_pipes[i].backup.len > 0 && ngx_pipes[i].backup.data != NULL) {
#else
                //just write to /dev/null
                ngx_pipes[i].backup.data = ngx_pipe_dev_null_file.data;
                ngx_pipes[i].backup.len = ngx_pipe_dev_null_file.len;
#endif
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
#ifdef T_PIPES_OUTPUT_ON_BROKEN
            }

            if (is_stderr) {
                ngx_set_stderr(ngx_cycle->log->file->fd);
            }
#endif

            if (master) {
#ifdef T_PIPES_OUTPUT_ON_BROKEN
                if (ngx_pipes[i].backup.len > 0 && ngx_pipes[i].backup.data != NULL) {
                    if (chown((const char *) ngx_pipes[i].backup.data,
                              ngx_pipes[i].user, -1)
                        == -1)
                    {
                        ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                                      "chown() \"%s\" failed",
                                      ngx_pipes[i].backup.data);
                    }
                }
#endif

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
#ifdef T_PIPE_USE_USER
    ngx_core_conf_t  *ccf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);
#endif

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

       /*
        * Set correct process type since closing listening Unix domain socket
        * in a master process also removes the Unix domain socket file.
        */
        ngx_process = NGX_PROCESS_PIPE;
        ngx_close_listening_sockets(cycle);

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
#ifdef T_PIPE_USE_USER
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
#endif

        /*
         * redirect stderr to /dev/null, because stderr will be connected with
         * fd used by the last pipe when error log is configured using pipe,
         * that will cause it no close
         */

        fd = ngx_open_file("/dev/null", NGX_FILE_WRONLY, NGX_FILE_OPEN, 0);
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

        if (ngx_strncmp(argv[0], "rollback", sizeof("rollback") - 1) == 0) {
            ngx_pipe_log(cycle, op);
            exit(0);

        } else {
            execv((const char *) argv[0], (char *const *) op->argv->elts);
            exit(0);
        }
    }

    return NGX_OK;

err:

    close(op->pfd[0]);
    close(op->pfd[1]);

    return NGX_ERROR;
}


static void
ngx_pipe_create_subdirs(char *filename, ngx_cycle_t *cycle)
{
    ngx_file_info_t stat_buf;
    char            dirname[1024];
    char           *p;

    for (p = filename; (p = strchr(p, '/')); p++)
    {
        if (p == filename) {
            continue;       // Don't bother with the root directory
        }

        ngx_memcpy(dirname, filename, p - filename);
        dirname[p-filename] = '\0';

        if (ngx_file_info(dirname, &stat_buf) < 0) {
            if (errno != ENOENT) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                              "stat [%s] failed", dirname);
                exit(2);

            } else {
                if ((ngx_create_dir(dirname, NGX_PIPE_DIR_ACCESS) < 0) && (errno != EEXIST)) {
                    ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                                  "mkdir [%s] failed", dirname);
                    exit(2);
                }
            }
        }
    }
}

static void
ngx_pipe_create_suitpath(ngx_cycle_t *cycle, ngx_pipe_rollback_conf_t *rbcf)
{
    char        realpath[256];
    struct      tm *tm_now;
    int         result;
    time_t      t = ngx_time();

    tm_now = localtime(&t);
    if (tm_now == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "get now time failed");
        return;
    }
    if (0 >= strftime(realpath, sizeof(realpath), rbcf->suitpath, tm_now)) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "parse suitpath with time now failed");
        return;
    }

    ngx_pipe_create_subdirs(realpath, cycle);

    result = unlink(realpath);
    if (0 == result) {
        ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                      "unlink [%s] success", realpath);
    } else {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                      "unlink [%s] failed", realpath);
    }

    result = symlink(rbcf->logname, realpath);
    if (0 == result) {
        ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                      "symlink [%s] success", realpath);
    } else {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                      "symlink [%s] failed", realpath);
    }

    rbcf->last_suit_time = rbcf->time_now;
}

static time_t
ngx_pipe_get_now_sec()
{
    ngx_time_update();

    return ngx_time() + ngx_cached_time->gmtoff * 60;
}

static void
ngx_pipe_log(ngx_cycle_t *cycle, ngx_open_pipe_t *op)
{
    ngx_int_t                   n_bytes_read;
    u_char                     *read_buf;
    size_t                      read_buf_len = 65536;
    ngx_fd_t                    log_fd = NGX_INVALID_FILE;
#ifdef T_PIPE_NO_DISPLAY
    size_t                      title_len;
#endif
    ngx_pipe_rollback_conf_t    rbcf;
    ngx_file_info_t             sb;
    size_t                      one_day = 24 * 60 * 60;

    ngx_pid = ngx_getpid();

    rbcf.last_open_time = 0;
    rbcf.last_suit_time = 0;
    rbcf.log_size = 0;

    if (ngx_pipe_rollback_parse_args(cycle, op, &rbcf) != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, "log rollback parse error");
        return;
    }

    read_buf = ngx_pcalloc(cycle->pool, read_buf_len);
    if (read_buf == NULL) {
        return;
    }

    //set title
    ngx_setproctitle((char *) op->cmd);
#ifdef T_PIPE_NO_DISPLAY
    title_len = ngx_strlen(ngx_os_argv[0]);
#if (NGX_SOLARIS)
#else
    ngx_memset((u_char *) ngx_os_argv[0], NGX_SETPROCTITLE_PAD, title_len);
    ngx_cpystrn((u_char *) ngx_os_argv[0], op->cmd, title_len);
#endif
#endif

    for (;;)
    {
        if (ngx_terminate == 1) {
            return;
        }

        n_bytes_read = ngx_read_fd(0, read_buf, read_buf_len);
        if (n_bytes_read == 0) {
            return;
        }
        if (errno == EINTR) {
            continue;

        } else if (n_bytes_read < 0) {
            return;
        }

        rbcf.time_now = ngx_pipe_get_now_sec();

        if (NULL != rbcf.suitpath) {
            if (rbcf.time_now / one_day >
                    rbcf.last_suit_time / one_day) {
                ngx_pipe_create_suitpath(cycle, &rbcf);
            }
        }

        if (log_fd >= 0) {
            if (rbcf.interval > 0) {
                if (((rbcf.time_now - rbcf.adjust_time) / rbcf.interval) >
                        (rbcf.last_open_time / rbcf.interval)) {
                    //need check rollback
                    ngx_close_file(log_fd);
                    log_fd = NGX_INVALID_FILE;
                    ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                                  "need check rollback time [%s]", rbcf.logname);
                    ngx_pipe_do_rollback(cycle, &rbcf);
                }
            }
        }

        if (log_fd >= 0 && rbcf.log_max_size > 0 &&
                           rbcf.log_size >= rbcf.log_max_size) {
            ngx_close_file(log_fd);
            log_fd = NGX_INVALID_FILE;
            ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                          "need check rollback size [%s] [%d]",
                          rbcf.logname, rbcf.log_size);
            ngx_pipe_do_rollback(cycle, &rbcf);
        }

        /* If there is no log file open then open a new one.
         *   */
        if (log_fd < 0) {
            ngx_pipe_create_subdirs(rbcf.logname, cycle);
            if (rbcf.interval > 0 && rbcf.last_open_time == 0 
                    && ((rbcf.time_now - rbcf.adjust_time_raw) / rbcf.interval < rbcf.time_now / rbcf.interval)) { /*just check
                when time is after interval and befor adjust_time_raw, fix when no backup file, do rollback
                */
                //need check last rollback time, because other process may do rollback after when it adjust time more than this process
                ngx_pipe_get_last_rollback_time(&rbcf);
            } else {
                rbcf.last_open_time = ngx_pipe_get_now_sec();
            }

            log_fd = ngx_open_file(rbcf.logname, NGX_FILE_APPEND, NGX_FILE_CREATE_OR_OPEN,
                          NGX_PIPE_FILE_ACCESS);
            if (log_fd < 0) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                              "open [%s] failed", rbcf.logname);
                return;
            }

            if (0 == ngx_fd_info(log_fd, &sb)) {
                rbcf.log_size = sb.st_size;
            }
        }

        if (ngx_write_fd(log_fd, read_buf, n_bytes_read) != n_bytes_read) {
            if (errno != EINTR) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                              "write to [%s] failed", rbcf.logname);
                return;
            }
        }
        rbcf.log_size += n_bytes_read;
    }

}

ngx_int_t
ngx_pipe_rollback_parse_args(ngx_cycle_t *cycle, ngx_open_pipe_t *op,
    ngx_pipe_rollback_conf_t *rbcf)
{
    u_char         **argv;
    ngx_uint_t       i;
    ngx_int_t        j;
    size_t           len;
    ngx_str_t        filename;
    ngx_str_t        value;
    uint32_t         hash;

    if (op->argv->nelts < 3) {
        //no logname
        return NGX_ERROR;
    }

    //parse args
    argv = op->argv->elts;

    //set default param
    filename.data = (u_char *) argv[1];
    filename.len = ngx_strlen(filename.data);
    if (ngx_conf_full_name(cycle, &filename, 0) != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                      "get fullname failed");
        return NGX_ERROR;
    }
    rbcf->logname = (char *) filename.data;
    rbcf->backup_num = 1;
    rbcf->log_max_size = -1;
    rbcf->interval = -1;
    rbcf->suitpath = NULL;
    rbcf->adjust_time = 60;
    rbcf->adjust_time_raw = 60;
    memset(rbcf->backup, 0, sizeof(rbcf->backup));

    for (i = 2; i < op->argv->nelts; i++) {
        if (argv[i] == NULL) {
            break;
        }
        if (ngx_strncmp((u_char *) "interval=", argv[i], 9) == 0) {
            value.data = argv[i] + 9;
            value.len = ngx_strlen((char *) argv[i]) - 9;
#ifdef T_PIPE_OLD_CONF
            //just compatibility
            rbcf->interval = ngx_atoi(value.data, value.len);
            if (rbcf->interval > 0) {
                rbcf->interval = rbcf->interval * 60;   //convert minute to second
                continue;
            }
#endif
            rbcf->interval = ngx_parse_time(&value, 1);
            if (rbcf->interval <= 0) {
                rbcf->interval = -1;
            }

        } else if (ngx_strncmp((u_char *) "baknum=", argv[i], 7) == 0) {
            rbcf->backup_num = ngx_atoi(argv[i] + 7,
                                        ngx_strlen((char *) argv[i]) - 7);
            if (rbcf->backup_num <= 0) {
                rbcf->backup_num = 1;

            } else if (MAX_BACKUP_NUM < (size_t)rbcf->backup_num) {
                rbcf->backup_num = MAX_BACKUP_NUM;
            }

        } else if (ngx_strncmp((u_char *) "maxsize=", argv[i], 8) == 0) {
            value.data = argv[i] + 8;
            value.len = ngx_strlen((char *) argv[i]) - 8;
#ifdef T_PIPE_OLD_CONF
            //just compatibility
            rbcf->log_max_size = ngx_atoi(value.data, value.len);
            if (rbcf->log_max_size > 0) {
                rbcf->log_max_size = rbcf->log_max_size * 1024 * 1024; //M
                continue;
            }
#endif
            rbcf->log_max_size = ngx_parse_offset(&value);
            if (rbcf->log_max_size <= 0) {
                rbcf->log_max_size = -1;
            } 
        } else if (ngx_strncmp((u_char *) "suitpath=", argv[i], 9) == 0) {
            filename.data = (u_char*)(argv[i] + 9);
            filename.len = ngx_strlen(filename.data);
            if (ngx_conf_full_name(cycle, &filename, 0) != NGX_OK) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                              "get fullname failed");
                return NGX_ERROR;
            }
            rbcf->suitpath = (char*)filename.data;

            rbcf->time_now = ngx_pipe_get_now_sec();
            ngx_pipe_create_suitpath(cycle, rbcf);
        } else if (ngx_strncmp((u_char *) "adjust=", argv[i], 7) == 0) {
            value.data =argv[i] + 7;
            value.len = ngx_strlen((char *) argv[i]) - 7;
            rbcf->adjust_time_raw = ngx_parse_time(&value, 1);
            if (rbcf->adjust_time_raw < 1) {
                rbcf->adjust_time_raw = 1;
            }
        }
    } 

    len = ngx_strlen(rbcf->logname) + 5; //max is ".128"
    for (j = 0; j < rbcf->backup_num; j++) {
        rbcf->backup[j] = ngx_pcalloc(cycle->pool, len);
        if (rbcf->backup[j] == NULL) {
            return NGX_ERROR;
        }
        ngx_snprintf((u_char *) rbcf->backup[j], len, "%s.%i%Z", rbcf->logname, j + 1);
    }

    //use same seed for same log file, when reload may have same adjust time
    hash = ngx_crc32_short((u_char*)rbcf->logname, ngx_strlen(rbcf->logname));
    srand(hash);
    rbcf->adjust_time = rand() % rbcf->adjust_time_raw;

    ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                  "log rollback param: num [%i], interval %i(S), size %i(B), adjust %i/%i(S)", 
                  rbcf->backup_num, rbcf->interval, rbcf->log_max_size, rbcf->adjust_time, rbcf->adjust_time_raw);

    return NGX_OK;
}

void ngx_pipe_get_last_rollback_time(ngx_pipe_rollback_conf_t *rbcf)
{
    int             fd;
    struct flock    lock;
    int             ret;

    struct stat     sb;

    fd = ngx_open_file(rbcf->logname, NGX_FILE_RDWR, NGX_FILE_OPEN, 0);
    if (fd < 0) {
        //open lock file failed just use now
        rbcf->last_open_time = rbcf->time_now;
        return;
    }

    lock.l_type     = F_WRLCK;
    lock.l_whence   = SEEK_SET;
    lock.l_start    = 0;
    lock.l_len      = 0;

    ret = fcntl(fd, F_SETLKW, &lock);
    if (ret < 0) {
        close(fd);
        //lock failed just use now
        rbcf->last_open_time = rbcf->time_now;
        return;
    }

    //check time
    if (rbcf->interval > 0) {
        if (ngx_file_info(rbcf->backup[0], &sb) == -1) {
            //no backup file ,so need rollback just set 1
            rbcf->last_open_time = 1;
        } else if (sb.st_ctime / rbcf->interval < ngx_time() / rbcf->interval) {
            //need rollback just set 1
            rbcf->last_open_time = 1;
        } else {
            //just no need rollback
            rbcf->last_open_time = rbcf->time_now;
        }
    } else {
        rbcf->last_open_time = rbcf->time_now;
    }

    close(fd);
}

void
ngx_pipe_do_rollback(ngx_cycle_t *cycle, ngx_pipe_rollback_conf_t *rbcf)
{
    int             fd;
    struct flock    lock;
    int             ret;
    ngx_int_t       i;
    ngx_file_info_t sb;
    ngx_int_t       need_do = 0;

    fd = ngx_open_file(rbcf->logname, NGX_FILE_RDWR, NGX_FILE_OPEN, 0);
    if (fd < 0) {
        //open lock file failed just no need rollback
        return;
    }

    lock.l_type     = F_WRLCK;
    lock.l_whence   = SEEK_SET;
    lock.l_start    = 0;
    lock.l_len      = 0;

    ret = fcntl(fd, F_SETLKW, &lock);
    if (ret < 0) {
        ngx_close_file(fd);
        //lock failed just no need rollback
        return;
    }

    //check time
    if (rbcf->interval >= 0) {
        if (ngx_file_info(rbcf->backup[0], &sb) == -1) {
            need_do = 1;
            ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                          "need rollback [%s]: cannot open backup", rbcf->logname);

        } else if (sb.st_ctime / rbcf->interval < ngx_time() / rbcf->interval) {
            need_do = 1;
            ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                          "need rollback [%s]: time on [%d] [%d]",
                          rbcf->logname, sb.st_ctime, rbcf->time_now);

        } else {
            ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                          "no need rollback [%s]: time not on [%d] [%d]",
                          rbcf->logname, sb.st_ctime, rbcf->time_now);
        }

    } else {
        ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                      "no need check rollback [%s] time: no interval", rbcf->logname);
    }

    //check size
    if (rbcf->log_max_size > 0) {
        if (ngx_file_info(rbcf->logname, &sb) == 0 && (sb.st_size >= rbcf->log_max_size)) {
            need_do = 1;
            ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                          "need rollback [%s]: size on [%d]", rbcf->logname, sb.st_size);

        } else {
            ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                          "no need rollback [%s]: size not on", rbcf->logname);
        }

    } else {
        ngx_log_error(NGX_LOG_INFO, cycle->log, 0,
                      "no need check rollback [%s] size: no max size", rbcf->logname);
    }

    if (need_do) {
        for (i = 1; i < rbcf->backup_num; i++) {
            ngx_rename_file(rbcf->backup[rbcf->backup_num - i - 1],
                   rbcf->backup[rbcf->backup_num - i]);
        }
        if (ngx_rename_file(rbcf->logname, rbcf->backup[0]) < 0) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "rname %s to %s failed", rbcf->logname, rbcf->backup[0]);
        } else {
            ngx_log_error(NGX_LOG_WARN, cycle->log, 0,
                          "rollback [%s] success", rbcf->logname);
        }
    }
    ngx_close_file(fd);
}

#endif

