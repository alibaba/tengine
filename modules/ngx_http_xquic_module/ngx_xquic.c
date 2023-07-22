/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

/**
 * for engine and socket operation
 */

#include <ngx_xquic.h>
#include <ngx_http_xquic_module.h>
#include <ngx_http_xquic.h>
#include <ngx_xquic_intercom.h>
#include <ngx_xquic_recv.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <xquic/xquic_typedef.h>
#include <xquic/xquic.h>

#define NGX_XQUIC_TMP_BUF_LEN 512
#define NGX_XQUIC_SUPPORT_CID_ROUTE 1
#if (T_NGX_UDPV2)
static void ngx_xquic_batch_udp_traffic(ngx_event_t * ev);
#endif


xqc_engine_callback_t ngx_xquic_engine_callback = {

#if (NGX_XQUIC_SUPPORT_CID_ROUTE)
    .cid_generate_cb = ngx_xquic_cid_generate_cb,
#endif

    .set_event_timer = ngx_xquic_engine_set_event_timer,
    .log_callbacks = {
        .xqc_log_write_err = ngx_xquic_log_write_err,
        .xqc_log_write_stat = ngx_xquic_log_write_stat,
    },
};

xqc_transport_callbacks_t ngx_xquic_transport_callbacks = {

    .server_accept = ngx_xquic_conn_accept,
    .server_refuse = ngx_xquic_conn_refuse,
    .write_socket = ngx_xquic_server_send,
#if defined(T_NGX_XQUIC_SUPPORT_SENDMMSG)
    .write_mmsg  = ngx_xquic_server_send_mmsg,
#endif
    .conn_update_cid_notify = ngx_http_v3_conn_update_cid_notify,
    .conn_cert_cb = ngx_http_v3_cert_cb,
};


uint64_t 
ngx_xquic_get_time()
{
    /* take the time in microseconds */
    struct timeval tv;
    gettimeofday(&tv, NULL);
    uint64_t ul = tv.tv_sec * 1000000 + tv.tv_usec;
    return  ul;
}


/* TODO: close file */
ngx_int_t 
ngx_xquic_read_file_data( char * data, size_t data_len, char *filename)
{
    FILE * fp = fopen(filename, "rb");

    if(fp == NULL){
        return -1;
    }
    fseek(fp, 0 , SEEK_END);
    size_t total_len  = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    if(total_len > data_len){
        return -1;
    }

    size_t read_len = fread(data, 1, total_len, fp);
    if (read_len != total_len){

        return -1;
    }

    return read_len;
}


/* run main logic */
void 
ngx_xquic_engine_timer_callback(ngx_event_t *ev)
{
    xqc_engine_t * engine = (xqc_engine_t *)(ev->data);

    xqc_engine_main_logic(engine);
    return;
}


void 
ngx_xquic_engine_init_event_timer(ngx_http_xquic_main_conf_t *qmcf, xqc_engine_t *engine)
{
    ngx_event_t *ev = &(qmcf->engine_ev_timer);
    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0, 
                    "|xquic|ngx_xquic_init_event_timer|%p|", engine);  

    ngx_memzero(ev, sizeof(ngx_event_t));
    ev->handler = ngx_xquic_engine_timer_callback;
    ev->log = ngx_cycle->log;
    ev->data = engine;

#if (T_NGX_UDPV2)
    ngx_memcpy(&qmcf->udpv2_batch, ev, sizeof(*ev));
    qmcf->udpv2_batch.handler = ngx_xquic_batch_udp_traffic;
#endif
}


void 
ngx_xquic_engine_set_event_timer(xqc_msec_t wake_after, void *engine_user_data)
{
    ngx_http_xquic_main_conf_t *qmcf = (ngx_http_xquic_main_conf_t *)engine_user_data;
    ngx_msec_t wake_after_ms = wake_after / 1000;

    if(wake_after_ms == 0){
        wake_after_ms = 1; //most event timer interval 1
    }

    if (qmcf->engine_ev_timer.timer_set){
        ngx_del_timer(&(qmcf->engine_ev_timer));
    }

    ngx_add_timer(&(qmcf->engine_ev_timer), wake_after_ms);
}


ngx_int_t
ngx_xquic_engine_init_alpn_ctx(ngx_cycle_t *cycle, xqc_engine_t *engine)
{
    ngx_int_t ret = NGX_OK;

    xqc_h3_callbacks_t h3_cbs = {
        .h3c_cbs = {
            .h3_conn_create_notify = ngx_http_v3_conn_create_notify,
            .h3_conn_close_notify = ngx_http_v3_conn_close_notify,
            .h3_conn_handshake_finished = ngx_http_v3_conn_handshake_finished,
        },
        .h3r_cbs = {
            .h3_request_write_notify = ngx_http_v3_request_write_notify,
            .h3_request_read_notify = ngx_http_v3_request_read_notify,
            .h3_request_create_notify = ngx_http_v3_request_create_notify,
            .h3_request_close_notify = ngx_http_v3_request_close_notify,
        }
    };

    /* init http3 context */
    ret = xqc_h3_ctx_init(engine, &h3_cbs);
    if (ret != XQC_OK) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, "init h3 context error, ret: %d\n", ret);
        return ret;
    }

    return ret;
}

ngx_int_t
ngx_xquic_engine_init(ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);
    xqc_engine_ssl_config_t *engine_ssl_config = NULL;
    xqc_config_t config;

    if (xqc_engine_get_default_config(&config, XQC_ENGINE_SERVER) < 0) {
        return NGX_ERROR;
    }

    if (qmcf->stateless_reset_token_key.len > 0
        && qmcf->stateless_reset_token_key.len <= XQC_RESET_TOKEN_MAX_KEY_LEN)
    {
        strncpy(config.reset_token_key, (char *)qmcf->stateless_reset_token_key.data, XQC_RESET_TOKEN_MAX_KEY_LEN);
        config.reset_token_keylen = qmcf->stateless_reset_token_key.len;
    }

    if (qmcf == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                    "|xquic|ngx_xquic_engine_init: get main conf fail|");
        return NGX_ERROR;
    }

    if (qmcf->xquic_engine != NULL) {
        return NGX_OK;
    }

    /* enable cid negotiate */
#if (NGX_XQUIC_SUPPORT_CID_ROUTE)
    if (ngx_xquic_is_cid_route_on(cycle)) {
        config.cid_negotiate = 1;
        config.cid_len       = qmcf->cid_len;
        /* using time and pid as the seed for a new sequence of pseudo-random integer */
        srandom(time(NULL) + getpid());
    }
#endif

    /* init log level */
    config.cfg_log_level = qmcf->log_level;
    config.cfg_log_timestamp = 0;

#if defined(T_NGX_XQUIC_SUPPORT_SENDMMSG)
    /* set sendmmsg */
    config.sendmmsg_on = 1;
#endif

    /* init ssl config */
    engine_ssl_config = &(qmcf->engine_ssl_config);

    if (qmcf->certificate.len == 0 || qmcf->certificate.data == NULL
        || qmcf->certificate_key.len == 0 || qmcf->certificate_key.data == NULL)
    {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                    "|xquic|ngx_xquic_engine_init: null certificate or key|");     
        return NGX_ERROR;
    }

    /* copy cert key */
    engine_ssl_config->private_key_file = ngx_pcalloc(cycle->pool, qmcf->certificate_key.len + 1);
    if (engine_ssl_config->private_key_file == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                    "|xquic|ngx_xquic_engine_init: fail to alloc memory|");     
        return NGX_ERROR;
    }
    ngx_memcpy(engine_ssl_config->private_key_file, qmcf->certificate_key.data, qmcf->certificate_key.len);

    /* copy cert */
    engine_ssl_config->cert_file = ngx_pcalloc(cycle->pool, qmcf->certificate.len + 1);
    if (engine_ssl_config->cert_file == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                    "|xquic|ngx_xquic_engine_init: fail to alloc memory|");     
        return NGX_ERROR;
    }
    ngx_memcpy(engine_ssl_config->cert_file, qmcf->certificate.data, qmcf->certificate.len);

    engine_ssl_config->ciphers = XQC_TLS_CIPHERS;
    engine_ssl_config->groups = XQC_TLS_GROUPS;

    /* copy session ticket */
    char g_ticket_file[NGX_XQUIC_TMP_BUF_LEN]={0};
    char g_session_ticket_key[NGX_XQUIC_TMP_BUF_LEN];    
    if (qmcf->session_ticket_key.data != NULL 
        && qmcf->session_ticket_key.len != 0
        && qmcf->session_ticket_key.len < NGX_XQUIC_TMP_BUF_LEN) 
    {
        ngx_memcpy(g_ticket_file, qmcf->session_ticket_key.data, qmcf->session_ticket_key.len);

        int ticket_key_len  = ngx_xquic_read_file_data(g_session_ticket_key, 
                                                       sizeof(g_session_ticket_key), 
                                                       g_ticket_file);

        ngx_log_error(NGX_LOG_DEBUG, cycle->log, 0, 
                      "|xquic|ngx_xquic_engine_init: ticket_key_len=%i|", ticket_key_len); 

        if(ticket_key_len < 0){
            engine_ssl_config->session_ticket_key_data = NULL;
            engine_ssl_config->session_ticket_key_len = 0;
        } else {
            engine_ssl_config->session_ticket_key_data = ngx_pcalloc(cycle->pool, (size_t)ticket_key_len);
            if (engine_ssl_config->session_ticket_key_data == NULL) {
                ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                            "|xquic|ngx_xquic_engine_init: fail to alloc memory|");     
                return NGX_ERROR;
            }
            engine_ssl_config->session_ticket_key_len = ticket_key_len;
            ngx_memcpy(engine_ssl_config->session_ticket_key_data, g_session_ticket_key, ticket_key_len);
        }
    }

    /* create engine */
    qmcf->xquic_engine = xqc_engine_create(XQC_ENGINE_SERVER, &config, engine_ssl_config, 
                                           &ngx_xquic_engine_callback, &ngx_xquic_transport_callbacks, qmcf);
    if (qmcf->xquic_engine == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                    "|xquic|xqc_engine_create: fail|");
        return NGX_ERROR;
    }

    /* init http3 alpn context */
    if (ngx_xquic_engine_init_alpn_ctx(cycle, qmcf->xquic_engine) != NGX_OK) {
        return NGX_ERROR;
    }

    /* set congestion control */
    xqc_cong_ctrl_callback_t cong_ctrl;
    if (qmcf->congestion_control.len == sizeof("bbr")-1
        && ngx_strncmp(qmcf->congestion_control.data, "bbr", sizeof("bbr")-1) == 0) 
    {
        cong_ctrl = xqc_bbr_cb;
    } else if (qmcf->congestion_control.len == sizeof("reno")-1
        && ngx_strncmp(qmcf->congestion_control.data, "reno", sizeof("reno")-1) == 0) 
    {
        cong_ctrl = xqc_reno_cb;
    } else if (qmcf->congestion_control.len == sizeof("cubic")-1
        && ngx_strncmp(qmcf->congestion_control.data, "cubic", sizeof("cubic")-1) == 0) 
    {
        cong_ctrl = xqc_cubic_cb;
    } else {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                    "|xquic|unknown xquic_congestion_control|%V|", &qmcf->congestion_control);     
        return NGX_ERROR;
    }

    int pacing_on = (qmcf->pacing_on? 1 : 0);

    xqc_conn_settings_t conn_settings = {
        .pacing_on  =   pacing_on,
        .cong_ctrl_callback = cong_ctrl,
    };

    if (qmcf->anti_amplification_limit != NGX_CONF_UNSET_UINT) {
        conn_settings.anti_amplification_limit = qmcf->anti_amplification_limit;
    }

    if (qmcf->keyupdate_pkt_threshold != NGX_CONF_UNSET_UINT) {
        conn_settings.keyupdate_pkt_threshold = qmcf->keyupdate_pkt_threshold;
    }

    xqc_server_set_conn_settings(&conn_settings);

    xqc_h3_engine_set_enc_max_dtable_capacity(qmcf->xquic_engine, 
                                        qmcf->qpack_encoder_dynamic_table_capacity);
    xqc_h3_engine_set_dec_max_dtable_capacity(qmcf->xquic_engine, 
                                        qmcf->qpack_decoder_dynamic_table_capacity);


    /* init event timer */
    ngx_xquic_engine_init_event_timer(qmcf, qmcf->xquic_engine);

    ngx_log_error(NGX_LOG_DEBUG, cycle->log, 0, 
                "|xquic|xquic_engine|%p|", qmcf->xquic_engine);  


    return NGX_OK;
}

#if (T_NGX_UDPV2)

static void
ngx_xquic_batch_udp_traffic(ngx_event_t * ev)
{
    xqc_engine_t *xquic_engine;
    xquic_engine = (xqc_engine_t *)(ev->data);
    xqc_engine_finish_recv(xquic_engine);
    ngx_accept_disabled = ngx_cycle->connection_n / 8
                              - ngx_cycle->free_connection_n;
}

static ngx_udpv2_traffic_filter_retcode
ngx_xquic_udp_accept_filter(ngx_listening_t *ls, const ngx_udpv2_packet_t *upkt){

    ngx_connection_t *lc;
    ngx_http_xquic_main_conf_t *qmcf;

    lc      = ls->connection ;
    qmcf    = (ngx_http_xquic_main_conf_t *)(lc->data);

    // feed to xquic
    ngx_xquic_dispatcher_process(lc, upkt);
    // posted udpv2 event 
    ngx_post_event(&qmcf->udpv2_batch, &ngx_udpv2_posted_event);

    return NGX_UDPV2_DONE;
}
#endif

ngx_int_t
ngx_xquic_process_init(ngx_cycle_t *cycle)
{
    int                          with_xquic = 0;
    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);


    ngx_log_debug0(NGX_LOG_DEBUG_CORE, cycle->log, 0, "|xquic|ngx_xquic_process_init|");

    /* socket init */
    ngx_event_t       *rev;
    ngx_listening_t   *ls;
    ngx_connection_t  *c;
    unsigned int       i;

    ls = (ngx_listening_t *)(cycle->listening.elts);
    for (i = 0; i < cycle->listening.nelts; i++) {

#if !(T_RELOAD)
#if (NGX_HAVE_REUSEPORT)
        if (ls[i].reuseport && ls[i].worker != ngx_worker) {
            continue;
        }
#endif
#endif

        if (ls[i].fd == -1) {
            continue;
        }

        if (!ls[i].xquic) {
            continue;
        }

        with_xquic = 1;

        c = ls[i].connection;
        rev = c->read;

#if (T_NGX_UDPV2)
        /* outofband */
        if (ls[i].support_udpv2) {
            ngx_udpv2_reset_dispatch_filter(&ls[i]);
            ngx_udpv2_push_dispatch_filter(cycle, &ls[i], ngx_xquic_udp_accept_filter);
        }
#endif

        rev->handler = ngx_xquic_event_recv;
        c->data = qmcf;
        if (c->data == NULL) {
            ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                        "|xquic|ngx_xquic_process_init|qmcf equals NULL|");
            return NGX_ERROR;  
        }
    }

    /* socket init end */
    if (with_xquic && ngx_xquic_engine_init(cycle) != NGX_OK) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, 
                    "|xquic|ngx_xquic_process_init|engine_init fail|");
        return NGX_ERROR;
    }

    if (with_xquic && ngx_xquic_intercom_init(cycle, qmcf->xquic_engine) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


void
ngx_xquic_process_exit(ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t  *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);

    ngx_log_debug0(NGX_LOG_DEBUG_CORE, cycle->log, 0, "|xquic|ngx_xquic_process_exit|");

    if (qmcf->xquic_engine) {
        xqc_engine_destroy(qmcf->xquic_engine);
        qmcf->xquic_engine = NULL;

        ngx_xquic_intercom_exit();
    }
}


void 
ngx_xquic_log_write_err(xqc_log_level_t lvl, const void *buf, size_t size, void *engine_user_data)
{
    ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "|xquic|lib%*s|", size, buf);
}


void 
ngx_xquic_log_write_stat(xqc_log_level_t lvl, const void *buf, size_t size, void *engine_user_data)
{
    ngx_log_xquic(NGX_LOG_WARN, ngx_cycle->x_log, 0, "%*s|", size, buf);
}


#if (NGX_XQUIC_SUPPORT_CID_ROUTE)

ngx_int_t
ngx_xquic_is_cid_route_on(ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);
    return !!qmcf->cid_route;
}

ngx_inline ngx_int_t
ngx_xquic_init_cid_route(ngx_cycle_t *cycle, ngx_http_xquic_main_conf_t *qmcf)
{
    ngx_cycle_t                 *old_cycle;
    ngx_http_xquic_main_conf_t  *old_qmcf;

    if (!qmcf) {
        return NGX_ERROR;
    }

    old_cycle = cycle->old_cycle;
    old_qmcf  = (old_cycle && !ngx_is_init_cycle(old_cycle)) ? ngx_http_cycle_get_module_main_conf(old_cycle, ngx_http_xquic_module) : NULL;

    /* set salt range */
    qmcf->cid_worker_id_salt_range  = qmcf->cid_worker_id_offset;

    /* keep the same cid_worker_id_secret for the tengine reload */
    if (old_qmcf) {
        /* use same cid_worker_id_secret */
        qmcf->cid_worker_id_secret  = old_qmcf->cid_worker_id_secret;
    }else {
        srandom(time(NULL));
        /* generate security stuff */
        qmcf->cid_worker_id_secret  = random();
    }

    return NGX_OK;
}

ngx_int_t
ngx_xquic_enable_cid_route(ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);
    if (!qmcf) {
        return NGX_ERROR;
    }

    if (qmcf->cid_route == NGX_CONF_UNSET) {
        /* need init xquic module first */
        return NGX_ERROR;
    }else if (qmcf->cid_route) {
        /* already enable */
        return NGX_OK;
    }

    qmcf->cid_route = 1;
    return ngx_xquic_init_cid_route(cycle, qmcf);
}

ssize_t
ngx_xquic_cid_generate_cb(const xqc_cid_t *ori_cid, uint8_t *cid_buf, size_t cid_buflen, void *engine_user_data)
{
    (void) engine_user_data;

    size_t   current_cid_buflen;
    const uint8_t *current_cid_buf;

    current_cid_buf     = NULL;
    current_cid_buflen  = 0;

    if (ori_cid) {
        current_cid_buf = ori_cid->cid_buf;
        current_cid_buflen = ori_cid->cid_len;
    }

    return ngx_xquic_generate_route_cid(cid_buf, cid_buflen, current_cid_buf, current_cid_buflen);
}

uint32_t
ngx_xquic_cid_length(ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);
    return qmcf->cid_len;
}

uint32_t
ngx_xquic_cid_worker_id_salt_range(ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);
    return qmcf->cid_worker_id_salt_range;
}

uint32_t
ngx_xquic_cid_worker_id_offset(ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);
    return qmcf->cid_worker_id_offset;
}

uint32_t
ngx_xquic_cid_worker_id_secret(ngx_cycle_t *cycle)
{
    ngx_http_xquic_main_conf_t *qmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_xquic_module);
    return qmcf->cid_worker_id_secret;
}

static inline void
ngx_xquic_random_buf(unsigned char *p, size_t len)
{
    uint32_t r;
    while (len > sizeof(r)) {
       r = random();
       ngx_memcpy(p, &r, sizeof(r));
       p   += sizeof(r);
       len -= sizeof(r);
    }
    if (len > 0) {
        r = random();
        ngx_memcpy(p, &r, len);
    }
}

ssize_t
ngx_xquic_generate_route_cid(unsigned char *buf, size_t len, const uint8_t *current_cid_buf, size_t current_cid_buflen)
{
    ngx_core_conf_t *ccf;
    ngx_http_xquic_main_conf_t  *qmcf;
    uint32_t worker, salt;
    int32_t delta;

    qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);
    ccf = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx, ngx_core_module);

    if (XQC_UNLIKELY(len < qmcf->cid_len)) {
        /**
        * just return 0 to force xquic generate random cid
        * Notes: broke the DCID spec
        */
        ngx_log_error(NGX_LOG_WARN, ngx_cycle->log, 0, "|xquic|dismatch cid length %d (required %d)|", len, qmcf->cid_len);
        return 0;
    }

    /* fill with random data */
    ngx_xquic_random_buf(buf, qmcf->cid_len);

    /* calculate salt */
    salt = ngx_murmur_hash2(buf, qmcf->cid_worker_id_salt_range);

    /**
     * required :
     * 1. pid < 2 ^ 22  (SYSTEM LIMITED)
     * 2. ngx_worker < 1024
     * */

    delta = ngx_worker - salt % ccf->worker_processes;
    if (delta < 0) {
        delta += ccf->worker_processes;
    }

#define PID_MAX_BIT 22
    /* set worker delta */
    worker = delta << PID_MAX_BIT;
    /* set PID */
    worker = worker | getpid();
    /* encrypt worker */
    worker = htonl( (worker + salt) ^ qmcf->cid_worker_id_secret);
    /* set worker id */
    ngx_memcpy(buf + qmcf->cid_worker_id_offset, &worker, sizeof(worker));
    return qmcf->cid_len;
}

#ifdef UINT64_MAX
static ngx_inline uint32_t
ngx_sum_complement(uint64_t a, uint64_t b, uint32_t c)
{
    return (a + b) % c;
}
#endif

ngx_int_t
ngx_xquic_get_target_worker_from_cid(ngx_xquic_recv_packet_t *packet)
{
    ngx_core_conf_t             *ccf;
    ngx_http_xquic_main_conf_t  *qmcf;
    uint32_t                     worker, salt;
    u_char                      *dcid;

    ccf  = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx, ngx_core_module);
    qmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle, ngx_http_xquic_module);
    dcid = packet->xquic.dcid.cid_buf;

    if (packet->xquic.dcid.cid_len >= qmcf->cid_len) {
        /* calculate salt */
        salt = ngx_murmur_hash2(dcid, qmcf->cid_worker_id_salt_range);
        /* get cipher worker */
        memcpy(&worker, dcid + qmcf->cid_worker_id_offset, sizeof(worker));
        /* decrypt */
        worker = (ntohl(worker) ^ qmcf->cid_worker_id_secret) - salt;

#ifdef UINT64_MAX
        return ngx_sum_complement(worker >> PID_MAX_BIT, salt, ccf->worker_processes);
#else
        /**
         * For the mathematics, ((worker >> PID_MAX_BIT) + salt) % ccf->worker_processes is better
         * (worker >> PID_MAX_BIT) + salt may overflow in practice
         * */
        return ((worker >> PID_MAX_BIT) % ccf->worker_processes + salt % ccf->worker_processes)
                % ccf->worker_processes;
#endif

#undef PID_MAX_BIT
    }

    return ngx_murmur_hash2(dcid, packet->xquic.dcid.cid_len) % ccf->worker_processes;
}
#endif
