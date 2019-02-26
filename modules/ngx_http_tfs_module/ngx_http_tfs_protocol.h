
/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_PROTOCOL_H_
#define _NGX_HTTP_TFS_PROTOCOL_H_


#define NGX_PACKED __attribute__ ((__packed__))

#define NGX_HTTP_TFS_PACKET_FLAG            0x4E534654      /* TFSN */
#define NGX_HTTP_TFS_PACKET_VERSION         2

#define NGX_HTTP_TFS_READ                   0
#define NGX_HTTP_TFS_READ_V2                1

#define NGX_HTTP_TFS_RAW_FILE_INFO_SIZE     sizeof(ngx_http_tfs_raw_file_info_t)
#define NGX_HTTP_TFS_READ_V2_TAIL_LEN           \
    sizeof(ngx_http_tfs_ds_readv2_response_tail_t)

typedef enum
{
    NGX_HTTP_TFS_STATUS_MESSAGE = 1,
    NGX_HTTP_TFS_GET_BLOCK_INFO_MESSAGE = 2,
    NGX_HTTP_TFS_SET_BLOCK_INFO_MESSAGE = 3,
    NGX_HTTP_TFS_CARRY_BLOCK_MESSAGE = 4,
    NGX_HTTP_TFS_SET_DATASERVER_MESSAGE = 5,
    NGX_HTTP_TFS_UPDATE_BLOCK_INFO_MESSAGE = 6,
    NGX_HTTP_TFS_READ_DATA_MESSAGE = 7,
    NGX_HTTP_TFS_RESP_READ_DATA_MESSAGE = 8,
    NGX_HTTP_TFS_WRITE_DATA_MESSAGE = 9,
    NGX_HTTP_TFS_CLOSE_FILE_MESSAGE = 10,
    NGX_HTTP_TFS_UNLINK_FILE_MESSAGE = 11,
    NGX_HTTP_TFS_REPLICATE_BLOCK_MESSAGE = 12,
    NGX_HTTP_TFS_COMPACT_BLOCK_MESSAGE = 13,
    NGX_HTTP_TFS_GET_SERVER_STATUS_MESSAGE = 14,
    NGX_HTTP_TFS_SHOW_SERVER_INFORMATION_MESSAGE = 15,
    NGX_HTTP_TFS_SUSPECT_DATASERVER_MESSAGE = 16,
    NGX_HTTP_TFS_FILE_INFO_MESSAGE = 17,
    NGX_HTTP_TFS_RESP_FILE_INFO_MESSAGE = 18,
    NGX_HTTP_TFS_RENAME_FILE_MESSAGE = 19,
    NGX_HTTP_TFS_CLIENT_CMD_MESSAGE = 20,
    NGX_HTTP_TFS_CREATE_FILENAME_MESSAGE = 21,
    NGX_HTTP_TFS_RESP_CREATE_FILENAME_MESSAGE = 22,
    NGX_HTTP_TFS_ROLLBACK_MESSAGE = 23,
    NGX_HTTP_TFS_RESP_HEART_MESSAGE = 24,
    NGX_HTTP_TFS_RESET_BLOCK_VERSION_MESSAGE = 25,
    NGX_HTTP_TFS_BLOCK_FILE_INFO_MESSAGE = 26,
    NGX_HTTP_TFS_LEGACY_UNIQUE_FILE_MESSAGE = 27,
    NGX_HTTP_TFS_LEGACY_RETRY_COMMAND_MESSAGE = 28,
    NGX_HTTP_TFS_NEW_BLOCK_MESSAGE = 29,
    NGX_HTTP_TFS_REMOVE_BLOCK_MESSAGE = 30,
    NGX_HTTP_TFS_LIST_BLOCK_MESSAGE = 31,
    NGX_HTTP_TFS_RESP_LIST_BLOCK_MESSAGE = 32,
    NGX_HTTP_TFS_BLOCK_WRITE_COMPLETE_MESSAGE = 33,
    NGX_HTTP_TFS_BLOCK_RAW_META_MESSAGE = 34,
    NGX_HTTP_TFS_WRITE_RAW_DATA_MESSAGE = 35,
    NGX_HTTP_TFS_WRITE_INFO_BATCH_MESSAGE = 36,
    NGX_HTTP_TFS_BLOCK_COMPACT_COMPLETE_MESSAGE = 37,
    NGX_HTTP_TFS_READ_DATA_MESSAGE_V2 = 38,
    NGX_HTTP_TFS_RESP_READ_DATA_MESSAGE_V2 = 39,
    NGX_HTTP_TFS_LIST_BITMAP_MESSAGE =40,
    NGX_HTTP_TFS_RESP_LIST_BITMAP_MESSAGE = 41,
    NGX_HTTP_TFS_RELOAD_CONFIG_MESSAGE = 42,
    NGX_HTTP_TFS_SERVER_META_INFO_MESSAGE = 43,
    NGX_HTTP_TFS_RESP_SERVER_META_INFO_MESSAGE = 44,
    NGX_HTTP_TFS_READ_RAW_DATA_MESSAGE = 45,
    NGX_HTTP_TFS_RESP_READ_RAW_DATA_MESSAGE = 46,
    NGX_HTTP_TFS_REPLICATE_INFO_MESSAGE = 47,
    NGX_HTTP_TFS_ACCESS_STAT_INFO_MESSAGE = 48,
    NGX_HTTP_TFS_READ_SCALE_IMAGE_MESSAGE = 49,
    NGX_HTTP_TFS_OPLOG_SYNC_MESSAGE = 50,
    NGX_HTTP_TFS_OPLOG_SYNC_RESPONSE_MESSAGE = 51,
    NGX_HTTP_TFS_MASTER_AND_SLAVE_HEART_MESSAGE = 52,
    NGX_HTTP_TFS_MASTER_AND_SLAVE_HEART_RESPONSE_MESSAGE = 53,
    NGX_HTTP_TFS_HEARTBEAT_AND_NS_HEART_MESSAGE = 54,
    NGX_HTTP_TFS_OWNER_CHECK_MESSAGE = 55,
    NGX_HTTP_TFS_GET_BLOCK_LIST_MESSAGE = 56,
    NGX_HTTP_TFS_CRC_ERROR_MESSAGE = 57,
    NGX_HTTP_TFS_ADMIN_CMD_MESSAGE = 58,
    NGX_HTTP_TFS_BATCH_GET_BLOCK_INFO_MESSAGE = 59,
    NGX_HTTP_TFS_BATCH_SET_BLOCK_INFO_MESSAGE = 60,
    NGX_HTTP_TFS_REMOVE_BLOCK_RESPONSE_MESSAGE = 61,
    NGX_HTTP_TFS_READ_DATA_MESSAGE_V3 = 62,
    NGX_HTTP_TFS_RESP_READ_DATA_MESSAGE_V3 = 63,
    NGX_HTTP_TFS_DUMP_PLAN_MESSAGE = 64,
    NGX_HTTP_TFS_DUMP_PLAN_RESPONSE_MESSAGE = 65,
    NGX_HTTP_TFS_REQ_RC_LOGIN_MESSAGE = 66,
    NGX_HTTP_TFS_RSP_RC_LOGIN_MESSAGE = 67,
    NGX_HTTP_TFS_REQ_RC_KEEPALIVE_MESSAGE = 68,
    NGX_HTTP_TFS_RSP_RC_KEEPALIVE_MESSAGE = 69,
    NGX_HTTP_TFS_REQ_RC_LOGOUT_MESSAGE = 70,
    NGX_HTTP_TFS_REQ_RC_RELOAD_MESSAGE = 71,
    NGX_HTTP_TFS_GET_DATASERVER_INFORMATION_MESSAGE = 72,
    NGX_HTTP_TFS_GET_DATASERVER_INFORMATION_RESPONSE_MESSAGE = 73,
    NGX_HTTP_TFS_FILEPATH_ACTION_MESSAGE = 74,
    NGX_HTTP_TFS_WRITE_FILEPATH_MESSAGE = 75,
    NGX_HTTP_TFS_READ_FILEPATH_MESSAGE = 76,
    NGX_HTTP_TFS_RESP_READ_FILEPATH_MESSAGE = 77,
    NGX_HTTP_TFS_LS_FILEPATH_MESSAGE = 78,
    NGX_HTTP_TFS_RESP_LS_FILEPATH_MESSAGE = 79,
    NGX_HTTP_TFS_REQ_RT_UPDATE_TABLE_MESSAGE = 80,
    NGX_HTTP_TFS_RSP_RT_UPDATE_TABLE_MESSAGE = 81,
    NGX_HTTP_TFS_REQ_RT_MS_KEEPALIVE_MESSAGE = 82,
    NGX_HTTP_TFS_RSP_RT_MS_KEEPALIVE_MESSAGE = 83,
    NGX_HTTP_TFS_REQ_RT_GET_TABLE_MESSAGE = 84,
    NGX_HTTP_TFS_RSP_RT_GET_TABLE_MESSAGE = 85,
    NGX_HTTP_TFS_REQ_RT_RS_KEEPALIVE_MESSAGE = 86,
    NGX_HTTP_TFS_RSP_RT_RS_KEEPALIVE_MESSAGE = 87,
    NGX_HTTP_TFS_LOCAL_PACKET = 500
} ngx_http_tfs_status_msg_e;


typedef enum
{
    NGX_HTTP_TFS_STATUS_MESSAGE_OK = 0,
    NGX_HTTP_TFS_STATUS_MESSAGE_ERROR,
    NGX_HTTP_TFS_STATUS_NEED_SEND_BLOCK_INFO,
    NGX_HTTP_TFS_STATUS_MESSAGE_PING,
    NGX_HTTP_TFS_STATUS_MESSAGE_REMOVE,
    NGX_HTTP_TFS_STATUS_MESSAGE_BLOCK_FULL,
    NGX_HTTP_TFS_STATUS_MESSAGE_ACCESS_DENIED
} ngx_http_tfs_message_status_t;


typedef enum
{
    NGX_HTTP_TFS_ACTION_NON = 0,
    NGX_HTTP_TFS_ACTION_CREATE_DIR = 1,
    NGX_HTTP_TFS_ACTION_CREATE_FILE = 2,
    NGX_HTTP_TFS_ACTION_REMOVE_DIR = 3,
    NGX_HTTP_TFS_ACTION_REMOVE_FILE = 4,
    NGX_HTTP_TFS_ACTION_MOVE_DIR = 5,
    NGX_HTTP_TFS_ACTION_MOVE_FILE = 6,
    NGX_HTTP_TFS_ACTION_READ_FILE = 7,
    NGX_HTTP_TFS_ACTION_LS_DIR = 8,
    NGX_HTTP_TFS_ACTION_LS_FILE = 9,
    NGX_HTTP_TFS_ACTION_WRITE_FILE = 10,
    NGX_HTTP_TFS_ACTION_STAT_FILE = 11,
    NGX_HTTP_TFS_ACTION_KEEPALIVE = 12,
    NGX_HTTP_TFS_ACTION_GET_APPID = 13,
    NGX_HTTP_TFS_ACTION_UNDELETE_FILE = 14,
    NGX_HTTP_TFS_ACTION_CONCEAL_FILE = 15,
    NGX_HTTP_TFS_ACTION_REVEAL_FILE = 16,
} ngx_http_tfs_action_e;


typedef enum
{
    NGX_HTTP_TFS_OPEN_MODE_DEFAULT = 0,
    NGX_HTTP_TFS_OPEN_MODE_READ = 1,
    NGX_HTTP_TFS_OPEN_MODE_WRITE = 2,
    NGX_HTTP_TFS_OPEN_MODE_CREATE = 4,
    NGX_HTTP_TFS_OPEN_MODE_NEWBLK = 8,
    NGX_HTTP_TFS_OPEN_MODE_NOLEASE = 16,
    NGX_HTTP_TFS_OPEN_MODE_STAT = 32,
    NGX_HTTP_TFS_OPEN_MODE_LARGE = 64,
    NGX_HTTP_TFS_OPEN_MODE_UNLINK = 128
} ngx_http_tfs_open_mode_e;


typedef enum
{
    NGX_HTTP_TFS_CUSTOM_FT_FILE = 1,
    NGX_HTTP_TFS_CUSTOM_FT_DIR,
    NGX_HTTP_TFS_CUSTOM_FT_PWRITE_FILE
} ngx_http_tfs_custom_file_type_e;


typedef enum
{
    NGX_HTTP_TFS_CLIENT_CMD_EXPBLK = 1,
    NGX_HTTP_TFS_CLIENT_CMD_LOADBLK,
    NGX_HTTP_TFS_CLIENT_CMD_COMPACT,
    NGX_HTTP_TFS_CLIENT_CMD_IMMEDIATELY_REPL,
    NGX_HTTP_TFS_CLIENT_CMD_REPAIR_GROUP,
    NGX_HTTP_TFS_CLIENT_CMD_SET_PARAM,
    NGX_HTTP_TFS_CLIENT_CMD_UNLOADBLK,
    NGX_HTTP_TFS_CLIENT_CMD_FORCE_DATASERVER_REPORT,
    NGX_HTTP_TFS_CLIENT_CMD_ROTATE_LOG,
    NGX_HTTP_TFS_CLIENT_CMD_GET_BALANCE_PERCENT,
    NGX_HTTP_TFS_CLIENT_CMD_SET_BALANCE_PERCENT
} ngx_http_tfs_ns_ctl_type_e;


typedef enum
{
    NGX_HTTP_TFS_CLOSE_FILE_MASTER = 100,
    NGX_HTTP_TFS_CLOSE_FILE_SLAVER
} ngx_http_tfs_close_mode_e;


typedef enum
{
    NGX_HTTP_TFS_REMOVE_FILE_MASTER = 0,
    NGX_HTTP_TFS_REMOVE_FILE_SLAVER
} ngx_http_tfs_remove_mode_e;


typedef enum
{
    NGX_HTTP_TFS_FILE_DEFAULT_OPTION = 0,
    NGX_HTTP_TFS_FILE_NO_SYNC_LOG = 1,
    NGX_HTTP_TFS_FILE_CLOSE_FLAG_WRITE_DATA_FAILED = 2
} ngx_http_tfs_close_option_e;


typedef enum
{
    NGX_HTTP_TFS_UNLINK_DELETE = 0,
    NGX_HTTP_TFS_UNLINK_UNDELETE = 2,
    NGX_HTTP_TFS_UNLINK_CONCEAL = 4,
    NGX_HTTP_TFS_UNLINK_REVEAL = 6
} ngx_http_tfs_unlink_type_e;


typedef enum
{
    NGX_HTTP_TFS_FILE_NORMAL = 0,
    NGX_HTTP_TFS_FILE_DELETED = 1,
    NGX_HTTP_TFS_FILE_INVALID = 2,
    NGX_HTTP_TFS_FILE_CONCEAL = 4
} ngx_http_tfs_file_status_e;


typedef enum
{
    NGX_HTTP_TFS_ACCESS_FORBIDEN = 0,
    NGX_HTTP_TFS_ACCESS_READ_ONLY = 1,
    NGX_HTTP_TFS_ACCESS_READ_AND_WRITE = 2,
} ngx_http_tfs_access_type_e;


typedef struct {
    uint32_t                                flag;
    uint32_t                                len;
    uint16_t                                type;
    uint16_t                                version;
    uint64_t                                id;
    uint32_t                                crc;
} NGX_PACKED ngx_http_tfs_header_t;


typedef struct {
    int32_t                                 code;
    uint32_t                                error_len;
    u_char                                  error_str[];
} NGX_PACKED ngx_http_tfs_status_msg_t;


/* root server */
typedef struct {
    ngx_http_tfs_header_t                   header;
    uint8_t                                 reserse;
} NGX_PACKED ngx_http_tfs_rs_request_t;


typedef struct {
    uint64_t                                version;
    uint64_t                                length;
    u_char                                  table[];
} NGX_PACKED ngx_http_tfs_rs_response_t;


/* meta server */
typedef struct {
    uint32_t        block_id;
    uint64_t        file_id;
    int64_t         offset;
    uint32_t        size;
} NGX_PACKED ngx_http_tfs_meta_frag_meta_info_t;


typedef struct {
    uint32_t                               cluster_id;

    /* highest is split flag */
    uint32_t                               frag_count;
    ngx_http_tfs_meta_frag_meta_info_t     frag_meta[];
} NGX_PACKED ngx_http_tfs_meta_frag_info_t;


typedef struct {
    ngx_http_tfs_header_t                   header;
    uint64_t                                app_id;
    uint64_t                                user_id;
    uint32_t                                file_len;
    u_char                                  file_path_s[];
} NGX_PACKED ngx_http_tfs_ms_base_msg_header_t;


typedef struct {
    ngx_http_tfs_header_t                   header;
    uint64_t                                app_id;
    uint64_t                                user_id;
    int64_t                                 pid;
    uint32_t                                file_len;
    u_char                                  file_path[];
} NGX_PACKED ngx_http_tfs_ms_ls_msg_header_t;


typedef struct {
    /* ignore header */
    uint8_t               still_have;
    uint32_t              count;
} NGX_PACKED ngx_http_tfs_ms_ls_response_t;


typedef struct {
    /* ignore header */
    uint8_t                           still_have;
    ngx_http_tfs_meta_frag_info_t     frag_info;
} NGX_PACKED ngx_http_tfs_ms_read_response_t;


/* rc server  */
typedef struct {
    ngx_http_tfs_header_t                   header;
    uint32_t                                appkey_len;
    u_char                                  appkey[];
    /* uint64_t                             app_ip */
} NGX_PACKED ngx_http_tfs_rcs_login_msg_header_t;


/* name server */
typedef struct {
    ngx_http_tfs_header_t                   header;
    uint32_t                                mode;

    uint32_t                                block_id;
    uint32_t                                fs_count;
    u_char                                  fs_id[];
} NGX_PACKED ngx_http_tfs_ns_block_info_request_t;


typedef struct {
    ngx_http_tfs_header_t                   header;
    uint32_t                                mode;

    uint32_t                                block_count;
    uint32_t                                block_ids[];
} NGX_PACKED ngx_http_tfs_ns_batch_block_info_request_t;


typedef struct {
    /* ignore header */
    uint32_t                                block_id;
    uint32_t                                ds_count;
    uint64_t                                ds_addrs[];
} NGX_PACKED ngx_http_tfs_ns_block_info_response_t;


typedef struct {
    /* ignore header */
    uint32_t                                block_count;
} NGX_PACKED ngx_http_tfs_ns_batch_block_info_response_t;


typedef struct {
    ngx_http_tfs_header_t                   header;

    int32_t                                 cmd;
    int64_t                                 value1;
    int32_t                                 value2;
    int32_t                                 value3;
    int64_t                                 value4;
} NGX_PACKED ngx_http_tfs_ns_ctl_request_t;


/* data server */
typedef struct {
    ngx_http_tfs_header_t                   base_header;
    uint32_t                                block_id;
    uint64_t                                file_id;
} NGX_PACKED ngx_http_tfs_ds_msg_header_t;


typedef struct {
    ngx_http_tfs_ds_msg_header_t            header;
    int32_t                                 offset;
    uint32_t                                length;
    uint8_t                                 flag;
} NGX_PACKED ngx_http_tfs_ds_read_request_t;


typedef struct {
    ngx_http_tfs_header_t                    header;
    int32_t                                  data_len;
} NGX_PACKED ngx_http_tfs_ds_read_response_t;


typedef struct {
    /* ignore header */
    uint32_t                                block_id;
    uint64_t                                file_id;
    uint64_t                                file_number;
} NGX_PACKED ngx_http_tfs_ds_cf_reponse_t;


typedef struct {
    ngx_http_tfs_ds_msg_header_t             header;
    int32_t                                  offset;
    uint32_t                                 length;
    int32_t                                  is_server;
    uint64_t                                 file_number;
} NGX_PACKED ngx_http_tfs_ds_write_request_t;


typedef struct {
    ngx_http_tfs_ds_msg_header_t             header;
    uint32_t                                 server_mode;
} NGX_PACKED ngx_http_tfs_ds_unlink_request_t;


typedef struct {
    ngx_http_tfs_ds_msg_header_t             header;
    int32_t                                  mode;
    uint32_t                                 crc;
    uint64_t                                 file_number;
} NGX_PACKED ngx_http_tfs_ds_close_request_t;


typedef struct {
    ngx_http_tfs_ds_msg_header_t            header;
    uint32_t                                mode;
} NGX_PACKED ngx_http_tfs_ds_stat_request_t;


typedef struct {
    /* ignore header */
    uint32_t                                 data_len;
    ngx_http_tfs_raw_file_info_t             file_info;
} NGX_PACKED ngx_http_tfs_ds_stat_response_t;


typedef struct {
    uint32_t                                 file_info_len;
    ngx_http_tfs_raw_file_info_t             file_info;
} NGX_PACKED ngx_http_tfs_ds_readv2_response_tail_t;


typedef struct {
    uint32_t                                 count; /* segment count */

    /* total size of all data segments */
    uint64_t                                 size;
    u_char                                   reserve[64];
} NGX_PACKED ngx_http_tfs_segment_head_t;


typedef struct {
    /* ignore header */
    int32_t                                  data_len;
    ngx_http_tfs_segment_head_t              seg_head;
    uint32_t                                 file_info_len;
    ngx_http_tfs_raw_file_info_t             file_info;
} NGX_PACKED ngx_http_tfs_ds_sp_readv2_response_t;


typedef struct {
    ngx_str_t                                file_name;
    ngx_http_tfs_custom_file_info_t          file_info;
} ngx_http_tfs_custom_file_t;


typedef struct ngx_http_tfs_custom_meta_info_s ngx_http_tfs_custom_meta_info_t;

struct ngx_http_tfs_custom_meta_info_s {
    uint32_t                                   file_count;
    uint32_t                                   rest_file_count;
    uint32_t                                   file_index;
    ngx_http_tfs_custom_file_t                *files;
    ngx_http_tfs_custom_meta_info_t           *next;
};


typedef struct {
    uint64_t                                 offset;
    uint64_t                                 length;
} ngx_http_tfs_file_hole_info_t;




#endif  /* _NGX_HTTP_TFS_PROTOCOL_H_ */
