#include <nginx.h>
#include<ngx_proc.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include<ngx_channel.h>

#define NGX_HTTP_REQSTAT_RSRV    29
#define NGX_HTTP_REQSTAT_MAX     50
#define NGX_HTTP_REQSTAT_USER    NGX_HTTP_REQSTAT_MAX - NGX_HTTP_REQSTAT_RSRV

// 思路:从cycle中拿到共享内存的地址直接读,读完后将结果输出
typedef struct {
    ngx_int_t         test;
    ngx_msec_t      time_out;
    ngx_http_reqstat_ctx_t    *ctx;
    
} ngx_proc_prome_traffic_main_conf_t; 

struct  ngx_http_reqstat_rbnode_s {
    u_char                       color;
    u_char                       padding[3];
    uint32_t                     len;

    ngx_queue_t                  queue;
    ngx_queue_t                  visit;

    ngx_atomic_t                 bytes_in;
    ngx_atomic_t                 bytes_out;
    ngx_atomic_t                 conn_total;
    ngx_atomic_t                 req_total;
    ngx_atomic_t                 http_2xx;
    ngx_atomic_t                 http_3xx;
    ngx_atomic_t                 http_4xx;
    ngx_atomic_t                 http_5xx;
    ngx_atomic_t                 other_status;
    ngx_atomic_t                 http_200;
    ngx_atomic_t                 http_206;
    ngx_atomic_t                 http_302;
    ngx_atomic_t                 http_304;
    ngx_atomic_t                 http_403;
    ngx_atomic_t                 http_404;
    ngx_atomic_t                 http_416;
    ngx_atomic_t                 http_499;
    ngx_atomic_t                 http_500;
    ngx_atomic_t                 http_502;
    ngx_atomic_t                 http_503;
    ngx_atomic_t                 http_504;
    ngx_atomic_t                 http_508;
    ngx_atomic_t                 other_detail_status;
    ngx_atomic_t                 http_ups_4xx;
    ngx_atomic_t                 http_ups_5xx;
    ngx_atomic_t                 rt;
    ngx_atomic_t                 ureq;
    ngx_atomic_t                 urt;
    ngx_atomic_t                 utries;
    ngx_atomic_t                 extra[NGX_HTTP_REQSTAT_USER];

    ngx_atomic_int_t             excess;

    ngx_msec_t                   last_visit;

    u_char                       data[1];
};




typedef struct {
    ngx_rbtree_t                 rbtree;
    ngx_rbtree_node_t            sentinel;
    ngx_queue_t                  queue;
    ngx_queue_t                  visit;
} ngx_http_reqstat_shctx_t;


typedef struct {
    ngx_str_t                   *val;
    ngx_slab_pool_t             *shpool;
    ngx_http_reqstat_shctx_t    *sh;
    ngx_http_complex_value_t     value;
    ngx_array_t                 *user_defined;
    ngx_int_t                    key_len;
    ngx_uint_t                   recycle_rate;
    ngx_int_t                    alloc_already_fail;
    ngx_event_t               loop_event;
} ngx_http_reqstat_ctx_t;

typedef struct {
    ngx_uint_t                   recv;
    ngx_uint_t                   sent;
    ngx_array_t                  monitor_index;
    ngx_array_t                  value_index;
    ngx_flag_t                   bypass;
    ngx_proc_prome_traffic_main_conf_t     *conf;
} ngx_http_reqstat_store_t;

static ngx_int_t ngx_proc_prome_traffic_prepare(ngx_cycle_t *cycle);
static void ngx_proc_prome_traffic_exit_worker(ngx_cycle_t *cycle);
static ngx_int_t ngx_proc_prome_traffic_init_worker(ngx_cycle_t *cycle);
static void * ngx_proc_prome_traffic_create_main_conf(ngx_conf_t *cf);
void ngx_proc_prome_traffic_handler (ngx_event_t *ev);





static ngx_command_t ngx_proc_prome_traffic_commands[] = {
    { ngx_string("traffic_timeout"),
      NGX_PROC_CONF | NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_PROC_CONF_OFFSET,
      offsetof(ngx_proc_prome_traffic_main_conf_t, time_out),
      NULL,
    },

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
    // 思路 在这里初始化共享内存,然后保存到一个全局变量中

    return NGX_OK;
}

static ngx_int_t
ngx_proc_prome_traffic_init_worker(ngx_cycle_t *cycle)
{
    ngx_event_t                                     *loop_event;
    ngx_http_reqstat_ctx_t                      *ctx;
    
    loop_event = &ctx->loop_event;
    loop_event->log = ngx_cycle->log;
    loop_event->data = ctx;
    loop_event->handler = ngx_proc_prome_traffic_handler;
    // 设置循环时间
    ngx_add_timer(loop_event,1000);
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

    return conf;
}



void
ngx_proc_prome_traffic_handler(ngx_event_t *ev){




}