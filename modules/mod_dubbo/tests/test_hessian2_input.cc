/*
 * Copyright (C) 2026 Alibaba Group Holding Limited
 */

/*
 * Stand-alone unit tests for the hessian2 string decoder:
 * hessian2_input::parse_utf8_string() and the readers built on it.
 *
 * The test links the very sources the module ships, with a stub
 * ngx_config.h, so no nginx build is needed (see the Makefile next to this
 * file).
 *
 * Every case runs in a forked child: several regressions covered here end in
 * an invalid free() or a sanitizer abort rather than in a failed check, and a
 * crashing case must not hide the outcome of the others. Children leave with
 * _exit(), so LeakSanitizer, which checks at exit, does not judge the cases:
 * the codec still leaks partially decoded objects on some malformed input,
 * which is a separate matter from what is tested here.
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
 * Bytes placed right after the input handed to the decoder. They are valid
 * UTF-8 continuation bytes, so a decoder that reads past the end does not
 * trip over them: it returns them as part of the string, which the checks
 * below catch even without a sanitizer.
 */
static const char  trailer[] = { '\x80', '\x80', '\x80' };

struct outcome {
    bool          thrown;
    std::string   what;
    std::string   value;
};

/*
 * Runs read_utf8_string() over data[0 .. len). With exact set the input sits
 * in a heap block of exactly len bytes, so a sanitizer reports any read past
 * it; otherwise it is followed by the trailer above.
 */
static outcome
decode_string(const char *data, size_t len, bool exact)
{
    char         *buf;
    outcome       o;
    std::string  *s;

    buf = new char[len + sizeof(trailer)];
    memcpy(buf, data, len);

    if (exact) {
        delete[] buf;
        buf = new char[len];
        memcpy(buf, data, len);

    } else {
        memcpy(buf + len, trailer, sizeof(trailer));
    }

    o.thrown = false;

    try {
        hessian2_input  hin(buf, (uint32_t) len);

        s = hin.read_utf8_string();
        if (s != NULL) {
            o.value = *s;
            delete s;
        }

    } catch (io_exception &e) {
        o.thrown = true;
        o.what = e.what();
    }

    delete[] buf;

    return o;
}

static bool
truncated(const outcome &o)
{
    return o.thrown && o.what.find("truncated utf-8") != std::string::npos;
}

/* reads one object and frees it, reporting whether io_exception was thrown */
static bool
read_object_throws(const char *data, size_t len, std::string *what)
{
    std::pair<Object*, bool>  ret;

    try {
        hessian2_input  hin(data, (uint32_t) len);

        ret = hin.read_object();
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

/* --- well-formed input ----------------------------------------------- */

static void
test_one_two_three_byte_chars(void)
{
    /* 'A', U+00E9, U+4E2D: the last char ends exactly at the input end */
    outcome  o = decode_string(LIT("\x03" "A" "\xc3\xa9" "\xe4\xb8\xad"),
                               true);

    CHECK(!o.thrown, "a well-formed string must decode");
    CHECK(o.value == "A\xc3\xa9\xe4\xb8\xad", "decoded bytes");
}

static void
test_empty_string(void)
{
    outcome  o = decode_string(LIT("\x00"), true);

    CHECK(!o.thrown, "an empty string at the input end must decode");
    CHECK(o.value.empty(), "decoded bytes");
}

static void
test_long_forms(void)
{
    outcome  o;

    /* 'S': 16-bit char count */
    o = decode_string(LIT("S\x00\x02" "\xc3\xa9" "\xe4\xb8\xad"), true);
    CHECK(!o.thrown, "'S' string must decode");
    CHECK(o.value == "\xc3\xa9\xe4\xb8\xad", "'S' decoded bytes");

    /* 0x30-0x33: 10-bit char count */
    o = decode_string(LIT("\x30\x02" "\xc3\xa9" "Z"), true);
    CHECK(!o.thrown, "0x30 string must decode");
    CHECK(o.value == "\xc3\xa9Z", "0x30 decoded bytes");
}

static void
test_chunked(void)
{
    /* a non-final 'R' chunk followed by the final compact chunk */
    outcome  o = decode_string(LIT("R\x00\x01" "A" "\x01" "\xe4\xb8\xad"),
                               true);

    CHECK(!o.thrown, "a chunked string must decode");
    CHECK(o.value == "A\xe4\xb8\xad", "decoded bytes");
}

static void
test_char_count_beyond_input(void)
{
    /* three chars announced, one byte present: the up-front check fires */
    outcome  o = decode_string(LIT("\x03" "A"), false);

    CHECK(o.thrown, "a char count larger than the input must be rejected");
    CHECK(o.what.find("will reach EOF") != std::string::npos,
          "rejected by the up-front length check");
}

/* --- multi-byte sequences cut by the input end ----------------------- */

static void
test_report_reproducer(void)
{
    /*
     * The reproducer from the report: 4 chars announced over 4 bytes, so the
     * up-front check passes, but the first char takes 3 of them and the
     * second is a 3-byte lead with nothing after it.
     */
    static const char  in[] = { 0x04, '\xe0', '\x80', '\x80', '\xe0' };

    outcome  o = decode_string(in, sizeof(in), true);

    CHECK(truncated(o), "a 3-byte lead at the input end must be rejected");
}

static void
test_three_byte_lead_last(void)
{
    /* the cut char is the last one, so nothing else would stop the read */
    outcome  o = decode_string(LIT("\x02" "\xe0\x80\x80" "\xe0"), false);

    CHECK(truncated(o), "a 3-byte lead at the input end must be rejected");
    CHECK(o.value.find('\x80', 3) == std::string::npos,
          "no byte past the input end may be returned");
}

static void
test_three_byte_one_continuation(void)
{
    outcome  o = decode_string(LIT("\x01" "\xe4\xb8"), false);

    CHECK(truncated(o), "a 3-byte char missing its last byte must be rejected");
}

static void
test_two_byte_lead_last(void)
{
    outcome  o = decode_string(LIT("\x01" "\xc3"), false);

    CHECK(truncated(o), "a 2-byte lead at the input end must be rejected");
}

static void
test_report_reproducer_read_object(void)
{
    /*
     * The exact reproducer from the report, through read_object(): len=1
     * announcing one char, a 2-byte lead present. The input sits in a heap
     * block of exactly its size, so a continuation-byte read past the end
     * leaves the allocation.
     */
    static const char  in[] = { 0x01, '\xc3' };

    char               *buf;
    bool                thrown;
    std::string         what;

    buf = new char[sizeof(in)];
    memcpy(buf, in, sizeof(in));

    thrown = false;

    try {
        hessian2_input  hin(buf, (uint32_t) sizeof(in));

        std::pair<Object*, bool>  ret = hin.read_object();
        if (ret.second) {
            delete ret.first;
        }

    } catch (io_exception &e) {
        thrown = true;
        what = e.what();
    }

    delete[] buf;

    CHECK(thrown, "read_object() must reject the cut string");
    CHECK(what.find("truncated utf-8") != std::string::npos,
          "rejected where the char is cut");
}

static void
test_truncated_long_forms(void)
{
    outcome  o;

    o = decode_string(LIT("S\x00\x01" "\xe4"), false);
    CHECK(truncated(o), "'S' string cut inside a char must be rejected");

    o = decode_string(LIT("\x30\x01" "\xc3"), false);
    CHECK(truncated(o), "0x30 string cut inside a char must be rejected");
}

static void
test_truncated_chunk(void)
{
    outcome  o;

    /* final chunk cut */
    o = decode_string(LIT("R\x00\x01" "A" "\x01" "\xc3"), false);
    CHECK(truncated(o), "final chunk cut inside a char must be rejected");

    /* non-final chunk cut */
    o = decode_string(LIT("R\x00\x01" "\xe4\xb8"), false);
    CHECK(truncated(o), "'R' chunk cut inside a char must be rejected");
}

static void
test_truncated_map_value(void)
{
    /*
     * The shape ngx_dubbo_hessian2_decode_payload_map() reads from the
     * backend: an int, then a map whose last value is cut inside a char.
     */
    static const char  in[] = "I\x00\x00\x00\x01" "H"
                              "\x04" "body" "\x02" "A" "\xe4";

    char               buf[sizeof(in) - 1 + sizeof(trailer)];
    bool               thrown;
    std::string        what;

    memcpy(buf, in, sizeof(in) - 1);
    memcpy(buf + sizeof(in) - 1, trailer, sizeof(trailer));

    thrown = false;

    try {
        hessian2_input  hin(buf, sizeof(in) - 1);

        hin.read_int32();

        std::pair<Object*, bool>  ret = hin.read_object();
        if (ret.second) {
            delete ret.first;
        }

    } catch (io_exception &e) {
        thrown = true;
        what = e.what();
    }

    CHECK(thrown, "a map with a cut value must be rejected");
    CHECK(what.find("truncated utf-8") != std::string::npos,
          "rejected where the value is cut, not past the input end");
}

static void
test_map_value_decodes(void)
{
    static const char  in[] = "I\x00\x00\x00\x01" "H"
                              "\x04" "body" "\x01" "\xe4\xb8\xad"
                              "\x06" "status" "\x03" "200" "Z";

    Map               *map;
    Object            *body;

    hessian2_input  hin(in, sizeof(in) - 1);

    CHECK(hin.read_int32() == 1, "attachment flag");

    std::pair<Object*, bool>  ret = hin.read_object();
    map = (Map *) ret.first;

    CHECK(map != NULL, "map decoded");
    if (map == NULL) {
        return;
    }

    body = map->get("body");
    CHECK(body != NULL && body->to_string() == "\xe4\xb8\xad", "body value");
    CHECK(hin.eof(), "whole input consumed");

    if (ret.second) {
        delete ret.first;
    }
}

/* --- caller-owned destination strings -------------------------------- */

/*
 * read_utf8_string() and read_chunked_utf8_string() may be handed a string
 * owned by the caller; a failed read must leave it alone rather than free it.
 * exception_deserialize() passes strings on its stack and inside the
 * Exception object it is building.
 */

static void
test_caller_dest_survives_short_input(void)
{
    std::string  key("kept");
    bool         thrown = false;

    hessian2_input  hin(LIT("S\x00\x05" "a"));

    try {
        hin.read_utf8_string(&key);
    } catch (io_exception &) {
        thrown = true;
    }

    CHECK(thrown, "a short string must be rejected");
    CHECK(key.compare(0, 4, "kept") == 0, "caller's string left intact");
}

static void
test_caller_dest_survives_truncated_char(void)
{
    std::string  key("kept");
    bool         thrown = false;

    hessian2_input  hin(LIT("S\x00\x02" "a" "\xe4"));

    try {
        hin.read_utf8_string(&key);
    } catch (io_exception &) {
        thrown = true;
    }

    CHECK(thrown, "a cut char must be rejected");
    CHECK(key.compare(0, 4, "kept") == 0, "caller's string left intact");
}

static void
test_caller_dest_survives_bad_tag(void)
{
    std::string  key("kept");
    bool         thrown = false;

    hessian2_input  hin(LIT("s\x00\x01" "a"));

    try {
        hin.read_utf8_string(&key);
    } catch (io_exception &) {
        thrown = true;
    }

    CHECK(thrown, "a non-string tag must be rejected");
    CHECK(key == "kept", "caller's string left intact");
}

static void
test_chunked_caller_dest_survives(void)
{
    std::string  msg("kept");
    bool         thrown = false;

    hessian2_input  hin(LIT("S\x00\x02" "a" "\xe4"));

    try {
        hin.read_chunked_utf8_string(&msg);
    } catch (io_exception &) {
        thrown = true;
    }

    CHECK(thrown, "a cut char must be rejected");
    CHECK(msg.compare(0, 4, "kept") == 0, "caller's string left intact");
}

static void
test_exception_object_bad_key(void)
{
    /* a typed map whose class name selects the Exception deserializer */
    std::string  what;

    CHECK(read_object_throws(LIT("M" "\x13" "java.lang.Exception"
                                 "S\x00\x05" "a"), &what),
          "an Exception with a short key must be rejected");

    CHECK(read_object_throws(LIT("M" "\x13" "java.lang.Exception"
                                 "S\x00\x02" "a" "\xe4"), &what),
          "an Exception with a cut key must be rejected");
    CHECK(what.find("truncated utf-8") != std::string::npos,
          "rejected where the key is cut");
}

static void
test_exception_object_bad_detail_message(void)
{
    CHECK(read_object_throws(LIT("M" "\x13" "java.lang.Exception"
                                 "S\x00\x0d" "detailMessage"
                                 "S\x00\x05" "a"), NULL),
          "an Exception with a short detailMessage must be rejected");

    CHECK(read_object_throws(LIT("M" "\x13" "java.lang.Exception"
                                 "S\x00\x0d" "detailMessage"
                                 "S\x00\x02" "a" "\xe4"), NULL),
          "an Exception with a cut detailMessage must be rejected");
}

static void
test_exception_object_decodes(void)
{
    std::pair<Object*, bool>  ret;

    hessian2_input  hin(LIT("M" "\x13" "java.lang.Exception"
                            "S\x00\x0d" "detailMessage"
                            "S\x00\x02" "o" "\xc3\xa9"
                            "z"));

    ret = hin.read_object();

    CHECK(ret.first != NULL, "Exception decoded");
    if (ret.first == NULL) {
        return;
    }

    CHECK(((Exception *) ret.first)->detail_message() == "o\xc3\xa9",
          "detailMessage value");
    CHECK(hin.eof(), "whole input consumed");

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

    RUN(test_one_two_three_byte_chars);
    RUN(test_empty_string);
    RUN(test_long_forms);
    RUN(test_chunked);
    RUN(test_char_count_beyond_input);

    RUN(test_report_reproducer);
    RUN(test_three_byte_lead_last);
    RUN(test_three_byte_one_continuation);
    RUN(test_two_byte_lead_last);
    RUN(test_report_reproducer_read_object);
    RUN(test_truncated_long_forms);
    RUN(test_truncated_chunk);
    RUN(test_truncated_map_value);
    RUN(test_map_value_decodes);

    RUN(test_caller_dest_survives_short_input);
    RUN(test_caller_dest_survives_truncated_char);
    RUN(test_caller_dest_survives_bad_tag);
    RUN(test_chunked_caller_dest_survives);
    RUN(test_exception_object_bad_key);
    RUN(test_exception_object_bad_detail_message);
    RUN(test_exception_object_decodes);

    printf("%d case(s) failed\n", failed);

    return failed ? 1 : 0;
}
