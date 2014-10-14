
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


static ngx_int_t ngx_http_send_error_page(ngx_http_request_t *r,
    ngx_http_err_page_t *err_page);
static ngx_int_t ngx_http_send_special_response(ngx_http_request_t *r,
    ngx_http_core_loc_conf_t *clcf, ngx_uint_t err);
static ngx_int_t ngx_http_send_refresh(ngx_http_request_t *r);
static ngx_buf_t *ngx_http_set_server_info(ngx_http_request_t *r);


static u_char ngx_http_error_doctype[] =
"<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">" CRLF;


static u_char ngx_http_server_info_head[] =
" Sorry for the inconvenience.<br/>" CRLF
"Please report this message and include the following information to us.<br/>"
CRLF
"Thank you very much!</p>" CRLF
"<table>" CRLF
"<tr>" CRLF
"<td>URL:</td>" CRLF
"<td>"
;


static u_char ngx_http_server_info_server[] =
"</td>" CRLF
"</tr>" CRLF
"<tr>" CRLF
"<td>Server:</td>" CRLF
"<td>"
;


static u_char ngx_http_server_info_admin[] =
"</td>" CRLF
"</tr>" CRLF
"<tr>" CRLF
"<td>Admin:</td>" CRLF
"<td>"
;


static u_char ngx_http_server_info_date[] =
"</td>" CRLF
"</tr>" CRLF
"<tr>" CRLF
"<td>Date:</td>" CRLF
"<td>"
;


static u_char ngx_http_server_info_tail[] =
"</td>" CRLF
"</tr>" CRLF
"</table>" CRLF
;


static u_char ngx_http_error_banner[] =
"<hr/>Powered by " TENGINE;


static u_char ngx_http_error_full_banner[] =
"<hr/>Powered by " TENGINE_VER;


static u_char ngx_http_error_powered_by[] =
"<hr/>Powered by ";


static u_char ngx_http_error_tail[] =
"</body>" CRLF
"</html>" CRLF
;


static u_char ngx_http_msie_padding[] =
"<!-- a padding to disable MSIE and Chrome friendly error page -->" CRLF
"<!-- a padding to disable MSIE and Chrome friendly error page -->" CRLF
"<!-- a padding to disable MSIE and Chrome friendly error page -->" CRLF
"<!-- a padding to disable MSIE and Chrome friendly error page -->" CRLF
"<!-- a padding to disable MSIE and Chrome friendly error page -->" CRLF
"<!-- a padding to disable MSIE and Chrome friendly error page -->" CRLF
;


static u_char ngx_http_msie_refresh_head[] =
"<html><head><meta http-equiv=\"Refresh\" content=\"0; URL=";


static u_char ngx_http_msie_refresh_tail[] =
"\"></head><body></body></html>" CRLF;


static char ngx_http_error_301_page[] =
"<html>" CRLF
"<head><title>301 Moved Permanently</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>301 Moved Permanently</h1>" CRLF
"<p>The requested resource has been assigned a new permanent URI.</p>" CRLF
;


static char ngx_http_error_302_page[] =
"<html>" CRLF
"<head><title>302 Found</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>302 Found</h1>" CRLF
"<p>The requested resource resides temporarily under a different URI.</p>" CRLF
;


static char ngx_http_error_303_page[] =
"<html>" CRLF
"<head><title>303 See Other</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>303 See Other</h1>" CRLF
"<p>The response to the request can be found under a different URI.</p>" CRLF
;


static char ngx_http_error_307_page[] =
"<html>" CRLF
"<head><title>307 Temporary Redirect</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>307 Temporary Redirect</h1>" CRLF
"<p>The requested resource resides temporarily under a different URI.</p>" CRLF
;


static char ngx_http_error_400_page[] =
"<html>" CRLF
"<head><title>400 Bad Request</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>400 Bad Request</h1>" CRLF
"<p>Your browser sent a request that this server could not understand."
;


static char ngx_http_error_401_page[] =
"<html>" CRLF
"<head><title>401 Authorization Required</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>401 Authorization Required</h1>" CRLF
"<p>This server could not verify that you are authorized to access the "
"document requested."
;


static char ngx_http_error_402_page[] =
"<html>" CRLF
"<head><title>402 Payment Required</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>402 Payment Required</h1>" CRLF
"<p>Payment required."
;


static char ngx_http_error_403_page[] =
"<html>" CRLF
"<head><title>403 Forbidden</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>403 Forbidden</h1>" CRLF
"<p>You don't have permission to access the URL on this server."
;


static char ngx_http_error_404_page[] =
"<html>" CRLF
"<head><title>404 Not Found</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>404 Not Found</h1>" CRLF
"<p>The requested URL was not found on this server."
;


static char ngx_http_error_405_page[] =
"<html>" CRLF
"<head><title>405 Method Not Allowed</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>405 Method Not Allowed</h1>" CRLF
"<p>The requested method is not allowed for the URL."
;


static char ngx_http_error_406_page[] =
"<html>" CRLF
"<head><title>406 Not Acceptable</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>406 Not Acceptable</h1>" CRLF
"<p>An appropriate representation of the requested resource could not "
"be found on this server."
;


static char ngx_http_error_408_page[] =
"<html>" CRLF
"<head><title>408 Request Time-out</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>408 Request Time-out</h1>" CRLF
"<p>Server timeout waiting for the HTTP request from the client."
;


static char ngx_http_error_409_page[] =
"<html>" CRLF
"<head><title>409 Conflict</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>409 Conflict</h1>" CRLF
"<p>The request could not be completed due to a conflict with the current "
"state of the resource."
;


static char ngx_http_error_410_page[] =
"<html>" CRLF
"<head><title>410 Gone</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>410 Gone</h1>" CRLF
"<p>The requested resource is no longer available on this server and there "
"is no forwarding address. Please remove all references to this resource."
;


static char ngx_http_error_411_page[] =
"<html>" CRLF
"<head><title>411 Length Required</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>411 Length Required</h1>" CRLF
"<p>A request of the requested method requires a valid Content-length."
;


static char ngx_http_error_412_page[] =
"<html>" CRLF
"<head><title>412 Precondition Failed</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>412 Precondition Failed</h1>" CRLF
"<p>The precondition on the request for the URL evaluated to false."
;


static char ngx_http_error_413_page[] =
"<html>" CRLF
"<head><title>413 Request Entity Too Large</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>413 Request Entity Too Large</h1>" CRLF
"<P>The requested resource does not allow request data with the requested "
"method or the amount of data provided in the request exceeds the capacity "
"limit."
;


static char ngx_http_error_414_page[] =
"<html>" CRLF
"<head><title>414 Request-URI Too Large</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>414 Request-URI Too Large</h1>" CRLF
"<p>The requested URL's length exceeds the capacity limit for this server."
;


static char ngx_http_error_415_page[] =
"<html>" CRLF
"<head><title>415 Unsupported Media Type</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>415 Unsupported Media Type</h1>" CRLF
"<p>The supplied request data is not in a format acceptable for processing "
"by this resource."
;


static char ngx_http_error_416_page[] =
"<html>" CRLF
"<head><title>416 Requested Range Not Satisfiable</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>416 Requested Range Not Satisfiable</h1>" CRLF
"<p>None of the range-specifier values in the Range request-header field "
"overlap the current extent of the selected resource."
;


static char ngx_http_error_494_page[] =
"<html>" CRLF
"<head><title>400 Request Header Or Cookie Too Large</title></head>"
CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>400 Bad Request</h1>" CRLF
"<p>Request header or cookie too large."
;


static char ngx_http_error_495_page[] =
"<html>" CRLF
"<head><title>400 The SSL certificate error</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>400 Bad Request</h1>" CRLF
"<p>The SSL certificate error."
;


static char ngx_http_error_496_page[] =
"<html>" CRLF
"<head><title>400 No required SSL certificate was sent</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>400 Bad Request</h1>" CRLF
"<p>No required SSL certificate was sent."
;


static char ngx_http_error_497_page[] =
"<html>" CRLF
"<head><title>400 The plain HTTP request was sent to HTTPS port</title></head>"
CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>400 Bad Request</h1>" CRLF
"<p>The plain HTTP request was sent to HTTPS port."
;


static char ngx_http_error_500_page[] =
"<html>" CRLF
"<head><title>500 Internal Server Error</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>500 Internal Server Error</h1>" CRLF
"<p>The server encountered an internal error or misconfiguration and was "
"unable to complete your request."
;


static char ngx_http_error_501_page[] =
"<html>" CRLF
"<head><title>501 Not Implemented</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>501 Not Implemented</h1>" CRLF
"<p>The requested method to the URL not supported."
;


static char ngx_http_error_502_page[] =
"<html>" CRLF
"<head><title>502 Bad Gateway</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>502 Bad Gateway</h1>" CRLF
"<p>The proxy server received an invalid response from an upstream server."
;


static char ngx_http_error_503_page[] =
"<html>" CRLF
"<head><title>503 Service Temporarily Unavailable</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>503 Service Temporarily Unavailable</h1>" CRLF
"<p>The server is temporarily unable to service your request due to "
"maintenance downtime or capacity problems. Please try again later."
;


static char ngx_http_error_504_page[] =
"<html>" CRLF
"<head><title>504 Gateway Time-out</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>504 Gateway Time-out</h1>" CRLF
"<p>The gateway did not receive a timely response from the upstream server "
"or application."
;


static char ngx_http_error_507_page[] =
"<html>" CRLF
"<head><title>507 Insufficient Storage</title></head>" CRLF
"<body bgcolor=\"white\">" CRLF
"<h1>507 Insufficient Storage</h1>" CRLF
"<p>A mandatory extension policy in the request is not accepted by the server "
"for this resource."
;


static ngx_str_t ngx_http_error_pages[] = {

    ngx_null_string,                     /* 201, 204 */

#define NGX_HTTP_LAST_2XX  202
#define NGX_HTTP_OFF_3XX   (NGX_HTTP_LAST_2XX - 201)

    /* ngx_null_string, */               /* 300 */
    ngx_string(ngx_http_error_301_page),
    ngx_string(ngx_http_error_302_page),
    ngx_string(ngx_http_error_303_page),
    ngx_null_string,                     /* 304 */
    ngx_null_string,                     /* 305 */
    ngx_null_string,                     /* 306 */
    ngx_string(ngx_http_error_307_page),

#define NGX_HTTP_LAST_3XX  308
#define NGX_HTTP_OFF_4XX   (NGX_HTTP_LAST_3XX - 301 + NGX_HTTP_OFF_3XX)

    ngx_string(ngx_http_error_400_page),
    ngx_string(ngx_http_error_401_page),
    ngx_string(ngx_http_error_402_page),
    ngx_string(ngx_http_error_403_page),
    ngx_string(ngx_http_error_404_page),
    ngx_string(ngx_http_error_405_page),
    ngx_string(ngx_http_error_406_page),
    ngx_null_string,                     /* 407 */
    ngx_string(ngx_http_error_408_page),
    ngx_string(ngx_http_error_409_page),
    ngx_string(ngx_http_error_410_page),
    ngx_string(ngx_http_error_411_page),
    ngx_string(ngx_http_error_412_page),
    ngx_string(ngx_http_error_413_page),
    ngx_string(ngx_http_error_414_page),
    ngx_string(ngx_http_error_415_page),
    ngx_string(ngx_http_error_416_page),

#define NGX_HTTP_LAST_4XX  417
#define NGX_HTTP_OFF_5XX   (NGX_HTTP_LAST_4XX - 400 + NGX_HTTP_OFF_4XX)

    ngx_string(ngx_http_error_494_page), /* 494, request header too large */
    ngx_string(ngx_http_error_495_page), /* 495, https certificate error */
    ngx_string(ngx_http_error_496_page), /* 496, https no certificate */
    ngx_string(ngx_http_error_497_page), /* 497, http to https */
    ngx_string(ngx_http_error_404_page), /* 498, canceled */
    ngx_null_string,                     /* 499, client has closed connection */

    ngx_string(ngx_http_error_500_page),
    ngx_string(ngx_http_error_501_page),
    ngx_string(ngx_http_error_502_page),
    ngx_string(ngx_http_error_503_page),
    ngx_string(ngx_http_error_504_page),
    ngx_null_string,                     /* 505 */
    ngx_null_string,                     /* 506 */
    ngx_string(ngx_http_error_507_page)

#define NGX_HTTP_LAST_5XX  508

};


static ngx_str_t  ngx_http_get_name = { 3, (u_char *) "GET " };


ngx_int_t
ngx_http_special_response_handler(ngx_http_request_t *r, ngx_int_t error)
{
    ngx_uint_t                 i, err;
    ngx_http_err_page_t       *err_page;
    ngx_http_core_loc_conf_t  *clcf;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http special response: %i, \"%V?%V\"",
                   error, &r->uri, &r->args);

    r->err_status = error;

    if (r->keepalive) {
        switch (error) {
            case NGX_HTTP_BAD_REQUEST:
            case NGX_HTTP_REQUEST_ENTITY_TOO_LARGE:
            case NGX_HTTP_REQUEST_URI_TOO_LARGE:
            case NGX_HTTP_TO_HTTPS:
            case NGX_HTTPS_CERT_ERROR:
            case NGX_HTTPS_NO_CERT:
            case NGX_HTTP_INTERNAL_SERVER_ERROR:
            case NGX_HTTP_NOT_IMPLEMENTED:
                r->keepalive = 0;
        }
    }

    if (r->lingering_close) {
        switch (error) {
            case NGX_HTTP_BAD_REQUEST:
            case NGX_HTTP_TO_HTTPS:
            case NGX_HTTPS_CERT_ERROR:
            case NGX_HTTPS_NO_CERT:
                r->lingering_close = 0;
        }
    }

    r->headers_out.content_type.len = 0;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (!r->error_page && clcf->error_pages && r->uri_changes != 0) {

        if (clcf->recursive_error_pages == 0) {
            r->error_page = 1;
        }

        err_page = clcf->error_pages->elts;

        for (i = 0; i < clcf->error_pages->nelts; i++) {
            if (err_page[i].status == error) {
                return ngx_http_send_error_page(r, &err_page[i]);
            }
        }
    }

    r->expect_tested = 1;

    if (ngx_http_discard_request_body(r) != NGX_OK) {
        r->keepalive = 0;
    }

    if (clcf->msie_refresh
        && r->headers_in.msie
        && (error == NGX_HTTP_MOVED_PERMANENTLY
            || error == NGX_HTTP_MOVED_TEMPORARILY))
    {
        return ngx_http_send_refresh(r);
    }

    if (error == NGX_HTTP_CREATED) {
        /* 201 */
        err = 0;

    } else if (error == NGX_HTTP_NO_CONTENT) {
        /* 204 */
        err = 0;

    } else if (error >= NGX_HTTP_MOVED_PERMANENTLY
               && error < NGX_HTTP_LAST_3XX)
    {
        /* 3XX */
        err = error - NGX_HTTP_MOVED_PERMANENTLY + NGX_HTTP_OFF_3XX;

    } else if (error >= NGX_HTTP_BAD_REQUEST
               && error < NGX_HTTP_LAST_4XX)
    {
        /* 4XX */
        err = error - NGX_HTTP_BAD_REQUEST + NGX_HTTP_OFF_4XX;

    } else if (error >= NGX_HTTP_NGINX_CODES
               && error < NGX_HTTP_LAST_5XX)
    {
        /* 49X, 5XX */
        err = error - NGX_HTTP_NGINX_CODES + NGX_HTTP_OFF_5XX;
        switch (error) {
            case NGX_HTTP_TO_HTTPS:
            case NGX_HTTPS_CERT_ERROR:
            case NGX_HTTPS_NO_CERT:
            case NGX_HTTP_REQUEST_HEADER_TOO_LARGE:
                r->err_status = NGX_HTTP_BAD_REQUEST;
                break;
        }

    } else {
        /* unknown code, zero body */
        err = 0;
    }

    return ngx_http_send_special_response(r, clcf, err);
}


ngx_int_t
ngx_http_filter_finalize_request(ngx_http_request_t *r, ngx_module_t *m,
    ngx_int_t error)
{
    void       *ctx;
    ngx_int_t   rc;

    ngx_http_clean_header(r);

    ctx = NULL;

    if (m) {
        ctx = r->ctx[m->ctx_index];
    }

    /* clear the modules contexts */
    ngx_memzero(r->ctx, sizeof(void *) * ngx_http_max_module);

    if (m) {
        r->ctx[m->ctx_index] = ctx;
    }

    r->filter_finalize = 1;

    rc = ngx_http_special_response_handler(r, error);

    /* NGX_ERROR resets any pending data */

    switch (rc) {

    case NGX_OK:
    case NGX_DONE:
        return NGX_ERROR;

    default:
        return rc;
    }
}


void
ngx_http_clean_header(ngx_http_request_t *r)
{
    ngx_memzero(&r->headers_out.status,
                sizeof(ngx_http_headers_out_t)
                    - offsetof(ngx_http_headers_out_t, status));

    r->headers_out.headers.part.nelts = 0;
    r->headers_out.headers.part.next = NULL;
    r->headers_out.headers.last = &r->headers_out.headers.part;

    r->headers_out.content_length_n = -1;
    r->headers_out.last_modified_time = -1;
}


static ngx_int_t
ngx_http_send_error_page(ngx_http_request_t *r, ngx_http_err_page_t *err_page)
{
    ngx_int_t                  overwrite;
    ngx_str_t                  uri, args;
    ngx_table_elt_t           *location;
    ngx_http_core_loc_conf_t  *clcf;

    overwrite = err_page->overwrite;

    if (overwrite && overwrite != NGX_HTTP_OK) {
        r->expect_tested = 1;
    }

    if (overwrite >= 0) {
        r->err_status = overwrite;
    }

    if (ngx_http_complex_value(r, &err_page->value, &uri) != NGX_OK) {
        return NGX_ERROR;
    }

    if (uri.data[0] == '/') {

        if (err_page->value.lengths) {
            ngx_http_split_args(r, &uri, &args);

        } else {
            args = err_page->args;
        }

        if (r->method != NGX_HTTP_HEAD) {
            r->method = NGX_HTTP_GET;
            r->method_name = ngx_http_get_name;
        }

        return ngx_http_internal_redirect(r, &uri, &args);
    }

    if (uri.data[0] == '@') {
        return ngx_http_named_location(r, &uri);
    }

    location = ngx_list_push(&r->headers_out.headers);

    if (location == NULL) {
        return NGX_ERROR;
    }

    if (overwrite != NGX_HTTP_MOVED_PERMANENTLY
        && overwrite != NGX_HTTP_MOVED_TEMPORARILY
        && overwrite != NGX_HTTP_SEE_OTHER
        && overwrite != NGX_HTTP_TEMPORARY_REDIRECT)
    {
        r->err_status = NGX_HTTP_MOVED_TEMPORARILY;
    }

    location->hash = 1;
    ngx_str_set(&location->key, "Location");
    location->value = uri;

    ngx_http_clear_location(r);

    r->headers_out.location = location;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    if (clcf->msie_refresh && r->headers_in.msie) {
        return ngx_http_send_refresh(r);
    }

    return ngx_http_send_special_response(r, clcf, r->err_status
                                                   - NGX_HTTP_MOVED_PERMANENTLY
                                                   + NGX_HTTP_OFF_3XX);
}


static ngx_int_t
ngx_http_send_special_response(ngx_http_request_t *r,
    ngx_http_core_loc_conf_t *clcf, ngx_uint_t err)
{
    ngx_int_t     rc;
    ngx_buf_t    *b, *ib;
    ngx_uint_t    i, msie_padding;
    ngx_chain_t   out[7];

    if (clcf->server_info && err >= NGX_HTTP_OFF_4XX) {
        ib = ngx_http_set_server_info(r);
        if (ib == NULL) {
            return NGX_ERROR;
        }

    } else {
        ib = NULL;
    }

    msie_padding = 0;

    if (ngx_http_error_pages[err].len) {
        r->headers_out.content_length_n = sizeof(ngx_http_error_doctype) - 1
                                          + ngx_http_error_pages[err].len
                                          + (ib ? (ib->last - ib->pos) : 0)
                                          + sizeof(ngx_http_error_tail) - 1;

        if (clcf->server_tag_type == NGX_HTTP_SERVER_TAG_ON) {
            r->headers_out.content_length_n += clcf->server_tokens
                ? sizeof(ngx_http_error_full_banner) - 1
                : sizeof(ngx_http_error_banner) - 1;

        } else if (clcf->server_tag_type == NGX_HTTP_SERVER_TAG_CUSTOMIZED) {
            r->headers_out.content_length_n += sizeof(ngx_http_error_powered_by)
                                               - 1;
            r->headers_out.content_length_n += clcf->server_tag.len;
        }

        if (clcf->msie_padding
            && (r->headers_in.msie || r->headers_in.chrome)
            && r->http_version >= NGX_HTTP_VERSION_10
            && err >= NGX_HTTP_OFF_4XX)
        {
            r->headers_out.content_length_n +=
                                         sizeof(ngx_http_msie_padding) - 1;
            msie_padding = 1;
        }

        r->headers_out.content_type_len = sizeof("text/html") - 1;
        ngx_str_set(&r->headers_out.content_type, "text/html");
        r->headers_out.content_type_lowcase = NULL;

    } else {
        r->headers_out.content_length_n = 0;
    }

    if (r->headers_out.content_length) {
        r->headers_out.content_length->hash = 0;
        r->headers_out.content_length = NULL;
    }

    ngx_http_clear_accept_ranges(r);
    ngx_http_clear_last_modified(r);
    ngx_http_clear_etag(r);

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || r->header_only) {
        return rc;
    }

    if (ngx_http_error_pages[err].len == 0) {
        return ngx_http_send_special(r, NGX_HTTP_LAST);
    }

    i = 0;

    b = ngx_calloc_buf(r->pool);
    if (b == NULL) {
        return NGX_ERROR;
    }

    b->memory = 1;
    b->pos = ngx_http_error_doctype;
    b->last = ngx_http_error_doctype + sizeof(ngx_http_error_doctype) - 1;

    out[i].buf = b;
    out[i].next = &out[i + 1];
    i++;

    b = ngx_calloc_buf(r->pool);
    if (b == NULL) {
        return NGX_ERROR;
    }

    b->memory = 1;
    b->pos = ngx_http_error_pages[err].data;
    b->last = ngx_http_error_pages[err].data + ngx_http_error_pages[err].len;

    out[i].buf = b;
    out[i].next = &out[i + 1];
    i++;

    if (ib) {
        out[i].buf = ib;
        out[i].next = &out[i + 1];
        i++;
    }

    if (clcf->server_tag_type == NGX_HTTP_SERVER_TAG_ON) {
        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            return NGX_ERROR;
        }

        b->memory = 1;

        if (clcf->server_tokens) {
            b->pos = ngx_http_error_full_banner;
            b->last = ngx_http_error_full_banner
                      + sizeof(ngx_http_error_full_banner) - 1;

        } else {
            b->pos = ngx_http_error_banner;
            b->last = ngx_http_error_banner + sizeof(ngx_http_error_banner) - 1;
        }

        out[i].buf = b;
        out[i].next = &out[i + 1];
        i++;

    } else if (clcf->server_tag_type == NGX_HTTP_SERVER_TAG_CUSTOMIZED) {
        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            return NGX_ERROR;
        }

        b->memory = 1;
        b->pos = ngx_http_error_powered_by;
        b->last = ngx_http_error_powered_by
                  + sizeof(ngx_http_error_powered_by) - 1;

        out[i].buf = b;
        out[i].next = &out[i + 1];
        i++;

        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            return NGX_ERROR;
        }

        b->memory = 1;
        b->pos = clcf->server_tag.data;
        b->last = clcf->server_tag.data + clcf->server_tag.len;

        out[i].buf = b;
        out[i].next = &out[i + 1];
        i++;
    }

    b = ngx_calloc_buf(r->pool);
    if (b == NULL) {
        return NGX_ERROR;
    }

    b->memory = 1;

    b->pos = ngx_http_error_tail;
    b->last = ngx_http_error_tail + sizeof(ngx_http_error_tail) - 1;

    out[i].buf = b;
    out[i].next = NULL;

    if (msie_padding) {
        b = ngx_calloc_buf(r->pool);
        if (b == NULL) {
            return NGX_ERROR;
        }

        b->memory = 1;
        b->pos = ngx_http_msie_padding;
        b->last = ngx_http_msie_padding + sizeof(ngx_http_msie_padding) - 1;

        out[i].next = &out[i + 1];
        i++;
        out[i].buf = b;
        out[i].next = NULL;
    }

    if (r == r->main) {
        b->last_buf = 1;
    }

    b->last_in_chain = 1;

    return ngx_http_output_filter(r, &out[0]);
}


static ngx_int_t
ngx_http_send_refresh(ngx_http_request_t *r)
{
    u_char       *p, *location;
    size_t        len, size;
    uintptr_t     escape;
    ngx_int_t     rc;
    ngx_buf_t    *b;
    ngx_chain_t   out;

    len = r->headers_out.location->value.len;
    location = r->headers_out.location->value.data;

    escape = 2 * ngx_escape_uri(NULL, location, len, NGX_ESCAPE_REFRESH);

    size = sizeof(ngx_http_msie_refresh_head) - 1
           + escape + len
           + sizeof(ngx_http_msie_refresh_tail) - 1;

    r->err_status = NGX_HTTP_OK;

    r->headers_out.content_type_len = sizeof("text/html") - 1;
    ngx_str_set(&r->headers_out.content_type, "text/html");
    r->headers_out.content_type_lowcase = NULL;

    r->headers_out.location->hash = 0;
    r->headers_out.location = NULL;

    r->headers_out.content_length_n = size;

    if (r->headers_out.content_length) {
        r->headers_out.content_length->hash = 0;
        r->headers_out.content_length = NULL;
    }

    ngx_http_clear_accept_ranges(r);
    ngx_http_clear_last_modified(r);

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || r->header_only) {
        return rc;
    }

    b = ngx_create_temp_buf(r->pool, size);
    if (b == NULL) {
        return NGX_ERROR;
    }

    p = ngx_cpymem(b->pos, ngx_http_msie_refresh_head,
                   sizeof(ngx_http_msie_refresh_head) - 1);

    if (escape == 0) {
        p = ngx_cpymem(p, location, len);

    } else {
        p = (u_char *) ngx_escape_uri(p, location, len, NGX_ESCAPE_REFRESH);
    }

    b->last = ngx_cpymem(p, ngx_http_msie_refresh_tail,
                         sizeof(ngx_http_msie_refresh_tail) - 1);

    b->last_buf = 1;
    b->last_in_chain = 1;

    out.buf = b;
    out.next = NULL;

    return ngx_http_output_filter(r, &out);
}


static ngx_buf_t *
ngx_http_set_server_info(ngx_http_request_t *r)
{
    size_t                     size;
    ngx_buf_t                 *b;
    uintptr_t                  euri, ehost;
    ngx_str_t                 *host, scheme, port;
    ngx_uint_t                 p;
    struct sockaddr_in        *sin;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6       *sin6;
#endif
    ngx_http_core_srv_conf_t  *cscf;

    cscf = ngx_http_get_module_srv_conf(r, ngx_http_core_module);

    ngx_str_null(&scheme);

#if (NGX_HTTP_SSL)

    if (r->connection->ssl) {
        ngx_str_set(&scheme, "https://");
    }

#endif

    if (scheme.len == 0) {
        ngx_str_set(&scheme, "http://");
    }

    if (r->headers_in.server.len) {
        host = &r->headers_in.server;

    } else {
        host = &cscf->server_name;
    }

    if (ngx_connection_local_sockaddr(r->connection, NULL, 0) != NGX_OK) {
        return NULL;
    }

    ngx_str_null(&port);

    switch (r->connection->local_sockaddr->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:
        sin6 = (struct sockaddr_in6 *) r->connection->local_sockaddr;
        p = ntohs(sin6->sin6_port);
        break;
#endif

    default:
        sin = (struct sockaddr_in *) r->connection->local_sockaddr;
        p = ntohs(sin->sin_port);
        break;
    }

    if (p > 0 && p < 65536 && p != 80 && p != 443) {
        port.data = ngx_pnalloc(r->pool, sizeof(":65535") - 1);
        if (port.data == NULL) {
            return NULL;
        }

        port.len = ngx_sprintf(port.data, ":%ui", p) - port.data;
    }

    ehost = ngx_escape_html(NULL, host->data, host->len);
    euri = ngx_escape_html(NULL, r->unparsed_uri.data, r->unparsed_uri.len);

    size = sizeof(ngx_http_server_info_head) - 1
           + scheme.len + host->len + ehost
           + port.len + r->unparsed_uri.len + euri
           + sizeof(ngx_http_server_info_server) - 1
           + ngx_cycle->hostname.len
           + sizeof(ngx_http_server_info_date) - 1
           + ngx_cached_err_log_time.len
           + sizeof(ngx_http_server_info_tail) - 1;

    if (cscf->server_admin.len) {
        size += sizeof(ngx_http_server_info_admin) - 1 + cscf->server_admin.len;
    }

    b = ngx_create_temp_buf(r->pool, size);
    if (b == NULL) {
        return NULL;
    }

    b->last = ngx_cpymem(b->last, ngx_http_server_info_head,
                         sizeof(ngx_http_server_info_head) - 1);
    b->last = ngx_cpymem(b->last, scheme.data, scheme.len);

    if (ehost == 0) {
        b->last = ngx_cpymem(b->last, host->data, host->len);

    } else {
        b->last = (u_char *) ngx_escape_html(b->last, host->data, host->len);
    }

    if (port.len) {
        b->last = ngx_cpymem(b->last, port.data, port.len);
    }

    if (euri == 0) {
        b->last = ngx_cpymem(b->last, r->unparsed_uri.data,
                             r->unparsed_uri.len);

    } else {
        b->last = (u_char *) ngx_escape_html(b->last, r->unparsed_uri.data,
                                             r->unparsed_uri.len);
    }

    b->last = ngx_cpymem(b->last, ngx_http_server_info_server,
                         sizeof(ngx_http_server_info_server) - 1);
    b->last = ngx_cpymem(b->last, ngx_cycle->hostname.data,
                         ngx_cycle->hostname.len);

    if (cscf->server_admin.len) {
        b->last = ngx_cpymem(b->last, ngx_http_server_info_admin,
                             sizeof(ngx_http_server_info_admin) - 1);
        b->last = ngx_cpymem(b->last, cscf->server_admin.data,
                             cscf->server_admin.len);
    }

    b->last = ngx_cpymem(b->last, ngx_http_server_info_date,
                         sizeof(ngx_http_server_info_date) - 1);
    b->last = ngx_cpymem(b->last, ngx_cached_err_log_time.data,
                         ngx_cached_err_log_time.len);
    b->last = ngx_cpymem(b->last, ngx_http_server_info_tail,
                         sizeof(ngx_http_server_info_tail) - 1);

    return b;
}
