/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

#include "ngx_ingress_failover.h"
#include "ngx_ingress_module.h"

#include <ngx_http.h>
#include "ngx_comm_string.h"
#include "ngx_comm_math.h"

extern ngx_module_t ngx_ingress_module;

static ngx_str_t ngx_scheme_var_name = ngx_string("scheme");

static ngx_int_t
ngx_ingress_failover_get_value_from_nginx_var(ngx_http_request_t *r, ngx_str_t *name, ngx_str_t *value)
{
    u_char                      *low;
    ngx_str_t                    var;
    ngx_uint_t                   hash;
    ngx_http_variable_value_t   *vv;

    if (0 >= name->len || NULL == name->data) {
        return NGX_ERROR;
    }

    low = ngx_pnalloc(r->pool, name->len);
    if (low == NULL) {
        return NGX_ERROR;
    }

    hash = ngx_hash_strlow(low, name->data, name->len);
    var.data = low;
    var.len = name->len;

    vv = ngx_http_get_variable(r, &var, hash);

    if (vv == NULL || vv->not_found || vv->valid == 0) {
        return NGX_ERROR;
    }

    value->data = vv->data;
    value->len = vv->len;

    return NGX_OK;
}

static ngx_ingress_ctx_failover_rule_t *
ngx_failover_get_rule(ngx_http_request_t *r,
    ngx_ingress_ctx_t *ctx, 
    ngx_int_t status)
{
    ngx_uint_t                        i, j, k;
    ngx_ingress_ctx_failover_rule_t  *rule;
    ngx_ingress_ctx_failover_t       *failover;

    if (ctx->active_failover == NULL && ctx->failover_index == 0) {
        /* 第一次进入进行 failover 匹配 */
        failover = (ngx_ingress_ctx_failover_t *)ctx->failover->elts;
        for (i = 0; i < ctx->failover->nelts && ctx->active_failover == NULL; i++) {
            rule = failover[i].rules->elts;
            if (failover[i].rules->nelts == 0) {
                continue;
            }
            ngx_int_t *err_code = (ngx_int_t *)rule[0].err_codes->elts;
            for (k = 0; k < rule[0].err_codes->nelts; k++) {
                if (status == err_code[k]) {
                    ctx->active_failover = failover[i].rules;
                    return &rule[0];
                }
            }
        }
    }

    if (ctx->active_failover == NULL 
        || ctx->failover_index >= ctx->active_failover->nelts) {
        /* 超出最大支持的 failover 次数  */
        return NULL;
    }

    rule = ctx->active_failover->elts;
    ngx_int_t *err_code = (ngx_int_t *)rule[ctx->failover_index].err_codes->elts;
    for (k = 0; k < rule[ctx->failover_index].err_codes->nelts; k ++) {
        if (status == err_code[k]) {
            return &rule[ctx->failover_index];
        }
    }

    return NULL;
}


ngx_int_t 
ngx_failover_check_handler(ngx_http_request_t *r, ngx_int_t status)
{
    ngx_ingress_ctx_t                       *ctx;
    ngx_ingress_ctx_failover_rule_t         *rule;
    ngx_ingress_main_conf_t                 *imcf = NULL;
    ngx_ingress_loc_conf_t                  *ilcf;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ilcf = ngx_http_get_module_loc_conf(r, ngx_ingress_module);

    /* 无配置，默认不生效 failover 功能 */
    if (ilcf->failover_named_location.len == 0) {
        return NGX_OK;
    }

    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "|ingress|failover get ctx failed|");
        return NGX_OK;
    }

    /* 判断是否执行过 failover 检查 */
    if (ctx->check_index > ctx->failover_index) {
        return ctx->check_status;
    }

    ctx->check_index ++;

    /* 查询 failover 规则 */
    if (ctx->failover == NULL || ctx->failover->nelts == 0) {
        /* 请求无关联的 failover 配置，无操作 */
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "|ingress|no failover rule|");
        ctx->check_status = NGX_OK;
        return NGX_OK;
    }

    /* 判断是否需要执行 failover */
    rule = ngx_failover_get_rule(r, ctx, status);
    if (rule == NULL) {
        /* 无匹配的 failover 规则  */
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "|ingress|no matched rule|%i|", status);
        ctx->check_status = NGX_ERROR;
        return NGX_ERROR;
    }

    ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "|ingress|matched failover rule|%i|%i", status, ctx->check_index);

    ctx->failover_rule = rule;
    ctx->check_status = NGX_DONE;
    return NGX_DONE;
}

ngx_int_t
ngx_http_send_special_response(ngx_http_request_t *r,
    ngx_http_core_loc_conf_t *clcf, ngx_uint_t err);

#define NGX_HTTP_OFF_3XX   1

ngx_int_t
ngx_http_send_redirect_to_client(ngx_http_request_t *r, ngx_str_t *redirect_host)
{
    ngx_http_core_loc_conf_t    *clcf;
    ngx_table_elt_t             *location;
    ngx_str_t                    redirect_location;
    ngx_str_t                    scheme = ngx_string("https");

    ngx_ingress_ctx_t            *ctx;
    ngx_ingress_main_conf_t      *imcf = NULL;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);
    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx != NULL && !ctx->force_https) {
        ngx_ingress_failover_get_value_from_nginx_var(r, &ngx_scheme_var_name, &scheme);
    }

    redirect_location.len = scheme.len + sizeof("://") + redirect_host->len + r->unparsed_uri.len;
    redirect_location.data = ngx_palloc(r->pool, redirect_location.len);
    if (redirect_location.data == NULL) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "|ingress|alloc redirect_location failed|");
        return NGX_ERROR;
    }
    redirect_location.len = ngx_snprintf(redirect_location.data,
                                         redirect_location.len, "%V://%V%V",
                                         &scheme,
                                         redirect_host,
                                         &r->unparsed_uri) - redirect_location.data;

    r->err_status = NGX_HTTP_MOVED_TEMPORARILY;
    r->expect_tested = 1;

    if (ngx_http_discard_request_body(r) != NGX_OK) {
        r->keepalive = 0;
    }

    location = ngx_list_push(&r->headers_out.headers);
    if (location == NULL) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "|ingress|redirect ngx_list_push location failed|");
        return NGX_ERROR;
    }

    location->hash = 1;
    ngx_str_set(&location->key, "Location");
    location->value = redirect_location;

    ngx_http_clear_location(r);

    r->headers_out.location = location;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    return ngx_http_send_special_response(r, clcf, r->err_status
                                                   - NGX_HTTP_MOVED_PERMANENTLY
                                                   + NGX_HTTP_OFF_3XX);
}

ngx_int_t 
ngx_failover_check_and_action_handler(ngx_http_request_t *r, ngx_int_t status, ngx_int_t *ret_code)
{
    ngx_int_t                  rc;
    ngx_ingress_loc_conf_t    *ilcf;

    ngx_ingress_ctx_t                       *ctx;
    ngx_ingress_ctx_failover_rule_t         *rule;
    ngx_ingress_main_conf_t                 *imcf = NULL;

    imcf = ngx_http_get_module_main_conf(r, ngx_ingress_module);

    ilcf = ngx_http_get_module_loc_conf(r, ngx_ingress_module);

    rc = ngx_failover_check_handler(r, status);
    if (rc != NGX_DONE) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "|ingress|failover check mismatch|");
        return rc;
    }

    ctx = ngx_ingress_get_ctx(imcf, r);
    if (ctx == NULL || ctx->failover_rule == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "|ingress|failover get ctx failed|");
        return NGX_ERROR;
    } else if (ctx->failover_rule->target.len == 0 && ctx->failover_rule->redirect_host.len == 0) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "|ingress|failover target and redirect_host is null|");
        return NGX_ERROR;
    }

    /* 执行failover */
    ctx->failover_index += 1;
    r->err_status = 0;

    ctx->target = ctx->failover_rule->target;
    if (ctx->failover_rule->timeout.set_flag == NGX_INGRESS_TIMEOUT_SET) {
        ctx->connect_timeout = ctx->failover_rule->timeout.connect_timeout;
        ctx->write_timeout = ctx->failover_rule->timeout.write_timeout;
        ctx->read_timeout = ctx->failover_rule->timeout.read_timeout;
    }

#if (T_NGX_HTTP_UPSTREAM_TIMEOUT_VAR_ALI)
    if (ctx->failover_rule->timeout.set_flag == NGX_INGRESS_TIMEOUT_SET) {
        r->connect_time = ctx->failover_rule->timeout.connect_timeout;
        r->send_time = ctx->failover_rule->timeout.write_timeout;
        r->read_time = ctx->failover_rule->timeout.read_timeout;
    }
#endif

    if (ctx->failover_rule->redirect_host.len > 0) {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "|ingress|failover redirect %V|", &ctx->failover_rule->redirect_host);
        *ret_code = ngx_http_send_redirect_to_client(r, &ctx->failover_rule->redirect_host);
    } else {
        ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "|ingress|failover named location %V|", &ilcf->failover_named_location);
        *ret_code = ngx_http_named_location(r, &ilcf->failover_named_location);
    }

    return NGX_DONE;
}
