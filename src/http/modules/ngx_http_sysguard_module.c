/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#define NGX_HTTP_SYSGUARD_MODE_OR  0
#define NGX_HTTP_SYSGUARD_MODE_AND 1


typedef struct {
    time_t           stamp;
    ngx_uint_t       requests;
    time_t           sec;
    ngx_msec_int_t   msec;
} ngx_http_sysguard_rt_node_t;

typedef struct {
    ngx_http_sysguard_rt_node_t  *slots;
    ngx_int_t                     nr_slots;
    ngx_int_t                     current;

    time_t                        cached_rt_exptime;
    ngx_int_t                     cached_rt;
} ngx_http_sysguard_rt_ring_t;

typedef struct {
    ngx_flag_t                    enable;

    ngx_int_t                     load;
    ngx_str_t                     load_action;
    ngx_int_t                     swap;
    ngx_str_t                     swap_action;
    size_t                        free;
    ngx_str_t                     free_action;
    ngx_int_t                     rt;
    ngx_int_t                     rt_period;
    ngx_str_t                     rt_action;
    time_t                        interval;

    ngx_uint_t                    log_level;
    ngx_uint_t                    mode;

    ngx_http_sysguard_rt_ring_t  *rt_ring;
} ngx_http_sysguard_conf_t;


static void *ngx_http_sysguard_create_conf(ngx_conf_t *cf);
static char *ngx_http_sysguard_merge_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_sysguard_load(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_sysguard_mem(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_sysguard_rt(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_sysguard_init(ngx_conf_t *cf);


static ngx_conf_enum_t  ngx_http_sysguard_log_levels[] = {
    { ngx_string("info"), NGX_LOG_INFO },
    { ngx_string("notice"), NGX_LOG_NOTICE },
    { ngx_string("warn"), NGX_LOG_WARN },
    { ngx_string("error"), NGX_LOG_ERR },
    { ngx_null_string, 0 }
};

static ngx_conf_enum_t  ngx_http_sysguard_modes[] = {
    { ngx_string("or"), NGX_HTTP_SYSGUARD_MODE_OR },
    { ngx_string("and"), NGX_HTTP_SYSGUARD_MODE_AND },
    { ngx_null_string, 0 }
};


static ngx_command_t  ngx_http_sysguard_commands[] = {

    { ngx_string("sysguard"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_sysguard_conf_t, enable),
      NULL },

    { ngx_string("sysguard_mode"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_enum_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_sysguard_conf_t, mode),
      &ngx_http_sysguard_modes },

    { ngx_string("sysguard_load"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE12,
      ngx_http_sysguard_load,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("sysguard_mem"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE12,
      ngx_http_sysguard_mem,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("sysguard_rt"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE123,
      ngx_http_sysguard_rt,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("sysguard_interval"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_sec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_sysguard_conf_t, interval),
      NULL },

    { ngx_string("sysguard_log_level"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_enum_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_sysguard_conf_t, log_level),
      &ngx_http_sysguard_log_levels },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_sysguard_module_ctx = {
    NULL,                                   /* preconfiguration */
    ngx_http_sysguard_init,                 /* postconfiguration */

    NULL,                                   /* create main configuration */
    NULL,                                   /* init main configuration */

    NULL,                                   /* create server configuration */
    NULL,                                   /* merge server configuration */

    ngx_http_sysguard_create_conf,          /* create location configuration */
    ngx_http_sysguard_merge_conf            /* merge location configuration */
};


ngx_module_t  ngx_http_sysguard_module = {
    NGX_MODULE_V1,
    &ngx_http_sysguard_module_ctx,          /* module context */
    ngx_http_sysguard_commands,             /* module directives */
    NGX_HTTP_MODULE,                        /* module type */
    NULL,                                   /* init master */
    NULL,                                   /* init module */
    NULL,                                   /* init process */
    NULL,                                   /* init thread */
    NULL,                                   /* exit thread */
    NULL,                                   /* exit process */
    NULL,                                   /* exit master */
    NGX_MODULE_V1_PADDING
};


static time_t    ngx_http_sysguard_cached_load_exptime;
static time_t    ngx_http_sysguard_cached_mem_exptime;
static ngx_int_t ngx_http_sysguard_cached_load;
static ngx_int_t ngx_http_sysguard_cached_swapstat;
static size_t    ngx_http_sysguard_cached_free;


static ngx_int_t
ngx_http_sysguard_update_load(ngx_http_request_t *r, time_t exptime)
{
    ngx_int_t  load, rc;

    ngx_http_sysguard_cached_load_exptime = ngx_time() + exptime;

    rc = ngx_getloadavg(&load, 1, r->connection->log);
    if (rc == NGX_ERROR) {

        ngx_http_sysguard_cached_load = 0;

        return NGX_ERROR;
    }

    ngx_http_sysguard_cached_load = load;

    return NGX_OK;
}


static ngx_int_t
ngx_http_sysguard_update_mem(ngx_http_request_t *r, time_t exptime)
{
    ngx_int_t      rc;
    ngx_meminfo_t  m;

    ngx_http_sysguard_cached_mem_exptime = ngx_time() + exptime;

    rc = ngx_getmeminfo(&m, r->connection->log);
    if (rc == NGX_ERROR) {

        ngx_http_sysguard_cached_swapstat = 0;
        ngx_http_sysguard_cached_free = NGX_CONF_UNSET_SIZE;

        return NGX_ERROR;
    }

    ngx_http_sysguard_cached_swapstat = m.totalswap == 0
        ? 0 : (m.totalswap - m.freeswap) * 100 / m.totalswap;
    ngx_http_sysguard_cached_free = m.freeram + m.cachedram + m.bufferram;

    return NGX_OK;
}


static ngx_int_t
ngx_http_sysguard_update_rt(ngx_http_request_t *r, time_t exptime)
{
    ngx_uint_t                    rt = 0, rt_sec = 0,
                                  rt_requests = 0;
    ngx_int_t                     i, head, processed = 0;
    ngx_msec_int_t                rt_msec = 0;
    ngx_http_sysguard_conf_t     *glcf;
    ngx_http_sysguard_rt_ring_t  *ring;
    ngx_http_sysguard_rt_node_t  *node, *cur_node;

    glcf = ngx_http_get_module_loc_conf(r, ngx_http_sysguard_module);

    ring = glcf->rt_ring;

    ring->cached_rt_exptime = ngx_time() + exptime;

    i = ring->current;

    head = (ring->current + 1) % ring->nr_slots;

    cur_node = &ring->slots[ring->current];

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "sysguard update rt: i: %i, c:%i h: %i",
                   i, ring->current, head);

    for ( ; (i != head) && (processed < glcf->rt_period); i--, processed++) {

        node = &ring->slots[i];

        ngx_log_debug5(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "node in loop: i: %i, p:%i, sec: %T, msec: %i, r: %ui",
                       i, processed, node->sec, node->msec, node->requests);

        if (node->stamp == 0
            || (cur_node->stamp - node->stamp) != processed)
        {

            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "continue: i: %i, p:%i, node tamp: %T, "
                           "cur stamp: %T",
                           i, processed, node->stamp, cur_node->stamp);

           goto cont;
        }

        rt_sec += node->sec;
        rt_msec += node->msec;
        rt_requests += node->requests;

cont:
        /* wrap back to beginning */
        if (i == 0) {
            i = ring->nr_slots;
        }
    }

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "rt sec: %ui, rt msec:%i, rc requests: %ui",
                   rt_sec, rt_msec, rt_requests);

    rt_msec += (ngx_msec_int_t) (rt_sec * 1000);
    rt_msec = ngx_max(rt_msec, 0);

    if (rt_requests != 0 && rt_msec > 0) {

        rt_msec = rt_msec / rt_requests;

        rt = rt_msec / 1000 * 1000 + rt_msec % 1000;
    }

    ring->cached_rt = rt;

    return NGX_OK;
}


void
ngx_http_sysguard_update_rt_node(ngx_http_request_t *r)
{
    ngx_http_sysguard_rt_ring_t    *ring;
    ngx_http_sysguard_rt_node_t    *node;
    time_t                          cur_sec, off;
    ngx_uint_t                      cur_msec;
    ngx_http_sysguard_conf_t       *glcf;

    glcf = ngx_http_get_module_loc_conf(r, ngx_http_sysguard_module);

    if (!glcf->enable) {
        return;
    }

    if (glcf->rt == NGX_CONF_UNSET) {
        return;
    }

    cur_sec = ngx_cached_time->sec;
    cur_msec = ngx_cached_time->msec;

    ring = glcf->rt_ring;

    node = &ring->slots[ring->current];

    off = cur_sec - node->stamp;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "sysguard update rt node: off: %T, stamp:%T, cur time: %T",
                   off, node->stamp, cur_sec);

    if (off) {

        ring->current = (ring->current + off) % ring->nr_slots;

        node = &ring->slots[ring->current];

        memset(node, 0, sizeof(ngx_http_sysguard_rt_node_t));

        node->stamp = cur_sec;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "sysguard update rt node: new current: %i",
                   ring->current);

    node->sec += cur_sec - r->start_sec;
    node->msec += cur_msec - r->start_msec;
    node->requests++;
}


static ngx_int_t
ngx_http_sysguard_do_redirect(ngx_http_request_t *r, ngx_str_t *path)
{
    if (path->len == 0) {
        return NGX_HTTP_SERVICE_UNAVAILABLE;
    } else if (path->data[0] == '@') {
        (void) ngx_http_named_location(r, path);
    } else {
        (void) ngx_http_internal_redirect(r, path, &r->args);
    }

    ngx_http_finalize_request(r, NGX_DONE);

    return NGX_DONE;
}


static ngx_int_t
ngx_http_sysguard_handler(ngx_http_request_t *r)
{
    ngx_http_sysguard_conf_t  *glcf;
    ngx_int_t                  load_log = 0, swap_log = 0,
                               free_log = 0, rt_log = 0;
    ngx_str_t                 *action = NULL;

    if (r->main->sysguard_set) {
        return NGX_DECLINED;
    }

    glcf = ngx_http_get_module_loc_conf(r, ngx_http_sysguard_module);

    if (!glcf->enable) {
        return NGX_DECLINED;
    }

    r->main->sysguard_set = 1;

    /* load */

    if (glcf->load != NGX_CONF_UNSET) {

        if (ngx_http_sysguard_cached_load_exptime < ngx_time()) {
            ngx_http_sysguard_update_load(r, glcf->interval);
        }

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "http sysguard handler load: %1.3f %1.3f %V %V",
                       ngx_http_sysguard_cached_load * 1.0 / 1000,
                       glcf->load * 1.0 / 1000,
                       &r->uri,
                       &glcf->load_action);

        if (ngx_http_sysguard_cached_load > glcf->load) {

            if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_OR) {

                ngx_log_error(glcf->log_level, r->connection->log, 0,
                              "sysguard load limited, current:%1.3f conf:%1.3f",
                              ngx_http_sysguard_cached_load * 1.0 / 1000,
                              glcf->load * 1.0 / 1000);

                return ngx_http_sysguard_do_redirect(r, &glcf->load_action);
            } else {
                action = &glcf->load_action;
                load_log = 1;
            }
        } else {
            if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_AND) {
                goto out;
            }
        }
    }

    /* swap */

    if (glcf->swap != NGX_CONF_UNSET) {

        if (ngx_http_sysguard_cached_mem_exptime < ngx_time()) {
            ngx_http_sysguard_update_mem(r, glcf->interval);
        }

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "http sysguard handler swap: %i %i %V %V",
                       ngx_http_sysguard_cached_swapstat,
                       glcf->swap,
                       &r->uri,
                       &glcf->swap_action);

        if (ngx_http_sysguard_cached_swapstat > glcf->swap) {

            if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_OR) {

                ngx_log_error(glcf->log_level, r->connection->log, 0,
                              "sysguard swap limited, current:%i conf:%i",
                              ngx_http_sysguard_cached_swapstat,
                              glcf->swap);

                return ngx_http_sysguard_do_redirect(r, &glcf->swap_action);
            } else {
                action = &glcf->swap_action;
                swap_log = 1;
            }
        } else {
            if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_AND) {
                goto out;
            }
        }
    }

    /* mem free */

    if (glcf->free != NGX_CONF_UNSET_SIZE) {

        if (ngx_http_sysguard_cached_mem_exptime < ngx_time()) {
            ngx_http_sysguard_update_mem(r, glcf->interval);
        }

        if (ngx_http_sysguard_cached_free != NGX_CONF_UNSET_SIZE) {

            ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "http sysguard handler free: %uz %uz %V %V",
                           ngx_http_sysguard_cached_free,
                           glcf->free,
                           &r->uri,
                           &glcf->free_action);

            if (ngx_http_sysguard_cached_free < glcf->free) {

                if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_OR) {

                    ngx_log_error(glcf->log_level, r->connection->log, 0,
                                  "sysguard free limited, "
                                  "current:%uzM conf:%uzM",
                                  ngx_http_sysguard_cached_free / 1024 / 1024,
                                  glcf->free / 1024 / 1024);

                    return ngx_http_sysguard_do_redirect(r, &glcf->free_action);
                } else {
                    action = &glcf->free_action;
                    free_log = 1;
                }
            } else {
                if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_AND) {
                    goto out;
                }
            }
        }
    }

    /* response time */

    if (glcf->rt != NGX_CONF_UNSET) {

        if (glcf->rt_ring->cached_rt_exptime < ngx_time()) {
            ngx_http_sysguard_update_rt(r, glcf->interval);
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "http sysguard handler rt: %1.3f %1.3f",
                       glcf->rt_ring->cached_rt * 1.0 / 1000,
                       glcf->rt * 1.0 / 1000);

        if (glcf->rt_ring->cached_rt > glcf->rt) {

            if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_OR) {

                ngx_log_error(glcf->log_level, r->connection->log, 0,
                              "sysguard rt limited, current:%1.3f conf:%1.3f",
                              glcf->rt_ring->cached_rt * 1.0 / 1000,
                              glcf->rt * 1.0 / 1000);

                return ngx_http_sysguard_do_redirect(r, &glcf->rt_action);
            } else {
                action = &glcf->rt_action;
                rt_log = 1;
            }
        } else {
            if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_AND) {
                goto out;
            }
        }
    }

    if (glcf->mode == NGX_HTTP_SYSGUARD_MODE_AND && action) {

        if (load_log) {
            ngx_log_error(glcf->log_level, r->connection->log, 0,
                          "sysguard load limited, current:%1.3f conf:%1.3f",
                          ngx_http_sysguard_cached_load * 1.0 / 1000,
                          glcf->load * 1.0 / 1000);
        }

        if (swap_log) {
            ngx_log_error(glcf->log_level, r->connection->log, 0,
                          "sysguard swap limited, current:%i conf:%i",
                          ngx_http_sysguard_cached_swapstat,
                          glcf->swap);
        }

        if (free_log) {
            ngx_log_error(glcf->log_level, r->connection->log, 0,
                          "sysguard free limited, current:%uzM conf:%uzM",
                          ngx_http_sysguard_cached_free / 1024 / 1024,
                          glcf->free / 1024 / 1024);
        }

        if (rt_log) {
            ngx_log_error(glcf->log_level, r->connection->log, 0,
                          "sysguard rt limited, current:%1.3f conf:%1.3f",
                          glcf->rt_ring->cached_rt * 1.0 / 1000,
                          glcf->rt * 1.0 / 1000);
        }

        return ngx_http_sysguard_do_redirect(r, action);
    }

out:
    return NGX_DECLINED;
}


static void *
ngx_http_sysguard_create_conf(ngx_conf_t *cf)
{
    ngx_http_sysguard_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_sysguard_conf_t));
    if (conf == NULL) {
        return NGX_CONF_ERROR;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->load_action = {0, NULL};
     *     conf->swap_action = {0, NULL};
     *     conf->rt_action = {0, NULL};
     *     conf->ring = NULL;
     */

    conf->enable = NGX_CONF_UNSET;
    conf->load = NGX_CONF_UNSET;
    conf->swap = NGX_CONF_UNSET;
    conf->free = NGX_CONF_UNSET_SIZE;
    conf->rt = NGX_CONF_UNSET;
    conf->rt_period = NGX_CONF_UNSET;
    conf->interval = NGX_CONF_UNSET;
    conf->log_level = NGX_CONF_UNSET_UINT;
    conf->mode = NGX_CONF_UNSET_UINT;

    return conf;
}


static char *
ngx_http_sysguard_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_sysguard_conf_t  *prev = parent;
    ngx_http_sysguard_conf_t  *conf = child;

    ngx_conf_merge_value(conf->enable, prev->enable, 0);
    ngx_conf_merge_str_value(conf->load_action, prev->load_action, "");
    ngx_conf_merge_str_value(conf->swap_action, prev->swap_action, "");
    ngx_conf_merge_str_value(conf->free_action, prev->free_action, "");
    ngx_conf_merge_str_value(conf->rt_action, prev->rt_action, "");
    ngx_conf_merge_value(conf->load, prev->load, NGX_CONF_UNSET);
    ngx_conf_merge_value(conf->swap, prev->swap, NGX_CONF_UNSET);
    ngx_conf_merge_size_value(conf->free, prev->free, NGX_CONF_UNSET_SIZE);
    ngx_conf_merge_value(conf->rt, prev->rt, NGX_CONF_UNSET);
    ngx_conf_merge_value(conf->rt_period, prev->rt_period, 1);
    ngx_conf_merge_value(conf->interval, prev->interval, 1);
    ngx_conf_merge_uint_value(conf->log_level, prev->log_level, NGX_LOG_ERR);
    ngx_conf_merge_uint_value(conf->mode, prev->mode,
                              NGX_HTTP_SYSGUARD_MODE_OR);


    if (conf->rt != NGX_CONF_UNSET) {
        /* init glcf->ring */
        conf->rt_ring = ngx_pcalloc(cf->pool,
                                    sizeof(ngx_http_sysguard_rt_ring_t));
        if (conf->rt_ring == NULL) {
            return NGX_CONF_ERROR;
        }

        conf->rt_ring->slots = ngx_pcalloc(cf->pool,
                         sizeof(ngx_http_sysguard_rt_node_t) * conf->rt_period);
        if (conf->rt_ring->slots == NULL) {
            return NGX_CONF_ERROR;
        }

        conf->rt_ring->nr_slots = conf->rt_period;
        conf->rt_ring->current = 0;
        conf->rt_ring->slots[0].stamp = ngx_time();
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_sysguard_load(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_sysguard_conf_t  *glcf = conf;

    ngx_str_t  *value;
    ngx_uint_t  i, scale;

    value = cf->args->elts;
    i = 1;
    scale = 1;

    if (ngx_strncmp(value[i].data, "load=", 5) == 0) {

        if (glcf->load != NGX_CONF_UNSET) {
            return "is duplicate";
        }

        if (value[i].len == 5) {
            goto invalid;
        }

        value[i].data += 5;
        value[i].len -= 5;

        if (ngx_strncmp(value[i].data, "ncpu*", 5) == 0) {
            value[i].data += 5;
            value[i].len -= 5;
            scale = ngx_ncpu;
        }

        glcf->load = ngx_atofp(value[i].data, value[i].len, 3);
        if (glcf->load == NGX_ERROR) {
            goto invalid;
        }

        glcf->load = glcf->load * scale;

        if (cf->args->nelts == 2) {
            return NGX_CONF_OK;
        }

        i++;

        if (ngx_strncmp(value[i].data, "action=", 7) != 0) {
            goto invalid;
        }

        if (value[i].len == 7) {
            goto invalid;
        }

        if (value[i].data[7] != '/' && value[i].data[7] != '@') {
            goto invalid;
        }

        glcf->load_action.data = value[i].data + 7;
        glcf->load_action.len = value[i].len - 7;

        return NGX_CONF_OK;
    }

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static char *
ngx_http_sysguard_mem(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_sysguard_conf_t  *glcf = conf;

    ngx_str_t  *value, ss;
    ngx_uint_t  i;

    value = cf->args->elts;
    i = 1;

    if (ngx_strncmp(value[i].data, "swapratio=", 10) == 0) {

        if (glcf->swap != NGX_CONF_UNSET) {
            return "is duplicate";
        }

        if (value[i].data[value[i].len - 1] != '%') {
            goto invalid;
        }

        glcf->swap = ngx_atofp(value[i].data + 10, value[i].len - 11, 2);
        if (glcf->swap == NGX_ERROR) {
            goto invalid;
        }

        if (cf->args->nelts == 2) {
            return NGX_CONF_OK;
        }

        i++;

        if (ngx_strncmp(value[i].data, "action=", 7) != 0) {
            goto invalid;
        }

        if (value[i].len == 7) {
            goto invalid;
        }

        if (value[i].data[7] != '/' && value[i].data[7] != '@') {
            goto invalid;
        }

        glcf->swap_action.data = value[i].data + 7;
        glcf->swap_action.len = value[i].len - 7;

        return NGX_CONF_OK;

    } else if (ngx_strncmp(value[i].data, "free=", 5) == 0) {

        if (glcf->free != NGX_CONF_UNSET_SIZE) {
            return "is duplicate";
        }

        ss.data = value[i].data + 5;
        ss.len = value[i].len - 5;

        glcf->free = ngx_parse_size(&ss);
        if (glcf->free == (size_t) NGX_ERROR) {
            goto invalid;
        }

        if (cf->args->nelts == 2) {
            return NGX_CONF_OK;
        }

        i++;

        if (ngx_strncmp(value[i].data, "action=", 7) != 0) {
            goto invalid;
        }

        if (value[i].len == 7) {
            goto invalid;
        }

        if (value[i].data[7] != '/' && value[i].data[7] != '@') {
            goto invalid;
        }

        glcf->free_action.data = value[i].data + 7;
        glcf->free_action.len = value[i].len - 7;

        return NGX_CONF_OK;
    }

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static char *
ngx_http_sysguard_rt(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_sysguard_conf_t  *glcf = conf;

    ngx_str_t  *value, ss;
    ngx_uint_t  i;

    value = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {
        if (ngx_strncmp(value[i].data, "rt=", 3) == 0) {

            if (glcf->rt != NGX_CONF_UNSET) {
                return "is duplicate";
            }

            glcf->rt = ngx_atofp(value[i].data + 3, value[i].len - 3, 3);
            if (glcf->rt == NGX_ERROR) {
                goto invalid;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "period=", 7) == 0) {

            ss.data = value[i].data + 7;
            ss.len = value[i].len - 7;

            glcf->rt_period = ngx_parse_time(&ss, 1);
            if (glcf->rt_period == NGX_ERROR) {
                goto invalid;
            }

            continue;
        }

        if (ngx_strncmp(value[i].data, "action=", 7) == 0) {

            if (value[i].len == 7) {
                goto invalid;
            }

            if (value[i].data[7] != '/' && value[i].data[7] != '@') {
                goto invalid;
            }

            glcf->rt_action.data = value[i].data + 7;
            glcf->rt_action.len = value[i].len - 7;

            continue;
        }
    }

    return NGX_CONF_OK;

invalid:

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid parameter \"%V\"", &value[i]);

    return NGX_CONF_ERROR;
}


static ngx_int_t
ngx_http_sysguard_log_handler(ngx_http_request_t *r)
{
    ngx_http_sysguard_update_rt_node(r);

    return NGX_OK;
}


static ngx_int_t
ngx_http_sysguard_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_PREACCESS_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_sysguard_handler;

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_LOG_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_sysguard_log_handler;

    return NGX_OK;
}
