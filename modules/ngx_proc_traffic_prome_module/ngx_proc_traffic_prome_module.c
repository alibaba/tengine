#include <nginx.h>
#include<ngx_proc.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_config.h>
#include<ngx_channel.h>
#include<ngx_http_reqstat.h>

#define NGX_HTTP_REQSTAT_RSRV    29
#define NGX_HTTP_REQSTAT_MAX     50
#define NGX_HTTP_REQSTAT_USER    NGX_HTTP_REQSTAT_MAX - NGX_HTTP_REQSTAT_RSRV



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

typedef struct ngx_http_reqstat_rbnode_s ngx_http_reqstat_rbnode_t;

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
    // ngx_proc_prome_traffic_main_conf_t     *conf;
} ngx_http_reqstat_store_t;


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
    // 获取reqstat的共享内存名称
    ngx_array_t                                         *req_zone_names;
    // 获取prome的共享内存名称
    ngx_array_t                                         *pre_zone_name;
    
} ngx_proc_prome_traffic_main_conf_t; 


#define NGX_HTTP_REQSTAT_FMT_KEY_NUMS               29

char* ngx_http_reqstat_fmt_key[29] = {
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

off_t ngx_http_reqstat_fields[29] = {
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


static char *ngx_reqstat_zone_names(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_prome_zone_name(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);


static ngx_command_t ngx_proc_prome_traffic_commands[] = {
    { ngx_string("traffic_timeout"),
      NGX_PROC_CONF | NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_PROC_CONF_OFFSET,
      offsetof(ngx_proc_prome_traffic_main_conf_t, time_out),
      NULL,
    },

    { ngx_string("reqstat_zone"),
      NGX_PROC_CONF | NGX_CONF_1MORE,
      ngx_reqstat_zone_names,
      NGX_PROC_CONF_OFFSET,
      NULL,
      NULL,
    },

   { ngx_string("prome_zone"),
      NGX_PROC_CONF | NGX_CONF_TAKE1,
      ngx_prome_zone_name,
      NGX_PROC_CONF_OFFSET,
      NULL,
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
    ngx_msec_t                                          time_out;
    ngx_event_t                                         *loop_event;
    ngx_http_reqstat_ctx_t                          *ctx;
    ngx_shm_zone_t                                  **shm_zone;
    ngx_proc_prome_traffic_main_conf_t      *pmcf,*plcf;
    // 疑问:两者接口的区别?
    pmcf = ngx_proc_get_main_conf(cycle->conf_ctx,ngx_proc_traffic_prome_module);
    plcf   = ngx_proc_get_conf(cycle->conf_ctx,ngx_proc_traffic_prome_module);
    
    // 拿到全局变量中reqstat已有的共享内存,赋值给二级指针,在后续进行遍历
    // shm_zone = cycle->shared_memory.last->elts;
    // 设置事件循环时间
    time_out = plcf->time_out;
    // 注册共享内存的首地址

    loop_event = &ctx->loop_event;
    loop_event->log = ngx_cycle->log;
    loop_event->data = pmcf;
    loop_event->handler = ngx_proc_prome_traffic_handler;
    // 设置循环时间
    ngx_add_timer(loop_event,time_out);
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
    conf->pre_zone_name = NGX_CONF_UNSET_PTR;
    conf->req_zone_names = NGX_CONF_UNSET_PTR;
    return conf;
}



void
ngx_proc_prome_traffic_handler(ngx_event_t *ev){

    ngx_buf_t                                                 *b;
    ngx_uint_t                                                i,j;
    ngx_array_t                                              *display_traffic;
    ngx_queue_t                                            *q;
    ngx_shm_zone_t                                      **shm_zone;
    ngx_http_reqstat_ctx_t                              *ctx;
    ngx_proc_reqstat_prome_traffic_ctx_t         *pctx;
    ngx_proc_prome_traffic_main_conf_t          *ptmf;
    ngx_http_reqstat_rbnode_t                        *node; // 通过将节点挂载到系统的红黑树上进行获取节点信息
    size_t                                                      size,nodes;
    size_t                                                       host_len;


    // plcf   = ngx_proc_get_conf(cycle->conf_ctx,ngx_proc_traffic_prome_module);
    // 这里获取其指令
    ptmf = ev->data;
    
    

    // 直接指向需要监控的指标X
    display_traffic = ptmf->req_zone_names;

    shm_zone = ptmf->req_zone_names->elts;

    size = 0;
    nodes = 0;
    host_len =0;
    
    for(i = 0;i < NGX_HTTP_REQSTAT_FMT_KEY_NUMS;i++) {
        size += ngx_strlen(ngx_http_reqstat_fmt_key[i]);
    }

    
    // size = 5800;

     for(i = 0;i < display_traffic->nelts;i++) {

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
    size = nodes*(size+NGX_HTTP_REQSTAT_FMT_KEY_NUMS*(sizeof(ngx_atomic_t)+host_len));


    b = ngx_calloc_buf(r->pool);
    if(b == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }
    b->start = ngx_pcalloc(r->pool,size);
    if(b->start == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    b->end = b->start + size;
    b->last= b->pos = b->start;
    b->temporary = 1;

            
    // 循环遍历每一个已有的共享内存,将里面的内容按照prome的格式写入到prome_zone中
    for(i = 0;i < display_traffic->nelts;i++) {
        // 如果遍历到prome_zone name 则跳过
        // if(rlcf->prome_display->elts != shm_zone[i]) continue;

        ctx = shm_zone[i]->data;
        // 先打印出共享内存和tengine的信息(可删)
        b->last = ngx_slprintf(b->last,b->end,NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_INFO,
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

            for (j = 0; j < NGX_HTTP_REQSTAT_FMT_KEY_NUMS;j++) {
                    b->last = ngx_slprintf(b->last, b->end, ngx_http_reqstat_fmt_key[j],
                                                node->data, *NGX_HTTP_REQSTAT_REQ_FIELD(node,
                                                ngx_http_reqstat_fields[j]));
                }


            if(b->last == b->pos) {
                b->last = ngx_sprintf(b->last,"#");
            }
            *(b->last - 1) = '\n';
        }
    }

}

static char *
ngx_reqstat_zone_names(ngx_conf_t *cf, ngx_command_t *cmd, void *conf){
    ngx_str_t                    *value;
    ngx_uint_t                    i;
    ngx_shm_zone_t               *shm_zone, **z;
    ngx_proc_prome_traffic_main_conf_t     *ptmf = conf;

    value = cf->args->elts;

    if (ptmf->req_zone_names != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    if (cf->args->nelts == 1) {
        return NGX_CONF_ERROR;
    }

    ptmf->req_zone_names = ngx_array_create(cf->pool, cf->args->nelts - 1,
                                     sizeof(ngx_shm_zone_t *));
    if (ptmf->req_zone_names == NULL) {
        return NGX_CONF_ERROR;
    }

    for (i = 1; i < cf->args->nelts; i++) {
        shm_zone = ngx_shared_memory_add2(cf, &value[i], 0);
        if (shm_zone == NULL) {
            return NGX_CONF_ERROR;
        }

        z = ngx_array_push(ptmf->req_zone_names);
        *z = shm_zone;
    }

    return NGX_CONF_OK;
}

static char *ngx_prome_zone_name(ngx_conf_t *cf, ngx_command_t *cmd, void *conf){

    ngx_str_t                    *value;
    ngx_uint_t                    i;
    ngx_shm_zone_t               *shm_zone, **z;
    ngx_proc_prome_traffic_main_conf_t     *ptmf = conf;

    value = cf->args->elts;

    if (ptmf->pre_zone_name != NGX_CONF_UNSET_PTR) {
        return "is duplicate";
    }

    if (cf->args->nelts == 1) {
        return NGX_CONF_ERROR;
    }

    ptmf->pre_zone_name = ngx_array_create(cf->pool, cf->args->nelts - 1,
                                     sizeof(ngx_shm_zone_t *));
    if (ptmf->pre_zone_name == NULL) {
        return NGX_CONF_ERROR;
    }

    for (i = 1; i < cf->args->nelts; i++) {
        shm_zone = ngx_shared_memory_add2(cf, &value[i], 0);
        if (shm_zone == NULL) {
            return NGX_CONF_ERROR;
        }

        z = ngx_array_push(ptmf->pre_zone_name);
        *z = shm_zone;
    }

    return NGX_CONF_OK;

}


ngx_shm_zone_t *
ngx_shared_memory_add2(ngx_conf_t *cf, ngx_str_t *name, size_t size)
{
    ngx_uint_t i;
    // 代表一块共享内存
    ngx_shm_zone_t *shm_zone;
    ngx_list_part_t *part;
 
    part = &cf->cycle->shared_memory.part;
    shm_zone = part->elts;
 
    // 先遍历shared_memory链表，检测是否有与name相冲突的共享内存，
    // 若name和size一样的，则直接返回该共享内存
    for (i=0; /* void */; i++) {
        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            shm_zone = part->elts;
            i = 0;
        }
    
        if (name->len != shm_zone[i].shm.name.len) {
            continue;     
        }
 
        if (ngx_strncmp(name->data, shm_zone[i].shm.name.data, name->len) != 0) {
            continue;
        }
 
        // if (tag != shm_zone[i].tag) {
        //     return NULL;
        // }
 
        if (shm_zone[i].shm.size == 0) {
            shm_zone[i].shm.size = size;
        }
 
        if (size && size != shm_zone[i].shm.size) {
            return NULL;
        }
 
        return &shm_zone[i];
    }
 
    // // 从shared_memory链表中取出一个空闲项
    // shm_zone = ngx_list_push(&cf->cycle->shared_memory);
 
    // if (shm_zone == NULL) {
    //     return NULL;
    // }
 
    // //返回该表示共享内存的结构体
    // return shm_zone;
    return NULL;
}