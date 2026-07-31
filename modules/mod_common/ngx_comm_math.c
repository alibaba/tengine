/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

#include "ngx_comm_math.h"
#include <math.h>

static const size_t hash_size_list[] = {
    2llu, 3llu, 5llu, 7llu, 11llu, 13llu, 17llu, 23llu, 29llu, 37llu, 47llu,
    59llu, 73llu, 97llu, 127llu, 151llu, 197llu, 251llu, 313llu, 397llu,
    499llu, 631llu, 797llu, 1009llu, 1259llu, 1597llu, 2011llu, 2539llu,
    3203llu, 4027llu, 5087llu, 6421llu, 8089llu, 10193llu, 12853llu, 16193llu,
    20399llu, 25717llu, 32401llu, 40823llu, 51437llu, 64811llu, 81649llu,
    102877llu, 129607llu, 163307llu, 205759llu, 259229llu, 326617llu,
    411527llu, 518509llu, 653267llu, 823117llu, 1037059llu, 1306601llu,
    1646237llu, 2074129llu, 2613229llu, 3292489llu, 4148279llu, 5226491llu,
    6584983llu, 8296553llu, 10453007llu, 13169977llu, 16593127llu, 20906033llu};

ngx_int_t ngx_comm_is_prime(ngx_int_t n)
{
    ngx_int_t rc = 1;
    ngx_int_t max_n = 0, i = 0;

    if (n < 2) {
        return 0;
    }
    
    max_n = (ngx_int_t)sqrt((double)n);
    for (i = 2; i <= max_n; i++) {
        if (n % i == 0) {
            rc = 0;
            break;
        }
    }

    return rc;
}


ngx_int_t ngx_comm_generate_greater_prime(ngx_int_t n)
{
    ngx_int_t i;

    for (i = n; ;i++) {
        if (ngx_comm_is_prime(i) == 1) {
            break;
        }
    }

    return i;
}


#define ngx_java_hash(key, c)   ((int) key * 31 + c)

int
ngx_comm_java_hash_key(u_char *data, size_t len)
{
    int  i, key;

    key = 0;

    for (i = 0; i < (int)len; i++) {
        key = ngx_java_hash(key, data[i]);
    }

    return key;
}

ngx_uint_t
ngx_comm_get_bucket_size(ngx_uint_t size)
{
    size_t i = 0;
    for (; i < sizeof(hash_size_list); ++i)
    {
        if (size <= hash_size_list[i])
        {
            return hash_size_list[i];
        }
    }
    return ngx_comm_generate_greater_prime(size);
}


static void
ngx_comm_shuffle_generic(void *arr, size_t n, size_t size) {
    int i;
    u_char *base = (u_char *)arr;
    if (n <= 1) {
        return;
    }

    for (i = n - 1; i > 0; i--) {
        int j = ngx_random() % (i + 1);
        u_char temp[size];
        memcpy(temp, base + i * size, size);
        memcpy(base + i * size, base + j * size, size);
        memcpy(base + j * size, temp, size);
    }
}

void
ngx_comm_shuffle_array(ngx_array_t *array)
{
    ngx_comm_shuffle_generic(array->elts, array->nelts, array->size);
}
