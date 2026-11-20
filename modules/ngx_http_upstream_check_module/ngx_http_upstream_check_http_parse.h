/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */


/*
 * Self-contained HTTP response-header and body-drain parsers used by the
 * upstream health-check module. They intentionally depend only on a handful
 * of ngx primitives (ngx_buf_t, u_char, off_t, ngx_int_t, NGX_OK/AGAIN/ERROR,
 * NGX_MAX_OFF_T_VALUE and CR/LF), so the same source can be compiled both into
 * the production module and into a stand-alone unit-test harness that stubs
 * those primitives.
 *
 * Every byte parsed here comes from the checked peer and is untrusted: numeric
 * values are bounded before they are accumulated, and lookup tables are never
 * indexed by a counter the input can push past their end.
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

/*
 * chunk_idx values past a matched prefix of "chunked": the current
 * Transfer-Encoding list element is "chunked" followed by whitespace, or it is
 * anything else. The "chunked" table is only indexed below
 * NGX_CHECK_TE_CHUNKED_LEN, so these never reach it.
 */
#define NGX_CHECK_TE_CHUNKED_OWS (NGX_CHECK_TE_CHUNKED_LEN + 1)
#define NGX_CHECK_TE_OTHER       (NGX_CHECK_TE_CHUNKED_LEN + 2)


/* incremental state for the response-header parser */
typedef struct {
    ngx_uint_t   state;           /* header line state machine (see enum below) */
    off_t        content_length;  /* accumulated Content-Length value */
    ngx_uint_t   match_len;       /* header-name chars matched so far */
    ngx_uint_t   chunk_idx;       /* "chunked" match state of the current
                                     Transfer-Encoding list element */
    unsigned     maybe_cl:1;      /* current name may still be Content-Length */
    unsigned     maybe_te:1;      /* current name may still be Transfer-Encoding */
    unsigned     cur_is_cl:1;     /* current line is Content-Length */
    unsigned     cur_is_te:1;     /* current line is Transfer-Encoding */
    unsigned     seen_cl:1;       /* a Content-Length header was seen */
    unsigned     seen_te:1;       /* a Transfer-Encoding header was seen */
    unsigned     chunked:1;       /* the final transfer coding is chunked */
    unsigned     cl_digits:1;     /* current Content-Length value has digits */
    unsigned     cl_ows:1;        /* whitespace followed those digits */
    unsigned     bad_framing:1;   /* Content-Length cannot be trusted */
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
 * Most iterations of the chunked-drain loop consume a byte. A few only move to
 * the next state and leave the read pointer where it is: a chunk size that
 * ended, a trailer line that begins, an empty chunk. None of those states then
 * stands still again, so more than two pointer-less steps in a row mean the
 * state machine has stopped making sense. Refusing to go on is what keeps a
 * hostile body from spinning the worker forever (CWE-835).
 */
#define NGX_CHECK_CHUNK_MAX_STALL  2


/*
 * A Transfer-Encoding list element ended (at a comma or at the end of the
 * line). Empty elements are allowed by the list syntax and do not count; any
 * other element decides whether the final coding seen so far is chunked.
 */
static void
ngx_http_upstream_check_te_element_done(ngx_http_check_headers_ctx_t *h)
{
    if (h->chunk_idx == 0) {
        return;
    }

    h->chunked = (h->chunk_idx == NGX_CHECK_TE_CHUNKED_LEN
                  || h->chunk_idx == NGX_CHECK_TE_CHUNKED_OWS);
    h->chunk_idx = 0;
}


/* the value of the current header line ended */
static void
ngx_http_upstream_check_header_value_done(ngx_http_check_headers_ctx_t *h)
{
    if (h->cur_is_cl && !h->cl_digits) {
        /* an empty Content-Length */
        h->bad_framing = 1;
    }

    if (h->cur_is_te) {
        ngx_http_upstream_check_te_element_done(h);
    }
}


/*
 * Parse response headers incrementally, extracting Content-Length and whether
 * the final Transfer-Encoding is chunked. Returns:
 *   NGX_OK    - the terminating empty line was reached; b->pos points past it,
 *               h->content_length / h->chunked / h->seen_cl / h->seen_te /
 *               h->bad_framing are final.
 *   NGX_AGAIN - more data is needed; b->pos advanced past consumed bytes.
 *   NGX_ERROR - malformed header framing (bare CR).
 *
 * A Content-Length that is empty, not a plain decimal number, does not fit in
 * off_t, or is repeated sets h->bad_framing rather than failing the parse: the
 * check verdict comes from the status line, only the connection must not be
 * reused.
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
                    if (h->seen_cl) {
                        /* a repeated Content-Length */
                        h->bad_framing = 1;
                    }
                    h->seen_cl = 1;
                    h->content_length = 0;
                    h->cl_digits = 0;
                    h->cl_ows = 0;
                } else if (h->maybe_te && h->match_len == NGX_CHECK_HDR_TE_LEN) {
                    h->cur_is_te = 1;
                    h->seen_te = 1;
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
                ngx_http_upstream_check_header_value_done(h);
                h->state = sw_h_almost_done;
                break;
            }
            if (ch == LF) {
                ngx_http_upstream_check_header_value_done(h);
                h->state = sw_h_start;
                break;
            }
            h->state = sw_h_value;
            goto value_char;

        case sw_h_value:
        value_char:
            if (ch == CR) {
                ngx_http_upstream_check_header_value_done(h);
                h->state = sw_h_almost_done;
                break;
            }
            if (ch == LF) {
                ngx_http_upstream_check_header_value_done(h);
                h->state = sw_h_start;
                break;
            }

            if (h->cur_is_cl) {
                if (ch >= '0' && ch <= '9') {
                    if (h->cl_ows
                        || h->content_length
                           > (NGX_MAX_OFF_T_VALUE - (ch - '0')) / 10)
                    {
                        /* digits split by whitespace, or off_t overflow */
                        h->bad_framing = 1;
                        break;
                    }
                    h->content_length = h->content_length * 10 + (ch - '0');
                    h->cl_digits = 1;

                } else if (ch == ' ' || ch == '\t') {
                    h->cl_ows = h->cl_digits;

                } else {
                    h->bad_framing = 1;
                }

            } else if (h->cur_is_te) {
                if (ch == ',') {
                    ngx_http_upstream_check_te_element_done(h);

                } else if (ch == ' ' || ch == '\t') {
                    /* whitespace may only follow a complete element */
                    if (h->chunk_idx == NGX_CHECK_TE_CHUNKED_LEN) {
                        h->chunk_idx = NGX_CHECK_TE_CHUNKED_OWS;

                    } else if (h->chunk_idx > 0
                               && h->chunk_idx < NGX_CHECK_TE_CHUNKED_LEN)
                    {
                        h->chunk_idx = NGX_CHECK_TE_OTHER;
                    }

                } else {
                    c = (ch >= 'A' && ch <= 'Z') ? (u_char) (ch | 0x20) : ch;
                    if (h->chunk_idx < NGX_CHECK_TE_CHUNKED_LEN
                        && c == ck[h->chunk_idx])
                    {
                        h->chunk_idx++;
                    } else {
                        h->chunk_idx = NGX_CHECK_TE_OTHER;
                    }
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
 *   NGX_ERROR - malformed chunk framing, or a *state outside the enum above.
 * *state must start at sw_chunk_size and *remaining at 0.
 *
 * The loop advances its read pointer by hand, so every iteration is required
 * to make progress -- consume a byte, or move to a different state within the
 * NGX_CHECK_CHUNK_MAX_STALL budget -- and the check after the switch enforces
 * that at run time instead of leaving it to inspection.
 */
static ngx_int_t
ngx_http_upstream_check_chunked_drain(ngx_buf_t *b, ngx_uint_t *state,
    off_t *remaining)
{
    u_char      ch, c, *p, *prev;
    off_t       avail;
    ngx_uint_t  prev_state, stall;

    stall = 0;

    for (p = b->pos; p < b->last; /* void */) {
        prev = p;
        prev_state = *state;

        switch (*state) {

        case sw_chunk_size:
            ch = *p;
            c = (u_char) (ch | 0x20);
            if ((ch >= '0' && ch <= '9') || (c >= 'a' && c <= 'f')) {
                if (*remaining > NGX_MAX_OFF_T_VALUE / 16) {
                    /*
                     * The size does not fit in off_t. Letting it wrap would
                     * go negative and move p backwards in sw_chunk_data.
                     */
                    return NGX_ERROR;
                }
                *remaining = *remaining * 16
                             + ((ch <= '9') ? ch - '0' : c - 'a' + 10);
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
            if (*remaining < 0) {
                /*
                 * The count is added to p below, so a negative one would move
                 * p before b->start and read out of bounds. Callers bound what
                 * they store here, but the bound belongs next to the
                 * arithmetic that needs it.
                 */
                return NGX_ERROR;
            }

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

        default:
            /*
             * A state this parser does not know: no case would run, so the
             * pointer would never move and the loop would never end.
             */
            return NGX_ERROR;
        }

        if (p > prev) {
            /* bytes were consumed; the state budget starts over */
            stall = 0;
            continue;
        }

        if (p < prev || *state == prev_state) {
            /* walked back out of the buffer, or stood still in a state */
            return NGX_ERROR;
        }

        if (++stall > NGX_CHECK_CHUNK_MAX_STALL) {
            /* state-only steps chaining without ever consuming a byte */
            return NGX_ERROR;
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
 *   NGX_ERROR - malformed chunk framing (chunked only), or a negative
 *               *remaining.
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

    if (*remaining < 0) {
        /*
         * A negative byte count is not a byte count: both the Content-Length
         * branch below and sw_chunk_data add it to a pointer, so it would move
         * that pointer before b->start and read out of bounds. Every caller
         * stores a bounded, non-negative length here, so this only trips on a
         * bug; refuse to drain instead of trusting the value.
         */
        return NGX_ERROR;
    }

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
