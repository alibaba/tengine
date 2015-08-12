
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_RAW_FSNAME_H_INCLUDED_
#define _NGX_HTTP_TFS_RAW_FSNAME_H_INCLUDED_


#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_tfs_common.h>


typedef enum {
    NGX_HTTP_TFS_INVALID_FILE_TYPE = 0,
    NGX_HTTP_TFS_SMALL_FILE_TYPE,
    NGX_HTTP_TFS_LARGE_FILE_TYPE
} ngx_http_tfs_raw_file_type_e;


typedef struct {
    uint32_t                       block_id;
    uint32_t                       seq_id;
    uint32_t                       suffix;
} ngx_http_tfs_raw_fsname_filebits_t;


typedef struct {
    u_char                         file_name[NGX_HTTP_TFS_FILE_NAME_BUFF_LEN];

    ngx_http_tfs_raw_fsname_filebits_t  file;

    uint32_t                       cluster_id;
    ngx_http_tfs_raw_file_type_e   file_type;
} ngx_http_tfs_raw_fsname_t;


#define ngx_http_tfs_raw_fsname_set_suffix(fsname, fs_suffix) do {      \
        if ((fs_suffix != NULL)                                         \
             && (fs_suffix->data != NULL)                               \
             && (fs_suffix->len != 0))                                  \
        {                                                               \
            fsname->file.suffix = ngx_http_tfs_raw_fsname_hash(         \
                fs_suffix->data, fs_suffix->len);                       \
        }                                                               \
    } while(0)


#define ngx_http_tfs_raw_fsname_set_file_id(fsname, id) \
    fsname->file.suffix = (id >> 32);                   \
    fsname->file.seq_id = (id & 0xFFFFFFFF)


#define ngx_http_tfs_raw_fsname_get_file_id(fsname) \
    ((((uint64_t)(fsname.file.suffix)) << 32) | fsname.file.seq_id)


#define ngx_http_tfs_group_seq_match(block_id, group_count, group_seq)  \
    ((block_id % group_count) == (ngx_uint_t) group_seq)


ngx_http_tfs_raw_file_type_e ngx_http_tfs_raw_fsname_check_file_type(
    ngx_str_t *tfs_name);
void ngx_http_tfs_raw_fsname_encode(u_char * input, u_char *output);
void ngx_http_tfs_raw_fsname_decode(u_char * input, u_char *output);

ngx_int_t ngx_http_tfs_raw_fsname_parse(ngx_str_t *tfs_name, ngx_str_t *suffix,
    ngx_http_tfs_raw_fsname_t *fsname);
u_char* ngx_http_tfs_raw_fsname_get_name(ngx_http_tfs_raw_fsname_t *fsname,
    unsigned large_flag, ngx_int_t no_suffix);


#endif  /* _NGX_HTTP_TFS_RAW_FSNAME_H_INCLUDED_ */
