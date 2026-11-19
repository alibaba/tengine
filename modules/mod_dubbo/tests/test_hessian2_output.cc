/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for the hessian2 string encoder:
 * hessian2_output::write_utf8_string().
 *
 * The regression guarded here: the encoder advanced its index by whole
 * UTF-8 chars while iterating over a byte count, so a buffer ending in an
 * incomplete multi-byte sequence made the final append() read past the
 * buffer. Request-derived values ($args, $arg_*, ...) reach this code
 * unauthenticated, e.g. an argument ending in the byte 0xC3.
 *
 * Every input sits in a heap block of exactly the announced size, so a
 * sanitizer reports any read past it; the encoded bytes are also checked
 * directly, which catches an over-read even without a sanitizer. Where
 * possible the output is decoded again with hessian2_input, the same codec
 * the module ships.
 *
 * Every case runs in a forked child: an over-read aborts under a sanitizer
 * rather than failing a check, and a crashing case must not hide the
 * outcome of the others. Children leave with _exit(), so LeakSanitizer
 * does not judge the cases.
 */

#include "hessian2_output.h"
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

/*
 * Encodes data[0 .. len) from a heap block of exactly len bytes: a read
 * past the announced size then leaves the allocation, which a sanitizer
 * reports.
 */
static std::string
encode_exact(const char *data, size_t len)
{
    char         *buf;
    std::string   out;

    buf = new char[len];
    memcpy(buf, data, len);

    hessian2_output  hout(&out);
    hout.write_utf8_string(buf, (uint32_t) len);

    delete[] buf;

    return out;
}

/* decodes an encoded string again; false if the decoder rejects it */
static bool
decode_value(const std::string &enc, std::string *value)
{
    try {
        hessian2_input  hin(enc.data(), (uint32_t) enc.size());

        std::string  *s = hin.read_utf8_string();
        if (s == NULL) {
            value->clear();
            return true;
        }

        *value = *s;
        delete s;

        return hin.eof();

    } catch (io_exception &) {
        return false;
    }
}

/* --- buffers ending in an incomplete multi-byte sequence ------------- */

static void
test_report_reproducer(void)
{
    /*
     * The reproducer from the report: 64 bytes whose last one is a 2-byte
     * lead. The old encoder counted it as a char and appended 65 bytes.
     */
    char  in[64];

    memset(in, 'A', sizeof(in));
    in[sizeof(in) - 1] = '\xc3';

    std::string  out = encode_exact(in, sizeof(in));

    /*
     * 63 complete chars and no trailing 0xC3. 63 is above the 31 the
     * compact form covers, so the length takes the two byte form: 0x30
     * for the high bits, 0x3f for the count.
     */
    std::string  expect("\x30\x3f", 2);
    expect.append(63, 'A');

    CHECK(out == expect, "only the complete chars are encoded");

    std::string  value;
    CHECK(decode_value(out, &value), "encoded output decodes");
    CHECK(value == std::string(63, 'A'), "decoded value holds no over-read");
}

static void
test_two_byte_lead_last(void)
{
    std::string  out = encode_exact(LIT("A\xc3"));

    CHECK(out == "\x01" "A", "a trailing 2-byte lead is dropped");

    std::string  value;
    CHECK(decode_value(out, &value) && value == "A", "round trip");
}

static void
test_three_byte_cut(void)
{
    std::string  out, value;

    out = encode_exact(LIT("A\xe4"));
    CHECK(out == "\x01" "A", "a trailing 3-byte lead is dropped");
    CHECK(decode_value(out, &value) && value == "A", "round trip (lead)");

    out = encode_exact(LIT("A\xe4\xb8"));
    CHECK(out == "\x01" "A", "a 3-byte char missing its last byte is dropped");
    CHECK(decode_value(out, &value) && value == "A", "round trip (one byte)");
}

static void
test_four_byte_cut(void)
{
    std::string  out;

    out = encode_exact(LIT("A\xf0"));
    CHECK(out == "\x01" "A", "a trailing 4-byte lead is dropped");

    out = encode_exact(LIT("A\xf0\x90"));
    CHECK(out == "\x01" "A", "a 4-byte char missing two bytes is dropped");

    out = encode_exact(LIT("A\xf0\x90\x80"));
    CHECK(out == "\x01" "A", "a 4-byte char missing its last byte is dropped");

    /*
     * The lead byte of the report's reproducer: 0xFD is no UTF-8 lead at
     * all, and the encoder walks it as a 4-byte char.
     */
    out = encode_exact(LIT("A\xfd"));
    CHECK(out == "\x01" "A", "a stray high byte is dropped with its sequence");
}

static void
test_only_incomplete(void)
{
    /*
     * No complete char at all: an empty final chunk, not a missing value.
     * The chunk is spelled out because a C string literal cannot hold the
     * NUL byte it is made of.
     */
    const std::string  empty_chunk(1, '\0');

    std::string  out, value;

    out = encode_exact(LIT("\xc3"));
    CHECK(out == empty_chunk, "a lone 2-byte lead encodes as an empty string");
    CHECK(decode_value(out, &value) && value.empty(), "round trip (2-byte)");

    out = encode_exact(LIT("\xe4\xb8"));
    CHECK(out == empty_chunk, "a cut 3-byte char encodes as an empty string");
    CHECK(decode_value(out, &value) && value.empty(), "round trip (3-byte)");

    out = encode_exact(LIT("\xf0\x90\x80"));
    CHECK(out == empty_chunk, "a cut 4-byte char encodes as an empty string");
    CHECK(decode_value(out, &value) && value.empty(), "round trip (4-byte)");
}

/* --- well-formed input keeps its encoding ---------------------------- */

static void
test_well_formed_roundtrip(void)
{
    /* 'A', U+00E9, U+4E2D: the last char ends exactly at the buffer end */
    std::string  out = encode_exact(LIT("A\xc3\xa9\xe4\xb8\xad"));

    CHECK(out == "\x03" "A\xc3\xa9\xe4\xb8\xad", "char count and bytes");

    std::string  value;
    CHECK(decode_value(out, &value), "encoded output decodes");
    CHECK(value == "A\xc3\xa9\xe4\xb8\xad", "round trip preserves the bytes");
}

static void
test_four_byte_char_encoded(void)
{
    /*
     * U+10348 as one 4-byte char. Checked on the bytes only: the decoder
     * of this codec accepts 2- and 3-byte sequences, not 4-byte ones.
     */
    std::string  out = encode_exact(LIT("\xf0\x90\x8d\x88"));

    CHECK(out == "\x01\xf0\x90\x8d\x88", "one char, all four bytes kept");
}

static void
test_null_and_empty(void)
{
    std::string  out;
    hessian2_output  hout(&out);

    hout.write_utf8_string(NULL, 0);
    CHECK(out == "N", "a null buffer encodes as null");

    out.clear();
    hout.write_utf8_string("", 0);
    CHECK(out == "N", "an empty buffer encodes as null");
}

/* --- chunking at 0x8000 chars ---------------------------------------- */

static void
test_chunk_exact_boundary(void)
{
    /* exactly one full chunk: a final empty chunk must terminate it */
    std::string  in(0x8000, 'A');

    std::string  out = encode_exact(in.data(), in.size());

    std::string  expect("R\x80\x00", 3);
    expect.append(in);
    expect.push_back('\x00');

    CHECK(out == expect, "full chunk followed by an empty final chunk");

    std::string  value;
    CHECK(decode_value(out, &value), "chunked output decodes");
    CHECK(value == in, "round trip preserves every char");
}

static void
test_chunk_with_remainder(void)
{
    std::string  in(0x8000 + 5, 'A');

    std::string  out = encode_exact(in.data(), in.size());

    std::string  expect("R\x80\x00", 3);
    expect.append(0x8000, 'A');
    expect.append("\x05" "AAAAA");

    CHECK(out == expect, "full chunk followed by the remainder");

    std::string  value;
    CHECK(decode_value(out, &value) && value == in, "round trip");
}

static void
test_chunk_truncated_tail(void)
{
    /* a full chunk, then a lone 2-byte lead: the tail must not be read */
    std::string  in(0x8000, 'A');
    in.push_back('\xc3');

    std::string  out = encode_exact(in.data(), in.size());

    std::string  expect("R\x80\x00", 3);
    expect.append(0x8000, 'A');
    expect.push_back('\x00');

    CHECK(out == expect, "the cut tail after a chunk is dropped");

    std::string  value;
    CHECK(decode_value(out, &value), "chunked output decodes");
    CHECK(value == std::string(0x8000, 'A'), "round trip holds no over-read");
}

static void
test_multibyte_on_chunk_boundary(void)
{
    /* the 0x8000th char is a 3-byte one: counted once, kept whole */
    std::string  in(0x7fff, 'A');
    in.append("\xe4\xb8\xad");

    std::string  out = encode_exact(in.data(), in.size());

    std::string  expect("R\x80\x00", 3);
    expect.append(in);
    expect.push_back('\x00');

    CHECK(out == expect, "a multi-byte char may close a chunk");

    std::string  value;
    CHECK(decode_value(out, &value) && value == in, "round trip");
}

/* --- the path the module itself takes -------------------------------- */

/*
 * ngx_dubbo_hessian2_encode_payload_map() copies every request value into a
 * std::string, puts that into a Map and serializes the Map, so the buffer the
 * encoder walks is a heap block of exactly the value's length. An over-read
 * there copies neighbouring heap bytes into the request that goes to the
 * backend. The value below is long enough to rule out a string held inside
 * its own object.
 */
static void
test_map_value_with_cut_tail(void)
{
    std::string  key_name("uri");
    std::string  value(24, 'a');

    value.push_back('\xe0');

    Map          map;
    ObjectValue  key(key_name);
    ObjectValue  val(value);

    map.put(key, val);

    std::string      out;
    hessian2_output  hout(&out);

    hout.write_object(&map);

    /* 'H', the key, the value with its cut char dropped, 'Z' */
    std::string  expect("H" "\x03" "uri" "\x18");
    expect.append(24, 'a');
    expect.push_back('Z');

    CHECK(out == expect, "the map value holds no byte past the string");

    try {
        hessian2_input  hin(out.data(), (uint32_t) out.size());

        std::pair<Object*, bool>  ret = hin.read_object();

        CHECK(instance_of<Map>(ret.first), "the map decodes");

        if (instance_of<Map>(ret.first)) {
            Object  *v = ((Map *) ret.first)->get("uri");

            CHECK(v != NULL && v->to_string() == std::string(24, 'a'),
                  "decoded value is the complete part of the input");
        }

        if (ret.second) {
            delete ret.first;
        }

    } catch (io_exception &e) {
        CHECK(false, e.what());
    }
}

/* --------------------------------------------------------------------- */

#define RUN(t)  failed += run(#t, t)

int
main(void)
{
    int  failed = 0;

    RUN(test_report_reproducer);
    RUN(test_two_byte_lead_last);
    RUN(test_three_byte_cut);
    RUN(test_four_byte_cut);
    RUN(test_only_incomplete);

    RUN(test_well_formed_roundtrip);
    RUN(test_four_byte_char_encoded);
    RUN(test_null_and_empty);

    RUN(test_chunk_exact_boundary);
    RUN(test_chunk_with_remainder);
    RUN(test_chunk_truncated_tail);
    RUN(test_multibyte_on_chunk_boundary);

    RUN(test_map_value_with_cut_tail);

    printf("%d case(s) failed\n", failed);

    return failed ? 1 : 0;
}
