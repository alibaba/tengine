
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#ifndef _NGX_HTTP_TFS_ERRNO_H_INCLUDED_
#define _NGX_HTTP_TFS_ERRNO_H_INCLUDED_


#include <nginx.h>


#define NGX_HTTP_TFS_EXIT_GENERAL_ERROR            -1000
#define NGX_HTTP_TFS_EXIT_CONFIG_ERROR             -1001
#define NGX_HTTP_TFS_EXIT_UNKNOWN_MSGTYPE          -1002
#define NGX_HTTP_TFS_EXIT_INVALID_ARGU             -1003
#define NGX_HTTP_TFS_EXIT_ALL_SEGMENT_             -1004
#define NGX_HTTP_TFS_EXIT_INVALIDFD_ERROR          -1005
#define NGX_HTTP_TFS_EXIT_NOT_INIT_ERROR           -1006
#define NGX_HTTP_TFS_EXIT_INVALID_ARGU_ERROR       -1007
#define NGX_HTTP_TFS_EXIT_NOT_PERM_OPER            -1008
#define NGX_HTTP_TFS_EXIT_NOT_OPEN_ERROR           -1009
#define NGX_HTTP_TFS_EXIT_CHECK_CRC_ERROR          -1010
#define NGX_HTTP_TFS_EXIT_SERIALIZE_ERROR          -1011
#define NGX_HTTP_TFS_EXIT_DESERIALIZE_ERROR        -1012
/* access permission error */
#define NGX_HTTP_TFS_EXIT_ACCESS_PERMISSION_ERROR  -1013
/* system parameter error */
#define NGX_HTTP_TFS_EXIT_SYSTEM_PARAMETER_ERROR   -1014
#define NGX_HTTP_TFS_EXIT_UNIQUE_META_NOT_EXIST    -1015
/* fuction parameter error */
#define NGX_HTTP_TFS_EXIT_PARAMETER_ERROR          -1016
/* mmap file failed */
#define NGX_HTTP_TFS_EXIT_MMAP_FILE_ERROR          -1017
/* lru value not found by key */
#define NGX_HTTP_TFS_EXIT_LRU_VALUE_NOT_EXIST      -1018
/* lru value existed */
#define NGX_HTTP_TFS_EXIT_LRU_VALUE_EXIST          -1019
/* channel id invalid */
#define NGX_HTTP_TFS_EXIT_CHANNEL_ID_INVALID       -1020
/* data packet timeout */
#define NGX_HTTP_TFS_EXIT_DATA_PACKET_TIMEOUT      -1021

#define NGX_HTTP_TFS_EXIT_FILE_OP_ERROR            -2000
#define NGX_HTTP_TFS_EXIT_OPEN_FILE_ERROR          -2001
#define NGX_HTTP_TFS_EXIT_INVALID_FD               -2002
#define NGX_HTTP_TFS_EXIT_RECORD_SIZE_ERROR        -2003
#define NGX_HTTP_TFS_EXIT_READ_FILE_ERROR          -2004
#define NGX_HTTP_TFS_EXIT_WRITE_FILE_ERROR         -2005
#define NGX_HTTP_TFS_EXIT_FILESYSTEM_ERROR         -2006
#define NGX_HTTP_TFS_EXIT_FILE_FORMAT_ERROR        -2007
#define NGX_HTTP_TFS_EXIT_SLOTS_OFFSET_SIZE_ERROR  -2008
#define NGX_HTTP_TFS_EXIT_FILE_BUSY_ERROR          -2009

#define NGX_HTTP_TFS_EXIT_NETWORK_ERROR            -3000
#define NGX_HTTP_TFS_EXIT_IOCTL_ERROR              -3001
#define NGX_HTTP_TFS_EXIT_CONNECT_ERROR            -3002
#define NGX_HTTP_TFS_EXIT_SENDMSG_ERROR            -3003
#define NGX_HTTP_TFS_EXIT_RECVMSG_ERROR            -3004
#define NGX_HTTP_TFS_EXIT_TIMEOUT_ERROR            -3005
/* waitid exist error */
#define NGX_HTTP_TFS_EXIT_WAITID_EXIST_ERROR       -3006
/* waitid not found in waitid set */
#define NGX_HTTP_TFS_EXIT_WAITID_NOT_FOUND_ERROR   -3007
/* socket nof found in socket map */
#define NGX_HTTP_TFS_EXIT_SOCKET_NOT_FOUND_ERROR   -3008

#define NGX_HTTP_TFS_EXIT_TFS_ERROR                -5000
#define NGX_HTTP_TFS_EXIT_NO_BLOCK                 -5001
#define NGX_HTTP_TFS_EXIT_NO_DATASERVER            -5002
#define NGX_HTTP_TFS_EXIT_BLOCK_NOT_FOUND          -5003
#define NGX_HTTP_TFS_EXIT_DATASERVER_NOT_FOUND     -5004
/* lease not found */
#define NGX_HTTP_TFS_EXIT_CANNOT_GET_LEASE         -5005
#define NGX_HTTP_TFS_EXIT_COMMIT_ERROR             -5006
#define NGX_HTTP_TFS_EXIT_LEASE_EXPIRED            -5007
#define NGX_HTTP_TFS_EXIT_BINLOG_ERROR             -5008
#define NGX_HTTP_TFS_EXIT_NO_REPLICATE             -5009
#define NGX_HTTP_TFS_EXIT_BLOCK_BUSY               -5010
/* update block information version error */
#define NGX_HTTP_TFS_EXIT_UPDATE_BLOCK_INFO_VERSION_ERROR     -5011
/* access mode error */
#define NGX_HTTP_TFS_EXIT_ACCESS_MODE_ERROR                   -5012
/* play log error */
#define NGX_HTTP_TFS_EXIT_PLAY_LOG_ERROR                      -5013
/* current nameserver only read */
#define NGX_HTTP_TFS_EXIT_NAMESERVER_ONLY_READ                -5014
/* current block already exist */
#define NGX_HTTP_TFS_EXIT_BLOCK_ALREADY_EXIST                 -5015
/* create block by block id failed */
#define NGX_HTTP_TFS_EXIT_CREATE_BLOCK_BY_ID_ERROR            -5016
/* server object not found in XXX */
#define NGX_HTTP_TFS_EXIT_SERVER_OBJECT_NOT_FOUND             -5017
/* update relation error */
#define NGX_HTTP_TFS_EXIT_UPDATE_RELATION_ERROR               -5018
/* nameserver in safe_mode_time, discard newblk packet */
#define NGX_HTTP_TFS_EXIT_DISCARD_NEWBLK_ERROR                -5019

/* write offset error */
#define NGX_HTTP_TFS_EXIT_WRITE_OFFSET_ERROR                  -8001
/* read offset error */
#define NGX_HTTP_TFS_EXIT_READ_OFFSET_ERROR                   -8002
/* block id is zero, fatal error */
#define NGX_HTTP_TFS_EXIT_BLOCKID_ZERO_ERROR                  -8003
/* block is used up, fatal error */
#define NGX_HTTP_TFS_EXIT_BLOCK_EXHAUST_ERROR                 -8004
/* need extend too much physcial block when extend block */
#define NGX_HTTP_TFS_EXIT_PHYSICALBLOCK_NUM_ERROR             -8005
/* can't find logic block */
#define NGX_HTTP_TFS_EXIT_NO_LOGICBLOCK_ERROR                 -8006
/* input point is null */
#define NGX_HTTP_TFS_EXIT_POINTER_NULL                        -8007
/* cat find unused fileid in limited times */
#define NGX_HTTP_TFS_EXIT_CREATE_FILEID_ERROR                 -8008
/* block id conflict */
#define NGX_HTTP_TFS_EXIT_BLOCKID_CONFLICT_ERROR              -8009
/* LogicBlock already Exists */
#define NGX_HTTP_TFS_EXIT_BLOCK_EXIST_ERROR                   -8010
/* compact block error */
#define NGX_HTTP_TFS_EXIT_COMPACT_BLOCK_ERROR                 -8011
/* read or write length is less than required */
#define NGX_HTTP_TFS_EXIT_DISK_OPER_INCOMPLETE                -8012
/* datafile is NULL  / crc / getdata error */
#define NGX_HTTP_TFS_EXIT_DATA_FILE_ERROR                     -8013
/* too much data file */
#define NGX_HTTP_TFS_EXIT_DATAFILE_OVERLOAD                   -8014
/* data file is expired */
#define NGX_HTTP_TFS_EXIT_DATAFILE_EXPIRE_ERROR               -8015
/* file flag or id error when read file */
#define NGX_HTTP_TFS_EXIT_FILE_INFO_ERROR                     -8016
/* fileid is same in rename file */
#define NGX_HTTP_TFS_EXIT_RENAME_FILEID_SAME_ERROR            -8017
/* file status error(in unlinkfile) */
#define NGX_HTTP_TFS_EXIT_FILE_STATUS_ERROR                   -8018
/* action is not defined(in unlinkfile) */
#define NGX_HTTP_TFS_EXIT_FILE_ACTION_ERROR                   -8019
/* file system is not inited */
#define NGX_HTTP_TFS_EXIT_FS_NOTINIT_ERROR                    -8020
/* file system's bit map conflict */
#define NGX_HTTP_TFS_EXIT_BITMAP_CONFLICT_ERROR               -8021
/* physical block is already exist in file system */
#define NGX_HTTP_TFS_EXIT_PHYSIC_UNEXPECT_FOUND_ERROR         -8022
#define NGX_HTTP_TFS_EXIT_BLOCK_SETED_ERROR                   -8023
/* index is loaded when create or load */
#define NGX_HTTP_TFS_EXIT_INDEX_ALREADY_LOADED_ERROR          -8024
/* meta not found in index */
#define NGX_HTTP_TFS_EXIT_META_NOT_FOUND_ERROR                -8025
/* meta found in index when insert */
#define NGX_HTTP_TFS_EXIT_META_UNEXPECT_FOUND_ERROR           -8026
/* require offset is out of index size */
#define NGX_HTTP_TFS_EXIT_META_OFFSET_ERROR                   -8027
/* bucket size is conflict with before */
#define NGX_HTTP_TFS_EXIT_BUCKET_CONFIGURE_ERROR              -8028
/* index already exist when create index */
#define NGX_HTTP_TFS_EXIT_INDEX_UNEXPECT_EXIST_ERROR          -8029
/* index is corrupted, and index is created */
#define NGX_HTTP_TFS_EXIT_INDEX_CORRUPT_ERROR                 -8030
/* ds version error */
#define NGX_HTTP_TFS_EXIT_BLOCK_DS_VERSION_ERROR              -8031
/* ns version error */
#define NGX_HTTP_TFS_EXIT_BLOCK_NS_VERSION_ERROR              -8332
/* offset is out of physical block size */
#define NGX_HTTP_TFS_EXIT_PHYSIC_BLOCK_OFFSET_ERROR           -8033
/* file size is little than fileinfo */
#define NGX_HTTP_TFS_EXIT_READ_FILE_SIZE_ERROR                -8034
/* connect to ds fail */
#define NGX_HTTP_TFS_EXIT_DS_CONNECT_ERROR                    -8035
/* too much block checker */
#define NGX_HTTP_TFS_EXIT_BLOCK_CHECKER_OVERLOAD              -8036
/* fallocate is not implement */
#define NGX_HTTP_TFS_EXIT_FALLOCATE_NOT_IMPLEMENT             -8037
/* sync file failed */
#define NGX_HTTP_TFS_EXIT_SYNC_FILE_ERROR                     -8038

#define NGX_HTTP_TFS_EXIT_SESSION_EXIST_ERROR                 -9001
#define NGX_HTTP_TFS_EXIT_SESSIONID_INVALID_ERROR             -9002
#define NGX_HTTP_TFS_EXIT_APP_NOTEXIST_ERROR                  -9010
#define NGX_HTTP_TFS_EXIT_APPID_PERMISSION_DENY               -9011

#define NGX_HTTP_TFS_EXIT_SYSTEM_ERROR                        -10000
#define NGX_HTTP_TFS_EXIT_REGISTER_OPLOG_SYNC_ERROR           -12000
#define NGX_HTTP_TFS_EXIT_MAKEDIR_ERROR                       -13000

#define NGX_HTTP_TFS_EXIT_UNKNOWN_SQL_ERROR                   -14000
#define NGX_HTTP_TFS_EXIT_TARGET_EXIST_ERROR                  -14001
#define NGX_HTTP_TFS_EXIT_PARENT_EXIST_ERROR                  -14002
#define NGX_HTTP_TFS_EXIT_DELETE_DIR_WITH_FILE_ERROR          -14003
#define NGX_HTTP_TFS_EXIT_VERSION_CONFLICT_ERROR              -14004
#define NGX_HTTP_TFS_EXIT_NOT_CREATE_ERROR                    -14005
#define NGX_HTTP_TFS_EXIT_CLUSTER_ID_ERROR                    -14006
#define NGX_HTTP_TFS_EXIT_FRAG_META_OVERFLOW_ERROR            -14007
#define NGX_HTTP_TFS_EXIT_UPDATE_FRAG_INFO_ERROR              -14008
#define NGX_HTTP_TFS_EXIT_WRITE_EXIST_POS_ERROR               -14009
#define NGX_HTTP_TFS_EXIT_INVALID_FILE_NAME                   -14010
#define NGX_HTTP_TFS_EXIT_MOVE_TO_SUB_DIR_ERROR               -14011
#define NGX_HTTP_TFS_EXIT_OVER_MAX_SUB_DIRS_COUNT             -14012
#define NGX_HTTP_TFS_EXIT_OVER_MAX_SUB_DIRS_DEEP              -14013
#define NGX_HTTP_TFS_EXIT_OVER_MAX_SUB_FILES_COUNT            -14014

/* server register fail */
#define NGX_HTTP_TFS_EXIT_REGISTER_ERROR                      -15000
/* server register fail, server is existed */
#define NGX_HTTP_TFS_EXIT_REGISTER_EXIST_ERROR                -15001
/* renew lease fail, server is not existed */
#define NGX_HTTP_TFS_EXIT_REGISTER_NOT_EXIST_ERROR            -15002
/* table version error */
#define NGX_HTTP_TFS_EXIT_TABLE_VERSION_ERROR                 -15003
/* bucket id invalid */
#define NGX_HTTP_TFS_EXIT_BUCKET_ID_INVLAID                   -15004
/* bucket not exist */
#define NGX_HTTP_TFS_EXIT_BUCKET_NOT_EXIST                    -15005
/* new table not exist */
#define NGX_HTTP_TFS_EXIT_NEW_TABLE_NOT_EXIST                 -15005
/* new table invalid */
#define NGX_HTTP_TFS_EXIT_NEW_TABLE_INVALID                   -15005


#endif  /* _NGX_HTTP_TFS_ERRNO_H_INCLUDED_ */
