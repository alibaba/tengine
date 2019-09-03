#ifndef __STDC_FORMAT_MACROS
#define __STDC_FORMAT_MACROS
#endif

#include "utils.h"
#include <cstdlib>
#include <cstdio>
#include <string>
#include <cstring>
#include <cstdlib>
#include <inttypes.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <langinfo.h>
#include <iconv.h>
#include <sstream>
#include <ostream>
#include <unistd.h>

namespace hessian {

using namespace std;

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

vector<string> parse_lines(const string& data) {
    vector<string> r;
    string data0(data);
    trim(data0);
    if (data0.empty()) {
        return r;
    }

    size_t bol = 0, eol, len = data0.length();
    do {
        eol = data0.find('\n', bol);
        if (eol == string::npos) {
            r.push_back(data0.substr(bol));
        } else {
            size_t eol2 = eol;
            if (eol2 > bol && data0[eol2 - 1] == '\r') {
                --eol2;
            }
            if (eol2 > bol) {
                r.push_back(data0.substr(bol, eol2 - bol));
            }
        }
        bol = eol + 1;
    } while (eol != string::npos && bol < len);
    return r;
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
    string hex_str;
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

string system_charset() {
    // locale charmap
    setlocale(LC_CTYPE, "");
    return string(nl_langinfo(CODESET));
}

/*
 * Thread local
 */
template <class T>
class ThreadLocal {
    public:
        ThreadLocal(void (*destructor)(void*))
            : _destructor(destructor) {
                pthread_key_create(&_key, destructor);
            }
        ~ThreadLocal() {
            clear();
            pthread_key_delete(_key);
        }
        T* get() {
            return (T*) pthread_getspecific(_key);
        }
        void clear() {
            T* data = (T*) pthread_getspecific(_key);
            if (data && _destructor) {
                _destructor(data);
            }
        }
        int set(T* data) {
            return pthread_setspecific(_key, data);
        }

    private:
        ThreadLocal(const ThreadLocal& other);
        ThreadLocal& operator=(const ThreadLocal& other);

    private:
        pthread_key_t  _key;
        void (*_destructor)(void*);
};

/* ============================================================================
 * convert charset
 * ========================================================================= */
string iconv_string(const string& input, void* iconv_t_ptr) {
    if (input.empty() || !iconv_t_ptr) {
        return input;
    }

    char*  inbuf = const_cast<char*>(input.data());
    size_t insize = input.size();
    size_t outsize = insize << 1;
    char*  outbuf = new char[outsize];

    char*  inptr = inbuf;
    size_t inremain = insize;
    char*  outptr = outbuf;
    size_t outremain = outsize;

    iconv(*(iconv_t*) iconv_t_ptr, &inptr, &inremain, &outptr, &outremain);

    string ret(outbuf, outsize - outremain);
    delete[] outbuf;
    return ret;
}

static void iconv_t_destructor(void* iconv_t_ptr) {
    iconv_close(*(iconv_t*)iconv_t_ptr);
    delete (iconv_t*)iconv_t_ptr;
}

static ThreadLocal<iconv_t> utf8_to_gbk_iconv(iconv_t_destructor);
static ThreadLocal<iconv_t> gbk_to_utf8_iconv(iconv_t_destructor);
static ThreadLocal<iconv_t> utf8_to_native_iconv(iconv_t_destructor);

string utf8_to_gbk(const string& input) {
    iconv_t* iconv_t_ptr = utf8_to_gbk_iconv.get();
    if (!iconv_t_ptr) {
        iconv_t cd;
        if ((iconv_t)(-1) == (cd = iconv_open("GB18030//TRANSLIT", "UTF-8"))) {
            return input;
        }
        iconv_t_ptr = new iconv_t(cd);
        utf8_to_gbk_iconv.set(iconv_t_ptr);
    }
    return iconv_string(input, iconv_t_ptr);
}

string gbk_to_utf8(const string& input) {
    iconv_t* iconv_t_ptr = gbk_to_utf8_iconv.get();
    if (!iconv_t_ptr) {
        iconv_t cd;
        if ((iconv_t)(-1) == (cd = iconv_open("UTF-8//TRANSLIT", "GB18030"))) {
            return input;
        }
        iconv_t_ptr = new iconv_t(cd);
        gbk_to_utf8_iconv.set(iconv_t_ptr);
    }
    return iconv_string(input, iconv_t_ptr);
}

string utf8_to_native(const string& input) {
    static bool bconv = (system_charset() != "UTF-8");
    static string sys_conv = (system_charset() + "//TRANSLIT");
    if (bconv) {
        iconv_t* iconv_t_ptr = utf8_to_native_iconv.get();
        if (!iconv_t_ptr) {
            iconv_t cd;
            if ((iconv_t)(-1) == (cd = iconv_open(sys_conv.c_str(), "UTF-8"))) {
                return input;
            }
            iconv_t_ptr = new iconv_t(cd);
            utf8_to_native_iconv.set(iconv_t_ptr);
        }
        return iconv_string(input, iconv_t_ptr);
    } else {
        return input;
    }
}

}

