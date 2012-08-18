
#ifndef _NGX_HTTP_STATUS_MODULE_H_INCLUDED_
#define _NGX_HTTP_STATUS_MODULE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


typedef struct ngx_http_status_vip_s ngx_http_status_vip_t;


#define NGX_HTTP_STATUS_CONN_CURRENT        0
#define NGX_HTTP_STATUS_CONN_TOTAL          1
#define NGX_HTTP_STATUS_REQ_CURRENT         2
#define NGX_HTTP_STATUS_REQ_TOTAL           3
#define NGX_HTTP_STATUS_BYTE_IN             4
#define NGX_HTTP_STATUS_BYTE_OUT            5


typedef struct {
    ngx_uint_t             workers;
    ngx_uint_t             num;
    size_t                 index_size;
    size_t                 block_size;
    ngx_shmtx_t            mutex;
    void                  *data;
    ngx_shm_zone_t        *vip_zone;
} ngx_http_status_main_conf_t;


struct ngx_http_status_vip_s {
    ngx_http_status_vip_t *next;
    ngx_uint_t             conn_count;
    ngx_uint_t             conn_total;
    ngx_uint_t             req_count;
    ngx_uint_t             req_total;
    ngx_uint_t             byte_in;
    ngx_uint_t             byte_out;
};


extern void ngx_http_status_count(void *vip, int index, ngx_int_t incr);
extern void ngx_http_status_close_request(void *data);
extern ngx_http_status_vip_t *ngx_http_status_find_vip(ngx_uint_t key);


#endif    /* _NGX_HTTP_STATUS_MODULE_H_INCLUDED_ */
