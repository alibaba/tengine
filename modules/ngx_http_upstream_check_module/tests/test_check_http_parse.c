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
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/types.h>   /* off_t */

/* the drain-termination watchdog below needs a timer and a way back out */
#ifndef _WIN32
#include <signal.h>
#include <setjmp.h>
#include <sys/time.h>
#define CHECK_WATCHDOG  1
#endif

/* --- minimal ngx compatibility layer --------------------------------- */

typedef unsigned char   u_char;
typedef intptr_t        ngx_int_t;
typedef uintptr_t       ngx_uint_t;

#define NGX_OK       0
#define NGX_ERROR   -1
#define NGX_AGAIN   -2

#define CR  '\r'
#define LF  '\n'

/* off_t is 64-bit on every platform the module is built for */
#define NGX_MAX_OFF_T_VALUE  INT64_MAX

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

/* --- drain-termination watchdog --------------------------------------- */

/*
 * A parser that never terminates cannot be caught by comparing return values:
 * the test process simply spins. Every drain call below therefore runs under a
 * SIGALRM watchdog that reports the call as DRAIN_HUNG instead. A drain call is
 * microseconds long even under the sanitizers, so the timeout is generous by
 * four orders of magnitude; a few trips in a row mean the run is meaningless
 * and would otherwise take as long as the CI job's own timeout, so it stops.
 */

#define DRAIN_HUNG            (-100)   /* reported instead of a parser result */
#define WATCHDOG_USEC         200000
#define WATCHDOG_MAX_TRIPS    4

#ifdef CHECK_WATCHDOG

static sigjmp_buf    watchdog_jmp;
static volatile int  watchdog_armed;
static int           watchdog_trips;

static void
watchdog_expired(int sig)
{
    (void) sig;

    if (watchdog_armed) {
        watchdog_armed = 0;
        siglongjmp(watchdog_jmp, 1);
    }
}

static void
watchdog_start(void)
{
    static int        installed = 0;
    struct itimerval  it;

    if (!installed) {
        signal(SIGALRM, watchdog_expired);
        installed = 1;
    }

    watchdog_armed = 1;

    it.it_interval.tv_sec = 0;
    it.it_interval.tv_usec = 0;
    it.it_value.tv_sec = WATCHDOG_USEC / 1000000;
    it.it_value.tv_usec = WATCHDOG_USEC % 1000000;
    setitimer(ITIMER_REAL, &it, NULL);
}

static void
watchdog_stop(void)
{
    struct itimerval  it;

    watchdog_armed = 0;

    memset(&it, 0, sizeof(it));
    setitimer(ITIMER_REAL, &it, NULL);
}

#endif

/* One chunked-drain call, bounded by the watchdog where there is one. */
static ngx_int_t
drain_guarded(ngx_buf_t *b, ngx_uint_t *state, off_t *remaining)
{
#ifdef CHECK_WATCHDOG
    ngx_int_t  rc;

    if (sigsetjmp(watchdog_jmp, 1) != 0) {
        if (++watchdog_trips >= WATCHDOG_MAX_TRIPS) {
            printf("FAIL: the chunked drain keeps spinning, giving up after "
                   "%d hung calls\n", watchdog_trips);
            exit(1);
        }

        return DRAIN_HUNG;
    }

    watchdog_start();
    rc = ngx_http_upstream_check_chunked_drain(b, state, remaining);
    watchdog_stop();

    return rc;
#else
    return ngx_http_upstream_check_chunked_drain(b, state, remaining);
#endif
}

/* --- helpers --------------------------------------------------------- */

/* Parse headers from a fully-available buffer that may hold NUL bytes. */
static ngx_int_t
run_headers_len(const char *s, size_t len, ngx_http_check_headers_ctx_t *h)
{
    ngx_buf_t b;

    memset(h, 0, sizeof(*h));
    b.start = b.pos = (u_char *) s;
    b.last = (u_char *) s + len;
    b.end = b.last;

    return ngx_http_upstream_check_parse_headers(&b, h);
}

/* Parse headers from a fully-available buffer. */
static ngx_int_t
run_headers(const char *s, ngx_http_check_headers_ctx_t *h)
{
    return run_headers_len(s, strlen(s), h);
}

/* Parse headers fed one byte at a time (incremental / fragmented arrival). */
static ngx_int_t
run_headers_drip_len(const char *s, size_t len,
    ngx_http_check_headers_ctx_t *h)
{
    ngx_buf_t  b;
    ngx_int_t  rc = NGX_AGAIN;
    size_t     i;

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

static ngx_int_t
run_headers_drip(const char *s, ngx_http_check_headers_ctx_t *h)
{
    return run_headers_drip_len(s, strlen(s), h);
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

/*
 * The two feed patterns above, with every call bounded by the watchdog. b is
 * left as the parser left it, so a test can also check where the read pointer
 * ended up; on DRAIN_HUNG it is wherever the spinning call had it.
 */
static ngx_int_t
run_chunked_guarded(ngx_buf_t *b, const char *s, size_t len,
    ngx_uint_t *state, off_t *rem)
{
    b->start = b->pos = (u_char *) s;
    b->last = b->end = (u_char *) s + len;

    return drain_guarded(b, state, rem);
}

static ngx_int_t
run_chunked_guarded_drip(ngx_buf_t *b, const char *s, size_t len,
    ngx_uint_t *state, off_t *rem)
{
    ngx_int_t  rc = NGX_AGAIN;
    size_t     i;

    b->start = b->pos = (u_char *) s;
    b->last = (u_char *) s;
    b->end = (u_char *) s + len;

    for (i = 0; i < len; i++) {
        b->last = (u_char *) s + i + 1;
        rc = drain_guarded(b, state, rem);
        if (rc != NGX_AGAIN) {
            break;
        }
    }

    return rc;
}

/*
 * Follow the module end to end over one complete response: parse the headers,
 * take the framing decision ngx_http_upstream_check_http_parse() takes, and
 * drain the body bytes that arrived together with them.
 *
 * *drained says whether the drain was reached at all -- unusable framing makes
 * the module mark the connection not reusable and skip it. *remaining is the
 * byte count handed over, left at whatever the drain updated it to. b is left
 * as the drain left it, so the caller can see where it stopped.
 */
static ngx_int_t
run_response(const char *s, size_t len, ngx_http_check_headers_ctx_t *h,
    ngx_buf_t *b, unsigned *drained, off_t *remaining)
{
    ngx_uint_t  state = sw_chunk_size;
    ngx_int_t   rc;

    *drained = 0;
    *remaining = 0;

    memset(h, 0, sizeof(*h));

    b->start = b->pos = (u_char *) s;
    b->last = b->end = (u_char *) s + len;

    rc = ngx_http_upstream_check_parse_headers(b, h);
    if (rc != NGX_OK) {
        return rc;
    }

    if (h->bad_framing || (h->seen_te && !h->chunked)) {
        /* the module sets c->error here: the connection is closed, not reused */
        return NGX_OK;
    }

    if (h->chunked) {
        state = sw_chunk_size;
        *remaining = 0;

    } else if (h->seen_cl) {
        *remaining = h->content_length;

    } else {
        /* the body is delimited by close: not reusable either */
        return NGX_OK;
    }

    *drained = 1;

    return ngx_http_upstream_check_body_drain(b, h->chunked, &state, remaining);
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

/*
 * Regression for the out-of-bounds read of the "chunked" table: the old code
 * kept advancing the match index past the end of the token whenever the next
 * byte equalled the table's NUL terminator. A NUL right after "chunked" drove
 * it to 8, and the byte after that was compared against ck[8]. These inputs
 * now leave chunked clear, which the old code got wrong even without a
 * sanitizer; the Makefile builds with ASan as well, which also catches the
 * read itself.
 */
static void
test_headers_te_token(void)
{
    ngx_http_check_headers_ctx_t  h;
    ngx_int_t                     rc;
    char                          buf[64];
    size_t                        n;
    int                           i;

    static const char  nul_x[] = "Transfer-Encoding: chunked\0X\r\n\r\n";
    static const char  nul_run[] =
        "Transfer-Encoding: chunked\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\r\n\r\n";

    rc = run_headers_drip_len(nul_x, sizeof(nul_x) - 1, &h);
    CHECK(rc == NGX_OK, "TE OOB: chunked NUL X drip -> OK");
    CHECK(h.seen_te && !h.chunked, "TE OOB: chunked NUL X drip not chunked");

    rc = run_headers_len(nul_x, sizeof(nul_x) - 1, &h);
    CHECK(rc == NGX_OK && h.seen_te && !h.chunked,
          "TE OOB: chunked NUL X whole not chunked");

    rc = run_headers_drip_len(nul_run, sizeof(nul_run) - 1, &h);
    CHECK(rc == NGX_OK && !h.chunked, "TE OOB: run of NULs not chunked");

    /* the reporter's input: a byte glued to the token */
    rc = run_headers_drip("Transfer-Encoding: chunkedX\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.seen_te && !h.chunked, "TE: chunkedX not chunked");

    rc = run_headers("Transfer-Encoding: xchunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.chunked, "TE: xchunked not chunked");

    rc = run_headers("Transfer-Encoding: chunkedchunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.chunked, "TE: chunkedchunked not chunked");

    /* every possible byte right after "chunked", then more bytes */
    for (i = 0; i < 256; i++) {
        if (i == '\r' || i == '\n') {
            continue;
        }

        n = (size_t) snprintf(buf, sizeof(buf), "Transfer-Encoding: chunked");
        buf[n++] = (char) i;
        memcpy(buf + n, "chunked\r\n\r\n", sizeof("chunked\r\n\r\n") - 1);
        n += sizeof("chunked\r\n\r\n") - 1;

        rc = run_headers_drip_len(buf, n, &h);

        /* only a list separator makes the trailing "chunked" its own element */
        if (i == ',') {
            CHECK(rc == NGX_OK && h.chunked, "TE sweep: comma -> chunked");
        } else if (i == ' ' || i == '\t') {
            CHECK(rc == NGX_OK && !h.chunked, "TE sweep: OWS -> not chunked");
        } else {
            CHECK(rc == NGX_OK && !h.chunked, "TE sweep: glued byte");
        }
        CHECK(h.chunk_idx <= NGX_CHECK_TE_OTHER, "TE sweep: index bounded");
    }

    /* list semantics: only the final coding counts */
    rc = run_headers("Transfer-Encoding: gzip, chunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked, "TE list: gzip, chunked");

    rc = run_headers("Transfer-Encoding: gzip,chunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked, "TE list: no space");

    rc = run_headers("Transfer-Encoding: chunked, gzip\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.seen_te && !h.chunked,
          "TE list: chunked not final");

    rc = run_headers("Transfer-Encoding: , chunked ,, \r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked, "TE list: empty elements ignored");

    rc = run_headers("Transfer-Encoding: chunked \t\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked, "TE: trailing whitespace");

    rc = run_headers("Transfer-Encoding: chun ked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.chunked, "TE: split token not chunked");

    rc = run_headers("Transfer-Encoding: chunked;a=b\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.chunked, "TE: parameter not chunked");

    rc = run_headers("Transfer-Encoding: identity\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.seen_te && !h.chunked, "TE: identity");

    rc = run_headers("Transfer-Encoding:\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.seen_te && !h.chunked, "TE: empty value");

    /* several header lines form one list, in order */
    rc = run_headers("Transfer-Encoding: gzip\r\n"
                     "Transfer-Encoding: chunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked, "TE lines: chunked last");

    rc = run_headers("Transfer-Encoding: chunked\r\n"
                     "Transfer-Encoding: gzip\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.chunked, "TE lines: chunked not last");

    rc = run_headers_drip("Transfer-Encoding: gzip, chunked\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.chunked, "TE list: drip fragmented");
}

/* Content-Length must be one bounded decimal number */
static void
test_headers_content_length(void)
{
    ngx_http_check_headers_ctx_t  h;
    ngx_int_t                     rc;

    rc = run_headers("Content-Length: 9223372036854775807\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.bad_framing
          && h.content_length == INT64_MAX, "CL: off_t max accepted");

    rc = run_headers("Content-Length: 9223372036854775808\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: off_t max + 1 rejected");
    CHECK(h.content_length >= 0, "CL: no wrap past off_t max");

    /* wraps to -1 when accumulated without a bound */
    rc = run_headers("Content-Length: 18446744073709551615\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing && h.content_length >= 0,
          "CL: 2^64-1 rejected, not negative");

    rc = run_headers_drip("Content-Length: 99999999999999999999999999\r\n\r\n",
                          &h);
    CHECK(rc == NGX_OK && h.bad_framing && h.content_length >= 0,
          "CL: long overflow drip rejected");

    rc = run_headers("Content-Length: 000000000000000000000000042\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.bad_framing && h.content_length == 42,
          "CL: leading zeros");

    rc = run_headers("Content-Length: 12 \r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.bad_framing && h.content_length == 12,
          "CL: trailing whitespace");

    rc = run_headers("Content-Length: 1 2\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: split digits rejected");

    rc = run_headers("Content-Length: 12a\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: trailing junk rejected");

    rc = run_headers("Content-Length: -1\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: negative rejected");
    CHECK(h.content_length >= 0, "CL: minus sign not accumulated");

    rc = run_headers("Content-Length: -1000000\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing && h.content_length >= 0,
          "CL: large negative rejected");

    rc = run_headers("Content-Length: 1-2\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing && h.content_length >= 0,
          "CL: inner minus sign rejected");

    rc = run_headers("Content-Length: 5, 5\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: list rejected");

    rc = run_headers("Content-Length:\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: empty rejected");

    rc = run_headers("Content-Length:   \n\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: blank, bare LF rejected");

    rc = run_headers("Content-Length: 5\r\nContent-Length: 5\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: repeated header rejected");

    /* the old parser concatenated the digits of every line: 5 then 6 -> 56 */
    rc = run_headers("Content-Length: 5\r\nContent-Length: 6\r\n\r\n", &h);
    CHECK(rc == NGX_OK && h.bad_framing, "CL: conflicting header rejected");

    rc = run_headers("Content-Length: 5\r\nServer: x\r\n\r\n", &h);
    CHECK(rc == NGX_OK && !h.bad_framing && h.content_length == 5,
          "CL: valid value not flagged");
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

/*
 * The chunk size must not wrap: a negative size made sw_chunk_data move the
 * read pointer backwards, before the start of the buffer.
 */
static void
test_chunked_size_overflow(void)
{
    ngx_buf_t   b;
    ngx_uint_t  state;
    off_t       rem;
    ngx_int_t   rc;
    const char *s;

    /* the largest size that fits is accepted; it just needs more data */
    s = "7fffffffffffffff\r\nAB";
    b.start = b.pos = (u_char *) s;
    b.last = b.end = (u_char *) s + strlen(s);
    state = sw_chunk_size;
    rem = 0;
    rc = ngx_http_upstream_check_chunked_drain(&b, &state, &rem);
    CHECK(rc == NGX_AGAIN, "chunk size: off_t max -> AGAIN");
    CHECK(rem == INT64_MAX - 2, "chunk size: off_t max tracked");
    CHECK(b.pos == b.last, "chunk size: off_t max pointer in bounds");

    s = "8000000000000000\r\nAB\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_ERROR, "chunk size: 2^63 -> ERROR");

    /* wraps to -256 when accumulated without a bound */
    s = "ffffffffffffff00\r\nAB\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_ERROR, "chunk size: wrap to negative -> ERROR");

    s = "fffff00000000000\r\nAB\r\n0\r\n\r\n";
    rc = run_chunked_drip(s, strlen(s));
    CHECK(rc == NGX_ERROR, "chunk size: wrap to negative drip -> ERROR");

    s = "FFFFFFFFFFFFFFFFFFFFFFFF\r\nAB\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_ERROR, "chunk size: long upper hex -> ERROR");

    /* leading zeros do not count towards the bound */
    s = "00000000000000000000000005\r\nhello\r\n0\r\n\r\n";
    rc = run_chunked(s, strlen(s));
    CHECK(rc == NGX_OK, "chunk size: leading zeros");

    /* a later oversized chunk in the same body is caught too */
    s = "3\r\nabc\r\n10000000000000000\r\nAB\r\n0\r\n\r\n";
    rc = run_chunked_drip(s, strlen(s));
    CHECK(rc == NGX_ERROR, "chunk size: second chunk overflow -> ERROR");
}

/*
 * The chunked drain is the only parser here that moves its read pointer by
 * hand, so an iteration that neither consumes a byte nor changes the state
 * spins over the same buffer forever: the worker burns a core and never runs
 * another check. *state is a caller-owned ngx_uint_t carried across calls, so
 * the parser cannot assume it holds one of the enum values -- an unknown one
 * used to match no case at all, which is exactly such an iteration. These
 * tests report DRAIN_HUNG rather than hanging the run.
 */
static void
test_chunked_unknown_state(void)
{
    ngx_buf_t   b;
    ngx_uint_t  state;
    off_t       rem;
    ngx_int_t   rc;
    size_t      i;
    char        body[] = "5\r\nhello\r\n0\r\n\r\n";

    /* the first value past the enum, and several far outside it */
    static const ngx_uint_t  unknown[] = {
        sw_chunk_trailer_almost_done + 1, 63, 1000, 0xdeadbeef, (ngx_uint_t) -1
    };

    for (i = 0; i < sizeof(unknown) / sizeof(unknown[0]); i++) {
        state = unknown[i];
        rem = 0;
        rc = run_chunked_guarded(&b, body, sizeof(body) - 1, &state, &rem);

        CHECK(rc == NGX_ERROR, "unknown state: refused, not spun on");
        CHECK(b.pos == b.start, "unknown state: pointer untouched");
        CHECK(rem == 0, "unknown state: byte count untouched");
    }

    /* every state up to the last valid one parses, everything past it does not */
    for (i = 0; i < 64; i++) {
        state = (ngx_uint_t) i;
        rem = 0;
        rc = run_chunked_guarded(&b, body, sizeof(body) - 1, &state, &rem);

        CHECK(rc != DRAIN_HUNG, "state sweep: terminates");
        CHECK(rc == NGX_OK || rc == NGX_AGAIN || rc == NGX_ERROR,
              "state sweep: a parser result");
        CHECK(b.pos >= b.start && b.pos <= b.last,
              "state sweep: pointer inside the buffer");

        if (i > sw_chunk_trailer_almost_done) {
            CHECK(rc == NGX_ERROR, "state sweep: past the enum -> ERROR");
        }
    }

    /* an empty buffer never enters the loop, so it cannot spin either */
    state = 1000;
    rem = 0;
    rc = run_chunked_guarded(&b, body, 0, &state, &rem);
    CHECK(rc == NGX_AGAIN, "unknown state: empty buffer -> AGAIN");
    CHECK(b.pos == b.last, "unknown state: empty buffer pointer untouched");
}

/*
 * Every state the drain can be in against every byte value, at several byte
 * counts. Whatever the peer sends next, one call has to finish, keep the read
 * pointer inside the buffer, and keep the byte count non-negative: the three
 * things a stuck or wrapping state machine loses.
 */
static void
test_chunked_state_byte_sweep(void)
{
    ngx_buf_t   b;
    ngx_uint_t  state0, state;
    off_t       rem;
    ngx_int_t   rc;
    int         i;
    size_t      k;
    char        body[2] = "5";

    static const off_t  rems[] = { 0, 1, INT64_MAX };

    for (state0 = 0; state0 <= sw_chunk_trailer_almost_done; state0++) {
        for (i = 0; i < 256; i++) {
            body[0] = (char) i;

            for (k = 0; k < sizeof(rems) / sizeof(rems[0]); k++) {
                state = state0;
                rem = rems[k];
                rc = run_chunked_guarded(&b, body, 1, &state, &rem);

                CHECK(rc != DRAIN_HUNG, "state/byte sweep: terminates");
                CHECK(b.pos >= b.start && b.pos <= b.last,
                      "state/byte sweep: pointer inside the buffer");
                CHECK(rem >= 0, "state/byte sweep: byte count not negative");
            }
        }
    }
}

/*
 * Framing a broken or hostile peer can produce. Each case is fed whole and one
 * byte at a time, starting both from a fresh body and from every state a
 * previous call could have stopped in -- the discard handler resumes there.
 */
static void
test_chunked_hostile_framing(void)
{
    ngx_buf_t   b;
    ngx_uint_t  state0, state;
    off_t       rem;
    ngx_int_t   rc;
    size_t      i;

    static const char *cases[] = {
        /* not a hex digit where the chunk size goes */
        "Z\r\nAB\r\n0\r\n\r\n",
        "\xff\r\nAB\r\n0\r\n\r\n",
        "g\r\nhello\r\n0\r\n\r\n",
        /* a size line without its LF, chunk-data without its CRLF */
        "5\rX\r\n",
        "5\r",
        "5\r\nhelloX\r\n",
        "5\r\nhello\n",
        /* bare LFs, empty size lines, a last-chunk that repeats */
        "5\nhello\n0\n\n",
        "\r\n\r\n\r\n\r\n",
        "\n\n\n\n",
        "0\r\n\r\n0\r\n\r\n",
        "0\r\nX\r",
        "0\r",
        /* a chunk extension and a trailer that never end */
        "5;;;;;;;;;;;;;;;;;\r\nhello\r\n0\r\n\r\n",
        "0\r\nX-Long-Trailer: y\r",
        /* sizes that do not fit off_t, then data */
        "ffffffffffffffff\r\nAB",
        "7fffffffffffffff\r\nAB",
        /* cut off mid-frame */
        "1\r\na\r\n2\r\nb\r\n3\r\nc",
    };

    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        for (state0 = 0; state0 <= sw_chunk_trailer_almost_done + 1; state0++) {

            state = state0;
            rem = 0;
            rc = run_chunked_guarded(&b, cases[i], strlen(cases[i]),
                                     &state, &rem);
            CHECK(rc != DRAIN_HUNG, "hostile framing: whole terminates");
            CHECK(rc == NGX_OK || rc == NGX_AGAIN || rc == NGX_ERROR,
                  "hostile framing: whole result valid");
            CHECK(b.pos >= b.start && b.pos <= b.last,
                  "hostile framing: whole pointer inside the buffer");
            CHECK(rem >= 0, "hostile framing: whole byte count not negative");

            state = state0;
            rem = 0;
            rc = run_chunked_guarded_drip(&b, cases[i], strlen(cases[i]),
                                          &state, &rem);
            CHECK(rc != DRAIN_HUNG, "hostile framing: drip terminates");
            CHECK(b.pos >= b.start && b.pos <= b.last,
                  "hostile framing: drip pointer inside the buffer");
        }
    }

    /*
     * The 132-byte sample the report quotes: 0x13 filler with the handful of
     * odd bytes its hex dump shows. Nothing here is framing at all, which is
     * the point -- the drain still has to finish with it.
     */
    {
        char    reported[132];

        memset(reported, 0x13, sizeof(reported));
        reported[5] = (char) 0xfd;
        reported[7] = (char) 0x00;
        reported[8] = (char) 0x00;
        reported[9] = (char) 0x00;
        reported[10] = (char) 0xa0;

        for (state0 = 0; state0 <= sw_chunk_trailer_almost_done; state0++) {
            state = state0;
            rem = 0;
            rc = run_chunked_guarded(&b, reported, sizeof(reported),
                                     &state, &rem);
            CHECK(rc != DRAIN_HUNG, "reported sample: whole terminates");
            CHECK(b.pos >= b.start && b.pos <= b.last,
                  "reported sample: pointer inside the buffer");

            state = state0;
            rem = 0;
            rc = run_chunked_guarded_drip(&b, reported, sizeof(reported),
                                          &state, &rem);
            CHECK(rc != DRAIN_HUNG, "reported sample: drip terminates");
        }
    }
}

/*
 * Every combination of up to three framing bytes. Three bytes reach each
 * transition of the size line, the chunk extension, the chunk-data terminator
 * and the trailer, which is where a state that stops consuming would show up;
 * the alphabet holds every character the state machine branches on.
 */
static void
test_chunked_framing_sweep(void)
{
    ngx_buf_t   b;
    ngx_uint_t  state;
    off_t       rem;
    ngx_int_t   rc;
    char        in[3];
    size_t      len, i0, i1, i2;

    static const char  alpha[] = "019aAfFx\r\n;, \t";
    const size_t       n = sizeof(alpha) - 1;

    for (len = 0; len <= sizeof(in); len++) {
        for (i0 = 0; i0 < (len > 0 ? n : 1); i0++) {
            for (i1 = 0; i1 < (len > 1 ? n : 1); i1++) {
                for (i2 = 0; i2 < (len > 2 ? n : 1); i2++) {
                    in[0] = alpha[i0];
                    in[1] = alpha[i1];
                    in[2] = alpha[i2];

                    state = sw_chunk_size;
                    rem = 0;
                    rc = run_chunked_guarded(&b, in, len, &state, &rem);
                    CHECK(rc != DRAIN_HUNG, "framing sweep: whole terminates");
                    CHECK(b.pos >= b.start && b.pos <= b.last,
                          "framing sweep: pointer inside the buffer");
                    CHECK(rem >= 0, "framing sweep: byte count not negative");

                    state = sw_chunk_size;
                    rem = 0;
                    rc = run_chunked_guarded_drip(&b, in, len, &state, &rem);
                    CHECK(rc != DRAIN_HUNG, "framing sweep: drip terminates");
                }
            }
        }
    }
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

/*
 * The drain turns the byte count it is given into pointer arithmetic, and it is
 * the single entry point for both framings, so it must not trust that count: a
 * negative one used to be cast to size_t and move b->pos backwards, before the
 * buffer, where the caller would then read. Callers bound what they store here,
 * but the bound belongs next to the arithmetic that needs it.
 */
static void
test_body_drain_negative_remaining(void)
{
    ngx_buf_t   b;
    ngx_uint_t  state;
    off_t       rem;
    ngx_int_t   rc;
    char        body[] = "hello";
    int         i;

    static const off_t  negatives[] = { -1, -5, -1000000, INT64_MIN };

    for (i = 0; i < (int) (sizeof(negatives) / sizeof(negatives[0])); i++) {

        /* Content-Length framing: the count is added straight to b->pos */
        b.start = b.pos = (u_char *) body;
        b.last = b.end = (u_char *) body + 5;
        state = sw_chunk_size;
        rem = negatives[i];

        rc = ngx_http_upstream_check_body_drain(&b, 0, &state, &rem);
        CHECK(rc == NGX_ERROR, "drain negative: CL framing -> ERROR");
        CHECK(b.pos == b.start, "drain negative: CL pointer untouched");
        CHECK(rem == negatives[i], "drain negative: CL count untouched");

        /* chunked framing, caught while skipping chunk-data bytes */
        b.start = b.pos = (u_char *) body;
        b.last = b.end = (u_char *) body + 5;
        state = sw_chunk_data;
        rem = negatives[i];

        rc = ngx_http_upstream_check_body_drain(&b, 1, &state, &rem);
        CHECK(rc == NGX_ERROR, "drain negative: chunked framing -> ERROR");
        CHECK(b.pos == b.start, "drain negative: chunked pointer untouched");
        CHECK(rem == negatives[i], "drain negative: chunked count untouched");
    }

    /* an empty buffer is no reason to move the pointer either */
    b.start = b.pos = b.last = b.end = (u_char *) body;
    state = sw_chunk_size;
    rem = -1;
    rc = ngx_http_upstream_check_body_drain(&b, 0, &state, &rem);
    CHECK(rc == NGX_ERROR, "drain negative: empty buffer -> ERROR");
    CHECK(b.pos == b.start, "drain negative: empty buffer pointer untouched");

    /* zero is the boundary and stays a valid, fully drained body */
    b.start = b.pos = (u_char *) body;
    b.last = b.end = (u_char *) body + 5;
    rem = 0;
    rc = ngx_http_upstream_check_body_drain(&b, 0, &state, &rem);
    CHECK(rc == NGX_OK && b.pos == b.start, "drain negative: zero still OK");
}

/*
 * End-to-end regression for the report that a hostile Content-Length reaches
 * the drain as a negative byte count: whatever the checked peer puts in its
 * response headers, the module must either refuse to reuse the connection or
 * hand the drain a count that keeps b->pos inside the buffer. A value that
 * does not fit off_t is what actually wrapped negative -- a literal "-1" never
 * did, the parser rejects the minus sign -- so both are covered here.
 */
static void
test_response_body_drain_bounds(void)
{
    ngx_http_check_headers_ctx_t  h;
    ngx_buf_t                     b;
    unsigned                      drained;
    off_t                         rem;
    ngx_int_t                     rc;
    char                          buf[128];
    size_t                        n, i;

    static const char  overflow_digits[] = "99999999999999999999999\r\n\r\n";

    /*
     * A response, whether the module reaches the drain over it at all, and
     * what the drain then reports. The status line is parsed elsewhere, so
     * these start at the first header.
     */
    static const struct {
        const char  *resp;
        unsigned     drained;
        ngx_int_t    rc;
    } cases[] = {
        /* the reported PoC: the minus sign makes the framing unusable, so the
           connection is dropped and the drain is never reached */
        { "Content-Length: -1\r\n\r\nhello", 0, NGX_OK },
        { "Content-Length: -1000000\r\n\r\nhello", 0, NGX_OK },
        { "Content-Length: 1-2\r\n\r\nhello", 0, NGX_OK },
        { "Content-Length: 5-\r\n\r\nhello", 0, NGX_OK },
        /* accumulations that wrap off_t when left unbounded, and did so into a
           negative count the drain then added to b->pos */
        { "Content-Length: 18446744073709551615\r\n\r\n", 0, NGX_OK },
        { "Content-Length: 9223372036854775808\r\n\r\n", 0, NGX_OK },
        { "Content-Length: 99999999999999999999999\r\n\r\n", 0, NGX_OK },
        /* the largest count that fits: valid framing, body still owed */
        { "Content-Length: 9223372036854775807\r\n\r\nhello", 1, NGX_AGAIN },
        /* chunk sizes that wrap off_t the same way; here the drain is reached
           and must report the bad framing itself */
        { "Transfer-Encoding: chunked\r\n\r\n"
          "ffffffffffffffff\r\nAB\r\n0\r\n\r\n", 1, NGX_ERROR },
        { "Transfer-Encoding: chunked\r\n\r\n"
          "fffff00000000000\r\nAB\r\n0\r\n\r\n", 1, NGX_ERROR },
        /* well-formed controls: the drain is reached and consumes the body */
        { "Content-Length: 5\r\n\r\nhello", 1, NGX_OK },
        { "Content-Length: 0\r\n\r\n", 1, NGX_OK },
        { "Content-Length: 3\r\n\r\nhello", 1, NGX_OK },
        { "Transfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n",
          1, NGX_OK },
    };

    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        rc = run_response(cases[i].resp, strlen(cases[i].resp), &h, &b,
                          &drained, &rem);

        CHECK(drained == cases[i].drained, "response: drain reached as expected");
        CHECK(rc == cases[i].rc, "response: drain rc as expected");
        CHECK(rem >= 0, "response: byte count never negative");
        CHECK(h.content_length >= 0, "response: Content-Length never negative");
        CHECK(b.pos >= b.start && b.pos <= b.last,
              "response: pointer stays inside the buffer");
    }

    /* a body owed in full leaves the pointer at the end, not before the start */
    rc = run_response("Content-Length: 5\r\n\r\nhello",
                      sizeof("Content-Length: 5\r\n\r\nhello") - 1,
                      &h, &b, &drained, &rem);
    CHECK(drained && rc == NGX_OK && rem == 0 && b.pos == b.last,
          "response: valid Content-Length drained");

    /* every possible first byte of the value, in front of an oversized number:
       none of them may yield a negative count, however they are framed */
    for (i = 0; i < 256; i++) {
        n = (size_t) snprintf(buf, sizeof(buf), "Content-Length: ");
        buf[n++] = (char) i;
        memcpy(buf + n, overflow_digits, sizeof(overflow_digits) - 1);
        n += sizeof(overflow_digits) - 1;

        rc = run_response(buf, n, &h, &b, &drained, &rem);

        CHECK(rc == NGX_OK || rc == NGX_AGAIN || rc == NGX_ERROR,
              "CL sweep: drain rc valid");
        CHECK(h.content_length >= 0, "CL sweep: Content-Length never negative");
        CHECK(rem >= 0, "CL sweep: byte count never negative");
        CHECK(b.pos >= b.start && b.pos <= b.last,
              "CL sweep: pointer stays inside the buffer");
    }
}

int
main(void)
{
    test_headers();
    test_headers_te_token();
    test_headers_content_length();
    test_chunked();
    test_chunked_size_overflow();
    test_chunked_unknown_state();
    test_chunked_state_byte_sweep();
    test_chunked_hostile_framing();
    test_chunked_framing_sweep();
    test_body_drain();
    test_body_drain_negative_remaining();
    test_response_body_drain_bounds();

    printf("\n%d tests, %d failed\n", tests_run, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
