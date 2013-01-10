
#ifndef _NGX_HTTP_IPSTAT_MODULE_H_INCLUDED_
#define _NGX_HTTP_IPSTAT_MODULE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct ngx_http_ipstat_vip_s ngx_http_ipstat_vip_t;


#define NGX_HTTP_IPSTAT_CONN_TOTAL   offsetof(ngx_http_ipstat_vip_t, conn_total)
#define NGX_HTTP_IPSTAT_CONN_CURRENT offsetof(ngx_http_ipstat_vip_t, conn_count)
#define NGX_HTTP_IPSTAT_REQ_TOTAL    offsetof(ngx_http_ipstat_vip_t, req_total)
#define NGX_HTTP_IPSTAT_REQ_CURRENT  offsetof(ngx_http_ipstat_vip_t, req_count)
#define NGX_HTTP_IPSTAT_BYTES_IN     offsetof(ngx_http_ipstat_vip_t, bytes_in)
#define NGX_HTTP_IPSTAT_BYTES_OUT    offsetof(ngx_http_ipstat_vip_t, bytes_out)
#define NGX_HTTP_IPSTAT_RT_MIN       offsetof(ngx_http_ipstat_vip_t, rt_min)
#define NGX_HTTP_IPSTAT_RT_MAX       offsetof(ngx_http_ipstat_vip_t, rt_max)
#define NGX_HTTP_IPSTAT_RT_AVG       offsetof(ngx_http_ipstat_vip_t, rt_avg)
#define NGX_HTTP_IPSTAT_CONN_RATE    offsetof(ngx_http_ipstat_vip_t, conn_rate)
#define NGX_HTTP_IPSTAT_REQ_RATE     offsetof(ngx_http_ipstat_vip_t, req_rate)


typedef struct {
    time_t                 rt_interval;
    time_t                 rt_unit;
    ngx_uint_t             workers;
    ngx_uint_t             num;
    size_t                 index_size;
    size_t                 block_size;
    void                  *data;
    ngx_shm_zone_t        *vip_zone;
} ngx_http_ipstat_main_conf_t;


typedef struct {
    ngx_uint_t             int_val;
    double                 val;
} ngx_http_ipstat_avg_t;


typedef struct {
    ngx_uint_t             last_rate;
    ngx_uint_t             curr_rate;
    time_t                 t;
} ngx_http_ipstat_rate_t;


typedef struct {
    ngx_uint_t             val;
    ngx_uint_t             slot[60];
    time_t                 t;
    time_t                 unit;
    unsigned               index:6;
    unsigned               slice:6;
} ngx_http_ipstat_ts_t;


struct ngx_http_ipstat_vip_s {
    ngx_http_ipstat_vip_t *prev;
    ngx_uint_t             conn_total;
    ngx_uint_t             conn_count;
    ngx_uint_t             req_total;
    ngx_uint_t             req_count;
    ngx_uint_t             bytes_in;
    ngx_uint_t             bytes_out;
    ngx_http_ipstat_ts_t   rt_min;
    ngx_http_ipstat_ts_t   rt_max;
    ngx_http_ipstat_avg_t  rt_avg;
    ngx_http_ipstat_rate_t conn_rate;
    ngx_http_ipstat_rate_t req_rate;
};


extern void ngx_http_ipstat_count(void *vip, off_t offset, ngx_int_t incr);
extern void ngx_http_ipstat_min(void *vip, off_t offset, ngx_uint_t val);
extern void ngx_http_ipstat_max(void *vip, off_t offset, ngx_uint_t val);
extern void ngx_http_ipstat_ts_min(void *vip, off_t offset, ngx_uint_t val);
extern void ngx_http_ipstat_ts_max(void *vip, off_t offset, ngx_uint_t val);
extern void ngx_http_ipstat_avg(void *vip, off_t offset, ngx_uint_t val);
extern void ngx_http_ipstat_rate(void *vip, off_t offset, ngx_uint_t val);

extern void ngx_http_ipstat_close_request(void *data);
extern ngx_http_ipstat_vip_t *ngx_http_ipstat_find_vip(ngx_uint_t key);


#endif    /* _NGX_HTTP_IPSTAT_MODULE_H_INCLUDED_ */
