
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_http_tfs_peer_connection.h>
#include <ngx_http_tfs_server_handler.h>
#include <ngx_http_tfs_errno.h>


static ngx_str_t rcs_name = ngx_string("rc server");
static ngx_str_t ns_name = ngx_string("name server");
static ngx_str_t ds_name = ngx_string("data server");
static ngx_str_t rs_name = ngx_string("root server");
static ngx_str_t ms_name = ngx_string("meta server");


ngx_int_t
ngx_http_tfs_peer_init(ngx_http_tfs_t *t)
{
    char                            *addr;
    uint16_t                         port;
    ngx_http_connection_pool_t      *conn_pool;
    ngx_http_tfs_peer_connection_t  *rc_server, *name_server, *root_server,
                                    *meta_server, *data_server;

    conn_pool = t->main_conf->conn_pool;

    t->tfs_peer_servers = ngx_pcalloc(t->pool,
        sizeof(ngx_http_tfs_peer_connection_t) * NGX_HTTP_TFS_SERVER_COUNT);
    if (t->tfs_peer_servers == NULL) {
        return NGX_ERROR;
    }

    name_server = &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER];
    data_server = &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];
    root_server = &t->tfs_peer_servers[NGX_HTTP_TFS_ROOT_SERVER];
    meta_server = &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER];

    /* rc server */
    if (t->loc_conf->upstream->enable_rcs) {
        rc_server = &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];
        rc_server->peer.sockaddr = t->loc_conf->upstream->ups_addr->sockaddr;
        rc_server->peer.socklen = t->loc_conf->upstream->ups_addr->socklen;
        rc_server->peer.log = t->log;
        rc_server->peer.name = &rcs_name;
        rc_server->peer.data = conn_pool;
        rc_server->peer.get = conn_pool->get_peer;
        rc_server->peer.free = conn_pool->free_peer;
        rc_server->peer.log_error = NGX_ERROR_ERR;
        addr = inet_ntoa(((struct sockaddr_in*)
                          (rc_server->peer.sockaddr))->sin_addr);
        port = ntohs(((struct sockaddr_in*)
                      (rc_server->peer.sockaddr))->sin_port);
        ngx_sprintf(rc_server->peer_addr_text, "%s:%d", addr, port);

    } else {
        name_server->peer.sockaddr = t->loc_conf->upstream->ups_addr->sockaddr;
        name_server->peer.socklen = t->loc_conf->upstream->ups_addr->socklen;
        addr = inet_ntoa(((struct sockaddr_in*)
                          (name_server->peer.sockaddr))->sin_addr);
        port = ntohs(((struct sockaddr_in*)
                      (name_server->peer.sockaddr))->sin_port);
        ngx_sprintf(name_server->peer_addr_text, "%s:%d", addr, port);
    }

    /* name server */
    name_server->peer.log = t->log;
    name_server->peer.name = &ns_name;
    name_server->peer.data = conn_pool;
    name_server->peer.get = conn_pool->get_peer;
    name_server->peer.free = conn_pool->free_peer;
    name_server->peer.log_error = NGX_ERROR_ERR;

    /* data server */
    data_server->peer.log = t->log;
    data_server->peer.name = &ds_name;
    data_server->peer.data = conn_pool;
    data_server->peer.get = conn_pool->get_peer;
    data_server->peer.free = conn_pool->free_peer;
    data_server->peer.log_error = NGX_ERROR_ERR;

    if (t->r_ctx.version == 1) {
        t->tfs_peer_count = 3;

    } else {
        /* root server */
        root_server->peer.log = t->log;
        root_server->peer.name = &rs_name;
        root_server->peer.data = conn_pool;
        root_server->peer.get = conn_pool->get_peer;
        root_server->peer.free = conn_pool->free_peer;
        root_server->peer.log_error = NGX_ERROR_ERR;

        /* meta server */
        meta_server->peer.log = t->log;
        meta_server->peer.name = &ms_name;
        meta_server->peer.data = conn_pool;
        meta_server->peer.get = conn_pool->get_peer;
        meta_server->peer.free = conn_pool->free_peer;
        meta_server->peer.log_error = NGX_ERROR_ERR;

        t->tfs_peer_count = 5;
    }

    return NGX_OK;
}


static ngx_http_tfs_peer_connection_t *
ngx_http_tfs_select_peer_v1(ngx_http_tfs_t *t)
{
    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_START:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            t->input_filter = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_COUNT:
        case NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_SEQ:
        case NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO:
            t->create_request = ngx_http_tfs_create_ns_request;
            t->process_request_body = ngx_http_tfs_process_ns;
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_STAT_FILE:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds;
            t->input_filter = NULL;
            t->retry_handler = ngx_http_tfs_retry_ds;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_READ_META_SEGMENT:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds_read;
            t->input_filter = ngx_http_tfs_process_ds_input_filter;
            t->retry_handler = ngx_http_tfs_retry_ds;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds;
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_DONE:
            return t->tfs_peer;

        default:
            return NULL;
        }
        break;
    case NGX_HTTP_TFS_ACTION_READ_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_READ_START:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            t->input_filter = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

        case NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO:
            t->create_request = ngx_http_tfs_create_ns_request;
            t->process_request_body = ngx_http_tfs_process_ns;
            t->input_filter = NULL;
            t->retry_handler = ngx_http_tfs_retry_ns;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER];

        case NGX_HTTP_TFS_STATE_READ_READ_DATA:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds_read;
            t->input_filter = ngx_http_tfs_process_ds_input_filter;
            t->retry_handler = ngx_http_tfs_retry_ds;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        case NGX_HTTP_TFS_STATE_READ_DONE:
            t->input_filter = NULL;
            return t->tfs_peer;

        default:
            return NULL;
        }
        break;
    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_START:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            t->input_filter = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

        case NGX_HTTP_TFS_STATE_WRITE_GET_GROUP_COUNT:
        case NGX_HTTP_TFS_STATE_WRITE_GET_GROUP_SEQ:
        case NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS:
        case NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO:
            t->create_request = ngx_http_tfs_create_ns_request;
            t->process_request_body = ngx_http_tfs_process_ns;
            t->input_filter = NULL;
            t->retry_handler = ngx_http_tfs_retry_ns;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER];

        case NGX_HTTP_TFS_STATE_WRITE_STAT_DUP_FILE:
        case NGX_HTTP_TFS_STATE_WRITE_CREATE_FILE_NAME:
        case NGX_HTTP_TFS_STATE_WRITE_WRITE_DATA:
        case NGX_HTTP_TFS_STATE_WRITE_CLOSE_FILE:
        case NGX_HTTP_TFS_STATE_WRITE_DELETE_DATA:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds;
            t->input_filter = NULL;
            t->retry_handler = ngx_http_tfs_retry_ds;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        case NGX_HTTP_TFS_STATE_WRITE_DONE:
            t->input_filter = NULL;
            return t->tfs_peer;
        default:
            return NULL;
        }
        break;
    case NGX_HTTP_TFS_ACTION_STAT_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_STAT_START:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            t->input_filter = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

        case NGX_HTTP_TFS_STATE_STAT_GET_BLK_INFO:
            t->create_request = ngx_http_tfs_create_ns_request;
            t->process_request_body = ngx_http_tfs_process_ns;
            t->input_filter = NULL;
            t->retry_handler = ngx_http_tfs_retry_ns;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER];

        case NGX_HTTP_TFS_STATE_STAT_STAT_FILE:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds;
            t->input_filter = NULL;
            t->retry_handler = ngx_http_tfs_retry_ds;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        default:
            return NULL;
        }
        break;

    case NGX_HTTP_TFS_ACTION_KEEPALIVE:
        t->create_request = ngx_http_tfs_create_rcs_request;
        t->process_request_body = ngx_http_tfs_process_rcs;
        t->input_filter = NULL;
        return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

    default:
        break;
    }

    return NULL;
}


static ngx_http_tfs_peer_connection_t *
ngx_http_tfs_select_peer_v2(ngx_http_tfs_t *t)
{
    switch (t->r_ctx.action.code) {
    case NGX_HTTP_TFS_ACTION_GET_APPID:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

    case NGX_HTTP_TFS_ACTION_REMOVE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_REMOVE_START:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_GET_META_TABLE:
            t->create_request = ngx_http_tfs_create_rs_request;
            t->process_request_body = ngx_http_tfs_process_rs;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_ROOT_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_NOTIFY_MS:
        case NGX_HTTP_TFS_STATE_REMOVE_GET_FRAG_INFO:
            t->create_request = ngx_http_tfs_create_ms_request;
            t->process_request_body = ngx_http_tfs_process_ms;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_COUNT:
        case NGX_HTTP_TFS_STATE_REMOVE_GET_GROUP_SEQ:
        case NGX_HTTP_TFS_STATE_REMOVE_GET_BLK_INFO:
            t->create_request = ngx_http_tfs_create_ns_request;
            t->process_request_body = ngx_http_tfs_process_ns;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_DELETE_DATA:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        case NGX_HTTP_TFS_STATE_REMOVE_DONE:
            return t->tfs_peer;
        default:
            return NULL;
        }
        break;
    case NGX_HTTP_TFS_ACTION_READ_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_READ_START:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

        case NGX_HTTP_TFS_STATE_READ_GET_META_TABLE:
            t->create_request = ngx_http_tfs_create_rs_request;
            t->process_request_body = ngx_http_tfs_process_rs;
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_ROOT_SERVER];

        case NGX_HTTP_TFS_STATE_READ_GET_FRAG_INFO:
            t->create_request = ngx_http_tfs_create_ms_request;
            t->process_request_body = ngx_http_tfs_process_ms;
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER];

        case NGX_HTTP_TFS_STATE_READ_GET_BLK_INFO:
            t->create_request = ngx_http_tfs_create_ns_request;
            t->process_request_body = ngx_http_tfs_process_ns;
            t->input_filter = NULL;
            t->retry_handler = ngx_http_tfs_retry_ns;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER];

        case NGX_HTTP_TFS_STATE_READ_READ_DATA:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds_read;
            t->input_filter = ngx_http_tfs_process_ds_input_filter;
            t->retry_handler = ngx_http_tfs_retry_ds;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        case NGX_HTTP_TFS_STATE_READ_DONE:
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return t->tfs_peer;
        default:
            return NULL;
        }
        break;
    case NGX_HTTP_TFS_ACTION_WRITE_FILE:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_WRITE_START:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

        case NGX_HTTP_TFS_STATE_WRITE_GET_META_TABLE:
            t->create_request = ngx_http_tfs_create_rs_request;
            t->process_request_body = ngx_http_tfs_process_rs;
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_ROOT_SERVER];

        case NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_MS:
        case NGX_HTTP_TFS_STATE_WRITE_WRITE_MS:
            t->create_request = ngx_http_tfs_create_ms_request;
            t->process_request_body = ngx_http_tfs_process_ms;
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER];

        case NGX_HTTP_TFS_STATE_WRITE_CLUSTER_ID_NS:
        case NGX_HTTP_TFS_STATE_WRITE_GET_BLK_INFO:
            t->create_request = ngx_http_tfs_create_ns_request;
            t->process_request_body = ngx_http_tfs_process_ns;
            t->input_filter = NULL;
            t->retry_handler = ngx_http_tfs_retry_ns;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER];

        case NGX_HTTP_TFS_STATE_WRITE_CREATE_FILE_NAME:
        case NGX_HTTP_TFS_STATE_WRITE_WRITE_DATA:
        case NGX_HTTP_TFS_STATE_WRITE_CLOSE_FILE:
            t->create_request = ngx_http_tfs_create_ds_request;
            t->process_request_body = ngx_http_tfs_process_ds;
            t->input_filter = NULL;
            /* FIXME: it's better to retry_ns instead of ds when write failed */
            t->retry_handler = ngx_http_tfs_retry_ds;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER];

        case NGX_HTTP_TFS_STATE_WRITE_DONE:
            t->input_filter = NULL;
            t->retry_handler = NULL;
            return t->tfs_peer;
        default:
            return NULL;
        }
        break;
    case NGX_HTTP_TFS_ACTION_CREATE_FILE:
    case NGX_HTTP_TFS_ACTION_CREATE_DIR:
    case NGX_HTTP_TFS_ACTION_LS_FILE:
    case NGX_HTTP_TFS_ACTION_LS_DIR:
    case NGX_HTTP_TFS_ACTION_MOVE_DIR:
    case NGX_HTTP_TFS_ACTION_MOVE_FILE:
    case NGX_HTTP_TFS_ACTION_REMOVE_DIR:
        switch (t->state) {
        case NGX_HTTP_TFS_STATE_ACTION_START:
            t->create_request = ngx_http_tfs_create_rcs_request;
            t->process_request_body = ngx_http_tfs_process_rcs;
            t->input_filter = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_RC_SERVER];

        case NGX_HTTP_TFS_STATE_ACTION_GET_META_TABLE:
            t->create_request = ngx_http_tfs_create_rs_request;
            t->process_request_body = ngx_http_tfs_process_rs;
            t->input_filter = NULL;
            return &t->tfs_peer_servers[NGX_HTTP_TFS_ROOT_SERVER];

        case NGX_HTTP_TFS_STATE_ACTION_PROCESS:
            t->create_request = ngx_http_tfs_create_ms_request;
            if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_LS_DIR) {
                t->process_request_body = ngx_http_tfs_process_ms_ls_dir;
                t->input_filter = ngx_http_tfs_process_ms_input_filter;
            } else {
                t->process_request_body = ngx_http_tfs_process_ms;
                t->input_filter = NULL;
            }
            return &t->tfs_peer_servers[NGX_HTTP_TFS_META_SERVER];

        case NGX_HTTP_TFS_STATE_ACTION_DONE:
            t->input_filter = NULL;
            return t->tfs_peer;
        default:
            return NULL;
        }
        break;
    default:
        break;
    }

    return NULL;
}


ngx_http_tfs_peer_connection_t *
ngx_http_tfs_select_peer(ngx_http_tfs_t *t)
{
    if (t->r_ctx.version == 1) {
        return ngx_http_tfs_select_peer_v1(t);
    }

    if (t->r_ctx.version == 2) {
        return ngx_http_tfs_select_peer_v2(t);
    }

    return NULL;
}

