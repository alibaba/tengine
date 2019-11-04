#ifndef DUBBO_UTILS_H
#define DUBBO_UTILS_H

#ifndef __STDC_LIMIT_MACROS
#define __STDC_LIMIT_MACROS
#endif

#include <stdint.h>
#include <vector>
#include <string>
#include "ngx_config.h"

namespace hessian {

int ngx_hessian_is_big_endian();

#define ngx_hessian_swap64(val) (((val) >> 56)   |\
        (((val) & 0x00ff000000000000ll) >> 40) |\
        (((val) & 0x0000ff0000000000ll) >> 24) |\
        (((val) & 0x000000ff00000000ll) >> 8)  |\
        (((val) & 0x00000000ff000000ll) << 8)  |\
        (((val) & 0x0000000000ff0000ll) << 24) |\
        (((val) & 0x000000000000ff00ll) << 40) |\
        (((val) << 56)))

#define ngx_hessian_hton64(val) ngx_hessian_is_big_endian() ? val : ngx_hessian_swap64(val)
#define ngx_hessian_ntoh64(val) ngx_hessian_hton64(val)

#define CONST_C_STRING(const_c_str) const_c_str, sizeof(const_c_str) - 1

int64_t double_to_long(double dval);
double long_to_double(int64_t lval);

inline bool string_ends_with(const std::string& target, const std::string& end) {
    int pos = target.size() - end.size();
    return pos >= 0 && ((int)target.rfind(end, pos)) == pos;
}

/*
 * string convert
 */
std::string bool_to_string(bool bval);
std::string int32_to_string(int32_t ival);
std::string int64_to_string(int64_t lval);
std::string double_to_string(double dval);

int32_t cstr_to_int32(const char* cstr);
inline int32_t string_to_int32(const std::string& str) { return cstr_to_int32(str.c_str()); };
int64_t cstr_to_int64(const char* cstr);
inline int64_t string_to_int64(const std::string& str) { return cstr_to_int64(str.c_str()); };
double cstr_to_double(const char* cstr);
inline double string_to_double(const std::string& str) { return cstr_to_double(str.c_str()); };

std::string to_hex_string(const void* ch, size_t size);
void write_hex_to_stream(std::ostream& os, const void* ch, size_t size);

/**
 * debug function, output hex
 * @param caption title, not output when NULL
 * @param ptr start pos when output
 * @param len len when output
 */
void hexdump(const char* caption, const void* ptr, unsigned int len);

template <class T>
class Safeguard {
    public:
        Safeguard(): m_pt(NULL) { }
        Safeguard(T* pt): m_pt(pt) { }
        ~Safeguard() { if (m_pt != NULL) delete m_pt; }

        void reset(T* pt) { m_pt = pt; }
        void release() { m_pt = NULL; }
    private:
        T* m_pt;
};

}

#endif
