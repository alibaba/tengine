/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */


/*
 * Byte-string helpers behind the protocol-independent "send" and "udp" health
 * check types: decoding the configured payload and deciding a verdict from the
 * bytes that came back.
 *
 * Like ngx_http_upstream_check_http_parse.h, this depends only on a handful of
 * ngx primitives (u_char, size_t, ngx_int_t, NGX_OK/NGX_AGAIN), so the exact
 * same source is compiled both into the production module and into a
 * stand-alone unit-test harness that stubs those primitives.
 */


#ifndef _NGX_UPSTREAM_CHECK_SEND_PARSE_H_INCLUDED_
#define _NGX_UPSTREAM_CHECK_SEND_PARSE_H_INCLUDED_


/* value of a single hex digit, or 0xff when the character is not one */
static u_char
ngx_upstream_check_hex_digit(u_char c)
{
    if (c >= '0' && c <= '9') {
        return (u_char) (c - '0');
    }

    if (c >= 'a' && c <= 'f') {
        return (u_char) (c - 'a' + 10);
    }

    if (c >= 'A' && c <= 'F') {
        return (u_char) (c - 'A' + 10);
    }

    return 0xff;
}


/*
 * Locates a byte string inside another one. Unlike ngx_strnstr() this is safe
 * on arbitrary bytes, including embedded zeros, which is the point of the
 * "send" type: the payload and the expected reply may be binary.
 *
 * An empty needle matches at the start, mirroring memmem(3).
 */
static u_char *
ngx_upstream_check_memmem(u_char *haystack, size_t hlen, u_char *needle,
    size_t nlen)
{
    u_char  *p, *last;

    if (nlen == 0) {
        return haystack;
    }

    if (hlen < nlen) {
        return NULL;
    }

    last = haystack + (hlen - nlen);

    for (p = haystack; p <= last; p++) {
        if (*p == *needle && memcmp(p, needle, nlen) == 0) {
            return p;
        }
    }

    return NULL;
}


/*
 * Decodes \xHH into a raw byte, passing everything else through unchanged.
 * The configuration parser has already turned \r, \n, \t and \\ into their
 * bytes by the time a directive value reaches us, so this only adds what is
 * needed to spell out a binary payload.
 *
 * Writes to dst, which must have room for slen bytes (the output is never
 * longer than the input), and reports the decoded length through dlen.
 *
 * A malformed escape is left as-is rather than rejected: "\xZZ" and a
 * truncated "\x4" at the end of the value stay literal, so a value that just
 * happens to contain a backslash still means what it looks like.
 */
static void
ngx_upstream_check_unescape_bytes(u_char *dst, size_t *dlen, u_char *src,
    size_t slen)
{
    u_char  *p, *last, *d;
    u_char   hi, lo;

    d = dst;
    p = src;
    last = src + slen;

    while (p < last) {

        if (p[0] != '\\' || last - p < 4 || (p[1] != 'x' && p[1] != 'X')) {
            *d++ = *p++;
            continue;
        }

        hi = ngx_upstream_check_hex_digit(p[2]);
        lo = ngx_upstream_check_hex_digit(p[3]);

        if (hi == 0xff || lo == 0xff) {
            *d++ = *p++;
            continue;
        }

        *d++ = (u_char) ((hi << 4) + lo);
        p += 4;
    }

    *dlen = (size_t) (d - dst);
}


/*
 * The verdict of a "send"/"udp" check over the bytes received so far.
 *
 * NGX_OK      the peer is alive
 * NGX_AGAIN   undecided; keep reading. The check timeout is what ultimately
 *             fails a peer whose reply never contains the expected bytes --
 *             this function never returns NGX_ERROR, because "not yet" and
 *             "never" are indistinguishable from a partial read.
 *
 * With no expectation configured, any byte at all means alive.
 */
static ngx_int_t
ngx_upstream_check_send_verdict(u_char *recv, size_t recv_len, u_char *expect,
    size_t expect_len)
{
    if (recv_len == 0) {
        return NGX_AGAIN;
    }

    if (expect_len == 0) {
        return NGX_OK;
    }

    if (ngx_upstream_check_memmem(recv, recv_len, expect, expect_len) != NULL) {
        return NGX_OK;
    }

    return NGX_AGAIN;
}


#endif /* _NGX_UPSTREAM_CHECK_SEND_PARSE_H_INCLUDED_ */
