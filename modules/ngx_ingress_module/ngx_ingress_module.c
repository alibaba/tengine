
/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_buf.h>

#include <ngx_comm_string.h>
#include <ngx_comm_shm.h>

#include <ngx_ingress_module.h>

#define NGX_INGRESS_UPDATE_INTERVAL             (30 * 1000)
#define NGX_INGRESS_SHM_POOL_SIZE               (32 * 1024 * 1024)
#define NGX_INGRESS_HASH_SIZE                   15013
#define NGX_INGRESS_GATEWAY_MAX_NAME_BUF_LEN    255
#define NGX_INGRESS_DEFAULT_GATEWAY_NUM         10

#define NGX_INGRESS_CTX_VAR          "__ingress_ctx__"

#define NGX_INGRESS_TAG_MATCH_SUCCESS           NGX_OK
#define NGX_INGRESS_TAG_MATCH_FAIL              NGX_DONE
#define NGX_INGRESS_TAG_MATCH_ERROR             NGX_ERROR

#define NGX_INGRESS_TAG_ACTION_APPEND_SEPARATOR ","

#define NGX_INGRESS_API_TYPES_SPLITE_CHAR   ','

static ngx_int_t ngx_ingress_add_variables(ngx_conf_t *cf);
static ngx_int_t ngx_ingress_ctx_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static char *ngx_conf_set_ingress_gateway(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static void ngx_ingress_exit_process(ngx_cycle_t *cycle);

static char *ngx_ingress_gateway_set_msec_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_ingress_gateway_set_num_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_ingress_gateway_set_size_slot(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static char *ngx_ingress_gateway_shm_config(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

static ngx_int_t ngx_ingress_route_target_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_ingress_get_unit_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);

static ngx_int_t ngx_ingress_get_failover_count_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);

static ngx_int_t ngx_ingress_force_https_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_ingress_get_time_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v, uintptr_t data);
static char *ngx_ingress_gateway_metadata(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
extern int ngx_ingress_metadata_compare(const void *c1, const void *c2);
static char *ngx_ingress_set_default_api_types(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);

static ngx_int_t ngx_ingress_get_api_name_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_ingress_get_api_version_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_ingress_get_api_mark_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_ingress_get_api_type_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_ingress_get_api_access_deny_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);

/* function declare */
static void * ngx_ingress_create_main_conf(ngx_conf_t *cf);

static void * ngx_ingress_create_loc_conf(ngx_conf_t *cf);
static char * ngx_ingress_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child);
static char * ngx_ingress_init_main_conf(ngx_conf_t *cf, void *conf);

check_update_status ngx_ingress_check_update(void * context, void * data);
ngx_int_t ngx_ingress_update(ngx_cycle_t *cycle, void * context, ngx_shm_pool_t * pool, void * data, ngx_int_t print_detail);

static ngx_command_t ngx_ingress_commands[] = {
    { ngx_string("ingress_gateway"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
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
   
    { ngx_string("ingress_gateway_apiv_hash_num"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_ingress_gateway_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_ingress_gateway_t, apiv_hash_size),
      NULL },

    { ngx_string("ingress_gateway_pool_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_ingress_gateway_set_size_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_ingress_gateway_t, pool_size),
      NULL },

    { ngx_string("ingress_gateway_path_segment_bucket_num"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE2,
      ngx_ingress_gateway_set_num_slot,
      NGX_HTTP_MAIN_CONF_OFFSET,
      offsetof(ngx_ingress_gateway_t, path_segment_bucket_num),
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
    
    { ngx_string("ingress_failover_named_location"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_str_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_ingress_loc_conf_t, failover_named_location),
      NULL },
    
    { ngx_string("ingress_default_api_types"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_ingress_set_default_api_types,
      NGX_HTTP_MAIN_CONF_OFFSET,
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
    conf->default_api_allow_types_num = NGX_CONF_UNSET;

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

    ngx_conf_init_value(imcf->default_api_allow_types_num, 0);

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
        ngx_conf_init_value(gateway[i].apiv_hash_size, NGX_INGRESS_HASH_SIZE);
        ngx_conf_init_value(gateway[i].path_segment_bucket_num, NGX_INGRESS_HASH_SIZE);

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

        ngx_log_error(NGX_LOG_DEBUG, cf->log, 0,
                    "|ingress|register strategy %V successfully|",
                    &gateway[i].name);
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

    ngx_conf_merge_str_value(conf->failover_named_location, 
                             prev->failover_named_location, 
                             "");

    return NGX_CONF_OK;
}

static ngx_int_t
ngx_ingress_check_upstream_enable(ngx_ingress_service_t *service)
{
    ngx_int_t   enable = 0;

    if (service->upstreams == NULL || service->upstreams->nelts == 0) {
        /* No upstream is processed according to no rules */
        enable = 1;
        return enable;
    }

    enable = 1;

    return enable;
}

int
ngx_ingress_tag_value_compar(const void *v1, const void *v2)
{
    ngx_str_t *s1 = (ngx_str_t *)v1;
    ngx_str_t *s2 = (ngx_str_t *)v2;
    return ngx_comm_strcasecmp(s1, s2);
}

ngx_int_t
ngx_ingress_tag_mod_compar(ngx_str_t *tag_value, ngx_int_t divisor,
    ngx_int_t remainder, ngx_ingress_tag_operator_e op) 
{
    ngx_int_t ret = NGX_INGRESS_TAG_MATCH_FAIL;
    ngx_int_t mod_value = ngx_atoi(tag_value->data, tag_value->len);

    if (mod_value == NGX_ERROR || divisor == 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "|ingress|mod_value atoi error|"); 
        return NGX_INGRESS_TAG_MATCH_ERROR;
    }
    
    ngx_int_t mod_r = mod_value % divisor;

    switch (op) {
    case INGRESS__OPERATOR_TYPE__OperatorEqual:
        if (mod_r == remainder) {
            ret = NGX_INGRESS_TAG_MATCH_SUCCESS;
        }
        break;
    case INGRESS__OPERATOR_TYPE__OperatorGreater:
        if (mod_r > remainder) {
            ret = NGX_INGRESS_TAG_MATCH_SUCCESS;
        }
        break;
    case INGRESS__OPERATOR_TYPE__OperatorLess:
        if (mod_r < remainder) {
            ret = NGX_INGRESS_TAG_MATCH_SUCCESS;
        }
        break;
    case INGRESS__OPERATOR_TYPE__OperatorGreaterEqual:
        if (mod_r >= remainder) {
            ret = NGX_INGRESS_TAG_MATCH_SUCCESS;
        }
        break;
    case INGRESS__OPERATOR_TYPE__OperatorLessEqual:
        if (mod_r <= remainder) {
            ret = NGX_INGRESS_TAG_MATCH_SUCCESS;
        }
        break;
    case INGRESS__OPERATOR_TYPE__OperatorUnDefined:
    default:
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "|ingress|invalid op value:%d|", op); 
        ret = NGX_INGRESS_TAG_MATCH_ERROR;
        break;
    }

    return ret;
}

/*
 *  return value:
 *  NGX_INGRESS_TAG_MATCH_SUCCESS means the value matched successfully
 *  NGX_INGRESS_TAG_MATCH_ERROR means an error occurred 
 *  NGX_INGRESS_TAG_MATCH_FAIL means the value failed to match
 */
static ngx_inline ngx_int_t
ngx_ingress_cmp_tag_value(ngx_ingress_tag_match_type_e match_type,
    ngx_ingress_tag_condition_t *p_cond, ngx_str_t *tag_value)
{
    ngx_int_t ret = NGX_INGRESS_TAG_MATCH_FAIL;
    void *s_result = NULL;
    switch (match_type) {
    case INGRESS__MATCH_TYPE__WholeMatch:
        if (ngx_comm_strcasecmp(tag_value, &p_cond->value_str) == 0) {    
            ret = NGX_INGRESS_TAG_MATCH_SUCCESS;
        }
        break;
    case INGRESS__MATCH_TYPE__StrListInMatch:
        s_result = ngx_shm_search_array(p_cond->value_a, tag_value, ngx_ingress_tag_value_compar);
        if (s_result != NULL) {
            ret = NGX_INGRESS_TAG_MATCH_SUCCESS;
        }
        break;
    case INGRESS__MATCH_TYPE__ModCompare:
        ret = ngx_ingress_tag_mod_compar(tag_value, p_cond->divisor, p_cond->remainder, p_cond->op);
        break;
    case INGRESS__MATCH_TYPE__MatchUnDefined:
    default:
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
            "|ingress|invalid match type|%d|", match_type);
        ret = NGX_INGRESS_TAG_MATCH_ERROR;
        break;
    }

    return ret;
}

static ngx_int_t
ngx_ingress_get_value_from_nginx_var(ngx_http_request_t *r,
    ngx_str_t *var_name,
    ngx_str_t *value)
{
    ngx_http_variable_value_t *vv = NULL;
    ngx_uint_t hash;

    value->data = "";
    value->len = 0;

    ngx_str_t var_name_lowcase;

    var_name_lowcase.data = ngx_pnalloc(r->pool, var_name->len);
    if (var_name_lowcase.data == NULL) {
        return NGX_ERROR;
    }

    hash = ngx_hash_strlow(var_name_lowcase.data, var_name->data, var_name->len);
    var_name_lowcase.len = var_name->len;

    vv = ngx_http_get_variable(r, &var_name_lowcase, hash);

    if (vv == NULL || vv->not_found || vv->len == 0) {
        return NGX_OK;
    }

    value->data = vv->data;
    value->len = vv->len;
    
    return NGX_OK;
}


/*
 * function: get tag rule value from http request
 * return: NGX_OK means that the tag rule's value has found
 * other value means that the tag rule's value hasn't found, or there is an error
 */
static ngx_inline ngx_int_t
ngx_ingress_get_req_tag_value(ngx_http_request_t *r, ngx_ingress_tag_value_location_e location,
    ngx_str_t *tag_key, ngx_str_t *tag_value)
{
    ngx_int_t               ret = NGX_ERROR;
    tag_value->data = NULL;
    tag_value->len = 0;
    switch (location) {
    case INGRESS__LOCATION_TYPE__LocHttpHeader:
        ret = ngx_http_header_in(r, (u_char *)tag_key->data, tag_key->len, tag_value);
        break;
    case INGRESS__LOCATION_TYPE__LocHttpQuery:
        ret = ngx_http_arg(r, (u_char *)tag_key->data, tag_key->len, tag_value); 
        break;
    case INGRESS__LOCATION_TYPE__LocNginxVar:
        ret = ngx_ingress_get_value_from_nginx_var(r, tag_key, tag_value);
        break;
    case INGRESS__LOCATION_TYPE__LocHttpCookie:
        if (ngx_http_parse_cookie_lines(r, r->headers_in.cookie, tag_key, tag_value)
                != NULL
            && tag_value->data != NULL)
        {
            ret = NGX_OK;
        } else {
            ret = NGX_DECLINED;
        }
        break;
    case INGRESS__LOCATION_TYPE__LocUnDefined:
    default:
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
            "|ingress|invalid loc type|%d|", location);
        ret = NGX_ERROR; 
        break;
    }
    return ret;
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
            if (tag_rule[j].items->nelts == 0) { /* no items */
                continue;
            }

            ngx_ingress_tag_item_t *tag_item = tag_rule[j].items->elts;
            
            /* Traversing each tag item, each item must match before returning */
            for (k = 0; k < tag_rule[j].items->nelts; k++) {

                ret = ngx_ingress_get_req_tag_value(r, tag_item[k].location, &tag_item[k].key, &value);
                /* The request does not carry the target parameter */
                if (ret != NGX_OK) {
                    break;
                } else {
                    ret = ngx_ingress_cmp_tag_value(tag_item[k].match_type, &tag_item[k].condition, &value);
                    if (ret != NGX_INGRESS_TAG_MATCH_SUCCESS) {
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

ngx_int_t
ngx_ingress_get_api_and_ver(ngx_http_request_t *r, ngx_str_t *api, ngx_str_t *v, ngx_str_t *api_type)
{
    u_char    *uri_pos, *uri_end, *new_pos;
    ngx_uint_t i;

    /* /gw/api/v or //gw/api/v or /gw/api/ or /gw/api */

    uri_pos = r->raw_uri.data;
    uri_end = uri_pos + r->raw_uri.len;

    for ( ; uri_pos < uri_end; uri_pos++) {
        if (*uri_pos != '/') {
            break;
        }
    }

    /* 1-gw, 2-api, 3-v */
    for (i = 1; i <= 3; i++) {
        for (new_pos = uri_pos; new_pos < uri_end; new_pos++) {
            if (*new_pos == '/' || *new_pos == '?') {
                break;
            }
        }

        if (i == 1 && new_pos - uri_pos > 0) {
            api_type->data = uri_pos;
            api_type->len = new_pos - uri_pos;
        }

        if (i == 2
            && ((new_pos < uri_end && ((*new_pos) == '/' || (*new_pos) == '?')) || (new_pos == uri_end))
            && new_pos - uri_pos > 0)
        {
            api->data = uri_pos;
            api->len = new_pos - uri_pos;
        }

        if (i == 3 && new_pos - uri_pos > 0) {
            v->data = uri_pos;
            v->len = new_pos - uri_pos;
        }

        if (new_pos >= uri_end || *new_pos == '?') {
            break;
        }

        uri_pos = new_pos + 1;
    }

    ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                    "|ingress|api=%V|v=%V|", api, v);

    return NGX_OK;

}


ngx_int_t
ngx_ingress_get_apiv(ngx_ingress_ctx_t *ctx, ngx_http_request_t *r, ngx_str_t *apiv)
{
    ngx_int_t rc = NGX_ERROR;
    ngx_str_t api = ngx_null_string, ver = ngx_string(""), api_type = ngx_string("");
    
    rc = ngx_ingress_get_api_and_ver(r, &api, &ver, &api_type);
    // Empty api version is allowed (E.g., mtop.common.getTimestamp)
    if (rc != NGX_OK || api.data == NULL || api.len == 0) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                    "|ingress|get api and ver error|");
        return NGX_ERROR;
    }
    
    apiv->data = ngx_pcalloc(r->pool, api.len + ver.len + 1);
    if (apiv->data == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "|ingress|apiv alloc error|");
        return NGX_ERROR;
    }
    ngx_strlow(apiv->data, api.data, api.len);
    apiv->data[api.len] = '_';
    ngx_copy(apiv->data + api.len + 1, ver.data, ver.len);
    apiv->len = api.len + ver.len + 1;

    ctx->mtop_api_name.data = apiv->data;
    ctx->mtop_api_name.len = api.len;

    ctx->mtop_api_version.data = apiv->data + api.len + 1;
    ctx->mtop_api_version.len = ver.len;

    ctx->mtop_api_mark = *apiv;
    ctx->mtop_api_type = api_type;
    
    return NGX_OK;
}

ngx_int_t
ngx_ingress_service_queue_head_insert(ngx_http_request_t *r, ngx_queue_t *head, ngx_ingress_service_t *service)
{
    ngx_ingress_service_queue_t *service_queue = ngx_pcalloc(r->pool, sizeof(ngx_ingress_service_queue_t));
    if (service_queue == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                "|ingress|ingress alloc service queue error|");
        return NGX_ERROR;
    }
    service_queue->service = service;
    ngx_queue_insert_head(head, &service_queue->queue_node); 
    return NGX_OK;
}

static ngx_int_t
ngx_ingress_appname_service_queue_head_insert(
    ngx_ingress_gateway_t *gateway,
    ngx_ingress_t *current,
    ngx_ingress_service_t *service,
    ngx_http_request_t *r,
    ngx_queue_t *head)
{
    ngx_int_t                    rc;
    ngx_ingress_service_t       *app_service = NULL;
    ngx_ingress_app_router_t     app_key;
    ngx_ingress_app_router_t    *app_router;

    if (service == NULL || service->appname.len == 0) {
        return NGX_OK;
    }

    app_key.appname = service->appname;
    app_router = (ngx_ingress_app_router_t *)ngx_shm_hash_get(current->app_map, &app_key);
    if (app_router == NULL || app_router->tags == NULL) {
        return NGX_OK;
    }

    app_service = ngx_ingress_get_tag_match_service(gateway, r, app_router->tags);
    if (app_service == NULL) {
        return NGX_OK;
    }

    rc = ngx_ingress_service_queue_head_insert(r, head, app_service);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|app tag service insert service queue failed|");
        return NGX_ERROR;
    }

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                      "|ingress|hit app router service|%V|", &service->appname);

    return NGX_OK;
}

static ngx_int_t
ngx_ingress_match_service(ngx_ingress_ctx_t *ctx, ngx_ingress_gateway_t *gateway, ngx_http_request_t* r, ngx_queue_t *head)
{
    ngx_uint_t i;
    ngx_ingress_t *current;
    ngx_ingress_service_t *service = NULL;
    ngx_ingress_host_router_t host_key;
    ngx_ingress_host_router_t *host_router;
    ngx_int_t rc;

    current = ngx_strategy_get_current_slot(gateway->ingress_app);
    if (current == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                    "|ingress|get ingress_app failed|");
        return NGX_ERROR;
    }

    /* request no host */
    if (r->headers_in.server.len == 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                    "|ingress|request no host|");
        return NGX_ERROR;
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
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                    "|ingress|ingress host router not found|%V|", &r->headers_in.server);
        return NGX_ERROR;
    }
    
    if (host_router->service) {
        rc = ngx_ingress_service_queue_head_insert(r, head, host_router->service);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                    "|ingress|host service insert service queue failed|");
            return NGX_ERROR;
        }
    }

    /* if host route has tag router, match */
    if (host_router->tags) {
        service = ngx_ingress_get_tag_match_service(gateway, r, host_router->tags);
        if (service) {
            rc = ngx_ingress_service_queue_head_insert(r, head, service);
            if (rc != NGX_OK) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|host tag service insert service queue failed|");
                return NGX_ERROR;
            }
        }
    }

    if (host_router->type == INGRESS__HOST_TYPE__MTOP) {
        /* match apiv rule */
        ngx_str_t apiv = ngx_null_string;
        rc = ngx_ingress_get_apiv(ctx, r, &apiv);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_INFO, ngx_cycle->log, 0,
                          "|ingress|ingress get apiv error|");
            return NGX_OK;
        }

        ngx_ingress_apiv_router_t apiv_key, *apiv_router;
        apiv_key.apiv = apiv;
        apiv_router = (ngx_ingress_apiv_router_t *)ngx_shm_hash_get(current->apiv_map, &apiv_key);
        if (apiv_router == NULL) {
            /* if type, apiv_router must not NULL */
            ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                          "|ingress|ingress get apiv_router NULL|");
            return NGX_ERROR; /* not found api_router*/
        }
        if (apiv_router->service) {
            rc = ngx_ingress_service_queue_head_insert(r, head, apiv_router->service);
            if (rc != NGX_OK) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|apiv service insert service queue failed|");
                return NGX_ERROR;
            }
        }

        /* add appname tag router */
        ngx_ingress_appname_service_queue_head_insert(gateway, current, apiv_router->service, r, head);

        if (apiv_router->tags) {
            service = ngx_ingress_get_tag_match_service(gateway, r, apiv_router->tags);
            if (service) {
                rc = ngx_ingress_service_queue_head_insert(r, head, service);
                if (rc != NGX_OK) {
                    ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|tag service insert service queue failed|");
                    return NGX_ERROR;
                }
            }
        }

    } else if (host_router->type == INGRESS__HOST_TYPE__Web) {
        /* match path */
        ngx_ingress_path_router_t *path_router = host_router->paths->elts;
        for (i = 0; i < host_router->paths->nelts; i++) {
            if (ngx_comm_prefix_casecmp(&r->uri, &path_router[i].prefix) == 0) {
                ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                        "|ingress|match prefix prefix|%V|%V|",
                        &host_key.host,
                        &r->uri);
                
                if (ngx_ingress_check_upstream_enable(path_router[i].service)) {
                    rc = ngx_ingress_service_queue_head_insert(r, head, path_router[i].service);
                    if (rc != NGX_OK) {
                        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                "|ingress|path service insert service queue failed|");
                        return NGX_ERROR;
                    }
                }

                /* add appname tag router */
                ngx_ingress_appname_service_queue_head_insert(gateway, current, path_router[i].service, r, head);
 
                /* if path route has tag router, match first */
                if (path_router[i].tags) {
                    service = ngx_ingress_get_tag_match_service(gateway, r, path_router[i].tags);
                    if (service) {
                        rc = ngx_ingress_service_queue_head_insert(r, head, service);
                        if (rc != NGX_OK) {
                            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                    "|ingress|path service with tag insert service queue failed|");
                            return NGX_ERROR;
                        }
                    }
                }
                
                break;
            }
        }
    } else if (host_router->type == INGRESS__HOST_TYPE__MCP) {
        /* match path */
        ngx_ingress_path_router_t *path_router = ngx_shm_trie_search(host_router->tries, &r->uri);
        if (path_router != NULL) {
            ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                    "|ingress|match tries prefix|%V|%V|",
                    &host_key.host,
                    &r->uri);
            
            if (ngx_ingress_check_upstream_enable(path_router->service)) {
                rc = ngx_ingress_service_queue_head_insert(r, head, path_router->service);
                if (rc != NGX_OK) {
                    ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|path service insert service queue failed|");
                    return NGX_ERROR;
                }
            }

            /* add appname tag router */
            ngx_ingress_appname_service_queue_head_insert(gateway, current, path_router->service, r, head);

            /* if path route has tag router, match first */
            if (path_router->tags) {
                service = ngx_ingress_get_tag_match_service(gateway, r, path_router->tags);
                if (service) {
                    rc = ngx_ingress_service_queue_head_insert(r, head, service);
                    if (rc != NGX_OK) {
                        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                "|ingress|path service with tag insert service queue failed|");
                        return NGX_ERROR;
                    }
                }
            }
        }
    }

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                  "|ingress|match host|%V|%V|", &host_key.host, &r->uri);
    
    return NGX_OK;
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
    shm_pb_config.pbconfig = NULL;

    rc = ngx_ingress_shared_memory_read_pb(gateway->shared, &shm_pb_config, ngx_ingress_pb_read_body);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|ingress|shared memory read pb failed|%V|%i|", &gateway->name, rc);
        goto ret;
    }

    if (ingress->version != 0 && shm_pb_config.pbconfig->n_services == 0) {
        /* empty config protection */
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "|ingress|shared memory empty protection|%V|%i|", &gateway->name, rc);
        goto ret;
    }

    ngx_shm_pool_reset(ingress->pool);

    rc = ngx_ingress_update_shm_by_pb(gateway, &shm_pb_config, ingress);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                 "|ingress|ngx_ingress_update failed|%V|", &gateway->name);
    }

    ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                  "|ingress|update ingress md5|%*s|num=%uz|ver=%uL",
                  NGX_COMM_MD5_HEX_LEN,
                  shm_pb_config.md5_digit,
                  shm_pb_config.pbconfig->n_services,
                  shm_pb_config.version);

    ingress->version = shm_pb_config.version;

ret:

    ngx_ingress_shared_memory_free_pb(&shm_pb_config);

    if (rc != NGX_OK) {
        ngx_ingress_shared_memory_write_status(gateway->shared,
                                               NGX_INGRESS_SHARED_MEMORY_STATUS_INGRESS,
                                               NGX_INGRESS_SHARED_MEMORY_TYPE_ERR);
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "|ingress|update ingress rule error|");
    }
    else {
        ngx_ingress_shared_memory_write_status(gateway->shared,
                                               NGX_INGRESS_SHARED_MEMORY_STATUS_INGRESS,
                                               NGX_INGRESS_SHARED_MEMORY_TYPE_SUCCESS);
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
      NGX_HTTP_VAR_CHANGEABLE, 0 },
    
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
    
    { ngx_string("ingress_unit"), NULL,
      ngx_ingress_get_unit_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("ingress_failover_count"), NULL,
      ngx_ingress_get_failover_count_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },
    
    { ngx_string("ingress_api_name"), NULL,
      ngx_ingress_get_api_name_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },
    
    { ngx_string("ingress_api_version"), NULL,
      ngx_ingress_get_api_version_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },
    
    { ngx_string("ingress_api_mark"), NULL,
      ngx_ingress_get_api_mark_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("ingress_api_type"), NULL,
      ngx_ingress_get_api_type_variable, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_string("ingress_api_access_deny"), NULL,
      ngx_ingress_get_api_access_deny_variable, 0,
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
    gateway->apiv_hash_size = NGX_CONF_UNSET_UINT;
    gateway->path_segment_bucket_num = NGX_CONF_UNSET_UINT;
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
ngx_ingress_service_get_value_from_nginx_var(ngx_http_request_t *r, ngx_str_t *key,
    ngx_str_t *var_value)
{
    ngx_str_t var_name;
    u_char *p_strlow = ngx_pnalloc(r->pool, key->len);
    if (p_strlow == NULL) {
        return NGX_ERROR;
    }
    ngx_uint_t hash = ngx_hash_strlow(p_strlow, key->data, key->len);
    var_name.data = p_strlow;
    var_name.len = key->len;
    ngx_http_variable_value_t *vv = ngx_http_get_variable(r, &var_name, hash);

    if (vv == NULL || vv->not_found || vv->len == 0) {
        return NGX_ERROR;
    }

    var_value->len = vv->len;
    var_value->data = vv->data;
    return NGX_OK;
}


/*
 * add header, if header key which add already exists in request,
 * this fuction will add a new header with the same key
 */
static ngx_int_t
ngx_ingress_service_request_add_header(ngx_http_request_t *r, ngx_str_t *key,
    ngx_str_t *value)
{
    ngx_table_elt_t             *h;
    h = ngx_list_push(&r->headers_in.headers);
    if (h == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
            "|ingress|ingress add header push headers error|");
        return NGX_ERROR;
    }

    h->key.len = key->len;
    h->key.data = key->data;
    h->hash = ngx_hash_key_lc(h->key.data, h->key.len);
    
    h->lowcase_key = ngx_pnalloc(r->pool, h->key.len);
    if (h->lowcase_key == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
            "|ingress|ingress add header alloc error|");
        ngx_list_delete(&r->headers_in.headers, h);
        return NGX_ERROR;
    }
    ngx_strlow(h->lowcase_key, key->data, key->len);

    h->value.data = value->data;
    h->value.len = value->len;

    return NGX_OK;
}

/*
 * If header key exists in the request, value will be appended
 * otherwise, new header will be added to the request
 * Based on RFC2616, the multiple message-header fields with the same field-name 
 * MAY be present in a message if and only if the entire field-value for that
 * header field is defined as a comma-separated list [i.e., #(values)].
 */
static ngx_int_t
ngx_ingress_service_request_append_header(ngx_http_request_t *r, ngx_str_t *key,
    ngx_str_t *value)
{
    ngx_uint_t                   i, hash, tag_len;
    ngx_table_elt_t             *h;
    ngx_list_part_t             *part;
    ngx_str_t                    new_value = ngx_null_string;
    u_char                      *p = NULL;
    ngx_int_t                    rc; 

    if (value->len == 0) {
        return NGX_OK;
    }

    part = &r->headers_in.headers.part;
    h = part->elts;
    hash = ngx_hash_key_lc(key->data, key->len);

    for (i = 0; /* void */; i++) {
        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            h = part->elts;
            i = 0;
        }

        if (hash == h[i].hash 
            && key->len == h[i].key.len
            && ngx_strncasecmp(key->data, h[i].lowcase_key, key->len) == 0)
        {
            tag_len = sizeof(NGX_INGRESS_TAG_ACTION_APPEND_SEPARATOR) - 1;
            new_value.len = h[i].value.len + value->len + tag_len;
            new_value.data = ngx_pnalloc(r->pool, new_value.len);
            if (new_value.data == NULL) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                        "|ingress|ingress append header alloc error|");
                return NGX_ERROR;
            }
            p = ngx_copy(new_value.data, h[i].value.data, h[i].value.len);
            p = ngx_copy(p, NGX_INGRESS_TAG_ACTION_APPEND_SEPARATOR, tag_len);
            p = ngx_copy(p, value->data, value->len);
            h[i].value.data = new_value.data;
            h[i].value.len = new_value.len;
            return NGX_OK;
        }
    }

    /* match failed */
    rc = ngx_ingress_service_request_add_header(r, key, value);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|ingress append header do add error|");
        return NGX_ERROR;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_ingress_service_response_add_header(ngx_http_request_t *r, ngx_str_t *key,
    ngx_str_t *value)
{
    ngx_table_elt_t  *h;
    h = ngx_list_push(&r->headers_out.headers);
    if (h == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|ingress do action push headers_out error|");
        return NGX_ERROR;
    }
    
    h->hash = 1;
    h->key = *key;
    h->value = *value;

    return NGX_OK;
}

/*
 * Appending header value to response  
 * However, the request headers_out has not response headers of upstream currently.
 * So, the function always add a new header to the response.
 */
static ngx_int_t
ngx_ingress_service_response_append_header(ngx_http_request_t *r, ngx_str_t *key,
    ngx_str_t *value)
{
    ngx_uint_t                   i, hash;
    ngx_table_elt_t             *h;
    ngx_list_part_t             *part;
    ngx_str_t                    new_value = ngx_null_string;
    u_char                      *p = NULL;
    ngx_int_t                    rc; 

    if (value->len == 0) {
        return NGX_OK;
    }

    part = &r->headers_out.headers.part;
    h = part->elts;
    hash = ngx_hash_key_lc(key->data, key->len);
    for (i = 0; /* void */; i++) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                        "Hash[%d]Append=[%s|%d][%s|%d],i[%d]",
                        hash,
                        key->data, key->len,
                        value->data, value->len,
                        i);

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            h = part->elts;
            i = 0;
        }

        if (h[i].hash == 0) {
            continue;
        }

        if (h[i].key.len == key->len
            && ngx_strncasecmp(h[i].key.data, key->data, h[i].key.len) == 0)
        {
            new_value.len = h[i].value.len + value->len + sizeof(NGX_INGRESS_TAG_ACTION_APPEND_SEPARATOR) - 1;
            new_value.data = ngx_pnalloc(r->pool, new_value.len);
            if (new_value.data == NULL) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                        "|ingress|ingress response append header alloc error|");
                return NGX_ERROR;
            }
            p = ngx_copy(new_value.data, h[i].value.data, h[i].value.len);
            p = ngx_copy(p, NGX_INGRESS_TAG_ACTION_APPEND_SEPARATOR,
                    sizeof(NGX_INGRESS_TAG_ACTION_APPEND_SEPARATOR) - 1);
            p = ngx_copy(p, value->data, value->len);
            h[i].value.data = new_value.data;
            h[i].value.len = new_value.len;
            return NGX_OK;
        }
    }

    /* match failed */
    rc = ngx_ingress_service_response_add_header(r, key, value);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|ingress response append header do add error|");
        return NGX_ERROR;
    }

    return NGX_OK;
}

/*
 * function: add parameter
 * if the key added already exists in the http request parameters, this fuction
 * will do nothing, so this function will not modify the value of the parameter with the same
 * key, which is setted by the clients.
 */
static ngx_int_t
ngx_ingress_service_param_add(ngx_http_request_t *r, ngx_str_t *key, ngx_str_t *value)
{
    u_char *p, *last;
    ngx_str_t new_args = ngx_null_string;
    ngx_int_t found_flag = 0;
    if (r->args.len != 0) {
        last = p + r->args.len;
        for ( p = r->args.data; p < last; p++) {
            p = ngx_strlcasestrn(p, last - 1, key->data, key->len - 1);
            if (p == NULL) {
                break;
            }
            if ((p == r->args.data || *(p - 1) == '&') && *(p + key->len) == '=') {
                found_flag = 1;
                break;
            }
        }
    }

    if (found_flag == 1) { // find the key in the http parameter
        //log
    } else {
        if (r->args.len == 0) {
            new_args.len = key->len + value->len + 2;
        } else {
            new_args.len = r->args.len + key->len + value->len + 2; 
        }
        new_args.data = ngx_pnalloc(r->pool, new_args.len);
        if (new_args.data == NULL) {
            return NGX_ERROR;
        }

        if (r->args.len == 0) {
            p = ngx_copy(new_args.data, "?", 1);
            p = ngx_copy(p, key->data, key->len);
            p = ngx_copy(p, "=", 1);
            p = ngx_copy(p, value->data, value->len);
        } else {
            p = ngx_copy(new_args.data, r->args.data, r->args.len);
            p = ngx_copy(p, "&", 1);
            p = ngx_copy(p, key->data, key->len);
            p = ngx_copy(p, "=", 1);
            p = ngx_copy(p, value->data, value->len);
        }
        
        r->args.data = new_args.data;
        r->args.len = new_args.len;
    }
    return NGX_OK;
    
}


/*
 * add param: no matter the key is exist in the query or not
 * add action append 'key=value' at the end of the query
 *
 */
static ngx_int_t
ngx_ingress_service_query_add_param(ngx_http_request_t *r, ngx_str_t *key, ngx_str_t *value)
{
    u_char *p, *last, *found;
    ngx_str_t new_unparsed_uri = ngx_null_string;
    new_unparsed_uri.len = r->unparsed_uri.len + key->len + value->len + 2;
    new_unparsed_uri.data = ngx_pnalloc(r->pool, new_unparsed_uri.len);
    if (new_unparsed_uri.data == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|ingress action add param alloc error|");
        return NGX_ERROR;
    }

    found = strstr(r->unparsed_uri.data, "?");
    if (r->args.len == 0 && !found) {
        p = ngx_copy(new_unparsed_uri.data, r->unparsed_uri.data, r->unparsed_uri.len);
        p = ngx_copy(p, "?", 1);
        p = ngx_copy(p, key->data, key->len);
        p = ngx_copy(p, "=", 1);
        p = ngx_copy(p, value->data, value->len);
    } else {
        p = ngx_copy(new_unparsed_uri.data, r->unparsed_uri.data, r->unparsed_uri.len);
        p = ngx_copy(p, "&", 1);
        p = ngx_copy(p, key->data, key->len);
        p = ngx_copy(p, "=", 1);
        p = ngx_copy(p, value->data, value->len);
    }

    r->unparsed_uri.data = new_unparsed_uri.data;
    r->unparsed_uri.len = new_unparsed_uri.len;
    return NGX_OK;
}

static ngx_int_t
ngx_ingress_service_do_action(ngx_http_request_t *r, ngx_ingress_action_t *action)
{
    ngx_int_t rc = NGX_ERROR;
    ngx_str_t value = ngx_null_string, key = ngx_null_string;
    
    if (action->key.data == NULL || action->key.len == 0 
        || action->value.len == 0 || action->value.data == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|ingress action key or value NULL|");
        return NGX_ERROR;
    }

    key.data = action->key.data;
    key.len = action->key.len;

    switch (action->value_type) {
    case INGRESS__ACTION_VALUE_TYPE__ActionValueUnDefined:
        /* action value type not defined */
        break;
    case INGRESS__ACTION_VALUE_TYPE__ActionStaticValue:
        value.data = action->value.data;
        value.len = action->value.len;
        break;
    case INGRESS__ACTION_VALUE_TYPE__ActionDynamicValue:
        rc = ngx_ingress_service_get_value_from_nginx_var(r, &action->value, &value);
        if (rc != NGX_OK || value.len == 0 || value.data == NULL ) {
            ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                    "|ingress|ingress find nginx var failed, %V|", &action->value);
            return NGX_OK; /* nginx var not found is not error */
        }
        break;
    default:
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|ingress action value type error|");
        return NGX_ERROR; 
    }

    switch (action->action_type) {
    case INGRESS__ACTION_TYPE__ActionAddReqHeader:
        if (value.len == 0 || value.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "|ingress|ingress action add req header value invalid|");
            return NGX_ERROR;;
        }
        
        rc = ngx_ingress_service_request_add_header(r, &key, &value);
        break;
    case INGRESS__ACTION_TYPE__ActionAppendReqHeader:
        if (value.len == 0 || value.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "|ingress|ingress action append req header value invalid|");
            return NGX_ERROR;
        }
 
        rc = ngx_ingress_service_request_append_header(r, &key, &value);
        break;
    case INGRESS__ACTION_TYPE__ActionAddRespHeader:
        if (value.len == 0 || value.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "|ingress|ingress action add resp header value invalid|");
            break;
        }
 
        rc = ngx_ingress_service_response_add_header(r, &key, &value); 
        break;
    case INGRESS__ACTION_TYPE__ActionAddParam:
        if (value.len == 0 || value.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "|ingress|ingress action add param value invalid|");
            break;
        }

        rc = ngx_ingress_service_query_add_param(r, &key, &value);
        break;
    case INGRESS__ACTION_TYPE__ActionUnDefined:
    default:
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|ingress action type invalid|");
        return NGX_ERROR;
    }
   
    return rc;
}

static ngx_int_t
ngx_ingress_init_ctx_failover(ngx_ingress_ctx_t *ctx,
                          ngx_ingress_service_t *service,
                          ngx_http_request_t *r)
{
    ngx_uint_t          i;

    if (service->failover == NULL  || service->failover->nelts == 0) {
        return NGX_OK;
    }

    ngx_array_t *ctx_failover = ngx_array_create(r->pool,
                                                 service->failover->nelts,
                                                 sizeof(ngx_ingress_ctx_failover_t));
    if (ctx_failover == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|ingress failover array create failed|");
        return NGX_ERROR;
    }

    ngx_shm_failover_t *shm_failover = service->failover->elts;
    for (i = 0; i < service->failover->nelts; i++) {
        ngx_uint_t                  j;
        ngx_ingress_ctx_failover_t *failover = ngx_array_push(ctx_failover);
        if (failover == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|ingress failover array push failed|");
            return NGX_ERROR;
        }

        failover->rules = ngx_array_create(r->pool,
                                           shm_failover[i].rules->nelts,
                                           sizeof(ngx_ingress_ctx_failover_rule_t));
        if (failover->rules == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "|ingress|ingress failover rule array create failed|");
            return NGX_ERROR;
        }

        ngx_shm_failover_rule_t *shm_failover_rule = shm_failover[i].rules->elts;
        for (j = 0; j < shm_failover[i].rules->nelts; j++) {
            ngx_ingress_ctx_failover_rule_t *failover_rule = ngx_array_push(failover->rules);
            if (failover_rule == NULL) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                              "|ingress|ingress failover rule array push failed|");
                return NGX_ERROR;
            }
            /* error_codes */
            failover_rule->err_codes = ngx_array_create(r->pool,
                                                        shm_failover_rule[j].err_codes->nelts,
                                                        sizeof(ngx_int_t));
            if (failover_rule->err_codes == NULL) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                              "|ingress|ingress failover err codes create failed|");
                return NGX_ERROR;
            }
            ngx_uint_t k;
            ngx_int_t *shm_code = shm_failover_rule[j].err_codes->elts;
            for (k = 0; k < shm_failover_rule[j].err_codes->nelts; k++) {
                ngx_int_t *code = ngx_array_push(failover_rule->err_codes);
                if (code == NULL) {
                    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                                  "|ingress|ingress failover err codes push failed|");
                    return NGX_ERROR;
                }
                *code = shm_code[k];
            }

            /* target */
            failover_rule->target.len = 0;
            if (shm_failover_rule[j].target.len > 0) {
                failover_rule->target.data = ngx_palloc(r->pool, shm_failover_rule[j].target.len);
                if (failover_rule->target.data == NULL) {
                    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                                "|ingress|ingress failover target alloc failed|");
                    return NGX_ERROR;
                }
                failover_rule->target.len = shm_failover_rule[j].target.len;
                ngx_memcpy(failover_rule->target.data, shm_failover_rule[j].target.data, failover_rule->target.len);
            }

            /* redirect host */
            failover_rule->redirect_host.len = 0;
            if (shm_failover_rule[j].redirect_host.len > 0) {
                failover_rule->redirect_host.data = ngx_palloc(r->pool, shm_failover_rule[j].redirect_host.len);
                if (failover_rule->redirect_host.data == NULL) {
                    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                                "|ingress|ingress failover redirect_host alloc failed|");
                    return NGX_ERROR;
                }
                failover_rule->redirect_host.len = shm_failover_rule[j].redirect_host.len;
                ngx_memcpy(failover_rule->redirect_host.data, shm_failover_rule[j].redirect_host.data, failover_rule->redirect_host.len);
            }

            /* timeout */
            failover_rule->timeout = shm_failover_rule[j].timeout;
        }
    }

    ctx->failover = ctx_failover;

    return NGX_OK;
}

static ngx_int_t
ngx_ingress_init_ctx_unit(ngx_ingress_ctx_t *ctx,
                          ngx_ingress_service_t *service,
                          ngx_http_request_t *r)
{
    if (service->unit == NULL) {
        return NGX_OK;
    }

    ngx_ingress_unit_t *shm_unit = service->unit;

    if (shm_unit->total_weight > 0 && shm_unit->weights != NULL) {
        size_t       i;
        ngx_int_t    rc;
        ngx_str_t    utdid = ngx_null_string;
        ngx_int_t    index = 0;

        index = rand() % shm_unit->total_weight;

        if (shm_unit->consistent_hashing) {
            ngx_str_t utdid_key = ngx_string("x-utdid");
            rc = ngx_http_header_in(r, utdid_key.data, utdid_key.len, &utdid);
            
            if (rc != NGX_OK || utdid.len == 0) {
                ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                              "|ingress|ingress unit hash utdid empty|");
                utdid.data = r->connection->addr_text.data;
                utdid.len = r->connection->addr_text.len;
            }

            ngx_uint_t ran_num = ngx_hash_key(utdid.data, utdid.len);
            index = ran_num % shm_unit->total_weight;

            ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                          "|ingress|ingress unit hash utdid: %V, index: %d|", &utdid, index);
        }

        ngx_str_t target_unit = ngx_string("");

        ngx_ingress_weight_unit_t *weights = (ngx_ingress_weight_unit_t *)shm_unit->weights->elts;
        for (i = 0; i < shm_unit->weights->nelts; i++) {
            if (index >= weights[i].start && index < weights[i].end) {
                target_unit = weights[i].unit;
                break;
            }
        }
        ctx->unit.data = ngx_palloc(r->pool, target_unit.len);
        if (ctx->unit.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                        "|ingress|runtime ctx->unit alloc failed|");
            return NGX_ERROR;
        }
        ngx_memcpy(ctx->unit.data, target_unit.data, target_unit.len);
        ctx->unit.len = target_unit.len;
    }

    return NGX_OK;
}

ngx_int_t 
ngx_ingress_read_value_from_service_queue(ngx_ingress_ctx_t *ctx,
    ngx_http_request_t *r, ngx_queue_t *head)

{
    ngx_ingress_service_t *target_service = NULL;
    ngx_ingress_service_t *timeout_service = NULL;
    ngx_ingress_service_t *force_https_service = NULL;
    ngx_ingress_service_t *action_service = NULL;
    ngx_ingress_service_t *unit_service = NULL;
    ngx_int_t   action_num = 0;
    ngx_int_t   metadata_num = 0;
    ngx_int_t   rc, i;
    ngx_queue_t *node;
    
    for (node = ngx_queue_head(head); node != ngx_queue_sentinel(head); node = ngx_queue_next(node)) {
        ngx_ingress_service_queue_t *service_queue =
            ngx_queue_data(node, ngx_ingress_service_queue_t, queue_node);
        if (service_queue->service == NULL) {
            continue;
        }
        if (service_queue->service->metadata->nelts > 0) {
            metadata_num += service_queue->service->metadata->nelts; 
        }
        
        if (service_queue->service->upstreams != NULL
            && service_queue->service->upstreams->nelts > 0
            && target_service == NULL) {
            target_service = service_queue->service;
        }

        if (service_queue->service->timeout.set_flag == NGX_INGRESS_TIMEOUT_SET
            && timeout_service == NULL) {
            timeout_service = service_queue->service;
        }

        if (service_queue->service->force_https != NGX_INGRESS_FORCE_HTTPS_UNSET
            && force_https_service == NULL) {
            force_https_service = service_queue->service;
        }

        if (service_queue->service->action_a != NULL
            && service_queue->service->action_a->nelts > 0
            && action_service == NULL) {
            action_num += service_queue->service->action_a->nelts;
            action_service = service_queue->service;
        }

        if (service_queue->service->unit != NULL
            && unit_service == NULL) {
            unit_service = service_queue->service;
        }
    }

    if (target_service == NULL) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                "|ingress|get target from service queue error|");
    } else {
        ngx_ingress_upstream_t *ups = target_service->upstreams->elts;
        ngx_int_t ups_index = 0;
        if (target_service->upstream_weight != 0) {
            ngx_int_t  offset = ngx_random() % target_service->upstream_weight;
            ngx_uint_t i;
            for (i = 0; i < target_service->upstreams->nelts; i++) {
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
    }

    if (timeout_service != NULL) {
        ctx->connect_timeout = timeout_service->timeout.connect_timeout;
        ctx->write_timeout = timeout_service->timeout.write_timeout;
        ctx->read_timeout = timeout_service->timeout.read_timeout;
    } else { /* timeout unset, default value 0 */
        ctx->connect_timeout = 0;
        ctx->write_timeout = 0;
        ctx->read_timeout = 0;
    }
    
    if (force_https_service != NULL) {
        ctx->force_https = force_https_service->force_https;
    } else {
        ctx->force_https = 0;
    }

    rc = ngx_array_init(&ctx->action_a, r->pool, action_num, 
            sizeof(ngx_ingress_action_t));
 
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|init ctx alloc action array failed|");
        return NGX_ERROR;
    }

    if (action_service != NULL) {
        ngx_ingress_action_t *shm_action = action_service->action_a->elts;
        for (i = 0; i < action_service->action_a->nelts; i++) {
            ngx_ingress_action_t *action = ngx_array_push(&ctx->action_a);
            if (action == NULL) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                        "|ingress|init ctx alloc action failed|");
                return NGX_ERROR;
            }
           
            action->action_type = shm_action[i].action_type;
            action->value_type = shm_action[i].value_type;
            
            action->key.data = ngx_palloc(r->pool, shm_action[i].key.len);
            if (action->key.data == NULL) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                        "|ingress|init ctx alloc action key failed:%d|", shm_action[i].key.len);
                return NGX_ERROR;
            }
            ngx_memcpy(action->key.data, shm_action[i].key.data, shm_action[i].key.len);
            action->key.len = shm_action[i].key.len;
            
            action->value.data = ngx_palloc(r->pool, shm_action[i].value.len);
            if (action->value.data == NULL) {
                ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                        "|ingress|init ctx alloc action value failed:%d|", shm_action[i].value.len);
                return NGX_ERROR;
            }
            ngx_memcpy(action->value.data, shm_action[i].value.data, shm_action[i].value.len);
            action->value.len = shm_action[i].value.len;
        }
    }

    rc = ngx_array_init(&ctx->metadata, r->pool, metadata_num, sizeof(ngx_ingress_metadata_t));
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "|ingress|init ctx metadata array failed|");
        return NGX_ERROR;
    }

    size_t last_metadata_num = 0;

    for (node = ngx_queue_head(head); node != ngx_queue_sentinel(head); node = ngx_queue_next(node)) {
        ngx_ingress_service_queue_t *service_queue =
            ngx_queue_data(node, ngx_ingress_service_queue_t, queue_node);
        if (service_queue->service == NULL) {
            continue;
        }

        size_t current_metadata_num = 0;

        ngx_ingress_metadata_t *shm_metas = service_queue->service->metadata->elts;
        for (i = 0; i < service_queue->service->metadata->nelts; i++) {
            /* check exist metadata */
            if (bsearch(&shm_metas[i],
                        ctx->metadata.elts,
                        last_metadata_num,
                        ctx->metadata.size,
                        ngx_ingress_metadata_compare) != NULL)
            {
                ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                              "|ingress|exist metadata|%V|", &shm_metas[i].key);
                continue;
            }

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

            /* set api type */
            if (metadata->key.len == sizeof(NGX_INGRESS_METADATA_KEY_API_TYPE) - 1
                && ngx_strncmp(metadata->key.data, NGX_INGRESS_METADATA_KEY_API_TYPE, metadata->key.len) == 0)
            {
                ctx->mtop_api_allow_types_num = ngx_comm_split_string(ctx->mtop_api_allow_types,
                                                                      MAX_INGRESS_API_TYPES_NUM,
                                                                      metadata->value.data,
                                                                      metadata->value.data + metadata->value.len,
                                                                      NGX_INGRESS_API_TYPES_SPLITE_CHAR);
            }

            current_metadata_num ++;
        }

        if (current_metadata_num > 0) {
            qsort(ctx->metadata.elts, ctx->metadata.nelts, ctx->metadata.size, ngx_ingress_metadata_compare); 
        }

        last_metadata_num = ctx->metadata.nelts;
    }
    

    if (unit_service != NULL) {
        rc = ngx_ingress_init_ctx_unit(ctx, unit_service, r);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "|ingress|init ctx unit failed|");
            return NGX_ERROR;
        }
    }

    /* Use failover rules associated with upstream */
    if (target_service != NULL) {
        rc = ngx_ingress_init_ctx_failover(ctx, target_service, r);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "|ingress|init ctx failover failed|");
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}

/* 
 * return NGX_ERROR: may match again
 * return NGX_DECLINED: no need to match again
 */
 
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

    ngx_queue_t service_head;
    ngx_queue_init(&service_head);

    rc = ngx_ingress_match_service(ctx, ilcf->gateway, r, &service_head);
    if (rc != NGX_OK || ngx_queue_empty(&service_head)) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                "|ingress|route service not found|");
        
        /* not found probably, no need to match again  */
        return NGX_DECLINED;
    }
    
    rc = ngx_ingress_read_value_from_service_queue(ctx, r, &service_head);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                "|ingress|read value from service queue failed|");
        return rc;
    }

    return NGX_OK;
}

ngx_ingress_ctx_t *
ngx_ingress_get_ctx(ngx_ingress_main_conf_t *imcf,
                    ngx_http_request_t *r)
{
    ngx_ingress_ctx_t               *ctx = NULL;
    ngx_http_variable_value_t       *vv;
    ngx_int_t                        rc;
    ngx_int_t                        i;

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
        ctx->initialized = 1; /* initialized flag 1 indicates no need to match again */

        if (rc == NGX_OK && ctx->action_a.nelts > 0) {
            /* 
             * action should do while ctx->initialized equal 1,
             * so it can avoid to do action duplicately
             */
            ngx_ingress_action_t *action = ctx->action_a.elts;     
            for (i = 0; i < ctx->action_a.nelts; i++) {
                rc = ngx_ingress_service_do_action(r, &action[i]);
                if (rc != NGX_OK) {
                    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                            "|ingress|ingress service do action error|");
                    /* just log error */
                }
            }
        }  
        
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
ngx_ingress_get_unit_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;
    ngx_ingress_main_conf_t         *imcf = NULL;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|unit get ctx failed|");
        return NGX_ERROR;
    }

    if (ctx->unit.len > 0) {
        v->not_found = 0;
        v->data = ctx->unit.data;
        v->len = ctx->unit.len;
    } else {
        v->not_found = 1;
        v->data = "";
        v->len = 0;
    }
    return NGX_OK;
}

static ngx_int_t
ngx_ingress_get_failover_count_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;
    ngx_ingress_main_conf_t         *imcf = NULL;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|unit get ctx failed|");
        return NGX_ERROR;
    }

    v->data = ngx_pnalloc(r->pool, NGX_INT32_LEN);
    if (v->data == NULL) {
        return NGX_ERROR;
    }

    v->len = ngx_sprintf(v->data, "%ui", ctx->failover_index) - v->data;
    v->not_found = 0;

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

static char *
ngx_ingress_set_default_api_types(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                           *value;
    ngx_ingress_main_conf_t             *imcf = conf;

    value = cf->args->elts;

    if (imcf->default_api_allow_types_num != NGX_CONF_UNSET) {
        ngx_conf_log_error(NGX_LOG_NOTICE, cf, 0,
                           "duplicate \"%V\"", &value[0]);

        return NGX_CONF_ERROR;
    }

    imcf->default_api_allow_types_num = ngx_comm_split_string(imcf->default_api_allow_types,
                                                              MAX_INGRESS_API_TYPES_NUM,
                                                              value[1].data,
                                                              value[1].data + value[1].len,
                                                              NGX_INGRESS_API_TYPES_SPLITE_CHAR);

    return NGX_CONF_OK;
}

static ngx_int_t
ngx_ingress_get_api_name_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;
    ngx_ingress_main_conf_t         *imcf = NULL;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|api name get ctx failed|");
        return NGX_ERROR;
    }

    if (ctx->mtop_api_name.len > 0) {
        v->valid = 1;
        v->no_cacheable = 1;
        v->not_found = 0;
        v->data = ctx->mtop_api_name.data;
        v->len = ctx->mtop_api_name.len;
    } else {
        v->valid = 0;
        v->not_found = 1;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_ingress_get_api_version_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;
    ngx_ingress_main_conf_t         *imcf = NULL;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|api version get ctx failed|");
        return NGX_ERROR;
    }

    if (ctx->mtop_api_version.len > 0) {
        v->valid = 1;
        v->no_cacheable = 1;
        v->not_found = 0;
        v->data = ctx->mtop_api_version.data;
        v->len = ctx->mtop_api_version.len;
    } else {
        v->valid = 0;
        v->not_found = 1;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_ingress_get_api_mark_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;
    ngx_ingress_main_conf_t         *imcf = NULL;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|api mark get ctx failed|");
        return NGX_ERROR;
    }

    if (ctx->mtop_api_mark.len > 0) {
        v->valid = 1;
        v->no_cacheable = 1;
        v->not_found = 0;
        v->data = ctx->mtop_api_mark.data;
        v->len = ctx->mtop_api_mark.len;
    } else {
        v->valid = 0;
        v->not_found = 1;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_ingress_get_api_type_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;
    ngx_ingress_main_conf_t         *imcf = NULL;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 1;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|api mark get ctx failed|");
        return NGX_ERROR;
    }

    if (ctx->mtop_api_type.len > 0) {
        v->valid = 1;
        v->no_cacheable = 1;
        v->not_found = 0;
        v->data = ctx->mtop_api_type.data;
        v->len = ctx->mtop_api_type.len;
    } else {
        v->valid = 0;
        v->not_found = 1;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_ingress_get_api_access_deny_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_ingress_ctx_t               *ctx;
    ngx_ingress_main_conf_t         *imcf = NULL;
    ngx_uint_t                       i;

    ngx_int_t                        allow_types_num = 0;
    ngx_str_t                       *allow_types = NULL;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "|ingress|api mark get ctx failed|");
        return NGX_ERROR;
    }

    v->valid = 1;
    v->no_cacheable = 1;
    v->not_found = 0;
    v->data = (u_char*)"0";
    v->len = 1;

    if (ctx->mtop_api_type.len == 0) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                      "|ingress|api type is empty|");
        return NGX_OK;
    }

    allow_types_num = ctx->mtop_api_allow_types_num;
    allow_types = ctx->mtop_api_allow_types;
    if (allow_types_num == 0) {
        allow_types_num = imcf->default_api_allow_types_num;
        allow_types = imcf->default_api_allow_types;

        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                      "|ingress|use default api allow types|%d|", allow_types_num);
    } else {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0,
                      "|ingress|use api allow types|%d|", allow_types_num);
    }

    if (allow_types_num == 0) {
        return NGX_OK;
    }

    for (i = 0; i < allow_types_num; i++) {
        if (ngx_comm_str_compare(&ctx->mtop_api_type, &allow_types[i]) == 0) {
            return NGX_OK;
        }
    }

    v->data = (u_char*)"1";
    v->len = 1;

    return NGX_OK;
}
