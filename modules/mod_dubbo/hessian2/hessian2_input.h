#ifndef _HESSIAN2_INPUT_H_
#define _HESSIAN2_INPUT_H_

#include "exceptions.h"
#include "utils.h"
#include <stdint.h>
#include <string>
#include <vector>

namespace hessian {

class Object;

/**
 * Hessian2 deserializater
 * Decode hessian from input data
 */
class hessian2_input {
    public:
        hessian2_input(const std::string* data);
        hessian2_input(const char* data, uint32_t size);
        ~hessian2_input() {}

        bool eof() const { return _curr >= _end; }

        //Clear refs, but not clear data
        void clear() { _refs_list.clear(); }

        // ---------------------------------------------------------

        void read_null();

        bool read_bool();

        int32_t read_int32();
        int64_t read_int64();

        double read_double();

        int64_t read_utc_date();

        std::string* read_utf8_string(std::string* dest = NULL);
        std::string* read_chunked_utf8_string(std::string* dest = NULL);
        std::string* read_string();

        std::string* read_bytes();
        std::string* read_chunked_bytes(std::string* dest = NULL);

        uint32_t read_length();
        std::string read_type();

        Object* read_list(const std::string& classname = "");
        Object* read_map(const std::string& classname = "");

        // Need do delete when the second param return is true !
        std::pair<Object*, bool> read_object();
        std::pair<Object*, bool> read_object(const std::string& classname);

        int32_t add_ref(Object* object = NULL);
        Object* read_ref();
        Object* get_ref_object(uint32_t ref_id);

        /* --------------------------------------------------------- *
         * Low level functions
         * --------------------------------------------------------- */
        uint32_t current_position() const { return _curr - _begin; }
        const char* current_ptr() const { return _curr; }
        void seek(uint32_t offset) { _curr += offset; }

        uint8_t peek();
        uint8_t parse_8bit();
        uint16_t parse_16bit();
        uint32_t parse_32bit();
        uint64_t parse_64bit();

        double parse_double();

        void parse_raw_bytes(uint32_t byte_size, std::string* dest);

        void parse_utf8_string(uint32_t char_size, std::string* dest);

        void skip_object();

    private:
        io_exception expect(const std::string& expect, int ch);
        io_exception error(const std::string& expect);

    private:
        const char* _begin;
        const char* _curr;
        const char* _end;

        std::vector<Object*> _refs_list;
};

inline uint8_t hessian2_input::peek() {
    if (_curr >= _end) {
        throw io_exception("hessian2_input::peek(): will reach EOF");
    }
    return *_curr;
}

inline uint8_t hessian2_input::parse_8bit() {
    if (_curr >= _end) {
        throw io_exception("hessian2_input::read_8bit(): will reach EOF");
    }
    return *_curr++;
}

inline uint16_t hessian2_input::parse_16bit() {
    if (_curr + 1 >= _end) {
        throw io_exception("hessian2_input::read_16bit(): will reach EOF");
    }
    uint16_t ret = ntohs(*((uint16_t *)(_curr)));
    _curr += 2;
    return ret;
}

inline uint32_t hessian2_input::parse_32bit() {
    if (_curr + 3 >= _end) {
        throw io_exception("hessian2_input::read_32bit(): will reach EOF");
    }
    uint32_t ret = ntohl(*((uint32_t *)(_curr)));
    _curr += 4;
    return ret;
}

inline uint64_t hessian2_input::parse_64bit() {
    if (_curr + 7 >= _end) {
        throw io_exception("hessian2_input::read_64bit(): will reach EOF");
    }
    uint64_t ret = ngx_hessian_ntoh64(*((uint64_t *)(_curr)));
    _curr += 8;
    return ret;
}

inline void hessian2_input::parse_raw_bytes(uint32_t byte_size, std::string* dest) {
    if (_curr + byte_size - 1 >= _end) {
        throw io_exception("hessian2_input::read_raw_bytes(): will reach EOF");
    }
    dest->append(_curr, byte_size);
    _curr += byte_size;
}

}

#endif
