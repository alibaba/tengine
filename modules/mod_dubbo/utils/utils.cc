#ifndef __STDC_FORMAT_MACROS
#define __STDC_FORMAT_MACROS
#endif

#include "utils.h"
#include <string>
#include <sstream>
#include <ostream>
#include <inttypes.h>

namespace hessian {

using namespace std;

int ngx_hessian_is_big_endian() {
    const int n = 1;
    if(*(char *)&n) {
        return 0;
    }
    return 1;
}

union double_int64 {
    double  dval;
    int64_t lval;
};

int64_t double_to_long(double dval) {
    // *(int64_t*)(&d_val)
    union double_int64 x;
    x.dval = dval;
    return x.lval;
}

double long_to_double(int64_t lval) {
    // *(double*)(&lval)
    union double_int64 x;
    x.lval = lval;
    return x.dval;
}

string bool_to_string(bool bval) {
    return bval ? string("true") : string("false");
}

string int32_to_string(int32_t ival) {
    char buff[32];
    return string(buff, snprintf(buff, sizeof(buff), "%" PRId32, ival));
}

string int64_to_string(int64_t lval) {
    char buff[32];
    return string(buff, snprintf(buff, sizeof(buff), "%" PRId64, lval));
}

string double_to_string(double dval) {
    char buff[32];
    return string(buff, snprintf(buff, sizeof(buff), "%f", dval));
}

int32_t cstr_to_int32(const char* cstr) {
    return strtol(cstr, NULL, 0);
}

int64_t cstr_to_int64(const char* cstr) {
#if __WORDSIZE == 64
    return strtol(cstr, NULL, 0);
#else
    return strtoll(cstr, NULL, 0);
#endif
}

double cstr_to_double(const char* cstr) {
    return strtod(cstr, NULL);
}

string to_hex_string(const void* ch, size_t size) {
    static char alpha[] = "0123456789ABCDEF";
    string hex_str;
    hex_str.reserve(size * 3);
    for (size_t i = 0; i < size; ++i) {
        uint8_t c = *((const uint8_t*)ch + i);
        hex_str.push_back(alpha[c >> 4]);
        hex_str.push_back(alpha[c & 0xF]);
        hex_str.push_back(' ');
    }

    return hex_str;
}

void write_hex_to_stream(ostream& os, const void* ch, size_t size) {
    static char alpha[] = "0123456789ABCDEF";
    for (size_t i = 0; i < size; ++i) {
        uint8_t c = *((const uint8_t*)ch + i);
        os << alpha[c >> 4] << alpha[c & 0xF] << ' ';
    }
}

/**
 * debug function 
 * @param caption title, not output when NULL
 * @param ptr start pos need output
 * @param len len nedd output
 */
void hexdump(const char* caption, const void* ptr, unsigned int len) {
    unsigned char* buf = (unsigned char*) ptr;
    unsigned int i, j;
    if (caption)
        printf("\n%s (%p@%d)\n", caption, ptr, len);
    for (i=0; i < len; i+=16) {
        printf("%08x  ", i);
        for (j=0; j<8; j++)
            if (i+j < len)
                printf("%02x ", buf[i+j]);
            else
                printf("   ");
        printf(" ");
        for (; j<16; j++)
            if (i+j < len)
                printf("%02x ", buf[i+j]);
            else
                printf("   ");
        printf(" |");
        for (j=0; j<16; j++)
            if (i+j < len)
                printf("%c", isprint(buf[i+j]) ? buf[i+j] : '.');
        printf("|\n");
    }
    printf("%08x\n", len);
}
}

