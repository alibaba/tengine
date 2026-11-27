/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 * Copyright (C) 2010-2013 Weibin Yao (yaoweibin@gmail.com)
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_stream.h>

#include "ngx_upstream_check_module.h"


/*
 * Active health checks for stream upstreams. This module is only the
 * configuration shell for the stream side: the timers, the shared peer state,
 * the probe state machine and the status page all live in the health-check
 * core (ngx_http_upstream_check_module.c) and are shared with the HTTP side,
 * so both sides end up in one shared memory zone and one index space.
 *
 * Consequences worth knowing about:
 *
 *   - "check_status" is an HTTP location handler and is therefore only
 *     available in http{}. A deployment with just a stream{} block needs an
 *     http{} server of its own to render the page, which will then list the
 *     stream peers as well.
 *
 *   - The probe types accepted here are the protocol-independent ones (tcp,
 *     ssl_hello, mysql). The core rejects the HTTP-only types.
 */


typedef struct {
    ngx_uint_t                            check_shm_size;
} ngx_stream_upstream_check_main_conf_t;


static char *ngx_stream_upstream_check(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_stream_upstream_check_send(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_stream_upstream_check_expect_response(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_stream_upstream_check_shm_size(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);

static void *ngx_stream_upstream_check_create_main_conf(ngx_conf_t *cf);
static char *ngx_stream_upstream_check_init_main_conf(ngx_conf_t *cf,
    void *conf);
static void *ngx_stream_upstream_check_create_srv_conf(ngx_conf_t *cf);
static char *ngx_stream_upstream_check_init_srv_conf(ngx_conf_t *cf, void *conf);


static ngx_command_t  ngx_stream_upstream_check_commands[] = {

    { ngx_string("check"),
      NGX_STREAM_UPS_CONF|NGX_CONF_1MORE,
      ngx_stream_upstream_check,
      0,
      0,
      NULL },

    { ngx_string("check_send"),
      NGX_STREAM_UPS_CONF|NGX_CONF_TAKE1,
      ngx_stream_upstream_check_send,
      0,
      0,
      NULL },

    { ngx_string("check_expect_response"),
      NGX_STREAM_UPS_CONF|NGX_CONF_TAKE1,
      ngx_stream_upstream_check_expect_response,
      0,
      0,
      NULL },

    { ngx_string("check_shm_size"),
      NGX_STREAM_MAIN_CONF|NGX_CONF_TAKE1,
      ngx_stream_upstream_check_shm_size,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_stream_module_t  ngx_stream_upstream_check_module_ctx = {
    NULL,                                      /* preconfiguration */
    NULL,                                      /* postconfiguration */

    ngx_stream_upstream_check_create_main_conf, /* create main configuration */
    ngx_stream_upstream_check_init_main_conf,   /* init main configuration */

    ngx_stream_upstream_check_create_srv_conf,  /* create server configuration */
    NULL                                       /* merge server configuration */
};


ngx_module_t  ngx_stream_upstream_check_module = {
    NGX_MODULE_V1,
    &ngx_stream_upstream_check_module_ctx,   /* module context */
    ngx_stream_upstream_check_commands,      /* module directives */
    NGX_STREAM_MODULE,                       /* module type */
    NULL,                                    /* init master */
    NULL,                                    /* init module */
    NULL,                                    /* init process */
    NULL,                                    /* init thread */
    NULL,                                    /* exit thread */
    NULL,                                    /* exit process */
    NULL,                                    /* exit master */
    NGX_MODULE_V1_PADDING
};


ngx_uint_t
ngx_stream_upstream_check_add_peer(ngx_conf_t *cf,
    ngx_stream_upstream_srv_conf_t *us, ngx_addr_t *peer_addr)
{
    ngx_upstream_check_srv_conf_t  *ucscf;

    if (us->srv_conf == NULL) {
        return NGX_ERROR;
    }

    ucscf = ngx_stream_conf_upstream_srv_conf(us,
                                              ngx_stream_upstream_check_module);

    return ngx_upstream_check_add_peer(cf, ucscf, &us->host, peer_addr,
                                       NGX_UPSTREAM_CHECK_STREAM);
}


ngx_uint_t
ngx_stream_upstream_check_peer_down(ngx_uint_t index)
{
    return ngx_upstream_check_peer_down(index);
}


static char *
ngx_stream_upstream_check(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_upstream_check_srv_conf_t  *ucscf;

    ucscf = ngx_stream_conf_get_module_srv_conf(cf,
                                              ngx_stream_upstream_check_module);

    return ngx_upstream_check_parse_directive(cf, ucscf,
                                              NGX_UPSTREAM_CHECK_STREAM);
}


static char *
ngx_stream_upstream_check_send(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_upstream_check_srv_conf_t  *ucscf;

    ucscf = ngx_stream_conf_get_module_srv_conf(cf,
                                              ngx_stream_upstream_check_module);

    return ngx_upstream_check_parse_send(cf, ucscf);
}


static char *
ngx_stream_upstream_check_expect_response(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_upstream_check_srv_conf_t  *ucscf;

    ucscf = ngx_stream_conf_get_module_srv_conf(cf,
                                              ngx_stream_upstream_check_module);

    return ngx_upstream_check_parse_expect(cf, ucscf);
}


static char *
ngx_stream_upstream_check_shm_size(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_str_t                             *value;
    ngx_stream_upstream_check_main_conf_t  *ucmcf;

    ucmcf = ngx_stream_conf_get_module_main_conf(cf,
                                              ngx_stream_upstream_check_module);
    if (ucmcf->check_shm_size) {
        return "is duplicate";
    }

    value = cf->args->elts;

    ucmcf->check_shm_size = ngx_parse_size(&value[1]);
    if (ucmcf->check_shm_size == (size_t) NGX_ERROR) {
        return "invalid value";
    }

    return NGX_CONF_OK;
}


static void *
ngx_stream_upstream_check_create_main_conf(ngx_conf_t *cf)
{
    ngx_stream_upstream_check_main_conf_t  *ucmcf;

    ucmcf = ngx_pcalloc(cf->pool,
                        sizeof(ngx_stream_upstream_check_main_conf_t));
    if (ucmcf == NULL) {
        return NULL;
    }

    /*
     * Make sure the cross-protocol peer container exists for this cycle even
     * when the configuration has no http{} block at all.
     */
    if (ngx_upstream_check_get_peers(cf) == NULL) {
        return NULL;
    }

    return ucmcf;
}


static char *
ngx_stream_upstream_check_init_main_conf(ngx_conf_t *cf, void *conf)
{
    ngx_uint_t                              i;
    ngx_stream_upstream_srv_conf_t         **uscfp;
    ngx_stream_upstream_main_conf_t         *umcf;
    ngx_stream_upstream_check_main_conf_t   *ucmcf = conf;

    umcf = ngx_stream_conf_get_module_main_conf(cf, ngx_stream_upstream_module);

    uscfp = umcf->upstreams.elts;

    for (i = 0; i < umcf->upstreams.nelts; i++) {

        if (ngx_stream_upstream_check_init_srv_conf(cf, uscfp[i]) != NGX_OK) {
            return NGX_CONF_ERROR;
        }
    }

    return ngx_upstream_check_init_shm(cf, ucmcf->check_shm_size);
}


static void *
ngx_stream_upstream_check_create_srv_conf(ngx_conf_t *cf)
{
    return ngx_upstream_check_create_srv_conf(cf);
}


static char *
ngx_stream_upstream_check_init_srv_conf(ngx_conf_t *cf, void *conf)
{
    ngx_stream_upstream_srv_conf_t  *us = conf;
    ngx_upstream_check_srv_conf_t   *ucscf;

    if (us->srv_conf == NULL) {
        return NGX_CONF_OK;
    }

    ucscf = ngx_stream_conf_upstream_srv_conf(us,
                                              ngx_stream_upstream_check_module);

    return ngx_upstream_check_init_srv_conf(cf, ucscf,
                                            NGX_UPSTREAM_CHECK_STREAM);
}
