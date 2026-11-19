/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for the upstream health-check HTTP response parsers
 * (ngx_http_upstream_check_http_parse.h).
 *
 * The header depends only on a few ngx primitives; we stub them here so the
 * exact same parser source that ships in the module is exercised in isolation,
 * with no nginx build required:
 *
 *     cc -Wall -Wextra -o test_check_http_parse test_check_http_parse.c
 *     ./test_check_http_parse
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <sys/types.h>   /* off_t */

/* --- minimal ngx compatibility layer --------------------------------- */

typedef unsigned char   u_char;
typedef intptr_t        ngx_int_t;
typedef uintptr_t       ngx_uint_t;

#define NGX_OK       0
#define NGX_ERROR   -1
#define NGX_AGAIN   -2

#define CR  '\r'
#define LF  '\n'

typedef struct {
    u_char  *pos;
    u_char  *last;
    u_char  *start;
    u_char  *end;
} ngx_buf_t;

#include "../ngx_http_upstream_check_http_parse.h"

/* --- tiny test framework --------------------------------------------- */

static int tests_run = 0;
static int tests_failed = 0;

#define CHECK(cond, msg)                                                      \
    do {                                                                      \
        tests_run++;                                                          \
        if (!(cond)) {                                                        \
            tests_failed++;                                                   \
            printf("FAIL: %s (%s:%d)\n", (msg), __FILE__, __LINE__);          \
        }                                                                     \
    } while (0)

/* --- helpers --------------------------------------------------------- */

/* Parse headers from a fully-available buffer. */
static ngx_int_t
run_headers(const char *s, ngx_http_check_headers_ctx_t *h)
{
    ngx_buf_t b;

    memset(h, 0, sizeof(*h));
    b.start = b.pos = (u_char *) s;
    b.last = (u_char *) s + strlen(s);
    b.end = b.last;

    return ngx_http_upstream_check_parse_headers(&b, h);
}

/* Parse headers fed one byte at a time (incremental / fragmented arrival). */
static ngx_int_t
run_headers_drip(const char *s, ngx_http_check_headers_ctx_t *h)
{
    ngx_buf_t  b;
    ngx_int_t  rc = NGX_AGAIN;
    size_t     i, len = strlen(s);

    memset(h, 0, sizeof(*h));
    b.start = b.pos = (u_char *) s;
    b.last = (u_char *) s;
    b.end = (u_char *) s + len;

    for (i = 0; i < len; i++) {
        b.last = (u_char *) s + i + 1;
        rc = ngx_http_upstream_check_parse_headers(&b, h);
        if (rc != NGX_AGAIN) {
            break;
        }
    }

    return rc;
}

/* Drain a chunked body from a fully-available buffer. */
static ngx_int_t
run_chunked(const char *s, size_t len)
{
    ngx_buf_t   b;
    ngx_uint_t  state = sw_chunk_size;
    off_t       rem = 0;

    b.start = b.pos = (u_char *) s;
    b.last = (u_char *) s + len;
    b.end = b.last;

    return ngx_http_upstream_check_chunked_drain(&b, &state, &rem);
}

/* Drain a chunked body fed one byte at a time. */
static ngx_int_t
run_chunked_drip(const char *s, size_t len)
{
    ngx_buf_t   b;
    ngx_uint_t  state = sw_chunk_size;
    off_t       rem = 0;
    ngx_int_t   rc = NGX_AGAIN;
    size_t      i;

    b.start = b.pos = (u_char *) s;
    b.last = (u_char *) s;
    b.end = (u_char *) s + len;

    for (i = 0; i < len; i++) {
        b.last = (u_char *) s + i + 1;
        rc = ngx_http_upstream_check_chunked_drain(&b, &state, &rem);
        if (rc != NGX_AGAIN) {
            break;
        }
    }

    return rc;
}

/* --- header parser tests --------------------------------------------- */

static void
test_headers(void)
{
    ngx_http_check_headers_ctx_t  h;
    ngx_int_t                     rc;

    /* basic Content-Length */
    rc = run_headers("Content-Length: 123\r\n\r\n", &h);
    CHECK(rc == NGX_OK, "CL: rc OK");
    CHECK(h.seen_cl && h.content_length == 123, "CL: value 123");
    CHECK(!h.chunked, "CL: not chunked");

    /* Content-Length: 0 */
    rc = run_headers("Content-Length: 0\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.seen_cl && h.content_length == 0, "CL: zero");

    /* several headers, Content-Length among them */
    rc = run_headers("Server: t\r\nContent-Length: 4096\r\nDate: x\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.content_length == 4096, "CL: among others");

    /* chunked */
    rc = run_headers("Transfer-Encoding: chunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked && !h.seen_cl, "TE: chunked");

    /* no body framing at all */
    rc = run_headers("Server: t\r\nDate: y\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.seen_cl && !h.chunked, "no CL, no chunked");

    /* case-insensitive names / values */
    rc = run_headers("content-length: 7\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.content_length == 7, "CL: lower-case name");

    rc = run_headers("CONTENT-LENGTH: 9\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.content_length == 9, "CL: upper-case name");

    rc = run_headers("Transfer-Encoding: Chunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked, "TE: mixed-case value");

    /* extra whitespace / tab before value */
    rc = run_headers("Content-Length:\t  42\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.content_length == 42, "CL: tab+spaces");

    /* name that merely starts with the target must not match */
    rc = run_headers("Content-Lengthy: 5\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.seen_cl, "CL: longer name not matched");

    /* shorter prefix must not match */
    rc = run_headers("Content: 5\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.seen_cl, "CL: shorter name not matched");

    /* chunked + a Content-Length both present -> chunked wins downstream,
       but the parser should still flag chunked */
    rc = run_headers("Content-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n",
                     &h);
    CHECK(rc == NGX_OK && h.chunked, "both: chunked flagged");

    /* incomplete headers -> AGAIN */
    rc = run_headers("Content-Length: 12\r\n", &h);
    CHECK(rc == NGX_AGAIN, "incomplete headers -> AGAIN");

    /* malformed framing: bare CR not followed by LF */
    rc = run_headers("X: y\rZ", &h);
    CHECK(rc == NGX_ERROR, "bare CR -> ERROR");

    /* byte-by-byte fragmented arrival yields identical result */
    rc = run_headers_drip("Content-Length: 8192\r\nServer: x\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.content_length == 8192, "CL: drip fragmented");

    rc = run_headers_drip("Transfer-Encoding: chunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked, "TE: drip fragmented");
}

/* --- chunked drain tests --------------------------------------------- */

static void
test_chunked(void)
{
    ngx_int_t  rc;
    const char *s;

    /* single chunk */
    s = "5\r\nhello\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk: single");

    /* multiple chunks */
    s = "3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk: multiple");

    /* chunk extension */
    s = "5;foo=bar\r\nhello\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk: extension");

    /* trailer headers after last-chunk */
    s = "5\r\nhello\r\n0\r\nX-Trailer: v\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk: trailer");

    /* hex size (lower & upper case): 0x0a = 10 data bytes */
    s = "a\r\n0123456789\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk: lower hex size");

    s = "A\r\n0123456789\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk: upper hex size");

    /* incomplete -> AGAIN */
    s = "5\r\nhel";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_AGAIN, "chunk: incomplete -> AGAIN");

    /* last chunk not yet arrived -> AGAIN */
    s = "5\r\nhello\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_AGAIN, "chunk: missing last-chunk -> AGAIN");

    /* malformed: data not followed by CRLF */
    s = "5\r\nhelloXY\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_ERROR, "chunk: bad data terminator -> ERROR");

    /* byte-by-byte fragmented arrival still completes */
    s = "3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n";
    rc = run_chunked_drip(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk: drip fragmented");

    s = "5;ext=1\r\nhello\r\n0\r\nX: y\r\n\r\n";
    rc = run_chunked_drip(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk: drip with ext+trailer");
}

/* --- body drain tests ------------------------------------------------- */

/*
 * These cover the framing-agnostic entry point used both by the parser (over
 * body bytes that arrived together with the headers) and by the discard handler
 * (over body bytes that arrive later, across several reads).
 */
static void
test_body_drain(void)
{
    ngx_buf_t   b;
    ngx_uint_t  state;
    off_t       rem;
    ngx_int_t   rc;
    const char *s;

    /* Content-Length fully present in one buffer */
    s = "0123456789";
    b.start = b.pos = (u_char *) s;
    b.last = b.end = (u_char *) s + 10;
    state = sw_chunk_size;
    rem = 10;
    rc = ngx_http_upstream_check_body_drain(&b, 0, &state, &rem);
    CHECK(rc == NGX_OK, "drain CL: complete -> OK");
    CHECK(rem == 0, "drain CL: remaining zeroed");
    CHECK(b.pos == b.last, "drain CL: buffer consumed");

    /* Content-Length of zero completes without consuming anything */
    s = "";
    b.start = b.pos = (u_char *) s;
    b.last = b.end = (u_char *) s;
    rem = 0;
    rc = ngx_http_upstream_check_body_drain(&b, 0, &state, &rem);
    CHECK(rc == NGX_OK, "drain CL: zero-length -> OK");

    /* Content-Length split across two reads, as the discard handler sees it */
    s = "0123456789";
    rem = 10;
    b.start = b.pos = (u_char *) s;
    b.last = b.end = (u_char *) s + 4;
    rc = ngx_http_upstream_check_body_drain(&b, 0, &state, &rem);
    CHECK(rc == NGX_AGAIN, "drain CL: partial -> AGAIN");
    CHECK(rem == 6, "drain CL: remaining decremented to 6");
    CHECK(b.pos == b.last, "drain CL: partial buffer consumed");

    b.start = b.pos = (u_char *) s + 4;
    b.last = b.end = (u_char *) s + 10;
    rc = ngx_http_upstream_check_body_drain(&b, 0, &state, &rem);
    CHECK(rc == NGX_OK, "drain CL: rest -> OK");
    CHECK(rem == 0, "drain CL: remaining zeroed after rest");

    /* bytes past the body are left in the buffer for the caller to notice */
    s = "0123456789EXTRA";
    b.start = b.pos = (u_char *) s;
    b.last = b.end = (u_char *) s + 15;
    rem = 10;
    rc = ngx_http_upstream_check_body_drain(&b, 0, &state, &rem);
    CHECK(rc == NGX_OK, "drain CL: overshoot -> OK");
    CHECK(b.last - b.pos == 5, "drain CL: 5 bytes left past body");

    /* chunked framing is delegated, single buffer */
    s = "3\r\nabc\r\n0\r\n\r\n";
    b.start = b.pos = (u_char *) s;
    b.last = b.end = (u_char *) s + strlen(s);
    state = sw_chunk_size;
    rem = 0;
    rc = ngx_http_upstream_check_body_drain(&b, 1, &state, &rem);
    CHECK(rc == NGX_OK, "drain chunked: complete -> OK");

    /* chunked split mid-chunk keeps state across calls */
    s = "5\r\nhello\r\n0\r\n\r\n";
    state = sw_chunk_size;
    rem = 0;
    b.start = b.pos = (u_char *) s;
    b.last = b.end = (u_char *) s + 5;
    rc = ngx_http_upstream_check_body_drain(&b, 1, &state, &rem);
    CHECK(rc == NGX_AGAIN, "drain chunked: partial -> AGAIN");

    b.start = b.pos = (u_char *) s + 5;
    b.last = b.end = (u_char *) s + strlen(s);
    rc = ngx_http_upstream_check_body_drain(&b, 1, &state, &rem);
    CHECK(rc == NGX_OK, "drain chunked: resumed -> OK");

    /* malformed chunk framing is reported */
    s = "5\r\nhelloXY\r\n0\r\n\r\n";
    b.start = b.pos = (u_char *) s;
    b.last = b.end = (u_char *) s + strlen(s);
    state = sw_chunk_size;
    rem = 0;
    rc = ngx_http_upstream_check_body_drain(&b, 1, &state, &rem);
    CHECK(rc == NGX_ERROR, "drain chunked: malformed -> ERROR");
}

int
main(void)
{
    test_headers();
    test_chunked();
    test_body_drain();

    printf("\n%d tests, %d failed\n", tests_run, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
