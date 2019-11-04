
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */

#ifndef _NGX_DUBBO_H_
#define _NGX_DUBBO_H_

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_event_connect.h>
#include "ngx_multi_upstream_module.h"

int ngx_dubbo_is_big_endian();

#define ngx_dubbo_swap64(val) (((val) >> 56)   |\
        (((val) & 0x00ff000000000000ll) >> 40) |\
        (((val) & 0x0000ff0000000000ll) >> 24) |\
        (((val) & 0x000000ff00000000ll) >> 8)  |\
        (((val) & 0x00000000ff000000ll) << 8)  |\
        (((val) & 0x0000000000ff0000ll) << 24) |\
        (((val) & 0x000000000000ff00ll) << 40) |\
        (((val) << 56)))

#define ngx_dubbo_hton64(val) ngx_dubbo_is_big_endian() ? val : ngx_dubbo_swap64(val)
#define ngx_dubbo_ntoh64(val) ngx_dubbo_hton64(val)

#if (NGX_HAVE_PACK_PRAGMA)
#pragma pack(push, 1)
#elif (NGX_SOLARIS)
#pragma pack(1)
#else
#error "dubbo module needs structure packing pragma support"
#endif

typedef struct
{
    u_char magic_0;
    u_char magic_1;
    u_char type;
    u_char status;

    uint64_t reqid;

    uint32_t payloadlen;
} ngx_dubbo_header_t;

typedef struct {
    ngx_dubbo_header_t header;

    u_char *payload;
} ngx_dubbo_req_t;

typedef struct {
    ngx_dubbo_header_t header;

    u_char*  payload;
    size_t   payload_alloc; 
} ngx_dubbo_resp_t;

#if (NGX_HAVE_PACK_PRAGMA)
#pragma pack(pop)
#elif (NGX_SOLARIS)
#pragma pack()
#else
#error "dubbo module needs structure packing pragma support"
#endif

#define MAGIC_VALUE_0                 0xda
#define MAGIC_VALUE_1                 0xbb
#define DUBBO_FLAG_REQ                0x80
#define DUBBO_FLAG_TWOWAY             0x40
#define DUBBO_FLAG_PING               0x20

typedef enum {
    DUBBO_PARSE_READ_HEADER = 0,
    DUBBO_PARSE_READ_PAYLOAD = 1,
} ngx_dubbo_parse_state_t;

typedef struct {
    ngx_pool_t                     *temp_pool;


    ngx_log_t                      *log;

    void*                          *data;

    ngx_int_t                       last_request_id;

    ngx_flag_t                      read_header;
    ngx_dubbo_resp_t                resp;

    ngx_dubbo_parse_state_t         parse_state;
    size_t                          remain;

    ngx_event_t                     ping_event;
} ngx_dubbo_connection_t;

typedef enum {
    DUBBO_ARG_STR=0,
    DUBBO_ARG_INT,
    DUBBO_ARG_LSTR,
    DUBBO_ARG_MAP,

    DUBBO_ARG_MAX
} ngx_dubbo_arg_type_t;

typedef struct {
    ngx_dubbo_arg_type_t type;

    union ngx_dubbo_value_t {
        int          n;
        ngx_str_t    str;
        ngx_array_t *pstr;
        ngx_array_t *m;
    } value;
} ngx_dubbo_arg_t;

ngx_int_t ngx_dubbo_encode_request(ngx_dubbo_connection_t *dubbo_c, ngx_str_t *service_name, ngx_str_t *service_version, ngx_str_t *method_name, ngx_array_t *args, ngx_multi_request_t *multi_r);
ngx_int_t ngx_dubbo_encode_ping_request(ngx_dubbo_connection_t *dubbo_c, ngx_multi_request_t *multi_r);
ngx_int_t ngx_dubbo_decode_response(ngx_dubbo_connection_t *dubbo_c, ngx_chain_t *in);

ngx_int_t ngx_dubbo_hessian2_encode_str(ngx_pool_t *pool, ngx_str_t *in, ngx_str_t *out);
ngx_int_t ngx_dubbo_hessian2_encode_int(ngx_pool_t *pool, int n, ngx_str_t *out);
ngx_int_t ngx_dubbo_hessian2_encode_lstr(ngx_pool_t *pool, ngx_array_t *lstr, ngx_str_t *out);
ngx_int_t ngx_dubbo_hessian2_encode_map(ngx_pool_t *pool, ngx_array_t *in, ngx_str_t *out);

ngx_int_t ngx_dubbo_hessian2_decode_str(ngx_pool_t *pool, ngx_str_t *in, ngx_str_t *result, ngx_log_t *log);
ngx_int_t ngx_dubbo_hessian2_decode_payload_map(ngx_pool_t *pool, ngx_str_t *in, ngx_array_t **result, ngx_log_t *log);
ngx_int_t ngx_dubbo_hessian2_encode_payload_map(ngx_pool_t *pool, ngx_array_t *in, ngx_str_t *out);

ngx_dubbo_connection_t* ngx_dubbo_create_connection(ngx_connection_t *c, ngx_event_handler_pt ping_handler);
ngx_int_t ngx_dubbo_init_connection(ngx_dubbo_connection_t *dubbo_c, ngx_connection_t *c, ngx_event_handler_pt ping_handler);

#endif /* _NGX_DUBBO_H_ */
