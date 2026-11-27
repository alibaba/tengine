/*
 * CVE-2026-123007: execute the production functions extracted by the test
 * driver directly instead of copying the flow control algorithm. Networking,
 * allocation and scheduling are replaced by minimal stubs so that unsent,
 * partially sent and cancelled DATA can be reproduced deterministically.
 * Entry: python3 -m unittest discover -v -s src/http/v2/tests
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <stddef.h>
typedef intptr_t ngx_int_t;
typedef uintptr_t ngx_uint_t;
/* Only the production queue primitives are used; the remaining ngx types
 * are provided by the stubs below. */
#define _NGX_CONFIG_H_INCLUDED_
#define _NGX_CORE_H_INCLUDED_
#include "ngx_queue.h"

/* Constants are extracted from the production headers as well. */
#include "flow_control_constants.inc"

typedef unsigned char u_char;
typedef void *ngx_buf_tag_t;
typedef struct ngx_event_s ngx_event_t;
typedef struct ngx_http_v2_stream_s ngx_http_v2_stream_t;
typedef struct ngx_http_v2_connection_s ngx_http_v2_connection_t;
typedef struct ngx_http_v2_out_frame_s ngx_http_v2_out_frame_t;
typedef struct ngx_chain_s ngx_chain_t;
typedef struct ngx_buf_s ngx_buf_t;

#define NGX_OK 0
#define NGX_ERROR -1
#define NGX_AGAIN -2
#define NGX_DECLINED -5
#define NGX_HTTP_V2_BUFFERED 1
#define NGX_CHAIN_ERROR ((ngx_chain_t *) -1)
#define NGX_HTTP_V2_NO_TRAILERS ((ngx_http_v2_out_frame_t *) -1)
#define ngx_inline inline
#define NGX_LOG_DEBUG_HTTP 0
#define ngx_log_error(...) ((void) 0)
#define ngx_log_debug0(...) ((void) 0)
#define ngx_log_debug1(...) ((void) 0)
#define ngx_log_debug2(...) ((void) 0)
#define ngx_log_debug4(...) ((void) 0)
#define ngx_buf_in_memory(b) ((b)->memory)
#define ngx_buf_size(b) ((b)->memory ? (off_t) ((b)->last - (b)->pos) : \
                        (b)->file_last - (b)->file_pos)
#define ngx_free_chain(pool, cl) ((void) (cl))
#define ngx_http_get_module_loc_conf(r, module) (&loc_conf)
#define ngx_post_event(ev, queue) ((ev)->posted = 1)

struct ngx_event_s {
    int active, ready, delayed, posted;
    void (*handler)(ngx_event_t *);
};
typedef struct {
    void *data, *log;
    ngx_event_t *write;
    unsigned buffered;
} ngx_connection_t;
typedef struct {
    ngx_connection_t *connection;
    ngx_http_v2_stream_t *stream;
    void *pool;
    size_t header_size;
} ngx_http_request_t;
typedef struct {
    ngx_uint_t id;
    ngx_http_v2_stream_t *stream;
} ngx_http_v2_node_t;
typedef struct { size_t chunk_size; } ngx_http_v2_loc_conf_t;
struct ngx_buf_s {
    u_char *pos, *last;
    ngx_buf_tag_t tag;
    ngx_buf_t *shadow;
    off_t file_pos, file_last;
    int memory, in_file, last_buf, flush;
};
struct ngx_chain_s { ngx_buf_t *buf; ngx_chain_t *next; };
struct ngx_http_v2_out_frame_s {
    ngx_chain_t *first, *last;
    ngx_http_v2_out_frame_t *next;
    ngx_http_v2_stream_t *stream;
    ngx_int_t (*handler)(ngx_http_v2_connection_t *, ngx_http_v2_out_frame_t *);
    size_t length;
    unsigned blocked, fin;
};
struct ngx_http_v2_connection_s {
    ngx_connection_t *connection;
    size_t send_window, send_queued, frame_size, payload_bytes;
    ngx_queue_t waiting;
    struct { size_t length; ngx_uint_t sid; } state;
    ngx_http_v2_out_frame_t *last_out;
};
struct ngx_http_v2_stream_s {
    ngx_http_request_t *request;
    ngx_http_v2_connection_t *connection;
    ngx_http_v2_node_t *node;
    ssize_t send_window;
    ngx_uint_t queued;
    unsigned waiting, exhausted, out_closed;
    ngx_queue_t queue;
    ngx_chain_t *free_bufs, *free_frame_headers;
};

static int ngx_http_v2_module;
static ngx_http_v2_loc_conf_t loc_conf = { 16384 };
static ngx_http_v2_node_t *lookup_node;
static int connection_error, stream_error, saved, wakeups;
static unsigned checks, failures;
static ngx_chain_t chains[64];
static ngx_http_v2_out_frame_t frames[32];
static unsigned chain_n, frame_n;

#define CHECK(c) do { checks++; if (!(c)) { failures++; \
    fprintf(stderr, "assertion failed: %s (line %d)\n", #c, __LINE__); } } while (0)

static void wake(ngx_event_t *ev) { (void) ev; wakeups++; }
static u_char *ngx_http_v2_connection_error(ngx_http_v2_connection_t *h, int code)
{ (void) h; connection_error = code; return NULL; }
static u_char *ngx_http_v2_state_complete(ngx_http_v2_connection_t *h,
    u_char *pos, u_char *end)
{ (void) h; (void) end; return pos; }
static u_char *ngx_http_v2_state_save(ngx_http_v2_connection_t *h,
    u_char *pos, u_char *end,
    u_char *(*handler)(ngx_http_v2_connection_t *, u_char *, u_char *))
{ (void) h; (void) end; (void) handler; saved++; return pos; }
static size_t ngx_http_v2_parse_window(u_char *p)
{ return (((size_t) p[0] << 24) | ((size_t) p[1] << 16) |
          ((size_t) p[2] << 8) | p[3]) & 0x7fffffff; }
static ngx_http_v2_node_t *ngx_http_v2_get_node_by_id(
    ngx_http_v2_connection_t *h, ngx_uint_t sid, int alloc)
{ (void) h; (void) alloc; return lookup_node && lookup_node->id == sid ? lookup_node : NULL; }
static ngx_int_t ngx_http_v2_terminate_stream(ngx_http_v2_connection_t *h,
    ngx_http_v2_stream_t *s, int code)
{ (void) h; (void) s; stream_error = code; return NGX_OK; }
static ngx_chain_t *ngx_alloc_chain_link(void *pool)
{ (void) pool; if (chain_n == 64) abort(); return &chains[chain_n++]; }
static ngx_chain_t *ngx_http_v2_filter_get_shadow(ngx_http_v2_stream_t *s,
    ngx_buf_t *b, off_t offset, off_t size)
{ (void) s; (void) b; (void) offset; (void) size; abort(); return NULL; }
static ngx_http_v2_out_frame_t *ngx_http_v2_create_trailers_frame(ngx_http_request_t *r)
{ (void) r; return NGX_HTTP_V2_NO_TRAILERS; }
static ngx_int_t ngx_http_v2_data_frame_handler(ngx_http_v2_connection_t *,
    ngx_http_v2_out_frame_t *);
static ngx_http_v2_out_frame_t *ngx_http_v2_filter_get_data_frame(
    ngx_http_v2_stream_t *s, size_t len, ngx_chain_t *first, ngx_chain_t *last)
{
    ngx_http_v2_out_frame_t *f;
    if (frame_n == 32) abort();
    f = &frames[frame_n++];
    memset(f, 0, sizeof(*f));
    f->stream = s; f->length = len; f->first = first; f->last = last;
    f->handler = ngx_http_v2_data_frame_handler;
    return f;
}
/* Since nginx 1.31.6 frames are queued at an RFC 9218 priority position
 * instead of always at the head. The stub keeps the production insertion
 * semantics with a deterministic stream order: lower stream ids precede. */
static int ngx_http_v2_stream_precedes(ngx_http_v2_stream_t *s,
    ngx_http_v2_stream_t *stream)
{ return s->node->id <= stream->node->id; }
static ngx_http_v2_out_frame_t **ngx_http_v2_queue_position(
    ngx_http_v2_connection_t *h, ngx_http_v2_stream_t *s)
{
    ngx_http_v2_out_frame_t **out;
    for (out = &h->last_out; *out; out = &(*out)->next) {
        if ((*out)->blocked || (*out)->stream == NULL) break;
        if (ngx_http_v2_stream_precedes((*out)->stream, s)) break;
    }
    return out;
}
static void ngx_http_v2_queue_frame(ngx_http_v2_out_frame_t **out,
    ngx_http_v2_out_frame_t *f)
{ f->next = *out; *out = f; }
static ngx_int_t ngx_http_v2_flow_control(ngx_http_v2_connection_t *h,
    ngx_http_v2_stream_t *s)
{ return h->send_window && s->send_window > 0 ? NGX_OK : NGX_DECLINED; }
static ngx_int_t ngx_http_v2_filter_send(ngx_connection_t *c, ngx_http_v2_stream_t *s)
{ (void) c; (void) s; return NGX_AGAIN; }
static void ngx_http_v2_handle_frame(ngx_http_v2_stream_t *s,
    ngx_http_v2_out_frame_t *f)
{ (void) f; s->queued--; }
static void ngx_http_v2_handle_stream(ngx_http_v2_connection_t *h,
    ngx_http_v2_stream_t *s)
{ (void) h; (void) s; }

/* Include the complete production function bodies, preserving their control
 * branches and arithmetic type conversions at compile time. */
#include "flow_control_functions.inc"

static ngx_http_v2_connection_t h2c;
static ngx_http_v2_stream_t streams[2];
static ngx_http_request_t requests[2];
static ngx_http_v2_node_t nodes[2];
static ngx_connection_t connections[3];
static ngx_event_t events[3];
static u_char payload[16384];

static void reset(void)
{
    unsigned i;
    memset(&h2c, 0, sizeof(h2c));
    memset(streams, 0, sizeof(streams));
    memset(requests, 0, sizeof(requests));
    memset(connections, 0, sizeof(connections));
    memset(events, 0, sizeof(events));
    chain_n = frame_n = 0;
    connection_error = stream_error = saved = wakeups = 0;
    lookup_node = NULL;
    h2c.connection = &connections[2];
    h2c.send_window = NGX_HTTP_V2_DEFAULT_WINDOW;
    h2c.frame_size = 16384;
    h2c.state.length = 4;
    ngx_queue_init(&h2c.waiting);
    for (i = 0; i < 2; i++) {
        nodes[i].id = 2 * i + 1; nodes[i].stream = &streams[i];
        streams[i].node = &nodes[i]; streams[i].connection = &h2c;
        streams[i].request = &requests[i];
        streams[i].send_window = NGX_HTTP_V2_DEFAULT_WINDOW;
        requests[i].stream = &streams[i]; requests[i].connection = &connections[i];
        connections[i].data = &requests[i]; connections[i].write = &events[i];
        events[i].handler = wake;
        ngx_queue_init(&streams[i].queue);
    }
}

static void update(size_t increment, unsigned sid)
{
    u_char b[4];
    b[0] = (u_char) (increment >> 24); b[1] = (u_char) (increment >> 16);
    b[2] = (u_char) (increment >> 8); b[3] = (u_char) increment;
    h2c.state.sid = sid;
    ngx_http_v2_state_window_update(&h2c, b, b + 4);
}

static ngx_http_v2_out_frame_t *queue_data(unsigned sid, size_t len)
{
    ngx_buf_t *b = calloc(1, sizeof(*b));
    ngx_chain_t in;
    if (b == NULL) abort();
    b->pos = payload; b->last = payload + len; b->memory = b->last_buf = 1;
    in.buf = b; in.next = NULL;
    CHECK(ngx_http_v2_send_chain(&connections[sid], &in, 0) == NULL);
    return h2c.last_out;
}

static void free_data(ngx_http_v2_out_frame_t *f)
{ free(f->last->buf); }

static void test_window_boundaries(void)
{
    size_t q, w, limit;
    unsigned i;
    const size_t queued[] = { 0, 1, 16384, 65535, NGX_HTTP_V2_MAX_WINDOW };
    for (i = 0; i < sizeof(queued) / sizeof(queued[0]); i++) {
        reset();
        q = queued[i]; w = q == NGX_HTTP_V2_MAX_WINDOW ? 0 : 123;
        h2c.send_queued = q; h2c.send_window = w;
        limit = NGX_HTTP_V2_MAX_WINDOW - w - q;
        if (limit) {
            update(limit, 0);
            CHECK(connection_error == 0);
            CHECK(h2c.send_window + h2c.send_queued == NGX_HTTP_V2_MAX_WINDOW);
        }
        update(1, 0);
        CHECK(connection_error == NGX_HTTP_V2_FLOW_CTRL_ERROR);
        CHECK(h2c.send_window + h2c.send_queued <= NGX_HTTP_V2_MAX_WINDOW);
    }
    reset(); update(0, 0);
    CHECK(connection_error == NGX_HTTP_V2_PROTOCOL_ERROR);
    reset(); h2c.state.length = 5; update(1, 0);
    CHECK(connection_error == NGX_HTTP_V2_SIZE_ERROR);
    reset();
    ngx_http_v2_state_window_update(&h2c, payload, payload + 3);
    CHECK(saved == 1); CHECK(h2c.send_window == NGX_HTTP_V2_DEFAULT_WINDOW);

    /* A stream window may be negative; the connection queued counter must
     * not be wrongly applied to stream windows. */
    reset(); lookup_node = &nodes[0]; streams[0].send_window = -100;
    h2c.send_queued = 100;
    update(NGX_HTTP_V2_MAX_WINDOW, 1);
    CHECK(stream_error == 0);
    CHECK(streams[0].send_window == NGX_HTTP_V2_MAX_WINDOW - 100);
    update(100, 1); CHECK(stream_error == 0);
    update(1, 1); CHECK(stream_error == NGX_HTTP_V2_FLOW_CTRL_ERROR);
    CHECK(connection_error == 0);
}

static void test_queue_send_cancel(void)
{
    ngx_http_v2_out_frame_t *a, *b;
    reset();
    a = queue_data(0, 8192); b = queue_data(1, 4096);
    CHECK(h2c.send_queued == 12288);
    CHECK(h2c.send_window == NGX_HTTP_V2_DEFAULT_WINDOW - 12288);
    CHECK(streams[0].send_window == NGX_HTTP_V2_DEFAULT_WINDOW - 8192);
    CHECK(streams[1].send_window == NGX_HTTP_V2_DEFAULT_WINDOW - 4096);

    /* Cancel right after topping up to the effective window limit; the
     * refund must not overflow either. */
    update(NGX_HTTP_V2_MAX_WINDOW - NGX_HTTP_V2_DEFAULT_WINDOW, 0);
    CHECK(connection_error == 0);
    ngx_http_v2_filter_cleanup(&streams[0]);
    CHECK(h2c.send_queued == 4096);
    CHECK(h2c.send_window == NGX_HTTP_V2_MAX_WINDOW - 4096);
    CHECK(h2c.last_out == b); CHECK(streams[0].queued == 0);

    /* A partial send must keep the whole frame charged; it is released
     * exactly once on completion. */
    CHECK(ngx_http_v2_data_frame_handler(&h2c, b) == NGX_AGAIN);
    CHECK(h2c.send_queued == 4096);
    b->last->buf->pos = b->last->buf->last;
    CHECK(ngx_http_v2_data_frame_handler(&h2c, b) == NGX_OK);
    CHECK(h2c.send_queued == 0); CHECK(streams[1].queued == 0);
    update(4096, 0); CHECK(connection_error == 0);
    CHECK(h2c.send_window == NGX_HTTP_V2_MAX_WINDOW);
    free_data(a); free_data(b);

    /* Original vulnerability sequence: unsent DATA must not free extra
     * room for WINDOW_UPDATE. */
    reset(); a = queue_data(0, 8192);
    update(NGX_HTTP_V2_MAX_WINDOW - NGX_HTTP_V2_DEFAULT_WINDOW + 1, 0);
    CHECK(connection_error == NGX_HTTP_V2_FLOW_CTRL_ERROR);
    CHECK(h2c.send_window + h2c.send_queued == NGX_HTTP_V2_DEFAULT_WINDOW);
    free_data(a);

    /* An empty END_STREAM DATA frame must not underflow the counter. */
    reset(); a = queue_data(0, 0);
    CHECK(h2c.send_queued == 0);
    CHECK(ngx_http_v2_data_frame_handler(&h2c, a) == NGX_OK);
    CHECK(h2c.send_queued == 0); free_data(a);
}

static ngx_int_t non_data(ngx_http_v2_connection_t *h, ngx_http_v2_out_frame_t *f)
{ (void) h; (void) f; return NGX_OK; }

static void test_cleanup_selection(void)
{
    ngx_http_v2_out_frame_t *a, *b, header;
    reset(); a = queue_data(0, 8192); b = queue_data(0, 4096);
    b->blocked = 1;
    memset(&header, 0, sizeof(header));
    header.stream = &streams[0]; header.handler = non_data; header.length = 100;
    ngx_http_v2_queue_frame(&h2c.last_out, &header); streams[0].queued++;
    ngx_http_v2_filter_cleanup(&streams[0]);
    CHECK(h2c.send_queued == 4096);
    CHECK(h2c.send_window == NGX_HTTP_V2_DEFAULT_WINDOW - 4096);
    CHECK(h2c.last_out == b); CHECK(b->next == NULL);
    CHECK(streams[0].queued == 1);
    /* Repeated cleanup must not refund removed DATA twice, nor refund
     * blocked frames. */
    ngx_http_v2_filter_cleanup(&streams[0]);
    CHECK(h2c.send_queued == 4096);
    b->last->buf->pos = b->last->buf->last;
    CHECK(ngx_http_v2_data_frame_handler(&h2c, b) == NGX_OK);
    CHECK(h2c.send_queued == 0);
    free_data(a); free_data(b);

    /* Refunding DATA on a zero window wakes waiting streams; a cancelled
     * waiting stream is removed from the queue. */
    reset(); h2c.send_window = 8192; a = queue_data(0, 8192);
    streams[1].waiting = 1;
    ngx_queue_insert_tail(&h2c.waiting, &streams[1].queue);
    ngx_http_v2_filter_cleanup(&streams[0]);
    CHECK(h2c.send_window == 8192); CHECK(h2c.send_queued == 0);
    CHECK(streams[1].waiting == 0); CHECK(events[1].posted == 1);
    CHECK(ngx_queue_empty(&h2c.waiting)); free_data(a);
    reset(); streams[0].waiting = 1;
    ngx_queue_insert_tail(&h2c.waiting, &streams[0].queue);
    ngx_http_v2_filter_cleanup(&streams[0]);
    CHECK(streams[0].waiting == 0); CHECK(ngx_queue_empty(&h2c.waiting));
}

int main(void)
{
    test_window_boundaries();
    test_queue_send_cancel();
    test_cleanup_selection();
    printf("flow control unit tests: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
