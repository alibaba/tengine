/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

#ifndef _NGX_XQUIC_SSL_CONF_H_INCLUDED_
#define _NGX_XQUIC_SSL_CONF_H_INCLUDED_


#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

/*
 * Helpers validating the engine level xquic certificate configuration.
 *
 * xquic loads its certificate inside the engine, once per worker, long after
 * the configuration has been parsed. A missing or unreadable path therefore
 * used to surface only as
 *
 *     worker process exited with fatal code 2 and cannot be respawned
 *
 * which takes every listener down with it, plain HTTP included, and leaves no
 * hint about the actual cause. These helpers let the same condition be
 * reported while the configuration is still being validated, and with the
 * offending path named in the message.
 *
 * Only ngx_str_t, ngx_err_t and ngx_inline are required from the surrounding
 * translation unit, so the stand-alone unit test under test/unit/ can exercise
 * this very source with a minimal stub instead of a full nginx build.
 */

/*
 * Report which of the two mandatory certificate directives is missing, or NULL
 * when both are configured.
 *
 * Neither has a default: xquic cannot serve a handshake without an engine
 * level certificate, so an unset value is a configuration error rather than
 * something to be guessed at. The returned name is a static string, safe to
 * log with "%s".
 */
static ngx_inline const char *
ngx_xquic_ssl_cert_missing(ngx_str_t *cert, ngx_str_t *key)
{
    if (cert->data == NULL || cert->len == 0) {
        return "xquic_ssl_certificate";
    }

    if (key->data == NULL || key->len == 0) {
        return "xquic_ssl_certificate_key";
    }

    return NULL;
}

/*
 * Check that path can be opened for reading. Returns 0 on success, otherwise
 * the errno explaining the failure, ready to be passed to ngx_log_error() so
 * that it appends the system message.
 *
 * Opening is deliberate rather than stat()ing: the master runs as root while
 * the worker does not, and a key that only root can read is the failure this
 * is most often called upon to explain. Only an open() as the effective user
 * reproduces it.
 */
static ngx_inline ngx_err_t
ngx_xquic_cert_file_check(const char *path)
{
    int        fd;
    ngx_err_t  err;

    fd = open(path, O_RDONLY);
    if (fd == -1) {
        err = errno;
        return err ? err : EACCES;
    }

    close(fd);

    return 0;
}


#endif /* _NGX_XQUIC_SSL_CONF_H_INCLUDED_ */
