/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for ngx_xquic_read_file_data() (ngx_xquic_file.h).
 *
 * That helper loads the xquic session ticket key and token key from disk. When
 * it fails, xquic silently falls back to a per-worker random session ticket
 * key, which makes 0-RTT impossible to resume across workers -- so its return
 * value contract and its file descriptor hygiene both matter.
 *
 * The header only needs ngx_int_t from its translation unit, which is stubbed
 * below so the exact same source that ships in the module is exercised without
 * requiring a full nginx build:
 *
 *     cc -Wall -Wextra -o test_xquic_read_file_data test_xquic_read_file_data.c
 *     ./test_xquic_read_file_data
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

/* --- minimal ngx compatibility layer --------------------------------- */

typedef intptr_t        ngx_int_t;

#include "../../ngx_xquic_file.h"

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

static char  tmpl[] = "/tmp/ngx_xquic_key_test_XXXXXX";
static char  path[sizeof(tmpl)];

/* Create a temp file holding len bytes of deterministic content. */
static int
write_temp_file(size_t len)
{
    size_t   i;
    int      fd;
    FILE    *fp;

    memcpy(path, tmpl, sizeof(tmpl));

    fd = mkstemp(path);
    if (fd == -1) {
        return -1;
    }

    fp = fdopen(fd, "wb");
    if (fp == NULL) {
        close(fd);
        return -1;
    }

    for (i = 0; i < len; i++) {
        if (fputc((int) (i & 0xff), fp) == EOF) {
            fclose(fp);
            return -1;
        }
    }

    fclose(fp);
    return 0;
}

/* Number of currently open descriptors, used to detect leaks. */
static int
count_open_fds(void)
{
    int  fd, n = 0;

    for (fd = 0; fd < 256; fd++) {
        if (fcntl(fd, F_GETFD) != -1) {
            n++;
        }
    }

    return n;
}

/* --- test cases ------------------------------------------------------ */

/* A 48-byte key -- the size recommended for xquic_ssl_session_ticket_key. */
static void
test_reads_whole_file(void)
{
    char       buf[512];
    ngx_int_t  ret;
    size_t     i;
    int        ok = 1;

    if (write_temp_file(48) != 0) {
        CHECK(0, "failed to create temp file");
        return;
    }

    memset(buf, 0, sizeof(buf));
    ret = ngx_xquic_read_file_data(buf, sizeof(buf), path);

    CHECK(ret == 48, "48-byte key should return 48");

    for (i = 0; i < 48; i++) {
        if ((unsigned char) buf[i] != (unsigned char) (i & 0xff)) {
            ok = 0;
            break;
        }
    }
    CHECK(ok, "content should match what was written");

    unlink(path);
}

/*
 * A missing file must return -1. This is the case that bit in practice: the
 * default xquic_ssl_session_ticket_key value is the relative path
 * "./session_ticket.key", which usually does not exist.
 */
static void
test_missing_file(void)
{
    char       buf[512];
    ngx_int_t  ret;

    ret = ngx_xquic_read_file_data(buf, sizeof(buf), "/tmp/ngx_xquic_no_such_key");

    CHECK(ret == -1, "missing file should return -1");
}

/* A file larger than the destination buffer must be rejected, not truncated. */
static void
test_file_larger_than_buffer(void)
{
    char       buf[16];
    ngx_int_t  ret;

    if (write_temp_file(64) != 0) {
        CHECK(0, "failed to create temp file");
        return;
    }

    ret = ngx_xquic_read_file_data(buf, sizeof(buf), path);

    CHECK(ret == -1, "file larger than buffer should return -1");

    unlink(path);
}

/* An empty file reads back as zero bytes rather than as an error. */
static void
test_empty_file(void)
{
    char       buf[512];
    ngx_int_t  ret;

    if (write_temp_file(0) != 0) {
        CHECK(0, "failed to create temp file");
        return;
    }

    ret = ngx_xquic_read_file_data(buf, sizeof(buf), path);

    CHECK(ret == 0, "empty file should return 0");

    unlink(path);
}

/* Exactly filling the buffer is allowed; one byte more is not. */
static void
test_exact_buffer_size(void)
{
    char       buf[32];
    ngx_int_t  ret;

    if (write_temp_file(32) != 0) {
        CHECK(0, "failed to create temp file");
        return;
    }

    ret = ngx_xquic_read_file_data(buf, sizeof(buf), path);

    CHECK(ret == 32, "file exactly filling the buffer should be accepted");

    unlink(path);
}

/*
 * The stream must be closed on every return path. Regression test: the helper
 * used to leak a FILE * on success and on the too-large path, which accumulated
 * once per worker on every reload.
 */
static void
test_no_fd_leak(void)
{
    char       buf[512];
    char       small[16];
    int        before, after, i;

    if (write_temp_file(48) != 0) {
        CHECK(0, "failed to create temp file");
        return;
    }

    /* warm up so that any one-off allocation is not counted */
    (void) ngx_xquic_read_file_data(buf, sizeof(buf), path);

    before = count_open_fds();

    for (i = 0; i < 200; i++) {
        /* success path */
        (void) ngx_xquic_read_file_data(buf, sizeof(buf), path);
        /* too-large path */
        (void) ngx_xquic_read_file_data(small, sizeof(small), path);
        /* open failure path */
        (void) ngx_xquic_read_file_data(buf, sizeof(buf),
                                        "/tmp/ngx_xquic_no_such_key");
    }

    after = count_open_fds();

    CHECK(before == after, "no file descriptor should leak across calls");

    unlink(path);
}

/* --- main ------------------------------------------------------------ */

int
main(void)
{
    test_reads_whole_file();
    test_missing_file();
    test_file_larger_than_buffer();
    test_empty_file();
    test_exact_buffer_size();
    test_no_fd_leak();

    printf("%d tests run, %d failed\n", tests_run, tests_failed);

    return tests_failed == 0 ? 0 : 1;
}
