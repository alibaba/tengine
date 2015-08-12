/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_channel.h>
#include <ngx_proc.h>


static char *ngx_procs_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static void ngx_procs_cycle(ngx_cycle_t *cycle, void *data);
static void ngx_procs_process_init(ngx_cycle_t *cycle,
    ngx_proc_module_t *module, ngx_int_t priority);
static void ngx_procs_channel_handler(ngx_event_t *ev);
static void ngx_procs_process_exit(ngx_cycle_t *cycle,
    ngx_proc_module_t *module);
static void ngx_procs_pass_open_channel(ngx_cycle_t *cycle, ngx_channel_t *ch);

static char *ngx_proc_process(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static void *ngx_proc_create_main_conf(ngx_conf_t *cf);
static void *ngx_proc_create_conf(ngx_conf_t *cf);
static char *ngx_proc_merge_conf(ngx_conf_t *cf, void *parent, void *child);
static char *ngx_procs_set_priority(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


static ngx_command_t ngx_procs_commands[] = {

    { ngx_string("processes"),
      NGX_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_procs_block,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_core_module_t  ngx_procs_module_ctx = {
    ngx_string("procs"),
    NULL,
    NULL
};


ngx_module_t  ngx_procs_module = {
    NGX_MODULE_V1,
    &ngx_procs_module_ctx,                 /* module context */
    ngx_procs_commands,                    /* module directives */
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


static ngx_command_t ngx_proc_core_commands[] = {

    { ngx_string("process"),
      NGX_PROC_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_TAKE1,
      ngx_proc_process,
      0,
      0,
      NULL },

    { ngx_string("count"),
      NGX_PROC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_num_slot,
      NGX_PROC_CONF_OFFSET,
      offsetof(ngx_proc_conf_t, count),
      NULL },

    { ngx_string("priority"),
      NGX_PROC_CONF|NGX_CONF_TAKE1,
      ngx_procs_set_priority,
      NGX_PROC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("delay_start"),
      NGX_PROC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_PROC_CONF_OFFSET,
      offsetof(ngx_proc_conf_t, delay_start),
      NULL },

    { ngx_string("respawn"),
      NGX_PROC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_PROC_CONF_OFFSET,
      offsetof(ngx_proc_conf_t, respawn),
      NULL },

      ngx_null_command
};


static ngx_proc_module_t ngx_proc_core_module_ctx = {
    ngx_string("proc_core"),
    ngx_proc_create_main_conf,
    NULL,
    ngx_proc_create_conf,
    ngx_proc_merge_conf,
    NULL,
    NULL,
    NULL,
    NULL
};


ngx_module_t  ngx_proc_core_module = {
    NGX_MODULE_V1,
    &ngx_proc_core_module_ctx,             /* module context */
    ngx_proc_core_commands,                /* module directives */
    NGX_PROC_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_uint_t       ngx_procs_max_module;
static ngx_cycle_t      ngx_procs_exit_cycle;
static ngx_log_t        ngx_procs_exit_log;
static ngx_open_file_t  ngx_procs_exit_log_file;
#if (NGX_SYSLOG)
static ngx_syslog_t     ngx_procs_exit_log_syslog;
#endif


static char *
ngx_procs_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                 *rv;
    ngx_uint_t            i, mi, p;
    ngx_conf_t            pcf;
    ngx_proc_conf_t     **cpcfp;
    ngx_proc_module_t     *module;
    ngx_proc_conf_ctx_t   *ctx;
    ngx_proc_main_conf_t  *cmcf;

    /* the procs context */
    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_proc_conf_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    *(ngx_proc_conf_ctx_t **) conf = ctx;

    ngx_procs_max_module = 0;

    for (i = 0; ngx_modules[i]; i++) {
        if (ngx_modules[i]->type != NGX_PROC_MODULE) {
            continue;
        }

        ngx_modules[i]->ctx_index = ngx_procs_max_module++;
    }

    ctx->main_conf = ngx_pcalloc(cf->pool,
                                 ngx_procs_max_module * sizeof(void *));
    if (ctx->main_conf == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->proc_conf = ngx_pcalloc(cf->pool,
                                 sizeof(void *) * ngx_procs_max_module);
    if (ctx->proc_conf == NULL) {
        return NGX_CONF_ERROR;
    }

    /* create the main_confs for all proc modules */

    for (i = 0; ngx_modules[i]; i++) {
        if (ngx_modules[i]->type != NGX_PROC_MODULE) {
            continue;
        }

        module = ngx_modules[i]->ctx;
        mi = ngx_modules[i]->ctx_index;

        if (module->create_main_conf) {

            ctx->main_conf[mi] = module->create_main_conf(cf);

            if (ctx->main_conf[mi] == NULL) {
                return NGX_CONF_ERROR;
            }
        }

        if (module->create_proc_conf) {
            ctx->proc_conf[mi] = module->create_proc_conf(cf);

            if (ctx->proc_conf[mi] == NULL) {
                return NGX_CONF_ERROR;
            }
        }
    }


    pcf = *cf;
    cf->ctx = ctx;

    /* parse inside the procs block */
    cf->module_type = NGX_PROC_MODULE;
    cf->cmd_type = NGX_PROC_MAIN_CONF;

    rv = ngx_conf_parse(cf, NULL);

    if (rv != NGX_CONF_OK) {
        *cf = pcf;
        return rv;
    }

    cmcf = ctx->main_conf[ngx_proc_core_module.ctx_index];
    cpcfp = cmcf->processes.elts;

    for (i = 0; ngx_modules[i]; i++) {

        if (ngx_modules[i]->type != NGX_PROC_MODULE) {
            continue;
        }

        module = ngx_modules[i]->ctx;
        mi = ngx_modules[i]->ctx_index;

        cf->ctx = ctx;

        if (module->init_main_conf) {
            rv = module->init_main_conf(cf,ctx->main_conf[mi]);
            if (rv != NGX_CONF_OK) {
                *cf = pcf;
                return rv;
            }
        }

        for (p = 0; p < cmcf->processes.nelts; p++) {

            cf->ctx = cpcfp[p]->ctx;

            if (ngx_strcmp(module->name.data, cpcfp[p]->name.data) == 0
                || ngx_strcmp(module->name.data, "proc_core") == 0)
            {
                if (module->merge_proc_conf) {
                    rv = module->merge_proc_conf(cf, ctx->proc_conf[mi],
                                                 cpcfp[p]->ctx->proc_conf[mi]);

                    if (rv != NGX_CONF_OK) {
                        *cf = pcf;
                        return rv;
                    }

                    /* copy child to parent, tricky */
                    ctx->proc_conf[mi] = cpcfp[p]->ctx->proc_conf[mi];
                }
            }
        }
    }

    *cf = pcf;

    return NGX_CONF_OK;
}


ngx_int_t
ngx_procs_start(ngx_cycle_t *cycle, ngx_int_t type)
{
    ngx_int_t              rc, respawn;
    ngx_uint_t             i, p, n;
    ngx_channel_t          ch;
    ngx_proc_args_t      **args;
    ngx_proc_conf_t      **cpcfp;
    ngx_proc_module_t     *module;
    ngx_proc_main_conf_t  *cmcf;

    ngx_log_error(NGX_LOG_NOTICE, cycle->log, 0, "start procs processes");

    if (ngx_get_conf(cycle->conf_ctx, ngx_procs_module) == NULL) {
        return NGX_OK;
    }

    ch.command = NGX_CMD_OPEN_CHANNEL;
    cmcf = ngx_proc_get_main_conf(cycle->conf_ctx, ngx_proc_core_module);

    cpcfp = cmcf->processes.elts;
    args = ngx_pcalloc(cycle->pool,
                       sizeof(ngx_proc_args_t *) * cmcf->processes.nelts);
    if (args == NULL) {
        return NGX_ERROR;
    }

    for (p = 0; p< cmcf->processes.nelts; p++) {
        args[p] = ngx_pcalloc(cycle->pool, sizeof(ngx_proc_args_t));
        if (args[p] == NULL) {
            return NGX_ERROR;
        }
    }

    respawn = type ? NGX_PROCESS_JUST_RESPAWN : NGX_PROCESS_RESPAWN;

    for (i = 0; ngx_modules[i]; i++) {

        if (ngx_modules[i]->type != NGX_PROC_MODULE) {
            continue;
        }

        module = ngx_modules[i]->ctx;

        for (p = 0; p < cmcf->processes.nelts; p++) {
            if (ngx_strcmp(cpcfp[p]->name.data, module->name.data) == 0) {

                if (module->prepare) {
                    rc = module->prepare(cycle);
                    if (rc != NGX_OK) {
                        break;
                    }
                }

                if (type == 1) {
                    if (cpcfp[p]->respawn) {
                        respawn = NGX_PROCESS_JUST_RESPAWN;
                    }
                } else {
                    if (cpcfp[p]->respawn) {
                        respawn = NGX_PROCESS_RESPAWN;
                    } else {
                        respawn = NGX_PROCESS_NORESPAWN;
                    }
                }

                /* processes count */
                for (n = 0; n < cpcfp[p]->count; n++) {
                    args[p]->module = ngx_modules[i];
                    args[p]->proc_conf = cpcfp[p];

                    ngx_log_error(NGX_LOG_NOTICE, cycle->log, 0,
                                  "start process %V", &cpcfp[p]->name);

                    ngx_spawn_process(cycle, ngx_procs_cycle, args[p],
                                      (char *) cpcfp[p]->name.data, respawn);

                    ch.pid = ngx_processes[ngx_process_slot].pid;
                    ch.slot = ngx_process_slot;
                    ch.fd = ngx_processes[ngx_process_slot].channel[0];

                    ngx_procs_pass_open_channel(cycle, &ch);
                }
            }
        }
    }

    return NGX_OK;
}


static void
ngx_procs_cycle(ngx_cycle_t *cycle, void *data)
{
    ngx_int_t           rc;
    ngx_uint_t          i;
    ngx_module_t       *module;
    ngx_proc_args_t    *args;
    ngx_proc_conf_t    *cpcf;
    ngx_connection_t   *c;
    ngx_proc_module_t  *ctx;

    args = data;
    module = args->module;
    cpcf = args->proc_conf;
    ctx = module->ctx;
    ngx_process = NGX_PROCESS_PROC;

    ngx_setproctitle((char *) ctx->name.data);
    ngx_msleep(cpcf->delay_start);

    ngx_procs_process_init(cycle, ctx, cpcf->priority);
    ngx_close_listening_sockets(cycle);
    ngx_use_accept_mutex = 0;

    for ( ;; ) {
        if (ngx_exiting || ngx_quit) {
            ngx_exiting = 1;
            ngx_log_error(NGX_LOG_NOTICE, cycle->log, 0,
                          "process %V gracefully shutting down", &ctx->name);
            ngx_setproctitle("processes are shutting down");

            c = cycle->connections;

            for (i = 0; i < cycle->connection_n; i++) {
                if (c[i].fd != -1 && c[i].idle) {
                    c[i].close = 1;
                    c[i].read->handler(c[i].read);
                }
            }

            ngx_procs_process_exit(cycle, ctx);
        }

        if (ngx_terminate) {
            ngx_log_error(NGX_LOG_NOTICE, cycle->log, 0, "process %V exiting",
                          &ctx->name);

            ngx_procs_process_exit(cycle, ctx);
        }

        if (ngx_reopen) {
            ngx_reopen = 0;
            ngx_log_error(NGX_LOG_NOTICE, cycle->log, 0, "reopening logs");
            ngx_reopen_files(cycle, -1);
        }

        if (ctx->loop) {
            rc = ctx->loop(cycle);
            if (rc != NGX_OK) {
                break;
            }
        }

        ngx_time_update();

        ngx_process_events_and_timers(cycle);
    }

    ngx_procs_process_exit(cycle, ctx);
}


static void
ngx_procs_process_init(ngx_cycle_t *cycle, ngx_proc_module_t *module,
    ngx_int_t priority)
{
    sigset_t          set;
    ngx_int_t         n;
    ngx_uint_t        i;
    struct rlimit     rlmt;
    ngx_core_conf_t  *ccf;
    ngx_listening_t  *ls;

    if (ngx_set_environment(cycle, NULL) == NULL) {
        /* fatal */
        exit(2);
    }

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);

    if (priority != 0) {
        if (setpriority(PRIO_PROCESS, 0, (int) priority) == -1) {
            ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                          "process %V setpriority(%i) failed", &module->name,
                          priority);
        }
    }

    if (ccf->rlimit_nofile != NGX_CONF_UNSET) {
        rlmt.rlim_cur = (rlim_t) ccf->rlimit_nofile;
        rlmt.rlim_max = (rlim_t) ccf->rlimit_nofile;

        if (setrlimit(RLIMIT_NOFILE, &rlmt) == -1) {
            ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                          "process %V setrlimit(RLIMIT_NOFILE, %i) failed",
                          &module->name, ccf->rlimit_nofile);
        }
    }

    if (ccf->rlimit_core != NGX_CONF_UNSET) {
        rlmt.rlim_cur = (rlim_t) ccf->rlimit_core;
        rlmt.rlim_max = (rlim_t) ccf->rlimit_core;

        if (setrlimit(RLIMIT_CORE, &rlmt) == -1) {
            ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                          "process %V setrlimit(RLIMIT_CORE, %O) failed",
                          &module->name, ccf->rlimit_core);
        }
    }

#ifdef RLIMIT_SIGPENDING
    if (ccf->rlimit_sigpending != NGX_CONF_UNSET) {
        rlmt.rlim_cur = (rlim_t) ccf->rlimit_sigpending;
        rlmt.rlim_max = (rlim_t) ccf->rlimit_sigpending;

        if (setrlimit(RLIMIT_SIGPENDING, &rlmt) == -1) {
            ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                          "process %V setrlimit(RLIMIT_SIGPENDING, %i) failed",
                          &module->name, ccf->rlimit_sigpending);
        }
    }
#endif

    if (geteuid() == 0) {
        if (setgid(ccf->group) == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "process %V setgid(%d) failed", &module->name,
                          ccf->group);
            /* fatal */
            exit(2);
        }

        if (initgroups(ccf->username, ccf->group) == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "process %V initgroups(%s, %d) failed", &module->name,
                          ccf->username, ccf->group);
        }

        if (setuid(ccf->user) == -1) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "process %V setuid(%d) failed", &module->name,
                          ccf->user);
            /* fatal */
            exit(2);
        }
    }

#if (NGX_HAVE_PR_SET_DUMPABLE)

    /* allow coredump after setuid() in Linux 2.4.x */

    if (prctl(PR_SET_DUMPABLE, 1, 0, 0, 0) == -1) {
        ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                      "process %V prctl(PR_SET_DUMPABLE) failed",
                      &module->name);
    }

#endif

    if (ccf->working_directory.len) {
        if (chdir((char *) ccf->working_directory.data) == -1) {
            ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                          "process %V chdir(\"%s\") failed", &module->name,
                          ccf->working_directory.data);
            /* fatal */
            exit(2);
        }
    }

    sigemptyset(&set);

    if (sigprocmask(SIG_SETMASK, &set, NULL) == -1) {
        ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                      "process %V sigprocmask() failed", &module->name);
    }

    /*
     * disable deleting previous events for the listening sockets because
     * in the worker processes there are no events at all at this point
     */
    ls = cycle->listening.elts;

    for (i = 0; i < cycle->listening.nelts; i++) {
        ls[i].previous = NULL;
    }

    if (ngx_event_core_module.init_process(cycle) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                      "process %V init event error", &module->name);
        exit(2);
    }

    if (module->init) {
        if (module->init(cycle) != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                          "process %V process init error", &module->name);
            exit(2);
        }
    }


    for (n = 0; n < ngx_last_process; n++) {

        if (ngx_processes[n].pid == -1) {
            continue;
        }

        if (n == ngx_process_slot) {
            continue;
        }

        if (ngx_processes[n].channel[1] == -1) {
            continue;
        }

        if (close(ngx_processes[n].channel[1]) == -1) {
            ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                          "process %V close() channel failed", &module->name);
        }
    }

    if (close(ngx_processes[ngx_process_slot].channel[0]) == -1) {
        ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                      "process %V close() channel failed", &module->name);
    }

#if 0
    ngx_last_process = 0;
#endif

    if (ngx_add_channel_event(cycle, ngx_channel, NGX_READ_EVENT,
                              ngx_procs_channel_handler)
        == NGX_ERROR)
    {
        /* fatal */
        exit(2);
    }
}


static void
ngx_procs_channel_handler(ngx_event_t *ev)
{
    ngx_int_t          n;
    ngx_channel_t      ch;
    ngx_connection_t  *c;

    if (ev->timedout) {
        ev->timedout = 0;
        return;
    }

    c = ev->data;

    ngx_log_debug0(NGX_LOG_DEBUG_CORE, ev->log, 0, "process channel handler");

    for ( ;; ) {

        n = ngx_read_channel(c->fd, &ch, sizeof(ngx_channel_t), ev->log);

        ngx_log_debug1(NGX_LOG_DEBUG_CORE, ev->log, 0,
                       "process channel: %i", n);

        if (n == NGX_ERROR) {

            if (ngx_event_flags & NGX_USE_EPOLL_EVENT) {
                ngx_del_conn(c, 0);
            }

            ngx_close_connection(c);
            return;
        }

        if (ngx_event_flags & NGX_USE_EVENTPORT_EVENT) {
            if (ngx_add_event(ev, NGX_READ_EVENT, 0) == NGX_ERROR) {
                return;
            }
        }

        if (n == NGX_AGAIN) {
            return;
        }

        ngx_log_debug1(NGX_LOG_DEBUG_CORE, ev->log, 0,
                       "process channel command: %ui", ch.command);

        switch (ch.command) {

        case NGX_CMD_QUIT:
            ngx_quit = 1;
            break;

        case NGX_CMD_TERMINATE:
            ngx_terminate = 1;
            break;

        case NGX_CMD_REOPEN:
            ngx_reopen = 1;
            break;

        case NGX_CMD_OPEN_CHANNEL:

            ngx_log_debug3(NGX_LOG_DEBUG_CORE, ev->log, 0,
                           "process got channel s:%i pid:%P fd:%d",
                           ch.slot, ch.pid, ch.fd);

            ngx_processes[ch.slot].pid = ch.pid;
            ngx_processes[ch.slot].channel[0] = ch.fd;
            break;

        case NGX_CMD_CLOSE_CHANNEL:

            ngx_log_debug4(NGX_LOG_DEBUG_CORE, ev->log, 0,
                           "process closed channel s:%i pid:%P our:%P fd:%d",
                           ch.slot, ch.pid, ngx_processes[ch.slot].pid,
                           ngx_processes[ch.slot].channel[0]);

            if (close(ngx_processes[ch.slot].channel[0]) == -1) {
                ngx_log_error(NGX_LOG_ALERT, ev->log, ngx_errno,
                              "process close() channel failed");
            }

            ngx_processes[ch.slot].channel[0] = -1;
            break;

        case NGX_CMD_PIPE_BROKEN:
            ngx_pipe_broken_action(ev->log, ch.pid, 0);
            break;
        }
    }
}


static void
ngx_procs_process_exit(ngx_cycle_t *cycle, ngx_proc_module_t *module)
{
    ngx_uint_t         i;
    ngx_connection_t  *c;

#if (NGX_THREADS)
    ngx_terminate = 1;

    ngx_wakeup_worker_threads(cycle);
#endif

    if (module->exit) {
        module->exit(cycle);
    }

    if (ngx_exiting) {
        c = cycle->connections;
        for (i = 0; i < cycle->connection_n; i++) {
            if (c[i].fd != -1
                && c[i].read
                && !c[i].read->accept
                && !c[i].read->channel
                && !c[i].read->resolver)
            {
                ngx_log_error(NGX_LOG_ALERT, cycle->log, 0,
                              "open socket #%d left in connection %ui",
                              c[i].fd, i);
                ngx_debug_quit = 1;
            }
        }

        if (ngx_debug_quit) {
            ngx_log_error(NGX_LOG_ALERT, cycle->log, 0, "aborting");
            ngx_debug_point();
        }
    }

    /*
     * Copy ngx_cycle->log related data to the special static exit cycle,
     * log, and log file structures enough to allow a signal handler to log.
     * The handler may be called when standard ngx_cycle->log allocated from
     * ngx_cycle->pool is already destroyed.
     */

    ngx_procs_exit_log_file.fd = ngx_cycle->log->file->fd;

    ngx_procs_exit_log = *ngx_cycle->log;
    ngx_procs_exit_log.file = &ngx_procs_exit_log_file;

#if (NGX_SYSLOG)
    if (ngx_procs_exit_log.syslog != NULL) {
        ngx_procs_exit_log_syslog = *ngx_procs_exit_log.syslog;
        ngx_procs_exit_log.syslog = &ngx_procs_exit_log_syslog;
    }
#endif

    ngx_procs_exit_cycle.log = &ngx_procs_exit_log;
    ngx_cycle = &ngx_procs_exit_cycle;

    ngx_log_error(NGX_LOG_NOTICE, ngx_cycle->log, 0, "process %V exit",
                  &module->name);

    ngx_destroy_pool(cycle->pool);

    exit(0);
}


static void
ngx_procs_pass_open_channel(ngx_cycle_t *cycle, ngx_channel_t *ch)
{
    ngx_int_t  i;

    for (i = 0; i < ngx_last_process; i++) {

        if (i == ngx_process_slot
            || ngx_processes[i].pid == -1
            || ngx_processes[i].channel[0] == -1)
        {
            continue;
        }

        ngx_log_debug6(NGX_LOG_DEBUG_CORE, cycle->log, 0,
            "process passed channel s:%d pid:%P fd:%d to s:%i pid:%P fd:%d",
             ch->slot, ch->pid, ch->fd, i, ngx_processes[i].pid,
             ngx_processes[i].channel[0]);

        /* TODO: NGX_AGAIN */

        ngx_write_channel(ngx_processes[i].channel[0],
                          ch, sizeof(ngx_channel_t), cycle->log);
    }
}


static char *
ngx_proc_process(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                  *rv;
    void                  *mconf;
    ngx_int_t              i;
    ngx_str_t             *value;
    ngx_flag_t             flag;
    ngx_conf_t             pcf;
    ngx_uint_t             m;
    ngx_proc_conf_t       *cpcf, **cpcfp;
    ngx_proc_module_t     *module;
    ngx_proc_conf_ctx_t   *ctx, *procs_ctx;
    ngx_proc_main_conf_t  *cmcf;

    value = cf->args->elts;
    flag = 0;

    for (m = 0; ngx_modules[m]; m++) {
        if (ngx_modules[m]->type != NGX_PROC_MODULE) {
            continue;
        }
        module = ngx_modules[m]->ctx;

        if (ngx_strcmp(module->name.data, value[1].data) == 0) {
            flag = 1;
            break;
        }
    }

    if (flag == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "no %V process module", &value[1]);
        return NGX_CONF_ERROR;
    }

    /* new conf ctx */
    ctx = ngx_pcalloc(cf->pool, sizeof(ngx_proc_conf_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    procs_ctx = cf->ctx;
    ctx->main_conf = procs_ctx->main_conf; /* old main conf */

    /* the processes{}'s proc_conf */

    ctx->proc_conf = ngx_pcalloc(cf->pool,
                                 sizeof(void *) * ngx_procs_max_module);
    if (ctx->proc_conf == NULL) {
        return NGX_CONF_ERROR;
    }

    for (m = 0; ngx_modules[m]; m++) {
        if (ngx_modules[m]->type != NGX_PROC_MODULE) {
            continue;
        }

        module = ngx_modules[m]->ctx;

        if (module->create_proc_conf) {
            mconf = module->create_proc_conf(cf);

            if (mconf == NULL) {
                return NGX_CONF_ERROR;
            }

            /* new proc conf */
            ctx->proc_conf[ngx_modules[m]->ctx_index] = mconf;
        }
    }

    /* the proc configuration context */

    cpcf = ctx->proc_conf[ngx_proc_core_module.ctx_index];
    cpcf->ctx = ctx;
    cpcf->name = value[1];

    cmcf = ctx->main_conf[ngx_proc_core_module.ctx_index];

    cpcfp = ngx_array_push(&cmcf->processes);
    if (cpcfp == NULL) {
        return NGX_CONF_ERROR;
    }

    *cpcfp = cpcf;

    /* check process conf repeat */
    cpcfp = cmcf->processes.elts;
    for (i = cmcf->processes.nelts - 2; i >= 0 ; i--) {
        if (ngx_strcmp(cpcfp[i]->name.data, cpcf->name.data) == 0) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "process repeat");
            return NGX_CONF_ERROR;
        }
    }

    /* parse inside process{} */

    pcf = *cf;
    cf->ctx = ctx;
    cf->cmd_type = NGX_PROC_CONF;

    rv = ngx_conf_parse(cf, NULL);

    *cf = pcf;

    return rv;
}


static void *
ngx_proc_create_main_conf(ngx_conf_t *cf)
{
    ngx_proc_main_conf_t  *cmcf;

    cmcf = ngx_pcalloc(cf->pool, sizeof(ngx_proc_main_conf_t));
    if (cmcf == NULL) {
        return NULL;
    }

    if (ngx_array_init(&cmcf->processes, cf->pool, 4, sizeof(ngx_proc_conf_t *))
        != NGX_OK)
    {
        return NULL;
    }

    return cmcf;
}


static void *
ngx_proc_create_conf(ngx_conf_t *cf)
{
    ngx_proc_conf_t  *cpcf;

    cpcf = ngx_pcalloc(cf->pool, sizeof(ngx_proc_conf_t));
    if (cpcf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc()
     *
     *     cpcf->delay_start = 0;
     *     cpcf->priority = 0;
     *     cpcf->count = 0;
     *     cpcf->respawn = 0;
     */

    cpcf->delay_start = NGX_CONF_UNSET_MSEC;
    cpcf->count = NGX_CONF_UNSET_UINT;
    cpcf->respawn = NGX_CONF_UNSET;

    return cpcf;
}


static char *
ngx_proc_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_proc_conf_t  *prev = parent;
    ngx_proc_conf_t  *conf = child;

    ngx_conf_merge_msec_value(conf->delay_start, prev->delay_start, 300);
    ngx_conf_merge_uint_value(conf->count, prev->count, 1);
    ngx_conf_merge_value(conf->respawn, prev->respawn, 1);

    return NGX_CONF_OK;
}


static char *
ngx_procs_set_priority(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_proc_conf_t  *pcf = conf;

    ngx_str_t        *value;
    ngx_uint_t        n, minus;

    if (pcf->priority != 0) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].data[0] == '-') {
        n = 1;
        minus = 1;

    } else if (value[1].data[0] == '+') {
        n = 1;
        minus = 0;

    } else {
        n = 0;
        minus = 0;
    }

    pcf->priority = ngx_atoi(&value[1].data[n], value[1].len - n);
    if (pcf->priority == NGX_ERROR) {
        return "invalid number";
    }

    if (minus) {
        pcf->priority = -pcf->priority;
    }

    return NGX_CONF_OK;
}
