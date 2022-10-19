#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include<ngx_log.h>
#include<nginx.h>


#define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_INFO                      \
    "# HELP tengine_reqstat_info Nginx info\n"                                       \
    "# TYPE tengine_reqstat_info gauge\n"                                            \
    "tengine_reqstat_info{shm_zone=\"%V\",module_version=\"%s\",version=\"%s\"} 1\n" 


#define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_BYTES_IN                      \
"# HELP tengine_reqstat_bytes_in The request bytes\n"         \
"# TYPE tengine_reqstat_bytes_in counter\n"    \
"tengine_reqstat_bytes_in{host=\"%s\"} %uA\n" 


#define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_BYTES_OUT                      \
    "# HELP tengine_reqstat_bytes_out The response bytes\n"         \
    "# TYPE tengine_reqstat_bytes_out counter\n"                                           \
    "tengine_reqstat_bytes_out{host=\"%s\"} %uA\n" 


#define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_CONN_TATAL                      \
    "# HELP tengine_reqstat_conn_total The connections of server\n"         \
    "# TYPE tengine_reqstat_conn_total counter\n"                                           \
    "tengine_reqstat_conn_total{host=\"%s\"} %uA\n" 
   

#define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_REQ_TOTAL                      \
    "# HELP tengine_reqstat_req_total The requests of server\n"         \
    "# TYPE tengine_reqstat_req_total counter\n"                                           \
    "tengine_reqstat_req_total{host=\"%s\"} %uA\n" 
   

    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_2XX                      \
    "# HELP tengine_reqstat_http_2xx The 2xx\n"         \
    "# TYPE tengine_reqstat_http_2xx counter\n"                                           \
    "tengine_reqstat_http_2xx{host=\"%s\"} %uA\n" 


    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_3XX                      \
    "# HELP tengine_reqstat_http_3xx The 2xx\n"         \
    "# TYPE tengine_reqstat_http_3xx counter\n"                                           \
    "tengine_reqstat_http_3xx{host=\"%s\"} %uA\n" 


    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_4XX                      \
    "# HELP tengine_reqstat_http_4xx The 2xx\n"         \
    "# TYPE tengine_reqstat_http_4xx counter\n"                                           \
    "tengine_reqstat_http_4xx{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_5XX                      \
    "# HELP tengine_reqstat_http_5xx The 2xx\n"         \
    "# TYPE tengine_reqstat_http_5xx counter\n"                                           \
    "tengine_reqstat_http_5xx{host=\"%s\"} %uA\n" 
   
     #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_OTHER_STATUS                      \
    "# HELP tengine_reqstat_http_other_status The 2xx\n"         \
    "# TYPE tengine_reqstat_http_other_status counter\n"                                           \
    "tengine_reqstat_http_other_status{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_RT                     \
    "# HELP tengine_reqstat_rt The 2xx\n"         \
    "# TYPE tengine_reqstat_rt counter\n"                                           \
    "tengine_reqstat_rt{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_REQ                      \
    "# HELP tengine_reqstat_ups_req The request/response bytes\n"         \
    "# TYPE tengine_reqstat_ups_req counter\n"                                           \
    "tengine_reqstat_ups_req{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_RT                    \
    "# HELP tengine_reqstat_ups_rt The request/response bytes\n"         \
    "# TYPE tengine_reqstat_ups_rt counter\n"                                           \
    "tengine_reqstat_ups_rt{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_TRIES                      \
    "# HELP tengine_reqstat_ups_tries The request/response bytes\n"         \
    "# TYPE tengine_reqstat_ups_tries counter\n"                                           \
    "tengine_reqstat_ups_tries{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_200                      \
    "# HELP tengine_reqstat_http_200l The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_200 counter\n"                                           \
    "tengine_reqstat_http_200{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_206                      \
    "# HELP tengine_reqstat_http_206 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_206 counter\n"                                           \
    "tengine_reqstat_http_206{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_302                      \
    "# HELP tengine_reqstat_http_302 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_302 counter\n"                                           \
    "tengine_reqstat_http_302{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_304                      \
    "# HELP tengine_reqstat_http_304 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_304 counter\n"                                           \
    "tengine_reqstat_http_304{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_403                      \
    "# HELP tengine_reqstat_http_403 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_403 counter\n"                                           \
    "tengine_reqstat_http_403{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_404                      \
    "# HELP tengine_reqstat_http_404 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_404 counter\n"                                           \
    "tengine_reqstat_http_404{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_416                      \
    "# HELP tengine_reqstat_http_416 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_416 counter\n"                                           \
    "tengine_reqstat_http_416{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_499                      \
    "# HELP tengine_reqstat_http_499 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_499 counter\n"                                           \
    "tengine_reqstat_http_499{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_500                      \
    "# HELP tengine_reqstat_http_500 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_500 counter\n"                                           \
    "tengine_reqstat_http_500{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_502                      \
    "# HELP tengine_reqstat_http_502 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_502 counter\n"                                           \
    "tengine_reqstat_http_502{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_503                     \
    "# HELP tengine_reqstat_http_503 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_503 counter\n"                                           \
    "tengine_reqstat_http_503{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_504                      \
    "# HELP tengine_reqstat_http_504 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_504 counter\n"                                          \
    "tengine_reqstat_http_504{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_508                      \
    "# HELP tengine_reqstat_http_508 The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_508 counter\n"                                           \
    "tengine_reqstat_http_508{host=\"%s\"} %uA\n" 
   

    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_HTTP_OTHER_DETAIL_STATUS                      \
    "# HELP tengine_reqstat_http_other_detail_status The request/response bytes\n"         \
    "# TYPE tengine_reqstat_http_other_detail_status counter\n"                                           \
    "tengine_reqstat_http_other_detail_status{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_4XX                      \
    "# HELP tengine_reqstat_ups_4xx The request/response bytes\n"         \
    "# TYPE tengine_reqstat_ups_4xx counter\n"                                           \
    "tengine_reqstat_ups_4xx{host=\"%s\"} %uA\n" 
   
    #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT_UPS_5XX                     \
    "# HELP tengine_reqstat_ups_5xx The request/response bytes\n"         \
    "# TYPE tengine_reqstat_ups_5xx counter\n"                                           \
    "tengine_reqstat_ups_5xx{host=\"%s\"} %uA\n" 
   

// 名字
/* #define NGX_HTTP_REQSTAT_TRAFFIC_PROME_FMT                      \
    "# HELP tengine_reqstat_info Nginx info\n"                                       \
    "# TYPE tengine_reqstat_info gauge\n"                                            \
    "tengine_reqstat_info{hostname=\"%s\",module_version=\"%s\",version=\"%s\"} 1\n" \
    "# HELP tengine_reqstat_server_bytes_total The request/response bytes\n"         \
    "# TYPE tengine_reqstat_server_bytes_total counter\n"                            \
    "tengine_reqstat_server_bytes_total{host=\"%V\",direction=\"in\"} %uA\n"         \
    "tengine_reqstat_server_bytes_total{host=\"%V\",direction=\"out\"} %uA\n"        \
    "# HELP tengine_reqstat_server_requests_total The requests counter\n"            \
    "# TYPE tengine_reqstat_server_requests_total counter\n"                         \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"conn_total\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"req_total\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"2xx\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"3xx\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"4xx\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"5xx\"} %uA\n"           \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_other_status\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"rt\"} %uA\n"             \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"ups_req\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"ups_rt\"} %uA\n"             \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"ups_tries\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_200\"} %uA\n"             \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_206\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_302\"} %uA\n"               \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_304\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_403\"} %uA\n"             \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_404\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_416\"} %uA\n"         \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_499\"} %uA\n"             \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_500\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_502\"} %uA\n"             \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_503\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_504\"} %uA\n"             \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_508\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_other_detail_status\"} %uA\n"             \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_ups_4xx\"} %uA\n"          \
    "tengine_reqstat_server_requests_total{host=\"%V\",code=\"http_ups_5xx\"} %uA\n"             
 */


 



#define NGX_HTTP_REQSTAT_RSRV    29
#define NGX_HTTP_REQSTAT_MAX     50
#define NGX_HTTP_REQSTAT_USER    NGX_HTTP_REQSTAT_MAX - NGX_HTTP_REQSTAT_RSRV


#define variable_index(str, index)  { ngx_string(str), index }

typedef struct ngx_http_reqstat_rbnode_s ngx_http_reqstat_rbnode_t;

typedef struct variable_index_s variable_index_t;

struct variable_index_s {
    ngx_str_t                    name;
    ngx_int_t                    index;
};

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
    ngx_flag_t                   lazy;
    ngx_array_t                 *monitor;
    ngx_array_t                 *display;
    ngx_array_t                 *bypass;
    ngx_int_t                    index;
    ngx_array_t                 *user_select;
    ngx_array_t                 *user_defined_str;
    ngx_array_t                 *prome_display;
    ngx_array_t                 *prome_zone;
} ngx_http_reqstat_conf_t;


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
} ngx_http_reqstat_ctx_t;


typedef struct {
    ngx_uint_t                   recv;
    ngx_uint_t                   sent;
    ngx_array_t                  monitor_index;
    ngx_array_t                  value_index;
    ngx_flag_t                   bypass;
    ngx_http_reqstat_conf_t     *conf;
} ngx_http_reqstat_store_t;


typedef struct {
    ngx_queue_t                 queue;
}ngx_http_reqstat_prome_traffic_shctx_t;

typedef struct {
    ngx_str_t                                               *val;
    ngx_uint_t                                              p_recycle_rate;
    ngx_slab_pool_t                                     *shpool;
    ngx_http_complex_value_t                        value;
    ngx_http_reqstat_prome_traffic_shctx_t     *sh;  //作为存储prome格式的结构体
    ngx_shm_zone_t                                     **shm_zone;
}ngx_http_reqstat_prome_traffic_ctx_t;


#define NGX_HTTP_REQSTAT_BYTES_IN                                       \
    offsetof(ngx_http_reqstat_rbnode_t, bytes_in)

#define NGX_HTTP_REQSTAT_BYTES_OUT                                      \
    offsetof(ngx_http_reqstat_rbnode_t, bytes_out)

#define NGX_HTTP_REQSTAT_CONN_TOTAL                                     \
    offsetof(ngx_http_reqstat_rbnode_t, conn_total)

#define NGX_HTTP_REQSTAT_REQ_TOTAL                                      \
    offsetof(ngx_http_reqstat_rbnode_t, req_total)

#define NGX_HTTP_REQSTAT_2XX                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_2xx)

#define NGX_HTTP_REQSTAT_3XX                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_3xx)

#define NGX_HTTP_REQSTAT_4XX                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_4xx)

#define NGX_HTTP_REQSTAT_5XX                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_5xx)

#define NGX_HTTP_REQSTAT_OTHER_STATUS                                   \
    offsetof(ngx_http_reqstat_rbnode_t, other_status)

#define NGX_HTTP_REQSTAT_200                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_200)

#define NGX_HTTP_REQSTAT_206                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_206)

#define NGX_HTTP_REQSTAT_302                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_302)

#define NGX_HTTP_REQSTAT_304                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_304)

#define NGX_HTTP_REQSTAT_403                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_403)

#define NGX_HTTP_REQSTAT_404                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_404)

#define NGX_HTTP_REQSTAT_416                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_416)

#define NGX_HTTP_REQSTAT_499                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_499)

#define NGX_HTTP_REQSTAT_500                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_500)

#define NGX_HTTP_REQSTAT_502                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_502)

#define NGX_HTTP_REQSTAT_503                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_503)

#define NGX_HTTP_REQSTAT_504                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_504)

#define NGX_HTTP_REQSTAT_508                                            \
    offsetof(ngx_http_reqstat_rbnode_t, http_508)

#define NGX_HTTP_REQSTAT_OTHER_DETAIL_STATUS                            \
    offsetof(ngx_http_reqstat_rbnode_t, other_detail_status)

#define NGX_HTTP_REQSTAT_RT                                             \
    offsetof(ngx_http_reqstat_rbnode_t, rt)

#define NGX_HTTP_REQSTAT_UPS_REQ                                        \
    offsetof(ngx_http_reqstat_rbnode_t, ureq)

#define NGX_HTTP_REQSTAT_UPS_RT                                         \
    offsetof(ngx_http_reqstat_rbnode_t, urt)

#define NGX_HTTP_REQSTAT_UPS_TRIES                                      \
    offsetof(ngx_http_reqstat_rbnode_t, utries)

#define NGX_HTTP_REQSTAT_UPS_4XX                                        \
    offsetof(ngx_http_reqstat_rbnode_t, http_ups_4xx)

#define NGX_HTTP_REQSTAT_UPS_5XX                                        \
    offsetof(ngx_http_reqstat_rbnode_t, http_ups_5xx)

#define NGX_HTTP_REQSTAT_EXTRA(slot)                                    \
    (offsetof(ngx_http_reqstat_rbnode_t, extra)                         \
         + sizeof(ngx_atomic_t) * slot)

#define NGX_HTTP_REQSTAT_REQ_FIELD(node, offset)                        \
    ((ngx_atomic_t *) ((char *) node + offset))


ngx_http_reqstat_rbnode_t *
    ngx_http_reqstat_rbtree_lookup(ngx_shm_zone_t *shm_zone, ngx_str_t *val);

