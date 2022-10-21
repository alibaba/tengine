#include <nginx.h>
#include<ngx_http_reqstat.h>
#include<ngx_proc.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include<ngx_event.h>

ngx_uint_t          pz_flag;
extern ngx_module_t ngx_http_reqstat_module;
// typedef struct {

//     ngx_uint_t                   flag;
//     ngx_str_t                    buffer[2];

// }ngx_http_prome_shctx_t;

// typedef struct {
//     ngx_str_t                   *val;
//     ngx_uint_t                   p_recycle_rate;
//     ngx_slab_pool_t             *shpool;
//     ngx_http_complex_value_t     value;
//     ngx_http_prome_shctx_t      *sh;  //作为存储prome格式的结构体
// }ngx_http_prome_ctx_t;

// 思路:从cycle中拿到共享内存的地址直接读,读完后将结果输出
typedef struct {
    ngx_flag_t                                             enable;
    ngx_msec_t                                             interval;
    ngx_event_t                                            event;
    ngx_http_reqstat_conf_t                               *rmcf;
} ngx_proc_prome_main_conf_t; 


#define NGX_HTTP_PROME_FMT_KEY_NUMS               29

char* ngx_http_reqstat_fmt_key2[NGX_HTTP_PROME_FMT_KEY_NUMS] = {
    NGX_HTTP_PROME_FMT_BYTES_IN,
    NGX_HTTP_PROME_FMT_BYTES_OUT,
    NGX_HTTP_PROME_FMT_CONN_TATAL,
    NGX_HTTP_PROME_FMT_REQ_TOTAL,
    NGX_HTTP_PROME_FMT_HTTP_2XX,
    NGX_HTTP_PROME_FMT_HTTP_3XX,
    NGX_HTTP_PROME_FMT_HTTP_4XX,
    NGX_HTTP_PROME_FMT_HTTP_5XX,
    NGX_HTTP_PROME_FMT_OTHER_STATUS,
    NGX_HTTP_PROME_FMT_RT,
    NGX_HTTP_PROME_FMT_UPS_REQ,
    NGX_HTTP_PROME_FMT_UPS_RT,
    NGX_HTTP_PROME_FMT_UPS_TRIES,
    NGX_HTTP_PROME_FMT_HTTP_200,
    NGX_HTTP_PROME_FMT_HTTP_206,
    NGX_HTTP_PROME_FMT_HTTP_302,
    NGX_HTTP_PROME_FMT_HTTP_304,
    NGX_HTTP_PROME_FMT_HTTP_403,
    NGX_HTTP_PROME_FMT_HTTP_404,
    NGX_HTTP_PROME_FMT_HTTP_416,
    NGX_HTTP_PROME_FMT_HTTP_499,
    NGX_HTTP_PROME_FMT_HTTP_500 ,
    NGX_HTTP_PROME_FMT_HTTP_502,
    NGX_HTTP_PROME_FMT_HTTP_503,
    NGX_HTTP_PROME_FMT_HTTP_504,
    NGX_HTTP_PROME_FMT_HTTP_508,
    NGX_HTTP_PROME_FMT_HTTP_OTHER_DETAIL_STATUS,
    NGX_HTTP_PROME_FMT_UPS_4XX,
    NGX_HTTP_PROME_FMT_UPS_5XX
};

off_t ngx_http_reqstat_fields2[NGX_HTTP_PROME_FMT_KEY_NUMS] = {
    NGX_HTTP_REQSTAT_BYTES_IN,
    NGX_HTTP_REQSTAT_BYTES_OUT,
    NGX_HTTP_REQSTAT_CONN_TOTAL,
    NGX_HTTP_REQSTAT_REQ_TOTAL,
    NGX_HTTP_REQSTAT_2XX,
    NGX_HTTP_REQSTAT_3XX,
    NGX_HTTP_REQSTAT_4XX,
    NGX_HTTP_REQSTAT_5XX,
    NGX_HTTP_REQSTAT_OTHER_STATUS,
    NGX_HTTP_REQSTAT_RT,
    NGX_HTTP_REQSTAT_UPS_REQ,
    NGX_HTTP_REQSTAT_UPS_RT,
    NGX_HTTP_REQSTAT_UPS_TRIES,
    NGX_HTTP_REQSTAT_200,
    NGX_HTTP_REQSTAT_206,
    NGX_HTTP_REQSTAT_302,
    NGX_HTTP_REQSTAT_304,
    NGX_HTTP_REQSTAT_403,
    NGX_HTTP_REQSTAT_404,
    NGX_HTTP_REQSTAT_416,
    NGX_HTTP_REQSTAT_499,
    NGX_HTTP_REQSTAT_500,
    NGX_HTTP_REQSTAT_502,
    NGX_HTTP_REQSTAT_503,
    NGX_HTTP_REQSTAT_504,
    NGX_HTTP_REQSTAT_508,
    NGX_HTTP_REQSTAT_OTHER_DETAIL_STATUS,
    NGX_HTTP_REQSTAT_UPS_4XX,
    NGX_HTTP_REQSTAT_UPS_5XX
};

static ngx_int_t ngx_proc_prome_prepare(ngx_cycle_t *cycle);
static ngx_int_t ngx_proc_prome_init_worker(ngx_cycle_t *cycle);
static void ngx_proc_prome_exit_worker(ngx_cycle_t *cycle);
// static void *ngx_proc_prome_create_main_conf(ngx_conf_t *cf);
static void *ngx_proc_prome_create_conf(ngx_conf_t *cf);
void ngx_proc_prome_handler (ngx_event_t *ev);
// ngx_shm_zone_t * ngx_shared_memory_add2(ngx_conf_t *cf, ngx_str_t *name, size_t size);
static char *ngx_proc_prome_merge_conf(ngx_conf_t *cf, void *parent, void *child);

// static char *ngx_reqstat_zone_names(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
// static char *ngx_prome_zone_name(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);


static ngx_command_t ngx_proc_prome_commands[] = {

      { ngx_string("start"),
      NGX_PROC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_PROC_CONF_OFFSET,
      offsetof(ngx_proc_prome_main_conf_t, enable),
      NULL },
    
    { ngx_string("interval"),
      NGX_PROC_CONF | NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_PROC_CONF_OFFSET,
      offsetof(ngx_proc_prome_main_conf_t, interval),
      NULL },

    ngx_null_command
};


static ngx_proc_module_t ngx_proc_prome_module_ctx = {
    ngx_string("prome_traffic"),
    NULL,
    NULL,
    ngx_proc_prome_create_conf,
    ngx_proc_prome_merge_conf,
    ngx_proc_prome_prepare,
    ngx_proc_prome_init_worker,
    NULL,
    ngx_proc_prome_exit_worker
};


ngx_module_t ngx_proc_prome_module = {
    NGX_MODULE_V1,
    &ngx_proc_prome_module_ctx,
    ngx_proc_prome_commands,
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
ngx_proc_prome_prepare(ngx_cycle_t *cycle)
{
   ngx_proc_prome_main_conf_t      *pmcf;

    pmcf = ngx_proc_get_conf(cycle->conf_ctx, ngx_proc_prome_module);
     if (!pmcf->enable) {
        return NGX_DECLINED;
    }

    if (pmcf->interval == 0) {
        return NGX_DECLINED;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_proc_prome_init_worker(ngx_cycle_t *cycle)
{
    ngx_event_t                                             *loop_event;
    ngx_http_reqstat_conf_t                                 *rmcf;
    ngx_proc_prome_main_conf_t                              *pmcf;
    // ngx_msec_t                                          time_interval;
    // ngx_http_reqstat_ctx_t                          *ctx;
    // ngx_shm_zone_t                                  **shm_zone;
    // int                                                       reuseaddr;
    // ngx_socket_t                                             fd;
    // ngx_connection_t                                    *c;
    // struct sockaddr_in                                   sin;

    pmcf = ngx_proc_get_conf(cycle->conf_ctx, ngx_proc_prome_module);

    if(pmcf == NULL){
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "init worker pmcf is NULL");
        return NGX_ERROR;
    }

    ngx_log_error(NGX_LOG_ERR,cycle->log, 0, "init worker pmcf is time %i", pmcf->interval);

    rmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_reqstat_module);

    if(rmcf == NULL){
         ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "init worker rmcf is NULL");
         return NGX_ERROR;
    }

    pmcf->rmcf = rmcf;




    // ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "rmcf_monitor*************>%d", rmcf->monitor->nelts);
    // ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "rmcf_pd*************>%d", rmcf->prome_display->nelts);
    // ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "rmcf_pz*************>%d", rmcf->prome_zone->nelts);
    // ngx_log_error(NGX_LOG_ERR,cycle->log, 0, "rmcf*************>%p", ((ngx_shm_zone_t*)rmcf->prome_display->elts));




    loop_event = &pmcf->event;
    loop_event->log = ngx_cycle->log;
    loop_event->data = pmcf;
    loop_event->handler = ngx_proc_prome_handler;
    ngx_add_timer(loop_event,(ngx_msec_t)10000);

    return NGX_OK;
}


static char *
ngx_proc_prome_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_proc_prome_main_conf_t      *prev= parent;
    ngx_proc_prome_main_conf_t      *conf = child;

    ngx_conf_merge_off_value(conf->enable, prev->enable, 0);
    ngx_conf_merge_msec_value(conf->interval, prev->interval, 0);
    return NGX_CONF_OK;
}



static void
ngx_proc_prome_exit_worker(ngx_cycle_t *cycle)
{

}


// static void *
// ngx_proc_prome_create_main_conf(ngx_conf_t *cf)
// {
//     ngx_proc_prome_main_conf_t  *pmcf;

//     pmcf = ngx_pcalloc(cf->pool, sizeof(ngx_proc_prome_main_conf_t));
//     if (pmcf == NULL) {
//         ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
//                            "daytime create proc conf error");
//         return NULL;
//     }
//     pmcf->enable = NGX_CONF_UNSET;
//     pmcf->time_interval = NGX_CONF_UNSET_MSEC;
//     pmcf->port = NGX_CONF_UNSET_UINT;

//     return pmcf;
// }

static void *
ngx_proc_prome_create_conf(ngx_conf_t *cf)
{
    ngx_proc_prome_main_conf_t     *pmcf;

    pmcf = ngx_pcalloc(cf->pool, sizeof(ngx_proc_prome_main_conf_t));
    if (pmcf == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "daytime create proc conf error");
        return NULL;
    }
    pmcf->enable = NGX_CONF_UNSET;
    pmcf->interval = NGX_CONF_UNSET_MSEC;

    return pmcf;
}

void
ngx_proc_prome_handler(ngx_event_t *ev){


    // ngx_int_t                                      rc;
    size_t                                               size;
    size_t                                               per_size;
    size_t                                               nodes;
    size_t                                               host_len,sum;
    ngx_buf_t                                           *b;
    ngx_uint_t                                           i,j;
    ngx_array_t                                         *display_traffic; //指向需要转换的监控节点
    ngx_pool_t                                          *pool;
    ngx_queue_t                                         *q;
    ngx_shm_zone_t                                     **shm_zone; //获取共享内存
    ngx_shm_zone_t                                      *shm_pzone; 
    ngx_http_reqstat_ctx_t                              *ctx; // 获取监控指标以及用户定义的指标类型
    ngx_http_reqstat_conf_t                             *rmcf;
    ngx_http_reqstat_rbnode_t                           *node; // 通过将节点挂载到系统的红黑树上进行获取节点信息
    ngx_proc_prome_main_conf_t                          *pmcf;
    ngx_http_prome_ctx_t                                *pctx;
    // ngx_http_reqstat_rbnode_t             *display_node;
    // ngx_chain_t                                  out,*tl,**cl;
    // ngx_int_t                                       ngx_ret;
    // u_char                                          *o,*s,*p;
    // clock_t                                            start,finish;
    // double                                            duration;

    // 获取指令指针来寻找共享内存
    pmcf = ev->data;
    rmcf = pmcf->rmcf;


     // 直接指向需要监控的指标X
    display_traffic = rmcf->prome_display;
    shm_zone = rmcf->prome_display->elts;

   shm_pzone = rmcf->prome_zone->elts;
   pctx = shm_pzone->data;


    per_size = 0;
    sum = 0;
    size = 0;
    nodes = 0;
    host_len =0;
    
    for(i = 0; i < NGX_HTTP_PROME_FMT_KEY_NUMS; i++) {
        sum += ngx_strlen(ngx_http_reqstat_fmt_key2[i]);
    }

    // per_size = sum;
    // size = 5800;

     for(i = 0; i < display_traffic->nelts; i++) {

        ctx = shm_zone[i]->data;


        for (q = ngx_queue_head(&ctx->sh->queue);
             q != ngx_queue_sentinel(&ctx->sh->queue);
             q = ngx_queue_next(q))
        {
            node = ngx_queue_data(q, ngx_http_reqstat_rbnode_t, queue);

            if(node->conn_total == 0) {
                continue;
            }
            host_len += ngx_strlen(node->data);
            ++nodes;
        }
    }

    if(nodes == 0)
    nodes = 1;
    sum = nodes*(sum+NGX_HTTP_PROME_FMT_KEY_NUMS*(sizeof(ngx_atomic_t)+host_len));

     ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, " due with %zu nums nodes\n", sum);

    pool = ngx_create_pool(NGX_MAX_ALLOC_FROM_POOL, ngx_cycle->log);

    b = ngx_calloc_buf(pool);
    if(b == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "calloc buf error");
    }

     for(i = 0; i < display_traffic->nelts; i++) {
       
        ctx = shm_zone[i]->data;
        // 先打印出共享内存和tengine的信息(可删)
        b->last = ngx_slprintf(b->last, b->end, NGX_HTTP_PROME_FMT_INFO,
                                    &shm_zone[i]->shm.name,
                                    TENGINE_VERSION,NGINX_VERSION);

        for (q = ngx_queue_head(&ctx->sh->queue);
             q != ngx_queue_sentinel(&ctx->sh->queue);
             q = ngx_queue_next(q))
        {
            node = ngx_queue_data(q, ngx_http_reqstat_rbnode_t, queue);

            if(node->conn_total == 0) {
                continue;
            }

            b = ngx_calloc_buf(pool);
            if(b == NULL) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "calloc buf error");
            }

            // 每个结点的大小
            size = per_size+NGX_HTTP_PROME_FMT_KEY_NUMS*(ngx_strlen(node->data)+sizeof(ngx_atomic_t));
            b->start = ngx_pcalloc(pool,size);
            if(b->start == NULL) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "pcalloc b-start error");
            }

            b->end = b->start + size;
            b->last= b->pos = b->start;
            b->temporary = 1;


            for (j = 0;j < NGX_HTTP_PROME_FMT_KEY_NUMS;j++) {
                    b->last = ngx_slprintf(b->last, b->end, ngx_http_reqstat_fmt_key2[j],
                                                node->data, *NGX_HTTP_REQSTAT_REQ_FIELD(node,
                                                ngx_http_reqstat_fields2[j]));
                }
                


                // if (ctx->user_defined) {
                //     for (j = 0; j < ctx->user_defined->nelts; j++) {
                //         b->last = ngx_slprintf(b->last, b->end, "%uA,",
                //                            *NGX_HTTP_REQSTAT_REQ_FIELD(node,
                //                                    NGX_HTTP_REQSTAT_EXTRA(j)));
                //     }
                // }
    
            *(b->last - 1) = '\n';

            // 从这里出现问题
            if(pz_flag % 2 == 1) {
                pctx->sh->buffer1 = ngx_slab_alloc(pctx->shpool, size);
                ngx_memcpy(pctx->sh->buffer1->data, b->start, size);
            }else{
                pctx->sh->buffer2 = ngx_slab_alloc(pctx->shpool, size);
                 ngx_memcpy(pctx->sh->buffer2->data, b->start, size);
            }

        }
    }

    ngx_destroy_pool(pool);
    ngx_add_timer(ev, (ngx_msec_t)10000);
}
