#include <nginx.h>
#include<ngx_proc.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include<ngx_channel.h>

typedef struct {
    ngx_int_t   test;
    ngx_msec_t              time_out;
    ngx_array_t              *uri_prome;
} ngx_proc_prome_traffic_main_conf_t; 


static ngx_int_t ngx_proc_prome_traffic_prepare(ngx_cycle_t *cycle);
static void ngx_proc_prome_traffic_exit_worker(ngx_cycle_t *cycle);
static ngx_int_t ngx_proc_prome_traffic_init_worker(ngx_cycle_t *cycle);
static void * ngx_proc_prome_traffic_create_main_conf(ngx_conf_t *cf);

// 里面初始化指令数据(例如时间,port,)
static ngx_command_t ngx_proc_prome_traffic_commands[] = {
    { ngx_string("traffic_timeout"),
      NGX_PROC_CONF | NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_PROC_CONF_OFFSET,
      offsetof(ngx_proc_prome_traffic_main_conf_t, time_out),
      NULL,
    }
    

    ngx_null_command
};


static ngx_proc_module_t ngx_proc_prome_traffic_module_ctx = {
    ngx_string("prome_traffic"),
    ngx_proc_prome_traffic_create_main_conf,
    NULL,
    NULL,
    NULL,
    ngx_proc_prome_traffic_prepare,
    ngx_proc_prome_traffic_init_worker,
    NULL,
    ngx_proc_prome_traffic_exit_worker
};


ngx_module_t ngx_proc_traffic_prome_module = {
    NGX_MODULE_V1,
    &ngx_proc_prome_traffic_module_ctx,
    ngx_proc_prome_traffic_commands,
    NGX_PROC_MODULE,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NGX_MODULE_V1_PADDING
};

static ngx_int_t
ngx_proc_prome_traffic_prepare(ngx_cycle_t *cycle)
{
    return NGX_OK;
}

static ngx_int_t
ngx_proc_prome_traffic_init_worker(ngx_cycle_t *cycle)
{

    
    return NGX_OK;
}


static void
ngx_proc_prome_traffic_exit_worker(ngx_cycle_t *cycle)
{

}


static void *
ngx_proc_prome_traffic_create_main_conf(ngx_conf_t *cf)
{
    ngx_proc_prome_traffic_main_conf_t  *conf;
    // ngx_int_t rc = NGX_OK;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_proc_prome_traffic_main_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    conf->test = 0;
    conf->time_out = 0;
    conf->uri_prome = NGX_CONF_UNSET_PTR;

    return conf;
}



