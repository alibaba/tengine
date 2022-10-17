#include <nginx.h>
#include<ngx_proc.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include<ngx_channel.h>
#include<stdio.h>
#include<ngx_http_reqstat.h>

extern ngx_module_t ngx_http_reqstat_module;

typedef struct {
    ngx_queue_t                 queue;
}ngx_proc_reqstat_prome_traffic_shctx_t;

typedef struct {
    ngx_str_t                                               *val;
    ngx_slab_pool_t                                     *shpool;
    ngx_proc_reqstat_prome_traffic_shctx_t     *sh;  //作为存储prome格式的结构体
    ngx_shm_zone_t                                     **shm_zone;
}ngx_proc_reqstat_prome_traffic_ctx_t;

// 思路:从cycle中拿到共享内存的地址直接读,读完后将结果输出
typedef struct {
    ngx_msec_t                                          time_out;
    ngx_event_t                                          loop_event;
    // ngx_http_reqstat_conf_t                           *rlcf;
} ngx_proc_prome_traffic_main_conf_t; 


#define NGX_HTTP_REQSTAT_FMT_KEY_NUMS               29

char* ngx_http_reqstat_fmt_key2[29] = {
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_BYTES_IN,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_BYTES_OUT,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_CONN_TATAL,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_REQ_TOTAL,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_2XX,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_3XX,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_4XX,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_5XX,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_OTHER_STATUS,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_RT,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_REQ,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_RT,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_TRIES,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_200,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_206,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_302,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_304,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_403,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_404,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_416,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_499,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_500 ,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_502,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_503,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_504,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_508,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_OTHER_DETAIL_STATUS,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_4XX,
    NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_5XX
};

off_t ngx_http_reqstat2_fields[29] = {
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

static ngx_int_t ngx_proc_prome_traffic_prepare(ngx_cycle_t *cycle);
static void ngx_proc_prome_traffic_exit_worker(ngx_cycle_t *cycle);
static ngx_int_t ngx_proc_prome_traffic_init_worker(ngx_cycle_t *cycle);
static void * ngx_proc_prome_traffic_create_main_conf(ngx_conf_t *cf);
void ngx_proc_prome_traffic_handler (ngx_event_t *ev);
ngx_shm_zone_t * ngx_shared_memory_add2(ngx_conf_t *cf, ngx_str_t *name, size_t size);


// static char *ngx_reqstat_zone_names(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
// static char *ngx_prome_zone_name(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);


static ngx_command_t ngx_proc_prome_traffic_commands[] = {
    // { ngx_string("traffic_timeout"),
    //   NGX_PROC_CONF | NGX_CONF_TAKE1,
    //   ngx_conf_set_msec_slot,
    //   NGX_PROC_CONF_OFFSET,
    //   offsetof(ngx_proc_prome_traffic_main_conf_t, time_out),
    //   NULL,
    // },

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
    // ngx_msec_t                                          time_out;
    ngx_event_t                                         *loop_event;
    // ngx_http_reqstat_ctx_t                          *ctx;
    // ngx_shm_zone_t                                  **shm_zone;
    ngx_proc_prome_traffic_main_conf_t      *pmcf;
    // ngx_http_reqstat_conf_t                        *rlcf;
    // 疑问:两者接口的区别?
    pmcf = ngx_proc_get_main_conf(cycle->conf_ctx,ngx_proc_traffic_prome_module);

    
    if(pmcf == NULL){
        printf("null****************************************************\n");
        return NGX_ERROR;
    }


    // rlcf = ngx_http_cycle_get_module_main_conf(ngx_cycle,ngx_http_reqstat_module);
    
    // if(rlcf == NULL){
    //     printf("rlcfnull**********************************\n");
    //     return NGX_ERROR;
    // }
    // printf("%ld\n",rlcf->prome_display->nelts);



    // 拿到全局变量中reqstat已有的共享内存,赋值给二级指针,在后续进行遍历
    // shm_zone = cycle->shared_memory.last->elts;
    // 设置事件循环时间
    // time_out = pmcf->time_out;
    // 注册共享内存的首地址

    loop_event = &pmcf->loop_event;
    loop_event->log = ngx_cycle->log;
    loop_event->data = pmcf;
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

    conf->time_out = 0;
    return conf;
}



void
ngx_proc_prome_traffic_handler(ngx_event_t *ev){

    //  ngx_buf_t                                                 *b;
    // ngx_uint_t                                                i,j;
    // ngx_array_t                                              *display_traffic;
    // ngx_queue_t                                            *q;
    // ngx_shm_zone_t                                      **shm_zone;
    // ngx_http_reqstat_ctx_t                              *ctx;
    // ngx_http_reqstat_conf_t                            *rlcf;
    // // ngx_proc_reqstat_prome_traffic_ctx_t         *pctx;
    // // ngx_proc_prome_traffic_main_conf_t          *ptmf;
    // ngx_http_reqstat_rbnode_t                        *node; // 通过将节点挂载到系统的红黑树上进行获取节点信息
    // size_t                                                      size,nodes;
    // size_t                                                       host_len;


    // rlcf = ev->data;


    // plcf   = ngx_proc_get_conf(cycle->conf_ctx,ngx_proc_traffic_prome_module);
    // 这里获取其指令

    
    

    // 直接指向需要监控的指标X


    // size = 0;
    // nodes = 0;
    // host_len =0;
    
    // for(i = 0;i < NGX_HTTP_REQSTAT_FMT_KEY_NUMS;i++) {
    //     size += ngx_strlen(ngx_http_reqstat_fmt_key[i]);
    // }

    
    // // size = 5800;

    //  for(i = 0;i < display_traffic->nelts;i++) {

    //     ctx = shm_zone[i]->data;


    //     for (q = ngx_queue_head(&ctx->sh->queue);
    //          q != ngx_queue_sentinel(&ctx->sh->queue);
    //          q = ngx_queue_next(q))
    //     {
    //         node = ngx_queue_data(q, ngx_http_reqstat_rbnode_t, queue);

    //         if(node->conn_total == 0) {
    //             continue;
    //         }
    //         host_len += ngx_strlen(node->data);
    //         ++nodes;
    //     }
    // }

    // if(nodes == 0)
    // nodes = 1;
    // size = nodes*(size+NGX_HTTP_REQSTAT_FMT_KEY_NUMS*(sizeof(ngx_atomic_t)+host_len));


    // b = ngx_calloc_buf(r->pool);
    // if(b == NULL) {
    //     return NGX_HTTP_INTERNAL_SERVER_ERROR;
    // }
    // b->start = ngx_pcalloc(r->pool,size);
    // if(b->start == NULL) {
    //     return NGX_HTTP_INTERNAL_SERVER_ERROR;
    // }

    // b->end = b->start + size;
    // b->last= b->pos = b->start;
    // b->temporary = 1;

            
    // // 循环遍历每一个已有的共享内存,将里面的内容按照prome的格式写入到prome_zone中
    // for(i = 0;i < display_traffic->nelts;i++) {
    //     // 如果遍历到prome_zone name 则跳过
    //     // if(rlcf->prome_display->elts != shm_zone[i]) continue;

    //     ctx = shm_zone[i]->data;
    //     // 先打印出共享内存和tengine的信息(可删)
    //     b->last = ngx_slprintf(b->last,b->end,NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_INFO,
    //                                 &shm_zone[i]->shm.name,
    //                                 TENGINE_VERSION,NGINX_VERSION);

    //     for (q = ngx_queue_head(&ctx->sh->queue);
    //          q != ngx_queue_sentinel(&ctx->sh->queue);
    //          q = ngx_queue_next(q))
    //     {
    //         node = ngx_queue_data(q, ngx_http_reqstat_rbnode_t, queue);

    //         if(node->conn_total == 0) {
    //             continue;
    //         }

    //         for (j = 0; j < NGX_HTTP_REQSTAT_FMT_KEY_NUMS;j++) {
    //                 b->last = ngx_slprintf(b->last, b->end, ngx_http_reqstat_fmt_key[j],
    //                                             node->data, *NGX_HTTP_REQSTAT_REQ_FIELD(node,
    //                                             ngx_http_reqstat_fields[j]));
    //             }


    //         if(b->last == b->pos) {
    //             b->last = ngx_sprintf(b->last,"#");
    //         }
    //         *(b->last - 1) = '\n';
    //     }
    // }

}




