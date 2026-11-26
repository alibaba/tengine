/* Execute the complete production writers against controlled send results. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

typedef intptr_t ngx_int_t;
typedef uintptr_t ngx_uint_t;
typedef unsigned char u_char;
typedef unsigned long ngx_msec_t;
typedef struct ngx_chain_s ngx_chain_t;
typedef struct ngx_connection_s ngx_connection_t;

typedef struct {
    u_char *start, *pos, *last;
    void *file;
    off_t file_pos, file_last;
    unsigned temporary, recycled, in_file, memory, flush, sync, last_buf;
} ngx_buf_t;
struct ngx_chain_s { ngx_buf_t *buf; ngx_chain_t *next; };
typedef struct {
    unsigned ready, delayed, posted;
    ngx_msec_t timer;
} ngx_event_t;
struct ngx_connection_s {
    void *log;
    ngx_event_t *write;
    off_t sent;
    unsigned buffered, error, need_last_buf, need_flush_buf;
    ngx_chain_t *(*send_chain)(ngx_connection_t *, ngx_chain_t *, off_t);
};
typedef struct {
    off_t limit_rate, limit_rate_after;
    size_t postpone_output, sendfile_max_chunk;
} ngx_http_core_loc_conf_t;
typedef struct ngx_http_request_s {
    ngx_connection_t *connection;
    ngx_chain_t *out;
    void *pool, *postponed;
    struct ngx_http_request_s *main;
    struct { ngx_msec_t resp_send_start_time, resp_send_finish_time; } stat_time;
    off_t limit_rate, limit_rate_after;
    long start_sec;
    unsigned limit_rate_set, limit_rate_after_set, response_sent;
} ngx_http_request_t;
typedef struct {
    ngx_chain_t *out, **last;
    ngx_connection_t *connection;
    void *pool;
    off_t limit;
} ngx_chain_writer_ctx_t;

#define NGX_OK 0
#define NGX_ERROR -1
#define NGX_AGAIN -2
#define NGX_CHAIN_ERROR ((ngx_chain_t *) -1)
#define NGX_LOWLEVEL_BUFFERED 0x0f
#define NGX_HTTP_WRITE_BUFFERED 0x10
#define ngx_log_error(...) ((void) 0)
#define ngx_log_debug1(...) ((void) 0)
#define ngx_log_debug2(...) ((void) 0)
#define ngx_log_debug3(...) ((void) 0)
#define ngx_log_debug7(...) ((void) 0)
#define ngx_debug_point() ((void) 0)
#define ngx_buf_size(b) ((b)->in_file ? (b)->file_last - (b)->file_pos : \
                        (off_t) ((b)->last - (b)->pos))
#define ngx_buf_special(b) (((b)->flush || (b)->sync || (b)->last_buf) \
                            && !(b)->memory && !(b)->in_file)
#define ngx_http_get_module_loc_conf(r, module) (&loc_conf)
#define ngx_http_complex_value_size(r, value, fallback) (value)
#define ngx_time() 100L
#define ngx_post_event(ev, queue) ((ev)->posted = 1)

static ngx_msec_t ngx_current_msec = 100000;
static ngx_http_core_loc_conf_t loc_conf;
static unsigned checks, failures, calls, freed, used;
static ngx_chain_t links[32];
static ngx_event_t write_event;
static ngx_connection_t connection;
static ngx_http_request_t request;
static ngx_chain_writer_ctx_t writer;
static ngx_buf_t buffer;
static u_char payload[8192];
static off_t progress, observed_limit;
static unsigned fail_send, block_send, low_buffered;

#define CHECK(c) do { checks++; if (!(c)) { failures++; \
    fprintf(stderr, "assertion failed: %s (line %d)\n", #c, __LINE__); } } while (0)

static ngx_chain_t *ngx_alloc_chain_link(void *pool)
{
    (void) pool;
    if (used == sizeof(links) / sizeof(links[0])) { abort(); }
    return &links[used++];
}
static void ngx_free_chain(void *pool, ngx_chain_t *cl)
{ (void) pool; (void) cl; freed++; }
static void ngx_add_timer(ngx_event_t *ev, ngx_msec_t delay)
{ ev->timer = delay; }

#if (T_NGX_REQ_STATUS)
static ngx_int_t (*ngx_http_write_filter_stat)(ngx_http_request_t *r);
#endif

#include "write_progress_functions.inc"

static ngx_chain_t *send_result(ngx_connection_t *c, ngx_chain_t *in, off_t limit)
{
    calls++;
    observed_limit = limit;
    if (fail_send) { return NGX_CHAIN_ERROR; }
    if (block_send) { c->write->ready = 0; }
    c->buffered |= low_buffered;
    c->sent += progress;
    while (in && progress >= ngx_buf_size(in->buf)) {
        progress -= ngx_buf_size(in->buf);
        in->buf->pos = in->buf->last;
        in = in->next;
    }
    if (in) { in->buf->pos += progress; }
    return in;
}

static void reset(void)
{
    memset(&connection, 0, sizeof(connection));
    memset(&request, 0, sizeof(request));
    memset(&writer, 0, sizeof(writer));
    memset(&write_event, 0, sizeof(write_event));
    memset(&loc_conf, 0, sizeof(loc_conf));
    memset(&buffer, 0, sizeof(buffer));
    buffer.start = buffer.pos = payload;
    buffer.last = payload + sizeof(payload);
    buffer.memory = buffer.last_buf = 1;
    connection.write = &write_event;
    connection.send_chain = send_result;
    connection.sent = 1000;
    write_event.ready = 1;
    request.connection = &connection;
    request.main = &request;
    request.limit_rate_set = request.limit_rate_after_set = 1;
    request.start_sec = 1;
    writer.connection = &connection;
    writer.last = &writer.out;
    calls = freed = used = 0;
    progress = observed_limit = 0;
    fail_send = block_send = low_buffered = 0;
}

static ngx_int_t run_writer(int http)
{
    ngx_chain_t input = { &buffer, NULL };
    return http ? ngx_http_write_filter(&request, &input) :
                  ngx_chain_writer(&writer, &input);
}

static void writer_matrix(int http)
{
    reset();
    CHECK(run_writer(http) == NGX_AGAIN);
    CHECK(calls == 1 && !write_event.posted && write_event.ready);
    CHECK(!request.response_sent && freed == 0);
    CHECK(http ? request.out != NULL : writer.out != NULL);
    if (http) { CHECK(connection.buffered & NGX_HTTP_WRITE_BUFFERED); }

    /* A later write attempt must resume and finish the pending output. */
    progress = sizeof(payload);
    CHECK((http ? ngx_http_write_filter(&request, NULL) :
                  ngx_chain_writer(&writer, NULL)) == NGX_OK);
    CHECK(calls == 2 && !write_event.posted && freed == 1);
    CHECK(http ? request.out == NULL : writer.out == NULL);
    CHECK(http ? request.response_sent : writer.last == &writer.out);
    CHECK(!(connection.buffered & NGX_HTTP_WRITE_BUFFERED));

    reset();
    progress = 1;
    CHECK(run_writer(http) == NGX_AGAIN);
    CHECK(write_event.posted && connection.sent == 1001);
    CHECK(buffer.pos == payload + 1 && freed == 0);

    reset();
    progress = sizeof(payload);
    CHECK(run_writer(http) == NGX_OK);
    CHECK(!write_event.posted && freed == 1);

    reset();
    block_send = 1;
    CHECK(run_writer(http) == NGX_AGAIN);
    CHECK(!write_event.posted && !write_event.ready);

    reset();
    fail_send = 1;
    CHECK(run_writer(http) == NGX_ERROR);
    CHECK(!write_event.posted && freed == 0);
    if (http) { CHECK(connection.error); }

    reset();
    progress = sizeof(payload);
    low_buffered = 1;
    CHECK(run_writer(http) == NGX_AGAIN);
    CHECK(!write_event.posted && connection.buffered == 1);
}

static void rate_matrix(void)
{
    /* A nonzero snapshot must not be changed by limit_rate_after. */
    reset();
    request.limit_rate = 1000000;
    request.limit_rate_after = 100;
    CHECK(run_writer(1) == NGX_AGAIN);
    CHECK(!write_event.posted && !write_event.delayed);
    CHECK(write_event.timer == 0 && connection.sent == 1000);

    reset();
    request.limit_rate = 1000000;
    request.limit_rate_after = 100;
    progress = 1;
    CHECK(run_writer(1) == NGX_AGAIN);
    CHECK(write_event.posted && !write_event.delayed);

    reset();
    request.limit_rate = 1000;
    request.limit_rate_after = 1000;
    connection.sent = 900;
    progress = 200;
    CHECK(run_writer(1) == NGX_AGAIN);
    CHECK(write_event.delayed && write_event.timer == 100);
    CHECK(!write_event.posted && connection.sent == 1100);

    reset();
    request.limit_rate = 1000;
    request.limit_rate_after = 1000;
    connection.sent = 900;
    progress = 50;
    CHECK(run_writer(1) == NGX_AGAIN);
    CHECK(write_event.posted && !write_event.delayed);

    reset();
    write_event.delayed = 1;
    CHECK(run_writer(1) == NGX_AGAIN);
    CHECK(calls == 0 && !write_event.posted);

    reset();
    request.limit_rate = 10;
    connection.sent = 2000;
    CHECK(run_writer(1) == NGX_AGAIN);
    CHECK(calls == 0 && write_event.delayed && write_event.timer > 0);

    reset();
    loc_conf.sendfile_max_chunk = 4096;
    CHECK(run_writer(1) == NGX_AGAIN);
    CHECK(observed_limit == 4096 && !write_event.posted);
}

int main(void)
{
    (void) ngx_current_msec;
    writer_matrix(0);
    writer_matrix(1);
    rate_matrix();
    printf("write progress: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
