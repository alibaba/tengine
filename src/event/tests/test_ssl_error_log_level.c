/*
 * Execute ngx_ssl_connection_error() extracted verbatim from production.
 * OpenSSL supplies the real error queue and SNI; nginx allocation and the
 * final log sink are stubbed to observe severity without socket races.
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/ssl.h>
#include <openssl/err.h>

#include "ssl_error_constants.inc"

typedef uintptr_t ngx_uint_t;
typedef int ngx_err_t;
typedef unsigned char u_char;
typedef struct {
    SSL *connection;
    unsigned handshaked;
    ngx_uint_t handshake_error_log_level;
} ngx_ssl_connection_t;
typedef struct {
    ngx_ssl_connection_t *ssl;
    ngx_connection_log_error_e log_error;
    void *pool;
    void *log;
} ngx_connection_t;

#define NGX_ECONNRESET ECONNRESET
#define NGX_ECONNABORTED ECONNABORTED
#define NGX_EPIPE EPIPE
#define NGX_ENOTCONN ENOTCONN
#define NGX_ETIMEDOUT ETIMEDOUT
#define NGX_ECONNREFUSED ECONNREFUSED
#define NGX_ENETDOWN ENETDOWN
#define NGX_ENETUNREACH ENETUNREACH
#define NGX_EHOSTDOWN EHOSTDOWN
#define NGX_EHOSTUNREACH EHOSTUNREACH

static ngx_uint_t logged_level;
static ngx_err_t logged_errno;
static char logged_text[1024];
static unsigned assertions;
#if (T_NGX_SSL_ERR_LOG_ALI)
static void *allocation;
static int fail_allocation;

static void *
ngx_palloc(void *pool, size_t size)
{
    (void) pool;
    if (fail_allocation) {
        return NULL;
    }
    allocation = malloc(size);
    return allocation;
}

static void *
ngx_cpymem(void *dst, const void *src, size_t size)
{
    memcpy(dst, src, size);
    return (u_char *) dst + size;
}
#define ngx_strlen strlen
#endif

static void
ngx_ssl_error(ngx_uint_t level, void *log, ngx_err_t err, char *text)
{
    (void) log;
    logged_level = level;
    logged_errno = err;
    snprintf(logged_text, sizeof(logged_text), "%s", text);
    ERR_clear_error();
}

#include "ssl_error_functions.inc"

#define CHECK(expr) do { \
    assertions++; \
    if (!(expr)) { \
        fprintf(stderr, "assertion failed at line %d: %s\n", __LINE__, #expr); \
        return 1; \
    } \
} while (0)

static void
invoke(ngx_connection_t *c, int sslerr, ngx_err_t err, int reason, char *text)
{
    ERR_clear_error();
    if (reason) {
        ERR_put_error(ERR_LIB_SSL, 0, reason, __FILE__, __LINE__);
    }
    logged_level = 0;
    ngx_ssl_connection_error(c, sslerr, err, text);
#if (T_NGX_SSL_ERR_LOG_ALI)
    free(allocation);
    allocation = NULL;
#endif
}

int
main(void)
{
    SSL_CTX *ctx;
    ngx_ssl_connection_t sc;
    ngx_connection_t c;
    size_t i, j, k, p;
    unsigned handshaked;
    int errors[] = {
        NGX_ECONNRESET, NGX_EPIPE, NGX_ENOTCONN, NGX_ETIMEDOUT,
        NGX_ECONNREFUSED, NGX_ENETDOWN, NGX_ENETUNREACH,
        NGX_EHOSTDOWN, NGX_EHOSTUNREACH,
#if (NGX_WIN32)
        NGX_ECONNABORTED,
#endif
    };
    int reasons[] = {
        SSL_R_WRONG_VERSION_NUMBER, SSL_R_DECRYPTION_FAILED_OR_BAD_RECORD_MAC,
        SSL_R_UNEXPECTED_RECORD, SSL_AD_REASON_OFFSET + SSL_AD_INTERNAL_ERROR
    };
    ngx_uint_t levels[] = {
        0, NGX_LOG_INFO, NGX_LOG_NOTICE, NGX_LOG_WARN, NGX_LOG_ERR
    };
    ngx_connection_log_error_e policies[] = {
        NGX_ERROR_INFO, NGX_ERROR_IGNORE_ECONNRESET,
        NGX_ERROR_ERR, NGX_ERROR_ALERT
    };
    char *operations[] = {
        "SSL_do_handshake() failed", "SSL_read() failed", "SSL_write() failed",
        "SSL_read_early_data() failed", "SSL_write_early_data() failed",
        "SSL_sendfile() failed", "SSL_shutdown() failed"
    };

    memset(&sc, 0, sizeof(sc));
    memset(&c, 0, sizeof(c));
    ctx = SSL_CTX_new(TLS_method());
    CHECK(ctx != NULL);
    sc.connection = SSL_new(ctx);
    CHECK(sc.connection != NULL);
    c.ssl = &sc;
    CHECK(SSL_set_tlsext_host_name(sc.connection, "unit.example") == 1);

    for (handshaked = 0; handshaked <= 1; handshaked++) {
        sc.handshaked = handshaked;
        for (i = 0; i < sizeof(levels) / sizeof(levels[0]); i++) {
            sc.handshake_error_log_level = levels[i];
            for (p = 0; p < sizeof(policies) / sizeof(policies[0]); p++) {
                ngx_uint_t expected;
                c.log_error = policies[p];
                expected = (c.log_error == NGX_ERROR_ERR) ? NGX_LOG_ERR
                         : (c.log_error == NGX_ERROR_ALERT) ? NGX_LOG_CRIT
                         : NGX_LOG_INFO;
#if (T_NGX_SSL_ERR_LOG_ALI)
                if (expected == NGX_LOG_INFO && !handshaked && levels[i]) {
                    expected = levels[i];
                }
#endif
                for (j = 0; j < sizeof(operations) / sizeof(operations[0]); j++) {
                    for (k = 0; k < sizeof(errors) / sizeof(errors[0]); k++) {
                        invoke(&c, SSL_ERROR_SYSCALL, errors[k], 0, operations[j]);
                        CHECK(logged_level == expected);
                        CHECK(logged_errno == errors[k]);
                        CHECK(strstr(logged_text, operations[j]) != NULL);
#if (T_NGX_SSL_ERR_LOG_ALI)
                        CHECK(strstr(logged_text, "SNI: unit.example ") != NULL);
#endif
                    }
                    for (k = 0; k < sizeof(reasons) / sizeof(reasons[0]); k++) {
                        invoke(&c, SSL_ERROR_SSL, 0, reasons[k], operations[j]);
                        CHECK(logged_level == expected);
                    }
                }
                /* Unknown failures remain critical, even at a raised level. */
                invoke(&c, SSL_ERROR_SYSCALL, EIO, 0, operations[1]);
                CHECK(logged_level == NGX_LOG_CRIT);
                invoke(&c, SSL_ERROR_SSL, 0, ERR_R_MALLOC_FAILURE, operations[1]);
                CHECK(logged_level == NGX_LOG_CRIT);
            }
        }
    }

#if (T_NGX_SSL_ERR_LOG_ALI)
    /* Preserve SNI enrichment, safe formatting, and allocation fallback. */
    c.log_error = NGX_ERROR_INFO;
    sc.handshaked = 1;
    CHECK(SSL_set_tlsext_host_name(sc.connection, "percent%s.example") == 1);
    invoke(&c, SSL_ERROR_SYSCALL, NGX_ECONNRESET, 0, operations[1]);
    CHECK(strstr(logged_text, "SNI: percent&s.example ") != NULL);
    fail_allocation = 1;
    invoke(&c, SSL_ERROR_SYSCALL, NGX_ECONNRESET, 0, operations[1]);
    CHECK(logged_level == NGX_LOG_INFO);
    CHECK(strcmp(logged_text, operations[1]) == 0);
#endif

    SSL_free(sc.connection);
    SSL_CTX_free(ctx);
    printf("SSL error log level: %u assertions passed (ALI=%d, WIN32=%d)\n",
           assertions, T_NGX_SSL_ERR_LOG_ALI, NGX_WIN32);
    return 0;
}
