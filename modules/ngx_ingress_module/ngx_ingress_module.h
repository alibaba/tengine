/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef NGX_INGRESS_MODULE_H
#define NGX_INGRESS_MODULE_H

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_buf.h>

#include <ngx_comm_string.h>
#include <ngx_comm_shm.h>
#include <ngx_proc_strategy_module.h>

typedef struct {
    ngx_msec_t      connect_timeout;
    ngx_msec_t      read_timeout;
    ngx_msec_t      write_timeout;
} ngx_ingress_timeout_t;

typedef struct {
    ngx_int_t       start;
    ngx_int_t       end;

    ngx_str_t       target;
} ngx_ingress_upstream_t;

typedef struct {
    ngx_str_t           key;
    ngx_str_t           value;
} ngx_ingress_metadata_t;

typedef struct {
    ngx_str_t                   name;

    ngx_int_t                   upstream_weight;
    ngx_shm_array_t            *upstreams;   /* ngx_ingress_upstream_t */

    ngx_ingress_timeout_t       timeout;
    ngx_int_t                   force_https;

    ngx_shm_array_t            *metadata;       /* ngx_ingress_metadata_t */
} ngx_ingress_service_t;

typedef struct {
    Ingress__LocationType       location;       /* match field location */
    ngx_str_t                   key;            /* match field name */
    ngx_str_t                   value;          /* match field value */
    Ingress__MatchType          match_type;     /* match field type */
} ngx_ingress_tag_item_t;

typedef struct {
    ngx_shm_array_t        *items;              /* ngx_ingress_tag_item_t */
} ngx_ingress_tag_rule_t;

typedef struct {
    ngx_shm_array_t         *rules;             /* ngx_ingress_tag_rule_t */
    ngx_ingress_service_t   *service;
} ngx_ingress_tag_router_t;

typedef struct {
    ngx_str_t                prefix;
    ngx_shm_array_t         *tags;              /* ngx_ingress_tag_router_t: The number of elements is 0 and assigned to NULL */
    ngx_ingress_service_t   *service;
} ngx_ingress_path_router_t;

typedef struct {
    ngx_str_t                   host;
    ngx_shm_array_t            *paths;          /* ngx_ingress_path_router_t */
    ngx_shm_array_t            *tags;           /* ngx_ingress_tag_router_t: The number of elements is 0 and assigned to NULL */
    ngx_ingress_service_t      *service;
} ngx_ingress_host_router_t;


typedef struct {
    ngx_shm_hash_t      *host_map;                  /* ngx_ingress_host_router_t */
    ngx_shm_hash_t      *wildcard_host_map;         /* ngx_ingress_host_router_t */

    ngx_shm_hash_t      *service_map;               /* ngx_ingress_service_t */

    uint64_t            version;

    ngx_shm_pool_t      *pool;
} ngx_ingress_t;


typedef struct {
    ngx_str_t                        name;

    ngx_str_t                        shm_name;
    ngx_uint_t                       shm_size;

    ngx_str_t                        lock_file;

    ngx_msec_t                       update_check_interval;
    size_t                           pool_size;
    ngx_int_t                        hash_size;

    ngx_ingress_shared_memory_t     *shared;
    ngx_strategy_slot_app_t         *ingress_app;
} ngx_ingress_gateway_t;


typedef struct {
    ngx_array_t                  gateways;  /* ngx_ingress_gateway_t */

    ngx_int_t                    ctx_var_index;
} ngx_ingress_main_conf_t;

typedef struct {
    ngx_ingress_gateway_t *gateway;
} ngx_ingress_loc_conf_t;


ngx_int_t ngx_ingress_update_shm_by_pb(ngx_ingress_gateway_t *gateway, ngx_ingress_shared_memory_config_t *shm_pb_config, ngx_ingress_t *ingress);


#endif // NGX_INGRESS_MODULE_H
