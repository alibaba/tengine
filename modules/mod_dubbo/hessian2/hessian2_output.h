#ifndef _HESSIAN2_OUTPUT_H_
#define _HESSIAN2_OUTPUT_H_

#include "utils.h"
#include <stdint.h>
#include <string>
#include <map>

namespace hessian {

class Object;

class hessian2_output {
    public:
        hessian2_output(std::string* data) : _data(data), _ref_idx(0) {}
        ~hessian2_output() {}

        std::string* data() { return _data; }
        uint32_t size() const { return _data->size(); }

        void clear();

        // ---------------------------------------------------------

        void write_null();

        void write_bool(bool b);

        void write_int32(int32_t value);
        void write_int64(int64_t value);

        void write_double(double d_val);

        void write_utc_date(int64_t milli_epoch);

        void write_utf8_string(const char* str, uint32_t byte_size);
        void write_utf8_string(const std::string& str);

        void write_bytes(const char* bytes, uint32_t byte_size);

        void write_length(uint32_t length);
        void write_type(const std::string& type);

        void write_ref(int32_t ref_id);
        bool write_ref(const Object* object);
        void write_object(const Object* object);

        /* --------------------------------------------------------- *
         * Low level functions
         * --------------------------------------------------------- */
        int32_t add_ref() { return _ref_idx++; }

        void print_8bit(int8_t value) {
            _data->push_back((char) value);
        }
        void print_16bit(int16_t value) {
            _data->append((const char*)&(value = htons((uint16_t)value)), 2);
        }
        void print_32bit(int32_t value) {
            _data->append((const char*)&(value = htonl((uint32_t)value)), 4);
        }
        void print_64bit(int64_t value) {
            _data->append((const char*)&(value = ngx_hessian_hton64((uint64_t)value)), 8);
        }

        void fill_chars(uint32_t size, char c) {
            _data->append(size, c);
        }

        void print_raw_bytes(const char* bytes, uint32_t byte_size) {
            _data->append(bytes, byte_size);
        }

        void print_raw_len_bytes(const char* bytes, uint16_t byte_size) {
            print_16bit(byte_size);
            print_raw_bytes(bytes, byte_size);
        }

        uint32_t current_position() const { return _data->length(); }
        void print_8bit_at_position(uint32_t pos, char value);
        void print_16bit_at_position(uint32_t pos, int16_t value);
        void print_32bit_at_position(uint32_t pos, int32_t value);
        void print_64bit_at_position(uint32_t pos, int64_t value);

    private:
        std::string* _data;
        std::map<uintptr_t, int32_t> _refs_map;
        int32_t _ref_idx;
};

inline void hessian2_output::print_8bit_at_position(uint32_t pos, char value) {
    (*_data)[pos] = value;
}
inline void hessian2_output::print_16bit_at_position(uint32_t pos, int16_t value) {
    (*_data)[  pos] = (char) (value >> 8);
    (*_data)[++pos] = (char) value;
}
inline void hessian2_output::print_32bit_at_position(uint32_t pos, int32_t value) {
    (*_data)[  pos] = (char) (value >> 24);
    (*_data)[++pos] = (char) (value >> 16);
    (*_data)[++pos] = (char) (value >> 8);
    (*_data)[++pos] = (char) value;
}
inline void hessian2_output::print_64bit_at_position(uint32_t pos, int64_t value) {
    (*_data)[  pos] = (char) (value >> 56);
    (*_data)[++pos] = (char) (value >> 48);
    (*_data)[++pos] = (char) (value >> 40);
    (*_data)[++pos] = (char) (value >> 32);
    (*_data)[++pos] = (char) (value >> 24);
    (*_data)[++pos] = (char) (value >> 16);
    (*_data)[++pos] = (char) (value >> 8);
    (*_data)[++pos] = (char) value;
}

}

#endif
