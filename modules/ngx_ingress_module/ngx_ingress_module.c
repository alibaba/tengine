
/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_buf.h>

#include <ngx_comm_string.h>
#include <ngx_comm_shm.h>

#include <ngx_ingress_protobuf.h>

#include <ngx_ingress_module.h>

#ifdef T_HTTP_VIPSERVER_MODULE
#include <ngx_http_vipserver.h>
#endif

#define NGX_INGRESS_UPDATE_INTERVAL             (30 * 1000)
#define NGX_INGRESS_SHM_POOL_SIZE               (32 * 1024 * 1024)
#define NGX_INGRESS_HASH_SIZE                   1323323
#define NGX_INGRESS_GATEWAY_MAX_NAME_BUF_LEN    255
#define NGX_INGRESS_DEFAULT_GATEWAY_NUM         10

#define NGX_INGRESS_CTX_VAR          "__ingress_ctx__"

static ngx_int_t ngx_ingress_add_variables(ngx_conf_t *cf);
static ngx_int_t ngx_ingress_ctx_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static char *ngx_conf_set_ingress_gateway(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static void ngx_ingress_exit_process(ngx_cycle_t *cycle);

static char *ngx_ingress_gateway_set_msec_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_ingress_gateway_set_num_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_ingress_gateway_set_size_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_ingress_gateway_shm_config(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_ingress_route_target_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_ingress_force_https_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_ingress_get_time_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static char *ngx_ingress_gateway_metadata(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

typedef struct {
    ngx_int_t   initialized;

    ngx_str_t   target;
    ngx_int_t   force_https;

    ngx_msec_t  connect_timeout;
    ngx_msec_t  read_timeout;
    ngx_msec_t  write_timeout;

    ngx_array_t metadata;      /* ngx_ingress_metadata_t */
} ngx_ingress_ctx_t;

/* function declare */
static void * ngx_ingress_create_main_conf(ngx_conf_t *cf);

static void * ngx_ingress_create_loc_conf(ngx_conf_t *cf);
static char * ngx_ingress_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child);
static char * ngx_ingress_init_main_conf(ngx_conf_t *cf, void *conf);

check_update_status ngx_ingress_check_update(void * context, void * data);
ngx_int_t ngx_ingress_update(ngx_cycle_t *cycle, void * context, ngx_shm_pool_t * pool, void * data, ngx_int_t print_detail);

static ngx_command_t ngx_ingress_commands[] = {
    { ngx_string("ingress_gateway"),
      NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_ingress_gateway,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("ingress_gateway_update_interval"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_ingress_gateway_set_msec_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_ingress_gateway_t, update_check_interval),
      NULL },

    { ngx_string("ingress_gateway_hash_num"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_ingress_gateway_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_ingress_gateway_t, hash_size),
      NULL },
    
    { ngx_string("ingress_gateway_pool_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_ingress_gateway_set_size_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_ingress_gateway_t, pool_size),
      NULL },

    { ngx_string("ingress_gateway_shm_config"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE4,
      ngx_ingress_gateway_shm_config,
      NGX_HTTP_MAIN_CONF_OFFSET,
      0,
      NULL },
    
    { ngx_string("ingress_gateway_metadata"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_ingress_gateway_metadata,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },
    
    ngx_null_command
};

static ngx_http_module_t ngx_ingress_module_ctx = {
    ngx_ingress_add_variables,          /* preconfiguration */
    NULL,                               /* postconfiguration */

    ngx_ingress_create_main_conf,       /* create main configuration */
    ngx_ingress_init_main_conf,         /* init main configuration */

    NULL,                               /* create server configuration */
    NULL,                               /* merge server configuration */

    ngx_ingress_create_loc_conf,        /* create location configuration */
    ngx_ingress_merge_loc_conf          /* merge location configuration */
};

ngx_module_t ngx_ingress_module = {
    NGX_MODULE_V1,
    &ngx_ingress_module_ctx,                    /* module context */
    ngx_ingress_commands,                       /* module directives */
    NGX_HTTP_MODULE,                            /* module type */
    NULL,                                       /* init master */
    NULL,                                       /* init module */
    NULL,                                       /* init process */
    NULL,                                       /* init thread */
    NULL,                                       /* exit thread */
    ngx_ingress_exit_process,                   /* exit process */
    NULL,                                       /* exit master */
    NGX_MODULE_V1_PADDING
};


static void *
ngx_ingress_create_main_conf(ngx_conf_t *cf)
{
    ngx_ingress_main_conf_t  *conf;
    ngx_int_t                 rc;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_ingress_main_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    rc = ngx_array_init(&conf->gateways,
                        cf->pool,
                        NGX_INGRESS_DEFAULT_GATEWAY_NUM,
                        sizeof(ngx_ingress_gateway_t));
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                "|ingress|create main gaetways array failed|");
        return NULL;
    }

    conf->ctx_var_index = NGX_CONF_UNSET;

    return conf;
}

static char *
ngx_ingress_init_main_conf(ngx_conf_t *cf, void *conf)
{
    ngx_ingress_main_conf_t     *imcf = (ngx_ingress_main_conf_t*)conf;
    ngx_strategy_slot_app_t     app;

    ngx_str_t                   gw_prefix = ngx_string("ingress_gateway_");
    ngx_uint_t                  i;

    u_char                      name_buf[NGX_INGRESS_GATEWAY_MAX_NAME_BUF_LEN];
    size_t                      name_len;


    ngx_ingress_gateway_t *gateway = (ngx_ingress_gateway_t *)imcf->gateways.elts;
    for (i = 0; i < imcf->gateways.nelts; i++) {
        /* check config valid */
        if (gateway[i].shm_name.len == 0
            || gateway[i].shm_size == 0)
        {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                    "|ingress|gateway %V is not configured|", &gateway[i].name);
            return NGX_CONF_ERROR;
        }

        /* attach shared memory */
        gateway[i].shared = ngx_ingress_shared_memory_create(&gateway[i].shm_name, gateway[i].shm_size, &gateway[i].lock_file);
        if (gateway[i].shared == NULL) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                    "|ingress|gateway %V is open shared failed|", &gateway[i].name);
            return NGX_CONF_ERROR;
        }

        /* set default value */
        ngx_conf_init_msec_value(gateway[i].update_check_interval, NGX_INGRESS_UPDATE_INTERVAL);
        ngx_conf_init_size_value(gateway[i].pool_size, NGX_INGRESS_SHM_POOL_SIZE);
        ngx_conf_init_value(gateway[i].hash_size, NGX_INGRESS_HASH_SIZE);

        /* register double buffered shared memory */
        memset(&app, 0, sizeof(app));
        if (gw_prefix.len + gateway[i].name.len >=  NGX_INGRESS_GATEWAY_MAX_NAME_BUF_LEN) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                "|ingress|gateway name %V is too long|", &gateway[i].name);
            return NGX_CONF_ERROR;
        }

        name_len = ngx_snprintf(name_buf, NGX_INGRESS_GATEWAY_MAX_NAME_BUF_LEN, "%V%V", &gw_prefix, &gateway[i].name) - name_buf;
        
        app.frame_ctx.name.data = name_buf;
        app.frame_ctx.name.len = name_len;
        app.frame_ctx.interval = gateway[i].update_check_interval;
        app.data = &gateway[i];
        app.check_update = ngx_ingress_check_update;
        app.update = ngx_ingress_update;
        app.slot_size = sizeof(ngx_ingress_t);
        app.pool_size = gateway[i].pool_size;
        app.shm_warn_mem_rate = 0;

        gateway[i].ingress_app = ngx_strategy_slot_app_register(cf, &app);
        if (gateway[i].ingress_app == NULL) {
            ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                    "|ingress|register strategy ingress_app failed");
            return NGX_CONF_ERROR;
        }
    }

    ngx_str_t ngx_ingress_ctx_name = ngx_string(NGX_INGRESS_CTX_VAR);
    imcf->ctx_var_index = ngx_http_get_variable_index(cf, &ngx_ingress_ctx_name);
    if (imcf->ctx_var_index == NGX_ERROR) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                      "|ingress|ctx_var_index failed|");
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}

static void *
ngx_ingress_create_loc_conf(ngx_conf_t *cf)
{
    ngx_ingress_loc_conf_t  *sscf;

    sscf = ngx_pcalloc(cf->pool, sizeof(ngx_ingress_loc_conf_t));
    if (sscf == NULL) {
        return NULL;
    }

    return sscf;
}


static char *
ngx_ingress_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_ingress_loc_conf_t   *prev = parent;
    ngx_ingress_loc_conf_t   *conf = child;

    if (conf->gateway == NULL) {
        conf->gateway = prev->gateway;
    }

    return NGX_CONF_OK;
}

static ngx_int_t
ngx_ingress_check_upstream_enable(ngx_ingress_service_t *service)
{
    ngx_int_t   enable = 0;

    if (service->upstreams == NULL || service->upstreams->nelts == 0) {
        /* No upstream is processed according to no rules */
        return enable;
    }

#ifdef T_HTTP_VIPSERVER_MODULE
    ngx_uint_t  i;
    ngx_ingress_upstream_t *ups = service->upstreams->elts;
    for (i = 0; i < service->upstreams->nelts; i++) {
        if (ngx_http_vipserver_check_dynamic_enable(ngx_cycle, &ups[i].target) == NGX_OK) {
            /* If there is a successful one, return success */
            enable = 1;
            break;
        }
    }
#else
    enable = 1;
#endif

    return enable;
}

static ngx_inline ngx_int_t
ngx_ingress_cmp_tag_value(Ingress__MatchType match_type,
    ngx_str_t *value1, ngx_str_t *value2)
{
    /* full string match */
    if (INGRESS__MATCH_TYPE__WholeMatch == match_type) {

        if ((value1->len == value2->len)
            && (0 == ngx_strncasecmp(value1->data, value2->data, value1->len)))
        {
            return NGX_OK;

        } else {
            return NGX_ERROR;
        }

    /* prefix match TODO */
    } else if (INGRESS__MATCH_TYPE__PrefixMatch == match_type) {
        // TODO

    /* suffix match TODO */
    } else if (INGRESS__MATCH_TYPE__SuffixMatch == match_type) {
        // TODO

    /* regular match TODO */
    } else if (INGRESS__MATCH_TYPE__RegMatch == match_type) {
        // TODO

    } else {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
            "|ingress|invalid match type|%d|", match_type);
        return NGX_ERROR;
    }

    return NGX_ERROR;
}

static ngx_inline ngx_int_t
ngx_ingress_get_req_tag_value(ngx_http_request_t *r, Ingress__LocationType location,
    ngx_str_t *tag_key, ngx_str_t *tag_value)
{
    ngx_int_t               ret = NGX_ERROR;

    /* Tag from HttpHeader */
    if (INGRESS__LOCATION_TYPE__LocHttpHeader == location) {

        ret = ngx_http_header_in(r, (u_char *)tag_key->data, tag_key->len, tag_value);

    /* Tag from HttpQuery TODO */
    } else if (INGRESS__LOCATION_TYPE__LocHttpQuery == location) {
        // TODO

    /* Tag from nginx var TODO */
    } else if (INGRESS__LOCATION_TYPE__LocNginxVar == location) {
        // TODO

    /* Tag from x-biz-info TODO */
    } else if (INGRESS__LOCATION_TYPE__LocXBizInfo == location) {
        // TODO

    } else {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
            "|ingress|invalid loc type|%d|", location);
    }

    if (ret != NGX_OK) {
        tag_value->data = NULL;
        tag_value->len = 0;
    }

    return NGX_OK;
}

static ngx_ingress_service_t *
ngx_ingress_get_tag_match_service(ngx_ingress_gateway_t *gateway,
ngx_http_request_t *r, ngx_shm_array_t *tags)
{
    ngx_uint_t                      i, j, k;
    ngx_ingress_service_t          *service = NULL;
    ngx_int_t                       ret = NGX_ERROR;
    ngx_str_t                       value;

    ngx_ingress_tag_router_t *tag_router = tags->elts;

    /* Traversing each tag route (sorted in the array by priority), the first match is returned */
    for (i = 0; i < tags->nelts; i++) {

        ngx_ingress_tag_rule_t *tag_rule = tag_router[i].rules->elts;

        /* Traversing each tag rule (sorted in the array by priority), the first match is returned */
        for (j = 0; j < tag_router[i].rules->nelts; j++) {

            ngx_ingress_tag_item_t *tag_item = tag_rule[j].items->elts;

            /* Traversing each tag item, each item must match before returning */
            for (k = 0; k < tag_rule[j].items->nelts; k++) {

                ret = ngx_ingress_get_req_tag_value(r, tag_item[k].location, &tag_item[k].key, &value);
                /* The request does not carry the target parameter */
                if (ret != NGX_OK) {
                    break;

                } else {
                    ret = ngx_ingress_cmp_tag_value(tag_item[k].match_type, &tag_item[k].value, &value);
                    if (ret != NGX_OK) {
                        break;
                    }
                }
            }

            /* every item matched */
            if (k == tag_rule[j].items->nelts) {
                if (ngx_ingress_check_upstream_enable(tag_router[i].service)) {
                    return tag_router[i].service;
                }
            }
        }
    }

    return service;
}

static ngx_ingress_service_t *
ngx_ingress_match_service(ngx_ingress_gateway_t *gateway, ngx_http_request_t* r)
{
    ngx_uint_t i;
    ngx_ingress_t *current;
    ngx_ingress_service_t *service = NULL;
    ngx_ingress_host_router_t host_key;
    ngx_ingress_host_router_t *host_router;

    current = ngx_strategy_get_current_slot(gateway->ingress_app);
    if (current == NULL) {
        return NULL;
    }

    /* request no host */
    if (r->headers_in.server.len == 0) {
        return NULL;
    }

    host_key.host = r->headers_in.server;
    host_router = (ngx_ingress_host_router_t *)ngx_shm_hash_get(current->host_map, &host_key);
    if (host_router == NULL) {
        /* wildcard match */
        u_char *p = ngx_strlchr(host_key.host.data, host_key.host.data + host_key.host.len, '.');
        if (p != NULL) {
            ngx_int_t prefix_len = p - host_key.host.data + 1;

            host_key.host.data += prefix_len;
            host_key.host.len -= prefix_len;
            host_router = (ngx_ingress_host_router_t *)ngx_shm_hash_get(current->wildcard_host_map, &host_key);
        }
    }

    if (host_router == NULL) {
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|ingress|ingress host router not found|%V|", &host_key.host);
        return NULL;
    }

    /* match path */
    ngx_ingress_path_router_t *path_router = host_router->paths->elts;
    for (i = 0; i < host_router->paths->nelts; i++) {
        if (ngx_comm_prefix_casecmp(&r->uri, &path_router[i].prefix) == 0) {
            ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                          "|ingress|match prefix prefix|%V|%V|",
                          &host_key.host,
                          &r->uri);
            
            /* if path route has tag router, match first */
            if (path_router[i].tags) {
                service = ngx_ingress_get_tag_match_service(gateway, r, path_router[i].tags);
                if (service) {
                    return service;
                }
            }

            if (ngx_ingress_check_upstream_enable(path_router[i].service)) {
                return path_router[i].service;
            }
        }
    }

    /* if host route has tag router, match first */
    if (host_router->tags) {
        service = ngx_ingress_get_tag_match_service(gateway, r, host_router->tags);
        if (service) {
            return service;
        }
    }

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                  "|ingress|match host|%V|%V|", &host_key.host, &r->uri);
    
    return host_router->service;
}


ngx_int_t
ngx_ingress_update(ngx_cycle_t *cycle,
    void * context,
    ngx_shm_pool_t * pool,
    void * data,
    ngx_int_t print_detail)
{
    ngx_ingress_gateway_t   *gateway = context;
    ngx_ingress_t *ingress = data;

    ngx_int_t rc;

    ngx_ingress_shared_memory_config_t shm_pb_config;

    if (print_detail) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "|ingress|need to update|");
    }
    
    ingress->pool = pool;

    rc = ngx_ingress_shared_memory_read_pb(gateway->shared, &shm_pb_config, ngx_ingress_pb_read_body);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "|ingress|shared memory read pb failed|%V|%i|", &gateway->name, rc);
        return NGX_ERROR;
    }

    if (ingress->version != 0 && shm_pb_config.pbconfig->n_services == 0) {
        /* empty config protection */
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "|ingress|shared memory empty protection|%V|%i|", &gateway->name, rc);
        return NGX_ERROR;
    }

    ngx_shm_pool_reset(ingress->pool);

    rc = ngx_ingress_update_shm_by_pb(gateway, &shm_pb_config, ingress);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "|ingress|ngx_ingress_update failed|%V|", &gateway->name);
    }

    ngx_ingress_shared_memory_free_pb(&shm_pb_config);

    ingress->version = shm_pb_config.version;

    ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                  "|ingress|update ingress md5|%*s|",
                  NGX_COMM_MD5_HEX_LEN, shm_pb_config.md5_digit);

    if (rc == NGX_ERROR) {
        ngx_ingress_shared_memory_write_status(gateway->shared, NGX_INGRESS_SHARED_MEMORY_TYPE_ERR);
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "|ingress|update ingress rule error|");
    }
    else {
        ngx_ingress_shared_memory_write_status(gateway->shared, NGX_INGRESS_SHARED_MEMORY_TYPE_SUCCESS);
        ngx_log_error(NGX_LOG_WARN, cycle->log, 0, "|ingress|update ingress rule succ|");
    }

    return rc;
}

check_update_status
ngx_ingress_check_update(void * context,
    void * data)
{
    ngx_ingress_gateway_t       *gateway = context;
    ngx_ingress_t               *ingress = data;

    ngx_ingress_shared_memory_config_t   shm_pb_config;

    ngx_int_t need_update = 0, rc;

    ngx_int_t shm_key = 0;

    rc = ngx_ingress_shared_memory_read_pb(gateway->shared, &shm_pb_config, ngx_ingress_pb_read_version);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, 0,
                 "|ingress|shared memory read pb failed|%x|%i|", shm_key, rc);
        return STATUS_CHECK_NO_UPDATE;
    }

    if (ingress->version != shm_pb_config.version) {
        need_update = 1;
    }

    ngx_ingress_shared_memory_free_pb(&shm_pb_config);

    if (need_update) {
        return STATUS_CHECK_NEED_UPDATE;
    }
    return STATUS_CHECK_NO_UPDATE;
}



static ngx_http_variable_t  ngx_ingress_vars[] = {

    { ngx_string(NGX_INGRESS_CTX_VAR), NULL,
      ngx_ingress_ctx_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },
    
    { ngx_string("ingress_route_target"), NULL,
      ngx_ingress_route_target_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },
    
    { ngx_string("ingress_force_https"), NULL,
      ngx_ingress_force_https_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },
    
    { ngx_string("ingress_read_timeout"), NULL,
      ngx_ingress_get_time_variable, offsetof(ngx_ingress_ctx_t, read_timeout),
      NGX_HTTP_VAR_NOCACHEABLE, 0 },
    
    { ngx_string("ingress_connect_timeout"), NULL,
      ngx_ingress_get_time_variable, offsetof(ngx_ingress_ctx_t, connect_timeout),
      NGX_HTTP_VAR_NOCACHEABLE, 0 },
    
    { ngx_string("ingress_write_timeout"), NULL,
      ngx_ingress_get_time_variable, offsetof(ngx_ingress_ctx_t, write_timeout),
      NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_null_string, NULL, NULL, 0, 0, 0 }
};

static ngx_int_t
ngx_ingress_add_variables(ngx_conf_t *cf)
{
   ngx_http_variable_t  *var, *v;

    for (v = ngx_ingress_vars; v->name.len; v++) {
        var = ngx_http_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }

        var->get_handler = v->get_handler;
        var->data = v->data;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_ingress_ctx_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    ctx = ngx_http_get_module_ctx(r, ngx_ingress_module);
    if (ctx == NULL) {
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_ingress_ctx_t));
        if (ctx == NULL) {
            return NGX_ERROR;
        }

        ngx_http_set_ctx(r, ctx, ngx_ingress_module);
    }

    v->not_found = 0;

    v->data = (u_char *) ctx;
    v->len = sizeof(ctx);

    return NGX_OK;
}


static void*
ngx_ingress_get_gateway(ngx_conf_t *cf, ngx_ingress_main_conf_t *imcf, ngx_str_t *gateway_name)
{
    /* check gateway exist */
    ngx_uint_t               i;
    ngx_ingress_gateway_t *gateway = (ngx_ingress_gateway_t *)imcf->gateways.elts;
    for (i = 0; i < imcf->gateways.nelts; i++) {
        if (ngx_comm_strcmp(&gateway[i].name, gateway_name) == 0) {
            return &gateway[i];
        }
    }

    /* create new gateway */
    gateway = ngx_array_push(&imcf->gateways);
    if (gateway == NULL) {
        return NULL;
    }

    ngx_memset(gateway, 0, sizeof(ngx_ingress_gateway_t));

    /* init gateway */
    gateway->hash_size = NGX_CONF_UNSET_UINT;
    gateway->pool_size = NGX_CONF_UNSET_SIZE;
    gateway->update_check_interval = NGX_CONF_UNSET_MSEC;

    gateway->name.data = ngx_palloc(cf->pool, gateway_name->len);
    if (gateway->name.data == NULL) {
        return NULL;
    }
    ngx_memcpy(gateway->name.data, gateway_name->data, gateway_name->len);
    gateway->name.len = gateway_name->len;

    return gateway;
}

static char *
ngx_conf_set_ingress_gateway(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t           *value = cf->args->elts;
    ngx_str_t           *gateway_name = &value[1];

    ngx_ingress_loc_conf_t       *dlcf = conf;
    ngx_ingress_main_conf_t      *imcf = NULL;

    imcf = ngx_http_cycle_get_module_main_conf(cf->cycle, ngx_ingress_module);
    if (imcf == NULL) {
        return "ingress gateway get main conf failed";
    }
    
    ngx_ingress_gateway_t *gateway = ngx_ingress_get_gateway(cf, imcf, gateway_name);
    if (gateway == NULL) {
        return "ingress alloc gateway failed";
    }

    dlcf->gateway = gateway;

    return NGX_CONF_OK;
}


static void
ngx_ingress_exit_process(ngx_cycle_t *cycle)
{
    ngx_ingress_main_conf_t   *imcf;
    ngx_uint_t                 i;

    imcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_ingress_module);
    if (imcf == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|ingress|exit process get main conf failed|");
        return;
    }

    ngx_ingress_gateway_t *gateway = (ngx_ingress_gateway_t *)imcf->gateways.elts;
    for (i = 0; i < imcf->gateways.nelts; i++) {
        if (gateway[i].shared == NULL) {
            continue;
        }
        ngx_ingress_shared_memory_free(gateway[i].shared);
        gateway[i].shared = NULL;
    }
}

static char *
ngx_ingress_gateway_set_msec_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                       *value;
    ngx_str_t                       gateway_name, data_value;
    ngx_ingress_main_conf_t         *imcf = conf;

    ngx_msec_t       *msp;

    value = cf->args->elts;

    gateway_name = value[1];
    data_value = value[2];

    ngx_ingress_gateway_t *gateway = ngx_ingress_get_gateway(cf, imcf, &gateway_name);
    if (gateway == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "|ingress|alloc gateway failed");
        return NGX_CONF_ERROR;
    }

    msp = (ngx_msec_t *)  ((u_char*)gateway + cmd->offset);
    if (*msp != NGX_CONF_UNSET_MSEC) {
        return "is duplicate";
    }

    *msp = ngx_parse_time(&data_value, 0);
    if (*msp == (ngx_msec_t) NGX_ERROR) {
        return "invalid value";
    }
    
    return NGX_CONF_OK;
}

static char *
ngx_ingress_gateway_set_num_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                           *value;
    ngx_str_t                            gateway_name, data_value;
    ngx_ingress_main_conf_t             *dmcf = conf;

    ngx_int_t        *np;

    value = cf->args->elts;

    gateway_name = value[1];
    data_value = value[2];

    ngx_ingress_gateway_t *gateway = ngx_ingress_get_gateway(cf, dmcf, &gateway_name);
    if (gateway == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "|ingress|alloc gateway failed");
        return NGX_CONF_ERROR;
    }

    np = (ngx_int_t *) ((u_char*)gateway + cmd->offset);

    if (*np != NGX_CONF_UNSET) {
        return "is duplicate";
    }

    *np = ngx_atoi(data_value.data, data_value.len);
    if (*np == NGX_ERROR) {
        return "invalid number";
    }
    
    return NGX_CONF_OK;
}

static char *
ngx_ingress_gateway_set_size_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                       *value;
    ngx_str_t                        gateway_name, data_value;
    ngx_ingress_main_conf_t         *dmcf = conf;

    size_t                          *sp;

    value = cf->args->elts;

    gateway_name = value[1];
    data_value = value[2];

    ngx_ingress_gateway_t * gateway = ngx_ingress_get_gateway(cf, dmcf, &gateway_name);
    if (gateway == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "|ingress|alloc gateway failed");
        return NGX_CONF_ERROR;
    }

    sp = (size_t *) ((u_char*)gateway + cmd->offset);

    if (*sp != NGX_CONF_UNSET_SIZE) {
        return "is duplicate";
    }

    *sp = ngx_parse_size(&data_value);
    if (*sp == (size_t) NGX_ERROR) {
        return "invalid value";
    }
    
    return NGX_CONF_OK;
}

static char *
ngx_ingress_gateway_shm_config(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                       *value;
    ngx_str_t                        gateway_name;
    ngx_ingress_main_conf_t         *dmcf = conf;

    size_t                          shm_size;

    value = cf->args->elts;

    gateway_name = value[1];

    /*
      ingress_gateway_shm_config $gateway_name $shm_name shm_size lock_file
      gateway_name: gateway name
      shm_name: shared memory name
      shm_size: shared memory size
      lock_file: lock file path
    */

    ngx_ingress_gateway_t * gateway = ngx_ingress_get_gateway(cf, dmcf, &gateway_name);
    if (gateway == NULL) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "|ingress|alloc gateway failed");
        return NGX_CONF_ERROR;
    }

    gateway->shm_name = value[2];

    shm_size = ngx_parse_size(&value[3]);
    if (shm_size == (size_t) NGX_ERROR) {
        return "invalid value";
    }
    gateway->shm_size = shm_size;

    gateway->lock_file = value[4];

    if (ngx_conf_full_name(cf->cycle, &gateway->lock_file, 1) != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, ngx_errno,
                      "|ingress|lock file full path failed: %V|", &gateway->lock_file);
                      return NGX_CONF_ERROR;
    }
    
    return NGX_CONF_OK;
}

static ngx_int_t
ngx_ingress_init_ctx(ngx_ingress_ctx_t *ctx, ngx_http_request_t *r)
{
    ngx_ingress_loc_conf_t              *ilcf = NULL;
    ngx_ingress_upstream_t              *ups;
    ngx_int_t                            ups_index;
    ngx_int_t                            rc;
    ngx_uint_t                           i;

    ilcf = ngx_http_get_module_loc_conf(r, ngx_ingress_module);
    if (ilcf->gateway == NULL) {
        return NGX_DECLINED;
    }

    ngx_ingress_service_t *service = ngx_ingress_match_service(ilcf->gateway, r);
    if (service == NULL) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                    "|ingress|route service not found|");
        return NGX_DECLINED;
    }

    /* assign target */
    if (service->upstreams == NULL || service->upstreams->nelts == 0) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                    "|ingress|route service no upstream|");
        return NGX_ERROR;
    }

    ups = service->upstreams->elts;
    ups_index = 0;
    if (service->upstream_weight != 0) {
        ngx_int_t  offset = ngx_random() % service->upstream_weight;
        ngx_uint_t i;

        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                      "|ingress|weight target|%i|%i|%i|", service->upstream_weight, offset, service->upstreams->nelts);
        for (i = 0; i < service->upstreams->nelts; i++) {
            if (ups[i].start <= offset && ups[i].end > offset) {
                ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                              "|ingress|hit weight target|%i|%V|", ups_index, &ups[ups_index].target);
                ups_index = i;
                break;
            }
        }
    }

    ctx->target.len = ups[ups_index].target.len;
    ctx->target.data = ngx_palloc(r->pool, ctx->target.len);
    if (ctx->target.data == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|runtime target alloc failed|");
        return NGX_ERROR;
    }
    ngx_memcpy(ctx->target.data, ups[ups_index].target.data, ctx->target.len);

    /* assign force https */
    ctx->force_https = service->force_https;
    
    ctx->connect_timeout = service->timeout.connect_timeout;
    ctx->write_timeout = service->timeout.write_timeout;
    ctx->read_timeout = service->timeout.read_timeout;

    rc = ngx_array_init(&ctx->metadata, r->pool, service->metadata->nelts, sizeof(ngx_ingress_metadata_t));
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|init ctx metadata array failed|");
        return NGX_ERROR;
    }

    ngx_ingress_metadata_t *shm_metas = service->metadata->elts;
    for (i = 0; i < service->metadata->nelts; i++) {
        ngx_ingress_metadata_t *metadata = ngx_array_push(&ctx->metadata);
        if (metadata == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "|ingress|init ctx push metadata failed|");
            return NGX_ERROR;
        }

        metadata->key.data = ngx_palloc(r->pool, shm_metas[i].key.len);
        if (metadata->key.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "|ingress|init ctx alloc meta key failed|");
            return NGX_ERROR;
        }
        ngx_memcpy(metadata->key.data, shm_metas[i].key.data, shm_metas[i].key.len);
        metadata->key.len = shm_metas[i].key.len;

        metadata->value.data = ngx_palloc(r->pool, shm_metas[i].value.len);
        if (metadata->value.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "|ingress|init ctx alloc meta value failed|");
            return NGX_ERROR;
        }
        ngx_memcpy(metadata->value.data, shm_metas[i].value.data, shm_metas[i].value.len);
        metadata->value.len = shm_metas[i].value.len;
    }

    return NGX_OK;
}

static ngx_ingress_ctx_t *
ngx_ingress_get_ctx(ngx_ingress_main_conf_t *imcf,
                    ngx_http_request_t *r)
{
    ngx_ingress_ctx_t               *ctx = NULL;
    ngx_http_variable_value_t       *vv;
    ngx_int_t                        rc;

    ctx = ngx_http_get_module_ctx(r, ngx_ingress_module);
    if (ctx != NULL) {
        goto ret;
    }

    vv = ngx_http_get_indexed_variable(r, imcf->ctx_var_index);
    if (vv == NULL || vv->not_found) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|get ctx variable failed|");
        return NULL;
    }

    ctx = (ngx_ingress_ctx_t *) vv->data;
    ngx_http_set_ctx(r, ctx, ngx_ingress_module);

ret:
    if (!ctx->initialized) {
        rc = ngx_ingress_init_ctx(ctx, r);
        if (rc == NGX_ERROR) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|init ctx failed|");
            return NULL;
        }

        ctx->initialized = 1;
    }

    return ctx;
}

static ngx_int_t
ngx_ingress_route_target_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;

    ngx_ingress_main_conf_t             *imcf = NULL;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|route target get ctx failed|");
        return NGX_ERROR;
    }

    v->not_found = 0;
    v->data = ctx->target.data;
    v->len = ctx->target.len;

    return NGX_OK;
}

static ngx_int_t
ngx_ingress_force_https_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;

    ngx_ingress_main_conf_t             *imcf = NULL;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|route service get ctx failed|");
        return NGX_ERROR;
    }

    v->not_found = 0;
    v->len = 1;
    v->valid = 1;
    if (ctx->force_https) {
        v->data = (u_char*)"1";
    } else {
        v->data = (u_char*)"0";
    }

    ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                  "|ingress|force https variable|%d|", ctx->force_https);

    return NGX_OK;
}

static ngx_int_t
ngx_ingress_get_time_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;

    ngx_ingress_main_conf_t             *imcf = NULL;

    v->valid = 0;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|route target get ctx failed|");
        return NGX_ERROR;
    }

    ngx_msec_t  *tp;

    tp = (ngx_msec_t *) ((char *) ctx + data);
    if (*tp == 0 || *tp == NGX_CONF_UNSET_MSEC) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                      "|ingress|ignore unset timeout|");
        return NGX_ERROR;
    }

    v->data = ngx_pnalloc(r->pool, NGX_INT_T_LEN);
    if (v->data == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|gettime alloc failed|");
        return NGX_ERROR;
    }

    v->len = ngx_sprintf(v->data, "%Mms", *tp) - v->data;
    v->valid = 1;
    v->not_found = 0;

    return NGX_OK;
}

typedef struct {
    ngx_str_t key;
} ngx_ingress_metadata_ctx_t;

extern int ngx_ingress_metadata_compare(const void *c1, const void *c2);

static ngx_int_t
ngx_ingress_gateway_metadata_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v,
    uintptr_t data)
{
    ngx_ingress_metadata_ctx_t     *metadata_ctx = (ngx_ingress_metadata_ctx_t*)data;

    ngx_ingress_ctx_t              *ingress_ctx;
    ngx_str_t                       value = ngx_null_string;

    ngx_ingress_main_conf_t             *imcf = NULL;

    v->valid = 0;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ingress_ctx = ngx_ingress_get_ctx(imcf, r);

    if (ingress_ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|route metadata get ctx failed|");
        return NGX_ERROR;
    }

    /* get meta value */

    ngx_ingress_metadata_t key;
    ngx_ingress_metadata_t *meta_value;

    key.key = metadata_ctx->key;

    meta_value = bsearch(&key,
                         ingress_ctx->metadata.elts,
                         ingress_ctx->metadata.nelts,
                         ingress_ctx->metadata.size,
                         ngx_ingress_metadata_compare);
    
    if (meta_value != NULL) {
        value.len = meta_value->value.len;
        value.data = meta_value->value.data;
    }
    
    v->valid = 1;
    v->no_cacheable = 1;
    v->not_found = 0;
    v->data = value.data;
    v->len = value.len;

    return NGX_OK;
}

static char *
ngx_ingress_gateway_metadata(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t               *value          = cf->args->elts;
    ngx_http_variable_t     *var;

    ngx_ingress_metadata_ctx_t *ctx = ngx_palloc(cf->pool, sizeof(ngx_ingress_metadata_ctx_t));
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, 0,
                      "|ingress|metadata ctx alloc failed|");
        return NGX_CONF_ERROR;
    }

    /* key */
    ctx->key = value[1];

    /* variable */
    if (value[2].data[0] == '$') {
        value[2].data++;
        value[2].len--;
    }

    var = ngx_http_add_variable(cf, &value[2], NGX_HTTP_VAR_CHANGEABLE);
    if (var == NULL) {
        return NGX_CONF_ERROR;
    }

    var->get_handler = ngx_ingress_gateway_metadata_variable;
    var->data = (uintptr_t)ctx;

    return NGX_CONF_OK;
}

