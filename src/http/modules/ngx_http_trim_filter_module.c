
/*
 *  Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#define NGX_HTTP_TRIM_FLAG      "http_trim"

#define NGX_HTTP_TRIM_SAVE_SLASH        -1
#define NGX_HTTP_TRIM_SAVE_JSCSS        -2
#define NGX_HTTP_TRIM_SAVE_SPACE        -3
#define NGX_HTTP_TRIM_SAVE_HACKCSS      -4
#define NGX_HTTP_TRIM_SAVE_JAVASCRIPT   -5

#define NGX_HTTP_TRIM_TAG_PRE            1
#define NGX_HTTP_TRIM_TAG_STYLE          2
#define NGX_HTTP_TRIM_TAG_SCRIPT         3
#define NGX_HTTP_TRIM_TAG_TEXTAREA       4

typedef struct {
    ngx_hash_t                   types;
    ngx_array_t                 *types_keys;

    ngx_http_complex_value_t    *js;
    ngx_http_complex_value_t    *css;
    ngx_http_complex_value_t    *trim;
} ngx_http_trim_loc_conf_t;


typedef struct {
    u_char          prev;

    ngx_chain_t    *in;
    ngx_chain_t    *free;
    ngx_chain_t    *busy;

    size_t          looked;
    size_t          saved_comment;

    ngx_int_t       tag;
    ngx_int_t       saved;
    ngx_int_t       count;
    ngx_uint_t      state;

    unsigned        js_enable:1;
    unsigned        css_enable:1;
} ngx_http_trim_ctx_t;


typedef enum {
    trim_state_text = 0,
    trim_state_text_whitespace,         /* \r \t ' ' */
    trim_state_tag,                     /* <  */
    trim_state_tag_text,
    trim_state_tag_attribute,
    trim_state_tag_whitespace,          /* \r \n \t ' ' */
    trim_state_tag_single_quote,        /* '  */
    trim_state_tag_double_quote,        /* "  */
    trim_state_tag_s,                   /* <s */
    trim_state_tag_pre_begin,           /* <pre */
    trim_state_tag_pre,
    trim_state_tag_pre_angle,
    trim_state_tag_pre_nest,
    trim_state_tag_pre_end,             /* <pre    </pre> */
    trim_state_tag_textarea_begin,      /* <textarea */
    trim_state_tag_textarea_end,        /* <textarea </textarea> */
    trim_state_tag_style_begin,         /* <style */
    trim_state_tag_style_end,           /* <style    </style> */
    trim_state_tag_style_css_end,       /* <style    </style> */
    trim_state_tag_style_css_text,      /* <style type="text/css" */
    trim_state_tag_style_css_whitespace,
    trim_state_tag_style_css_single_quote,
    trim_state_tag_style_css_single_quote_esc,
    trim_state_tag_style_css_double_quote,
    trim_state_tag_style_css_double_quote_esc,
    trim_state_tag_style_css_comment,
    trim_state_tag_style_css_comment_begin,
    trim_state_tag_style_css_comment_end,
    trim_state_tag_style_css_comment_begin_empty,
    trim_state_tag_style_css_comment_empty,
    trim_state_tag_style_css_comment_begin_hack,
    trim_state_tag_style_css_comment_hack,
    trim_state_tag_style_css_comment_hack_text,
    trim_state_tag_style_css_comment_hack_text_begin,
    trim_state_tag_style_css_comment_hack_text_end,
    trim_state_tag_style_css_comment_hack_text_last,
    trim_state_tag_script_begin,        /* <script */
    trim_state_tag_script_end,          /* <script   </script> */
    trim_state_tag_script_js_end,       /* <script   </script> */
    trim_state_tag_script_js_text,      /* <script type="text/javascript" */
    trim_state_tag_script_js_single_quote,
    trim_state_tag_script_js_single_quote_esc,
    trim_state_tag_script_js_double_quote,
    trim_state_tag_script_js_double_quote_esc,
    trim_state_tag_script_js_re_begin,
    trim_state_tag_script_js_re,
    trim_state_tag_script_js_re_esc,
    trim_state_tag_script_js_whitespace,
    trim_state_tag_script_js_comment_begin,
    trim_state_tag_script_js_single_comment,
    trim_state_tag_script_js_single_comment_end,
    trim_state_tag_script_js_multi_comment,
    trim_state_tag_script_js_multi_comment_end,
    trim_state_comment_begin,           /* <!-- */
    trim_state_comment_ie_begin,        /* <!--[if */
    trim_state_comment_hack_begin,
    trim_state_comment_end,             /* <!--  --> */
    trim_state_comment_ie_end,          /* <!--[if  <![endif]--> */
    trim_state_comment_hack_end,
} ngx_http_trim_state_e;



/* '(' ',' '=' ':' '[' '!' '&' '|' '?' ';' '>' '~' '*' '{' */

static uint32_t   trim_js_prefix[] = {
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
    0xec001542, /* 1110 1100 0000 0000  0001 0101 0100 0010 */

                /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
    0x08000000, /* 0000 1000 0000 0000  0000 0000 0000 0000 */

                /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
    0x58000000, /* 0101 1000 0000 0000  0000 0000 0000 0000 */

    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
};



/* ';' '>' '{' '}' ',' ':' */

static uint32_t   trim_css_prefix[] = {
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
    0x4c001000, /* 0100 1100 0000 0000  0001 0000 0000 0000 */

                /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
    0x28000000, /* 0010 1000 0000 0000  0000 0000 0000 0000 */

    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
};


static ngx_int_t ngx_http_trim_parse(ngx_http_request_t *r, ngx_buf_t *buf,
    ngx_http_trim_ctx_t *ctx);

static void *ngx_http_trim_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_trim_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);
static ngx_int_t ngx_http_trim_filter_init(ngx_conf_t *cf);


static ngx_command_t  ngx_http_trim_commands[] = {

    { ngx_string("trim"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_set_complex_value_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, trim),
      NULL },

    { ngx_string("trim_js"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_set_complex_value_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, js),
      NULL },

    { ngx_string("trim_css"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_set_complex_value_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, css),
      NULL },

    { ngx_string("trim_types"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_types_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, types_keys),
      &ngx_http_html_default_types[0] },

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
static ngx_str_t ngx_http_trim_style_css = ngx_string("text/css");
static ngx_str_t ngx_http_trim_script_js = ngx_string("text/javascript");
static ngx_str_t ngx_http_trim_comment = ngx_string("-->");
static ngx_str_t ngx_http_trim_textarea = ngx_string("</textarea>");
static ngx_str_t ngx_http_trim_comment_ie = ngx_string("[if");
static ngx_str_t ngx_http_trim_comment_ie_end = ngx_string("<![endif]-->");

static ngx_str_t ngx_http_trim_saved_html = ngx_string("<!--[if");
static ngx_str_t ngx_http_trim_saved_jscss = ngx_string("/**");
static ngx_str_t ngx_http_trim_saved_css_hack = ngx_string("/*\\*");


static ngx_int_t
ngx_http_trim_header_filter(ngx_http_request_t *r)
{
    ngx_int_t                  rc;
    ngx_str_t                  flag;
    ngx_http_trim_ctx_t       *ctx;
    ngx_http_trim_loc_conf_t  *conf;

    conf = ngx_http_get_module_loc_conf(r, ngx_http_trim_filter_module);

    if (!conf->trim
        || r->headers_out.status != NGX_HTTP_OK
        || (r->method & NGX_HTTP_HEAD)
        || r->headers_out.content_length_n == 0
        || (r->headers_out.content_encoding
            && r->headers_out.content_encoding->value.len)
        || ngx_http_test_content_type(r, &conf->types) == NULL)
    {
        return ngx_http_next_header_filter(r);
    }

    rc = ngx_http_arg(r, (u_char *) NGX_HTTP_TRIM_FLAG,
                      sizeof(NGX_HTTP_TRIM_FLAG) - 1, &flag);

    if(rc == NGX_OK
       && flag.len == sizeof("off") - 1
       && ngx_strncmp(flag.data, "off", sizeof("off") - 1) == 0)
    {
        return ngx_http_next_header_filter(r);
    }

    if (ngx_http_complex_value(r, conf->trim, &flag) != NGX_OK) {
        return NGX_ERROR;
    }

    if (!(flag.len == sizeof("on") - 1
          && ngx_strncmp(flag.data, "on", sizeof("on") - 1) == 0))
    {
        return ngx_http_next_header_filter(r);
    }

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_trim_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    if (conf->js) {
        if (ngx_http_complex_value(r, conf->js, &flag) != NGX_OK) {
            return NGX_ERROR;
        }

        if (flag.len == sizeof("on") - 1
            && ngx_strncmp(flag.data, "on", sizeof("on") - 1) == 0)
        {
            ctx->js_enable = 1;
        }
    }

    if (conf->css) {
        if (ngx_http_complex_value(r, conf->css, &flag) != NGX_OK) {
            return NGX_ERROR;
        }

        if (flag.len == sizeof("on") - 1
            && ngx_strncmp(flag.data, "on", sizeof("on") - 1) == 0)
        {
            ctx->css_enable = 1;
        }
    }

    ctx->prev = ' ';

    ngx_http_set_ctx(r, ctx, ngx_http_trim_filter_module);

    r->filter_need_temporary = 1;
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
            cl->buf->memory = 1;

            if (ctx->saved > 0) {
                cl->buf->pos = ngx_http_trim_saved_html.data;
                cl->buf->last = cl->buf->pos + ctx->saved;

            } else if (ctx->saved == NGX_HTTP_TRIM_SAVE_SLASH) {
                cl->buf->pos = ngx_http_trim_saved_jscss.data;
                cl->buf->last = cl->buf->pos + 1;

            } else if (ctx->saved == NGX_HTTP_TRIM_SAVE_SPACE) {
                cl->buf->pos = (u_char *) " ";
                cl->buf->last = cl->buf->pos + 1;

            } else if (ctx->saved == NGX_HTTP_TRIM_SAVE_JSCSS) {
                cl->buf->pos = ngx_http_trim_saved_jscss.data;
                cl->buf->last = cl->buf->pos + ngx_http_trim_saved_jscss.len;

            } else if (ctx->saved == NGX_HTTP_TRIM_SAVE_HACKCSS) {
                cl->buf->pos = ngx_http_trim_saved_css_hack.data;
                cl->buf->last = cl->buf->pos + ngx_http_trim_saved_css_hack.len;

            } else if (ctx->saved == NGX_HTTP_TRIM_SAVE_JAVASCRIPT) {
                cl->buf->pos = ngx_http_trim_script.data;
                cl->buf->last = cl->buf->pos + ngx_http_trim_script.len - 1;
            }

            *ll = cl;
            ll = &cl->next;

            ctx->saved = 0;
        }

        if(ln->buf->in_file
           && (ln->buf->file_last - ln->buf->file_pos)
               != (off_t) (ln->buf->last - ln->buf->pos))
        {
            ln->buf->in_file = 0;
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
                ll = &cl->next;

            }  else {
                if (ln->next == NULL) {
                    *ll = NULL;
                }
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

    for (write = buf->pos, read = buf->pos; read < buf->last; read++) {

        ch = ngx_tolower(*read);

        switch (ctx->state) {

        case trim_state_text:
            switch (ch) {
            case '\r':
                continue;
            case '\n':
                ctx->state = trim_state_text_whitespace;
                if (ctx->prev == '\n') {
                    continue;

                } else {
                    break;
                }
            case '\t':
            case ' ':
                ctx->state = trim_state_text_whitespace;
                continue;
            case '<':
                ctx->state = trim_state_tag;
                ctx->saved_comment = 1;
                continue;
            default:
                break;
            }
            break;

        case trim_state_tag:
            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                ctx->state = trim_state_text_whitespace;
                break;
            case '!':
                ctx->state = trim_state_comment_begin;
                ctx->looked = 0;        /* --> */
                ctx->saved_comment++;
                continue;
            case 'p':
                ctx->state = trim_state_tag_pre_begin;
                ctx->looked = 3;        /* </pre> */
                break;
            case 't':
                ctx->state = trim_state_tag_textarea_begin;
                ctx->looked = 3;       /* </textarea> */
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

            if ((size_t) (read - buf->pos) >= ctx->saved_comment) {
                write = ngx_cpymem(write, ngx_http_trim_saved_html.data,
                                   ctx->saved_comment);

            } else {
                ctx->saved = ctx->saved_comment;
            }

            if (ctx->state == trim_state_tag
                || ctx->state == trim_state_text_whitespace)
            {
               ctx->prev = '<';
               continue;
            }

            break;

        case trim_state_tag_text:
            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                ctx->state = trim_state_tag_whitespace;
                continue;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_attribute:
            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->prev != '=') {
                    ctx->state = trim_state_tag_whitespace;
                }
                continue;
            case '\'':
                ctx->state = trim_state_tag_single_quote;
                break;
            case '"':
                ctx->state = trim_state_tag_double_quote;
                break;
            case '>':
                if (ctx->tag == NGX_HTTP_TRIM_TAG_PRE) {
                    ctx->state = trim_state_tag_pre;

                } else if (ctx->tag == NGX_HTTP_TRIM_TAG_TEXTAREA) {
                    ctx->state = trim_state_tag_textarea_end;

                } else if (ctx->tag == NGX_HTTP_TRIM_TAG_SCRIPT) {
                    if (ctx->js_enable
                        && ctx->looked == ngx_http_trim_script_js.len)
                    {
                        ctx->state = trim_state_tag_script_js_text;

                    } else {
                        ctx->state = trim_state_tag_script_end;
                    }

                } else if (ctx->tag == NGX_HTTP_TRIM_TAG_STYLE) {
                    if (ctx->css_enable
                        && ctx->looked == ngx_http_trim_style_css.len)
                    {
                        ctx->state = trim_state_tag_style_css_text;

                    } else {
                        ctx->state = trim_state_tag_style_end;
                    }

                } else {
                    ctx->state = trim_state_text;
                }

                ctx->tag = 0;
                ctx->looked = 0;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_s:
            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                ctx->state = trim_state_tag_whitespace;
                continue;
            case 't':
                ctx->state = trim_state_tag_style_begin;
                ctx->looked = 4;    /* </style> */
                break;
            case 'c':
                ctx->state = trim_state_tag_script_begin;
                ctx->looked = 4;    /* </script> */
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
            look = ngx_http_trim_comment.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_comment.len - 1) { /* --> */
                    ctx->state = trim_state_comment_hack_begin;
                    ctx->looked = 0;
                }

                ctx->saved_comment++;
                continue;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                ctx->state = trim_state_tag_whitespace;
                continue;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }

            if ((size_t) (read - buf->pos) >= ctx->saved_comment) {
                write = ngx_cpymem(write, ngx_http_trim_saved_html.data,
                                   ctx->saved_comment);

            } else {
                ctx->saved = ctx->saved_comment;
            }

            break;

        case trim_state_comment_hack_begin:
            switch (ch) {
            case '#':
                ctx->state = trim_state_comment_hack_end;
                ctx->looked = 0;
                break;
            case 'e':
                ctx->state = trim_state_comment_hack_end;
                ctx->looked = 0;
                break;
            case '[':
                ctx->state = trim_state_comment_ie_begin;
                ctx->looked = 1;
                ctx->saved_comment++;
                continue;
            case '-':
                ctx->state = trim_state_comment_end;
                ctx->looked = 1;
                continue;
            default:
                ctx->state = trim_state_comment_end;
                ctx->looked = 0;
                continue;
            }

            if ((size_t) (read - buf->pos) >= ctx->saved_comment) {
                write = ngx_cpymem(write, ngx_http_trim_saved_html.data,
                                   ctx->saved_comment);

            } else {
                ctx->saved = ctx->saved_comment;
            }

            break;

        case trim_state_comment_ie_begin:
            look = ngx_http_trim_comment_ie.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_comment_ie.len) { /* [if */
                    ctx->state = trim_state_comment_ie_end;
                    ctx->looked = 0;

                    if ((size_t) (read - buf->pos) >= ctx->saved_comment) {
                        write = ngx_cpymem(write, ngx_http_trim_saved_html.data,
                                           ctx->saved_comment);

                    } else {
                         ctx->saved = ctx->saved_comment;
                    }

                    break;
                }

                ctx->saved_comment++;
                continue;
            }

            switch (ch) {
            case '-':
                ctx->state = trim_state_comment_end;
                ctx->looked = 1;
                break;
            default:
                ctx->state = trim_state_comment_end;
                ctx->looked = 0;
                break;
            }

            continue;

        case trim_state_tag_pre_begin:
            look = ngx_http_trim_pre.data[ctx->looked++];    /* <pre> */
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_pre.len) {
                    ctx->state = trim_state_tag_pre;
                    ctx->count = 1;
                    ctx->looked = 0;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_pre.len) {
                    ctx->tag = NGX_HTTP_TRIM_TAG_PRE;
                    ctx->count = 1;
                }

                ctx->state = trim_state_tag_whitespace;
                ctx->looked = 0;
                continue;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }
            break;

        case trim_state_tag_textarea_begin:
            look = ngx_http_trim_textarea.data[ctx->looked++]; /* <textarea> */
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_textarea.len) {
                    ctx->state = trim_state_tag_textarea_end;
                    ctx->looked = 0;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_textarea.len) {
                    ctx->tag = NGX_HTTP_TRIM_TAG_TEXTAREA;
                }

                ctx->state = trim_state_tag_whitespace;
                ctx->looked = 0;
                continue;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }
            break;

        case trim_state_tag_script_begin:
            look = ngx_http_trim_script.data[ctx->looked++];    /* <script> */
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_script.len) {
                    if (ctx->js_enable) {
                        ctx->state = trim_state_tag_script_js_text;

                    } else {
                        ctx->state = trim_state_tag_script_end;
                    }

                    ctx->looked = 0;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_script.len) {
                    ctx->tag = NGX_HTTP_TRIM_TAG_SCRIPT;
                }

                ctx->state = trim_state_tag_whitespace;
                ctx->looked = 0;
                continue;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }
            break;

        case trim_state_tag_script_js_text:
            switch (ch) {
            case '\r':
                continue;
            case '\n':
            case '\t':
            case ' ':
                ctx->state = trim_state_tag_script_js_whitespace;
                if (trim_js_prefix[ctx->prev >> 5] & (1 << (ctx->prev & 0x1f))
                    || ctx->prev == ch)
                {
                    continue;

                } else {
                    break;
                }
            case '\'':
                ctx->state = trim_state_tag_script_js_single_quote;
                break;
            case '"':
                ctx->state = trim_state_tag_script_js_double_quote;
                break;
            case '<':
                ctx->state = trim_state_tag_script_js_end;
                ctx->looked = 1;
                break;
            case '/':
                if (trim_js_prefix[ctx->prev >> 5] & (1 << (ctx->prev & 0x1f))
                    || ctx->prev == '+' || ctx->prev == '-')
                {
                    ctx->state = trim_state_tag_script_js_re_begin;

                } else {
                    ctx->state = trim_state_tag_script_js_comment_begin;
                }
                continue;
            default:
                break;
            }
            break;

        case trim_state_tag_script_js_single_quote:
            switch (ch) {
            case '\\':
                ctx->state = trim_state_tag_script_js_single_quote_esc;
                break;
            case '\'':
                ctx->state = trim_state_tag_script_js_text;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_script_js_double_quote:
            switch (ch) {
            case '\\':
                ctx->state = trim_state_tag_script_js_double_quote_esc;
                break;
            case '"':
                ctx->state = trim_state_tag_script_js_text;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_script_js_single_quote_esc:
            ctx->state = trim_state_tag_script_js_single_quote;
            break;

        case trim_state_tag_script_js_double_quote_esc:
            ctx->state = trim_state_tag_script_js_double_quote;
            break;

        case trim_state_tag_script_js_re_begin:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_script_js_single_comment;
                continue;
            case '*':
                ctx->state = trim_state_tag_script_js_multi_comment;
                continue;
            case '\\':
                ctx->state = trim_state_tag_script_js_re_esc;
                if (read > buf->pos) {
                    *write++ = '/';

                } else {
                    ctx->saved = NGX_HTTP_TRIM_SAVE_SLASH;
                }
                break;
            default:
                ctx->state = trim_state_tag_script_js_re;
                if (read > buf->pos) {
                    *write++ = '/';

                } else {
                    ctx->saved = NGX_HTTP_TRIM_SAVE_SLASH;
                }
                break;
             }
             break;

        case trim_state_tag_script_js_re:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_script_js_text;
                break;
            case '\\':
                ctx->state = trim_state_tag_script_js_re_esc;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_script_js_re_esc:
            ctx->state = trim_state_tag_script_js_re;
            break;

        case trim_state_tag_script_js_comment_begin:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_script_js_single_comment;
                continue;
            case '*':
                ctx->state = trim_state_tag_script_js_multi_comment;
                continue;
            default:
                ctx->state = trim_state_tag_script_js_text;
                if (read > buf->pos) {
                    *write++ = '/';

                } else {
                    ctx->saved = NGX_HTTP_TRIM_SAVE_SLASH;
                }
                break;
             }
             break;

        case trim_state_tag_script_js_single_comment:
            switch (ch) {
            case '<':
                ctx->looked = 1;
                ctx->state = trim_state_tag_script_js_single_comment_end;
                continue;
            case '\n':
                ctx->state = trim_state_tag_script_js_text;
                if (trim_js_prefix[ctx->prev >> 5] & (1 << (ctx->prev & 0x1f))
                    || ctx->prev == ch)
                {
                    continue;

                } else {
                    break;
                }
            default:
                continue;
            }
            break;

        case trim_state_tag_script_js_single_comment_end:
            look = ngx_http_trim_script.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_script.len) {
                    ctx->state = trim_state_text;
                    ctx->looked = 0;

                    if ((size_t) (read - buf->pos)
                        >= ngx_http_trim_script.len - 1)
                    {
                        write = ngx_cpymem(write, ngx_http_trim_script.data,
                                           ngx_http_trim_script.len - 1);

                    } else {
                        ctx->saved = NGX_HTTP_TRIM_SAVE_JAVASCRIPT;
                    }

                    break;
                }

                continue;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_script.len) {
                    ctx->state = trim_state_tag_whitespace;

                    if ((size_t) (read - buf->pos)
                        >= ngx_http_trim_script.len - 1)
                    {
                        write = ngx_cpymem(write, ngx_http_trim_script.data,
                                           ngx_http_trim_script.len - 1);

                    } else {
                        ctx->saved = NGX_HTTP_TRIM_SAVE_JAVASCRIPT;
                    }

                    ctx->prev = 't';
                    ctx->looked = 0;
                    continue;
                }
                ctx->looked = 0;
                break;
            case '<':
                ctx->looked = 1;
                break;
            default:
                ctx->state = trim_state_tag_script_js_single_comment;
                ctx->looked = 0;
                break;
            }

            continue;

        case trim_state_tag_script_js_multi_comment:
            switch (ch) {
            case '*':
                ctx->state = trim_state_tag_script_js_multi_comment_end;
                break;
            default:
                break;
            }
            continue;

        case trim_state_tag_script_js_multi_comment_end:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_script_js_text;
                break;
            case '*':
                break;
            default:
                ctx->state = trim_state_tag_script_js_multi_comment;
                break;
            }
            continue;

        case trim_state_tag_script_end:
            look = ngx_http_trim_script.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_script.len) {
                    ctx->state = trim_state_text;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_script.len) {
                    ctx->state = trim_state_tag_whitespace;
                    ctx->looked = 0;
                    continue;
                }

                ctx->looked = 0;
                break;
            case '<':
                ctx->looked = 1;
                break;
            default:
                ctx->looked = 0;
                break;
            }
            break;

        case trim_state_tag_script_js_end:
            look = ngx_http_trim_script.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_script.len) {
                    ctx->state = trim_state_text;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_script.len) {
                    ctx->state = trim_state_tag_whitespace;
                    ctx->looked = 0;
                    continue;
                }

                ctx->looked = 0;
                break;
            case '<':
                ctx->looked = 1;
                break;
            default:
                ctx->state = trim_state_tag_script_js_text;
                ctx->looked = 0;
                break;
            }
            break;

        case trim_state_tag_script_js_whitespace:
            switch (ch) {
            case '\n':
                if (trim_js_prefix[ctx->prev >> 5] & (1 << (ctx->prev & 0x1f))
                    || ctx->prev == ch)
                {
                    continue;

                } else {
                    break;
                }
            case '\r':
            case '\t':
            case ' ':
                 continue;
            case '\'':
                ctx->state = trim_state_tag_script_js_single_quote;
                break;
            case '"':
                ctx->state = trim_state_tag_script_js_double_quote;
                break;
            case '<':
                ctx->state = trim_state_tag_script_js_end;
                ctx->looked = 1;
                break;
            case '/':
                if (trim_js_prefix[ctx->prev >> 5] & (1 << (ctx->prev & 0x1f))
                    || ctx->prev == '+' || ctx->prev == '-')
                {
                    ctx->state = trim_state_tag_script_js_re_begin;

                } else {
                    ctx->state = trim_state_tag_script_js_comment_begin;
                }
                continue;
            default:
                ctx->state = trim_state_tag_script_js_text;
                break;
            }
            break;

        case trim_state_tag_style_begin:
            look = ngx_http_trim_style.data[ctx->looked++];    /* <style> */
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_style.len) {
                    if (ctx->css_enable) {
                        ctx->state = trim_state_tag_style_css_text;

                    } else {
                        ctx->state = trim_state_tag_style_end;
                    }

                    ctx->looked = 0;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_style.len) {
                    ctx->tag = NGX_HTTP_TRIM_TAG_STYLE;
                }

                ctx->state = trim_state_tag_whitespace;
                ctx->looked = 0;
                continue;
            case '>':
                ctx->state = trim_state_text;
                break;
            default:
                ctx->state = trim_state_tag_text;
                break;
            }
            break;

        case trim_state_tag_style_css_text:
            switch (ch) {
            case '\r':
                continue;
            case '\n':
            case '\t':
            case ' ':
                if (!(trim_css_prefix[ctx->prev >> 5] & (1 << (ctx->prev & 0x1f)))) {
                    ctx->state = trim_state_tag_style_css_whitespace;
                }
                continue;
            case '\'':
                ctx->state = trim_state_tag_style_css_single_quote;
                break;
            case '"':
                ctx->state = trim_state_tag_style_css_double_quote;
                break;
            case '<':
                ctx->state = trim_state_tag_style_css_end;
                ctx->looked = 1;
                break;
            case '/':
                ctx->state = trim_state_tag_style_css_comment_begin;
                continue;
            default:
                break;
            }
            break;

        case trim_state_tag_style_css_single_quote:
            switch (ch) {
            case '\\':
                ctx->state = trim_state_tag_style_css_single_quote_esc;
                break;
            case '\'':
                ctx->state = trim_state_tag_style_css_text;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_style_css_double_quote:
            switch (ch) {
            case '\\':
                ctx->state = trim_state_tag_style_css_double_quote_esc;
                break;
            case '"':
                ctx->state = trim_state_tag_style_css_text;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_style_css_single_quote_esc:
            ctx->state = trim_state_tag_style_css_single_quote;
            break;

        case trim_state_tag_style_css_double_quote_esc:
            ctx->state = trim_state_tag_style_css_double_quote;
            break;

        case trim_state_tag_style_css_comment_begin:
            switch (ch) {
            case '*':
                ctx->state = trim_state_tag_style_css_comment_begin_empty;
                continue;
            case '/':
                ctx->state = trim_state_tag_style_css_comment_begin;
                break;
            default:
                ctx->state = trim_state_tag_style_css_text;
                break;
            }

            if (read > buf->pos) {
                *write++ = '/';

            } else {
                ctx->saved = NGX_HTTP_TRIM_SAVE_SLASH;
            }

            if (ch == '/') {
                continue;

            }
            break;

        case trim_state_tag_style_css_comment_begin_empty:
            switch (ch) {
            case '*':
                ctx->state = trim_state_tag_style_css_comment_empty;
                break;
            case '\\':
                ctx->state = trim_state_tag_style_css_comment_begin_hack;
                break;
            default:
                ctx->state = trim_state_tag_style_css_comment;
                break;
            }
            continue;

        case trim_state_tag_style_css_comment:
            switch (ch) {
            case '*':
                ctx->state = trim_state_tag_style_css_comment_end;
                break;
            case '\\':
                ctx->state = trim_state_tag_style_css_comment_begin_hack;
                break;
            default:
                break;
            }
            continue;

        case trim_state_tag_style_css_comment_empty:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_style_css_text;

                if ((size_t) (read - buf->pos)
                    >= ngx_http_trim_saved_jscss.len)
                {
                    write = ngx_cpymem(write, ngx_http_trim_saved_jscss.data,
                                       ngx_http_trim_saved_jscss.len);

                } else {
                     ctx->saved = NGX_HTTP_TRIM_SAVE_JSCSS;
                }
                break;
            case '*':
                ctx->state = trim_state_tag_style_css_comment_end;
                continue;
            case '\\':
                ctx->state = trim_state_tag_style_css_comment_begin_hack;
                continue;
            default:
                ctx->state = trim_state_tag_style_css_comment;
                continue;
            }
            break;

        case trim_state_tag_style_css_comment_begin_hack:
            switch (ch) {
            case '*':
                ctx->state = trim_state_tag_style_css_comment_hack;
                break;
            default:
                ctx->state = trim_state_tag_style_css_comment;
                break;
            }
            continue;

        case trim_state_tag_style_css_comment_hack:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_style_css_comment_hack_text;

                if ((size_t) (read - buf->pos)
                    >= ngx_http_trim_saved_css_hack.len)
                {
                    write = ngx_cpymem(write, ngx_http_trim_saved_css_hack.data,
                                       ngx_http_trim_saved_css_hack.len);

                } else {
                    ctx->saved = NGX_HTTP_TRIM_SAVE_HACKCSS;
                }
                break;
            case '*':
                ctx->state = trim_state_tag_style_css_comment_end;
                continue;
            case '\\':
                ctx->state = trim_state_tag_style_css_comment_begin_hack;
                continue;
            default:
                ctx->state = trim_state_tag_style_css_comment;
                continue;
            }
            break;

        case trim_state_tag_style_css_comment_hack_text:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_style_css_comment_hack_text_begin;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_style_css_comment_hack_text_begin:
            switch (ch) {
            case '*':
                ctx->state = trim_state_tag_style_css_comment_hack_text_end;
                break;
            case '/':
                break;
            default:
                ctx->state = trim_state_tag_style_css_comment_hack_text;
                break;
            }
            break;

        case trim_state_tag_style_css_comment_hack_text_end:
            switch (ch) {
            case '*':
                ctx->state = trim_state_tag_style_css_comment_hack_text_last;
                break;
            default:
                continue;
            }
            break;

        case trim_state_tag_style_css_comment_hack_text_last:
            switch (ch) {
            case '*':
                ctx->state = trim_state_tag_style_css_comment_hack_text_last;
                break;
            case '/':
                ctx->state = trim_state_tag_style_css_text;
                break;
            default:
                ctx->state = trim_state_tag_style_css_comment_hack_text_end;
                break;
            }
            break;

        case trim_state_tag_style_css_comment_end:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_style_css_text;
                break;
            case '*':
                break;
            case '\\':
                ctx->state = trim_state_tag_style_css_comment_begin_hack;
                break;
            default:
                ctx->state = trim_state_tag_style_css_comment;
                break;
            }
            continue;

        case trim_state_tag_style_css_whitespace:
            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                 continue;
            case '\'':
                ctx->state = trim_state_tag_style_css_single_quote;
                break;
            case '"':
                ctx->state = trim_state_tag_style_css_double_quote;
                break;
            case '<':
                ctx->state = trim_state_tag_style_css_end;
                ctx->looked = 1;
                break;
            case '/':
                ctx->state = trim_state_tag_style_css_comment_begin;
                break;
            default:
                ctx->state = trim_state_tag_style_css_text;
                break;
            }

            if (!(trim_css_prefix[ch >> 5] & (1 << (ch & 0x1f)))) {
                if (read > buf->pos) {
                    *write++ = ' ';

                } else {
                    ctx->saved = NGX_HTTP_TRIM_SAVE_SPACE;
                }
            }

            if (ch == '/') {
                continue;
            }

            break;

        case trim_state_tag_style_end:
            look = ngx_http_trim_style.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_style.len) {
                    ctx->state = trim_state_text;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_style.len) {
                    ctx->state = trim_state_tag_whitespace;
                    ctx->looked = 0;
                    continue;
                }

                ctx->looked = 0;
                break;
            case '<':
                ctx->looked = 1;
                break;
            default:
                ctx->looked = 0;
                break;
            }
            break;

        case trim_state_tag_style_css_end:
            look = ngx_http_trim_style.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_style.len) {
                    ctx->state = trim_state_text;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_style.len) {
                    ctx->state = trim_state_tag_whitespace;
                    ctx->looked = 0;
                    continue;
                }

                ctx->looked = 0;
                break;
            case '<':
                ctx->looked = 1;
                break;
            default:
                ctx->state = trim_state_tag_style_css_text;
                ctx->looked = 0;
                break;
            }
            break;

        case trim_state_comment_end:
            look = ngx_http_trim_comment.data[ctx->looked++];  /* --> */
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_comment.len) {
                    ctx->state = trim_state_text;
                }
                continue;
            }

            switch (ch) {
            case '-':
                ctx->looked--;
                break;
            default:
                ctx->looked = 0;
                break;
            }
            continue;

        case trim_state_comment_ie_end:        /*  <![endif]-->  */
            look = ngx_http_trim_comment_ie_end.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_comment_ie_end.len) {
                    ctx->state = trim_state_text;
                }
                break;
            }

            switch (ch) {
            case '<':
                ctx->looked = 1;
                break;
            default:
                ctx->looked = 0;
                break;
            }
            break;

        case trim_state_comment_hack_end:
            look = ngx_http_trim_comment.data[ctx->looked++];  /* --> */
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_comment.len) {
                    ctx->state = trim_state_text;
                }
                break;
            }

            switch (ch) {
            case '-':
                ctx->looked--;
                break;
            default:
                ctx->looked = 0;
                break;
            }

            break;

        case trim_state_tag_pre:
            switch (ch) {
            case '<':
                ctx->state = trim_state_tag_pre_angle;
                break;
            default:
                break;
            }
            break;

        case trim_state_tag_pre_angle:
            switch (ch) {
            case '/':
                ctx->state = trim_state_tag_pre_end;
                ctx->looked = 2;
                break;
            case 'p':
                ctx->state = trim_state_tag_pre_nest;
                ctx->looked = 3;
                break;
            case '<':
                break;
            default:
                ctx->state = trim_state_tag_pre;
                break;
            }
            break;

        case trim_state_tag_pre_nest:
            look = ngx_http_trim_pre.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_pre.len) {
                    ctx->count++;
                    ctx->state = trim_state_tag_pre;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_pre.len) {
                    ctx->count++;
                    ctx->tag = NGX_HTTP_TRIM_TAG_PRE;
                    ctx->state = trim_state_tag_whitespace;
                    continue;

                } else {
                    ctx->state = trim_state_tag_pre;
                }

                break;
            case '<':
                ctx->state = trim_state_tag_pre_angle;
                break;
            default:
                ctx->state = trim_state_tag_pre;
                break;
            }
            break;

        case trim_state_tag_pre_end:
            look = ngx_http_trim_pre.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_pre.len) {
                    if (--ctx->count > 0) {
                        ctx->state = trim_state_tag_pre;

                    } else {
                        ctx->state = trim_state_text;
                    }
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_pre.len) {
                    if (--ctx->count > 0 ) {
                        ctx->tag = NGX_HTTP_TRIM_TAG_PRE;
                    }

                    ctx->state = trim_state_tag_whitespace;
                    ctx->looked = 0;
                    continue;
                }

                ctx->looked = 0;
                break;
            case '<':
                ctx->state = trim_state_tag_pre_angle;
                break;
            default:
                ctx->state = trim_state_tag_pre;
                break;
            }
            break;

        case trim_state_tag_textarea_end:
            look = ngx_http_trim_textarea.data[ctx->looked++];
            if (ch == look) {
                if (ctx->looked == ngx_http_trim_textarea.len) {
                    ctx->state = trim_state_text;
                }
                break;
            }

            switch (ch) {
            case '\r':
            case '\n':
            case '\t':
            case ' ':
                if (ctx->looked == ngx_http_trim_textarea.len) {
                    ctx->state = trim_state_tag_whitespace;
                    ctx->looked = 0;
                    continue;
                }

                ctx->looked = 0;
                break;
            case '<':
                ctx->looked = 1;
                break;
            default:
                ctx->looked = 0;
                break;
            }
            break;

        case trim_state_text_whitespace:
            switch (ch) {
            case '\r':
            case '\t':
            case ' ':
                continue;
            case '\n':
                if (ctx->prev == '\n') {
                    continue;

                } else {
                    break;
                }
            case '<':
                ctx->state = trim_state_tag;
                ctx->saved_comment = 1;
                break;
            default:
                ctx->state = trim_state_text;
                break;
            }

            if (ch != '\n' && ctx->prev != '\n') {
                if (read > buf->pos) {
                    *write++ = ' ';

                } else {
                    ctx->saved = NGX_HTTP_TRIM_SAVE_SPACE;
                }
            }

            if (ch == '<') {
                continue;
            }

            break;

        case trim_state_tag_whitespace:
            switch (ch) {
            case '\r':
            case '\n':
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
                if (ctx->tag == NGX_HTTP_TRIM_TAG_PRE) {
                    ctx->state = trim_state_tag_pre;

                } else if (ctx->tag == NGX_HTTP_TRIM_TAG_TEXTAREA) {
                    ctx->state = trim_state_tag_textarea_end;

                } else if (ctx->tag == NGX_HTTP_TRIM_TAG_SCRIPT) {
                    if (ctx->js_enable
                        && ctx->looked == ngx_http_trim_script_js.len)
                    {
                        ctx->state = trim_state_tag_script_js_text;

                    } else {
                        ctx->state = trim_state_tag_script_end;
                    }

                } else if (ctx->tag == NGX_HTTP_TRIM_TAG_STYLE) {
                    if (ctx->css_enable
                        && ctx->looked == ngx_http_trim_style_css.len)
                    {
                        ctx->state = trim_state_tag_style_css_text;

                    } else {
                        ctx->state = trim_state_tag_style_end;
                    }

                } else {
                    ctx->state = trim_state_text;
                }

                ctx->tag = 0;
                ctx->looked = 0;
                break;
            default:
                ctx->state = trim_state_tag_attribute;
                break;
            }

            if (ch != '>' && ch != '=') {
                if (read > buf->pos) {
                    *write++ = ' ';

                } else {
                    ctx->saved = NGX_HTTP_TRIM_SAVE_SPACE;
                }
            }

            break;

        case trim_state_tag_single_quote:
            switch (ch) {
            case '\'':
                ctx->state = trim_state_tag_attribute;
                break;
            default:
                break;
            }

            if (ctx->js_enable && ctx->tag == NGX_HTTP_TRIM_TAG_SCRIPT) {
                if (ctx->looked != ngx_http_trim_script_js.len) {
                    look = ngx_http_trim_script_js.data[ctx->looked++];
                    if (ch != look) {
                        ctx->looked = 0;
                    }
                }
            }

            if (ctx->css_enable && ctx->tag == NGX_HTTP_TRIM_TAG_STYLE) {
                if (ctx->looked != ngx_http_trim_style_css.len) {
                    look = ngx_http_trim_style_css.data[ctx->looked++];
                    if (ch != look) {
                        ctx->looked = 0;
                    }
                }
            }

            break;

        case trim_state_tag_double_quote:
            switch (ch) {
            case '"':
                ctx->state = trim_state_tag_attribute;
                break;
            default:
                break;
            }

            if (ctx->js_enable && ctx->tag == NGX_HTTP_TRIM_TAG_SCRIPT) {
                if (ctx->looked != ngx_http_trim_script_js.len) {
                    look = ngx_http_trim_script_js.data[ctx->looked++];
                    if (ch != look) {
                        ctx->looked = 0;
                    }
                }
            }

            if (ctx->css_enable && ctx->tag == NGX_HTTP_TRIM_TAG_STYLE) {
                if (ctx->looked != ngx_http_trim_style_css.len) {
                    look = ngx_http_trim_style_css.data[ctx->looked++];
                    if (ch != look) {
                        ctx->looked = 0;
                    }
                }
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
     *     conf->types = { NULL };
     *     conf->types_keys = NULL;
     *     conf->trim = NULL;
     *     conf->js = NULL;
     *     conf->css = NULL;
     */

    return conf;
}


static char *
ngx_http_trim_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_trim_loc_conf_t *prev = parent;
    ngx_http_trim_loc_conf_t *conf = child;

    if (ngx_http_merge_types(cf, &conf->types_keys, &conf->types,
                             &prev->types_keys, &prev->types,
                             ngx_http_html_default_types)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

    if (conf->trim == NULL) {
        conf->trim = prev->trim;
    }

    if (conf->js == NULL) {
        conf->js = prev->js;
    }

    if (conf->css == NULL) {
        conf->css = prev->css;
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
