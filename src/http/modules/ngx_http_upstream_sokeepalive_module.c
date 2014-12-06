/* Author: Bryton Lee 
 * Date: 2014-11-30
 */
#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

typedef struct {
#if (NGX_HAVE_KEEPALIVE_TUNABLE)
    int                        tcp_keepidle;
    int                        tcp_keepintvl;
    int                        tcp_keepcnt;
#endif

    ngx_http_upstream_init_pt         original_init_upstream;
    ngx_http_upstream_init_peer_pt    original_init_peer;
} ngx_http_upstream_sokeepalive_srv_conf_t;

typedef struct {
	ngx_http_upstream_sokeepalive_srv_conf_t *conf;

	ngx_http_upstream_t					*upstream;

	void								*data;

    ngx_event_get_peer_pt              original_get_peer;
    ngx_event_free_peer_pt             original_free_peer;

#if (NGX_HTTP_SSL)
    ngx_event_set_peer_session_pt      original_set_session;
    ngx_event_save_peer_session_pt     original_save_session;
#endif

} ngx_http_upstream_sokeepalive_peer_data_t;

static ngx_int_t ngx_http_upstream_init_sokeepalive_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_upstream_get_sokeepalive_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_upstream_free_sokeepalive_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);

#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_upstream_sokeepalive_set_session(
    ngx_peer_connection_t *pc, void *data);
static void ngx_http_upstream_sokeepalive_save_session(ngx_peer_connection_t *pc,
    void *data);
#endif


static void *ngx_http_upstream_sokeepalive_create_conf(ngx_conf_t *cf);
static char *ngx_http_upstream_sokeepalive(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

extern void ngx_http_upstream_finalize_request(ngx_http_request_t *r,
    ngx_http_upstream_t *u, ngx_int_t rc);
extern void ngx_http_upstream_connect(ngx_http_request_t *r,
    ngx_http_upstream_t *u);



static ngx_command_t  ngx_http_upstream_sokeepalive_commands[] = {

    { ngx_string("so_keepalive"),
      NGX_HTTP_UPS_CONF|NGX_CONF_TAKE123|NGX_CONF_NOARGS,
      ngx_http_upstream_sokeepalive,
      0,
      0,
      NULL },

      ngx_null_command
};

static ngx_http_module_t  ngx_http_upstream_sokeepalive_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    ngx_http_upstream_sokeepalive_create_conf, /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};

ngx_module_t  ngx_http_upstream_sokeepalive_module = {
    NGX_MODULE_V1,
    &ngx_http_upstream_sokeepalive_module_ctx, /* module context */
    ngx_http_upstream_sokeepalive_commands,    /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};

static ngx_int_t
ngx_http_upstream_init_sokeepalive(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_upstream_sokeepalive_srv_conf_t  *sokcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
                   "init so_keepalive");

    sokcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_sokeepalive_module);

    if (sokcf->original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    sokcf->original_init_peer = us->peer.init;

    us->peer.init = ngx_http_upstream_init_sokeepalive_peer;

    return NGX_OK;
}

static ngx_int_t
ngx_http_upstream_init_sokeepalive_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_upstream_sokeepalive_peer_data_t  *sokp;
    ngx_http_upstream_sokeepalive_srv_conf_t   *sokcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "init so_keepalive peer");

    sokcf = ngx_http_conf_upstream_srv_conf(us,
                                          ngx_http_upstream_sokeepalive_module);

    sokp = ngx_palloc(r->pool, sizeof(ngx_http_upstream_sokeepalive_peer_data_t));
    if (sokp == NULL) {
        return NGX_ERROR;
    }

    if (sokcf->original_init_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    sokp->conf = sokcf;
    sokp->upstream = r->upstream;
    sokp->data = r->upstream->peer.data;
    sokp->original_get_peer = r->upstream->peer.get;
    sokp->original_free_peer = r->upstream->peer.free;

    r->upstream->peer.data = sokp;
    r->upstream->peer.get = ngx_http_upstream_get_sokeepalive_peer;
    r->upstream->peer.free = ngx_http_upstream_free_sokeepalive_peer;

#if (NGX_HTTP_SSL)
    sokp->original_set_session = r->upstream->peer.set_session;
    sokp->original_save_session = r->upstream->peer.save_session;
    r->upstream->peer.set_session = ngx_http_upstream_sokeepalive_set_session;
    r->upstream->peer.save_session = ngx_http_upstream_sokeepalive_save_session;
#endif

    return NGX_OK;
}

static ngx_int_t
ngx_http_upstream_get_sokeepalive_peer(ngx_peer_connection_t *pc, void *data)
{
    ngx_int_t                               rc;
    ngx_http_upstream_sokeepalive_peer_data_t  *sokp = data;
    ngx_http_upstream_sokeepalive_srv_conf_t   *sokscf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "get so_keepalive peer");


    sokscf = sokp->conf;
	
	/* ask balancer */
	rc = sokp->original_get_peer(pc, sokp->data);
	if (rc != NGX_OK) {
		return rc;
	}

	pc->so_keepalive = 1;

#if (NGX_HAVE_KEEPALIVE_TUNABLE)
	if (sokscf->tcp_keepidle != NGX_CONF_UNSET)
		pc->keepidle = sokscf->tcp_keepidle;

	if (sokscf->tcp_keepintvl != NGX_CONF_UNSET)
		pc->keepintvl = sokscf->tcp_keepintvl;

	if (sokscf->tcp_keepcnt != NGX_CONF_UNSET)
		pc->keepcnt = sokscf->tcp_keepcnt;
#endif   
	
	return NGX_OK;
}

static void
ngx_http_upstream_free_sokeepalive_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_http_upstream_sokeepalive_peer_data_t  *bp = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "free sokeepalive peer");

    bp->original_free_peer(pc, bp->data, state);
}


#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_upstream_sokeepalive_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_sokeepalive_peer_data_t  *dp = data;

    return dp->original_set_session(pc, dp->data);
}


static void
ngx_http_upstream_sokeepalive_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_upstream_sokeepalive_peer_data_t  *dp = data;

    dp->original_save_session(pc, dp->data);

    return;
}

#endif

static void *
ngx_http_upstream_sokeepalive_create_conf(ngx_conf_t *cf)
{
    ngx_http_upstream_sokeepalive_srv_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool,
                       sizeof(ngx_http_upstream_sokeepalive_srv_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->original_init_upstream = NULL;
     *     conf->original_init_peer = NULL;
     */

    return conf;
}

static char *
ngx_http_upstream_sokeepalive(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_upstream_srv_conf_t            *uscf;
	ngx_http_upstream_sokeepalive_srv_conf_t *sokcf;
	ngx_str_t   *value, s;
    ngx_uint_t   i;

	uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

	sokcf = ngx_http_conf_upstream_srv_conf(uscf,
									ngx_http_upstream_sokeepalive_module);

	if (sokcf->original_init_upstream) {
		return "is duplicate";
	}

	sokcf->original_init_upstream = uscf->peer.init_upstream
										? uscf->peer.init_upstream
										: ngx_http_upstream_init_round_robin;

	uscf->peer.init_upstream = ngx_http_upstream_init_sokeepalive;
	
    /* read options */

	if (cf->args->nelts > 0) {
#if (NGX_HAVE_KEEPALIVE_TUNABLE)

		sokcf->tcp_keepidle = NGX_CONF_UNSET;
		sokcf->tcp_keepintvl = NGX_CONF_UNSET;
		sokcf->tcp_keepcnt = NGX_CONF_UNSET;

		value = cf->args->elts;
		for (i = 1; i < cf->args->nelts; i++) {
			if (ngx_strncmp(value[i].data, "tcp_keepidle=", 13) == 0) {
				s.len = value[i].len - 13;
				s.data = &value[i].data[13];
				sokcf->tcp_keepidle = ngx_parse_time(&s, 1);
				if (sokcf->tcp_keepidle == (time_t) NGX_ERROR) {
					ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
							"invalid so_keepalive tcp_keepidle value: \"%s\"",
							&value[i].data[13]);
					return NGX_CONF_ERROR;
				}
				continue;
			}
			
			if (ngx_strncmp(value[i].data, "tcp_keepintvl=", 14) == 0) {
				s.len = value[i].len - 14;
				s.data = &value[i].data[14];

				sokcf->tcp_keepintvl = ngx_parse_time(&s, 1);
				if (sokcf->tcp_keepintvl == (time_t) NGX_ERROR) {
					ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
							"invalid so_keepalive tcp_keepintvl value: \"%s\"",
							&value[i].data[14]);
					return NGX_CONF_ERROR;
				}
				continue;
			}
			
			if (ngx_strncmp(value[i].data, "tcp_keepcnt=", 12) == 0) {
				s.len = value[i].len - 12;
				s.data = &value[i].data[12];

				sokcf->tcp_keepcnt = ngx_atoi(s.data, s.len);
				if (sokcf->tcp_keepcnt == NGX_ERROR) {
					ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
							"invalid so_keepalive tcp_keepcnt value: \"%s\"",
							&value[i].data[12]);
					return NGX_CONF_ERROR;
				}
				continue;
			}
		}

		if (sokcf->tcp_keepidle == 0 && sokcf->tcp_keepintvl == 0
				&& sokcf->tcp_keepcnt == 0) {
			ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
					"invalied so_keepalive value: "
					"tcp_keepidle == tcp_keepintvl == tcp_keepcnt == 0");
			return NGX_CONF_ERROR;
		}

#else
		ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
				"the \"so_keepalive\" parameter accepts "
				"only \"on\" or \"off\" on this platform");
		return NGX_CONF_ERROR;
#endif
	}

    return NGX_CONF_OK;
}
