/*
 *  lieyuan@taobao.com
 *  remove comment   <!--  any words  -->
 */



#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


typedef struct {
    ngx_flag_t      enable;
    ngx_hash_t      types;
    ngx_array_t    *types_keys;
} ngx_http_remove_comment_loc_conf_t;


typedef struct {
    ngx_str_t       head;
    ngx_uint_t      saved;

    u_char         *pos;
    u_char         *copy_start;
    u_char         *copy_end;

    ngx_buf_t      *buf;

    ngx_chain_t    *in;
    ngx_chain_t    *out;
    ngx_chain_t   **last_out;
    ngx_chain_t    *free;
    ngx_chain_t    *busy;

    ngx_uint_t      state;
} ngx_http_remove_comment_ctx_t;


typedef enum {
    sw_start = 0,
    sw_state1,      /*   <           */
    sw_state2,      /*   <!          */
    sw_state3,      /*   <!-         */
    sw_state4,      /*   <!--        */
    sw_state5,      /*   <!-- -      */
    sw_state6,      /*   <!-- --     */
} ngx_http_remove_comment_state_e;


static ngx_int_t ngx_http_remove_comment_parse(ngx_http_request_t *r,
    ngx_http_remove_comment_ctx_t *ctx);
static ngx_int_t ngx_http_remove_comment_output(ngx_http_request_t *r,
    ngx_http_remove_comment_ctx_t *ctx);

static void *ngx_http_remove_comment_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_remove_comment_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);
static ngx_int_t ngx_http_remove_comment_filter_init(ngx_conf_t *cf);

static ngx_str_t ngx_http_remove_comment_default_types[] = {
    ngx_string("text/html")
};


static ngx_command_t  ngx_http_remove_comment_commands[] = {

    { ngx_string("remove_comment"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_remove_comment_loc_conf_t, enable),
      NULL },

    { ngx_string("comment_types"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_types_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_remove_comment_loc_conf_t, types_keys),
      &ngx_http_remove_comment_default_types[0] },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_remove_comment_filter_module_ctx = {
    NULL,                                        /* preconfiguration */
    ngx_http_remove_comment_filter_init,         /* postconfiguration */

    NULL,                                        /* create main configuration */
    NULL,                                        /* init main configuration */

    NULL,                                        /* create server configuration */
    NULL,                                        /* merge server configuration */

    ngx_http_remove_comment_create_loc_conf,     /* create location configuration */
    ngx_http_remove_comment_merge_loc_conf       /* merge location configuration */
};


ngx_module_t  ngx_http_remove_comment_filter_module = {
    NGX_MODULE_V1,
    &ngx_http_remove_comment_filter_module_ctx,  /* module context */
    ngx_http_remove_comment_commands,            /* module directives */
    NGX_HTTP_MODULE,                             /* module type */
    NULL,                                        /* init master */
    NULL,                                        /* init module */
    NULL,                                        /* init process */
    NULL,                                        /* init thread */
    NULL,                                        /* exit thread */
    NULL,                                        /* exit process */
    NULL,                                        /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_output_header_filter_pt ngx_http_next_header_filter;
static ngx_http_output_body_filter_pt   ngx_http_next_body_filter;


static ngx_int_t
ngx_http_remove_comment_header_filter(ngx_http_request_t *r)
{
    ngx_http_remove_comment_ctx_t      *ctx;
    ngx_http_remove_comment_loc_conf_t *conf;

    conf = ngx_http_get_module_loc_conf(r, ngx_http_remove_comment_filter_module);

    if (r->headers_out.status != NGX_HTTP_OK
        || r != r->main
        || (r->method & NGX_HTTP_HEAD)
        || !conf->enable
        || ngx_http_test_content_type(r, &conf->types) == NULL)
    {
        return ngx_http_next_header_filter(r);
    }

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_remove_comment_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_str_set(&ctx->head, "<!--");

    ngx_http_set_ctx(r, ctx, ngx_http_remove_comment_filter_module);

    r->filter_need_in_memory = 1;

    ngx_http_clear_content_length(r);
    ngx_http_clear_accept_ranges(r);

    return ngx_http_next_header_filter(r);
}


static ngx_int_t
ngx_http_remove_comment_body_filter(ngx_http_request_t *r, ngx_chain_t *in)
{
    ngx_int_t                           rc;
    ngx_buf_t                          *b;
    ngx_chain_t                        *cl;
    ngx_http_remove_comment_ctx_t      *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http remove comment filter");

    ctx = ngx_http_get_module_ctx(r, ngx_http_remove_comment_filter_module);
    if (ctx == NULL) {
        return ngx_http_next_body_filter(r, in);
     }

    if (in == NULL) {
        if (ctx->busy) {
            return ngx_http_remove_comment_output(r, ctx);

        } else {

            return ngx_http_next_body_filter(r, in);
        }
    }


    if (ngx_chain_add_copy(r->pool, &ctx->in, in) != NGX_OK) {
        return NGX_ERROR;
    }

    ctx->out = NULL;
    ctx->last_out = &ctx->out;

    while (ctx->in) {
        ctx->buf = ctx->in->buf;
        ctx->pos = ctx->buf->pos;
        ctx->in = ctx->in->next;

        b = NULL;

        ctx->copy_start = ctx->pos;
        ctx->copy_end = ctx->pos;

        while (ctx->pos < ctx->buf->last) {

            rc = ngx_http_remove_comment_parse(r, ctx);

            if (ctx->copy_start != ctx->copy_end) {

                if (ctx->saved) {
                    cl = ngx_chain_get_free_buf(r->pool, &ctx->free);
                    if (cl == NULL) {
                        return NGX_ERROR;
                    }

                    b = cl->buf;
                    ngx_memzero(b, sizeof(ngx_buf_t));

                    b->pos = ctx->head.data;
                    b->last = b->pos + ctx->saved;
                    b->memory = 1;

                    *ctx->last_out = cl;
                    ctx->last_out = &cl->next;

                    ctx->saved = 0;
                }

                cl = ngx_chain_get_free_buf(r->pool, &ctx->free);
                if (cl == NULL) {
                    return NGX_ERROR;
                }

                b = cl->buf;
                ngx_memcpy(b, ctx->buf, sizeof(ngx_buf_t));

                b->pos = ctx->copy_start;
                b->last = ctx->copy_end;
                b->shadow = NULL;
                b->last_buf = 0;
                b->recycled = 0;

                if (b->in_file) {
                    b->file_last = b->file_pos + (b->last - ctx->buf->pos);
                    b->file_pos += b->pos - ctx->buf->pos;
                }

                *ctx->last_out = cl;
                ctx->last_out = &cl->next;

            }

            ctx->copy_start = ctx->pos;
            ctx->copy_end = ctx->pos;
        }

        ctx->saved = (ctx->state < sw_state4) ? ctx->state : 0;   /*  */

        if (ctx->buf->last_buf && ctx->saved) {
            cl = ngx_chain_get_free_buf(r->pool, &ctx->free);
            if (cl == NULL) {
                return NGX_ERROR;
            }

            b = cl->buf;
            ngx_memzero(b, sizeof(ngx_buf_t));

            b->last_buf = 1;
            b->pos = ctx->head.data;
            b->last = b->pos + ctx->saved;
            b->memory = 1;

            *ctx->last_out = cl;
            ctx->last_out = &cl->next;
        }

        if (ctx->buf->last_buf || ngx_buf_in_memory(ctx->buf)) {
            if (b == NULL) {
                cl = ngx_chain_get_free_buf(r->pool, &ctx->free);
                if (cl == NULL) {
                    return NGX_ERROR;
                }

                b = cl->buf;
                ngx_memzero(b, sizeof(ngx_buf_t));

                b->sync = 1;

                *ctx->last_out = cl;
                ctx->last_out = &cl->next;
            }

            b->shadow = ctx->buf;
            b->last_buf = ctx->buf->last_buf;
            b->recycled = ctx->buf->recycled;

        }

        ctx->buf = NULL;
    }

    return ngx_http_remove_comment_output(r, ctx);
}


static ngx_int_t
ngx_http_remove_comment_output(ngx_http_request_t *r,
    ngx_http_remove_comment_ctx_t *ctx)
{
    ngx_int_t     rc;
    ngx_buf_t    *b;
    ngx_chain_t  *cl;

    rc = ngx_http_next_body_filter(r, ctx->out);

    if (ctx->busy == NULL) {
        ctx->busy = ctx->out;

    } else {

        for (cl = ctx->busy; cl->next; cl = cl->next) { /* void */ }
        cl->next = ctx->out;
    }

    ctx->out = NULL;
    ctx->last_out = &ctx->out;

    while (ctx->busy) {

        cl = ctx->busy;
        b = cl->buf;

        if (ngx_buf_size(b) != 0) {
            break;
        }

        if (b->shadow) {
            if (ngx_buf_in_memory(b->shadow)) {
                b->shadow->pos = b->shadow->last;
            }

            if (b->shadow->in_file) {
                b->shadow->file_pos = b->shadow->file_last;
            }
        }

        ctx->busy = cl->next;

        if (ngx_buf_in_memory(b) || b->in_file) {
            cl->next = ctx->free;
            ctx->free = cl;
        }
    }

    return rc;
}


static ngx_int_t ngx_http_remove_comment_parse(ngx_http_request_t *r,
    ngx_http_remove_comment_ctx_t *ctx)
{
    u_char                          *p, *last, ch;
    ngx_http_remove_comment_state_e  state;

    last = ctx->buf->last;
    state = ctx->state;

    for (p = ctx->pos; p < last; p++) {
        ch = *p;

        switch (state) {

        case sw_start:
            if (ch == '<') {
               state = sw_state1;
               ctx->copy_end = p;
               break;
            }

            ctx->copy_end = p + 1;
            break;

        /* < */
        case sw_state1:
            if (ch == '!') {
               state = sw_state2;
               break;
            }

            if (ch == '<') {
               state = sw_state1;
               ctx->copy_end = p;
               break;
            }

            state = sw_start;
            ctx->copy_end = p + 1;
            break;

        /* <! */
        case sw_state2:
            if (ch == '-') {
               state = sw_state3;
               break;
            }

            if (ch == '<') {
               state = sw_state1;
               ctx->copy_end = p;
               break;
            }

            state = sw_start;
            ctx->copy_end = p + 1;
            break;

        /* <!- */
        case sw_state3:
            if (ch == '-') {
               state = sw_state4;
               break;
            }

            if (ch == '<') {
               state = sw_state1;
               ctx->copy_end = p;
               break;
            }

            state = sw_start;
            ctx->copy_end = p + 1;
            break;

        /* <!-- */
        case sw_state4:
            if (ch == '-') {
               state = sw_state5;
               break;
            }

            break;

        /* <!-- - */
        case sw_state5:
            if (ch == '-') {
               state = sw_state6;
               break;
            }

            state = sw_state4;
            break;

        /* <!-- -- */
        case sw_state6:
            if (ch == '-') {
               break;
            }

            if (ch == '>') {
               ctx->pos = p + 1;
               ctx->state = sw_start;
               return NGX_OK;
            }

            state = sw_state4;
            break;
        }
    }

    ctx->pos = p;
    ctx->state = state;

    return NGX_AGAIN;
}


static void *
ngx_http_remove_comment_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_remove_comment_loc_conf_t *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_remove_comment_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->enable = 0;
     *     conf->types = { NULL };
     *     conf->types_keys = NULL;
     */

    conf->enable = NGX_CONF_UNSET;

    return conf;
}


static char *
ngx_http_remove_comment_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_remove_comment_loc_conf_t *prev = parent;
    ngx_http_remove_comment_loc_conf_t *conf = child;

    ngx_conf_merge_value(conf->enable, prev->enable, 0);

    if (ngx_http_merge_types(cf, &conf->types_keys, &conf->types,
                             &prev->types_keys, &prev->types,
                             ngx_http_remove_comment_default_types) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_remove_comment_filter_init(ngx_conf_t *cf)
{
    ngx_http_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_remove_comment_header_filter;

    ngx_http_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_remove_comment_body_filter;

    return NGX_OK;
}
