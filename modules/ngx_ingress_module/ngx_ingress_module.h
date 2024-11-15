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

#define NGX_INGRESS_FORCE_HTTPS_UNSET   -1
#define NGX_INGRESS_TIMEOUT_UNSET       0
#define NGX_INGRESS_TIMEOUT_SET         1

typedef struct {
    ngx_msec_t      connect_timeout;
    ngx_msec_t      read_timeout;
    ngx_msec_t      write_timeout;
    ngx_int_t       set_flag;
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

typedef Ingress__LocationType ngx_ingress_tag_value_location_e;
typedef Ingress__MatchType ngx_ingress_tag_match_type_e;
typedef Ingress__OperatorType ngx_ingress_tag_operator_e;
typedef Ingress__ActionType ngx_ingress_action_type_e;
typedef Ingress__ActionValueType ngx_ingress_action_value_type_e; 

typedef struct {
    ngx_str_t                   value_str;
    ngx_shm_array_t            *value_a;        /* ngx_str_t, already sorted */
    ngx_int_t                   divisor;
    ngx_int_t                   remainder;
    ngx_ingress_tag_operator_e  op;
} ngx_ingress_tag_condition_t;

typedef struct {
    ngx_ingress_action_type_e       action_type;
    ngx_ingress_action_value_type_e value_type;
    ngx_str_t                       key;
    ngx_str_t                       value;
} ngx_ingress_action_t;

typedef struct {
    ngx_str_t                   name;

    ngx_int_t                   upstream_weight;
    ngx_shm_array_t            *upstreams;   /* ngx_ingress_upstream_t */

    ngx_ingress_timeout_t       timeout;
    ngx_int_t                   force_https;

    ngx_shm_array_t            *action_a;         /* ngx_ingress_action_t */

    ngx_shm_array_t            *metadata;       /* ngx_ingress_metadata_t */
} ngx_ingress_service_t;

typedef struct {
    ngx_queue_t queue_node;
    ngx_ingress_service_t *service;
} ngx_ingress_service_queue_t;

typedef struct {
    ngx_ingress_tag_value_location_e    location;       /* match field location */
    ngx_str_t                           key;            /* match field name */
    ngx_ingress_tag_match_type_e        match_type;     /* match field type */
    ngx_ingress_tag_condition_t         condition;      /* match condition */ 
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
ngx_int_t ngx_ingress_tag_value_compar(const void *v1, const void *v2);

#endif // NGX_INGRESS_MODULE_H
