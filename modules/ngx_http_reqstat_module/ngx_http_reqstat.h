#include <nginx.h>
#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


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

struct ngx_http_reqstat_rbnode_s {
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
