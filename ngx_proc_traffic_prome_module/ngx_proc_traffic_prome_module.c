#include <nginx.h>
#include<ngx_proc.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include<ngx_channel.h>

typedef struct {
    ngx_int_t   test;
} ngx_proc_prome_traffic_main_conf_t; 

static ngx_int_t ngx_proc_prome_traffic_prepare(ngx_cycle_t *cycle);
static void ngx_proc_prome_traffic_exit_worker(ngx_cycle_t *cycle);
static ngx_int_t ngx_proc_prome_traffic_init_worker(ngx_cycle_t *cycle);
static void * ngx_proc_prome_traffic_create_main_conf(ngx_conf_t *cf);

static ngx_command_t ngx_proc_prome_traffic_commands[] = {

    

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

    return conf;
}



