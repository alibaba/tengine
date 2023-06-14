/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include "ngx_comm_string.h"


ngx_int_t
comm_split_string(ngx_str_t * out, ngx_int_t out_len, ngx_str_t * in, u_char terminate)
{
    u_char * pos = in->data;
    u_char * last = in->data + in->len;

    ngx_int_t index = 0;
    ngx_int_t last_emtpy = 0;

    while (index < out_len && pos < last) {
        out[index].data = pos;
        out[index].len = 0;
        while (pos < last) {
            if (*pos == terminate) {
                pos ++;
                last_emtpy = 1;
                break;
            }
            pos ++;
            out[index].len ++;
            last_emtpy = 0;
        }
        index ++;
    }
    if (last_emtpy == 1 && index < out_len - 1) {
        out[index].data = pos;
        out[index].len = 0;
        index ++;
    }
    return index;
}


#define UNIT_MAX_LONGLONG_T_VALUE  9223372036854775807

long long int
comm_atoll(u_char *line, size_t n)
{
    long long int  value, cutoff, cutlim;

    if (n == 0) {
        return NGX_ERROR;
    }

    cutoff = UNIT_MAX_LONGLONG_T_VALUE / 10;
    cutlim = UNIT_MAX_LONGLONG_T_VALUE % 10;

    for (value = 0; n--; line++) {
        if (*line < '0' || *line > '9') {
            return NGX_ERROR;
        }

        if (value >= cutoff && (value > cutoff || *line - '0' > cutlim)) {
            return NGX_ERROR;
        }

        value = value * 10 + (*line - '0');
    }

    return value;
}

long long int
comm_atoll_with_trim(u_char *line, size_t n)
{
    while (n > 0 && isspace(*line)) {
        line++;
        n--;
    }
    while (n > 0 && isspace(line[n-1])) {
        n--;
    }
    return comm_atoll(line, n);
}


ngx_int_t ngx_comm_strcasecmp(ngx_str_t * src, ngx_str_t * dst) {
    if (src->len != dst->len) {
        return src->len - dst->len;
    }

    return ngx_strncasecmp(src->data, dst->data, src->len);
}


void
ngx_strupper(u_char *dst, u_char *src, size_t n)
{
    while (n) {
        *dst = ngx_toupper(*src);
        dst++;
        src++;
        n--;
    }
}

int ngx_comm_strcmp(const ngx_str_t * v1, const ngx_str_t * v2)
{
    if (v1->len != v2->len) {
        return v1->len - v2->len;
    }
    return ngx_strncmp(v1->data, v2->data, v1->len);
}


ngx_str_t*
ngx_comm_str_dup(ngx_pool_t * pool, ngx_str_t * src)
{
    ngx_str_t * dst = NULL;
    u_char * p;

    p = ngx_palloc(pool, sizeof(ngx_str_t) + src->len);
    if (p == NULL) {
        return dst;
    }

    dst = (ngx_str_t*)p;

    dst->len = src->len;
    dst->data = p + sizeof(ngx_str_t);
    memcpy(dst->data, src->data, src->len);

    return dst;
}

int
ngx_comm_cstr_casecmp(const char * src, size_t src_len, ngx_str_t * dst)
{
    if (src_len != dst->len) {
        return src_len - dst->len;
    }
    return ngx_strncasecmp((u_char *)src, dst->data, src_len);
}


int
ngx_comm_count_character(u_char * pos, u_char * last, char c)
{
    int cnt;
    for (cnt = 0; pos < last; pos++) {
        if (*pos == c) {
            cnt ++;
        }
    }
    return cnt;
}

u_char *
ngx_comm_strchr(u_char * pos, u_char * last, char c)
{
    for (; pos < last; pos++) {
        if (*pos == c) {
            return pos;
        }
    }
    return NULL;
}

ngx_int_t
ngx_comm_split_string(ngx_str_t * arr, ngx_int_t n,
    u_char * pos, u_char * last, u_char terminate)
{
    ngx_str_t input = {last - pos, pos};
    return comm_split_string(arr, n , &input, terminate);
}

ngx_int_t
ngx_comm_trim_string(ngx_str_t * source)
{
    ngx_int_t cnt = 0;
    ngx_uint_t i;
    for (i = 0; i < source->len; i++) {
        if (!isspace(source->data[i])) {
            break;
        }
    }
    source->data += i;
    source->len -= i;
    cnt += i;
    for (i = 0; i < source->len; i++) {
        if (!isspace(source->data[source->len - i - 1])) {
            break;
        }
    }
    source->len -= i;
    cnt += i;
    return cnt;
}

ngx_int_t ngx_comm_strcpy(ngx_pool_t * pool, ngx_str_t * dst, ngx_str_t * src)
{
    dst->data = ngx_palloc(pool, src->len);
    if (dst->data == NULL) {
        return NGX_ERROR;
    }

    dst->len = src->len;
    memcpy(dst->data, src->data, src->len);

    return NGX_OK;
}

ngx_int_t ngx_comm_parse_string_value(ngx_str_t *line, ngx_str_t *key, ngx_str_t *value, u_char terminate)
{
#define MAX_LINE_KEY_NUM    128
    ngx_str_t arr[MAX_LINE_KEY_NUM];
    ngx_int_t i;

    ngx_int_t num = comm_split_string(arr, MAX_LINE_KEY_NUM, line, terminate);
    if (num == MAX_LINE_KEY_NUM) {
        return NGX_ERROR;
    }

    for (i = 0; i < num; i++) {
        ngx_str_t kv[3];
        ngx_int_t kv_num = comm_split_string(kv, 3, &arr[i], '=');
        if (kv_num != 2) {
            return NGX_ERROR;
        }
        if (ngx_comm_strcmp(&kv[0], key) == 0) {
            *value = kv[1];
            return NGX_OK;
        }
    }

    return NGX_ERROR;
}

ngx_int_t ngx_comm_parse_int_value(ngx_str_t *line, ngx_str_t *key, u_char terminate)
{
    ngx_int_t rc;
    ngx_str_t value;

    rc = ngx_comm_parse_string_value(line, key, &value, terminate);
    if (rc == NGX_ERROR) {
        return rc;
    }

    rc = ngx_atoi(value.data, value.len);

    return rc;
}


ngx_int_t
ngx_comm_suffix_casecmp(ngx_str_t * src, ngx_str_t * suffix)
{
    ngx_int_t diff = src->len - suffix->len;
    if (diff < 0) {
        return NGX_ERROR;
    }

    if (ngx_strncasecmp((u_char *)src->data + diff, suffix->data, suffix->len) == 0) {
        return NGX_OK;
    }

    return NGX_ERROR;
}


ngx_int_t
ngx_comm_prefix_casecmp(ngx_str_t * src, ngx_str_t * prefix)
{
    if (src->len < prefix->len) {
        return NGX_ERROR;
    }

    if (ngx_strncasecmp(src->data, prefix->data, prefix->len) == 0) {
        return NGX_OK;
    }

    return NGX_ERROR;
}

ngx_int_t
ngx_comm_prefix_cmp(ngx_str_t * src, ngx_str_t * prefix)
{
    if (src->len < prefix->len) {
        return NGX_ERROR;
    }

    if (ngx_strncmp(src->data, prefix->data, prefix->len) == 0) {
        return NGX_OK;
    }

    return NGX_ERROR;
}


int
ngx_comm_str_compare(const void *c1, const void *c2)
{
    return ngx_comm_strcmp(c1, c2);
}
