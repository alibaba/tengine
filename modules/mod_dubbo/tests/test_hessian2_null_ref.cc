/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for null entries and value references in maps
 * read by hessian2_input::read_object().
 *
 * Two regressions guarded here:
 *  - read_object() only peeked the null tag 'N' without consuming it, so a
 *    map with a null key or value made read_map()'s entry loop re-read the
 *    same byte forever (a hang plus unbounded memory growth from a single
 *    crafted response).
 *  - the ref tag 'Q' was not consumed either, and the referenced object
 *    was returned as owned: a map referring to itself or to a sibling
 *    entry double-freed that object when the map was deleted.
 *
 * Every case runs in a forked child with an alarm: the old code hangs on
 * the null cases, and a hanging case must not hold the whole suite.
 * Children leave with _exit(), so LeakSanitizer does not judge the cases.
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

#define LIT(s)  s, sizeof(s) - 1

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
        alarm(20);
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

/* decodes one object; NULL when io_exception was thrown */
static Object *
decode_object(const char *data, size_t len, bool *consumed)
{
    *consumed = false;

    try {
        hessian2_input  hin(data, (uint32_t) len);

        std::pair<Object*, bool>  ret = hin.read_object();
        *consumed = hin.eof();

        if (ret.second) {
            return ret.first;
        }

        delete ret.first;
        return NULL;

    } catch (io_exception &) {
        return NULL;
    }
}

/* --- null entries ----------------------------------------------------- */

static void
test_map_null_value(void)
{
    bool     consumed;
    Object  *o = decode_object(LIT("H\x01kNZ"), &consumed);

    CHECK(o != NULL, "a map with a null value decodes");
    if (o != NULL) {
        Map  *map = (Map *) o;
        CHECK(map->size() == 1, "one entry");
        CHECK(map->get("k") == NULL, "the value is null");
        delete o;
    }

    CHECK(consumed, "whole input consumed, no byte re-read");
}

static void
test_map_null_key(void)
{
    bool     consumed;
    Object  *o = decode_object(LIT("HN\x01vZ"), &consumed);

    CHECK(o != NULL, "a map with a null key decodes");
    if (o != NULL) {
        CHECK(((Map *) o)->size() == 1, "one entry");
        delete o;
    }

    CHECK(consumed, "whole input consumed, no byte re-read");
}

static void
test_map_null_key_and_value(void)
{
    bool     consumed;
    Object  *o = decode_object(LIT("HNNZ"), &consumed);

    CHECK(o != NULL, "a map with a null key and value decodes");
    if (o != NULL) {
        CHECK(((Map *) o)->size() == 1, "one entry");
        delete o;
    }

    CHECK(consumed, "whole input consumed, no byte re-read");
}

static void
test_nested_map_null_value(void)
{
    bool     consumed;
    Object  *o = decode_object(LIT("H\x01kH\x01xNZZ"), &consumed);

    CHECK(o != NULL, "a nested map with a null value decodes");
    if (o != NULL) {
        Object  *inner = ((Map *) o)->get("k");
        CHECK(inner != NULL, "the inner map is present");
        if (inner != NULL) {
            CHECK(((Map *) inner)->get("x") == NULL, "inner value is null");
        }

        delete o;
    }

    CHECK(consumed, "whole input consumed, no byte re-read");
}

/* --- value references -------------------------------------------------- */

static void
test_self_ref_value(void)
{
    /* the map's value refers to the map itself (ref id 0); deleting the
     * map once must not delete it a second time through the entry */
    bool     consumed;
    Object  *o = decode_object(LIT("H\x01" "aQ\x00\x00\x00\x00Z"), &consumed);

    CHECK(o != NULL, "a self-referencing map decodes");
    if (o != NULL) {
        CHECK(((Map *) o)->get("a") == o, "the ref points at the map");
        delete o;
    }

    CHECK(consumed, "whole input consumed, the ref tag is eaten");
}

static void
test_ref_to_inner_map(void)
{
    /* refs: outer map 0, inner map 1; the second entry refers to the
     * inner map, which the first entry already owns */
    bool     consumed;
    Object  *o = decode_object(
        LIT("H\x01mH\x01x\x01yZ\x01rQ\x00\x00\x00\x01Z"), &consumed);

    CHECK(o != NULL, "a map with a ref to a sibling entry decodes");
    if (o != NULL) {
        Map  *map = (Map *) o;
        CHECK(map->get("r") == map->get("m"), "the ref points at the inner map");
        delete o;
    }

    CHECK(consumed, "whole input consumed");
}

static void
test_bad_ref_id(void)
{
    bool     consumed;
    Object  *o = decode_object(LIT("H\x01" "aQ\x00\x00\x00\x05Z"), &consumed);

    CHECK(o == NULL, "a ref past the ref table is rejected");
}

static void
test_read_ref_wrong_tag(void)
{
    bool         thrown = false;
    std::string  what;

    hessian2_input  hin(LIT("\x01" "a"));

    try {
        hin.read_ref();
    } catch (io_exception &e) {
        thrown = true;
        what = e.what();
    }

    CHECK(thrown, "read_ref() rejects a non-ref tag");
    CHECK(what.find("expected ref") != std::string::npos,
          "rejected as a missing ref tag");
}

/* --------------------------------------------------------------------- */

#define RUN(t)  failed += run(#t, t)

int
main(void)
{
    int  failed = 0;

    RUN(test_map_null_value);
    RUN(test_map_null_key);
    RUN(test_map_null_key_and_value);
    RUN(test_nested_map_null_value);

    RUN(test_self_ref_value);
    RUN(test_ref_to_inner_map);
    RUN(test_bad_ref_id);
    RUN(test_read_ref_wrong_tag);

    printf("%d case(s) failed\n", failed);

    return failed ? 1 : 0;
}
