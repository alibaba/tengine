/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for hessian2_input::read_map(), focused on the type
 * of a typed map ('M'): it is read with read_utf8_string(), which returns
 * NULL for the null tag 'N', and read_map() must not dereference that.
 * Also covers the Exception deserializer's "cause" field, which is read
 * through read_object() and rejected when it is not an Exception.
 *
 * Built and run by the Makefile in this directory, against the codec sources
 * the module ships; nothing here requires a built tengine. The cases run in
 * the main process, so LeakSanitizer judges them at exit: a rejected payload
 * must not leave the objects decoded before the rejection behind.
 */

#include <stdio.h>
#include <string>
#include <utility>

#include "hessian2_input.h"
#include "objects.h"

using namespace std;
using namespace hessian;

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

enum outcome {
    RETURNED,
    THREW_IO,
    THREW_OTHER
};

/* The payloads are literals; sizeof - 1 drops the terminating NUL. */
#define PAYLOAD(lit)  (lit), (uint32_t) (sizeof(lit) - 1)

/*
 * Runs read_map() over the payload. On success the decoded map is handed
 * back through out (NULL for a null map); the caller owns it.
 */
static outcome
decode_map(const char *data, uint32_t size, Map **out)
{
    *out = NULL;

    try {
        hessian2_input hin(data, size);
        *out = static_cast<Map *>(hin.read_map());
        return RETURNED;

    } catch (io_exception &e) {
        return THREW_IO;

    } catch (...) {
        return THREW_OTHER;
    }
}

/* Same as decode_map(), but through the generic read_object() entry. */
static outcome
decode_object(const char *data, uint32_t size)
{
    try {
        hessian2_input hin(data, size);
        pair<Object *, bool> ret = hin.read_object();
        if (ret.second) {
            delete ret.first;
        }
        return RETURNED;

    } catch (io_exception &e) {
        return THREW_IO;

    } catch (...) {
        return THREW_OTHER;
    }
}

/* --- typed map with a null type -------------------------------------- */

static void
test_typed_map_null_type(void)
{
    Map  *map;

    CHECK(decode_map(PAYLOAD("MN"), &map) == THREW_IO,
          "typed map with a null type is rejected");
    CHECK(map == NULL, "no map is returned for a null type");

    CHECK(decode_map(PAYLOAD("MNZ"), &map) == THREW_IO,
          "typed map with a null type is rejected even when terminated");
    CHECK(map == NULL, "no map is returned for a terminated null type");

    CHECK(decode_object(PAYLOAD("MN")) == THREW_IO,
          "read_object() rejects a typed map with a null type");
}

/*
 * The path of the original report: read_object() -> read_map() ->
 * read_object() -> read_map(), with the null-typed map nested in an outer
 * map, both as a key and as a value. Every payload here reaches the null
 * type through a map entry of its own, so what these check is the type of
 * the inner map and nothing else.
 */
static void
test_nested_typed_map_null_type(void)
{
    CHECK(decode_object(PAYLOAD("HMN")) == THREW_IO,
          "null-typed map nested as a key is rejected");

    CHECK(decode_object(PAYLOAD("M\x03" "foo" "\x01k" "MN")) == THREW_IO,
          "null-typed map nested in a typed map is rejected");

    CHECK(decode_object(PAYLOAD("H\x01k" "MN")) == THREW_IO,
          "null-typed map nested as a value is rejected");
}

/* --- Exception with a cause that is not an Exception ------------------ */

/*
 * The Exception deserializer reads "cause" with read_object() and rejects a
 * value that is not an Exception. The decoded value never reaches
 * set_cause(), so the rejection path must free it itself; the cases run in
 * the main process and LeakSanitizer reports it if it does not.
 */
static void
test_exception_non_exception_cause(void)
{
    CHECK(decode_object(PAYLOAD("M\x13" "java.lang.Exception"
                                "S\x00\x05" "cause" "\x01v" "z"))
          == THREW_IO,
          "a string cause is rejected");

    CHECK(decode_object(PAYLOAD("M\x13" "java.lang.Exception"
                                "S\x00\x0d" "detailMessage" "\x02" "ok"
                                "S\x00\x05" "cause" "\x01v" "z"))
          == THREW_IO,
          "a string cause after a detailMessage is rejected");
}

static void
test_typed_map_truncated_type(void)
{
    Map  *map;

    CHECK(decode_map(PAYLOAD("M"), &map) == THREW_IO,
          "typed map without a type is rejected");
    CHECK(map == NULL, "no map is returned without a type");

    CHECK(decode_map(PAYLOAD("M\x05" "ab"), &map) == THREW_IO,
          "typed map with a truncated type is rejected");
    CHECK(map == NULL, "no map is returned for a truncated type");
}

/* --- well-formed maps keep decoding ---------------------------------- */

static void
test_well_formed_maps(void)
{
    Map     *map;
    Object  *v;

    CHECK(decode_map(PAYLOAD("HZ"), &map) == RETURNED && map != NULL,
          "untyped empty map is decoded");
    if (map != NULL) {
        CHECK(map->classname() == Map::DEFAULT_CLASSNAME,
              "untyped map gets the default classname");
        CHECK(map->size() == 0, "untyped empty map has no entries");
        delete map;
    }

    CHECK(decode_map(PAYLOAD("M\x00Z"), &map) == RETURNED && map != NULL,
          "typed map with an empty type is decoded");
    if (map != NULL) {
        CHECK(map->classname() == Map::DEFAULT_CLASSNAME,
              "empty type falls back to the default classname");
        delete map;
    }

    CHECK(decode_map(PAYLOAD("M\x03" "foo" "\x01k" "\x01v" "Z"), &map)
          == RETURNED && map != NULL,
          "typed map with a type and one entry is decoded");
    if (map != NULL) {
        CHECK(map->classname() == "foo", "typed map keeps its type");
        CHECK(map->size() == 1, "typed map has one entry");

        v = map->get("k");
        CHECK(v != NULL && v->to_string() == "v",
              "typed map entry value is decoded");
        delete map;
    }

    CHECK(decode_map(PAYLOAD("N"), &map) == RETURNED && map == NULL,
          "null map is decoded as NULL");
}

/* read_map() checks for NULL; read_utf8_string() keeps returning it. */
static void
test_read_utf8_string_null(void)
{
    string  *s = NULL;
    bool     threw = false;

    try {
        hessian2_input hin(PAYLOAD("N"));
        s = hin.read_utf8_string();

    } catch (...) {
        threw = true;
    }

    CHECK(!threw && s == NULL,
          "read_utf8_string() returns NULL for the null tag");

    delete s;
}

int
main(void)
{
    test_typed_map_null_type();
    test_nested_typed_map_null_type();
    test_exception_non_exception_cause();
    test_typed_map_truncated_type();
    test_well_formed_maps();
    test_read_utf8_string_null();

    printf("%d tests, %d failed\n", tests_run, tests_failed);

    return tests_failed ? 1 : 0;
}
