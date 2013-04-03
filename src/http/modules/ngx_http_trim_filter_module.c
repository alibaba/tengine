
/*
 *  Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


typedef struct {
    ngx_flag_t      trim_enable;
    ngx_flag_t      comment_enable;
    ngx_hash_t      types;
    ngx_array_t    *types_keys;
} ngx_http_trim_loc_conf_t;


typedef struct {
    ngx_str_t      *tag_name;

    u_char          prev;

    ngx_chain_t    *in;
    ngx_chain_t    *free;
    ngx_chain_t    *busy;

    size_t          saved;
    size_t          saved_comment;
    size_t          looked_tag;
    size_t          looked_comment;

    ngx_uint_t      state;
} ngx_http_trim_ctx_t;


typedef enum {
    trim_state_text = 0,
    trim_state_text_newline,            /* \n */
    trim_state_text_whitespace,         /* \r \f \t ' ' */
    trim_state_tag,                     /* <  */
    trim_state_tag_text,
    trim_state_tag_whitespace,          /* \r \n \f \t ' ' */
    trim_state_tag_single_quote,        /* '  */
    trim_state_tag_double_quote,        /* "  */
    trim_state_tag_s,                   /* <s */
    trim_state_tag_begin,               /* <tag_name */
    trim_state_tag_end,                 /* <tag_name  </tag_name> */
    trim_state_comment_begin,           /* <!-- */
    trim_state_comment_ie_begin,        /* <!--[if */
    trim_state_comment_end,             /* <!--  --> */
    trim_state_comment_ie_end,          /* <!--[if  <![endif]--> */
    trim_state_comment_whitespace,      /* \r \n \f \t ' ' */
} ngx_http_trim_state_e;


static ngx_int_t ngx_http_trim_parse(ngx_http_request_t *r, ngx_buf_t *buf,
    ngx_http_trim_ctx_t *ctx);

static void *ngx_http_trim_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_trim_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);
static ngx_int_t ngx_http_trim_filter_init(ngx_conf_t *cf);


static ngx_command_t  ngx_http_trim_commands[] = {

    { ngx_string("trim"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, trim_enable),
      NULL },

    { ngx_string("trim_comment"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, comment_enable),
      NULL },

    { ngx_string("trim_types"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_types_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, types_keys),
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_trim_filter_module_ctx = {
    NULL,                                    /* preconfiguration */
    ngx_http_trim_filter_init,               /* postconfiguration */

    NULL,                                    /* create main configuration */
    NULL,                                    /* init main configuration */

    NULL,                                    /* create server configuration */
    NULL,                                    /* merge server configuration */

    ngx_http_trim_create_loc_conf,           /* create location configuration */
    ngx_http_trim_merge_loc_conf             /* merge location configuration */
};


ngx_module_t  ngx_http_trim_filter_module = {
    NGX_MODULE_V1,
    &ngx_http_trim_filter_module_ctx,        /* module context */
    ngx_http_trim_commands,                  /* module directives */
    NGX_HTTP_MODULE,                         /* module type */
    NULL,                                    /* init master */
    NULL,                                    /* init module */
    NULL,                                    /* init process */
    NULL,                                    /* init thread */
    NULL,                                    /* exit thread */
    NULL,                                    /* exit process */
    NULL,                                    /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_output_header_filter_pt ngx_http_next_header_filter;
static ngx_http_output_body_filter_pt   ngx_http_next_body_filter;


static ngx_str_t ngx_http_trim_pre = ngx_string("</pre>");
static ngx_str_t ngx_http_trim_style = ngx_string("</style>");
static ngx_str_t ngx_http_trim_script = ngx_string("</script>");
static ngx_str_t ngx_http_trim_comment = ngx_string("-->");
static ngx_str_t ngx_http_trim_textarea = ngx_string("</textarea>");
static ngx_str_t ngx_http_trim_comment_ie = ngx_string("[if");
static ngx_str_t ngx_http_trim_comment_ie_end = ngx_string("<![endif]-->");

static ngx_str_t ngx_http_trim_saved = ngx_string("<!--[if");


static ngx_int_t
ngx_http_trim_header_filter(ngx_http_request_t *r)
{
    ngx_http_trim_ctx_t       *ctx;
    ngx_http_trim_loc_conf_t  *conf;

    conf = ngx_http_get_module_loc_conf(r, ngx_http_trim_filter_module);

    if (r->headers_out.status != NGX_HTTP_OK
        || (r->method & NGX_HTTP_HEAD)
        || r->headers_out.content_length_n == 0
        || !conf->trim_enable
        || (r->headers_out.content_encoding
            && r->headers_out.content_encoding->value.len)
        || ngx_http_test_content_type(r, &conf->types) == NULL)
    {
        return ngx_http_next_header_filter(r);
    }

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_trim_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->prev = '\n';

    ngx_http_set_ctx(r, ctx, ngx_http_trim_filter_module);

    r->main_filter_need_in_memory = 1;

    ngx_http_clear_content_length(r);
    ngx_http_clear_accept_ranges(r);

    return ngx_http_next_header_filter(r);
}


static ngx_int_t
ngx_http_trim_body_filter(ngx_http_request_t *r, ngx_chain_t *in)
{
    ngx_int_t             rc;
    ngx_chain_t          *cl, *ln, *out, **ll;
    ngx_http_trim_ctx_t  *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "http trim filter");

    ctx = ngx_http_get_module_ctx(r, ngx_http_trim_filter_module);
    if (ctx == NULL) {
        return ngx_http_next_body_filter(r, in);
    }

    if (in == NULL) {
        return ngx_http_next_body_filter(r, in);
    }

    ctx->in = NULL;
    if (ngx_chain_add_copy(r->pool, &ctx->in, in) != NGX_OK) {
        return NGX_ERROR;
    }

    out = NULL;
    ll = &out;

    for (ln = ctx->in; ln; ln = ln->next) {
        ngx_http_trim_parse(r, ln->buf, ctx);

        if (ctx->saved) {
            cl = ngx_chain_get_free_buf(r->pool, &ctx->free);
            if (cl == NULL) {
                return NGX_ERROR;
            }

            cl->buf->tag = (ngx_buf_tag_t) &ngx_http_trim_filter_module;
            cl->buf->temporary = 0;
            cl->buf->memory = 1;
            cl->buf->pos = ngx_http_trim_saved.data;
            cl->buf->last = cl->buf->pos + ctx->saved;

            *ll = cl;
            ll = &cl->next;

            ctx->saved = 0;
        }

        if (ngx_buf_size(ln->buf) == 0) {
            if (ln->buf->last_buf) {
                cl = ngx_chain_get_free_buf(r->pool, &ctx->free);
                if (cl == NULL) {
                    return NGX_ERROR;
                }

                ngx_memzero(cl->buf, sizeof(ngx_buf_t));
                cl->buf->tag = (ngx_buf_tag_t) &ngx_http_trim_filter_module;
                cl->buf->last_buf = 1;

                *ll = cl;
            }

        } else {
            *ll = ln;
            ll = &ln->next;
        }
    }

    if (out == NULL) {
        return NGX_OK;
    }

    rc = ngx_http_next_body_filter(r, out);

    ngx_chain_update_chains(r->pool, &ctx->free, &ctx->busy, &out,
                            (ngx_buf_tag_t) &ngx_http_trim_filter_module);

    return rc;
}


static ngx_int_t
ngx_http_trim_parse(ngx_http_request_t *r, ngx_buf_t *buf,
    ngx_http_trim_ctx_t *ctx)
{
    u_char                    *read, *write, ch, look;
    ngx_http_trim_loc_conf_t  *conf;

    conf = ngx_http_get_module_loc_conf(r, ngx_http_trim_filter_module);

    for (write = buf->pos, read = buf->pos; read < buf->last; read++) {

        ch = *read;
        ch = ngx_tolower(ch);

        switch (ctx->state) {

        case trim_state_text:
            switch (ch) {
            case '\r':
            case '\f':
            case '\t':
            case ' ':
                ctx->state = trim_state_text_whitespace;
                if (ctx->prev == '\n' || ctx->prev == ch) {
                    continue;

                } else {
                    break;
                }
            case '\n':
                ctx->state = trim_state_text_newline;
                if (ctx->prev == '\n') {
                    continue;

                } else {
                    break;
                }
            case '<':
                ctx->state = trim_state_tag;

                if (conf->comment_enable) {
                    ctx->saved_comment = 1;
                    continue;
                }

                break;
            default:
                break;
            }
            break;

        case trim_state_tag:
            switch (ch) {
            case '!':
                ctx->state = trim_state_comment_begin;
                ctx->looked_comment = 0;    /* --> */

                if (conf->comment_enable) {
                    ctx->saved_comment++;
                    continue;
                }

                break;
            case 'p':
                ctx->state = trim_state_tag_begin;
                ctx->tag_name = &ngx_http_trim_pre;
                ctx->looked_tag = 3;    /* </pre> */
                break;
            case 't':
                ctx->state = trim_state_tag_begin;
                ctx->tag_name = &ngx_http_trim_textarea;
                ctx->looked_tag = 3;    /* </textarea> */
                break;
            case 's':
                ctx->state = trim_state_tag_s;
                break;
            case '<':
                break;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                if ((ch >= 'a' && ch <= 'z') || ch == '/') {
                    ctx->state = trim_state_tag_text;

                } else {
                    ctx->state = trim_state_text;
                }
                break;
            }

            if (conf->comment_enable) {
                if ((size_t) (read - buf->pos) >= ctx->saved_comment) {
                    write = ngx_cpymem(write, ngx_http_trim_saved.data,
                                       ctx->saved_comment);

                } else {
                    ctx->saved = ctx->saved_comment;
                }
            }

            if (conf->comment_enable && ch == '<') {
                continue;
            }

            break;

        case trim_state_tag_text:
            switch (ch) {
            case '\r':
            case '\n':
            case '\f':
            case '\t':
            case ' ':
                *read = ' ';
                ctx->state = trim_state_tag_whitespace;
                break;
            case '\'':
                ctx->state = trim_state_tag_single_quote;
                break;
            case '"':
                ctx->state = trim_state_tag_double_quote;
                break;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_s:
            switch (ch) {
            case '\r':
            case '\n':
            case '\f':
            case '\t':
            case ' ':
                *read = ' ';
                ctx->state = trim_state_tag_whitespace;
                break;
            case 't':
                ctx->state = trim_state_tag_begin;
                ctx->tag_name = &ngx_http_trim_style;
                ctx->looked_tag = 4;    /* </style> */
                break;
            case 'c':
                ctx->state = trim_state_tag_begin;
                ctx->tag_name = &ngx_http_trim_script;
                ctx->looked_tag = 4;    /* </script> */
                break;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }
            break;

        case trim_state_comment_begin:
            look = ngx_http_trim_comment.data[ctx->looked_comment++];
            if (ch == look) {
                if (ctx->looked_comment == ngx_http_trim_comment.len - 1) { /* --> */
                    ctx->state = trim_state_comment_ie_begin;
                    ctx->looked_comment = 0;
                }

                if (conf->comment_enable) {
                    ctx->saved_comment++;
                    continue;
                }

                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\f':
            case '\t':
            case ' ':
                *read = ' ';
                ctx->state = trim_state_tag_whitespace;
                break;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }

            if (conf->comment_enable) {
                if ((size_t) (read - buf->pos) >= ctx->saved_comment) {
                    write = ngx_cpymem(write, ngx_http_trim_saved.data,
                                       ctx->saved_comment);

                } else {
                    ctx->saved = ctx->saved_comment;
                }
            }

            break;

        case trim_state_comment_ie_begin:
            look = ngx_http_trim_comment_ie.data[ctx->looked_comment++];
            if (ch == look) {
                if (ctx->looked_comment == ngx_http_trim_comment_ie.len) { /* [if */
                    ctx->state = trim_state_comment_ie_end;
                    ctx->looked_comment = 0;

                    if (conf->comment_enable) {
                        if ((size_t) (read - buf->pos) >= ctx->saved_comment) {
                           write = ngx_cpymem(write, ngx_http_trim_saved.data,
                                             ctx->saved_comment);

                        } else {
                            ctx->saved = ctx->saved_comment;
                        }
                    }
                    break;

                }

                if (conf->comment_enable) {
                    ctx->saved_comment++;
                    continue;
                }

                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\f':
            case '\t':
            case ' ':
                ctx->state = trim_state_comment_whitespace;
                ctx->looked_comment = 0;
                break;
            case '-':
                ctx->state = trim_state_comment_end;
                ctx->looked_comment = 1;
                break;
            default:
                ctx->state = trim_state_comment_end;
                ctx->looked_comment = 0;
                break;
            }

            if (conf->comment_enable) {
                continue;
            }

            break;

        case trim_state_tag_begin:
            look = ctx->tag_name->data[ctx->looked_tag++];    /* <tag_name> */
            if (ch == look) {
                if (ctx->looked_tag == ctx->tag_name->len) {
                    ctx->state = trim_state_tag_end;
                    ctx->looked_tag = 0;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\f':
            case '\t':
            case ' ':
                *read = ' ';
                if (ctx->looked_tag == ctx->tag_name->len) {
                    ctx->state = trim_state_tag_end;
                    ctx->looked_tag = 0;

                } else {
                    ctx->state = trim_state_tag_whitespace;
                }
                break;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }
            break;

        case trim_state_comment_end:
            look = ngx_http_trim_comment.data[ctx->looked_comment++];
            if (ch == look) {
                if (ctx->looked_comment == ngx_http_trim_comment.len) {
                    ctx->state = trim_state_text;
                }

            } else {
                switch (ch) {
                case '\r':
                case '\n':
                case '\f':
                case '\t':
                case ' ':
                    ctx->state = trim_state_comment_whitespace;
                    ctx->looked_comment = 0;
                    break;
                case '-':
                    ctx->looked_comment--;
                    break;
                default:
                    ctx->looked_comment = 0;
                    break;
                }
            }

            if (conf->comment_enable) {
                continue;
            }

            break;

        case trim_state_comment_ie_end:
            look = ngx_http_trim_comment_ie_end.data[ctx->looked_comment++];
            if (ch == look) {
                if (ctx->looked_comment == ngx_http_trim_comment_ie_end.len) {
                    ctx->state = trim_state_text;
                }

            } else {
                ctx->looked_comment = 0;
            }
            break;

        case trim_state_tag_end:
            look = ctx->tag_name->data[ctx->looked_tag++];
            if (ch == look) {
                if (ctx->looked_tag == ctx->tag_name->len) {
                    ctx->state = trim_state_text;
                }

            } else {
                ctx->looked_tag = 0;
            }
            break;

        case trim_state_text_whitespace:
            switch (ch) {
            case '\r':
            case '\f':
            case '\t':
            case ' ':
                continue;
            case '\n':
                ctx->state = trim_state_text_newline;
                if (ctx->prev == '\n') {
                    continue;

                } else {
                    break;
                }
            case '<':
                ctx->state = trim_state_tag;

                if (conf->comment_enable) {
                    ctx->saved_comment = 1;
                    continue;
                }

                break;
            default:
                ctx->state = trim_state_text;
                break;
            }
            break;

        case trim_state_tag_whitespace:
            switch (ch) {
            case '\r':
            case '\n':
            case '\f':
            case '\t':
            case ' ':
                continue;
            case '\'':
                ctx->state = trim_state_tag_single_quote;
                break;
            case '"':
                ctx->state = trim_state_tag_double_quote;
                break;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }
            break;

        case trim_state_comment_whitespace:
            switch (ch) {
            case '\r':
            case '\n':
            case '\f':
            case '\t':
            case ' ':
                continue;
            case '-':
                ctx->state = trim_state_comment_end;
                ctx->looked_comment++;
                break;
            default:
                ctx->state = trim_state_comment_end;
                break;
            }

            if (conf->comment_enable) {
                continue;
            }
            break;

        case trim_state_tag_single_quote:
            switch (ch) {
            case '\'':
                ctx->state = trim_state_tag_text;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_double_quote:
            switch (ch) {
            case '"':
                ctx->state = trim_state_tag_text;
                break;
            default:
                break;
            }
            break;

        case trim_state_text_newline:
            switch (ch) {
            case '\r':
            case '\n':
            case '\f':
            case '\t':
            case ' ':
                continue;
            case '<':
                ctx->state = trim_state_tag;

                if (conf->comment_enable) {
                    ctx->saved_comment = 1;
                    continue;
                }

                break;
            default:
                ctx->state = trim_state_text;
                break;
            }
            break;

        default:
            break;
        }

        *write++ = *read;
        ctx->prev = *read;
    }

    buf->last = write;
    return NGX_OK;
}


static void *
ngx_http_trim_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_trim_loc_conf_t *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_trim_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->trim_enable = 0;
     *     conf->comment_enable = 0;
     *     conf->types = { NULL };
     *     conf->types_keys = NULL;
     */

    conf->trim_enable = NGX_CONF_UNSET;
    conf->comment_enable = NGX_CONF_UNSET;

    return conf;
}


static char *
ngx_http_trim_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_trim_loc_conf_t *prev = parent;
    ngx_http_trim_loc_conf_t *conf = child;

    ngx_conf_merge_value(conf->trim_enable, prev->trim_enable, 0);
    ngx_conf_merge_value(conf->comment_enable, prev->comment_enable, 0);

    if (ngx_http_merge_types(cf, &conf->types_keys, &conf->types,
                             &prev->types_keys, &prev->types,
                             ngx_http_html_default_types)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_trim_filter_init(ngx_conf_t *cf)
{
    ngx_http_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_trim_header_filter;

    ngx_http_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_trim_body_filter;

    return NGX_OK;
}
