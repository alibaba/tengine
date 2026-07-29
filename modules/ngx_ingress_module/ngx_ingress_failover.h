
#ifndef NGX_INGRESS_FAILOVER_H
#define NGX_INGRESS_FAILOVER_H

#include <ngx_config.h>
#include <ngx_http.h>

/**
 * @brief Determine whether failover is needed
 * @param r request context
 * @param status http status code
 * @return ngx_int_t NGX_OK: Failover is not configured
 * @return ngx_int_t NGX_ERROR: Failover is configured, but the status codes do not match. The processing needs to be completed and returned to the client.
 * @return ngx_int_t NGX_DONE: Configure failover, and if the status code matches, failover can be executed.
 */
ngx_int_t ngx_failover_check_handler(ngx_http_request_t *r, ngx_int_t status);

/**
 * @brief Failover entry handler, called through ngx_http_special_response_handler
 * @param r request context
 * @param status http status code
 * @param ret_code return response_handler code
 * @return ngx_int_t NGX_OK: Failover is not configured
 * @return ngx_int_t NGX_ERROR: Failover is configured, but the status codes do not match. The processing needs to be completed and returned to the client.
 * @return ngx_int_t NGX_DONE: Configure failover, and the status codes match, and failover has been performed.
 */
ngx_int_t ngx_failover_check_and_action_handler(ngx_http_request_t *r, ngx_int_t status, ngx_int_t *ret_code);

#endif // NGX_INGRESS_FAILOVER_H
