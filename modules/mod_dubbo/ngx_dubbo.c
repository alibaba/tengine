
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2018-2019 Alibaba Group Holding Limited
 */

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#include <ngx_dubbo.h>

typedef struct {
    ngx_dubbo_arg_type_t    type;
    ngx_str_t               name;
} ngx_dubbo_arg_type_value_t;

ngx_dubbo_arg_type_value_t ngx_dubbo_arg_type_map[] = {
    {
        DUBBO_ARG_STR,
        ngx_string("Ljava/lang/String;")
    },
    {
        DUBBO_ARG_INT,
        ngx_string("I")
    },
    {
        DUBBO_ARG_LSTR,
        ngx_string("Ljava/util/List;")
    },
    {
        DUBBO_ARG_MAP,
        ngx_string("Ljava/util/Map;")
    }
};

int ngx_dubbo_is_big_endian() {
    const int n = 1;
    if(*(char *)&n) {
        return 0;
    }
    return 1;
}

static const u_char DUBBO_VERSION_ENCODE[] = { 0x05, 0x32, 0x2e, 0x30, 0x2e, 0x32 };            //0x05"2.0.2"
static const u_char DUBBO_SERVICE_VERSION_ENCODE[] = { 0x05, 0x30, 0x2e, 0x30, 0x2e, 0x30 };   //0x05"0.0.0"

static const u_char DUBBO_NULL[] = { 0x4e };                                                    //"N" null
static const u_char DUBBO_FLAG_REQ_HESSIAN2 = 0xc2;                                             // 0b11000010  req & hessian2
static const u_char DUBBO_FLAG_REQ_PING_HESSIAN2 = 0xe2;                                        // 0b11000010  req & ping & hessian2

static ngx_int_t ngx_dubbo_get_request_props(ngx_pool_t *pool, ngx_str_t *props);

ngx_int_t 
ngx_dubbo_encode_request(ngx_dubbo_connection_t *dubbo_c, ngx_str_t *service_name, ngx_str_t *service_version, ngx_str_t *method_name, ngx_array_t *args, ngx_multi_request_t *multi_r)
{
    size_t                   len, i, arg_len = 0;
    ngx_str_t               *args_encode;
    ngx_dubbo_arg_t         *arg;
    uint32_t                 tmp32;
    uint64_t                 tmp64;
    ngx_buf_t               *b;
    u_char                  *p;

    ngx_str_t                service_name_encode;
    ngx_str_t                service_version_encode;
    ngx_str_t                method_name_encode;
    ngx_str_t                arg_types;
    ngx_str_t                arg_types_encode;

    ngx_str_t                props;

    //calc buf len
    len = sizeof(ngx_dubbo_header_t);

    len += sizeof(DUBBO_VERSION_ENCODE);

    //service_name
    if (NGX_OK != ngx_dubbo_hessian2_encode_str(dubbo_c->temp_pool, service_name, &service_name_encode)) {
        ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: encode hessian2 str failed %V", service_name);
        return NGX_ERROR;
    }

    len += service_name_encode.len;

    //service version
    if (NGX_OK != ngx_dubbo_hessian2_encode_str(dubbo_c->temp_pool, service_version, &service_version_encode)) {
        ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: encode hessian2 str failed %V", service_version);
        return NGX_ERROR;
    }

    len += service_version_encode.len;

    //method_name
    if (NGX_OK != ngx_dubbo_hessian2_encode_str(dubbo_c->temp_pool, method_name, &method_name_encode)) {
        ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: encode hessian2 str failed %V", method_name);
        return NGX_ERROR;
    }

    len += method_name_encode.len;

    arg = args->elts;
    args_encode = ngx_pcalloc(dubbo_c->temp_pool, sizeof(ngx_str_t) * args->nelts);
    for (i=0; i<args->nelts; i++) {
        arg_len += ngx_dubbo_arg_type_map[arg[i].type].name.len;

        switch(arg[i].type) {
        case DUBBO_ARG_STR:
            if (NGX_OK != ngx_dubbo_hessian2_encode_str(dubbo_c->temp_pool, &arg[i].value.str, &args_encode[i])) {
                ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: encode hessian2 str failed");
                return NGX_ERROR;
            }
            break;
#if 0
        case DUBBO_ARG_INT:
            if (NGX_OK != ngx_dubbo_hessian2_encode_int(dubbo_c->temp_pool, arg[i].value.n, &args_encode[i])) {
                ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: encode hessian2 str int failed");
                return NGX_ERROR;
            }
            break;

        case DUBBO_ARG_LSTR:
            if (NGX_OK != ngx_dubbo_hessian2encode_lstr(dubbo_c->temp_pool, arg[i].value.pstr, &args_encode[i])) {
                ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: encode hessian2 str list failed");
                return NGX_ERROR;
            }
            break;
#endif
        case DUBBO_ARG_MAP:
            if (NGX_OK != ngx_dubbo_hessian2_encode_payload_map(dubbo_c->temp_pool, arg[i].value.m, &args_encode[i])) {
                ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: encode hessian2 map failed");
                return NGX_ERROR;
            }
            break;
        default:
            ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: args param type unknown %d", arg[i].type);
            return NGX_ERROR;
        }

        len += args_encode[i].len;
    }

    arg_types.data = ngx_pcalloc(dubbo_c->temp_pool, arg_len);
    if (arg_types.data == NULL) {
        return NGX_ERROR;
    }
    p = arg_types.data;
    arg_types.len = arg_len;
    for (i=0; i<args->nelts; i++) {
        ngx_memcpy(p, ngx_dubbo_arg_type_map[arg[i].type].name.data, ngx_dubbo_arg_type_map[arg[i].type].name.len);
        p += ngx_dubbo_arg_type_map[arg[i].type].name.len;
    }

    if (NGX_OK != ngx_dubbo_hessian2_encode_str(dubbo_c->temp_pool, &arg_types, &arg_types_encode)) {
        ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "dubbo: encode hessian2 str failed");
        return NGX_ERROR;
    }

    len += arg_types_encode.len;

    if (NGX_OK != ngx_dubbo_get_request_props(dubbo_c->temp_pool, &props)) {
        ngx_log_error(NGX_LOG_ERR, dubbo_c->log, 0, "encode props failed");
        return NGX_ERROR;
    }

    len += props.len;

    multi_r->out = ngx_alloc_chain_link(multi_r->pool);
    if (multi_r->out == NULL) {
        return NGX_ERROR;
    }
    
    multi_r->out->buf = ngx_create_temp_buf(multi_r->pool, len);
    multi_r->out->next = NULL;
    b = multi_r->out->buf;
    if (b == NULL) {
        return NGX_ERROR;
    }

    //fixed header
    b->pos = b->start;

    b->pos[0] = MAGIC_VALUE_0;              //magic
    b->pos[1] = MAGIC_VALUE_1;              //version
    b->pos[2] = DUBBO_FLAG_REQ_HESSIAN2;    //req & hessian2
    b->pos[3] = 0;
    b->last += 4;

    //request id
    dubbo_c->last_request_id++;
    tmp64 = ngx_dubbo_hton64(dubbo_c->last_request_id);
    multi_r->id = dubbo_c->last_request_id;
    memcpy(b->last, &tmp64, 8);
    b->last += 8;

    //payload len
    tmp32 = htonl(len - sizeof(ngx_dubbo_header_t));
    memcpy(b->last, &tmp32, 4);
    b->last += 4;

    //dubbo version
    memcpy(b->last, DUBBO_VERSION_ENCODE, sizeof(DUBBO_VERSION_ENCODE));
    b->last += sizeof(DUBBO_VERSION_ENCODE);

    //service name
    memcpy(b->last, service_name_encode.data, service_name_encode.len);
    b->last += service_name_encode.len;

    //service version
    memcpy(b->last, DUBBO_SERVICE_VERSION_ENCODE, sizeof(DUBBO_VERSION_ENCODE));
    b->last += sizeof(DUBBO_SERVICE_VERSION_ENCODE);

    //method name
    memcpy(b->last, method_name_encode.data, method_name_encode.len);
    b->last += method_name_encode.len;

    //arg types
    memcpy(b->last, arg_types_encode.data, arg_types_encode.len);
    b->last += arg_types_encode.len;

    for (i=0; i<args->nelts; i++) {
        memcpy(b->last, args_encode[i].data, args_encode[i].len);
        b->last += args_encode[i].len;
    }

    //props
    memcpy(b->last, props.data, props.len);
    b->last += props.len;

    ngx_reset_pool(dubbo_c->temp_pool);
    return NGX_OK;
}

static ngx_int_t
ngx_dubbo_get_request_props(ngx_pool_t *pool, ngx_str_t *props) 
{
    //no need attachments, just use null
    props->data = (u_char*)DUBBO_NULL;
    props->len = sizeof(DUBBO_NULL);

    return NGX_OK;
}

ngx_int_t
ngx_dubbo_encode_ping_request(ngx_dubbo_connection_t *dubbo_c, ngx_multi_request_t *multi_r)
{
    size_t                   len;
    uint32_t                 tmp32;
    uint64_t                 tmp64;
    ngx_buf_t               *b;

    //calc buf len
    len = sizeof(ngx_dubbo_header_t);

    len += sizeof(DUBBO_NULL);

    multi_r->out = ngx_alloc_chain_link(multi_r->pool);
    if (multi_r->out == NULL) {
        return NGX_ERROR;
    }

    multi_r->out->buf = ngx_create_temp_buf(multi_r->pool, len);
    multi_r->out->next = NULL;
    b = multi_r->out->buf;
    if (b == NULL) {
        return NGX_ERROR;
    }

    //fixed header
    b->pos = b->start;

    b->pos[0] = MAGIC_VALUE_0;                    //magic
    b->pos[1] = MAGIC_VALUE_1;                    //version
    b->pos[2] = DUBBO_FLAG_REQ_PING_HESSIAN2;     //req & ping & hessian2
    b->pos[3] = 0;
    b->last += 4;

    //request id
    dubbo_c->last_request_id++;
    tmp64 = ngx_dubbo_hton64(dubbo_c->last_request_id);
    multi_r->id = dubbo_c->last_request_id;
    memcpy(b->last, &tmp64, 8);
    b->last += 8;

    //payload len
    tmp32 = htonl(len - sizeof(ngx_dubbo_header_t));
    memcpy(b->last, &tmp32, 4);
    b->last += 4;

    //null
    memcpy(b->last, DUBBO_NULL, sizeof(DUBBO_NULL));
    b->last += sizeof(DUBBO_NULL);

    return NGX_OK;
}

static ngx_int_t
ngx_dubbo_copy_chain(void *dst, ngx_chain_t *src, size_t len)
{
    ngx_chain_t         *cl;

    for (cl = src; cl; cl = cl->next) {
        if (len <= (size_t)ngx_buf_size(cl->buf)) {
            ngx_memcpy(dst, cl->buf->pos, len);
            cl->buf->pos += len;

            return NGX_OK;
        } else {
            ngx_memcpy(dst, cl->buf->pos, ngx_buf_size(cl->buf));
            len -= ngx_buf_size(cl->buf);
            cl->buf->last = cl->buf->pos;
        }
    }

    return NGX_AGAIN;
}

ngx_int_t
ngx_dubbo_decode_response(ngx_dubbo_connection_t *dubbo_c, ngx_chain_t *in)
{
    ngx_chain_t             *cl;
    size_t                   len = 0;
    ngx_dubbo_resp_t        *resp = &dubbo_c->resp;
    u_char                  *dst;

    //get size first
    for (cl = in; cl; cl = cl->next) {
        len += ngx_buf_size(cl->buf);
    }

    if (len == 0) {
        return NGX_AGAIN;
    }

    for ( ; ; ) {
        switch (dubbo_c->parse_state) {
            case DUBBO_PARSE_READ_HEADER:
                dst = ((u_char*)&resp->header) + dubbo_c->remain;
                if ((len + dubbo_c->remain) >= sizeof(ngx_dubbo_header_t)) {
                    ngx_dubbo_copy_chain(dst, in, sizeof(ngx_dubbo_header_t) - dubbo_c->remain);
                    len -= sizeof(ngx_dubbo_header_t) - dubbo_c->remain;

                    dubbo_c->remain = 0;

                    resp->header.payloadlen = htonl(resp->header.payloadlen);
                    resp->header.reqid = ngx_dubbo_hton64(resp->header.reqid);

                    dubbo_c->parse_state = DUBBO_PARSE_READ_PAYLOAD;
                } else {
                    if (len) {
                        ngx_dubbo_copy_chain(dst, in, len);
                        dubbo_c->remain += len;
                    }

                    return NGX_AGAIN;
                }

                break;
            case DUBBO_PARSE_READ_PAYLOAD:
                if (resp->header.payloadlen > resp->payload_alloc || resp->payload == NULL) {
                    if (resp->payload != NULL) {
                        ngx_free(resp->payload);
                    }

                    resp->payload = ngx_alloc(resp->header.payloadlen, dubbo_c->log);
                    if (resp->payload == NULL) {
                        return NGX_ERROR;
                    }
                    resp->payload_alloc = resp->header.payloadlen;
                }

                dst = ((u_char*)resp->payload) + dubbo_c->remain;
                if ((len + dubbo_c->remain) >= resp->header.payloadlen) {
                    ngx_dubbo_copy_chain(dst, in, resp->header.payloadlen - dubbo_c->remain);
                    len -= resp->header.payloadlen - dubbo_c->remain;

                    dubbo_c->remain = 0;

                    dubbo_c->parse_state = DUBBO_PARSE_READ_HEADER;

                    return NGX_DONE;
                } else {
                    if (len) {
                        ngx_dubbo_copy_chain(dst, in, len);
                        dubbo_c->remain += len;
                    }

                    return NGX_AGAIN;
                }

                break;
            default:
                return NGX_ERROR;
        }
    }

    return NGX_ERROR;
}

ngx_dubbo_connection_t*
ngx_dubbo_create_connection(ngx_connection_t *c, ngx_event_handler_pt ping_handler)
{
    ngx_dubbo_connection_t        *dubbo_c;

    dubbo_c = ngx_palloc(c->pool, sizeof(ngx_dubbo_connection_t));
    if (dubbo_c == NULL) {
        return NULL;
    }

    if (NGX_OK == ngx_dubbo_init_connection(dubbo_c, c, ping_handler)) {
        return dubbo_c;
    }

    return NULL;
}

static void
ngx_dubbo_cleanup(void *data)
{
    ngx_dubbo_connection_t      *dubbo_c = data;

    if (dubbo_c->resp.payload != NULL) {
        ngx_free(dubbo_c->resp.payload);
        dubbo_c->resp.payload = NULL;
        dubbo_c->resp.payload_alloc = 0;
    }

    ngx_destroy_pool(dubbo_c->temp_pool);

    if (dubbo_c->ping_event.timer_set) {
        ngx_del_timer(&dubbo_c->ping_event);
    }
}

ngx_int_t
ngx_dubbo_init_connection(ngx_dubbo_connection_t *dubbo_c, ngx_connection_t *c, ngx_event_handler_pt ping_handler)
{
    ngx_pool_cleanup_t      *cln;

    ngx_memzero(dubbo_c, sizeof(ngx_dubbo_connection_t));

    dubbo_c->log = c->log;
    dubbo_c->data = (void*)c;

    dubbo_c->last_request_id = 1;

    dubbo_c->temp_pool = ngx_create_pool(4096, c->log);
    if (dubbo_c->temp_pool == NULL) {
        return NGX_ERROR;
    }

    cln = ngx_pool_cleanup_add(c->pool, 0);
    if (cln == NULL) {
        return NGX_ERROR;
    }

    cln->handler = ngx_dubbo_cleanup;
    cln->data = dubbo_c;

    dubbo_c->ping_event.handler = ping_handler;
    dubbo_c->ping_event.data = c;
    dubbo_c->ping_event.log = c->log;

    return NGX_OK;
}
