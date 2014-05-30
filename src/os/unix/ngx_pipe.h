
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_PIPE_H_INCLUDED_
#define _NGX_PIPE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>


#if !(NGX_WIN32)

typedef struct {
    u_char           *cmd;
    ngx_fd_t          pfd[2];
    ngx_pid_t         pid;
    ngx_str_t         backup;         /* when pipe is broken, log into it */
    ngx_uid_t         user;
    ngx_uint_t        generation;
    ngx_array_t      *argv;
    ngx_open_file_t  *open_fd;        /* the fd of pipe left open in master */

    unsigned          type:1;         /* 1: write, 0: read */
    unsigned          configured:1;
} ngx_open_pipe_t;


#define NGX_PIPE_WRITE    1
#define NGX_PIPE_READ     0


ngx_open_pipe_t *ngx_conf_open_pipe(ngx_cycle_t *cycle, ngx_str_t *cmd,
    const char *type);
void ngx_increase_pipe_generation(void);
void ngx_close_old_pipes(void);
ngx_int_t ngx_open_pipes(ngx_cycle_t *cycle);
void ngx_close_pipes(void);
void ngx_pipe_broken_action(ngx_log_t *log, ngx_pid_t pid, ngx_int_t master);


extern ngx_str_t ngx_log_error_backup;
extern ngx_str_t ngx_log_access_backup;

#else

#define ngx_increase_pipe_generation
#define ngx_close_old_pipes
#define ngx_open_pipes(cycle)
#define ngx_close_pipes
#define ngx_pipe_broken_action(log, pid, master)

#endif


#endif /* _NGX_PIPE_H_INCLUDED_ */
