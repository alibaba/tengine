/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_comm_serialize.h>

ngx_inline ngx_int_t
ngx_serialize_write_uint8(u_char **pos, uint32_t * left, uint8_t value)
{
    if (*left < sizeof(value)) {
        return NGX_ERROR;
    }

    *left -= sizeof(value);
    *(uint8_t*)(*pos) = value;

    *pos += sizeof(value);

    return NGX_OK;
}

ngx_inline ngx_int_t
ngx_serialize_write_uint16(u_char **pos, uint32_t * left, uint16_t value)
{
    if (*left < sizeof(value)) {
        return NGX_ERROR;
    }

    *left -= sizeof(value);
    *(uint16_t*)(*pos) = htons(value);

    *pos += sizeof(value);

    return NGX_OK;
}

ngx_inline ngx_int_t
ngx_serialize_write_uint32(u_char **pos, uint32_t * left, uint32_t value)
{
    if (*left < sizeof(value)) {
        return NGX_ERROR;
    }

    *left -= sizeof(value);
    *(uint32_t*)(*pos) = htonl(value);

    *pos += sizeof(value);

    return NGX_OK;
}

ngx_inline ngx_int_t
ngx_serialize_write_data(u_char **pos, uint32_t * left, void* value, uint32_t len)
{
    if (*left < len) {
        return NGX_ERROR;
    }

    *left -= len;

    *pos = ngx_cpymem(*pos, value, len);

    return NGX_OK;
}

ngx_inline ngx_int_t
ngx_serialize_write_uint8_data(u_char **pos, uint32_t * left, void* value, uint8_t len)
{
    ngx_int_t rc;
    
    rc = ngx_serialize_write_uint8(pos, left, len);
    if (rc == NGX_ERROR) {
        return rc;
    }

    return ngx_serialize_write_data(pos, left, value, len);
}

ngx_inline ngx_int_t 
ngx_serialize_write_uint16_string(u_char **pos, uint32_t * left, ngx_str_t * str)
{
    ngx_int_t rc;

    rc = ngx_serialize_write_uint16(pos, left, str->len);
    if (rc == NGX_ERROR) {
        return rc;
    }

    return ngx_serialize_write_data(pos, left, str->data, str->len);
}

ngx_inline ngx_int_t 
ngx_serialize_read_uint8(u_char **pos, uint32_t *left, uint8_t *value)
{
    if (*left < sizeof(*value)) {
        return NGX_ERROR;
    }

    *value = **pos;

    *pos += sizeof(*value);
    *left -= sizeof(*value);

    return NGX_OK;
}

ngx_inline ngx_int_t 
ngx_serialize_read_uint16(u_char **pos, uint32_t * left, uint16_t * value)
{
    if (*left < sizeof(*value)) {
        return NGX_ERROR;
    }

    *value = ntohs(*(uint16_t*)(*pos));

    *pos += sizeof(*value);
    *left -= sizeof(*value);

    return NGX_OK;
}

ngx_inline ngx_int_t 
ngx_serialize_read_uint32(u_char **pos, uint32_t * left, uint32_t * value)
{
    if (*left < sizeof(*value)) {
        return NGX_ERROR;
    }

    *value = ntohl(*(uint32_t*)(*pos));

    *pos += sizeof(*value);
    *left -= sizeof(*value);

    return NGX_OK;
}

ngx_inline ngx_int_t 
ngx_serialize_read_uint8_string(u_char **pos, uint32_t * left, ngx_str_t * str)
{
    ngx_int_t rc;
    uint8_t len;

    rc = ngx_serialize_read_uint8(pos, left, &len);
    if (rc == NGX_ERROR) {
        return rc;
    }

    if (*left < len) {
        return NGX_ERROR;
    }

    str->data = *pos;
    str->len = len;

    *pos += len;
    *left -= len;
    
    return NGX_OK;
}

ngx_inline ngx_int_t 
ngx_serialize_read_uint16_string(u_char **pos, uint32_t * left, ngx_str_t * str)
{
    ngx_int_t rc;
    uint16_t len;

    rc = ngx_serialize_read_uint16(pos, left, &len);
    if (rc == NGX_ERROR) {
        return rc;
    }

    if (*left < len) {
        return NGX_ERROR;
    }

    str->data = *pos;
    str->len = len;

    *pos += len;
    *left -= len;
    
    return NGX_OK;
}

ngx_inline ngx_int_t
ngx_serialize_read_data(u_char **pos, uint32_t * left, void* value, uint32_t len)
{
    if (*left < len) {
        return NGX_ERROR;
    }

    (void)ngx_cpymem(value, *pos, len);
    
    *pos += len;
    *left -= len;

    return NGX_OK;
}


ngx_inline ngx_int_t 
ngx_serialize_read_uint64(u_char **pos, uint32_t * left, uint64_t * value)
{
    if (*left < sizeof(*value)) {
        return NGX_ERROR;
    }

    if (__BYTE_ORDER == __LITTLE_ENDIAN)
    {
        uint64_t val = *(uint64_t*)(*pos);
        *value = (((uint64_t)htonl((uint32_t)((val << 32) >> 32))) << 32) | (unsigned int)htonl((int)(val >> 32));
    }
    else if (__BYTE_ORDER == __BIG_ENDIAN)
    {
        *value = *(uint64_t*)(*pos);
    }
    else {
        return NGX_ERROR;
    }

    *pos += sizeof(*value);
    *left -= sizeof(*value);

    return NGX_OK;
}
