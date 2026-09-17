/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for the byte-string helpers behind the "send" and
 * "udp" health check types (ngx_upstream_check_send_parse.h).
 *
 * The header depends only on a few ngx primitives; we stub them here so the
 * exact same source that ships in the module is exercised in isolation, with
 * no nginx build required:
 *
 *     cc -Wall -Wextra -o test_check_send_parse test_check_send_parse.c
 *     ./test_check_send_parse
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>   /* ptrdiff_t */

/* --- minimal ngx compatibility layer --------------------------------- */

typedef unsigned char   u_char;
typedef intptr_t        ngx_int_t;

#define NGX_OK       0
#define NGX_AGAIN   -2

#include "../ngx_upstream_check_send_parse.h"

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

/* memmem over NUL-terminated literals, returning the match offset or -1 */
static ptrdiff_t
find(const char *haystack, const char *needle)
{
    u_char  *p;

    p = ngx_upstream_check_memmem((u_char *) haystack, strlen(haystack),
                                  (u_char *) needle, strlen(needle));

    return p == NULL ? -1 : p - (u_char *) haystack;
}

/*
 * Decodes a NUL-terminated literal and compares the result against expect,
 * which is given with its length so it may contain zero bytes.
 */
static int
unescaped_is(const char *src, const char *expect, size_t expect_len)
{
    u_char  buf[256];
    size_t  len;

    ngx_upstream_check_unescape_bytes(buf, &len, (u_char *) src, strlen(src));

    return len == expect_len && memcmp(buf, expect, expect_len) == 0;
}

static ngx_int_t
verdict(const char *recv, size_t recv_len, const char *expect,
    size_t expect_len)
{
    return ngx_upstream_check_send_verdict((u_char *) recv, recv_len,
                                           (u_char *) expect, expect_len);
}

/* --- ngx_upstream_check_memmem --------------------------------------- */

static void
test_memmem(void)
{
    u_char  *p;

    /* an empty needle matches at the start, like memmem(3) */
    CHECK(find("abc", "") == 0, "memmem: empty needle matches at start");
    CHECK(find("", "") == 0, "memmem: empty needle in empty haystack");

    /* a needle longer than the haystack cannot match */
    CHECK(find("ab", "abc") == -1, "memmem: needle longer than haystack");
    CHECK(find("", "a") == -1, "memmem: empty haystack");

    CHECK(find("+PONG\r\n", "+PONG") == 0, "memmem: match at start");
    CHECK(find("x+PONGy", "+PONG") == 1, "memmem: match in the middle");
    CHECK(find("xx+PONG", "+PONG") == 2, "memmem: match at the end");
    CHECK(find("-ERR", "+PONG") == -1, "memmem: no match");

    /* exact-length haystack, both matching and not */
    CHECK(find("PONG", "PONG") == 0, "memmem: whole haystack matches");
    CHECK(find("PONX", "PONG") == -1, "memmem: whole haystack differs");

    /* single byte */
    CHECK(find("abc", "c") == 2, "memmem: single-byte needle");
    CHECK(find("abc", "d") == -1, "memmem: single-byte needle absent");

    /*
     * A false start must not stop the search: the first 'a' in "aab" begins a
     * candidate that fails on the second byte, and the match is one further on.
     */
    CHECK(find("aab", "ab") == 1, "memmem: resumes after a false start");
    CHECK(find("aaab", "aab") == 1, "memmem: overlapping false start");
    CHECK(find("abcabd", "abd") == 3, "memmem: second candidate matches");

    /*
     * The whole point of not using ngx_strnstr(): embedded zeros on both
     * sides must be handled as ordinary bytes.
     */
    p = ngx_upstream_check_memmem((u_char *) "a\0b\0c", 5,
                                  (u_char *) "b\0c", 3);
    CHECK(p != NULL && p == (u_char *) "a\0b\0c" + 2,
          "memmem: needle containing NUL");

    p = ngx_upstream_check_memmem((u_char *) "\0\0\1", 3,
                                  (u_char *) "\0\1", 2);
    CHECK(p != NULL, "memmem: haystack of mostly NULs");

    p = ngx_upstream_check_memmem((u_char *) "a\0b", 3, (u_char *) "b", 1);
    CHECK(p != NULL && *p == 'b', "memmem: searches past a NUL");
}

/* --- ngx_upstream_check_unescape_bytes ------------------------------- */

static void
test_unescape(void)
{
    /* nothing to decode */
    CHECK(unescaped_is("PING", "PING", 4), "unescape: no escapes");
    CHECK(unescaped_is("", "", 0), "unescape: empty input");

    /* the escape this adds on top of what the config parser already does */
    CHECK(unescaped_is("\\x41", "A", 1), "unescape: \\x41 -> A");
    CHECK(unescaped_is("\\x41\\x42", "AB", 2), "unescape: two escapes");
    CHECK(unescaped_is("a\\x42c", "aBc", 3), "unescape: escape in the middle");
    CHECK(unescaped_is("\\x50\\x49\\x4e\\x47", "PING", 4),
          "unescape: whole payload escaped");

    /* hex digits are case-insensitive, and so is the x */
    CHECK(unescaped_is("\\x4a", "J", 1), "unescape: lower-case hex digit");
    CHECK(unescaped_is("\\x4A", "J", 1), "unescape: upper-case hex digit");
    CHECK(unescaped_is("\\X4A", "J", 1), "unescape: upper-case X");

    /* a zero byte can be spelled out -- it must not terminate anything */
    CHECK(unescaped_is("a\\x00b", "a\0b", 3), "unescape: \\x00 stays a byte");
    CHECK(unescaped_is("\\x00\\x01", "\0\1", 2), "unescape: leading NUL");

    /* high bytes */
    CHECK(unescaped_is("\\xff", "\xff", 1), "unescape: 0xff");
    CHECK(unescaped_is("\\x80", "\x80", 1), "unescape: 0x80");

    /*
     * Malformed escapes stay literal rather than being rejected, so a value
     * that merely contains a backslash still means what it looks like.
     */
    CHECK(unescaped_is("\\xZZ", "\\xZZ", 4), "unescape: bad hex stays literal");
    CHECK(unescaped_is("\\x4Z", "\\x4Z", 4),
          "unescape: half-bad hex stays literal");
    CHECK(unescaped_is("\\x4", "\\x4", 3), "unescape: truncated escape");
    CHECK(unescaped_is("\\x", "\\x", 2), "unescape: bare \\x");
    CHECK(unescaped_is("\\", "\\", 1), "unescape: trailing backslash");
    CHECK(unescaped_is("a\\yz1", "a\\yz1", 5), "unescape: unknown escape");

    /*
     * A literal backslash followed by what looks like an escape: the config
     * parser turns "\\\\x41" into \x41, which we then decode. Written here as
     * the two characters that actually reach us.
     */
    CHECK(unescaped_is("\\x5cx41", "\\x41", 4),
          "unescape: escaped backslash then literal x41");

    /* decoding shortens the value, so the tail must still be copied */
    CHECK(unescaped_is("\\x41tail", "Atail", 5), "unescape: tail after escape");
}

/* --- ngx_upstream_check_send_verdict --------------------------------- */

static void
test_verdict(void)
{
    /* nothing received yet: undecided, whether or not something is expected */
    CHECK(verdict("", 0, "", 0) == NGX_AGAIN, "verdict: no data, no expect");
    CHECK(verdict("", 0, "PONG", 4) == NGX_AGAIN, "verdict: no data, expect");

    /* no expectation configured: any byte at all means alive */
    CHECK(verdict("x", 1, "", 0) == NGX_OK, "verdict: any byte without expect");
    CHECK(verdict("-ERR", 4, "", 0) == NGX_OK,
          "verdict: unexpected content without expect is still alive");
    CHECK(verdict("\0", 1, "", 0) == NGX_OK,
          "verdict: a single NUL byte counts as data");

    /* expectation present */
    CHECK(verdict("+PONG\r\n", 7, "+PONG", 5) == NGX_OK, "verdict: expect hit");
    CHECK(verdict("noise+PONG", 10, "+PONG", 5) == NGX_OK,
          "verdict: expect found after other bytes");
    CHECK(verdict("-ERR unexpected", 15, "+PONG", 5) == NGX_AGAIN,
          "verdict: wrong reply stays undecided");

    /*
     * A partial reply is undecided, not a failure: the same bytes plus the
     * rest must flip it. This is what makes an expectation split across two
     * reads work, since the caller keeps accumulating into one buffer.
     */
    CHECK(verdict("+PO", 3, "+PONG", 5) == NGX_AGAIN,
          "verdict: partial expect is undecided");
    CHECK(verdict("+PONG", 5, "+PONG", 5) == NGX_OK,
          "verdict: expect completed by a later read");

    /* binary expectations */
    CHECK(verdict("\0\1garbage", 9, "\0\1", 2) == NGX_OK,
          "verdict: binary expect hit");
    CHECK(verdict("\0\2garbage", 9, "\0\1", 2) == NGX_AGAIN,
          "verdict: binary expect miss");
}

/* --- main ------------------------------------------------------------ */

int
main(void)
{
    test_memmem();
    test_unescape();
    test_verdict();

    printf("%d tests, %d failures\n", tests_run, tests_failed);

    return tests_failed == 0 ? 0 : 1;
}
