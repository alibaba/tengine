/*
 * This fake module was used to reproduce a bug in ngx_lua's
 * init_worker_by_lua implementation.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


typedef struct {
    ngx_flag_t a;
} ngx_http_fake_merge_main_conf_t;


typedef struct {
    ngx_flag_t a;
} ngx_http_fake_merge_srv_conf_t;


typedef struct {
    ngx_flag_t a;
} ngx_http_fake_merge_loc_conf_t;


static ngx_int_t ngx_http_fake_merge_add_variable(ngx_conf_t *cf);
static ngx_int_t ngx_http_fake_merge_var(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_fake_merge_init(ngx_conf_t *cf);
static void *ngx_http_fake_merge_create_main_conf(ngx_conf_t *cf);
static void *ngx_http_fake_merge_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_fake_merge_merge_loc_conf(ngx_conf_t *cf, void *prev,
    void *conf);


/* flow identify module configure struct */
static ngx_http_module_t  ngx_http_fake_merge_module_ctx = {
    ngx_http_fake_merge_init,             /* preconfiguration */
    NULL,                                 /* postconfiguration */

    ngx_http_fake_merge_create_main_conf, /* create main configuration */
    NULL,                                 /* init main configuration */

    NULL,                                 /* create server configuration */
    NULL,                                 /* merge server configuration */

    ngx_http_fake_merge_create_loc_conf,  /* create location configuration */
    ngx_http_fake_merge_merge_loc_conf    /* merge location configuration */
};


/* flow identify module struct */
ngx_module_t  ngx_http_fake_merge_module = {
    NGX_MODULE_V1,
    &ngx_http_fake_merge_module_ctx,      /* module context */
    NULL,                                 /* module directives */
    NGX_HTTP_MODULE,                      /* module type */
    NULL,                                 /* init master */
    NULL,                                 /* init module */
    NULL,                                 /* init process */
    NULL,                                 /* init thread */
    NULL,                                 /* exit thread */
    NULL,                                 /* exit process */
    NULL,                                 /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_variable_t  ngx_http_fake_merge_variables[] = {

    { ngx_string("fake_var"), NULL,
      ngx_http_fake_merge_var, 0,
      NGX_HTTP_VAR_NOCACHEABLE, 0 },

    { ngx_null_string, NULL, NULL, 0, 0, 0 }
};


static ngx_int_t
ngx_http_fake_merge_var(ngx_http_request_t *r, ngx_http_variable_value_t *v,
    uintptr_t data)
{
    ngx_http_fake_merge_main_conf_t * fmcf;
    static char *str[] = {"0", "1"};

    fmcf = ngx_http_get_module_main_conf(r, ngx_http_fake_merge_module);
    if (fmcf == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "get module main conf failed if fake_var");
        return NGX_ERROR;
    }

    v->len = 1;
    v->data = (u_char *) str[fmcf->a];
    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    return NGX_OK;
}


static ngx_int_t 
ngx_http_fake_merge_add_variable(ngx_conf_t *cf)
{
    ngx_http_variable_t  *var, *v;

    for (v = ngx_http_fake_merge_variables; v->name.len; v++) {
        var = ngx_http_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }
        
        var->get_handler = v->get_handler;
        var->data = v->data;
        v->index = ngx_http_get_variable_index(cf, &v->name);
        if (v->index == (ngx_uint_t) NGX_ERROR) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;

}


/* postconfiguration init */
static ngx_int_t ngx_http_fake_merge_init(ngx_conf_t *cf)
{
    ngx_http_fake_merge_loc_conf_t   *flcf;

    flcf = ngx_http_conf_get_module_loc_conf(cf,
                                              ngx_http_fake_merge_module);
    if (flcf == NULL) {
        return NGX_ERROR;
    }

    flcf->a = 1;
 
    if (ngx_http_fake_merge_add_variable(cf) != NGX_OK) {
        return NGX_ERROR;
    }
    
    return NGX_OK;
}


/* create main configure */
static void *ngx_http_fake_merge_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_fake_merge_main_conf_t   *fmcf;

    fmcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_fake_merge_main_conf_t));
    if (fmcf == NULL) {
        ngx_conf_log_error(NGX_LOG_ALERT, cf, 0, "create module main conf");
        return NULL;
    }

    return fmcf;
}


/* create location configure */
static void *ngx_http_fake_merge_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_fake_merge_loc_conf_t   *flcf;

    flcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_fake_merge_loc_conf_t));
    if (flcf == NULL) {
        return NULL;
    }

    flcf->a = NGX_CONF_UNSET;

    return flcf;
}


/* merge location configure */
static char *
ngx_http_fake_merge_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_fake_merge_loc_conf_t    *conf = child;
    ngx_http_fake_merge_loc_conf_t    *prev = parent;
    ngx_http_fake_merge_main_conf_t   *fmcf;

    ngx_conf_merge_value(conf->a, prev->a, 0);

    fmcf = ngx_http_conf_get_module_main_conf(cf,
                                              ngx_http_fake_merge_module);
    if (fmcf == NULL) {
        ngx_conf_log_error(NGX_LOG_ALERT, cf, 0,
                           "get module main conf failed in merge loc conf");
        return NGX_CONF_ERROR;
    }
   

    fmcf->a = conf->a;

    return NGX_CONF_OK;
}
