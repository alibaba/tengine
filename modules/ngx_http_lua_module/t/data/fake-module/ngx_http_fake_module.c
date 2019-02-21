/*
 * This fake module was used to reproduce a bug in ngx_lua's
 * init_worker_by_lua implementation.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


typedef struct {
    ngx_int_t a;
} ngx_http_fake_srv_conf_t;


typedef struct {
    ngx_int_t a;
} ngx_http_fake_loc_conf_t;


static void *ngx_http_fake_create_srv_conf(ngx_conf_t *cf);
static char *ngx_http_fake_merge_srv_conf(ngx_conf_t *cf, void *prev, void *conf);
static void *ngx_http_fake_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_fake_merge_loc_conf(ngx_conf_t *cf, void *prev, void *conf);


/* flow identify module configure struct */
static ngx_http_module_t  ngx_http_fake_module_ctx = {
    NULL,                           /* preconfiguration */
    NULL,                           /* postconfiguration */

    NULL,                           /* create main configuration */
    NULL,                           /* init main configuration */

    ngx_http_fake_create_srv_conf,  /* create server configuration */
    ngx_http_fake_merge_srv_conf,   /* merge server configuration */

    ngx_http_fake_create_loc_conf,  /* create location configuration */
    ngx_http_fake_merge_loc_conf    /* merge location configuration */
};

/* flow identify module struct */
ngx_module_t  ngx_http_fake_module = {
    NGX_MODULE_V1,
    &ngx_http_fake_module_ctx,      /* module context */
    NULL,                           /* module directives */
    NGX_HTTP_MODULE,                /* module type */
    NULL,                           /* init master */
    NULL,                           /* init module */
    NULL,                           /* init process */
    NULL,                           /* init thread */
    NULL,                           /* exit thread */
    NULL,                           /* exit process */
    NULL,                           /* exit master */
    NGX_MODULE_V1_PADDING
};


/* create server configure */
static void *ngx_http_fake_create_srv_conf(ngx_conf_t *cf)
{
    ngx_http_fake_srv_conf_t   *fscf;

    fscf = ngx_pcalloc(cf->pool, sizeof(ngx_http_fake_srv_conf_t));
    if (fscf == NULL) {
        return NULL;
    }

    return fscf;
}


/* merge server configure */
static char *ngx_http_fake_merge_srv_conf(ngx_conf_t *cf, void *prev, void *conf)
{
    ngx_http_fake_srv_conf_t   *fscf;

    fscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_fake_module);
    if (fscf == NULL) {
        ngx_conf_log_error(NGX_LOG_ALERT, cf, 0,
                           "get module srv conf failed in merge srv conf");
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


/* create location configure */
static void *ngx_http_fake_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_fake_loc_conf_t   *flcf;

    flcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_fake_loc_conf_t));
    if (flcf == NULL) {
        return NULL;
    }

    return flcf;
}


/* merge location configure */
static char *ngx_http_fake_merge_loc_conf(ngx_conf_t *cf, void *prev, void *conf)
{
    ngx_http_fake_loc_conf_t   *flcf;

    flcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_fake_module);
    if (flcf == NULL) {
        ngx_conf_log_error(NGX_LOG_ALERT, cf, 0,
                           "get module loc conf failed in merge loc conf");
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}
