/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for the hessian2 binary encoder,
 * hessian2_output::write_bytes(), and for the decoder path that feeds it.
 *
 * Background -- report #2118 claimed write_bytes() reads out of bounds
 * because it trusts its byte_size argument. Unlike write_utf8_string()
 * (report #2117), write_bytes() does not scan the buffer for multi-byte
 * characters: it copies exactly byte_size bytes, in 0x8000-sized chunks.
 * It can therefore over-read only if a caller hands it a byte_size larger
 * than the buffer, and the single caller in the module,
 * bytearray_serialize_hessian2(), passes a std::string's (c_str(), size()),
 * which is always self-consistent. Untrusted input cannot break that either:
 * a binary whose announced length exceeds the bytes present is rejected by
 * hessian2_input::parse_raw_bytes() before any ByteArray -- and so any
 * write_bytes() call -- is built.
 *
 * These tests lock that in:
 *   - every buffer handed to write_bytes() sits in a heap block of exactly
 *     byte_size bytes, so a sanitizer reports any read past it; the encoder
 *     must stay clean at every chunk boundary and emit exactly byte_size
 *     payload bytes, which then decode back to the original;
 *   - the caller path (a ByteArray serialized through write_object()) is
 *     exercised the same way;
 *   - a binary read from an untrusted payload whose announced length exceeds
 *     the bytes present must be rejected by the decoder, for every binary tag
 *     form, before a ByteArray is produced.
 *
 * Every case runs in a forked child: an over-read aborts under a sanitizer
 * rather than failing a check, and a crashing case must not hide the outcome
 * of the others. Children leave with _exit(), so LeakSanitizer does not judge
 * the cases.
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

/* a repeating, non-UTF-8 payload of exactly n bytes */
static std::string
pattern(uint32_t n)
{
    std::string  s(n, '\0');

    for (uint32_t i = 0; i < n; i++) {
        /* include high bytes: binary data is not restricted to UTF-8 */
        s[i] = (char) (0x01 + (i % 0xFF));
    }

    return s;
}

/*
 * Encodes data[0 .. len) with write_bytes() from a heap block of exactly len
 * bytes: a read past the announced size then leaves the allocation, which a
 * sanitizer reports. Returns the encoded bytes.
 */
static std::string
encode_bytes_exact(const char *data, size_t len)
{
    char          *buf = new char[len];
    std::string    out;

    memcpy(buf, data, len);

    hessian2_output  hout(&out);
    hout.write_bytes(buf, (uint32_t) len);

    delete[] buf;

    return out;
}

/* decodes one value with the shipped codec; false if the decoder rejects it */
static bool
decode_bytes(const std::string &enc, std::string *value)
{
    try {
        hessian2_input  hin(enc.data(), (uint32_t) enc.size());

        std::pair<Object *, bool>  ret = hin.read_object();

        if (ret.first == NULL) {
            return false;
        }

        *value = ret.first->to_string();

        if (ret.second) {
            delete ret.first;
        }

        return hin.eof();

    } catch (io_exception &) {
        return false;
    }
}

/* reports whether decoding data[0 .. len) throws io_exception */
static bool
decode_throws(const char *data, size_t len)
{
    try {
        hessian2_input  hin(data, (uint32_t) len);

        std::pair<Object *, bool>  ret = hin.read_object();
        if (ret.second) {
            delete ret.first;
        }

    } catch (io_exception &) {
        return true;
    }

    return false;
}

/* --- write_bytes() copies exactly byte_size, at every boundary -------- */

static void
test_exact_copy_boundaries(void)
{
    static const uint32_t  sizes[] = {
        1, 15, 16, 1023, 1024, 0x8000 - 1, 0x8000, 0x8000 + 1, 2 * 0x8000
    };

    for (unsigned k = 0; k < sizeof(sizes) / sizeof(sizes[0]); k++) {
        uint32_t      n = sizes[k];
        std::string   in = pattern(n);

        /* the input lives in a block of exactly n bytes: no over-read */
        std::string   enc = encode_bytes_exact(in.data(), in.size());

        std::string   value;
        bool          ok = decode_bytes(enc, &value);

        CHECK(ok, "encoded binary decodes");
        CHECK(value == in, "round trip preserves every byte, none added");
        CHECK(value.size() == n, "payload length equals the announced size");
    }
}

/* the length tag of each encoding form, and the chunking above 0x8000 */
static void
test_encoding_shape(void)
{
    std::string  in, enc;

    /* short form: [0x20-0x2f] <data>, length 0-15 */
    in = pattern(5);
    enc = encode_bytes_exact(in.data(), in.size());
    CHECK(enc.size() == 1 + 5 && (unsigned char) enc[0] == 0x20 + 5,
          "short form: one tag byte 0x20+n, then n bytes");
    CHECK(enc.compare(1, 5, in) == 0, "short form payload");

    /* medium form: [0x34-0x37] b0 <data>, length 0-1023 */
    in = pattern(300);
    enc = encode_bytes_exact(in.data(), in.size());
    CHECK(enc.size() == 2 + 300
          && (unsigned char) enc[0] == 0x34 + (300 >> 8)
          && (unsigned char) enc[1] == (300 & 0xff),
          "medium form: 0x34+(n>>8), n&0xff, then n bytes");
    CHECK(enc.compare(2, 300, in) == 0, "medium form payload");

    /* long form: 'B' b1 b0 <data> */
    in = pattern(2000);
    enc = encode_bytes_exact(in.data(), in.size());
    CHECK(enc.size() == 3 + 2000
          && enc[0] == 'B'
          && (unsigned char) enc[1] == (2000 >> 8)
          && (unsigned char) enc[2] == (2000 & 0xff),
          "long form: 'B', 16-bit length, then n bytes");
    CHECK(enc.compare(3, 2000, in) == 0, "long form payload");

    /* chunked: one non-final 'A' chunk of 0x8000, then the remainder */
    in = pattern(0x8000 + 3);
    enc = encode_bytes_exact(in.data(), in.size());
    CHECK(enc[0] == 'A'
          && (unsigned char) enc[1] == 0x80
          && (unsigned char) enc[2] == 0x00,
          "chunked form: 'A' 0x80 0x00 header");
    CHECK(enc.compare(3, 0x8000, in, 0, 0x8000) == 0, "first full chunk");
    CHECK((unsigned char) enc[3 + 0x8000] == 0x20 + 3,
          "remainder uses the short form");
    CHECK(enc.compare(3 + 0x8000 + 1, 3, in, 0x8000, 3) == 0,
          "remainder payload");
    CHECK(enc.size() == 3 + 0x8000 + 1 + 3, "no byte beyond the buffer");

    /* exactly 0x8000 is not chunked: a single long-form value */
    in = pattern(0x8000);
    enc = encode_bytes_exact(in.data(), in.size());
    CHECK(enc[0] == 'B', "exactly one chunk stays a single long-form value");
    CHECK(enc.size() == 3 + 0x8000, "exactly-one-chunk size");
}

static void
test_null_and_empty(void)
{
    std::string    out;
    hessian2_output  hout(&out);

    hout.write_bytes(NULL, 0);
    CHECK(out == "N", "a null buffer encodes as null");

    out.clear();
    hout.write_bytes("A", 0);
    CHECK(out == "N", "a zero length encodes as null");
}

/* --- the real caller path: a ByteArray serialized through write_object -- */

static void
test_bytearray_caller_path(void)
{
    static const uint32_t  sizes[] = { 1, 20, 1024, 0x8000 + 7 };

    for (unsigned k = 0; k < sizeof(sizes) / sizeof(sizes[0]); k++) {
        std::string   in = pattern(sizes[k]);

        /*
         * The module builds a ByteArray from a (pointer, length) pair, which
         * copies into a std::string; bytearray_serialize_hessian2() then
         * passes that string's (c_str(), size()) to write_bytes(). The two
         * are always consistent, so the encoder can never over-read here.
         */
        ByteArray     ba(in.data(), (uint32_t) in.size());
        std::string   enc;

        CHECK(ba.data().size() == in.size(), "ByteArray keeps the exact size");

        hessian2_output  hout(&enc);
        hout.write_object(&ba);

        std::string   value;
        CHECK(decode_bytes(enc, &value) && value == in,
              "ByteArray round trips through write_object()");
    }
}

/* --- the real defence: the decoder rejects an oversized binary --------- */

static void
test_oversized_binary_rejected(void)
{
    /*
     * Each payload announces more binary bytes than it carries. This is what
     * a malicious dubbo backend would send to reach the reported over-read.
     * parse_raw_bytes() bounds-checks the announced length against the bytes
     * left in the payload and throws, so no ByteArray -- and no write_bytes()
     * call with a length larger than its buffer -- is ever produced.
     */

    /* 'B' announcing 32 bytes, carrying 1 */
    static const char  long_form[] = { 'B', 0x00, 0x20, 'A' };
    CHECK(decode_throws(LIT(long_form)),
          "long-form binary longer than the payload is rejected");

    /* 'B' announcing 3 bytes, carrying 2 */
    static const char  long_short[] = { 'B', 0x00, 0x03, 'A', 'B' };
    CHECK(decode_throws(LIT(long_short)),
          "long-form binary one byte short is rejected");

    /* non-final 'A' chunk announcing 32 bytes, carrying 1 */
    static const char  chunk_form[] = { 'A', 0x00, 0x20, 'A' };
    CHECK(decode_throws(LIT(chunk_form)),
          "chunked binary longer than the payload is rejected");

    /* compact form 0x2f announces 15 bytes, carrying none */
    static const char  compact[] = { 0x2f };
    CHECK(decode_throws(LIT(compact)),
          "compact binary with no payload is rejected");

    /* medium form 0x34 0x05 announces 5 bytes, carrying 2 */
    static const char  medium[] = { 0x34, 0x05, 'A', 'B' };
    CHECK(decode_throws(LIT(medium)),
          "medium-form binary longer than the payload is rejected");
}

static void
test_wellformed_binary_decodes(void)
{
    /* 'B' announcing exactly the 5 bytes present */
    static const char  in[] = { 'B', 0x00, 0x05, 'h', 'e', 'l', 'l', 'o' };

    std::string   value;
    std::string   enc(in, sizeof(in));

    CHECK(decode_bytes(enc, &value), "a well-formed binary decodes");
    CHECK(value == "hello", "decoded bytes match the payload");
}

/* --------------------------------------------------------------------- */

#define RUN(t)  failed += run(#t, t)

int
main(void)
{
    int  failed = 0;

    RUN(test_exact_copy_boundaries);
    RUN(test_encoding_shape);
    RUN(test_null_and_empty);
    RUN(test_bytearray_caller_path);
    RUN(test_oversized_binary_rejected);
    RUN(test_wellformed_binary_decodes);

    printf("%d case(s) failed\n", failed);

    return failed ? 1 : 0;
}
