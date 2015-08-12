
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_serialization.h>


ngx_int_t
ngx_http_tfs_serialize_string(u_char **p,
    ngx_str_t *string)
{
    if (p == NULL || *p == NULL || string == NULL) {
        return NGX_ERROR;
    }

    if (string->len == 0) {
        *((uint32_t *)*p) = 0;

    } else {
        *((uint32_t *)*p) = string->len + 1;
    }
    *p += sizeof(uint32_t);

    if (string->len > 0) {
        ngx_memcpy(*p, string->data, string->len);
        *p += string->len + 1;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_deserialize_string(u_char **p, ngx_pool_t *pool,
    ngx_str_t *string)
{
    if (p == NULL || *p == NULL || pool == NULL || string == NULL) {
        return NGX_ERROR;
    }

    string->len = *((uint32_t *)*p);
    (*p) += sizeof(uint32_t);

    if (string->len > 0) {
        /* this length includes '/0' */
        string->len -= 1;
        string->data = ngx_pcalloc(pool, string->len);
        if (string->data == NULL) {
            return NGX_ERROR;
        }
        ngx_memcpy(string->data, (*p), string->len);
        (*p) += string->len + 1;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_deserialize_vstring(u_char **p, ngx_pool_t *pool,
    uint32_t *count, ngx_str_t **string)
{
    uint32_t   new_count, i;
    ngx_int_t  rc;

    /* count */
    new_count = *((uint32_t *)*p);
    (*p) += sizeof(uint32_t);

    /* string */
    if (new_count > 0) {
        if (*string == NULL) {
            *string = ngx_pcalloc(pool, sizeof(ngx_str_t) * new_count);
            if (*string == NULL) {
                return NGX_ERROR;
            }

        } else if (new_count > *count) {
            *string = ngx_prealloc(pool, *string, sizeof(ngx_str_t) * (*count),
                                   sizeof(ngx_str_t) * new_count);
            if (*string == NULL) {
                return NGX_ERROR;
            }
            ngx_memzero(*string, sizeof(ngx_str_t) * new_count);
        }
        for (i = 0; i < new_count; i++) {
            rc = ngx_http_tfs_deserialize_string(p, pool, (*string) + i);
            if (rc == NGX_ERROR) {
                return NGX_ERROR;
            }
        }
    }
    *count = new_count;

    return NGX_OK;
}


/*ngx_int_t
ngx_http_tfs_serialize_bucket_meta_info(u_char **p,
    ngx_http_tfs_bucket_meta_info_t *bucket_meta_info)
{
    if (p == NULL || *p == NULL || bucket_meta_info == NULL) {
        return NGX_ERROR;
    }

    *((uint32_t *)*p) = NGX_HTTP_TFS_BUCKET_META_INFO_CREATE_TIME_TAG;
    (*p) += sizeof(uint32_t);

    *((int64_t *)*p) = bucket_meta_info->create_time;
    (*p) += sizeof(int64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_BUCKET_META_INFO_OWNER_ID_TAG;
    (*p) += sizeof(uint32_t);

    *((uint64_t *)*p) = bucket_meta_info->owner_id;
    (*p) += sizeof(uint64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_END_TAG;
    (*p) += sizeof(uint32_t);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_deserialize_bucket_meta_info(u_char **p,
    ngx_http_tfs_bucket_meta_info_t *bucket_meta_info)
{
    uint32_t   type_tag;
    ngx_int_t  rc;

    if (p == NULL || *p == NULL || bucket_meta_info == NULL) {
        return NGX_ERROR;
    }

    rc = NGX_OK;
    while (rc == NGX_OK) {
        type_tag = *((uint32_t *)*p);
        (*p) += sizeof(uint32_t);

        switch (type_tag) {
        case NGX_HTTP_TFS_BUCKET_META_INFO_CREATE_TIME_TAG:
            bucket_meta_info->create_time = *((int64_t *)*p);
            (*p) += sizeof(int64_t);
            break;
        case NGX_HTTP_TFS_BUCKET_META_INFO_OWNER_ID_TAG:
            bucket_meta_info->owner_id = *((uint64_t *)*p);
            (*p) += sizeof(uint64_t);
            break;
        case NGX_HTTP_TFS_END_TAG:
            break;
        default:
            rc = NGX_ERROR;
            break;
        }

        if (type_tag == NGX_HTTP_TFS_END_TAG) {
            break;
        }
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_serialize_object_meta_info(u_char **p,
    ngx_http_tfs_object_meta_info_t *object_meta_info)
{
    if (p == NULL || *p == NULL || object_meta_info == NULL) {
        return NGX_ERROR;
    }

    *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_META_INFO_CREATE_TIME_TAG;
    (*p) += sizeof(uint32_t);

    *((int64_t *)*p) = object_meta_info->create_time;
    (*p) += sizeof(int64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_META_INFO_MODIFY_TIME_TAG;
    (*p) += sizeof(uint32_t);

    *((int64_t *)*p) = object_meta_info->modify_time;
    (*p) += sizeof(int64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_META_INFO_BIG_FILE_SIZE_TAG;
    (*p) += sizeof(uint32_t);

    *((uint64_t *)*p) = object_meta_info->big_file_size;
    (*p) += sizeof(uint64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_META_INFO_MAX_TFS_FILE_SIZE_TAG;
    (*p) += sizeof(uint32_t);

    *((uint32_t *)*p) = object_meta_info->max_tfs_file_size;
    (*p) += sizeof(uint32_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_META_INFO_OWNER_ID_TAG;
    (*p) += sizeof(uint32_t);

    *((uint64_t *)*p) = object_meta_info->owner_id;
    (*p) += sizeof(uint64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_END_TAG;
    (*p) += sizeof(uint32_t);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_deserialize_object_meta_info(u_char **p,
    ngx_http_tfs_object_meta_info_t *object_meta_info)
{
    uint32_t   type_tag;
    ngx_int_t  rc;

    if (p == NULL || *p == NULL || object_meta_info == NULL) {
        return NGX_ERROR;
    }

    rc = NGX_OK;
    while (rc == NGX_OK) {
        type_tag = *((uint32_t *)*p);
        (*p) += sizeof(uint32_t);

        switch (type_tag) {
        case NGX_HTTP_TFS_OBJECT_META_INFO_CREATE_TIME_TAG:
            object_meta_info->create_time = *((int64_t *)*p);
            (*p) += sizeof(int64_t);
            break;
        case NGX_HTTP_TFS_OBJECT_META_INFO_MODIFY_TIME_TAG:
            object_meta_info->modify_time = *((int64_t *)*p);
            (*p) += sizeof(int64_t);
            break;
        case NGX_HTTP_TFS_OBJECT_META_INFO_MAX_TFS_FILE_SIZE_TAG:
            object_meta_info->max_tfs_file_size = *((uint32_t *)*p);
            (*p) += sizeof(uint32_t);
            break;
        case NGX_HTTP_TFS_OBJECT_META_INFO_BIG_FILE_SIZE_TAG:
            object_meta_info->big_file_size = *((uint64_t *)*p);
            (*p) += sizeof(uint64_t);
            break;
        case NGX_HTTP_TFS_OBJECT_META_INFO_OWNER_ID_TAG:
            object_meta_info->owner_id = *((uint64_t *)*p);
            (*p) += sizeof(uint64_t);
            break;
        case NGX_HTTP_TFS_END_TAG:
            break;
        default:
            rc = NGX_ERROR;
            break;
        }

        if (type_tag == NGX_HTTP_TFS_END_TAG) {
            break;
        }
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_serialize_tfs_file_info(u_char **p,
    ngx_http_tfs_file_info_t *tfs_file_info)
{
    if (p == NULL || *p == NULL || tfs_file_info == NULL) {
        return NGX_ERROR;
    }

    *((uint32_t *)*p) = NGX_HTTP_TFS_FILE_INFO_CLUSTER_ID_TAG;
    (*p) += sizeof(uint32_t);

    *((int32_t *)*p) = tfs_file_info->cluster_id;
    (*p) += sizeof(int32_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_FILE_INFO_BLOCK_ID_TAG;
    (*p) += sizeof(uint32_t);

    *((uint64_t *)*p) = tfs_file_info->block_id;
    (*p) += sizeof(uint64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_FILE_INFO_FILE_ID_TAG;
    (*p) += sizeof(uint32_t);

    *((uint64_t *)*p) = tfs_file_info->file_id;
    (*p) += sizeof(uint64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_FILE_INFO_OFFSET_TAG;
    (*p) += sizeof(uint32_t);

    *((int64_t *)*p) = tfs_file_info->offset;
    (*p) += sizeof(int64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_FILE_INFO_FILE_SIZE_TAG;
    (*p) += sizeof(uint32_t);

    *((uint64_t *)*p) = tfs_file_info->size;
    (*p) += sizeof(uint64_t);

    *((uint32_t *)*p) = NGX_HTTP_TFS_END_TAG;
    (*p) += sizeof(uint32_t);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_deserialize_tfs_file_info(u_char **p,
    ngx_http_tfs_file_info_t *tfs_file_info)
{
    uint32_t   type_tag;
    ngx_int_t  rc;

    if (p == NULL || *p == NULL || tfs_file_info == NULL) {
        return NGX_ERROR;
    }

    rc = NGX_OK;
    while (rc == NGX_OK) {
        type_tag = *((uint32_t *)*p);
        (*p) += sizeof(uint32_t);

        switch (type_tag) {
        case NGX_HTTP_TFS_FILE_INFO_CLUSTER_ID_TAG:
            tfs_file_info->cluster_id = *((int32_t *)*p);
            (*p) += sizeof(int32_t);
            break;
        case NGX_HTTP_TFS_FILE_INFO_BLOCK_ID_TAG:
            tfs_file_info->block_id = *((uint64_t *)*p);
            (*p) += sizeof(uint64_t);
            break;
        case NGX_HTTP_TFS_FILE_INFO_FILE_ID_TAG:
            tfs_file_info->file_id = *((uint64_t *)*p);
            (*p) += sizeof(uint64_t);
            break;
        case NGX_HTTP_TFS_FILE_INFO_OFFSET_TAG:
            tfs_file_info->offset = *((int64_t *)*p);
            (*p) += sizeof(int64_t);
            break;
        case NGX_HTTP_TFS_FILE_INFO_FILE_SIZE_TAG:
            tfs_file_info->size = *((uint64_t *)*p);
            (*p) += sizeof(uint64_t);
            break;
        case NGX_HTTP_TFS_END_TAG:
            break;
        default:
            rc = NGX_ERROR;
            break;
        }

        if (type_tag == NGX_HTTP_TFS_END_TAG) {
            break;
        }
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_serialize_customize_info(u_char **p,
    ngx_http_tfs_customize_info_t *customize_info)
{
    if (p == NULL || *p == NULL || customize_info == NULL) {
        return NGX_ERROR;
    }

    *((uint32_t *)*p) = NGX_HTTP_TFS_CUSTOMIZE_INFO_OTAG_TAG;
    (*p) += sizeof(uint32_t);

    *((uint32_t *)*p) = customize_info->otag_len + 1;
    (*p) += sizeof(uint32_t);

    ngx_memcpy(*p, customize_info->otag, customize_info->otag_len);
    (*p) += customize_info->otag_len + 1;

    *((uint32_t *)*p) = NGX_HTTP_TFS_END_TAG;
    (*p) += sizeof(uint32_t);

    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_deserialize_customize_info(u_char **p, ngx_pool_t *pool,
    ngx_http_tfs_customize_info_t *customize_info)
{
    uint32_t   type_tag;
    ngx_int_t  rc;

    if (p == NULL || *p == NULL || pool == NULL || customize_info == NULL) {
        return NGX_ERROR;
    }

    rc = NGX_OK;
    while (rc == NGX_OK) {
        type_tag = *((uint32_t *)*p);
        (*p) += sizeof(uint32_t);

        switch (type_tag) {
        case NGX_HTTP_TFS_CUSTOMIZE_INFO_OTAG_TAG:
            customize_info->otag_len = *((uint32_t *)*p) - 1;
            (*p) += sizeof(uint32_t);

            if (customize_info->otag_len > NGX_HTTP_TFS_MAX_CUSTOMIZE_INFO_SIZE) {
                return NGX_ERROR;
            }

            customize_info->otag = ngx_pcalloc(pool, customize_info->otag_len);
            if (customize_info->otag == NULL) {
                return NGX_ERROR;
            }

            ngx_memcpy(customize_info->otag, *p, customize_info->otag_len);
            (*p) += customize_info->otag_len + 1;

            break;
        case NGX_HTTP_TFS_END_TAG:
            break;
        default:
            rc = NGX_ERROR;
            break;
        }

        if (type_tag == NGX_HTTP_TFS_END_TAG) {
            break;
        }
    }

    return rc;
}


ngx_int_t
ngx_http_tfs_serialize_object_info(u_char **p,
    ngx_http_tfs_object_info_t *object_info)
{
    uint32_t  i;

    if (p == NULL || *p == NULL || object_info == NULL) {
        return NGX_ERROR;
    }

    *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_INFO_V_TFS_FILE_INFO_TAG;
    (*p) += sizeof(uint32_t);

    *((uint32_t *)*p) = object_info->tfs_file_count;
    (*p) += sizeof(uint32_t);

    for (i = 0; i < object_info->tfs_file_count; i++) {
        ngx_http_tfs_serialize_tfs_file_info(p, object_info->tfs_file_infos + i);
    }

    *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_INFO_HAS_META_INFO_TAG;
    (*p) += sizeof(uint32_t);

    *((uint8_t *)*p) = object_info->has_meta_info;
    (*p) += sizeof(uint8_t);

    if (object_info->has_meta_info) {
        *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_INFO_META_INFO_TAG;
        (*p) += sizeof(uint32_t);

        ngx_http_tfs_serialize_object_meta_info(p, &object_info->meta_info);
    }

    *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_INFO_HAS_CUSTOMIZE_INFO_TAG;
    (*p) += sizeof(uint32_t);

    *((uint8_t *)*p) = object_info->has_customize_info;
    (*p) += sizeof(uint8_t);

    if (object_info->has_customize_info) {
        *((uint32_t *)*p) = NGX_HTTP_TFS_OBJECT_INFO_CUSTOMIZE_INFO_TAG;
        (*p) += sizeof(uint32_t);

        ngx_http_tfs_serialize_customize_info(p, &object_info->customize_info);
    }

    *((uint32_t *)*p) = NGX_HTTP_TFS_END_TAG;
    (*p) += sizeof(uint32_t);

    return NGX_OK;
}*/


//ngx_int_t
//ngx_http_tfs_deserialize_object_info(u_char **p, ngx_pool_t *pool,
//    ngx_http_tfs_object_info_t *object_info)
//{
//    uint32_t   type_tag, file_info_count, i;
//    ngx_int_t  rc;
//
//    if (p == NULL || *p == NULL || pool == NULL || object_info == NULL) {
//        return NGX_ERROR;
//    }
//
//    rc = NGX_OK;
//    while (rc == NGX_OK) {
//        type_tag = *((uint32_t *)*p);
//        (*p) += sizeof(uint32_t);
//
//        switch (type_tag) {
//        case NGX_HTTP_TFS_OBJECT_INFO_V_TFS_FILE_INFO_TAG:
//            file_info_count = *((uint32_t *)*p);
//            (*p) += sizeof(uint32_t);
//            if (file_info_count > 0) {
//                if (object_info->tfs_file_infos == NULL) {
//                    object_info->tfs_file_infos = ngx_pcalloc(pool,
//                        sizeof(ngx_http_tfs_file_info_t) * file_info_count);
//                    if (object_info->tfs_file_infos == NULL) {
//                        return NGX_ERROR;
//                    }
//
//                } else {
//                    /* need realloc */
//                    if (file_info_count > object_info->tfs_file_count) {
//                        object_info->tfs_file_infos = ngx_prealloc(pool,
//                            object_info->tfs_file_infos,
//                            sizeof(ngx_http_tfs_file_info_t) * object_info->tfs_file_count,
//                            sizeof(ngx_http_tfs_file_info_t) * file_info_count);
//                        if (object_info->tfs_file_infos == NULL) {
//                            return NGX_ERROR;
//                        }
//                    }
//                    /* reuse */
//                    ngx_memzero(object_info->tfs_file_infos,
//                        sizeof(ngx_http_tfs_file_info_t) * file_info_count);
//                }
//                object_info->tfs_file_count = file_info_count;
//                for (i = 0; i < file_info_count; i++) {
//                    rc = ngx_http_tfs_deserialize_tfs_file_info(p, object_info->tfs_file_infos + i);
//                    if (rc == NGX_ERROR) {
//                        return NGX_ERROR;
//                    }
//                }
//            }
//            break;
//        case NGX_HTTP_TFS_OBJECT_INFO_HAS_META_INFO_TAG:
//            object_info->has_meta_info = *((uint8_t *)*p);
//            (*p) += sizeof(uint8_t);
//            break;
//        case NGX_HTTP_TFS_OBJECT_INFO_META_INFO_TAG:
//            rc = ngx_http_tfs_deserialize_object_meta_info(p, &object_info->meta_info);
//            if (rc == NGX_ERROR) {
//                return NGX_ERROR;
//            }
//            break;
//        case NGX_HTTP_TFS_OBJECT_INFO_HAS_CUSTOMIZE_INFO_TAG:
//            object_info->has_customize_info = *((uint8_t *)*p);
//            (*p) += sizeof(uint8_t);
//            break;
//        case NGX_HTTP_TFS_OBJECT_INFO_CUSTOMIZE_INFO_TAG:
//            rc = ngx_http_tfs_deserialize_customize_info(p, pool, &object_info->customize_info);
//            if (rc == NGX_ERROR) {
//                return NGX_ERROR;
//            }
//            break;
//        case NGX_HTTP_TFS_END_TAG:
//            break;
//        default:
//            rc = NGX_ERROR;
//            break;
//        }
//
//        if (type_tag == NGX_HTTP_TFS_END_TAG) {
//            break;
//        }
//    }
//
//    return rc;
//}
//
//
//ngx_int_t
//ngx_http_tfs_serialize_user_info(u_char **p,
//    ngx_http_tfs_user_info_t *user_info)
//{
//    if (p == NULL || *p == NULL || user_info == NULL) {
//        return NGX_ERROR;
//    }
//
//    *((uint32_t *)*p) = NGX_HTTP_TFS_USER_INFO_OWNER_ID_TAG;
//    (*p) += sizeof(uint32_t);
//
//    *((uint64_t *)*p) = user_info->owner_id;
//    (*p) += sizeof(uint64_t);
//
//    *((uint32_t *)*p) = NGX_HTTP_TFS_END_TAG;
//    (*p) += sizeof(uint32_t);
//
//    return NGX_OK;
//}
//
//
//ngx_int_t
//ngx_http_tfs_deserialize_kv_meta_table(u_char **p,
//    ngx_http_tfs_kv_meta_table_t *kv_meta_table)
//{
//    uint32_t   type_tag, table_size, i;
//    ngx_int_t  rc;
//
//    if (p == NULL || *p == NULL || kv_meta_table == NULL) {
//        return NGX_ERROR;
//    }
//
//    rc = NGX_OK;
//    while (rc == NGX_OK) {
//        type_tag = *((uint32_t *)*p);
//        (*p) += sizeof(uint32_t);
//
//        switch (type_tag) {
//        case NGX_HTTP_TFS_KV_META_TABLE_V_META_TABLE_TAG:
//            table_size = *((uint32_t *)*p);
//            (*p) += sizeof(uint32_t);
//            if (table_size == 0) {
//                return NGX_ERROR;
//            }
//
//            for (i = 0; i < table_size; i++) {
//                *(uint64_t *)(&kv_meta_table->table[i]) = *((uint64_t *)*p);
//                (*p) += sizeof(uint64_t);
//            }
//            kv_meta_table->size = table_size;
//            break;
//        case NGX_HTTP_TFS_END_TAG:
//            break;
//        default:
//            rc = NGX_ERROR;
//            break;
//        }
//
//        if (type_tag == NGX_HTTP_TFS_END_TAG) {
//            break;
//        }
//    }
//
//    return rc;
//}


ngx_int_t
ngx_http_tfs_serialize_rcs_stat(u_char **p,
    ngx_http_tfs_rcs_info_t  *rc_info, ngx_int_t *count)
{
    ngx_int_t                    i;
    ngx_http_tfs_stat_rcs_t     *stat_rcs;

    if (p == NULL || rc_info == NULL || count == NULL) {
        return NGX_ERROR;
    }

    *count = 0;
    stat_rcs = rc_info->stat_rcs;

    for (i = 0; i < NGX_HTTP_TFS_OPER_COUNT; ++i) {
        if (stat_rcs[i].oper_app_id == 0) {
            continue;
        }

        *((uint32_t *)*p) = (stat_rcs[i].oper_app_id << 16) | stat_rcs[i].oper_type;
        (*p) += sizeof(uint32_t);

        *((uint32_t *)*p) = (stat_rcs[i].oper_app_id << 16) | stat_rcs[i].oper_type;
        (*p) += sizeof(uint32_t);
        *((uint64_t *)*p) = stat_rcs[i].oper_times;
        (*p) += sizeof(uint64_t);
        *((uint64_t *)*p) = stat_rcs[i].oper_size;
        (*p) += sizeof(uint64_t);
        *((uint64_t *)*p) = stat_rcs[i].oper_rt;
        (*p) += sizeof(uint64_t);
        *((uint64_t *)*p) = stat_rcs[i].oper_succ;
        (*p) += sizeof(uint64_t);

        ++(*count);
    }

    return NGX_OK;
}
