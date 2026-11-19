/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */


/*
 * Self-contained HTTP response-header and body-drain parsers used by the
 * upstream health-check module. They intentionally depend only on a handful
 * of ngx primitives (ngx_buf_t, u_char, off_t, ngx_int_t, NGX_OK/AGAIN/ERROR
 * and CR/LF), so the same source can be compiled both into the production
 * module and into a stand-alone unit-test harness that stubs those primitives.
 *
 * All parsers are incremental: they consume [b->pos, b->last), advance b->pos,
 * and keep their cross-call state in numeric fields only (never in pointers
 * into the buffer, which the caller may reallocate between calls).
 */


#ifndef _NGX_HTTP_UPSTREAM_CHECK_HTTP_PARSE_H_INCLUDED_
#define _NGX_HTTP_UPSTREAM_CHECK_HTTP_PARSE_H_INCLUDED_


/* header-name matching targets (lower-case) */
#define NGX_CHECK_HDR_CL_STR    "content-length"
#define NGX_CHECK_HDR_CL_LEN    (sizeof(NGX_CHECK_HDR_CL_STR) - 1)
#define NGX_CHECK_HDR_TE_STR    "transfer-encoding"
#define NGX_CHECK_HDR_TE_LEN    (sizeof(NGX_CHECK_HDR_TE_STR) - 1)
#define NGX_CHECK_TE_CHUNKED    "chunked"
#define NGX_CHECK_TE_CHUNKED_LEN (sizeof(NGX_CHECK_TE_CHUNKED) - 1)


/* incremental state for the response-header parser */
typedef struct {
    ngx_uint_t   state;           /* header line state machine (see enum below) */
    off_t        content_length;  /* accumulated Content-Length value */
    ngx_uint_t   match_len;       /* header-name chars matched so far */
    ngx_uint_t   chunk_idx;       /* "chunked" token match progress in TE value */
    unsigned     maybe_cl:1;      /* current name may still be Content-Length */
    unsigned     maybe_te:1;      /* current name may still be Transfer-Encoding */
    unsigned     cur_is_cl:1;     /* current line is Content-Length */
    unsigned     cur_is_te:1;     /* current line is Transfer-Encoding */
    unsigned     seen_cl:1;       /* a Content-Length header was seen */
    unsigned     chunked:1;       /* Transfer-Encoding: chunked seen */
} ngx_http_check_headers_ctx_t;


enum {
    sw_h_start = 0,
    sw_h_name,
    sw_h_space_before_value,
    sw_h_value,
    sw_h_almost_done,          /* CR seen inside/after a header line */
    sw_h_header_almost_done    /* CR seen on the terminating empty line */
};


enum {
    sw_chunk_size = 0,             /* accumulating hex chunk size */
    sw_chunk_ext,                  /* skipping chunk extension until CR/LF */
    sw_chunk_size_almost_done,     /* expecting LF after the size-line CR */
    sw_chunk_data,                 /* discarding chunk-data bytes */
    sw_chunk_data_almost_done_cr,  /* expecting CR after chunk-data */
    sw_chunk_data_almost_done_lf,  /* expecting LF after chunk-data CR */
    sw_chunk_trailer,              /* between trailer lines after last-chunk */
    sw_chunk_trailer_line,         /* skipping a trailer header line */
    sw_chunk_trailer_almost_done   /* CR seen on the terminating empty line */
};


/*
 * Parse response headers incrementally, extracting Content-Length and whether
 * Transfer-Encoding is chunked. Returns:
 *   NGX_OK    - the terminating empty line was reached; b->pos points past it,
 *               h->content_length / h->chunked / h->seen_cl are final.
 *   NGX_AGAIN - more data is needed; b->pos advanced past consumed bytes.
 *   NGX_ERROR - malformed header framing (bare CR).
 */
static ngx_int_t
ngx_http_upstream_check_parse_headers(ngx_buf_t *b,
    ngx_http_check_headers_ctx_t *h)
{
    u_char        ch, c, *p;
    static const u_char  cl[] = NGX_CHECK_HDR_CL_STR;
    static const u_char  te[] = NGX_CHECK_HDR_TE_STR;
    static const u_char  ck[] = NGX_CHECK_TE_CHUNKED;

    for (p = b->pos; p < b->last; p++) {
        ch = *p;

        switch (h->state) {

        case sw_h_start:
            switch (ch) {
            case CR:
                h->state = sw_h_header_almost_done;
                break;
            case LF:
                goto headers_done;
            default:
                /* first byte of a new header name; reset per-line matching */
                h->state = sw_h_name;
                h->match_len = 0;
                h->maybe_cl = 1;
                h->maybe_te = 1;
                h->cur_is_cl = 0;
                h->cur_is_te = 0;
                goto name_char;
            }
            break;

        case sw_h_name:
        name_char:
            if (ch == ':') {
                if (h->maybe_cl && h->match_len == NGX_CHECK_HDR_CL_LEN) {
                    h->cur_is_cl = 1;
                } else if (h->maybe_te && h->match_len == NGX_CHECK_HDR_TE_LEN) {
                    h->cur_is_te = 1;
                }
                h->chunk_idx = 0;
                h->state = sw_h_space_before_value;
                break;
            }

            if (ch == CR) {
                h->state = sw_h_almost_done;
                break;
            }

            if (ch == LF) {
                /* tolerate a bare header line without a colon */
                h->state = sw_h_start;
                break;
            }

            c = (ch >= 'A' && ch <= 'Z') ? (u_char) (ch | 0x20) : ch;

            if (!(h->match_len < NGX_CHECK_HDR_CL_LEN
                  && c == cl[h->match_len]))
            {
                h->maybe_cl = 0;
            }

            if (!(h->match_len < NGX_CHECK_HDR_TE_LEN
                  && c == te[h->match_len]))
            {
                h->maybe_te = 0;
            }

            h->match_len++;
            break;

        case sw_h_space_before_value:
            if (ch == ' ' || ch == '\t') {
                break;
            }
            if (ch == CR) {
                h->state = sw_h_almost_done;
                break;
            }
            if (ch == LF) {
                h->state = sw_h_start;
                break;
            }
            h->state = sw_h_value;
            goto value_char;

        case sw_h_value:
        value_char:
            if (ch == CR) {
                h->state = sw_h_almost_done;
                break;
            }
            if (ch == LF) {
                h->state = sw_h_start;
                break;
            }

            if (h->cur_is_cl) {
                if (ch >= '0' && ch <= '9') {
                    h->content_length = h->content_length * 10 + (ch - '0');
                    h->seen_cl = 1;
                }

            } else if (h->cur_is_te) {
                c = (ch >= 'A' && ch <= 'Z') ? (u_char) (ch | 0x20) : ch;
                if (c == ck[h->chunk_idx]) {
                    h->chunk_idx++;
                    if (h->chunk_idx == NGX_CHECK_TE_CHUNKED_LEN) {
                        h->chunked = 1;
                    }
                } else {
                    h->chunk_idx = (c == ck[0]) ? 1 : 0;
                }
            }
            break;

        case sw_h_almost_done:
            if (ch == LF) {
                h->state = sw_h_start;
                break;
            }
            return NGX_ERROR;

        case sw_h_header_almost_done:
            if (ch == LF) {
                goto headers_done;
            }
            return NGX_ERROR;
        }
    }

    b->pos = p;
    return NGX_AGAIN;

headers_done:

    b->pos = p + 1;
    return NGX_OK;
}


/*
 * Discard a chunked response body incrementally. The chunk contents are not
 * retained (the health check only needs the connection drained). Returns:
 *   NGX_OK    - the last-chunk plus trailing empty line were consumed.
 *   NGX_AGAIN - more data is needed.
 *   NGX_ERROR - malformed chunk framing.
 * *state must start at sw_chunk_size and *remaining at 0.
 */
static ngx_int_t
ngx_http_upstream_check_chunked_drain(ngx_buf_t *b, ngx_uint_t *state,
    off_t *remaining)
{
    u_char  ch, *p;
    off_t   avail;

    for (p = b->pos; p < b->last; /* void */) {

        switch (*state) {

        case sw_chunk_size:
            ch = *p;
            if (ch >= '0' && ch <= '9') {
                *remaining = *remaining * 16 + (ch - '0');
                p++;
                break;
            }
            if (ch >= 'a' && ch <= 'f') {
                *remaining = *remaining * 16 + (ch - 'a' + 10);
                p++;
                break;
            }
            if (ch >= 'A' && ch <= 'F') {
                *remaining = *remaining * 16 + (ch - 'A' + 10);
                p++;
                break;
            }
            /* end of hex size; do not consume this byte */
            *state = sw_chunk_ext;
            break;

        case sw_chunk_ext:
            ch = *p;
            if (ch == CR) {
                *state = sw_chunk_size_almost_done;
                p++;
                break;
            }
            if (ch == LF) {
                p++;
                *state = (*remaining == 0) ? sw_chunk_trailer : sw_chunk_data;
                break;
            }
            /* skip chunk-extension byte */
            p++;
            break;

        case sw_chunk_size_almost_done:
            ch = *p;
            if (ch != LF) {
                return NGX_ERROR;
            }
            p++;
            *state = (*remaining == 0) ? sw_chunk_trailer : sw_chunk_data;
            break;

        case sw_chunk_data:
            avail = b->last - p;
            if (avail >= *remaining) {
                p += *remaining;
                *remaining = 0;
                *state = sw_chunk_data_almost_done_cr;
            } else {
                *remaining -= avail;
                p = b->last;
            }
            break;

        case sw_chunk_data_almost_done_cr:
            ch = *p;
            if (ch == CR) {
                *state = sw_chunk_data_almost_done_lf;
                p++;
                break;
            }
            if (ch == LF) {
                /* tolerate a lone LF after chunk-data */
                *state = sw_chunk_size;
                p++;
                break;
            }
            return NGX_ERROR;

        case sw_chunk_data_almost_done_lf:
            ch = *p;
            if (ch != LF) {
                return NGX_ERROR;
            }
            p++;
            *state = sw_chunk_size;
            break;

        case sw_chunk_trailer:
            ch = *p;
            if (ch == CR) {
                *state = sw_chunk_trailer_almost_done;
                p++;
                break;
            }
            if (ch == LF) {
                b->pos = p + 1;
                return NGX_OK;
            }
            /* a trailer header line begins */
            *state = sw_chunk_trailer_line;
            break;

        case sw_chunk_trailer_line:
            ch = *p;
            p++;
            if (ch == LF) {
                *state = sw_chunk_trailer;
            }
            break;

        case sw_chunk_trailer_almost_done:
            ch = *p;
            if (ch != LF) {
                return NGX_ERROR;
            }
            b->pos = p + 1;
            return NGX_OK;
        }
    }

    b->pos = p;
    return NGX_AGAIN;
}


/*
 * Drain response-body bytes from b, whichever framing the response uses, so
 * that both the initial pass over the buffer that already holds part of the
 * body and the later passes over freshly-read data go through one code path.
 * Advances b->pos past everything consumed. Returns:
 *   NGX_OK    - the body is fully drained; the connection is clean for reuse.
 *   NGX_AGAIN - more body bytes are still expected.
 *   NGX_ERROR - malformed chunk framing (chunked only).
 *
 * On the first call *remaining must hold the full Content-Length, or, when
 * chunked is set, *state must be sw_chunk_size and *remaining 0. Both are
 * carried across calls unchanged by the caller.
 */
static ngx_int_t
ngx_http_upstream_check_body_drain(ngx_buf_t *b, ngx_uint_t chunked,
    ngx_uint_t *state, off_t *remaining)
{
    off_t  avail;

    if (chunked) {
        return ngx_http_upstream_check_chunked_drain(b, state, remaining);
    }

    avail = b->last - b->pos;

    if (avail < *remaining) {
        b->pos = b->last;
        *remaining -= avail;
        return NGX_AGAIN;
    }

    b->pos += (size_t) *remaining;
    *remaining = 0;

    return NGX_OK;
}


#endif /* _NGX_HTTP_UPSTREAM_CHECK_HTTP_PARSE_H_INCLUDED_ */
