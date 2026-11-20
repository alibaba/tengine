/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for the type-confusion guard added to
 * ngx_dubbo_hessian2_decode_payload_map().
 *
 * The decoder used to cast the Object* returned by read_object() straight to
 * Map*, without checking the real dynamic type.  For any non-map payload
 * (Boolean, String, Integer, Long, Date, ByteArray, ...) Map::size() then
 * read the std::map member out of a much smaller allocation: an out-of-bounds
 * read under a sanitizer, a SIGSEGV in an ordinary build.
 *
 * These tests exercise the codec-level primitives the fix relies on --
 * read_object() and instance_of<T>() -- over the exact payloads from the
 * report, so a regression that drops the type check is caught here rather
 * than in a crashing worker.
 *
 * Built and run by the Makefile in this directory, against the codec sources
 * the module ships; nothing here requires a built tengine.
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

/* The payloads are literals; sizeof - 1 drops the terminating NUL. */
#define PAYLOAD(lit)  (lit), (uint32_t) (sizeof(lit) - 1)

/*
 * Reads one object from the payload and reports whether instance_of<Map>()
 * accepts it.  The object is freed through the pair's second flag, exactly as
 * the fixed ngx_dubbo_hessian2_decode_payload_map() does on the error path.
 */
static bool
payload_is_map(const char *data, uint32_t size, uint32_t *type_id)
{
    pair<Object *, bool>  ret;
    bool                  is_map;

    *type_id = 0;

    try {
        hessian2_input  hin(data, size);

        /* the attachment int the real decoder reads first */
        hin.read_int32();

        ret = hin.read_object();

    } catch (io_exception &) {
        return false;

    } catch (...) {
        return false;
    }

    if (ret.first != NULL) {
        *type_id = ret.first->type_id();
    }

    is_map = instance_of<Map>(ret.first);

    if (ret.second && ret.first != NULL) {
        delete ret.first;
    }

    return is_map;
}

/*
 * Same as payload_is_map(), but also verifies that a Map payload decodes to
 * a usable map with the expected entry count.
 */
static bool
payload_map_entries(const char *data, uint32_t size, uint32_t *nentries)
{
    pair<Object *, bool>  ret;
    Map                  *map;

    *nentries = 0;

    try {
        hessian2_input  hin(data, size);

        hin.read_int32();
        ret = hin.read_object();

    } catch (...) {
        return false;
    }

    if (!instance_of<Map>(ret.first)) {
        if (ret.second && ret.first != NULL) {
            delete ret.first;
        }
        return false;
    }

    map = static_cast<Map *>(ret.first);
    *nentries = map->size();

    if (ret.second) {
        delete ret.first;
    }

    return true;
}

/* --- non-map payloads from the report -------------------------------- */

/*
 * Each case is the three-or-more byte response body from section 4 of the
 * report: the attachment int (0x90 = 0) followed by one non-map object.
 * Before the fix, every one of these was cast to Map* and read out of
 * bounds; instance_of<Map>() must reject all of them.
 */

static void
test_boolean_payload_rejected(void)
{
    /* 0x90 (int 0) then 0x46 0x00 = Boolean false */
    static const char  in[] = { '\x90', '\x46', '\x00' };
    uint32_t           type_id;

    CHECK(!payload_is_map(in, sizeof(in), &type_id),
          "Boolean payload must not be accepted as a Map");
    CHECK(type_id == Object::BOOLEAN,
          "Boolean payload decodes to type BOOLEAN");
}

static void
test_long_payload_rejected(void)
{
    /* 0x90 then 0x38 + 8 bytes = Long */
    static const char  in[] = { '\x90', '\x38',
                                '\x00', '\x00', '\x00', '\x00',
                                '\x00', '\x00', '\x00', '\x00' };
    uint32_t           type_id;

    CHECK(!payload_is_map(in, sizeof(in), &type_id),
          "Long payload must not be accepted as a Map");
    CHECK(type_id == Object::LONG,
          "Long payload decodes to type LONG");
}

static void
test_date_payload_rejected(void)
{
    /* 0x90 then 0x4a + 8 bytes = Date */
    static const char  in[] = { '\x90', '\x4a',
                                '\x00', '\x00', '\x00', '\x00',
                                '\x00', '\x00', '\x00', '\x00' };
    uint32_t           type_id;

    CHECK(!payload_is_map(in, sizeof(in), &type_id),
          "Date payload must not be accepted as a Map");
    CHECK(type_id == Object::DATE,
          "Date payload decodes to type DATE");
}

static void
test_string_payload_rejected(void)
{
    /* 0x90 then 0x01 'a' = one-char String */
    static const char  in[] = { '\x90', '\x01', 'a' };
    uint32_t           type_id;

    CHECK(!payload_is_map(in, sizeof(in), &type_id),
          "String payload must not be accepted as a Map");
    CHECK(type_id == Object::STRING,
          "String payload decodes to type STRING");
}

static void
test_byte_array_payload_rejected(void)
{
    /* 0x90 then 0x22 '0' '0' '0' = three-byte ByteArray */
    static const char  in[] = { '\x90', '\x22', '0', '0', '0' };
    uint32_t           type_id;

    CHECK(!payload_is_map(in, sizeof(in), &type_id),
          "ByteArray payload must not be accepted as a Map");
    CHECK(type_id == Object::BYTE_ARRAY,
          "ByteArray payload decodes to type BYTE_ARRAY");
}

static void
test_integer_payload_rejected(void)
{
    /* 0x90 then 'I' + 4 bytes = Integer */
    static const char  in[] = { '\x90', 'I',
                                '\x00', '\x00', '\x00', '\x01' };
    uint32_t           type_id;

    CHECK(!payload_is_map(in, sizeof(in), &type_id),
          "Integer payload must not be accepted as a Map");
    CHECK(type_id == Object::INTEGER,
          "Integer payload decodes to type INTEGER");
}

static void
test_double_payload_rejected(void)
{
    /* 0x90 then 'D' + 8 bytes = Double */
    static const char  in[] = { '\x90', 'D',
                                '\x00', '\x00', '\x00', '\x00',
                                '\x00', '\x00', '\x00', '\x00' };
    uint32_t           type_id;

    CHECK(!payload_is_map(in, sizeof(in), &type_id),
          "Double payload must not be accepted as a Map");
    CHECK(type_id == Object::DOUBLE,
          "Double payload decodes to type DOUBLE");
}

static void
test_null_payload_rejected(void)
{
    /* 0x90 then 'N' = null object */
    static const char  in[] = { '\x90', 'N' };
    uint32_t           type_id;

    CHECK(!payload_is_map(in, sizeof(in), &type_id),
          "null payload must not be accepted as a Map");
    CHECK(type_id == 0,
          "null payload leaves type_id untouched");
}

/* --- well-formed map payloads keep decoding -------------------------- */

static void
test_empty_map_accepted(void)
{
    /* 0x90 then 'H' 'Z' = empty untyped map */
    static const char  in[] = { '\x90', 'H', 'Z' };
    uint32_t           type_id;
    uint32_t           nentries;

    CHECK(payload_is_map(in, sizeof(in), &type_id),
          "empty map payload must be accepted as a Map");
    CHECK(type_id == Object::MAP,
          "empty map payload decodes to type MAP");

    CHECK(payload_map_entries(in, sizeof(in), &nentries),
          "empty map decodes through the Map path");
    CHECK(nentries == 0, "empty map has no entries");
}

static void
test_map_with_entries_accepted(void)
{
    /*
     * 0x90 then 'H' with two string->string entries and the 'Z' terminator:
     * { "status": "200", "body": "hello" }.  This is the shape the real
     * decoder expects from a Dubbo backend.
     */
    static const char  in[] = {
        '\x90', 'H',
        '\x06', 's', 't', 'a', 't', 'u', 's',
        '\x03', '2', '0', '0',
        '\x04', 'b', 'o', 'd', 'y',
        '\x05', 'h', 'e', 'l', 'l', 'o',
        'Z'
    };
    uint32_t           type_id;
    uint32_t           nentries;

    CHECK(payload_is_map(in, sizeof(in), &type_id),
          "populated map payload must be accepted as a Map");
    CHECK(type_id == Object::MAP,
          "populated map payload decodes to type MAP");

    CHECK(payload_map_entries(in, sizeof(in), &nentries),
          "populated map decodes through the Map path");
    CHECK(nentries == 2, "populated map has two entries");
}

static void
test_typed_map_accepted(void)
{
    /*
     * A typed map ('M') whose class name selects the Exception deserializer
     * still carries a Map type_id (EXCEPTION >= EXT_MAP), so instance_of<Map>
     * accepts it -- matching the behaviour the fixed decoder relies on.
     * Note: the Exception deserializer terminates with 'z' (lowercase),
     * not 'Z' (uppercase) as the generic map parser does, and it only
     * handles keys encoded with the 'S' (long string) tag.
     */
    static const char  in[] = {
        '\x90', 'M',
        '\x13', 'j', 'a', 'v', 'a', '.', 'l', 'a', 'n', 'g', '.',
        'E', 'x', 'c', 'e', 'p', 't', 'i', 'o', 'n',
        'S', '\x00', '\x0d', 'd', 'e', 't', 'a', 'i', 'l', 'M', 'e',
        's', 's', 'a', 'g', 'e',
        'S', '\x00', '\x02', 'o', 'k',
        'z'
    };
    uint32_t           type_id;

    CHECK(payload_is_map(in, sizeof(in), &type_id),
          "typed Exception map must be accepted as a Map");
    CHECK(type_id >= Object::EXT_MAP,
          "Exception type_id is in the EXT_MAP range");
}

/* --- instance_of<> on hand-built objects ----------------------------- */

/*
 * The fix also guards the per-entry casts inside the loop: a key that is not
 * a String and a "body" value that is not a ByteArray must be rejected by
 * instance_of<> rather than cast blindly.  These checks pin the behaviour of
 * instance_of<> on objects built directly, independent of the decoder.
 */

static void
test_instance_of_string(void)
{
    String   s("key");
    Integer  i(42);
    Boolean  b(true);

    CHECK(instance_of<String>(&s), "String is instance_of<String>");
    CHECK(!instance_of<String>(&i), "Integer is not instance_of<String>");
    CHECK(!instance_of<String>(&b), "Boolean is not instance_of<String>");
    CHECK(!instance_of<String>(NULL), "NULL is not instance_of<String>");
}

static void
test_instance_of_byte_array(void)
{
    ByteArray  ba("bytes", 5);
    String     s("text");
    Integer    i(7);

    CHECK(instance_of<ByteArray>(&ba), "ByteArray is instance_of<ByteArray>");
    CHECK(!instance_of<ByteArray>(&s), "String is not instance_of<ByteArray>");
    CHECK(!instance_of<ByteArray>(&i), "Integer is not instance_of<ByteArray>");
    CHECK(!instance_of<ByteArray>(NULL), "NULL is not instance_of<ByteArray>");
}

static void
test_instance_of_map(void)
{
    Map      m;
    String   s("text");
    Integer  i(1);

    CHECK(instance_of<Map>(&m), "Map is instance_of<Map>");
    CHECK(!instance_of<Map>(&s), "String is not instance_of<Map>");
    CHECK(!instance_of<Map>(&i), "Integer is not instance_of<Map>");
    CHECK(!instance_of<Map>(NULL), "NULL is not instance_of<Map>");
}

/* --------------------------------------------------------------------- */

int
main(void)
{
    test_boolean_payload_rejected();
    test_long_payload_rejected();
    test_date_payload_rejected();
    test_string_payload_rejected();
    test_byte_array_payload_rejected();
    test_integer_payload_rejected();
    test_double_payload_rejected();
    test_null_payload_rejected();

    test_empty_map_accepted();
    test_map_with_entries_accepted();
    test_typed_map_accepted();

    test_instance_of_string();
    test_instance_of_byte_array();
    test_instance_of_map();

    printf("%d tests, %d failed\n", tests_run, tests_failed);

    return tests_failed ? 1 : 0;
}
