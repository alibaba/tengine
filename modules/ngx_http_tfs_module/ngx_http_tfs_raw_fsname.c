
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_raw_fsname.h>

#define NGX_HTTP_TFS_KEY_MASK_LEN  10     /* strlen(NGX_HTTP_TFS_KEY_MASK) */

static const u_char* NGX_HTTP_TFS_KEY_MASK = (u_char *) "Taobao-inc";

static const u_char enc_table[] = "0JoU8EaN3xf19hIS2d.6p"
    "ZRFBYurMDGw7K5m4CyXsbQjg_vTOAkcHVtzqWilnLPe";

static const u_char dec_table[] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  \
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,18,0,0,11,16,8,  \
    36,34,19,32,4,12,0,0,0,0,0,0,0,49,24,37,29,5,23,30,52,14,1,33,61,28,7, \
    48,62,42,22,15,47,3,53,57,39,25,21,0,0,0,0,45,0,6,41,51,17,63,10,44,13,\
    58,43,50,59,35,60,2,20,56,27,40,54,26,46,31,9,38,55,0,0,0,0,0,0,0,0,0, \
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, \
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, \
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, \
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};


static void
xor_mask(const u_char* source, const int32_t len, u_char* target)
{
    int32_t i = 0;

    for (; i < len; i++) {
        target[i] =
            source[i] ^ NGX_HTTP_TFS_KEY_MASK[i % NGX_HTTP_TFS_KEY_MASK_LEN];
    }
}


ngx_int_t
ngx_http_tfs_raw_fsname_parse(ngx_str_t *tfs_name, ngx_str_t *suffix,
    ngx_http_tfs_raw_fsname_t* fsname)
{
    ngx_uint_t  suffix_len;

    if (fsname != NULL && tfs_name->data != NULL && tfs_name->data[0] != '\0') {
        ngx_memzero(fsname, sizeof(ngx_http_tfs_raw_fsname_t));
        fsname->file_type = ngx_http_tfs_raw_fsname_check_file_type(tfs_name);
        if (fsname->file_type == NGX_HTTP_TFS_INVALID_FILE_TYPE) {
            return NGX_ERROR;
        } else {
            /* if two suffix exist, check consistency */
            if (suffix != NULL
                && suffix->data != NULL
                && tfs_name->len > NGX_HTTP_TFS_FILE_NAME_LEN)
            {
                suffix_len = tfs_name->len - NGX_HTTP_TFS_FILE_NAME_LEN;
                if (suffix->len != suffix_len) {
                    return NGX_ERROR;
                }
                suffix_len = suffix->len > suffix_len ? suffix_len :suffix->len;
                if (ngx_memcmp(suffix->data,
                               tfs_name->data + NGX_HTTP_TFS_FILE_NAME_LEN,
                               suffix_len))
                {
                    return NGX_ERROR;
                }
            }

            ngx_http_tfs_raw_fsname_decode(tfs_name->data + 2,
                                           (u_char*) &(fsname->file));
            if (suffix != NULL && suffix->data == NULL) {
                suffix->data = tfs_name->data + NGX_HTTP_TFS_FILE_NAME_LEN;
                suffix->len = tfs_name->len - NGX_HTTP_TFS_FILE_NAME_LEN;
            }

            ngx_http_tfs_raw_fsname_set_suffix(fsname, suffix);
            if (fsname->cluster_id == 0) {
                fsname->cluster_id = tfs_name->data[1] - '0';
            }
        }
    }

    return NGX_OK;
}


u_char*
ngx_http_tfs_raw_fsname_get_name(ngx_http_tfs_raw_fsname_t* fsname,
    unsigned large_flag, ngx_int_t simple_name)
{
    if (fsname != NULL) {
        if (simple_name) {
            /* zero suffix */
            fsname->file.suffix = 0;
        }

        ngx_http_tfs_raw_fsname_encode((u_char*) &(fsname->file),
                                       fsname->file_name + 2);

        if (large_flag) {
            fsname->file_name[0] = NGX_HTTP_TFS_LARGE_FILE_KEY_CHAR;

        } else {
            fsname->file_name[0] = NGX_HTTP_TFS_SMALL_FILE_KEY_CHAR;
        }
        fsname->file_name[1] = (u_char) ('0' + fsname->cluster_id);
        fsname->file_name[NGX_HTTP_TFS_FILE_NAME_LEN] = '\0';

        return fsname->file_name;
    }

    return NULL;
}


ngx_http_tfs_raw_file_type_e
ngx_http_tfs_raw_fsname_check_file_type(ngx_str_t *tfs_name)
{
    ngx_http_tfs_raw_file_type_e file_type = NGX_HTTP_TFS_INVALID_FILE_TYPE;

    if (tfs_name->data != NULL
        && tfs_name->len >= NGX_HTTP_TFS_FILE_NAME_LEN)
    {
        if (tfs_name->data[0] == NGX_HTTP_TFS_LARGE_FILE_KEY_CHAR) {
            file_type = NGX_HTTP_TFS_LARGE_FILE_TYPE;

        } else if (tfs_name->data[0] == NGX_HTTP_TFS_SMALL_FILE_KEY_CHAR) {
            file_type = NGX_HTTP_TFS_SMALL_FILE_TYPE;
        }
    }

    return file_type;
}


void
ngx_http_tfs_raw_fsname_encode(u_char *input, u_char *output)
{
    u_char      buffer[NGX_HTTP_TFS_FILE_NAME_EXCEPT_SUFFIX_LEN];
    uint32_t    value;
    ngx_uint_t  i, k;

    k = 0;

    if (input != NULL && output != NULL) {
        xor_mask(input, NGX_HTTP_TFS_FILE_NAME_EXCEPT_SUFFIX_LEN, buffer);
        for (i = 0; i < NGX_HTTP_TFS_FILE_NAME_EXCEPT_SUFFIX_LEN; i += 3) {
            value = ((buffer[i] << 16) & 0xff0000)
                     + ((buffer[i + 1] << 8) & 0xff00) + (buffer[i + 2] & 0xff);
            output[k++] = enc_table[value >> 18];
            output[k++] = enc_table[(value >> 12) & 0x3f];
            output[k++] = enc_table[(value >> 6) & 0x3f];
            output[k++] = enc_table[value & 0x3f];
        }
    }
}


void
ngx_http_tfs_raw_fsname_decode(u_char *input, u_char *output)
{
    u_char      buffer[NGX_HTTP_TFS_FILE_NAME_EXCEPT_SUFFIX_LEN];
    uint32_t    value;
    ngx_uint_t  i, k;

    k = 0;

    if (input != NULL && output != NULL) {
        for (i = 0; i < NGX_HTTP_TFS_FILE_NAME_LEN - 2; i += 4) {
            value = (dec_table[input[i] & 0xff] << 18)
                     + (dec_table[input[i + 1] & 0xff] << 12)
                        + (dec_table[input[i + 2] & 0xff] << 6)
                           + dec_table[input[i + 3] & 0xff];
            buffer[k++] = (u_char) ((value >> 16) & 0xff);
            buffer[k++] = (u_char) ((value >> 8) & 0xff);
            buffer[k++] = (u_char) (value & 0xff);
        }
        xor_mask(buffer, NGX_HTTP_TFS_FILE_NAME_EXCEPT_SUFFIX_LEN, output);
    }
}
