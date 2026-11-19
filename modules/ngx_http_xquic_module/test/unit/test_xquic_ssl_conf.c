/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for the xquic certificate configuration helpers
 * (ngx_xquic_ssl_conf.h).
 *
 * These cover the case reported from the field: a "listen ... xquic" server
 * without xquic_ssl_certificate. The certificate used to default to the bare
 * relative path "./server.crt", which resolves against the working directory of
 * the worker -- "/" under systemd -- so the engine could never load it. Every
 * worker exited with fatal code 2 and could not be respawned, taking the plain
 * HTTP listeners down too, while "nginx -t" still reported the configuration as
 * valid. The helpers below turn that into a startup time error naming the
 * missing directive, or the unreadable path and why.
 *
 * Only ngx_str_t, ngx_err_t and ngx_inline are needed from the surrounding
 * translation unit; they are stubbed below so the exact same source that ships
 * in the module is exercised without requiring a full nginx build:
 *
 *     cc -Wall -Wextra -o test_xquic_ssl_conf test_xquic_ssl_conf.c
 *     ./test_xquic_ssl_conf
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>

/* --- minimal ngx compatibility layer --------------------------------- */

typedef int             ngx_err_t;
typedef unsigned char   u_char;

typedef struct {
    size_t      len;
    u_char     *data;
} ngx_str_t;

#define ngx_inline      inline

#include "../../ngx_xquic_ssl_conf.h"

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

/*
 * Build an ngx_str_t over a literal the way ngx_conf_set_str_slot() leaves one:
 * NUL terminated, len excluding the terminator.
 */
static ngx_str_t
str(char *s)
{
    ngx_str_t  v;

    v.data = (u_char *) s;
    v.len = strlen(s);

    return v;
}

/* An unset directive: what ngx_pcalloc() of the main conf leaves behind. */
static ngx_str_t
unset(void)
{
    ngx_str_t  v;

    v.data = NULL;
    v.len = 0;

    return v;
}

static char  tmpl[] = "/tmp/ngx_xquic_cert_test_XXXXXX";
static char  path[sizeof(tmpl)];

/* Create a temp file standing in for a certificate, with the given mode. */
static int
write_temp_cert(mode_t mode)
{
    int  fd;

    memcpy(path, tmpl, sizeof(tmpl));

    fd = mkstemp(path);
    if (fd == -1) {
        return -1;
    }

    if (write(fd, "-----BEGIN CERTIFICATE-----\n", 28) != 28) {
        close(fd);
        unlink(path);
        return -1;
    }

    close(fd);

    if (chmod(path, mode) != 0) {
        unlink(path);
        return -1;
    }

    return 0;
}

/* --- test cases: which directive is missing --------------------------- */

/*
 * The reported case: an xquic listener with neither directive configured. The
 * certificate has to be named first, since that is what the user has to add.
 */
static void
test_both_unset_reports_certificate(void)
{
    ngx_str_t    cert = unset();
    ngx_str_t    key = unset();
    const char  *missing;

    missing = ngx_xquic_ssl_cert_missing(&cert, &key);

    CHECK(missing != NULL, "an unconfigured certificate must be reported");
    CHECK(missing != NULL && strcmp(missing, "xquic_ssl_certificate") == 0,
          "the missing directive should be named xquic_ssl_certificate");
}

/* Half a configuration is still a broken one: the key alone cannot serve. */
static void
test_key_only_reports_certificate(void)
{
    ngx_str_t    cert = unset();
    ngx_str_t    key = str("/etc/tengine/server.key");
    const char  *missing;

    missing = ngx_xquic_ssl_cert_missing(&cert, &key);

    CHECK(missing != NULL && strcmp(missing, "xquic_ssl_certificate") == 0,
          "a key without a certificate should report the certificate");
}

static void
test_cert_only_reports_key(void)
{
    ngx_str_t    cert = str("/etc/tengine/server.crt");
    ngx_str_t    key = unset();
    const char  *missing;

    missing = ngx_xquic_ssl_cert_missing(&cert, &key);

    CHECK(missing != NULL && strcmp(missing, "xquic_ssl_certificate_key") == 0,
          "a certificate without a key should report the key");
}

static void
test_both_set_reports_nothing(void)
{
    ngx_str_t    cert = str("/etc/tengine/server.crt");
    ngx_str_t    key = str("/etc/tengine/server.key");
    const char  *missing;

    missing = ngx_xquic_ssl_cert_missing(&cert, &key);

    CHECK(missing == NULL, "a complete configuration must not be rejected");
}

/*
 * A zero length value with a non-NULL data pointer counts as unset too: an
 * empty string is not a usable path, and treating it as one would push the
 * failure back down into the worker.
 */
static void
test_empty_string_counts_as_unset(void)
{
    ngx_str_t    cert = str("");
    ngx_str_t    key = str("/etc/tengine/server.key");
    const char  *missing;

    missing = ngx_xquic_ssl_cert_missing(&cert, &key);

    CHECK(missing != NULL && strcmp(missing, "xquic_ssl_certificate") == 0,
          "an empty certificate path should count as unset");
}

/*
 * "Not configured" and "configured but unreadable" have to stay distinguishable.
 * The old defaults collapsed them: an unset xquic_ssl_certificate became the
 * literal "./server.crt", so the only symptom left was a missing file, and the
 * log could not say that the directive was the thing that was absent.
 */
static void
test_unset_is_not_reported_as_unreadable(void)
{
    ngx_str_t    cert = unset();
    ngx_str_t    key = unset();
    const char  *missing;

    missing = ngx_xquic_ssl_cert_missing(&cert, &key);

    CHECK(missing != NULL,
          "an unset directive must be reported before any path is probed");

    /* and the reverse: a configured path is never reported as missing */
    cert = str("/tmp/ngx_xquic_no_such_cert");
    key = str("/tmp/ngx_xquic_no_such_key");

    missing = ngx_xquic_ssl_cert_missing(&cert, &key);

    CHECK(missing == NULL,
          "a configured path must be left to the readability probe");
    CHECK(ngx_xquic_cert_file_check("/tmp/ngx_xquic_no_such_cert") == ENOENT,
          "the probe should be what reports a configured path that is absent");
}

/* --- test cases: readability probe ------------------------------------ */

static void
test_readable_file(void)
{
    ngx_err_t  err;

    if (write_temp_cert(0644) != 0) {
        CHECK(0, "failed to create temp certificate");
        return;
    }

    err = ngx_xquic_cert_file_check(path);

    CHECK(err == 0, "a readable certificate should pass");

    unlink(path);
}

/*
 * The failure the old default produced: a relative path that resolves nowhere.
 * ENOENT is what has to reach the log, so that the message can say which path
 * was tried and that it does not exist.
 */
static void
test_missing_file_reports_enoent(void)
{
    ngx_err_t  err;

    err = ngx_xquic_cert_file_check("/tmp/ngx_xquic_no_such_cert");

    CHECK(err == ENOENT, "a missing certificate should report ENOENT");
}

/*
 * A certificate the worker cannot read after dropping privileges. This is the
 * other half of the same symptom -- workers dying with fatal code 2 -- and it
 * only reproduces as a non-root user, so skip the check when running as root.
 */
static void
test_unreadable_file_reports_eacces(void)
{
    ngx_err_t  err;

    if (geteuid() == 0) {
        printf("SKIP: unreadable certificate check needs a non-root user\n");
        return;
    }

    if (write_temp_cert(0000) != 0) {
        CHECK(0, "failed to create temp certificate");
        return;
    }

    err = ngx_xquic_cert_file_check(path);

    CHECK(err == EACCES, "a certificate with no read permission should report EACCES");

    unlink(path);
}

/* A directory is not a certificate; the errno must still be a real one. */
static void
test_directory_is_not_a_certificate(void)
{
    ngx_err_t  err;

    err = ngx_xquic_cert_file_check("/tmp");

    /*
     * open(O_RDONLY) on a directory succeeds on Linux and fails with EISDIR on
     * some other systems. Either way the probe must not report a bogus errno,
     * and the engine reports the parse failure afterwards.
     */
    CHECK(err == 0 || err == EISDIR, "a directory should not yield a bogus errno");
}

/*
 * Reproduce the mechanism behind the report: the very same certificate is
 * reachable by absolute path and unreachable by the relative one the old default
 * used, because the latter resolves against the working directory. A worker
 * started from systemd runs with "/" as its working directory, so "./server.crt"
 * meant "/server.crt". This is why the paths are now resolved against the prefix
 * in ngx_http_xquic_init_main_conf() and no longer default to "./".
 */
static void
test_relative_path_follows_cwd(void)
{
    ngx_err_t  err;
    char       relative[sizeof(tmpl) + 2];
    char       cwd[4096];

    if (getcwd(cwd, sizeof(cwd)) == NULL) {
        CHECK(0, "failed to read the working directory");
        return;
    }

    if (write_temp_cert(0644) != 0) {
        CHECK(0, "failed to create temp certificate");
        return;
    }

    /* "/tmp/ngx_xquic_cert_test_XXXXXX" -> "./ngx_xquic_cert_test_XXXXXX" */
    snprintf(relative, sizeof(relative), ".%s", path + sizeof("/tmp") - 1);

    err = ngx_xquic_cert_file_check(path);
    CHECK(err == 0, "the certificate should be readable by absolute path");

    if (chdir("/tmp") != 0) {
        CHECK(0, "failed to chdir to /tmp");
        unlink(path);
        return;
    }

    err = ngx_xquic_cert_file_check(relative);
    CHECK(err == 0, "the relative path should resolve inside its own directory");

    /* what the worker actually sees under systemd */
    if (chdir("/") != 0) {
        CHECK(0, "failed to chdir to /");
        unlink(path);
        return;
    }

    err = ngx_xquic_cert_file_check(relative);
    CHECK(err == ENOENT,
          "the same relative path must fail from another working directory");

    err = ngx_xquic_cert_file_check(path);
    CHECK(err == 0, "the absolute path must keep working from anywhere");

    if (chdir(cwd) != 0) {
        CHECK(0, "failed to restore the working directory");
    }

    unlink(path);
}

/* The probe must not leak the descriptor it opens. */
static void
test_no_fd_leak(void)
{
    int  fd, before = 0, after = 0, i;

    if (write_temp_cert(0644) != 0) {
        CHECK(0, "failed to create temp certificate");
        return;
    }

    (void) ngx_xquic_cert_file_check(path);

    for (fd = 0; fd < 256; fd++) {
        if (fcntl(fd, F_GETFD) != -1) {
            before++;
        }
    }

    for (i = 0; i < 200; i++) {
        (void) ngx_xquic_cert_file_check(path);
        (void) ngx_xquic_cert_file_check("/tmp/ngx_xquic_no_such_cert");
    }

    for (fd = 0; fd < 256; fd++) {
        if (fcntl(fd, F_GETFD) != -1) {
            after++;
        }
    }

    CHECK(before == after, "no file descriptor should leak across calls");

    unlink(path);
}

/* --- main ------------------------------------------------------------ */

int
main(void)
{
    test_both_unset_reports_certificate();
    test_key_only_reports_certificate();
    test_cert_only_reports_key();
    test_both_set_reports_nothing();
    test_empty_string_counts_as_unset();
    test_unset_is_not_reported_as_unreadable();

    test_readable_file();
    test_missing_file_reports_enoent();
    test_unreadable_file_reports_eacces();
    test_directory_is_not_a_certificate();
    test_relative_path_follows_cwd();
    test_no_fd_leak();

    printf("%d tests run, %d failed\n", tests_run, tests_failed);

    return tests_failed == 0 ? 0 : 1;
}
