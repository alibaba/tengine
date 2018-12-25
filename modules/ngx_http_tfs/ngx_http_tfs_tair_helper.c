
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_tair_helper.h>


#ifdef NGX_HTTP_TFS_USE_TAIR

ngx_int_t
ngx_http_tfs_tair_get_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_http_tair_data_t *key, ngx_http_tair_get_handler_pt callback,
    void *data)
{
    ngx_int_t  rc;

    if (instance == NULL || key == NULL) {
        return NGX_ERROR;
    }

    rc = ngx_http_tair_get(instance->server, pool, log, *key,
                           instance->area, callback, data);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_DECLINED;
}


ngx_int_t ngx_http_tfs_tair_mget_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t *kvs,
    ngx_http_tair_mget_handler_pt callback, void *data)
{
    ngx_int_t  rc;

    if (instance == NULL || kvs == NULL) {
        return NGX_ERROR;
    }

    rc = ngx_http_tair_mget(instance->server, pool, log, kvs,
                            instance->area, callback, data);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_DECLINED;
}


ngx_int_t
ngx_http_tfs_tair_put_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_http_tair_data_t *key, ngx_http_tair_data_t *value,
    ngx_int_t expire, ngx_int_t version,
    ngx_http_tair_handler_pt callback, void *data)
{
    ngx_int_t  rc;

    if (instance == NULL || key == NULL || value == NULL) {
        return NGX_ERROR;
    }

    rc = ngx_http_tair_put(instance->server, pool, log, *key,
                           *value, instance->area, 0 /*nx*/, expire,
                           version, callback, data);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_DECLINED;
}


ngx_int_t
ngx_http_tfs_tair_delete_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log, ngx_array_t *keys,
    ngx_http_tair_handler_pt callback, void *data)
{
    ngx_int_t  rc;

    if (instance == NULL || keys == NULL) {
        return NGX_ERROR;
    }

    rc = ngx_http_tair_delete(instance->server, pool, log, keys,
                              instance->area, callback, data);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_DECLINED;
}

#else

ngx_int_t
ngx_http_tfs_tair_get_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_http_tair_data_t *key, ngx_http_tair_get_handler_pt callback,
    void *data)
{
    return NGX_ERROR;
}


ngx_int_t ngx_http_tfs_tair_mget_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_array_t *kvs, ngx_http_tair_mget_handler_pt callback, void *data)
{
    return NGX_ERROR;
}


ngx_int_t
ngx_http_tfs_tair_put_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_http_tair_data_t *key, ngx_http_tair_data_t *value,
    ngx_int_t expire, ngx_int_t version,
    ngx_http_tair_handler_pt callback, void *data)
{
    return NGX_ERROR;
}


ngx_int_t
ngx_http_tfs_tair_delete_helper(ngx_http_tfs_tair_instance_t *instance,
    ngx_pool_t *pool, ngx_log_t *log,
    ngx_array_t *keys, ngx_http_tair_handler_pt callback, void *data)
{
    return NGX_ERROR;
}

#endif


ngx_int_t
ngx_http_tfs_parse_tair_server_addr_info(
    ngx_http_tfs_tair_server_addr_info_t *info,
    u_char *addr, uint32_t len, void *pool, uint8_t shared_memory)
{
    u_char    *temp, *p;
    ssize_t    info_size;
    ngx_int_t  i;

    p = addr;

    for (i = 0; i < NGX_HTTP_TFS_TAIR_SERVER_ADDR_PART_COUNT; i++) {
        temp = ngx_strlchr(p, p + len, ';');
        if (temp == NULL) {
            return NGX_ERROR;
        }

        info_size = temp - p;
        if (shared_memory) {
            info->server[i].data =
                ngx_slab_alloc_locked((ngx_slab_pool_t *)pool, info_size);
        } else {
            info->server[i].data = ngx_pcalloc((ngx_pool_t *)pool, info_size);
        }
        if (info->server[i].data == NULL) {
            return NGX_ERROR;
        }
        info->server[i].len = info_size;
        memcpy(info->server[i].data, p, info_size);

        p += info_size + 1;
        len -= (info_size + 1);
        if (len <= 0) {
            return NGX_ERROR;
        }
    }

    info->area = ngx_atoi(p, len);
    if (info->area == NGX_ERROR) {
        return NGX_ERROR;
    }

    return NGX_OK;
}
