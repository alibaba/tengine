/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

#ifndef _NGX_XQUIC_FILE_H_INCLUDED_
#define _NGX_XQUIC_FILE_H_INCLUDED_


#include <stdio.h>

/*
 * Read the entire content of filename into data.
 *
 * Returns the number of bytes read, or -1 when the file cannot be opened, does
 * not fit into data_len, or is short-read. The stream is closed on every path.
 *
 * Only ngx_int_t is required from the surrounding translation unit, so the
 * stand-alone unit test under test/unit/ can exercise this very source with a
 * minimal stub instead of a full nginx build.
 */
static ngx_int_t
ngx_xquic_read_file_data(char *data, size_t data_len, char *filename)
{
    FILE * fp = fopen(filename, "rb");

    if(fp == NULL){
        return -1;
    }
    fseek(fp, 0 , SEEK_END);
    size_t total_len  = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    if(total_len > data_len){
        fclose(fp);
        return -1;
    }

    size_t read_len = fread(data, 1, total_len, fp);
    fclose(fp);

    if (read_len != total_len){

        return -1;
    }

    return read_len;
}


#endif /* _NGX_XQUIC_FILE_H_INCLUDED_ */
