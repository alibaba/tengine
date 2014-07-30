

#include <ngx_event.h>

#define NGX_TIMER_WHEEL_DEFAULT_MAX_MSEC 4*60*1000 /* 4 mins */

static char *ngx_timer_use(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static void *ngx_timer_create_conf(ngx_cycle_t *cycle);
static char *ngx_timer_init_conf(ngx_cycle_t *cycle, void *conf);

extern ngx_timer_actions_t        ngx_timer_heap_actions;
extern ngx_timer_actions_t        ngx_timer_heap4_actions;
extern ngx_timer_actions_t        ngx_timer_wheel_actions;
extern ngx_timer_actions_t        ngx_timer_rbtree_actions;

static ngx_timer_actions_t*   ngx_timer_all_actions[] = {
    &ngx_timer_heap_actions,
    &ngx_timer_heap4_actions,
    &ngx_timer_wheel_actions,
    &ngx_timer_rbtree_actions,
    NULL
};


ngx_timer_actions_t   ngx_timer_actions;

static ngx_command_t  ngx_timer_commands[] = {

    { ngx_string("timer_use"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE1,
      ngx_timer_use,
      0,
      0,
      NULL },

    { ngx_string("timer_wheel_max"),
      NGX_MAIN_CONF|NGX_DIRECT_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      0,
      offsetof(ngx_timer_conf_t, wheel_max),
      NULL },

    ngx_null_command
};


static ngx_core_module_t  ngx_timer_module_ctx = {
    ngx_string("timer"),
    ngx_timer_create_conf,
    ngx_timer_init_conf
};


ngx_module_t  ngx_timer_module = {
    NGX_MODULE_V1,
    &ngx_timer_module_ctx,                 /* module context */
    ngx_timer_commands,                    /* module directives */
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
ngx_timer_use(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_timer_conf_t    *old_tcf, *tcf = conf;
    ngx_uint_t           i;
    ngx_str_t           *value;


    if (tcf->use) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (cf->cycle->old_cycle->conf_ctx) {

        old_tcf = (ngx_timer_conf_t *)ngx_get_conf(cf->cycle->old_cycle->conf_ctx,
                  ngx_timer_module);

        if (ngx_process == NGX_PROCESS_SINGLE
                && old_tcf
                && (old_tcf->use->name.len != value[1].len
                    || ngx_strncmp(old_tcf->use->name.data,
                                   value[1].data, value[1].len))) {

            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "when the server runs without a master process "
                               "the \"%V\" timer type must be the same as "
                               "in previous configuration - \"%V\" "
                               "and it cannot be changed on the fly, "
                               "to change it you need to stop server "
                               "and start it again",
                               &value[1], &old_tcf->use->name);

            return NGX_CONF_ERROR;
        }
    }

    for (i = 0; ngx_timer_all_actions[i]; i++) {

        if (ngx_timer_all_actions[i]->name.len != value[1].len) {
            continue;
        }

        if (ngx_strncmp(ngx_timer_all_actions[i]->name.data, value[1].data,value[1].len) ) {
            continue;
        }

        tcf->use = ngx_timer_all_actions[i];

        return NGX_CONF_OK;
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid timer type \"%V\"", &value[1]);

    return NGX_CONF_ERROR;
}


static void *
ngx_timer_create_conf(ngx_cycle_t *cycle)
{
    ngx_timer_conf_t     *tcf;

    /* create config  */
    tcf = ngx_pcalloc(cycle->pool, sizeof(ngx_timer_conf_t));
    if (tcf == NULL) {
        return NULL;
    }

    tcf->wheel_max = NGX_CONF_UNSET_MSEC;

    return tcf;
}


static char *
ngx_timer_init_conf(ngx_cycle_t *cycle, void *conf)
{
    ngx_timer_conf_t      *tcf = conf;
    ngx_core_conf_t       *ccf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);

    ngx_conf_init_msec_value(tcf->wheel_max, NGX_TIMER_WHEEL_DEFAULT_MAX_MSEC);

    if (tcf->use == NULL) {

        if (ccf->timer_resolution) {
            tcf->use = &ngx_timer_wheel_actions;
        } else {
            tcf->use = &ngx_timer_heap_actions;
        }
    }

    ngx_timer_actions = *tcf->use;

    ngx_log_error(NGX_LOG_NOTICE, cycle->log, 0,
                  "using the \"%V\" timer type", &tcf->use->name);

    if (ngx_timer_actions.init) {
        if (ngx_timer_actions.init(cycle) != NGX_OK) {
            return NGX_CONF_ERROR;
        }
    }

#if (NGX_THREADS)

    if (ngx_event_timer_mutex) {
        ngx_event_timer_mutex->log = log;
        return NGX_CONF_OK;
    }

    ngx_event_timer_mutex = ngx_mutex_init(log, 0);
    if (ngx_event_timer_mutex == NULL) {
        return NGX_CONF_ERROR;
    }

#endif

    return NGX_CONF_OK;
}


