/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for the nesting limit of the hessian2 decoder:
 * hessian2_input::read_object() and read_map().
 *
 * The regression guarded here: read_map() reads every key and value with
 * read_object(), which dispatches the map tags 'H' and 'M' back to
 * read_map(). Without a depth limit a payload of repeated 'H' bytes
 * recurses until the stack is exhausted; a single crafted Dubbo response
 * then terminates the worker. The limit is MAX_NESTING_DEPTH; each map
 * level costs two counts (read_object() plus read_map()).
 *
 * Every case runs in a forked child: without the fix the deep payloads
 * end in a stack overflow (a signal, not a failed check), and a crashing
 * case must not hide the outcome of the others. Children leave with
 * _exit(), so LeakSanitizer does not judge the cases.
 */

#include "hessian2_input.h"
#include "objects.h"

#include <stdio.h>
#include <string.h>
#include <string>
#include <utility>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

using namespace hessian;

/* --- tiny test framework --------------------------------------------- */

static int  case_failed;

#define CHECK(cond, msg)                                                      \
    do {                                                                      \
        if (!(cond)) {                                                        \
            case_failed = 1;                                                  \
            printf("  FAIL: %s (%s:%d)\n", (msg), __FILE__, __LINE__);        \
        }                                                                     \
    } while (0)

typedef void (*test_pt)(void);

static int
run(const char *name, test_pt test)
{
    int    status;
    pid_t  pid;

    fflush(stdout);

    pid = fork();
    if (pid < 0) {
        perror("fork");
        return 1;
    }

    if (pid == 0) {
        case_failed = 0;
        test();
        fflush(stdout);
        _exit(case_failed ? 1 : 0);
    }

    if (waitpid(pid, &status, 0) != pid) {
        perror("waitpid");
        return 1;
    }

    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        printf("ok   %s\n", name);
        return 0;
    }

    if (WIFSIGNALED(status)) {
        printf("FAIL %s (killed by signal %d)\n", name, WTERMSIG(status));
    } else {
        printf("FAIL %s (exit status %d)\n", name, WEXITSTATUS(status));
    }

    return 1;
}

/* --- helpers --------------------------------------------------------- */

static bool
depth_rejected(const std::string &what)
{
    return what.find("maximum nesting depth exceeded") != std::string::npos;
}

/* reads one object and frees it, reporting whether io_exception was thrown */
static bool
read_object_throws(const char *data, size_t len, std::string *what)
{
    try {
        hessian2_input  hin(data, (uint32_t) len);

        std::pair<Object*, bool>  ret = hin.read_object();
        if (ret.second) {
            delete ret.first;
        }

    } catch (io_exception &e) {
        if (what != NULL) {
            *what = e.what();
        }

        return true;
    }

    return false;
}

/* the same through the read_map() entry */
static bool
read_map_throws(const char *data, size_t len, std::string *what)
{
    try {
        hessian2_input  hin(data, (uint32_t) len);

        Object  *map = hin.read_map();
        delete map;

    } catch (io_exception &e) {
        if (what != NULL) {
            *what = e.what();
        }

        return true;
    }

    return false;
}

/*
 * levels nested untyped maps, each with the key "k" and the next map as
 * its value; the innermost map is empty. Every level closes with 'Z'.
 * The segments carry an embedded NUL (the key's length tag), so they are
 * appended with an explicit length, not as C strings.
 */
static std::string
nested_maps(int levels)
{
    std::string  s;
    int          i;

    for (i = 1; i < levels; i++) {
        s.append("H\x01k", 3);
    }

    s.push_back('H');
    s.append(levels, 'Z');

    return s;
}

/* the same with typed maps ('M' and an empty type) */
static std::string
nested_typed_maps(int levels)
{
    std::string  s;
    int          i;

    for (i = 1; i < levels; i++) {
        s.append("M\x00\x01k", 4);
    }

    s.append("M\x00Z", 3);
    s.append(levels - 1, 'Z');

    return s;
}

/* an Exception whose "cause" is another Exception, levels deep. The
 * payloads carry embedded NULs (string length tags), so every segment is
 * taken with its full sizeof, not as a C string. */
static std::string
cause_chain(int levels)
{
    static const char  innermost[] = "M\x13java.lang.Exception"
        "S\x00\x0d" "detailMessage" "S\x00\x02" "ok" "z";
    static const char  cause_prefix[] = "M\x13java.lang.Exception"
        "S\x00\x05" "cause";

    std::string  s(innermost, sizeof(innermost) - 1);
    int          i;

    for (i = 1; i < levels; i++) {
        s = std::string(cause_prefix, sizeof(cause_prefix) - 1) + s + "z";
    }

    return s;
}

/* --- the report's reproducer ----------------------------------------- */

static void
test_report_reproducer(void)
{
    /* 100000 map-start tags: the old decoder recursed until the stack ran
     * out; no closing 'Z' is needed to drive it there */
    std::string  data(100000, 'H');
    std::string  what;

    data.push_back('Z');

    CHECK(read_object_throws(data.data(), data.size(), &what),
          "a payload of repeated map tags must be rejected");
    CHECK(depth_rejected(what), "rejected by the nesting limit");
}

static void
test_report_reproducer_read_map(void)
{
    std::string  data(100000, 'H');
    std::string  what;

    CHECK(read_map_throws(data.data(), data.size(), &what),
          "read_map() rejects the same payload");
    CHECK(depth_rejected(what), "rejected by the nesting limit");
}

static void
test_deep_without_terminator(void)
{
    std::string  data(100000, 'H');
    std::string  what;

    CHECK(read_object_throws(data.data(), data.size(), &what),
          "an unterminated deep payload must be rejected");
    CHECK(depth_rejected(what),
          "rejected by the nesting limit, not by running out of input");
}

/* --- the limit itself ------------------------------------------------- */

static void
test_nested_maps_at_limit(void)
{
    /* each map level costs two counts; MAX_NESTING_DEPTH / 2 levels fit */
    std::string  data = nested_maps(hessian2_input::MAX_NESTING_DEPTH / 2);
    std::string  what;

    CHECK(!read_object_throws(data.data(), data.size(), &what),
          "nesting exactly at the limit still decodes");
}

static void
test_nested_maps_beyond_limit(void)
{
    std::string  data = nested_maps(hessian2_input::MAX_NESTING_DEPTH / 2 + 1);
    std::string  what;

    CHECK(read_object_throws(data.data(), data.size(), &what),
          "nesting one level past the limit is rejected");
    CHECK(depth_rejected(what), "rejected by the nesting limit");
}

static void
test_nested_typed_maps(void)
{
    std::string  data, what;

    data = nested_typed_maps(hessian2_input::MAX_NESTING_DEPTH / 2);
    CHECK(!read_object_throws(data.data(), data.size(), &what),
          "typed maps at the limit still decode");

    data = nested_typed_maps(hessian2_input::MAX_NESTING_DEPTH / 2 + 1);
    CHECK(read_object_throws(data.data(), data.size(), &what),
          "typed maps past the limit are rejected");
    CHECK(depth_rejected(what), "rejected by the nesting limit");
}

static void
test_exception_cause_chain(void)
{
    std::string  data, what;

    /* a short cause chain keeps decoding, detailMessage included */
    data = cause_chain(3);

    try {
        hessian2_input  hin(data.data(), (uint32_t) data.size());

        std::pair<Object*, bool>  ret = hin.read_object();

        CHECK(ret.first != NULL, "a short cause chain decodes");
        if (ret.first != NULL) {
            /* walk to the innermost Exception, which carries the message */
            const Exception  *ex = (const Exception *) ret.first;
            int               hops = 0;

            while (ex->cause() != NULL && hops < 3) {
                ex = ex->cause();
                hops++;
            }

            CHECK(hops == 2, "the chain keeps every cause link");
            CHECK(ex->detail_message() == "ok",
                  "the innermost detailMessage survives");
        }

        CHECK(hin.eof(), "whole input consumed");

        if (ret.second) {
            delete ret.first;
        }

    } catch (io_exception &e) {
        CHECK(false, "a short cause chain must not throw");
    }

    /* a deep one is cut by the same limit (the cause is read with
     * read_object() inside the Exception deserializer) */
    data = cause_chain(200);
    CHECK(read_object_throws(data.data(), data.size(), &what),
          "a deep cause chain is rejected");
    CHECK(depth_rejected(what), "rejected by the nesting limit");
}

/* --- the depth counter unwinds ---------------------------------------- */

static void
test_depth_restored_after_deep_read(void)
{
    /* a read at the limit, then a flat map on the same input: the counter
     * must be back to zero after the first object */
    std::string  data = nested_maps(hessian2_input::MAX_NESTING_DEPTH / 2);
    data.append("H\x01" "a" "\x01" "b" "Z");

    hessian2_input  hin(data.data(), (uint32_t) data.size());

    std::pair<Object*, bool>  deep = hin.read_object();
    CHECK(deep.first != NULL, "the deep object decodes");
    if (deep.second) {
        delete deep.first;
    }

    std::pair<Object*, bool>  flat = hin.read_object();
    CHECK(flat.first != NULL, "a flat map decodes after the deep one");
    if (flat.first != NULL) {
        Object  *v = ((Map *) flat.first)->get("a");
        CHECK(v != NULL && v->to_string() == "b", "flat map entry");
    }

    CHECK(hin.eof(), "whole input consumed");

    if (flat.second) {
        delete flat.first;
    }
}

static void
test_flat_map_still_decodes(void)
{
    static const char  in[] = "H\x04" "body" "\x05" "hello" "Z";

    hessian2_input  hin(in, sizeof(in) - 1);

    std::pair<Object*, bool>  ret = hin.read_object();

    CHECK(ret.first != NULL, "a flat map decodes");
    if (ret.first != NULL) {
        Object  *v = ((Map *) ret.first)->get("body");
        CHECK(v != NULL && v->to_string() == "hello", "map entry value");
    }

    if (ret.second) {
        delete ret.first;
    }
}

/* --------------------------------------------------------------------- */

#define RUN(t)  failed += run(#t, t)

int
main(void)
{
    int  failed = 0;

    RUN(test_report_reproducer);
    RUN(test_report_reproducer_read_map);
    RUN(test_deep_without_terminator);

    RUN(test_nested_maps_at_limit);
    RUN(test_nested_maps_beyond_limit);
    RUN(test_nested_typed_maps);
    RUN(test_exception_cause_chain);

    RUN(test_depth_restored_after_deep_read);
    RUN(test_flat_map_still_decodes);

    printf("%d case(s) failed\n", failed);

    return failed ? 1 : 0;
}
