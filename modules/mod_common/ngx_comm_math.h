/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

#ifndef NGX_COMM_MATH_H
#define NGX_COMM_MATH_H

#include <ngx_core.h>

/*
* 判断数字是否质数
* 返回值：
*   0 不是质数
*   1 是质数
*/
ngx_int_t ngx_comm_is_prime(ngx_int_t n);

/*
* 生成大于n的质数
*/
ngx_int_t ngx_comm_generate_greater_prime(ngx_int_t n);


/*
* java String.hashCode() 实现
*/
int ngx_comm_java_hash_key(u_char *data, size_t len);

/*
* 生成hash桶大小
*/
ngx_uint_t ngx_comm_get_bucket_size(ngx_uint_t size);

/*
* 随机打乱数组
*/
void ngx_comm_shuffle_array(ngx_array_t *array);


#endif // NGX_COMM_MATH_H
