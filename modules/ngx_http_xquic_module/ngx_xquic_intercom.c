/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_xquic_intercom.h>
#define NGX_XQUIC_DISPATCH_RELOAD_TIME 300   // Max time the old worker may live after a reload (during reload window)


static ngx_int_t ngx_xquic_intercom_create_socket(ngx_xquic_intercom_ctx_t *ctx, const u_char *path);
static void ngx_xquic_intercom_recv_handler(ngx_event_t *rev);
static void ngx_xquic_reload_intercom_recv_handler(ngx_event_t *rev);
static uint64_t ngx_xquic_stat_send_cnt = 0;
static uint64_t ngx_xquic_stat_recv_cnt = 0;
static uint64_t ngx_xquic_stat_send_eagain_cnt = 0;

extern ngx_uint_t    ngx_xquic_reload_flag;
ngx_xquic_intercom_ctx_t *g_intercom_ctx = NULL; /* Packet dispatcher for cross-process and reload-time dispatching */

ngx_int_t
ngx_xquic_set_send_recv_buf_size(ngx_socket_t s, ngx_int_t send_buf_size, ngx_int_t recv_buf_size)
{
    if (setsockopt(s, SOL_SOCKET, SO_SNDBUF, &send_buf_size, sizeof(send_buf_size)) != 0) {
        return NGX_ERROR;
    }
    if (setsockopt(s, SOL_SOCKET, SO_RCVBUF, &recv_buf_size, sizeof(recv_buf_size)) != 0) {
        return NGX_ERROR;
    }
    return NGX_OK;
}

ngx_int_t
ngx_xquic_intercom_master_init_sock(ngx_cycle_t *cycle, ngx_socket_t *sock, const u_char *path)
{
    socklen_t                   addr_len;
    ngx_socket_t                s;
    struct sockaddr_un          addr;
    ngx_http_xquic_main_conf_t *qmcf;
    ngx_log_t                  *log = cycle->log;

    qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);

    unlink((const char *) path);

        
    s = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (s == (ngx_socket_t) -1) {
        ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
                      "|xquic|intercom create unix domain socket failed|");
        return NGX_ERROR;
    }
    
    if (ngx_xquic_set_send_recv_buf_size(s, qmcf->intercom_socket_sndbuf, 
                qmcf->intercom_socket_rcvbuf) != NGX_OK)
    {
        ngx_log_error(NGX_LOG_ERR, log, ngx_socket_errno, 
                      "|xquic|reload intercom fd set send recv buf size error|"
                      "snd_buf_size:%d, rcv_buf_size:%d , worker_id:%d|",
                      qmcf->intercom_socket_sndbuf, qmcf->intercom_socket_rcvbuf, ngx_worker);
        return NGX_ERROR;
    }

    ngx_memzero(&addr, sizeof(addr));

    addr.sun_family = AF_UNIX;
    ngx_memcpy(addr.sun_path, path, strlen((const char *) path));

    addr_len = strlen((const char *) path) + sizeof(addr.sun_family);

    if (ngx_nonblocking(s) == -1) {
        ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
                      "|xquic|intercom set nonblocking failed|");
        
        return NGX_ERROR;
    }

    if (bind(s, (struct sockaddr *) &addr, addr_len) == -1) {
        ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
                      "|xquic|intercom reload bind() to %s failed|", path);

        return NGX_ERROR;
    }

    *sock = s;
    return NGX_OK;

}

ngx_int_t
ngx_xquic_intercom_worker_init_addr(ngx_xquic_intercom_ctx_t *ctx, ngx_cycle_t *cycle)
{
    u_char                       path[4096] = { 0 };
    u_char                       reload_path[4096] = { 0 };
    ngx_core_conf_t             *ccf;
    ngx_http_xquic_main_conf_t  *qmcf;
    ngx_log_t                   *log = ctx->log;
    ngx_int_t                    i;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);
    qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);

    ngx_pool_t *pool = ctx->pool;
    if (pool == NULL) {
        ngx_log_error(NGX_LOG_EMERG, log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init: alloc addr failed|");
        return NGX_ERROR;
    }
    ctx->addr = ngx_pcalloc(pool, ccf->worker_processes * sizeof(struct sockaddr_un));
    if (ctx->addr == NULL) {
        ngx_log_error(NGX_LOG_EMERG, log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init: alloc addr failed|");
        return NGX_ERROR;
    }

    ctx->addrlen = ngx_pcalloc(pool, ccf->worker_processes * sizeof(ngx_int_t));
    if (ctx->addrlen == NULL) {
        ngx_log_error(NGX_LOG_EMERG, log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init: alloc addrlen failed|");
        return NGX_ERROR;
    }

    /* ngx_snprintf needs one reserved byte at the end to write the trailing NUL */
    *ngx_snprintf(path, sizeof(path) - 1, "%V", &qmcf->intercom_socket_path) = 0;
    
    if (ngx_create_full_path(path, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH)) {
        ngx_log_error(NGX_LOG_EMERG, log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init: failed to create path: %s|",
                      (char *) path);
        return NGX_ERROR;
    }
    for (i = 0; i < ccf->worker_processes; i++) {
        *ngx_snprintf(path, sizeof(path) - 1, "%V#%uD", &qmcf->intercom_socket_path, i) = 0;
       
        *ngx_snprintf(reload_path, sizeof(reload_path) - 1, "%V#%uD", 
                &qmcf->intercom_reload_socket_path, i) = 0;
  
        if ((ngx_uint_t) i == ngx_worker) {
            ctx->addr[i].sun_family = AF_UNIX;
            ngx_memcpy(ctx->addr[i].sun_path, reload_path, strlen((const char *)reload_path));
            ctx->addrlen[i] = strlen((const char *) reload_path) + sizeof(ctx->addr[i].sun_family);
        } else {

            ctx->addr[i].sun_family = AF_UNIX;
            ngx_memcpy(ctx->addr[i].sun_path, path, strlen((const char *)path));
            ctx->addrlen[i] = strlen((const char *) path) + sizeof(ctx->addr[i].sun_family);
        }
    }

    return NGX_OK;
}


ngx_int_t
ngx_xquic_intercom_worker_init_connection(ngx_xquic_intercom_ctx_t *ctx, ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t  *qmcf;
    ngx_connection_t            *c;
    ngx_socket_t                 s;
    ngx_log_t                   *log = ctx->log;
    ngx_event_t                 *rev;
    u_char                       path[4096] = { 0 };

    qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);

    /* Initialize the socket and connection of the dispatch queue */
    *ngx_snprintf(path, sizeof(path) - 1, "%V#%uD", &qmcf->intercom_socket_path, ngx_worker) = 0;
    
    if (ngx_xquic_intercom_create_socket(ctx, path) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init_connection init connection error|");
        return NGX_ERROR;
    }

    /* Initialize the connection of the reload queue */
    if (ctx->reload_sock == NULL) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init_connection reload_sock NULL|");
        return NGX_ERROR;
    }
    s = ctx->reload_sock[ngx_worker];
    if (s == 0) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init_connection reload_sock invalid:%d|", ngx_worker);
        return NGX_ERROR;
    }
    
    c = ngx_get_connection(s, log);
    if (c == NULL) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init_connection get connection NULL|");

        return NGX_ERROR;
    }
    /* The reload fd is owned by the master and reused across reloads,
     * so the worker only borrows the connection slot and must not close
     * the underlying fd on exit. */
    c->shared = 1;
    c->pool = ctx->pool;
    c->log = ctx->log;
    c->data = ctx;

    ctx->reload_conn = c;
    
    rev = c->read;
    rev->log = ctx->log;
    rev->data = c;
    /* The read callback is set here, but it is not added to read-event notifications;
       it is added only when the prereload signal is received. */
    rev->handler = ngx_xquic_reload_intercom_recv_handler; 

    return NGX_OK;
}

ngx_int_t
ngx_xquic_intercom_worker_init_ctx(ngx_cycle_t *cycle, void *engine)
{
    ngx_xquic_intercom_ctx_t    *ctx;
    ngx_core_conf_t             *ccf;
    ngx_listening_t             *ls, **lsp;
    ngx_uint_t                   i;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);

    /* Even when worker_processes = 1, the reload queue is still required, so g_intercom_ctx must be initialized */
    if (ccf->worker_processes < 1 || ngx_process != NGX_PROCESS_WORKER) {
        return NGX_OK;
    }

    ctx = g_intercom_ctx;
    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0, "|xquic|g_intercom_ctx NULL|");
        return NGX_OK;
    }
    ctx->log = cycle->log;
    ctx->xquic_engine = engine;
    if (ngx_xquic_intercom_worker_init_addr(ctx, cycle) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_worker_init_ctx init addr error|");
        return NGX_ERROR;
    } 

    if (ngx_xquic_intercom_worker_init_connection(ctx, cycle) != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0, 
                      "|xquic|ngx_xquic_intercom_worker_init_ctx init connection error|");
        return NGX_ERROR;
    }

    /* Initialize xquic_ls to speed up the lookup of the listen struct when sending packets */
    ls = (ngx_listening_t *) cycle->listening.elts;
    for (i = 0; i < cycle->listening.nelts; i++) {
        if (ls[i].reuseport && ls[i].xquic && ls[i].worker == ngx_worker) {
            ngx_log_error(NGX_LOG_DEBUG, cycle->log, 0, "|xquic|listening:%p|worker:%d|",
                          &ls[i], ls[i].worker);
            lsp = ngx_array_push(&ctx->xquic_ls);
            if (lsp == NULL) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                              "|xquic|ngx_xquic_intercom_worker_init_ctx xquic_ls push error|");
                return NGX_ERROR;
            }
            *lsp = &ls[i];  /* ngx_cycle is already initialized, so only the listen struct pointer needs to be stored */
        }
    }


    if (ngx_xquic_reload_flag) {
        /* reload_expire_time prevents the new worker from forwarding packets to the old worker's reload
           queue after the old worker has already exited */
        ctx->reload_expire_time = ngx_time() + NGX_XQUIC_DISPATCH_RELOAD_TIME;  
    }

    return NGX_OK;
}

ngx_int_t 
ngx_xquic_intercom_master_init_ctx(ngx_cycle_t *cycle)
{
    ngx_int_t                    i;
    ngx_pool_t                  *pool;
    ngx_xquic_intercom_ctx_t    *ctx;
    ngx_core_conf_t             *ccf;
    ngx_http_xquic_main_conf_t  *qmcf;
    u_char                       reload_path[4096] = { 0 };
 
    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);

    qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);
    if (qmcf == NULL) {
        ngx_log_error(NGX_LOG_WARN, cycle->log, 0, 
                      "|xquic|ngx_xquic_intercom_master_init_ctx: main conf is empty|");
        return NGX_ERROR;
    }

    pool = ngx_create_pool(qmcf->intercom_pool_size, cycle->log);
    if (pool == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_master_init: create pool size %d failed|",
                      qmcf->intercom_pool_size);
        return NGX_ERROR;
    }

    ctx = ngx_pcalloc(pool, sizeof(ngx_xquic_intercom_ctx_t));

    if (ctx == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_master_init alloc failed|");
        return NGX_ERROR;
    }

    ctx->pool = pool;
    ctx->worker_processes = ccf->worker_processes;

    if (ngx_array_init(&ctx->xquic_ls, pool, NGX_XQUIC_LISTENING_DEFAULT_NUM,
                sizeof(ngx_listening_t *)) != NGX_OK)
    {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                      "|xquic|ngx_xquic_intercom_master_init xquic_ls init error|");
        return NGX_ERROR;
    }


    *ngx_snprintf(reload_path, sizeof(reload_path) - 1, "%V", &qmcf->intercom_reload_socket_path) = 0;

    if (ngx_create_full_path(reload_path, S_IRWXU | S_IRWXG | S_IRWXO)) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_master_init_ctx: failed to create reload path: %s|", 
                      (char *) reload_path);
        return NGX_ERROR;
    }

    ctx->reload_sock = ngx_pcalloc(pool, ccf->worker_processes * sizeof(ngx_socket_t));
    if (ctx->reload_sock == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_master_init_ctx: failed to create reload socket");
        return NGX_ERROR;
    }
    i = 0;
    if (g_intercom_ctx) {
        if (ccf->worker_processes != g_intercom_ctx->worker_processes) {
            ngx_log_error(NGX_LOG_ERR, cycle->log, 0, 
                          "|xquic|reload worker_processes number error|before reload:%d, after reload:%d|",
                          g_intercom_ctx->worker_processes, ccf->worker_processes);
        }
        /*
         * Reuse the fds that can be reused.
         * If the number of worker_processes differs before and after reload, fd leakage may occur.
         * However, this is an exceptional situation; compared to fd leakage, the impact of broken
         * long-lived connections caused by a change in worker_processes is far greater.
         * Changing worker_processes between reloads should be avoided.
         */
        i = ngx_min(ccf->worker_processes, g_intercom_ctx->worker_processes);
        ngx_memcpy(ctx->reload_sock, g_intercom_ctx->reload_sock, i * sizeof(ngx_socket_t));
    }

    mode_t mode = (S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
    for (; i < ccf->worker_processes; i++) {
        *ngx_snprintf(reload_path, sizeof(reload_path) - 1, "%V#%uD", 
                &qmcf->intercom_reload_socket_path, i) = 0;

        if (ngx_xquic_intercom_master_init_sock(cycle, &ctx->reload_sock[i], reload_path)
                != NGX_OK) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                          "|xquic|ngx_xquic_intercom_master_init_ctx init sock error|");
            return NGX_ERROR;
        }
        /* The file associated with the local socket created in the master must be inherited by the worker,
           so the permissions and ownership need to be adjusted */
        if (chmod((const char *)reload_path, mode) == -1
            || chown((const char *)reload_path, ccf->user, -1) == -1)
        {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                          "|xquic|ngx_xquic_intercom_master_init_ctx chmod chown(\"%s\", %d) failed|",
                          reload_path, ccf->user);
            return NGX_ERROR;
        } 
    }

    if (g_intercom_ctx) {
        /* destroy old g_intercom_ctx */
        ngx_destroy_pool(g_intercom_ctx->pool);
    }
    g_intercom_ctx = ctx;
    return NGX_OK;
}


ngx_int_t
ngx_xquic_intercom_init(ngx_cycle_t *cycle, void *engine)
{
    u_char                       path[4096] = { 0 };
    ngx_int_t                    i;
    ngx_pool_t                  *pool;
    ngx_core_conf_t             *ccf;
    ngx_http_xquic_main_conf_t  *qmcf;
    ngx_xquic_intercom_ctx_t    *ctx;


    ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx, ngx_core_module);
 
    if (ccf->worker_processes <= 1 || ngx_process != NGX_PROCESS_WORKER) {
        return NGX_OK;
    }
    
    qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);

    pool = ngx_create_pool(qmcf->intercom_pool_size, cycle->log);
    if (pool == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_init: create pool size %d failed|",
                      qmcf->intercom_pool_size);
        return NGX_ERROR;
    }

    g_intercom_ctx = ngx_pcalloc(pool, sizeof(ngx_xquic_intercom_ctx_t));
    if (g_intercom_ctx == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "|xquic|ngx_xquic_intercom_init: create g_intercom_ctx failed|");
        return NGX_ERROR;
    }
    
    ctx = g_intercom_ctx;

    ctx->pool = pool;
    ctx->log = cycle->log;
    ctx->xquic_engine = engine;

    ctx->addr = ngx_pcalloc(pool, ccf->worker_processes * sizeof(struct sockaddr_un));
    if (ctx->addr == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "ngx_xquic_intercom_init: alloc addr failed");
        return NGX_ERROR;
    }

    ctx->addrlen = ngx_pcalloc(pool, ccf->worker_processes * sizeof(ngx_int_t));
    if (ctx->addrlen == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "ngx_xquic_intercom_init: alloc addrlen failed");
        return NGX_ERROR;
    }

    *ngx_snprintf(path, sizeof(path) - 1, "%V", &qmcf->intercom_socket_path) = 0;

    if (ngx_create_full_path(path, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH)) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "ngx_xquic_intercom_init: failed to create path: %s", (char *) path);

        return NGX_ERROR;
    }

    for (i = 0; i < ccf->worker_processes; i++) {
        *ngx_snprintf(path, sizeof(path) - 1, "%V#%uD", &qmcf->intercom_socket_path, i) = 0;

        if ((ngx_uint_t) i == ngx_worker) {
            if (ngx_xquic_intercom_create_socket(g_intercom_ctx, (const u_char *) path) != NGX_OK) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                              "|xquic|ngx_xquic_intercom_init: failed to create intercom socket|");

               
                return NGX_ERROR;
            }
        } else {
            ctx->addr[i].sun_family = AF_UNIX;
            ngx_memcpy(ctx->addr[i].sun_path, path, strlen((const char *)path));
            ctx->addrlen[i] = strlen((const char *) path) + sizeof(ctx->addr[i].sun_family);
        }
    }

        
    return NGX_OK;
}



void
ngx_xquic_intercom_exit()
{
    if (g_intercom_ctx) {
        if (g_intercom_ctx->connection) {
            ngx_close_connection(g_intercom_ctx->connection);
            g_intercom_ctx->connection = NULL;
        }
        if (g_intercom_ctx->reload_conn) {
            /* shared=1 keeps the master-owned fd open while releasing the slot */
            ngx_close_connection(g_intercom_ctx->reload_conn);
            g_intercom_ctx->reload_conn = NULL;
        }
        ngx_destroy_pool(g_intercom_ctx->pool);
        g_intercom_ctx = NULL;
    }
}

static ngx_int_t
ngx_xquic_intercom_init_socket(ngx_xquic_intercom_ctx_t *ctx, const char *path)
{
    socklen_t                   addr_len;
    ngx_socket_t                s;
    ngx_connection_t           *c;
    struct sockaddr_un          addr;
    ngx_int_t                   send_buf_size = 0, recv_buf_size = 0;
    socklen_t                   optlen = sizeof(ngx_int_t);
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);

    unlink((const char *) path);

    s = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (s == (ngx_socket_t) -1) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, ngx_socket_errno,
                      "|xquic|intercom create unix domain socket failed|");
        return NGX_ERROR;
    }

    if (getsockopt(s, SOL_SOCKET, SO_SNDBUF, &send_buf_size, &optlen) == 0) {
        ngx_log_debug2(NGX_LOG_DEBUG_CORE, ctx->log, 0,
                       "|xquic|intercom fd default send_buf_size:%d, worker_id:%d|",
                       send_buf_size, ngx_worker);
    } else {
        ngx_log_debug1(NGX_LOG_DEBUG_CORE, ctx->log, 0,
                       "|xquic|intercom fd get default send_buf_size error|worker_id:%d|",
                       ngx_worker);
    }

    if (getsockopt(s, SOL_SOCKET, SO_RCVBUF, &recv_buf_size, &optlen) == 0) {
        ngx_log_debug2(NGX_LOG_DEBUG_CORE, ctx->log, 0,
                       "|xquic|intercom fd default recv_buf_size:%d, worker_id:%d|",
                       recv_buf_size, ngx_worker);
 
    } else {
        ngx_log_debug1(NGX_LOG_DEBUG_CORE, ctx->log, 0,
                       "|xquic|intercom fd get default recv_buf_size error|worker_id:%d|",
                       ngx_worker);
    }
    

    if (ngx_xquic_set_send_recv_buf_size(s, qmcf->intercom_socket_sndbuf,
                qmcf->intercom_socket_rcvbuf) != NGX_OK)
    {
        ngx_log_error(NGX_LOG_ERR, ctx->log, ngx_socket_errno, 
                      "|xquic|intercom fd set send recv buf size error|"
                      "snd_buf_size:%d, rcv_buf_size:%d , worker_id:%d|",
                      qmcf->intercom_socket_sndbuf, qmcf->intercom_socket_rcvbuf, ngx_worker);
        return NGX_ERROR;
    }

    c = ngx_get_connection(s, ctx->log);
    if (c == NULL) {
        if (ngx_close_socket(s) == -1) {
            ngx_log_error(NGX_LOG_EMERG, ctx->log, ngx_socket_errno,
                          "|xquic|intercom close socket failed|");
        }

        return NGX_ERROR;
    }

    ngx_memzero(&addr, sizeof(addr));

    addr.sun_family = AF_UNIX;
    ngx_memcpy(addr.sun_path, path, strlen((const char *) path));

    addr_len = strlen((const char *) path) + sizeof(addr.sun_family);

    if (ngx_nonblocking(s) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, ngx_socket_errno,
                      "|xquic|intercom set nonblocking failed|");
        goto failed;
    }

    if (bind(s, (struct sockaddr *) &addr, addr_len) == -1) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, ngx_socket_errno,
                      "|xquic|intercom bind() to %s failed|", path);

        goto failed;
    }

    c->pool = ctx->pool;
    c->log = ctx->log;
    c->data = ctx;

    ctx->connection = c;
    
    return NGX_OK;
failed:
    if (c->pool) {
        ngx_destroy_pool(c->pool);
        c->pool = NULL;
    }
    ngx_close_connection(c);
    return NGX_ERROR;

}

static ngx_int_t
ngx_xquic_intercom_create_socket(ngx_xquic_intercom_ctx_t *ctx, const u_char *path)
{
    ngx_event_t         *rev;
    if (ngx_xquic_intercom_init_socket(ctx, (const char*)path) != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, 0,
                      "|xquic|g_intercom_ctx init socket failed|");
        return NGX_ERROR;
    } 
    rev = ctx->connection->read;
    rev->log = ctx->log;
    rev->data = ctx->connection;
    rev->handler = ngx_xquic_intercom_recv_handler;

    if (ngx_add_event(rev, NGX_READ_EVENT, 0) != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, ctx->log, 0,
                      "|xquic|intercom add read event failed|");
        return NGX_ERROR;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_CORE, ctx->log, 0,
                   "|xquic|intercom create socket %s|", path);

    return NGX_OK;
}

static void
ngx_xquic_intercom_recv_handler(ngx_event_t *rev)
{
    ngx_int_t                   n;
    ngx_err_t                   err;
    ngx_connection_t           *c;
    ngx_xquic_recv_packet_t     packet;
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);


    c = rev->data;

    for ( ;; ) {
        n = recv(c->fd, (void *) &packet, sizeof(ngx_xquic_recv_packet_t), 0);

        if (n < 0) {
            err = ngx_socket_errno;

            if (err == NGX_EAGAIN || err == NGX_EINTR) {
                ngx_log_debug0(NGX_LOG_DEBUG_EVENT, rev->log, 0,
                               "|xquic|ngx_quic_intercom_recv_handler: recv() not ready|");
            } else {
                ngx_log_error(NGX_LOG_ERR, rev->log, ngx_socket_errno,
                              "|xquic|ngx_quic_intercom_recv_handler: recv() failed|");
            }

            goto finish_recv;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_EVENT, rev->log, 0,
                       "|xquic|ngx_quic_intercom_recv_handler: worker %d recv connection_id %s packet|",
                       ngx_worker, xqc_dcid_str(qmcf->xquic_engine, &packet.xquic.dcid));

        if (n != sizeof(ngx_xquic_recv_packet_t)) {
            ngx_log_error(NGX_LOG_ERR, rev->log, ngx_socket_errno,
                          "|xquic|ngx_quic_intercom_recv_handler: worker %d recv connection_id %s packet error %d|",
                          ngx_worker, xqc_dcid_str(qmcf->xquic_engine, &packet.xquic.dcid), n);
        } else {
            ngx_xquic_stat_recv_cnt++;
            ngx_xquic_recv_from_intercom(&packet);
        }
    }

finish_recv:
    xqc_engine_finish_recv(qmcf->xquic_engine);
}

static void
ngx_xquic_reload_intercom_recv_handler(ngx_event_t *rev)
{
    ngx_int_t                   n;
    ngx_err_t                   err;
    ngx_connection_t           *c;
    ngx_xquic_recv_packet_t     packet;
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);
    
    c = rev->data;

    for ( ;; ) {
        n = recv(c->fd, (void *) &packet, sizeof(ngx_xquic_recv_packet_t), 0);

        if (n < 0) {
            err = ngx_socket_errno;

            if (err == NGX_EAGAIN || err == NGX_EINTR) {
                ngx_log_debug0(NGX_LOG_DEBUG_EVENT, rev->log, 0,
                               "|xquic|ngx_xquic_reload_intercom_recv_handler: recv() not ready|");
            } else {
                ngx_log_error(NGX_LOG_ERR, rev->log, ngx_socket_errno,
                              "|xquic|ngx_xquic_reload_intercom_recv_handler: recv() failed|");
            }

            goto finish_recv;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_EVENT, rev->log, 0,
                       "|xquic|ngx_xquic_reload_intercom_recv_handler: worker %d recv connection_id %s packet|",
                       ngx_worker, xqc_dcid_str(qmcf->xquic_engine, &packet.xquic.dcid));

        if (n != sizeof(ngx_xquic_recv_packet_t)) {
            ngx_log_error(NGX_LOG_ERR, rev->log, ngx_socket_errno,
                          "|xquic|ngx_xquic_reload_intercom_recv_handler: worker %d recv connection_id %s packet error %d|",
                          ngx_worker, xqc_dcid_str(qmcf->xquic_engine, &packet.xquic.dcid), n);
        } else {
            ngx_xquic_stat_recv_cnt++;
            ngx_xquic_recv_from_reload_intercom(&packet);
        }
    }

finish_recv:
    xqc_engine_finish_recv(qmcf->xquic_engine);
}

void 
ngx_xquic_add_reload_intercom_socket_event()
{
    ngx_event_t         *rev;
    if (g_intercom_ctx) {
        if (ngx_xquic_reload_flag && g_intercom_ctx->reload_expire_time > (ngx_uint_t)ngx_time()) {
            /* Two reloads too close together may affect the reload queue; emit a warning */
            ngx_log_error(NGX_LOG_ERR, g_intercom_ctx->log, 0,
                          "|xquic|reload interval too short|");
        } 
        if (g_intercom_ctx->reload_conn) {
            rev = g_intercom_ctx->reload_conn->read;
            if (rev) {
                if (ngx_add_event(rev, NGX_READ_EVENT, 0) != NGX_OK) {
                    ngx_log_error(NGX_LOG_EMERG, g_intercom_ctx->log, 0,
                                  "|xquic|add reload intercom event read error|");
                }
            }
        }
    }
}


void
ngx_xquic_intercom_send(ngx_int_t worker_num, ngx_xquic_recv_packet_t *packet,
    ngx_xquic_intercom_ctx_t *ctx)
{
    ngx_int_t           n;
    ngx_err_t           err;
    ngx_connection_t   *c;
#if (NGX_DEBUG)
    ngx_http_xquic_main_conf_t *qmcf;

    qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);
#endif
    c = ctx->connection;

    n = sendto(c->fd, packet, sizeof(ngx_xquic_recv_packet_t), 0,
               &ctx->addr[worker_num], ctx->addrlen[worker_num]);

    ngx_xquic_stat_send_cnt++;

    ngx_log_debug6(NGX_LOG_DEBUG_EVENT, ctx->log, 0,
                   "|xquic|intercom_send: worker %d -> %d send connection_id %s packet, "
                   "recv(%ul), send(%ul), eagain(%ul)|",
                   ngx_worker, worker_num, xqc_dcid_str(qmcf->xquic_engine, &packet->xquic.dcid),
                   ngx_xquic_stat_recv_cnt, ngx_xquic_stat_send_cnt, ngx_xquic_stat_send_eagain_cnt);

    if (n < 0) {
        err = ngx_socket_errno;

        if (err == NGX_EAGAIN || err == NGX_EINTR) {
            ngx_xquic_stat_send_eagain_cnt++;
            if (ngx_xquic_stat_send_eagain_cnt % 100 == 1) {
                ngx_log_error(NGX_LOG_ERR, ctx->log, ngx_socket_errno,
                             "|xquic|ngx_xquic_intercom_send: worker %d -> %d send packet error, "
                             "recv(%ul), send(%ul), eagain(%ul)|",
                             ngx_worker, worker_num,
                             ngx_xquic_stat_recv_cnt, ngx_xquic_stat_send_cnt, ngx_xquic_stat_send_eagain_cnt);
            }
        } else {
            ngx_log_error(NGX_LOG_ERR, ctx->log, ngx_socket_errno,
                          "|xquic|ngx_xquic_intercom_send: worker %d -> %d send connection_id %ul packet error|",
                          ngx_worker, worker_num, packet->xquic.connection_id);
        }

        return;
    }

    if (n != sizeof(ngx_xquic_recv_packet_t)) {
        ngx_log_error(NGX_LOG_ERR, ctx->log, ngx_socket_errno,
                      "|xquic|ngx_xquic_intercom_send: worker %d -> %d send connection_id %ul packet uncomplete(%d != %d)|",
                      ngx_worker, worker_num, packet->xquic.connection_id, n, sizeof(ngx_xquic_recv_packet_t));
    }
}


ngx_int_t
ngx_xquic_intercom_packet_hash(ngx_xquic_recv_packet_t *packet)
{
    ngx_core_conf_t *ccf;
    ngx_int_t target_worker;

    if (g_intercom_ctx == NULL) {
        return ngx_worker;
    }

#if (NGX_XQUIC_SUPPORT_CID_ROUTE)
    if (ngx_xquic_is_cid_route_on((ngx_cycle_t *)ngx_cycle)) {
        return ngx_xquic_get_target_worker_from_cid(packet);
    }
#endif

    ccf = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx, ngx_core_module);
    target_worker = ngx_murmur_hash2(packet->xquic.dcid.cid_buf, packet->xquic.dcid.cid_len)
                                                % ccf->worker_processes;


    return target_worker;
}

