
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_tfs_common.h>
#include <ngx_http_tfs_json.h>


ngx_http_tfs_json_gen_t *
ngx_http_tfs_json_init(ngx_log_t *log, ngx_pool_t *pool)
{
    yajl_gen                  g;
    ngx_http_tfs_json_gen_t  *tj_gen;

    g = yajl_gen_alloc(NULL);
    if (g == NULL) {
        ngx_log_error(NGX_LOG_ERR, log, errno, "alloc yajl_gen failed");
        return NULL;
    }

    tj_gen = ngx_pcalloc(pool, sizeof(ngx_http_tfs_json_gen_t));
    if (tj_gen == NULL) {
        return NULL;
    }

    yajl_gen_config(g, yajl_gen_beautify, 1);

    tj_gen->gen = g;
    tj_gen->pool = pool;
    tj_gen->log = log;

    return tj_gen;
}


void
ngx_http_tfs_json_destroy(ngx_http_tfs_json_gen_t *tj_gen)
{
    if (tj_gen != NULL) {
        yajl_gen_free(tj_gen->gen);
    }
}


ngx_chain_t *
ngx_http_tfs_json_custom_file_info(ngx_http_tfs_json_gen_t *tj_gen,
    ngx_http_tfs_custom_meta_info_t *meta_info, uint8_t file_type)
{
    size_t                       size;
    u_char                       time_buf[NGX_HTTP_TFS_GMT_TIME_SIZE];
    yajl_gen                     g;
    uint32_t                     count;
    ngx_buf_t                   *b;
    ngx_int_t                    is_file;
    ngx_uint_t                   i;
    ngx_chain_t                 *cl;
    ngx_http_tfs_custom_file_t  *file;

    g = tj_gen->gen;
    size = 0;

    if (file_type == NGX_HTTP_TFS_CUSTOM_FT_DIR) {
        yajl_gen_array_open(g);
    }

    for(; meta_info; meta_info = meta_info->next) {
        count = meta_info->file_count;
        file = meta_info->files;

        for (i = 0; i < count; i++) {
            yajl_gen_map_open(g);

            yajl_gen_string(g, (const unsigned char *) "NAME", 4);
            yajl_gen_string(g, (const unsigned char *) file[i].file_name.data,
                            file[i].file_name.len);

            yajl_gen_string(g, (const unsigned char *) "PID", 3);
            yajl_gen_integer(g, file[i].file_info.pid);

            yajl_gen_string(g, (const unsigned char *) "ID", 2);
            yajl_gen_integer(g, file[i].file_info.id);

            yajl_gen_string(g, (const unsigned char *) "SIZE", 4);
            yajl_gen_integer(g, file[i].file_info.size);

            yajl_gen_string(g, (const unsigned char *) "IS_FILE", 7);
            if (file_type == NGX_HTTP_TFS_CUSTOM_FT_DIR) {
                is_file = (file[i].file_info.pid >> 63) & 0x01;
            } else {
                is_file = 1;
            }
            yajl_gen_bool(g, is_file);

            ngx_http_tfs_time(time_buf, file[i].file_info.create_time);
            yajl_gen_string(g, (const unsigned char *) "CREATE_TIME", 11);
            yajl_gen_string(g, time_buf, NGX_HTTP_TFS_GMT_TIME_SIZE);

            ngx_http_tfs_time(time_buf, file[i].file_info.modify_time);
            yajl_gen_string(g, (const unsigned char *) "MODIFY_TIME", 11);
            yajl_gen_string(g, time_buf, NGX_HTTP_TFS_GMT_TIME_SIZE);

            yajl_gen_string(g, (const unsigned char *) "VER_NO", 6);
            yajl_gen_integer(g, file[i].file_info.ver_no);

            yajl_gen_map_close(g);
        }
    }

    if (file_type == NGX_HTTP_TFS_CUSTOM_FT_DIR) {
        yajl_gen_array_close(g);
    }

    cl = ngx_alloc_chain_link(tj_gen->pool);
    if (cl == NULL) {
        return NULL;
    }
    cl->next = NULL;

    b = ngx_calloc_buf(tj_gen->pool);
    if (b == NULL) {
        return NULL;
    }

    yajl_gen_get_buf(g, (const unsigned char **) &b->pos, &size);
    b->last = b->pos + size;
    b->end = b->last;
    b->temporary = 1;
    b->flush = 1;
    /* b->last_buf = 1; */
    cl->buf = b;

    return cl;
}


ngx_chain_t *
ngx_http_tfs_json_file_name(ngx_http_tfs_json_gen_t *tj_gen,
    ngx_str_t *file_name)
{
    size_t        size;
    yajl_gen      g;
    ngx_buf_t    *b;
    ngx_chain_t  *cl;

    g = tj_gen->gen;
    size = 0;

    yajl_gen_map_open(g);
    yajl_gen_string(g, (const unsigned char *) "TFS_FILE_NAME", 13);
    yajl_gen_string(g, (const unsigned char *) file_name->data, file_name->len);
    yajl_gen_map_close(g);

    cl = ngx_alloc_chain_link(tj_gen->pool);
    if (cl == NULL) {
        return NULL;
    }
    cl->next = NULL;

    b = ngx_calloc_buf(tj_gen->pool);
    if (b == NULL) {
        return NULL;
    }
    yajl_gen_get_buf(g, (const unsigned char **) &b->pos, &size);
    b->last = b->pos + size;
    b->end = b->last;
    b->temporary = 1;
    b->flush = 1;
    /* b->last_buf = 1; */
    cl->buf = b;
    return cl;
}


ngx_chain_t *
ngx_http_tfs_json_raw_file_stat(ngx_http_tfs_json_gen_t *tj_gen,
    u_char* file_name, uint32_t block_id,
    ngx_http_tfs_raw_file_stat_t *file_stat)
{
    size_t        size;
    u_char        time_buf[NGX_HTTP_TFS_GMT_TIME_SIZE];
    yajl_gen      g;
    ngx_buf_t    *b;
    ngx_chain_t  *cl;

    g = tj_gen->gen;
    size = 0;

    yajl_gen_map_open(g);

    yajl_gen_string(g, (const unsigned char *) "FILE_NAME", 9);
    yajl_gen_string(g, (const unsigned char *) file_name, 18);

    yajl_gen_string(g, (const unsigned char *) "BLOCK_ID", 8);
    yajl_gen_integer(g, block_id);

    yajl_gen_string(g, (const unsigned char *) "FILE_ID", 7);
    yajl_gen_integer(g, file_stat->id);

    yajl_gen_string(g, (const unsigned char *) "OFFSET", 6);
    yajl_gen_integer(g, file_stat->offset);

    yajl_gen_string(g, (const unsigned char *) "SIZE", 4);
    yajl_gen_integer(g, file_stat->size);

    yajl_gen_string(g, (const unsigned char *) "OCCUPY_SIZE", 11);
    yajl_gen_integer(g, file_stat->u_size);

    ngx_http_tfs_time(time_buf, file_stat->modify_time);
    yajl_gen_string(g, (const unsigned char *) "MODIFY_TIME", 11);
    yajl_gen_string(g, time_buf, NGX_HTTP_TFS_GMT_TIME_SIZE);

    ngx_http_tfs_time(time_buf, file_stat->create_time);
    yajl_gen_string(g, (const unsigned char *) "CREATE_TIME", 11);
    yajl_gen_string(g, time_buf, NGX_HTTP_TFS_GMT_TIME_SIZE);

    yajl_gen_string(g, (const unsigned char *) "STATUS", 6);
    yajl_gen_integer(g, file_stat->flag);

    yajl_gen_string(g, (const unsigned char *) "CRC", 3);
    yajl_gen_integer(g, file_stat->crc);

    yajl_gen_map_close(g);

    cl = ngx_alloc_chain_link(tj_gen->pool);
    if (cl == NULL) {
        return NULL;
    }
    cl->next = NULL;

    b = ngx_calloc_buf(tj_gen->pool);
    if (b == NULL) {
        return NULL;
    }

    yajl_gen_get_buf(g, (const unsigned char **) &b->pos, &size);

    b->last = b->pos + size;
    b->end = b->last;
    b->temporary = 1;
    b->flush = 1;

    /* b->last_buf = 1; */

    cl->buf = b;

    return cl;
}


ngx_chain_t *
ngx_http_tfs_json_appid(ngx_http_tfs_json_gen_t *tj_gen,
    uint64_t app_id)
{
    size_t        size;
    yajl_gen      g;
    ngx_buf_t    *b;
    ngx_chain_t  *cl;

    g = tj_gen->gen;
    size = 0;

    u_char str_appid[NGX_INT64_LEN] = {'\0'};
    ngx_sprintf(str_appid, "%uL", app_id);

    yajl_gen_map_open(g);
    yajl_gen_string(g, (const unsigned char *) "APP_ID", 6);
    yajl_gen_string(g, (const unsigned char *) str_appid,
                    ngx_strlen(str_appid));
    yajl_gen_map_close(g);

    cl = ngx_alloc_chain_link(tj_gen->pool);
    if (cl == NULL) {
        return NULL;
    }
    cl->next = NULL;

    b = ngx_calloc_buf(tj_gen->pool);
    if (b == NULL) {
        return NULL;
    }

    yajl_gen_get_buf(g, (const unsigned char **) &b->pos, &size);
    b->last = b->pos + size;
    b->end = b->last;
    b->temporary = 1;
    b->flush = 1;
    /* b->last_buf = 1; */
    cl->buf = b;
    return cl;
}


ngx_chain_t *
ngx_http_tfs_json_file_hole_info(ngx_http_tfs_json_gen_t *tj_gen,
    ngx_array_t *file_holes)
{
    size_t                          size;
    yajl_gen                        g;
    ngx_buf_t                      *b;
    ngx_uint_t                      i;
    ngx_chain_t                    *cl;
    ngx_http_tfs_file_hole_info_t  *file_hole_info;

    g = tj_gen->gen;
    size = 0;

    yajl_gen_array_open(g);

    file_hole_info = (ngx_http_tfs_file_hole_info_t *) file_holes->elts;
    for(i = 0; i < file_holes->nelts; i++, file_hole_info++) {
        yajl_gen_map_open(g);

        yajl_gen_string(g, (const unsigned char *) "OFFSET", 6);
        yajl_gen_integer(g, file_hole_info->offset);

        yajl_gen_string(g, (const unsigned char *) "LENGTH", 6);
        yajl_gen_integer(g, file_hole_info->length);

        yajl_gen_map_close(g);
    }

    yajl_gen_array_close(g);

    cl = ngx_alloc_chain_link(tj_gen->pool);
    if (cl == NULL) {
        return NULL;
    }
    cl->next = NULL;

    b = ngx_calloc_buf(tj_gen->pool);
    if (b == NULL) {
        return NULL;
    }

    yajl_gen_get_buf(g, (const unsigned char **) &b->pos, &size);
    b->last = b->pos + size;
    b->end = b->last;
    b->temporary = 1;
    b->flush = 1;
    /* b->last_buf = 1; */
    cl->buf = b;
    return cl;
}
