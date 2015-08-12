
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_COMMON_H_INCLUDED_
#define _NGX_HTTP_TFS_COMMON_H_INCLUDED_


#include <ngx_core.h>
#include <ngx_http.h>

#define NGX_PACKED __attribute__ ((__packed__))

#define NGX_HTTP_TFS_HEADER                           0
#define NGX_HTTP_TFS_BODY                             1

#define NGX_HTTP_TFS_YES                              1
#define NGX_HTTP_TFS_NO                               0
#define NGX_HTTP_TFS_AGAIN                            -20
#define NGX_HTTP_TFS_MAX_RETRY_COUNT                  2

#define NGX_HTTP_TFS_NGINX_APPKEY                     "tfs"
#define NGX_HTTP_TFS_DEFAULT_APPID                    1
#define NGX_HTTP_TFS_RCS_LOCK_FILE                    "nginx_rcs.lock"

#define NGX_HTTP_TFS_MD5_RESULT_LEN                   16
#define NGX_HTTP_TFS_DUPLICATE_KEY_SIZE             \
    (sizeof(uint32_t) + NGX_HTTP_TFS_MD5_RESULT_LEN)
#define NGX_HTTP_TFS_DUPLICATE_VALUE_BASE_SIZE        sizeof(int32_t)
#define NGX_HTTP_TFS_DUPLICATE_INITIAL_MAGIC_VERSION  0x0fffffff

/* rcs, ns, ds, rs, ms */
#define NGX_HTTP_TFS_SERVER_COUNT                     5
#define NGX_HTTP_TFS_METASERVER_COUNT                 10240
/* master_conifg_server;slave_config_server;group */
#define NGX_HTTP_TFS_TAIR_SERVER_ADDR_PART_COUNT      3
/* master && slave */
#define NGX_HTTP_TFS_TAIR_CONFIG_SERVER_COUNT         2

#define NGX_HTTP_TFS_KEEPALIVE_ACTION                 "keepalive"

#define NGX_HTTP_TFS_MAX_READ_FILE_SIZE               (512 * 1024)
#define NGX_HTTP_TFS_USE_LARGE_FILE_SIZE              (15 * 1024 * 1024)
#define NGX_HTTP_TFS_MAX_SIZE                         (ULLONG_MAX - 1)

#define NGX_HTTP_TFS_DEFAULT_BODY_BUFFER_SIZE         (2 * 1024 * 1024)
#define NGX_HTTP_TFS_ZERO_BUF_SIZE                    (512 * 1024)
#define NGX_HTTP_TFS_INIT_FILE_HOLE_COUNT             5

#define NGX_HTTP_TFS_APPEND_OFFSET                     -1

/* tfs file name standard name length */
#define NGX_HTTP_TFS_SMALL_FILE_KEY_CHAR              'T'
#define NGX_HTTP_TFS_LARGE_FILE_KEY_CHAR              'L'
#define NGX_HTTP_TFS_FILE_NAME_LEN                     18
#define NGX_HTTP_TFS_FILE_NAME_BUFF_LEN                19
#define NGX_HTTP_TFS_FILE_NAME_EXCEPT_SUFFIX_LEN       12
#define NGX_HTTP_TFS_MAX_FILE_NAME_LEN                 256
#define NGX_HTTP_TFS_MAX_SUFFIX_LEN                    109 /* 128 - 19 */

#define NGX_HTTP_TFS_MAX_RCSERVER_COUNT                5
#define NGX_HTTP_TFS_MAX_CLUSTER_COUNT                 10
#define NGX_HTTP_TFS_MAX_CLUSTER_ID_COUNT              10

#define NGX_HTTP_TFS_CMD_GET_CLUSTER_ID_NS             20
#define NGX_HTTP_TFS_CMD_GET_GROUP_COUNT               22
#define NGX_HTTP_TFS_CMD_GET_GROUP_SEQ                 23

#define NGX_HTTP_TFS_GMT_TIME_SIZE                  \
    (sizeof("Mon, 28 Sep 1970 06:00:00 GMT") - 1)

#define NGX_HTTP_TFS_MAX_FRAGMENT_SIZE                 (2 * 1024 * 1024)
#define NGX_HTTP_TFS_MAX_BATCH_COUNT                   8


#define NGX_HTTP_TFS_MUR_HASH_SEED                     97

#define NGX_HTTP_TFS_CLIENT_VERSION                    "NGINX"

#define NGX_HTTP_TFS_MIN_TIMER_DELAY                    1000

#define NGX_HTTP_TFS_READ_STAT_NORMAL                   0
#define NGX_HTTP_TFS_READ_STAT_FORCE                    1

#define NGX_HTTP_TFS_IMAGE_TYPE_SIZE                    8

#define NGX_BSWAP_64(x)                         \
    ((((x) & 0xff00000000000000ull) >> 56)      \
    | (((x) & 0x00ff000000000000ull) >> 40)     \
    | (((x) & 0x0000ff0000000000ull) >> 24)     \
    | (((x) & 0x000000ff00000000ull) >> 8)      \
    | (((x) & 0x00000000ff000000ull) << 8)      \
    | (((x) & 0x0000000000ff0000ull) << 24)     \
    | (((x) & 0x000000000000ff00ull) << 40)     \
    | (((x) & 0x00000000000000ffull) << 56))

#define ngx_http_tfs_clear_buf(b) \
    (b)->pos = (b)->start;        \
    (b)->last = (b)->start;

#if (NGX_HAVE_BIG_ENDIAN)

#define ngx_hton64(x) x

#define ngx_ntoh64(x) x

#else

#define ngx_hton64(x)                           \
    NGX_BSWAP_64(x)

#define ngx_ntoh64(x)                           \
    NGX_BSWAP_64(x)


#endif

typedef struct ngx_http_tfs_s ngx_http_tfs_t;
typedef struct ngx_http_tfs_peer_connection_s ngx_http_tfs_peer_connection_t;

typedef struct ngx_http_tfs_main_conf_s ngx_http_tfs_main_conf_t;
typedef struct ngx_http_tfs_loc_conf_s ngx_http_tfs_loc_conf_t;
typedef struct ngx_http_tfs_upstream_s ngx_http_tfs_upstream_t;

typedef struct ngx_http_tfs_inet_s ngx_http_tfs_inet_t;
typedef struct ngx_http_tfs_meta_hh_s  ngx_http_tfs_meta_hh_t;

typedef struct ngx_http_tfs_segment_data_s ngx_http_tfs_segment_data_t;

typedef struct ngx_http_tfs_timers_lock_s ngx_http_tfs_timers_lock_t;
typedef struct ngx_http_tfs_timers_data_s ngx_http_tfs_timers_data_t;

typedef struct {
    uint64_t           size;
} ngx_http_tfs_stat_info_t;


typedef struct {
    uint32_t     crc;
    uint32_t     data_crc;
} ngx_http_tfs_crc_t;


typedef struct {
    uint16_t             code;
    ngx_str_t            msg;
} ngx_http_tfs_action_t;


struct ngx_http_tfs_meta_hh_s {
    uint64_t       app_id;
    uint64_t       user_id;
};


struct ngx_http_tfs_inet_s {
    uint32_t       ip;
    uint32_t       port;
};

typedef struct {
    ngx_http_tfs_inet_t          table[NGX_HTTP_TFS_METASERVER_COUNT];
    uint64_t                     version;
} ngx_http_tfs_meta_table_t;


typedef struct {
    uint64_t                   id;
    int32_t                    offset;
    int64_t                    size;
    int64_t                    u_size;
    int32_t                    modify_time;
    int32_t                    create_time;
    int32_t                    flag;
    uint32_t                   crc;
} NGX_PACKED ngx_http_tfs_raw_file_stat_t;


typedef struct {
    uint64_t                   id;
    int32_t                    offset;
    int32_t                    size;
    int32_t                    u_size;
    int32_t                    modify_time;
    int32_t                    create_time;
    int32_t                    flag;
    uint32_t                   crc;
} NGX_PACKED ngx_http_tfs_raw_file_info_t;


typedef struct {
    int64_t                    pid;
    int64_t                    id;
    uint32_t                   create_time;
    uint32_t                   modify_time;
    uint64_t                   size;
    uint16_t                   ver_no;
} NGX_PACKED ngx_http_tfs_custom_file_info_t;


typedef enum {
    NGX_HTTP_TFS_RC_SERVER = 0,
    NGX_HTTP_TFS_NAME_SERVER,
    NGX_HTTP_TFS_DATA_SERVER,
    NGX_HTTP_TFS_ROOT_SERVER,
    NGX_HTTP_TFS_META_SERVER,
} ngx_http_tfs_peer_server_e;


typedef enum {
    NGX_HTTP_TFS_STATE_WRITE_START = 0,
    NGX_HTTP_TFS_STATE_WRITE_GET_META_TABLE,
    NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_MS,
    NGX_HTTP_TFS_STATE_WRITE_GET_GROUP_COUNT,
    NGX_HTTP_TFS_STATE_WRITE_GET_GROUP_SEQ,
    NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS,
    NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO,
    NGX_HTTP_TFS_STATE_WRITE_STAT_DUP_FILE,
    NGX_HTTP_TFS_STATE_WRITE_CREATE_FILE_NAME,
    NGX_HTTP_TFS_STATE_WRITE_WRITE_DATA,
    NGX_HTTP_TFS_STATE_WRITE_CLOSE_FILE,
    NGX_HTTP_TFS_STATE_WRITE_WRITE_MS,
    NGX_HTTP_TFS_STATE_WRITE_DONE,
    NGX_HTTP_TFS_STATE_WRITE_DELETE_DATA,
} ngx_http_tfs_state_write_e;


typedef enum {
    NGX_HTTP_TFS_STATE_READ_START = 0,
    NGX_HTTP_TFS_STATE_READ_GET_META_TABLE,
    NGX_HTTP_TFS_STATE_READ_GET_FRAG_INFO,
    NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO,
    NGX_HTTP_TFS_STATE_READ_READ_DATA,
    NGX_HTTP_TFS_STATE_READ_DONE,
} ngx_http_tfs_state_read_e;


typedef enum {
    NGX_HTTP_TFS_STATE_REMOVE_START = 0,
    NGX_HTTP_TFS_STATE_REMOVE_GET_META_TABLE,
    NGX_HTTP_TFS_STATE_REMOVE_GET_FRAG_INFO,
    NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_COUNT,
    NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_SEQ,
    NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO,
    NGX_HTTP_TFS_STATE_REMOVE_STAT_FILE,
    NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT,
    NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA,
    NGX_HTTP_TFS_STATE_REMOVE_NOTIFY_MS,
    NGX_HTTP_TFS_STATE_REMOVE_DONE,
} ngx_http_tfs_state_remove_e;


typedef enum {
    NGX_HTTP_TFS_STATE_STAT_START = 0,
    NGX_HTTP_TFS_STATE_STAT_GET_BLK_INFO,
    NGX_HTTP_TFS_STATE_STAT_STAT_FILE,
    NGX_HTTP_TFS_STATE_STAT_DONE,
} ngx_http_tfs_state_stat_e;


typedef enum {
    NGX_HTTP_TFS_STATE_ACTION_START = 0,
    NGX_HTTP_TFS_STATE_ACTION_GET_META_TABLE,
    NGX_HTTP_TFS_STATE_ACTION_PROCESS,
    NGX_HTTP_TFS_STATE_ACTION_DONE,
} ngx_http_tfs_state_action_e;


static inline uint32_t
ngx_http_tfs_crc(uint32_t crc, const char *data, size_t len)
{
    size_t i;

    for (i = 0; i < len; ++i) {
        crc = (crc >> 8) ^ ngx_crc32_table256[(crc ^ *data++) & 0xff];
    }

    return crc;
}

ngx_chain_t *ngx_http_tfs_alloc_chains(ngx_pool_t *pool, size_t count);
ngx_chain_t *ngx_http_tfs_chain_get_free_buf(ngx_pool_t *p,
    ngx_chain_t **free, size_t size);
void ngx_http_tfs_free_chains(ngx_chain_t **free, ngx_chain_t **out);

ngx_int_t ngx_http_tfs_test_connect(ngx_connection_t *c);
uint64_t ngx_http_tfs_generate_packet_id(void);

ngx_int_t ngx_http_tfs_parse_headerin(ngx_http_request_t *r,
    ngx_str_t *header_name, ngx_str_t *value);

ngx_int_t ngx_http_tfs_compute_buf_crc(ngx_http_tfs_crc_t *t_crc, ngx_buf_t *b,
    size_t size, ngx_log_t *log);

ngx_int_t ngx_http_tfs_peer_set_addr(ngx_pool_t *pool,
    ngx_http_tfs_peer_connection_t *p, ngx_http_tfs_inet_t *addr);

uint32_t ngx_http_tfs_murmur_hash(u_char *data, size_t len);

ngx_int_t ngx_http_tfs_parse_inet(ngx_str_t *u, ngx_http_tfs_inet_t *addr);
int32_t ngx_http_tfs_raw_fsname_hash(const u_char *str, const int32_t len);
ngx_int_t ngx_http_tfs_get_local_ip(ngx_str_t device, struct sockaddr_in *addr);
ngx_buf_t *ngx_http_tfs_copy_buf_chain(ngx_pool_t *pool, ngx_chain_t *in);
ngx_int_t ngx_http_tfs_sum_md5(ngx_chain_t *body, u_char *md5_final,
    ssize_t *body_size, ngx_log_t *log);
u_char *ngx_http_tfs_time(u_char *buf, time_t t);

ngx_int_t ngx_http_tfs_status_message(ngx_buf_t *b, ngx_str_t *action,
    ngx_log_t *log);
ngx_int_t ngx_http_tfs_get_parent_dir(ngx_str_t *file_path,
    ngx_int_t *dir_level);
ngx_int_t ngx_http_tfs_set_output_file_name(ngx_http_tfs_t *t);
long long ngx_http_tfs_atoll(u_char *line, size_t n);
ngx_int_t ngx_http_tfs_atoull(u_char *line, size_t n,
    unsigned long long *value);
void *ngx_http_tfs_prealloc(ngx_pool_t *pool, void *p, size_t old_size,
    size_t new_size);
uint64_t ngx_http_tfs_get_chain_buf_size(ngx_chain_t *data);

void ngx_http_tfs_dump_segment_data(ngx_http_tfs_segment_data_t *segment,
    ngx_log_t *log);
ngx_http_tfs_t *ngx_http_tfs_alloc_st(ngx_http_tfs_t *t);

#define ngx_http_tfs_free_st(t)           \
        t->next = t->parent->free_sts;   \
        t->parent->free_sts = t;         \


ngx_int_t ngx_http_tfs_get_content_type(u_char *data, ngx_str_t *type);
ngx_msec_int_t ngx_http_tfs_get_request_time(ngx_http_tfs_t *t);
ngx_int_t ngx_chain_add_copy_with_buf(ngx_pool_t *pool, ngx_chain_t **chain,
    ngx_chain_t *in);
void ngx_http_tfs_wrap_raw_file_info(ngx_http_tfs_raw_file_info_t *file_info,
    ngx_http_tfs_raw_file_stat_t *file_stat);


#endif  /* _NGX_HTTP_TFS_COMMON_H_INCLUDED_ */
